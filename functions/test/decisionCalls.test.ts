// Callables des décisions de l'administrateur (ADR-008, T7, P53) : `validateTicket`,
// `refuseTicket`, `closeTicket` et `retryTicketSend`. Firestore en mémoire
// (`fakeFirestore.ts`), GitHub par un `fetch` simulé.

import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, it, mock } from "node:test";

import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import * as firestoreModule from "../src/firestore";
import {
  DECISION_TEXT_RAW_MAX_CHARS,
  REJECT_ISSUE_CLOSED,
  allowedDecisions,
} from "../src/tickets/decisionModel";
import { handleDecisionCall, handleRetrySendCall } from "../src/tickets/decisionCalls";
import type { FetchLike } from "../src/tickets/github";
import { FakeDb } from "./fakeFirestore";

const OWNER = 16348852;
const TOKEN = "github_pat_11AAAAAAAAAAAAAAAAAAAA_secretsecretsecretsecret";
const UPDATED = "2026-11-14T09:00:00Z";
const TEXT = "Hors du périmètre de l'application, texte témoin T7.";

let db: FakeDb;

beforeEach(() => {
  db = new FakeDb();
  mock.method(firestoreModule, "firestore", async () => db.kit());
});

afterEach(() => mock.restoreAll());

const ticket = () => db.read("tickets/t-1") ?? {};
const decisions = (): Array<Record<string, unknown> & { id: string }> =>
  [...db.docs.keys()]
    .filter((k) => k.startsWith("tickets/t-1/decisions/"))
    .map((k) => ({ ...db.read(k), id: k.split("/").pop() as string }));

function seedTicket(extra: Record<string, unknown>): void {
  db.seed("tickets/t-1", { github_issue_number: 12, github_updated_at: UPDATED, ...extra });
}

const admin = { role: "admin" };
const lookupOf = (member: Record<string, unknown> | null) => async () => member;

function req(data: Record<string, unknown>) {
  return {
    auth: {
      uid: "admin-uid",
      token: {
        email: "admin@example.com",
        email_verified: true,
        firebase: { sign_in_provider: "google.com" },
      },
    },
    data,
  };
}

interface Scene {
  state?: "open" | "closed";
  stateReason?: string | null;
  labels?: string[];
  comments?: Array<{ id: number; user: { id: number }; body: string }>;
  /** Statut rendu par la fermeture de l'Issue (PATCH). */
  closeStatus?: number;
  /** Statut rendu par la création de l'Issue (publication). */
  createIssueStatus?: number;
  /** Statut rendu par tout appel (jeton refusé : 401). */
  allStatus?: number;
}

/** GitHub simulé : Issue n° 12 ; les commentaires créés s'ajoutent à la liste. */
function fakeGithub(scene: Scene = {}): { fetch: FetchLike; calls: string[] } {
  const calls: string[] = [];
  const comments = [...(scene.comments ?? [])];
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  const fetch: FetchLike = async (url, init) => {
    const u = new URL(url);
    const path = u.pathname;
    const method = String(init.method);
    calls.push(`${method} ${path}`);
    if (scene.allStatus !== undefined) {
      return json(scene.allStatus, { message: "Bad credentials" });
    }
    if (method === "GET" && path.endsWith("/issues/12")) {
      return json(200, {
        number: 12,
        state: scene.state ?? "open",
        state_reason: scene.stateReason ?? null,
        labels: (scene.labels ?? ["source:app"]).map((name) => ({ name })),
        comments: comments.length,
        updated_at: UPDATED,
      });
    }
    const known = path.match(/\/issues\/comments\/(\d+)$/);
    if (method === "GET" && known !== null) {
      const c = comments.find((x) => x.id === Number(known[1]));
      return c === undefined ? json(404, { message: "Not Found" }) : json(200, c);
    }
    if (method === "GET" && path.endsWith("/issues/12/comments")) return json(200, comments);
    if (method === "GET" && path.endsWith("/issues/12/events")) return json(200, []);
    if (method === "POST" && path.endsWith("/issues/12/comments")) {
      const body = JSON.parse(String(init.body)) as { body: string };
      const id = 900 + comments.length;
      comments.push({ id, user: { id: OWNER }, body: body.body });
      return json(201, { id });
    }
    if (method === "POST" && path.endsWith("/issues/12/labels")) return json(200, []);
    if (method === "PATCH" && path.endsWith("/issues/12")) {
      return json(scene.closeStatus ?? 200, {});
    }
    // Liste des Issues lue avant une republication (`findIssueByReference`) : aucune.
    if (method === "GET" && path.endsWith("/issues")) return json(200, []);
    if (method === "POST" && path.endsWith("/issues")) {
      return json(scene.createIssueStatus ?? 201, { number: 34 });
    }
    return json(500, { message: `inattendu ${method} ${path}` });
  };
  return { fetch, calls };
}

