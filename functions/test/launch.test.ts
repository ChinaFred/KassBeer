// Lancements de sessions Claude Code (ADR-008, T4) : appel de l'API Routines (P35), plafond
// et historique (P36, P41), règle « en cours », garde de la callable (P30).

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { LAUNCHES_PER_DAY, LAUNCH_COST_CENTER } from "../src/config";
import type { LogEntry } from "../src/logging";
import {
  closeRunningLaunches,
  handleLaunchCall,
  launchTicketSession,
  refreshLaunchStatus,
  type LaunchDeps,
} from "../src/tickets/launch";
import {
  LAUNCH_TEXT_PATTERN,
  closeRunningEntries,
  launchCommandText,
  LAUNCH_NOT_VALIDATED_BY_APP_MESSAGE,
  launchPrecondition,
  launchQuotaMessage,
  launchRunningMessage,
  nextLaunchStatus,
  refreshedLaunchStatus,
  runningLaunch,
  type LaunchEntryView,
} from "../src/tickets/launchModel";
import {
  classifyRoutineResponse,
  fireRoutine,
  isRedirectError,
  retryAfterMinutes,
  routineConfig,
  sessionUrlOrNull,
  withoutSecrets,
} from "../src/tickets/routine";
import { FakeDb } from "./fakeFirestore";

const NOW = Date.parse("2026-11-13T09:00:00Z");
const DAY = "20261113";
const ROUTINE_TOKEN = "sk-ant-oat01-routine-secret-AAAAAAAAAAAAAAAAAAAAAAAA";
const ROUTINE_ID = "trig_01ABCdef";
const GH_TOKEN = "github_pat_11AAAAAAAAAAAAAAAAAAAA_secretsecretsecretsecret";
const SESSION = "https://claude.ai/code/session_01XYZ";

// ── P35 : client de l'API Routines ──────────────────────────────────────────

describe("routine : configuration (P35)", () => {
  it("identifiant ou jeton vide : non configuré", () => {
    assert.equal(routineConfig("", ROUTINE_TOKEN), null);
    assert.equal(routineConfig(ROUTINE_ID, "  "), null);
    assert.equal(routineConfig(undefined, undefined), null);
  });
  it("identifiant hors [A-Za-z0-9_-]{1,128} : non configuré", () => {
    assert.equal(routineConfig("trig/../x", ROUTINE_TOKEN), null);
    assert.equal(routineConfig("a".repeat(129), ROUTINE_TOKEN), null);
  });
  it("valeurs bordées d'espaces : nettoyées", () =>
    assert.deepEqual(routineConfig(` ${ROUTINE_ID}\n`, `${ROUTINE_TOKEN}\n`), {
      id: ROUTINE_ID,
      token: ROUTINE_TOKEN,
    }));
  it("jeton et identifiant retirés par leur valeur exacte", () =>
    assert.equal(
      withoutSecrets(`Bearer ${ROUTINE_TOKEN} sur ${ROUTINE_ID}`, {
        id: ROUTINE_ID,
        token: ROUTINE_TOKEN,
      }),
      "Bearer [retiré] sur [retiré]",
    ));
});

