import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import type { MemberLookup } from "../src/auth";
import { QUERYABLE_FUNCTIONS } from "../src/config";
import * as index from "../src/index";
import { logError, type LogEntry } from "../src/logging";
import {
  BASE_CLAUSE,
  FILTERED_FIELDS,
  TEXT_MAX_CHARS,
  buildFilter,
  handleQueryLogsCall,
  toEntry,
  readLogsQuery,
  type FetchLike,
  type LogsDeps,
  type TokenCache,
} from "../src/logs/queryLogs";

const NOW = new Date("2026-11-14T12:00:00.000Z");
const TOKEN = "ya29.jeton-secret-de-test-0123456789";
const ENV = { GCLOUD_PROJECT: "kassbeer" };

const members: Record<string, Record<string, unknown>> = {
  "admin@example.com": { role: "admin" },
  "brasseur@example.com": { role: "brewer" },
  "nonverifie@example.com": { role: "admin" },
  "motdepasse@example.com": { role: "admin" },
};
const lookup: MemberLookup = async (key) => members[key] ?? null;

const google = (email: string, extra: Record<string, unknown> = {}) => ({
  uid: "u",
  token: { email, email_verified: true, firebase: { sign_in_provider: "google.com" }, ...extra },
});
const admin = google("admin@example.com");