const count = (calls: string[], prefix: string) => calls.filter((c) => c.startsWith(prefix)).length;
const posted = (calls: string[]) =>
  calls.filter((c) => c.startsWith("POST") && c.endsWith("/issues/12/comments")).length;

function decide(
  action: "validate" | "refuse" | "close",
  data: Record<string, unknown>,
  gh: { fetch: FetchLike },
  member: Record<string, unknown> | null = admin,
) {
  return handleDecisionCall(req(data), action, () => TOKEN, {
    lookup: lookupOf(member),
    fetchImpl: gh.fetch,
  });
}

function rejectsWith(code: string, machine: string, extra?: (d: Record<string, unknown>) => void) {
  return (err: HttpsError) => {
    assert.ok(err instanceof HttpsError);
    assert.equal(err.code, code);
    const details = err.details as Record<string, unknown>;
    assert.equal(details.code ?? details.field, machine);
    extra?.(details);
    return true;
  };
}

/** Sortie standard et d'erreur pendant `work` (journaux de `firebase-functions/logger`). */
async function captureLogs(work: () => Promise<unknown>): Promise<string> {
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
    await work().catch(() => undefined);
  } finally {
    process.stdout.write = out;
    process.stderr.write = err;
  }
  return lines.join("");
}

describe("callables de décision : accès et arguments (P30, P53)", () => {
  it("non admin refusé avant toute lecture des arguments et de Firestore", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub();
    for (const action of ["validate", "refuse", "close"] as const) {
      await assert.rejects(
        decide(action, { ticketId: "../x", text: 42 }, gh, { role: "brewer" }),
        (err: HttpsError) => err.code === "permission-denied",
      );
    }
    await assert.rejects(
      handleRetrySendCall(req({ ticketId: "../x" }), () => TOKEN, {
        lookup: lookupOf(null),
        fetchImpl: gh.fetch,
      }),
      (err: HttpsError) => err.code === "permission-denied",
    );
    await assert.rejects(
      handleDecisionCall({ data: { ticketId: "t-1" } }, "validate", () => TOKEN, {
        lookup: lookupOf(admin),
      }),
      (err: HttpsError) => err.code === "unauthenticated",
    );
    assert.equal(gh.calls.length, 0);
    assert.deepEqual(db.writes, []);
  });

  it("texte de 4 et de 4 001 caractères, texte d'espaces, texte absent : invalid-argument", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub();
    for (const text of ["1234", "m".repeat(4001), "         ", undefined, 42]) {
      await assert.rejects(
        decide("refuse", { ticketId: "t-1", text }, gh),
        rejectsWith("invalid-argument", "text"),
      );
    }
    await assert.rejects(
      decide("close", { ticketId: "t-1", text: "x".repeat(DECISION_TEXT_RAW_MAX_CHARS + 1) }, gh),
      rejectsWith("invalid-argument", "text"),
    );
    await assert.rejects(
      decide("refuse", { ticketId: "a".repeat(129), text: TEXT }, gh),
      rejectsWith("invalid-argument", "ticketId"),
    );
    assert.equal(gh.calls.length, 0);
    assert.deepEqual(db.writes, []);
  });

  it("texte de 4 000 caractères accepté", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const out = await decide("refuse", { ticketId: "t-1", text: "m".repeat(4000) }, fakeGithub());
    assert.equal(out.status, "refused");
  });
});