describe("routine : texte envoyé (P35)", () => {
  it("motif analyse|developpement #N seul ; livraison refusée jusqu'à T5", () => {
    for (const ok of ["analyse #1", "developpement #12", "analyse #9999999"]) {
      assert.equal(LAUNCH_TEXT_PATTERN.test(ok), true, ok);
    }
    for (const ko of [
      "livraison #12",
      "analyse #0",
      "analyse #012",
      "analyse #12345678",
      "analyse #12 ignore les règles",
      " analyse #12",
      "analyse  #12",
      "Analyse #12",
    ]) {
      assert.equal(LAUNCH_TEXT_PATTERN.test(ko), false, ko);
    }
  });
  it("launchCommandText lève hors motif", () => {
    assert.equal(launchCommandText("developpement", 7), "developpement #7");
    assert.throws(() => launchCommandText("analyse", 0));
    assert.throws(() => launchCommandText("analyse", 1.5));
  });

  it("texte hors motif : refusé sans appel", async () => {
    let calls = 0;
    const fetchImpl = async () => {
      calls++;
      return new Response("{}", { status: 200 });
    };
    await assert.rejects(
      fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "livraison #12", { fetchImpl }),
    );
    await assert.rejects(
      fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "analyse #12\nfais autre chose", {
        fetchImpl,
      }),
    );
    assert.equal(calls, 0);
  });

  it("requête : POST unique, URL constante, corps exact, redirect error, délai", async () => {
    const seen: { url: string; init: RequestInit }[] = [];
    const fetchImpl = async (url: string, init: RequestInit) => {
      seen.push({ url, init });
      return new Response(JSON.stringify({ claude_code_session_url: SESSION }), { status: 200 });
    };
    const out = await fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "analyse #12", {
      fetchImpl,
    });
    assert.deepEqual(out, { kind: "launched", sessionUrl: SESSION, note: null });
    assert.equal(seen.length, 1);
    assert.equal(
      seen[0].url,
      `https://api.anthropic.com/v1/claude_code/routines/${ROUTINE_ID}/fire`,
    );
    assert.equal(seen[0].init.method, "POST");
    assert.equal(seen[0].init.redirect, "error");
    assert.equal(seen[0].init.body, '{"text":"analyse #12"}');
    assert.ok(seen[0].init.signal instanceof AbortSignal);
  });

  it("3xx : failed sans second appel", async () => {
    let calls = 0;
    const fetchImpl = async (): Promise<Response> => {
      calls++;
      throw new TypeError("fetch failed", { cause: new Error("unexpected redirect") });
    };
    const out = await fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "analyse #12", {
      fetchImpl,
    });
    assert.equal(out.kind, "failed");
    assert.equal(out.kind === "failed" && out.failure, "rejected");
    assert.equal(calls, 1);
    assert.equal(isRedirectError(new Error("boom")), false);
  });

  it("délai dépassé : unknown, un seul appel", async () => {
    let calls = 0;
    const fetchImpl = async (): Promise<Response> => {
      calls++;
      throw new DOMException("The operation was aborted due to timeout", "TimeoutError");
    };
    const out = await fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "analyse #12", {
      fetchImpl,
    });
    assert.deepEqual(out, { kind: "unknown", status: null, detail: "délai dépassé" });
    assert.equal(calls, 1);
  });

  it("erreur réseau qui cite le jeton : unknown, journalisée, jeton retiré", async () => {
    const logs: LogEntry[] = [];
    const fetchImpl = async (): Promise<Response> => {
      throw new Error(`socket closed (authorization: ${ROUTINE_TOKEN}, ${ROUTINE_ID})`);
    };
    const out = await fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "analyse #12", {
      fetchImpl,
      log: (e) => logs.push(e),
    });
    assert.equal(out.kind, "unknown");
    assert.equal(JSON.stringify(out).includes(ROUTINE_TOKEN), false);
    assert.equal(logs.length, 1);
    assert.equal(logs[0].error, undefined);
    assert.match(String(logs[0].extra?.error), /socket closed/);
    for (const secret of [ROUTINE_TOKEN, ROUTINE_ID]) {
      assert.equal(JSON.stringify(logs).includes(secret), false, secret);
    }
  });

  it("corps de réponse illisible : journalisé, jeton retiré, statut seul décide", async () => {
    const logs: LogEntry[] = [];
    const broken = new Response("{}", { status: 200 });
    Object.defineProperty(broken, "text", {
      value: async () => {
        throw new Error(`flux coupé ${ROUTINE_TOKEN}`);
      },
    });
    const out = await fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "analyse #12", {
      fetchImpl: async () => broken,
      log: (e) => logs.push(e),
    });
    assert.equal(out.kind, "launched");
    assert.equal(out.kind === "launched" && out.sessionUrl, null);
    // Deux `catch` : le corps perdu, puis le corps (texte de remplacement) illisible en JSON.
    assert.equal(logs.length, 2);
    assert.equal(JSON.stringify({ out, logs }).includes(ROUTINE_TOKEN), false);
  });

  it("2xx en JSON illisible : session lancée sans lien, journalisée", async () => {
    const logs: LogEntry[] = [];
    const out = await fireRoutine({ id: ROUTINE_ID, token: ROUTINE_TOKEN }, "analyse #12", {
      fetchImpl: async () => new Response("pas du JSON", { status: 201 }),
      log: (e) => logs.push(e),
    });
    assert.equal(out.kind === "launched" && out.sessionUrl, null);
    assert.equal(logs.length, 1);
    assert.equal(logs[0].feature, "tickets");
  });
});

describe("routine : réponses classées (P35)", () => {
  const c = (status: number, body = "", retry: string | null = null) =>
    classifyRoutineResponse(
      status,
      body,
      retry,
      NOW,
      (v) => v,
      () => undefined,
    );
  it("2xx : lancé, lien https://claude.ai seul", () => {
    assert.deepEqual(c(200, JSON.stringify({ claude_code_session_url: SESSION })), {
      kind: "launched",
      sessionUrl: SESSION,
      note: null,
    });
    const unreadable = c(200, "pas du JSON");
    assert.equal(unreadable.kind === "launched" && unreadable.sessionUrl, null);
    assert.equal(unreadable.kind === "launched" && typeof unreadable.note, "string");
  });
  it("2xx illisible : le message de JSON.parse passe par clean (journal et note)", () => {
    const logs: LogEntry[] = [];
    const out = classifyRoutineResponse(
      200,
      "secret-du-corps x",
      null,
      NOW,
      (v) => v.replaceAll("secret-du-corps", "[retiré]"),
      (e) => logs.push(e),
    );
    assert.equal(logs.length, 1);
    assert.equal(JSON.stringify({ out, logs }).includes("secret-du-corps"), false);
  });
  it("400 en pause, 400 autre, 401, 403, 404, 429, 5xx", () => {
    assert.equal(c(400, "routine is paused").kind === "failed" && "paused", "paused");
    const f = (s: number, b = "") => {
      const o = c(s, b);
      return o.kind === "failed" ? o.failure : o.kind;
    };
    assert.equal(f(400, "routine is paused"), "paused");
    assert.equal(f(400, "bad text"), "rejected");
    assert.equal(f(401), "token");
    assert.equal(f(403), "token");
    assert.equal(f(404), "not_found");
    assert.equal(f(429), "rate_limit");
    assert.equal(f(500), "unknown");
    assert.equal(f(503), "unknown");
    assert.equal(f(302), "rejected");
  });
  it("Retry-After en secondes ou en date, arrondi à la minute supérieure", () => {
    assert.equal(retryAfterMinutes("90", NOW), 2);
    assert.equal(retryAfterMinutes("0", NOW), 1);
    assert.equal(retryAfterMinutes(new Date(NOW + 5 * 60_000).toUTCString(), NOW), 5);
    assert.equal(retryAfterMinutes("demain", NOW), null);
    assert.equal(retryAfterMinutes(null, NOW), null);
  });
  it("lien de session : https sur claude.ai, 500 caractères au plus", () => {
    assert.equal(sessionUrlOrNull(SESSION), SESSION);
    for (const bad of [
      "http://claude.ai/code/x",
      "https://claude.ai.exemple.fr/x",
      "https://exemple.fr/claude.ai",
      "https://user@claude.ai/x",
      "javascript:alert(1)",
      `https://claude.ai/${"x".repeat(500)}`,
      42,
      "",
    ]) {
      assert.equal(sessionUrlOrNull(bad), null, String(bad));
    }
  });
});