interface Call {
  url: string;
  init: RequestInit;
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** `fetch` simulé : serveur de métadonnées, puis `entries:list` rendu par `logging`. */
function fakeFetch(logging: () => Promise<Response> | Response, calls: Call[]): FetchLike {
  return async (url, init) => {
    calls.push({ url, init });
    if (url.startsWith("http://metadata.google.internal/")) {
      return jsonResponse(200, { access_token: TOKEN, expires_in: 3599, token_type: "Bearer" });
    }
    return logging();
  };
}

function deps(
  logging: () => Promise<Response> | Response,
  calls: Call[] = [],
  logs: LogEntry[] = [],
  extra: Partial<LogsDeps> = {},
): LogsDeps {
  return {
    lookup,
    fetchImpl: fakeFetch(logging, calls),
    now: () => NOW,
    env: ENV,
    tokenCache: { value: null, expiresAt: 0 },
    log: (e) => logs.push(e),
    ...extra,
  };
}

const loggingCalls = (calls: Call[]) => calls.filter((c) => c.url.includes("logging.googleapis"));
const sentBody = (call: Call) => JSON.parse(String(call.init.body)) as Record<string, unknown>;

async function rejectsWith(p: Promise<unknown>, code: string, reason?: string, field?: string) {
  await assert.rejects(p, (err: unknown) => {
    assert.ok(err instanceof HttpsError);
    assert.equal(err.code, code);
    const details = err.details as Record<string, unknown> | undefined;
    if (reason !== undefined) assert.equal(details?.reason, reason);
    if (field !== undefined) assert.equal(details?.field, field);
    return true;
  });
}

describe("queryLogs — garde (P30)", () => {
  const profiles: [string, ReturnType<typeof google> | null, string][] = [
    ["anonyme", null, "unauthenticated"],
    [
      "e-mail non vérifié",
      google("nonverifie@example.com", { email_verified: false }),
      "permission-denied",
    ],
    [
      "autre fournisseur",
      google("motdepasse@example.com", { firebase: { sign_in_provider: "password" } }),
      "permission-denied",
    ],
    ["non membre", google("inconnu@example.com"), "permission-denied"],
    ["brasseur", google("brasseur@example.com"), "permission-denied"],
  ];
  for (const [name, auth, code] of profiles) {
    it(`${name} : refusé avant la lecture des arguments, sans appel`, async () => {
      const calls: Call[] = [];
      let read = false;
      const data = {
        get severity() {
          read = true;
          return "INFO";
        },
      };
      const req = auth === null ? { data } : { auth, data };
      await rejectsWith(
        handleQueryLogsCall(
          req,
          deps(() => jsonResponse(200, {}), calls),
        ),
        code,
      );
      assert.equal(read, false);
      assert.equal(calls.length, 0);
    });
  }
  it("admin : accepté", async () => {
    const res = await handleQueryLogsCall(
      { auth: admin, data: {} },
      deps(() => jsonResponse(200, { entries: [] })),
    );
    assert.deepEqual(res.entries, []);
    assert.equal(res.nextPageToken, null);
    assert.deepEqual(res.functions, [...QUERYABLE_FUNCTIONS]);
  });
});

describe("queryLogs — arguments (P49)", () => {
  const refused: [string, Record<string, unknown>, string][] = [
    ["gravité hors liste", { severity: "CRITICAL" }, "severity"],
    ["gravité en minuscules", { severity: "error" }, "severity"],
    ["fonction hors liste", { functionName: "autreFonction" }, "functionName"],
    ["fonction en minuscules", { functionName: "querylogs" }, "functionName"],
    ["période hors liste", { periodMinutes: 30 }, "periodMinutes"],
    ["période en texte", { periodMinutes: "60" }, "periodMinutes"],
    ["ticket avec espace", { ticketId: "a b" }, "ticketId"],
    ["ticket avec guillemet", { ticketId: 'a"b' }, "ticketId"],
    ["ticket vide", { ticketId: "" }, "ticketId"],
    ["ticket de 129 caractères", { ticketId: "a".repeat(129) }, "ticketId"],
    ["ticket non texte", { ticketId: 12 }, "ticketId"],
    ["texte vide", { freeText: "" }, "freeText"],
    ["texte de 101 caractères", { freeText: "a".repeat(101) }, "freeText"],
    ["texte avec saut de ligne", { freeText: "a\nb" }, "freeText"],
    ["texte avec tabulation", { freeText: "a\tb" }, "freeText"],
    ["page de 2 001 caractères", { pageToken: "a".repeat(2001) }, "pageToken"],
    ["page sans date", { pageToken: "abc" }, "pageToken"],
    ["page sans période", { pageToken: "2026-11-14T11:00:00.000Z|abc" }, "pageToken"],
    ["page à période hors liste", { pageToken: "30|2026-11-14T11:40:00.000Z|abc" }, "pageToken"],
    ["page à date future", { pageToken: "60|2026-11-15T00:00:00.000Z|abc" }, "pageToken"],
    // 1 h + 5 min de marge : 10:55 au plus tôt pour 12:00.
    [
      "page plus ancienne que la période",
      { pageToken: "60|2026-11-14T10:54:59.000Z|abc" },
      "pageToken",
    ],
    [
      "page à 24 h pour une période d'1 h",
      { pageToken: "60|2026-11-13T12:00:00.000Z|abc" },
      "pageToken",
    ],
    [
      "période de l'argument contraire au jeton",
      { periodMinutes: 1440, pageToken: "60|2026-11-14T11:00:00.000Z|abc" },
      "pageToken",
    ],
    ["page sans jeton de l'API", { pageToken: "60|2026-11-14T11:00:00.000Z|" }, "pageToken"],
  ];
  for (const [name, data, field] of refused) {
    it(`${name} : invalid-argument, champ ${field}, sans appel`, async () => {
      const calls: Call[] = [];
      await rejectsWith(
        handleQueryLogsCall(
          { auth: admin, data },
          deps(() => jsonResponse(200, {}), calls),
        ),
        "invalid-argument",
        undefined,
        field,
      );
      assert.equal(calls.length, 0);
    });
  }

  it("période par défaut : 60 minutes", () => {
    assert.equal(readLogsQuery({}, NOW).periodMinutes, 60);
  });
});

describe("queryLogs — filtre (P49)", () => {
  it("clause imposée en tête, quels que soient les arguments", () => {
    for (const data of [
      {},
      { severity: "DEBUG" },
      { severity: "ERROR", functionName: "syncTickets", ticketId: "abc", freeText: "x" },
    ]) {
      const q = readLogsQuery(data, NOW);
      assert.ok(buildFilter(q, "2026-11-14T11:00:00.000Z").startsWith(`${BASE_CLAUSE} AND `));
    }
  });

  it("clauses : gravité, fonction en minuscules, ticket, texte, période", () => {
    const q = readLogsQuery(
      {
        severity: "WARNING",
        functionName: "launchTicketDelivery",
        ticketId: "T_1-a",
        freeText: "échec",
        periodMinutes: 1440,
      },
      NOW,
    );
    assert.equal(
      buildFilter(q, "2026-11-13T12:00:00.000Z"),
      `${BASE_CLAUSE} AND severity>=WARNING AND ` +
        `resource.labels.service_name="launchticketdelivery" AND ` +
        `jsonPayload.ticketId="T_1-a" AND jsonPayload.message:"échec" AND ` +
        `timestamp>="2026-11-13T12:00:00.000Z"`,
    );
  });

  it("DEBUG seul : severity=DEBUG", () => {
    const f = buildFilter(readLogsQuery({ severity: "DEBUG" }, NOW), "x");
    assert.ok(f.includes(" AND severity=DEBUG AND "));
    assert.ok(!f.includes("severity>="));
  });

  it('texte avec ", \\ et OR : échappé, reste entre guillemets', () => {
    const q = readLogsQuery({ freeText: 'a" OR severity>=DEBUG OR "\\' }, NOW);
    const f = buildFilter(q, "x");
    assert.ok(f.includes('jsonPayload.message:"a\\" OR severity>=DEBUG OR \\"\\\\"'));
  });

  it("période envoyée : maintenant moins la période, ordre et taille fixés", async () => {
    const calls: Call[] = [];
    await handleQueryLogsCall(
      { auth: admin, data: { periodMinutes: 10080 } },
      deps(() => jsonResponse(200, { entries: [] }), calls),
    );
    const body = sentBody(loggingCalls(calls)[0]);
    assert.deepEqual(body.resourceNames, ["projects/kassbeer"]);
    assert.equal(body.orderBy, "timestamp desc");
    assert.equal(body.pageSize, 50);
    assert.ok(String(body.filter).endsWith('timestamp>="2026-11-07T12:00:00.000Z"'));
    assert.equal(body.pageToken, undefined);
  });

  it("projet tiré de l'environnement, jamais d'un argument", async () => {
    const calls: Call[] = [];
    await handleQueryLogsCall(
      { auth: admin, data: { project: "autre-projet", resourceNames: ["projects/x"] } },
      deps(() => jsonResponse(200, {}), calls),
    );
    assert.deepEqual(sentBody(loggingCalls(calls)[0]).resourceNames, ["projects/kassbeer"]);
  });

  it("page suivante : même début de période, jeton de l'API transmis", async () => {
    const calls: Call[] = [];
    const first = await handleQueryLogsCall(
      { auth: admin, data: {} },
      deps(() => jsonResponse(200, { entries: [], nextPageToken: "API-1" }), calls),
    );
    assert.equal(first.nextPageToken, "60|2026-11-14T11:00:00.000Z|API-1");
    assert.equal(first.maxChars, TEXT_MAX_CHARS);
    const later = new Date(NOW.getTime() + 5 * 60_000);
    await handleQueryLogsCall(
      { auth: admin, data: { periodMinutes: 60, pageToken: first.nextPageToken } },
      deps(() => jsonResponse(200, { entries: [] }), calls, [], { now: () => later }),
    );
    const [a, b] = loggingCalls(calls).map(sentBody);
    assert.equal(a.filter, b.filter);
    assert.equal(b.pageToken, "API-1");
  });
});

describe("queryLogs — jeton de page (P49)", () => {
  it("période relue dans le jeton, début dans la marge de 5 minutes accepté", () => {
    const q = readLogsQuery({ pageToken: "1440|2026-11-13T11:55:00.000Z|tok" }, NOW);
    assert.equal(q.periodMinutes, 1440);
    assert.deepEqual(q.pageToken, { since: "2026-11-13T11:55:00.000Z", token: "tok" });
  });

  it("jeton de l'API contenant | : gardé entier", () => {
    const q = readLogsQuery({ pageToken: "60|2026-11-14T11:00:00.000Z|a|b" }, NOW);
    assert.equal(q.pageToken?.token, "a|b");
  });

  it("jeton rendu avec la période de la recherche", async () => {
    const res = await handleQueryLogsCall(
      { auth: admin, data: { periodMinutes: 10080 } },
      deps(() => jsonResponse(200, { entries: [], nextPageToken: "T" })),
    );
    assert.equal(res.nextPageToken, "10080|2026-11-07T12:00:00.000Z|T");
  });
});

describe("queryLogs — appel et erreurs (P49)", () => {
  it("un seul appel à entries:list, jeton mémorisé", async () => {
    const calls: Call[] = [];
    const cache: TokenCache = { value: null, expiresAt: 0 };
    const d = deps(() => jsonResponse(200, { entries: [] }), calls, [], { tokenCache: cache });
    await handleQueryLogsCall({ auth: admin, data: {} }, d);
    assert.equal(loggingCalls(calls).length, 1);
    assert.equal(calls.length, 2);
    const call = loggingCalls(calls)[0];
    assert.equal(call.url, "https://logging.googleapis.com/v2/entries:list");
    assert.equal(call.init.method, "POST");
    assert.equal(call.init.redirect, "error");
    assert.ok(call.init.signal instanceof AbortSignal);
    const metadata = calls[0];
    assert.equal(metadata.init.redirect, "error");
    assert.equal((metadata.init.headers as Record<string, string>)["Metadata-Flavor"], "Google");
    await handleQueryLogsCall({ auth: admin, data: {} }, d);
    assert.equal(calls.length, 3, "jeton relu dans le cache");
  });

  it("émulateur : failed-precondition, aucun appel", async () => {
    const calls: Call[] = [];
    await rejectsWith(
      handleQueryLogsCall(
        { auth: admin, data: {} },
        deps(() => jsonResponse(200, {}), calls, [], {
          env: { ...ENV, FUNCTIONS_EMULATOR: "true" },
        }),
      ),
      "failed-precondition",
      "emulator",
    );
    assert.equal(calls.length, 0);
  });

  const failures: [string, () => Promise<Response> | Response, string, string][] = [
    ["429", () => jsonResponse(429, {}), "resource-exhausted", "quota"],
    [
      "403",
      () => jsonResponse(403, { error: { message: "filtre cité" } }),
      "failed-precondition",
      "iam",
    ],
    ["401", () => jsonResponse(401, {}), "failed-precondition", "iam"],
    ["500", () => jsonResponse(500, {}), "unavailable", "logging_unavailable"],
    [
      "délai",
      () => Promise.reject(new DOMException("The operation was aborted", "TimeoutError")),
      "unavailable",
      "logging_unavailable",
    ],
    [
      "réseau",
      () => Promise.reject(new TypeError("fetch failed")),
      "unavailable",
      "logging_unavailable",
    ],
    [
      "corps illisible",
      () => new Response("pas du json", { status: 200 }),
      "unavailable",
      "logging_unavailable",
    ],
  ];
  for (const [name, response, code, reason] of failures) {
    it(`${name} : ${code}, un seul appel, journalisé sans jeton, filtre ni texte`, async () => {
      const calls: Call[] = [];
      const logs: LogEntry[] = [];
      await rejectsWith(
        handleQueryLogsCall(
          { auth: admin, data: { freeText: "texte-cherché-secret", ticketId: "T1" } },
          deps(response, calls, logs),
        ),
        code,
        reason,
      );
      assert.equal(loggingCalls(calls).length, 1);
      assert.equal(logs.length, 1);
      const written = JSON.stringify(logs.map((l) => ({ ...l, error: String(l.error) })));
      assert.ok(!written.includes(TOKEN));
      assert.ok(!written.includes("texte-cherché-secret"));
      assert.ok(!written.includes("resource.type"));
    });
  }

  it("serveur de métadonnées en panne : unavailable, aucun appel à Cloud Logging", async () => {
    const calls: Call[] = [];
    const logs: LogEntry[] = [];
    const d = deps(() => jsonResponse(200, {}), calls, logs, {
      fetchImpl: async (url, init) => {
        calls.push({ url, init });
        return jsonResponse(500, {});
      },
    });
    await rejectsWith(handleQueryLogsCall({ auth: admin, data: {} }, d), "unavailable");
    assert.equal(loggingCalls(calls).length, 0);
    assert.equal(logs.length, 1);
  });

  it("projet inconnu : unavailable, aucun appel", async () => {
    const calls: Call[] = [];
    await rejectsWith(
      handleQueryLogsCall(
        { auth: admin, data: {} },
        deps(() => jsonResponse(200, {}), calls, [], { env: {} }),
      ),
      "unavailable",
    );
    assert.equal(calls.length, 0);
  });
});

describe("queryLogs — réponse (P49)", () => {
  it("entrée réduite, payload sans message, coupé à 8 000 caractères, jetons retirés", async () => {
    const long = "x".repeat(TEXT_MAX_CHARS + 10);
    const res = await handleQueryLogsCall(
      { auth: admin, data: {} },
      deps(() =>
        jsonResponse(200, {
          entries: [
            {
              timestamp: "2026-11-14T11:59:00.123456Z",
              severity: "ERROR",
              insertId: "id1",
              resource: { labels: { service_name: "syncTickets".toLowerCase() } },
              jsonPayload: {
                message: "Échec pour brasseur@example.com ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                feature: "tickets",
                stack: long,
              },
              httpRequest: { remoteIp: "203.0.113.1" },
            },
            {
              timestamp: "2026-11-14T11:58:00Z",
              severity: "INFO",
              insertId: "id2",
              resource: { labels: { service_name: "querylogs" } },
              jsonPayload: { message: "court", ticketId: "T1" },
            },
            { timestamp: "2026-11-14T11:57:00Z", insertId: "id3", textPayload: "texte brut" },
            "pas une entrée",
          ],
        }),
      ),
    );
    assert.equal(res.entries.length, 3);
    const [a, b, c] = res.entries;
    assert.equal(a.functionName, "synctickets");
    assert.equal(a.severity, "ERROR");
    assert.ok(a.message.includes("brasseur@example.com"), "e-mail visible (choix du 2026-11-14)");
    assert.ok(!a.message.includes("ghp_"));
    assert.equal(a.payloadTruncated, true);
    assert.equal(a.payload.length, TEXT_MAX_CHARS);
    assert.ok(!a.payload.includes('"message"'));
    assert.ok(!JSON.stringify(res).includes("203.0.113.1"));
    assert.equal(b.payloadTruncated, false);
    assert.deepEqual(JSON.parse(b.payload), { ticketId: "T1" });
    assert.equal(c.message, "texte brut");
    assert.equal(c.severity, "DEFAULT");
    assert.equal(c.payload, "");
  });
});

describe("queryLogs — coupe après nettoyage (P49)", () => {
  it("un jeton à cheval sur la coupe est retiré avant la coupe", () => {
    const entry = toEntry({
      jsonPayload: { message: "m", detail: "x".repeat(7990) + "ghp_" + "A".repeat(30) },
    });
    assert.ok(entry !== null);
    assert.ok(!entry.payload.includes("ghp_"));
    assert.equal(entry.payloadTruncated, entry.payload.length === TEXT_MAX_CHARS);
  });

  it("message long : coupé, messageTruncated posé ; court : non", () => {
    const long = toEntry({ jsonPayload: { message: "m".repeat(TEXT_MAX_CHARS + 1) } });
    assert.equal(long?.message.length, TEXT_MAX_CHARS);
    assert.equal(long?.messageTruncated, true);
    const court = toEntry({ textPayload: "court" });
    assert.equal(court?.messageTruncated, false);
    const net = toEntry({
      jsonPayload: { message: "x".repeat(7980) + " ghp_" + "A".repeat(30) },
    });
    assert.ok(!net?.message.includes("ghp_"));
    assert.equal(net?.messageTruncated, false, "calculé sur le texte nettoyé");
  });
});

describe("queryLogs — liste fermée et champs de logging.ts (P49, P50)", () => {
  it("QUERYABLE_FUNCTIONS est la liste des exports de index.ts", () => {
    assert.deepEqual([...QUERYABLE_FUNCTIONS].sort(), Object.keys(index).sort());
  });

  it("logging.ts écrit ticketId et message, les champs filtrés", () => {
    const lines: string[] = [];
    const out = process.stdout.write.bind(process.stdout);
    const err = process.stderr.write.bind(process.stderr);
    const capture = (chunk: unknown): boolean => {
      lines.push(String(chunk));
      return true;
    };
    process.stdout.write = capture as typeof process.stdout.write;
    process.stderr.write = capture as typeof process.stderr.write;
    try {
      logError({ message: "Message de test P50", feature: "tickets", ticketId: "T-P50" });
    } finally {
      process.stdout.write = out;
      process.stderr.write = err;
    }
    const entry = JSON.parse(lines.join("").trim()) as Record<string, unknown>;
    assert.equal(entry[FILTERED_FIELDS.ticketId], "T-P50");
    assert.ok(String(entry[FILTERED_FIELDS.message]).includes("Message de test P50"));
    assert.equal(entry.severity, "ERROR");
  });

  it("le message d'erreur est trouvé par la clause de texte", () => {
    assert.ok(
      buildFilter(readLogsQuery({ freeText: "Message" }, NOW), "x").includes(
        `jsonPayload.${FILTERED_FIELDS.message}:"Message"`,
      ),
    );
  });
});