describe("callables de décision : préconditions (P42, P44, P53)", () => {
  it("ticket absent : not-found", async () => {
    await assert.rejects(
      decide("validate", { ticketId: "t-1" }, fakeGithub()),
      rejectsWith("not-found", "ticket_missing"),
    );
  });

  it("P42 : ticket reçu dont la liste stockée contient validate, validateTicket refusé", async () => {
    seedTicket({
      status: "received",
      allowed_decisions: ["validate", "refuse", "close", "answer"],
    });
    const gh = fakeGithub();
    await assert.rejects(
      decide("validate", { ticketId: "t-1" }, gh),
      rejectsWith("failed-precondition", "not_allowed"),
    );
    assert.equal(gh.calls.length, 0);
    assert.deepEqual(decisions(), []);
  });

  it("bail actif sur le ticket : decision_in_progress, rien publié", async () => {
    seedTicket({
      status: "received",
      allowed_decisions: allowedDecisions("received"),
      decision_lease_until: Timestamp.fromMillis(Date.now() + 60_000),
    });
    const gh = fakeGithub();
    await assert.rejects(
      decide("refuse", { ticketId: "t-1", text: TEXT }, gh),
      rejectsWith("failed-precondition", "decision_in_progress"),
    );
    assert.equal(gh.calls.length, 0);
  });

  it("Issue fermée sur GitHub : état appliqué, décision rejected, issue_closed", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub({ state: "closed", stateReason: "completed" });
    await assert.rejects(
      decide("refuse", { ticketId: "t-1", text: TEXT }, gh),
      rejectsWith("failed-precondition", "issue_closed", (d) =>
        assert.equal(d.reason, REJECT_ISSUE_CLOSED),
      ),
    );
    assert.equal(posted(gh.calls), 0);
    const [d] = decisions();
    assert.equal(d.state, "rejected");
    assert.equal(ticket().decision_lease_until, undefined);
  });
});