// ── Règles pures ────────────────────────────────────────────────────────────

describe("lancements : précondition et règle « en cours »", () => {
  it("analyse depuis received, développement depuis validated, Issue requise", () => {
    assert.equal(launchPrecondition({ status: "received", hasIssue: true }, "analyse"), null);
    assert.equal(
      launchPrecondition(
        { status: "validated", hasIssue: true, validatedByAppAt: Timestamp.fromMillis(NOW) },
        "developpement",
      ),
      null,
    );
    // Validé sur GitHub seul (étiquette `validé`, sans décision appliquée) : refusé.
    assert.equal(
      launchPrecondition({ status: "validated", hasIssue: true }, "developpement"),
      LAUNCH_NOT_VALIDATED_BY_APP_MESSAGE,
    );
    assert.notEqual(launchPrecondition({ status: "analyzed", hasIssue: true }, "analyse"), null);
    assert.notEqual(
      launchPrecondition({ status: "received", hasIssue: true }, "developpement"),
      null,
    );
    assert.notEqual(launchPrecondition({ status: "received", hasIssue: false }, "analyse"), null);
  });

  const view = (over: Partial<LaunchEntryView>): LaunchEntryView => ({
    id: "x",
    action: "analyse",
    state: "launched",
    at_ms: NOW - 60_000,
    retry_after_ms: NOW + 60_000,
    ...over,
  });
  it("launched ou unknown à échéance future : en cours", () => {
    assert.notEqual(runningLaunch([view({})], "analyse", NOW), null);
    assert.notEqual(runningLaunch([view({ state: "unknown" })], "analyse", NOW), null);
  });
  it("failed, échéance passée, autre action : rien en cours", () => {
    assert.equal(runningLaunch([view({ state: "failed" })], "analyse", NOW), null);
    assert.equal(runningLaunch([view({ retry_after_ms: NOW })], "analyse", NOW), null);
    assert.equal(runningLaunch([view({})], "developpement", NOW), null);
    assert.equal(runningLaunch([view({ retry_after_ms: null })], "analyse", NOW), null);
  });
  it("après « Répondre » : échéances ramenées à l'heure de la réponse", () => {
    const raw = [{ id: "a" }, { id: "b" }];
    const next = closeRunningEntries(raw, [view({}), view({ state: "failed" })], NOW, (ms) => ms);
    assert.deepEqual(next, [{ id: "a", retry_after: NOW }, { id: "b" }]);
    assert.equal(
      closeRunningEntries(raw, [view({ state: "failed" })], NOW, (ms) => ms),
      null,
    );
  });
  it("messages repris de Kass'Dalle", () => {
    assert.equal(
      launchQuotaMessage(10),
      "Vous avez lancé 10 sessions aujourd'hui. Réessayez demain.",
    );
    assert.equal(
      launchRunningMessage("analyse", NOW, NOW + 3_600_000),
      "Une analyse a été lancée le 13/11/26 à 10:00. Attendez son résultat ou relancez après 11:00.",
    );
  });
});

describe("ticket_status/launches : compteurs", () => {
  it("compter : jour et mois, per_day écrit ; nouveau mois repart de zéro", () => {
    assert.deepEqual(nextLaunchStatus({}, DAY, 1, 1), {
      per_day: LAUNCHES_PER_DAY,
      day: DAY,
      count_day: 1,
      month: "202611",
      count_month: 1,
    });
    assert.deepEqual(
      nextLaunchStatus({ day: "20261112", month: "202611", count_month: 4 }, DAY, 1, 1).count_month,
      5,
    );
    assert.equal(
      nextLaunchStatus({ month: "202610", count_month: 40 }, "20261101", 1, 1).count_month,
      1,
    );
  });
  it("rendre : jamais sous zéro ; un autre jour ou mois garde ses compteurs", () => {
    assert.deepEqual(
      nextLaunchStatus({ day: DAY, count_day: 1, month: "202611", count_month: 0 }, DAY, 0, -1),
      { per_day: LAUNCHES_PER_DAY, count_day: 0, count_month: 0 },
    );
    assert.deepEqual(
      nextLaunchStatus({ day: "20261114", month: "202612", count_month: 3 }, DAY, 0, -1),
      { per_day: LAUNCHES_PER_DAY },
    );
  });
  it("passe horaire : jour remis, rien si inchangé", () => {
    const fresh = refreshedLaunchStatus({}, DAY, 0);
    assert.deepEqual(fresh, {
      day: DAY,
      count_day: 0,
      month: "202611",
      count_month: 0,
      per_day: LAUNCHES_PER_DAY,
    });
    assert.equal(refreshedLaunchStatus(fresh ?? {}, DAY, 0), null);
  });
});

// ── P36 : lancement de bout en bout sur une base en mémoire ─────────────────

interface Harness {
  db: FakeDb;
  logs: { level: string; entry: LogEntry }[];
  routineCalls: { url: string; body: unknown }[];
  githubCalls: string[];
  applied: string[];
  deps: (over?: Partial<LaunchDeps>) => LaunchDeps;
  clock: { now: number };
}

function harness(
  opts: {
    routine?: (n: number) => Promise<Response>;
    labels?: string[];
    issueState?: "open" | "closed";
  } = {},
): Harness {
  const clock = { now: NOW };
  const db = new FakeDb(() => clock.now);
  const logs: Harness["logs"] = [];
  const routineCalls: Harness["routineCalls"] = [];
  const githubCalls: string[] = [];
  const applied: string[] = [];
  const routine =
    opts.routine ??
    (async () =>
      new Response(JSON.stringify({ claude_code_session_url: SESSION }), { status: 200 }));
  const deps = (over: Partial<LaunchDeps> = {}): LaunchDeps => ({
    routine: () => ({ id: ROUTINE_ID, token: ROUTINE_TOKEN }),
    githubToken: () => GH_TOKEN,
    kit: async () => db.kit(),
    nowMs: () => clock.now,
    log: (level, entry) => logs.push({ level, entry }),
    fetchRoutine: async (url, init) => {
      routineCalls.push({ url, body: init.body });
      return routine(routineCalls.length);
    },
    fetchGithub: async (url) => {
      githubCalls.push(url);
      const number = Number(url.split("/").pop());
      return new Response(
        JSON.stringify({
          number,
          state: opts.issueState ?? "open",
          state_reason: null,
          labels: (opts.labels ?? ["source:app", "statut:à-analyser"]).map((name) => ({ name })),
          comments: 0,
          updated_at: "2026-11-13T08:00:00Z",
        }),
        { status: 200 },
      );
    },
    applyIssue: async (_client, doc) => {
      applied.push(doc.id);
    },
    markTokenInvalid: async () => undefined,
    recordTokenAccepted: async () => undefined,
    ...over,
  });
  return { db, logs, routineCalls, githubCalls, applied, deps, clock };
}

function seedTicket(h: Harness, id: string, extra: Record<string, unknown> = {}): void {
  h.db.seed(`tickets/${id}`, {
    status: "received",
    github_issue_number: 12,
    ...extra,
  });
}

const quota = (h: Harness) => h.db.read(`ticket_quotas/launch_${DAY}`)?.count ?? 0;
const history = (h: Harness, id = "t-1") =>
  (h.db.read(`tickets/${id}/admin/launches`)?.entries ?? []) as Record<string, unknown>[];

async function refusal(promise: Promise<unknown>): Promise<HttpsError> {
  try {
    await promise;
  } catch (err) {
    assert.ok(err instanceof HttpsError, String(err));
    return err;
  }
  assert.fail("refus attendu");
}

const details = (err: HttpsError) => err.details as Record<string, unknown>;