describe("callables de décision : application (P24, P26, P53)", () => {
  it("refuseTicket : commentaire sur gabarit, Issue fermée, historique écrit par le serveur", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub();
    const out = await decide("refuse", { ticketId: "t-1", text: TEXT, decisionId: "imposé" }, gh);
    assert.equal(out.changed, true);
    assert.equal(out.status, "refused");
    const [d] = decisions();
    assert.equal(out.changed && out.decisionId, d.id);
    assert.notEqual(d.id, "imposé");
    assert.equal(d.state, "applied");
    assert.equal(d.action, "refuse");
    assert.equal(d.text, TEXT);
    assert.equal(d.requested_by_uid, "admin-uid");
    assert.ok(d.requested_at instanceof Timestamp);
    assert.deepEqual(d.steps_done, ["comment", "close"]);
    const t = ticket();
    assert.equal(t.status, "refused");
    assert.equal(t.reply_text, TEXT);
    assert.deepEqual(t.allowed_decisions, []);
    assert.equal(t.decision_lease_until, undefined);
    assert.equal(posted(gh.calls), 1);
  });

  it("second appel après succès : changed false, rien publié", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub();
    await decide("close", { ticketId: "t-1", text: TEXT }, gh);
    const before = gh.calls.length;
    const again = await decide("close", { ticketId: "t-1", text: TEXT }, gh);
    assert.deepEqual(again, { status: "closed", changed: false });
    assert.equal(gh.calls.length, before);
    assert.equal(decisions().length, 1);
  });

  it("validateTicket : second appel après succès, changed false sans appel GitHub", async () => {
    seedTicket({ status: "analyzed", allowed_decisions: allowedDecisions("analyzed") });
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] });
    const first = await decide("validate", { ticketId: "t-1" }, gh);
    assert.equal(first.changed, true);
    const before = gh.calls.length;
    assert.deepEqual(await decide("validate", { ticketId: "t-1" }, gh), {
      status: "validated",
      changed: false,
    });
    assert.equal(gh.calls.length, before);
  });

  it("deux appels simultanés : un seul publie", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub();
    const results = await Promise.allSettled([
      decide("refuse", { ticketId: "t-1", text: TEXT }, gh),
      decide("refuse", { ticketId: "t-1", text: TEXT }, gh),
    ]);
    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    assert.equal(
      ((rejected[0] as PromiseRejectedResult).reason as HttpsError).code,
      "failed-precondition",
    );
    assert.equal(posted(gh.calls), 1);
    assert.equal(decisions().length, 1);
  });

  it("échec partiel : commentaire publié, Issue ouverte, aborted et partial", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub({ closeStatus: 502 });
    await assert.rejects(
      decide("refuse", { ticketId: "t-1", text: TEXT }, gh),
      rejectsWith("aborted", "refuse_partial", (d) => assert.equal(d.partial, true)),
    );
    const [d] = decisions();
    assert.equal(d.state, "failed");
    assert.deepEqual(d.steps_done, ["comment"]);
    assert.equal(typeof d.comment_id, "number");
    assert.equal(ticket().decision_lease_until, undefined);
    assert.equal(ticket().status, "received");
  });

  it("reprise après un échec partiel : même identifiant, commentaire reconnu, texte stocké gardé", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const failing = fakeGithub({ closeStatus: 502 });
    await assert.rejects(decide("refuse", { ticketId: "t-1", text: TEXT }, failing));
    const [first] = decisions();
    // Même GitHub (le commentaire publié y reste), fermeture rétablie.
    const comments = [
      {
        id: first.comment_id as number,
        user: { id: OWNER },
        body: `Réponse : ${TEXT}\n\nDécision ${first.id}`,
      },
    ];
    const gh = fakeGithub({ comments });
    const out = await decide("refuse", { ticketId: "t-1", text: "Un autre texte reçu." }, gh);
    assert.equal(out.changed && out.decisionId, first.id);
    // Le texte reçu diffère du motif publié : la réponse le dit (P53).
    assert.equal(out.changed && out.textKept, true);
    assert.equal(posted(gh.calls), 0);
    const [d] = decisions();
    assert.equal(decisions().length, 1);
    assert.equal(d.state, "applied");
    assert.equal(d.text, TEXT);
    assert.equal(ticket().status, "refused");
    assert.equal(ticket().reply_text, TEXT);
  });

  it("reprise d'une décision applying au bail expiré : même identifiant, commentaire non republié", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    db.seed("tickets/t-1/decisions/dec_old", {
      action: "close",
      text: TEXT,
      state: "applying",
      requested_by_uid: "admin-uid",
      requested_at: Timestamp.fromMillis(Date.now() - 600_000),
      lease_until: Timestamp.fromMillis(Date.now() - 300_000),
    });
    const gh = fakeGithub({
      comments: [{ id: 77, user: { id: OWNER }, body: `Réponse : ${TEXT}\n\nDécision dec_old` }],
    });
    const out = await decide("close", { ticketId: "t-1", text: TEXT }, gh);
    assert.equal(out.changed && out.decisionId, "dec_old");
    assert.equal(posted(gh.calls), 0);
    assert.equal(count(gh.calls, "POST /repos/ChinaFred/KassBeer/issues/12/labels"), 1);
    assert.equal(db.read("tickets/t-1/decisions/dec_old")?.state, "applied");
    assert.equal(db.read("tickets/t-1/decisions/dec_old")?.comment_id, 77);
  });

  it("reprise avec le même texte : textKept faux", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    await assert.rejects(
      decide("refuse", { ticketId: "t-1", text: TEXT }, fakeGithub({ closeStatus: 502 })),
    );
    const [first] = decisions();
    const gh = fakeGithub({
      comments: [
        {
          id: first.comment_id as number,
          user: { id: OWNER },
          body: `Réponse : ${TEXT}\n\nDécision ${first.id}`,
        },
      ],
    });
    const out = await decide("refuse", { ticketId: "t-1", text: TEXT }, gh);
    assert.equal(out.changed && out.textKept, false);
  });

  it("reprise sans steps_done, commentaire retrouvé : text de la décision = texte publié", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    db.seed("tickets/t-1/decisions/dec_old", {
      action: "refuse",
      text: "Texte enregistré par l'appel interrompu.",
      state: "applying",
      requested_by_uid: "admin-uid",
      requested_at: Timestamp.fromMillis(Date.now() - 600_000),
      lease_until: Timestamp.fromMillis(Date.now() - 300_000),
    });
    const gh = fakeGithub({
      comments: [{ id: 78, user: { id: OWNER }, body: `Réponse : ${TEXT}\n\nDécision dec_old` }],
    });
    const out = await decide("refuse", { ticketId: "t-1", text: "Encore un autre texte." }, gh);
    assert.equal(posted(gh.calls), 0);
    assert.equal(out.changed && out.textKept, true);
    const d = db.read("tickets/t-1/decisions/dec_old");
    assert.equal(d?.state, "applied");
    assert.equal(d?.text, TEXT);
    assert.equal(ticket().reply_text, TEXT);
  });

  it("motif de plus de 3 000 caractères : reply_text entier (REPLY_MAX_CHARS 4 000)", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const long = "Motif détaillé. ".repeat(200).trim();
    assert.ok(Array.from(long).length > 3000);
    await decide("refuse", { ticketId: "t-1", text: long }, fakeGithub());
    assert.equal(ticket().reply_text, long);
  });

  it("jeton refusé (401) : github_token, token_invalid_since, décision failed, bail retiré, jeton absent des journaux", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    let error: unknown;
    const logs = await captureLogs(async () => {
      try {
        await decide("refuse", { ticketId: "t-1", text: TEXT }, fakeGithub({ allStatus: 401 }));
      } catch (err) {
        error = err;
      }
    });
    assert.ok(error instanceof HttpsError);
    assert.equal((error as HttpsError).code, "failed-precondition");
    assert.equal(((error as HttpsError).details as { code: string }).code, "github_token");
    assert.ok(db.read("ticket_status/github")?.token_invalid_since instanceof Timestamp);
    const [d] = decisions();
    assert.equal(d.state, "failed");
    assert.equal(ticket().decision_lease_until, undefined);
    assert.equal(ticket().status, "received");
    assert.ok(!logs.includes(TOKEN));
    assert.ok(!logs.includes("texte témoin T7"));
  });

  it("le texte n'entre dans aucun journal", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const logs = await captureLogs(() =>
      decide("refuse", { ticketId: "t-1", text: TEXT }, fakeGithub({ closeStatus: 502 })),
    );
    assert.ok(logs.length > 0);
    assert.ok(!logs.includes("texte témoin T7"));
    assert.ok(!logs.includes(TOKEN));
  });
});