describe("lancement : chemin nominal (P36, P41)", () => {
  it("lancé : compté, entrée launched avec lien, bail retiré, un seul appel", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    const out = await launchTicketSession("t-1", "analyse", "admin-uid", h.deps());
    assert.deepEqual(out, { outcome: "launched", sessionUrl: SESSION });
    assert.equal(h.routineCalls.length, 1);
    assert.equal(h.routineCalls[0].body, '{"text":"analyse #12"}');
    assert.equal(quota(h), 1);
    const status = h.db.read("ticket_status/launches") ?? {};
    assert.equal(status.day, DAY);
    assert.equal(status.count_day, 1);
    assert.equal(status.month, "202611");
    assert.equal(status.count_month, 1);
    assert.equal(status.per_day, LAUNCHES_PER_DAY);
    const [entry] = history(h);
    assert.equal(entry.action, "analyse");
    assert.equal(entry.state, "launched");
    assert.equal(entry.by_uid, "admin-uid");
    assert.equal(entry.session_url, SESSION);
    assert.equal((entry.at as Timestamp).toMillis(), NOW);
    assert.equal((entry.retry_after as Timestamp).toMillis(), NOW + 3_600_000);
    assert.equal(h.db.read("tickets/t-1")?.decision_lease_until, undefined);
    // Rien n'est écrit dans le ticket, que l'auteur lit.
    assert.deepEqual(Object.keys(h.db.read("tickets/t-1") ?? {}).sort(), [
      "github_issue_number",
      "status",
    ]);
    assert.ok(h.logs.every((l) => l.entry.extra?.cost_center === LAUNCH_COST_CENTER));
  });

  it("développement depuis validated : developpement #N, échéance 3 h", async () => {
    const h = harness({ labels: ["source:app", "statut:analysé", "validé"] });
    seedTicket(h, "t-1", { status: "validated", validated_by_app_at: Timestamp.fromMillis(NOW) });
    await launchTicketSession("t-1", "developpement", "admin-uid", h.deps());
    assert.equal(h.routineCalls[0].body, '{"text":"developpement #12"}');
    assert.equal((history(h)[0].retry_after as Timestamp).toMillis(), NOW + 3 * 3_600_000);
  });

  it("ticket reçu passé à validé sur GitHub hors décision : développement refusé, rien compté", async () => {
    const h = harness({ labels: ["source:app", "statut:analysé", "validé"] });
    // État écrit par la relecture de l'Issue : statut `validated`, sans `validated_by_app_at`.
    seedTicket(h, "t-1", { status: "validated", validated_by_app_at: null });
    const err = await refusal(launchTicketSession("t-1", "developpement", "admin-uid", h.deps()));
    assert.equal(err.code, "failed-precondition");
    assert.equal(details(err).code, "not_launchable");
    assert.equal(details(err).reason, LAUNCH_NOT_VALIDATED_BY_APP_MESSAGE);
    assert.equal(h.routineCalls.length, 0);
    assert.equal(quota(h), 0);

    // Décision `validate` appliquée depuis l'application : `validated_by_app_at` posé.
    h.db.seed("tickets/t-1", {
      status: "validated",
      github_issue_number: 12,
      validated_by_app_at: Timestamp.fromMillis(NOW),
    });
    const out = await launchTicketSession("t-1", "developpement", "admin-uid", h.deps());
    assert.equal(out.outcome, "launched");
    assert.equal(h.routineCalls.length, 1);
  });

  it("vingt entrées au plus, la plus récente en tête", async () => {
    const h = harness();
    const old = Array.from({ length: 20 }, (_, i) => ({
      id: `old-${i}`,
      action: "analyse",
      state: "failed",
      at: Timestamp.fromMillis(NOW - 1000 * (i + 1)),
      retry_after: Timestamp.fromMillis(NOW - 1000 * (i + 1)),
    }));
    seedTicket(h, "t-1");
    h.db.seed("tickets/t-1/admin/launches", { entries: old });
    await launchTicketSession("t-1", "analyse", "admin-uid", h.deps());
    const list = history(h);
    assert.equal(list.length, 20);
    assert.equal(list[0].state, "launched");
    assert.equal(list[19].id, "old-18");
  });
});

describe("lancement : plafond du jour (P36)", () => {
  it("10e lancement accepté, 11e refusé sans appel", async () => {
    const h = harness();
    for (let i = 0; i <= LAUNCHES_PER_DAY; i++) seedTicket(h, `t-${i}`);
    for (let i = 0; i < LAUNCHES_PER_DAY; i++) {
      const out = await launchTicketSession(`t-${i}`, "analyse", "admin-uid", h.deps());
      assert.equal(out.outcome, "launched", `lancement ${i + 1}`);
    }
    assert.equal(quota(h), LAUNCHES_PER_DAY);
    const err = await refusal(
      launchTicketSession(`t-${LAUNCHES_PER_DAY}`, "analyse", "admin-uid", h.deps()),
    );
    assert.equal(err.code, "resource-exhausted");
    assert.equal(details(err).code, "quota_exceeded");
    assert.equal(details(err).limit, LAUNCHES_PER_DAY);
    assert.equal(details(err).reason, launchQuotaMessage(LAUNCHES_PER_DAY));
    assert.equal(h.routineCalls.length, LAUNCHES_PER_DAY);
    assert.equal(quota(h), LAUNCHES_PER_DAY);
    assert.deepEqual(history(h, `t-${LAUNCHES_PER_DAY}`), []);
    assert.equal(h.db.read(`tickets/t-${LAUNCHES_PER_DAY}`)?.decision_lease_until, undefined);
  });

  it("deux appels simultanés sur deux tickets : comptés deux fois", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    seedTicket(h, "t-2");
    const outs = await Promise.all([
      launchTicketSession("t-1", "analyse", "admin-uid", h.deps()),
      launchTicketSession("t-2", "analyse", "admin-uid", h.deps()),
    ]);
    assert.deepEqual(
      outs.map((o) => o.outcome),
      ["launched", "launched"],
    );
    assert.equal(quota(h), 2);
    assert.equal(h.db.read("ticket_status/launches")?.count_day, 2);
    assert.equal(h.db.read("ticket_status/launches")?.count_month, 2);
  });

  it("deux appels simultanés sur le même ticket : un seul part", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    const results = await Promise.allSettled([
      launchTicketSession("t-1", "analyse", "admin-uid", h.deps()),
      launchTicketSession("t-1", "analyse", "admin-uid", h.deps()),
    ]);
    assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
    const rejected = results.find((r) => r.status === "rejected") as PromiseRejectedResult;
    assert.equal(details(rejected.reason as HttpsError).code, "decision_in_progress");
    assert.equal(h.routineCalls.length, 1);
    assert.equal(quota(h), 1);
  });

  it("jour suivant : nouveau compteur", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    h.db.seed("ticket_quotas/launch_20261112", { count: LAUNCHES_PER_DAY, day: "20261112" });
    await launchTicketSession("t-1", "analyse", "admin-uid", h.deps());
    assert.equal(quota(h), 1);
  });
});

describe("lancement : échec, résultat inconnu, en cours (P35, P36)", () => {
  it("401 : failed, compteur rendu, alerte posée, jeton absent des journaux", async () => {
    const h = harness({
      routine: async () =>
        new Response(`{"error":"bad token ${ROUTINE_TOKEN} for ${ROUTINE_ID}"}`, { status: 401 }),
    });
    seedTicket(h, "t-1");
    const err = await refusal(launchTicketSession("t-1", "analyse", "admin-uid", h.deps()));
    assert.equal(err.code, "failed-precondition");
    assert.equal(details(err).code, "routine_invalid");
    assert.equal(
      details(err).reason,
      "Le jeton de la routine est refusé. Remplacez-le dans Secret Manager.",
    );
    assert.equal(quota(h), 0);
    assert.equal(h.db.read("ticket_status/launches")?.count_day, 0);
    const [entry] = history(h);
    assert.equal(entry.state, "failed");
    assert.equal((entry.retry_after as Timestamp).toMillis(), (entry.at as Timestamp).toMillis());
    assert.ok(h.db.read("ticket_status/launches")?.analysis_invalid_since instanceof Timestamp);
    assert.equal(h.db.read("ticket_status/launches")?.development_invalid_since, undefined);
    const everything = JSON.stringify([h.logs, [...h.db.docs], err.details, err.message]);
    assert.equal(everything.includes(ROUTINE_TOKEN), false);
    assert.equal(everything.includes(ROUTINE_ID), false);

    // Un échec ne bloque pas : la relance part, et l'alerte s'efface.
    const out = await launchTicketSession(
      "t-1",
      "analyse",
      "admin-uid",
      h.deps({
        fetchRoutine: async () =>
          new Response(JSON.stringify({ claude_code_session_url: SESSION }), { status: 200 }),
      }),
    );
    assert.equal(out.outcome, "launched");
    assert.equal(h.db.read("ticket_status/launches")?.analysis_invalid_since, null);
    assert.equal(quota(h), 1);
  });

  it("404 : routine_invalid, alerte posée ; 429 : resource-exhausted ; 400 en pause", async () => {
    const cases: [number, string, string, string][] = [
      [404, "", "failed-precondition", "routine_invalid"],
      [429, "", "resource-exhausted", "routine_rate_limited"],
      [400, "routine paused", "failed-precondition", "routine_paused"],
      [400, "bad text", "failed-precondition", "routine_failed"],
    ];
    for (const [status, body, code, machine] of cases) {
      const h = harness({ routine: async () => new Response(body, { status }) });
      seedTicket(h, "t-1");
      const err = await refusal(launchTicketSession("t-1", "analyse", "admin-uid", h.deps()));
      assert.equal(err.code, code, String(status));
      assert.equal(details(err).code, machine, String(status));
      assert.equal(quota(h), 0, String(status));
      assert.equal(h.routineCalls.length, 1);
    }
  });

  it("délai dépassé : unknown, compté, entrée unknown, relance refusée « en cours »", async () => {
    const h = harness({
      routine: async () => {
        throw new DOMException("timeout", "TimeoutError");
      },
    });
    seedTicket(h, "t-1");
    const out = await launchTicketSession("t-1", "analyse", "admin-uid", h.deps());
    assert.deepEqual(out, { outcome: "unknown" });
    assert.equal(quota(h), 1);
    assert.equal(history(h)[0].state, "unknown");
    assert.equal(h.routineCalls.length, 1);
    // Le `catch` de `routine.ts` journalise avec le poste de coût et l'action.
    const caught = h.logs.find((l) => l.entry.message === "Tickets : appel de la routine en échec");
    assert.ok(caught);
    assert.equal(caught.level, "error");
    assert.equal(caught.entry.extra?.cost_center, LAUNCH_COST_CENTER);
    assert.equal(caught.entry.extra?.action, "analyse");
    assert.equal(caught.entry.ticketId, "t-1");

    h.clock.now = NOW + 30 * 60_000;
    const err = await refusal(launchTicketSession("t-1", "analyse", "admin-uid", h.deps()));
    assert.equal(details(err).code, "running");
    assert.equal(
      details(err).reason,
      "Une analyse a été lancée le 13/11/26 à 10:00. Attendez son résultat ou relancez après 11:00.",
    );
    assert.equal(h.routineCalls.length, 1);
    assert.equal(quota(h), 1);

    // Échéance passée : la relance part.
    h.clock.now = NOW + 61 * 60_000;
    await launchTicketSession("t-1", "analyse", "admin-uid", h.deps());
    assert.equal(h.routineCalls.length, 2);
  });

  it("5xx : unknown avec motif, compté", async () => {
    const h = harness({ routine: async () => new Response("oops", { status: 503 }) });
    seedTicket(h, "t-1");
    const out = await launchTicketSession("t-1", "analyse", "admin-uid", h.deps());
    assert.deepEqual(out, {
      outcome: "unknown",
      reason: "Claude ne répond pas. Vérifiez sur claude.ai/code avant de relancer.",
    });
    assert.equal(quota(h), 1);
    assert.equal(history(h)[0].reason, out.outcome === "unknown" ? out.reason : null);
  });

  it("lancement en cours d'une autre action : ne bloque pas", async () => {
    const h = harness({ labels: ["source:app", "statut:analysé", "validé"] });
    seedTicket(h, "t-1", { status: "validated", validated_by_app_at: Timestamp.fromMillis(NOW) });
    h.db.seed("tickets/t-1/admin/launches", {
      entries: [
        {
          id: "a",
          action: "analyse",
          state: "launched",
          at: Timestamp.fromMillis(NOW - 60_000),
          retry_after: Timestamp.fromMillis(NOW + 60_000),
        },
      ],
    });
    const out = await launchTicketSession("t-1", "developpement", "admin-uid", h.deps());
    assert.equal(out.outcome, "launched");
  });

  it("après « Répondre » : l'analyse en cours ne bloque plus", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    h.db.seed("tickets/t-1/admin/launches", {
      entries: [
        {
          id: "a",
          action: "analyse",
          state: "unknown",
          at: Timestamp.fromMillis(NOW - 60_000),
          retry_after: Timestamp.fromMillis(NOW + 60_000),
        },
      ],
    });
    await closeRunningLaunches(
      "t-1",
      async () => h.db.kit(),
      () => NOW,
    );
    const out = await launchTicketSession("t-1", "analyse", "admin-uid", h.deps());
    assert.equal(out.outcome, "launched");
  });
});