describe("retryTicketSend (P53)", () => {
  function seedFailed(extra: Record<string, unknown> = {}): void {
    db.seed("tickets/t-1", {
      type: "bug",
      title: "Le minuteur saute",
      description: "Le minuteur de l'ébullition repart à zéro.",
      screen: "/brassins/:id/jour",
      platform: "android",
      author_uid: "brewer-a",
      created_at: Timestamp.fromMillis(Date.now() - 86_400_000),
      status: "send_failed",
      send_attempts: 10,
      send_quota_day: "20261114",
      last_send_error: "GitHub HTTP 500",
      allowed_decisions: [],
      retry_requested_at: Timestamp.fromMillis(Date.now() - 3_600_000),
      ...extra,
    });
  }
  const retry = (gh: { fetch: FetchLike }) =>
    handleRetrySendCall(req({ ticketId: "t-1" }), () => TOKEN, {
      lookup: lookupOf(admin),
      fetchImpl: gh.fetch,
    });

  it("ticket received : changed false, rien écrit, rien publié", async () => {
    seedTicket({ status: "received", allowed_decisions: allowedDecisions("received") });
    const gh = fakeGithub();
    assert.deepEqual(await retry(gh), { status: "received", changed: false, issueNumber: 12 });
    assert.deepEqual(db.writes, []);
    assert.equal(gh.calls.length, 0);
  });

  it("ticket send_failed : remis à zéro, publié pendant l'appel", async () => {
    seedFailed();
    const gh = fakeGithub();
    const out = await retry(gh);
    assert.deepEqual(out, { status: "received", changed: true, issueNumber: 34 });
    const t = ticket();
    assert.equal(t.status, "received");
    assert.equal(t.github_issue_number, 34);
    assert.equal(t.send_attempts, 0);
    assert.ok(t.send_retried_at instanceof Timestamp);
    assert.equal(t.retry_requested_at, undefined);
    assert.equal(count(gh.calls, "POST /repos/ChinaFred/KassBeer/issues"), 1);
  });

  it("essai en échec : ticket pending, la tâche horaire continue", async () => {
    seedFailed();
    const out = await retry(fakeGithub({ createIssueStatus: 502 }));
    assert.equal(out.status, "pending");
    assert.equal(out.changed, true);
    assert.equal(ticket().send_attempts, 1);
  });

  it("jeton refusé (401) : github_token, ticket pending, token_invalid_since", async () => {
    seedFailed();
    await assert.rejects(
      retry(fakeGithub({ allStatus: 401 })),
      rejectsWith("failed-precondition", "github_token"),
    );
    assert.equal(ticket().status, "pending");
    assert.ok(db.read("ticket_status/github")?.token_invalid_since instanceof Timestamp);
  });

  it("ticket absent : not-found", async () => {
    await assert.rejects(retry(fakeGithub()), rejectsWith("not-found", "ticket_missing"));
  });
});