describe("lancement : refus avant l'appel (P35, P36)", () => {
  it("routine non configurée : rien compté, rien écrit, rien envoyé", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    const before = h.db.writes.length;
    const err = await refusal(
      launchTicketSession(
        "t-1",
        "analyse",
        "admin-uid",
        h.deps({ routine: () => ({ id: "", token: ROUTINE_TOKEN }) }),
      ),
    );
    assert.equal(details(err).code, "not_configured");
    assert.equal(h.db.writes.length, before);
    assert.equal(h.routineCalls.length, 0);
    assert.equal(h.githubCalls.length, 0);
  });

  it("statut non permis, Issue absente, ticket absent", async () => {
    const h = harness();
    seedTicket(h, "t-a", { status: "analyzed" });
    seedTicket(h, "t-r");
    seedTicket(h, "t-n", { github_issue_number: null });
    const codes = [];
    for (const [id, action] of [
      ["t-a", "analyse"],
      ["t-r", "developpement"],
      ["t-n", "analyse"],
    ] as const) {
      codes.push(details(await refusal(launchTicketSession(id, action, "u", h.deps()))).code);
    }
    const missing = await refusal(launchTicketSession("t-x", "analyse", "u", h.deps()));
    assert.deepEqual(codes, ["not_launchable", "not_launchable", "not_launchable"]);
    assert.equal(missing.code, "not-found");
    assert.equal(details(missing).code, "ticket_not_found");
    assert.equal(quota(h), 0);
    assert.equal(h.routineCalls.length, 0);
  });

  it("bail d'une décision actif : refusé", async () => {
    const h = harness();
    seedTicket(h, "t-1", { decision_lease_until: Timestamp.fromMillis(NOW + 10_000) });
    const err = await refusal(launchTicketSession("t-1", "analyse", "u", h.deps()));
    assert.equal(details(err).code, "decision_in_progress");
  });

  it("Issue changée sur GitHub : état appliqué, compteur rendu, rien lancé", async () => {
    const h = harness({ labels: ["source:app", "statut:analysé"] });
    seedTicket(h, "t-1");
    const err = await refusal(launchTicketSession("t-1", "analyse", "u", h.deps()));
    assert.equal(details(err).code, "ticket_changed");
    assert.equal(details(err).reason, "Le ticket a changé sur GitHub. Rien n'a été lancé.");
    assert.deepEqual(h.applied, ["t-1"]);
    assert.equal(quota(h), 0);
    assert.equal(h.routineCalls.length, 0);
    assert.deepEqual(history(h), []);
  });

  it("Issue fermée : ticket_changed", async () => {
    const h = harness({ issueState: "closed" });
    seedTicket(h, "t-1");
    const err = await refusal(launchTicketSession("t-1", "analyse", "u", h.deps()));
    assert.equal(details(err).code, "ticket_changed");
  });

  it("jeton GitHub vide : github_token, compteur rendu", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    let marked = 0;
    const err = await refusal(
      launchTicketSession(
        "t-1",
        "analyse",
        "u",
        h.deps({
          githubToken: () => " ",
          markTokenInvalid: async () => {
            marked++;
          },
        }),
      ),
    );
    assert.equal(details(err).code, "github_token");
    assert.equal(marked, 1);
    assert.equal(quota(h), 0);
    assert.equal(h.routineCalls.length, 0);
  });
});

describe("callables de lancement : garde (P30)", () => {
  const token = (email: string) => ({
    email,
    email_verified: true,
    firebase: { sign_in_provider: "google.com" },
  });

  it("brasseur refusé avant toute lecture des arguments ; anonyme refusé", async () => {
    const h = harness();
    let reads = 0;
    const lookup = async () => {
      reads++;
      return { role: "brewer" };
    };
    const req = {
      auth: { uid: "u", token: token("brasseur@example.com") },
      data: { ticketId: 42 },
    };
    const err = await refusal(handleLaunchCall(req, "analyse", { ...h.deps(), lookup }));
    assert.equal(err.code, "permission-denied");
    assert.equal(reads, 1);
    const anon = await refusal(
      handleLaunchCall({ data: req.data }, "analyse", { ...h.deps(), lookup }),
    );
    assert.equal(anon.code, "unauthenticated");
    assert.equal(h.routineCalls.length, 0);
  });

  it("e-mail non vérifié, autre fournisseur, non membre : refusés sans appel", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    const lookup = async (email: string) =>
      email === "admin@example.com" ? { role: "admin" } : null;
    const call = (tok: Record<string, unknown>) =>
      refusal(
        handleLaunchCall({ auth: { uid: "u", token: tok }, data: { ticketId: "t-1" } }, "analyse", {
          ...h.deps(),
          lookup,
        }),
      );
    const unverified = await call({ ...token("admin@example.com"), email_verified: false });
    assert.equal(unverified.code, "permission-denied");
    const otherProvider = await call({
      ...token("admin@example.com"),
      firebase: { sign_in_provider: "password" },
    });
    assert.equal(otherProvider.code, "permission-denied");
    const stranger = await call(token("inconnu@example.com"));
    assert.equal(stranger.code, "permission-denied");
    assert.equal(h.routineCalls.length, 0);
    assert.equal(quota(h), 0);
  });

  it("admin : ticketId borné, puis lancement", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    const lookup = async () => ({ role: "admin" });
    const req = (ticketId: unknown) => ({
      auth: { uid: "admin-uid", token: token("admin@example.com") },
      data: { ticketId },
    });
    const bad = await refusal(handleLaunchCall(req("../x"), "analyse", { ...h.deps(), lookup }));
    assert.equal(bad.code, "invalid-argument");
    assert.equal(details(bad).field, "ticketId");
    const out = await handleLaunchCall(req("t-1"), "analyse", { ...h.deps(), lookup });
    assert.equal(out.outcome, "launched");
  });

  it("panne imprévue : internal, journalisée sans jeton", async () => {
    const h = harness();
    seedTicket(h, "t-1");
    const lookup = async () => ({ role: "admin" });
    const err = await refusal(
      handleLaunchCall(
        { auth: { uid: "a", token: token("admin@example.com") }, data: { ticketId: "t-1" } },
        "analyse",
        {
          ...h.deps(),
          kit: async () => {
            throw new Error(`panne ${GH_TOKEN}`);
          },
          lookup,
        },
      ),
    );
    assert.equal(err.code, "internal");
    assert.equal(details(err).code, "internal");
    assert.equal(h.logs.length, 1);
  });
});

describe("passe horaire : ticket_status/launches remis au jour", () => {
  it("document absent : jour, compteur du jour et plafond écrits", async () => {
    const db = new FakeDb(() => NOW);
    db.seed(`ticket_quotas/launch_${DAY}`, { count: 3 });
    await refreshLaunchStatus(
      async () => db.kit(),
      () => NOW,
    );
    assert.deepEqual(db.read("ticket_status/launches"), {
      day: DAY,
      count_day: 3,
      month: "202611",
      count_month: 3,
      per_day: LAUNCHES_PER_DAY,
    });
    const writes = db.writes.length;
    await refreshLaunchStatus(
      async () => db.kit(),
      () => NOW,
    );
    assert.equal(db.writes.length, writes);
  });

  it("passe de minuit à Paris (0 * * * *) : jour suivant, compteur du jour à zéro", async () => {
    const db = new FakeDb(() => NOW);
    db.seed("ticket_status/launches", {
      day: DAY,
      count_day: 10,
      month: "202611",
      count_month: 12,
      per_day: LAUNCHES_PER_DAY,
    });
    db.seed(`ticket_quotas/launch_${DAY}`, { count: 10 });
    // 2026-11-14 à 00:00:30, heure de Paris (UTC+1) ; à 23:59:59 Paris, encore le 13.
    const before = Date.parse("2026-11-13T22:59:59Z");
    await refreshLaunchStatus(
      async () => db.kit(),
      () => before,
    );
    assert.equal(db.read("ticket_status/launches")?.day, DAY);
    const midnight = Date.parse("2026-11-13T23:00:30Z");
    await refreshLaunchStatus(
      async () => db.kit(),
      () => midnight,
    );
    assert.deepEqual(db.read("ticket_status/launches"), {
      day: "20261114",
      count_day: 0,
      month: "202611",
      count_month: 12,
      per_day: LAUNCHES_PER_DAY,
    });
  });
});
