// Écritures de `validated_by_app_at` (ADR-008, T4, décision du 2026-11-13) : posé par
// `validateTicket` (T7), effacé par Refuser, Clore, « Répondre » et toute
// Issue qui sort le ticket de `validated` et `in_progress`. Firestore en mémoire
// (`fakeFirestore.ts`), GitHub par un `fetch` simulé.

import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, it, mock } from "node:test";

import { Timestamp, type DocumentSnapshot } from "firebase-admin/firestore";

import * as firestoreModule from "../src/firestore";
import { answerTicket } from "../src/tickets/answer";
import { allowedDecisions } from "../src/tickets/decisionModel";
import { decideTicket } from "../src/tickets/decisions";
import { githubClient, type FetchLike } from "../src/tickets/github";
import { applyIssue } from "../src/tickets/issueState";
import type { IssueView } from "../src/tickets/model";
import { ALLOWED_DECISIONS_VERSION, backfillAllowedDecisions } from "../src/tickets/sync";
import { FakeDb } from "./fakeFirestore";

const OWNER = 16348852;
const TOKEN = "github_pat_11AAAAAAAAAAAAAAAAAAAA_secretsecretsecretsecret";
const UPDATED = "2026-11-12T09:00:00Z";
const VALIDATED_AT = Timestamp.fromMillis(Date.parse("2026-11-11T10:00:00Z"));

let db: FakeDb;

beforeEach(() => {
  db = new FakeDb();
  mock.method(firestoreModule, "firestore", async () => db.kit());
});

afterEach(() => mock.restoreAll());

const ticket = () => db.read("tickets/t-1") ?? {};

function seedTicket(extra: Record<string, unknown>): void {
  db.seed("tickets/t-1", {
    github_issue_number: 12,
    github_updated_at: UPDATED,
    ...extra,
  });
}

/** GitHub simulé : Issue n° 12 ouverte, étiquettes données, commentaires donnés. */
function fakeGithub(issue: {
  labels: string[];
  state?: "open" | "closed";
  comments?: Array<{ id: number; user: { id: number }; body: string }>;
}): { fetch: FetchLike; calls: string[] } {
  const calls: string[] = [];
  const comments = issue.comments ?? [];
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  const fetch: FetchLike = async (url, init) => {
    const path = new URL(url).pathname;
    const method = String(init.method);
    calls.push(`${method} ${path}`);
    if (method === "GET" && path.endsWith("/issues/12")) {
      return json(200, {
        number: 12,
        state: issue.state ?? "open",
        state_reason: null,
        labels: issue.labels.map((name) => ({ name })),
        comments: comments.length,
        updated_at: UPDATED,
      });
    }
    if (method === "GET" && path.endsWith("/issues/12/comments")) return json(200, comments);
    if (method === "POST" && path.endsWith("/issues/12/comments")) return json(201, { id: 900 });
    if (method === "POST" && path.endsWith("/issues/12/labels")) return json(200, []);
    if (method === "DELETE" && path.includes("/issues/12/labels/")) return json(200, []);
    if (method === "PATCH" && path.endsWith("/issues/12")) return json(200, {});
    return json(500, { message: `inattendu ${method} ${path}` });
  };
  return { fetch, calls };
}

function issue(extra: Partial<IssueView>): IssueView {
  return {
    number: 12,
    state: "open",
    stateReason: null,
    labels: ["source:app"],
    isPullRequest: false,
    updatedAt: UPDATED,
    comments: 0,
    ...extra,
  };
}

async function runApplyIssue(view: IssueView): Promise<void> {
  const snap = await db.collection("tickets").doc("t-1").get();
  const client = githubClient(TOKEN, fakeGithub({ labels: view.labels }).fetch);
  await applyIssue(client, snap as unknown as DocumentSnapshot, view);
}

describe("validated_by_app_at : applyIssue", () => {
  it("validé dans l'application, Issue fermée (not_planned) : champ null, pas de lancement", async () => {
    seedTicket({
      status: "validated",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: allowedDecisions("validated", true),
    });
    await runApplyIssue(issue({ state: "closed", stateReason: "not_planned" }));
    const t = ticket();
    assert.equal(t.status, "refused");
    assert.equal(t.validated_by_app_at, null);
    assert.equal((t.allowed_decisions as string[]).includes("launch_development"), false);
  });

  it("validé dans l'application, Issue revenue à statut:analysé : ticket validé, champ gardé (un statut ne recule pas)", async () => {
    seedTicket({
      status: "validated",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: allowedDecisions("validated", true),
    });
    await runApplyIssue(issue({ labels: ["source:app", "statut:analysé"] }));
    const t = ticket();
    assert.equal(t.status, "validated");
    assert.ok(t.validated_by_app_at instanceof Timestamp);
    assert.ok((t.allowed_decisions as string[]).includes("launch_development"));
  });

  it("ticket clos au champ resté posé, Issue rouverte à statut:analysé : champ null, pas de lancement", async () => {
    seedTicket({
      status: "closed",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: [],
    });
    await runApplyIssue(issue({ labels: ["source:app", "statut:analysé"] }));
    const t = ticket();
    assert.equal(t.status, "analyzed");
    assert.equal(t.validated_by_app_at, null);
    assert.deepEqual(t.allowed_decisions, allowedDecisions("analyzed"));
    assert.equal((t.allowed_decisions as string[]).includes("launch_development"), false);
  });

  it("ticket reçu au champ resté posé, `validé` posé sur GitHub : champ null, pas de lancement", async () => {
    seedTicket({
      status: "received",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: allowedDecisions("received"),
    });
    await runApplyIssue(issue({ labels: ["source:app", "validé"] }));
    const t = ticket();
    assert.equal(t.status, "validated");
    assert.equal(t.validated_by_app_at, null);
    assert.deepEqual(t.allowed_decisions, allowedDecisions("validated", false));
    assert.equal((t.allowed_decisions as string[]).includes("launch_development"), false);
  });

  it("validated → in_progress : champ gardé", async () => {
    seedTicket({
      status: "validated",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: allowedDecisions("validated", true),
    });
    await runApplyIssue(issue({ labels: ["source:app", "validé", "statut:en-cours"] }));
    const t = ticket();
    assert.equal(t.status, "in_progress");
    assert.ok(t.validated_by_app_at instanceof Timestamp);
    assert.equal((t.validated_by_app_at as Timestamp).toMillis(), VALIDATED_AT.toMillis());
    assert.deepEqual(t.allowed_decisions, allowedDecisions("in_progress", true));
  });
});

describe("validated_by_app_at : decideTicket", () => {
  const TEXT = "Hors du périmètre de l'application.";

  it("validate : champ posé, « Lancer le développement » offert", async () => {
    seedTicket({ status: "analyzed", allowed_decisions: allowedDecisions("analyzed") });
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] });
    const out = await decideTicket("t-1", "validate", null, "admin-uid", TOKEN, gh.fetch);
    assert.equal(out.changed, true);
    const t = ticket();
    assert.equal(t.status, "validated");
    assert.ok(t.validated_by_app_at instanceof Timestamp);
    assert.ok((t.allowed_decisions as string[]).includes("launch_development"));
    assert.equal((t.allowed_decisions as string[]).includes("validate"), false);
  });

  it("validate sur un ticket validé sur GitHub seul : champ posé", async () => {
    seedTicket({
      status: "validated",
      validated_by_app_at: null,
      allowed_decisions: allowedDecisions("validated", false),
    });
    const gh = fakeGithub({ labels: ["source:app", "validé"] });
    await decideTicket("t-1", "validate", null, "admin-uid", TOKEN, gh.fetch);
    assert.ok(ticket().validated_by_app_at instanceof Timestamp);
  });

  for (const action of ["refuse", "close"] as const) {
    it(`${action} sur un ticket validé dans l'application : champ null`, async () => {
      seedTicket({
        status: "validated",
        validated_by_app_at: VALIDATED_AT,
        allowed_decisions: allowedDecisions("validated", true),
      });
      const gh = fakeGithub({ labels: ["source:app", "validé"] });
      await decideTicket("t-1", action, TEXT, "admin-uid", TOKEN, gh.fetch);
      const t = ticket();
      assert.equal(t.status, action === "refuse" ? "refused" : "closed");
      assert.equal(t.validated_by_app_at, null);
      assert.deepEqual(t.allowed_decisions, []);
    });
  }
});

describe("validated_by_app_at : « Répondre »", () => {
  it("validated → received : champ null, pas de lancement du développement", async () => {
    seedTicket({
      status: "validated",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: allowedDecisions("validated", true),
    });
    const gh = fakeGithub({
      labels: ["source:app", "statut:analysé", "validé"],
      comments: [{ id: 5, user: { id: OWNER }, body: "## Analyse\n\nTexte de l'analyse." }],
    });
    const out = await answerTicket("t-1", "Précisions de l'administrateur.", TOKEN, gh.fetch);
    assert.equal(out.status, "received");
    const t = ticket();
    assert.equal(t.status, "received");
    assert.equal(t.validated_by_app_at, null);
    assert.deepEqual(t.allowed_decisions, allowedDecisions("received"));
    assert.equal((t.allowed_decisions as string[]).includes("launch_development"), false);
  });
});

describe("validated_by_app_at : report des décisions permises (sync.ts)", () => {
  it("ticket received au champ resté posé : liste de received, sans lancement du développement", async () => {
    seedTicket({
      status: "received",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: ["refuse", "close", "answer", "launch_development"],
    });
    await backfillAllowedDecisions();
    const t = ticket();
    assert.deepEqual(t.allowed_decisions, allowedDecisions("received"));
    assert.equal((t.allowed_decisions as string[]).includes("launch_development"), false);
    assert.equal(
      db.read("ticket_status/github")?.allowed_decisions_backfill_version,
      ALLOWED_DECISIONS_VERSION,
    );
  });

  it("ticket validated au champ posé : liste avec lancement du développement", async () => {
    seedTicket({
      status: "validated",
      validated_by_app_at: VALIDATED_AT,
      allowed_decisions: allowedDecisions("validated", false),
    });
    await backfillAllowedDecisions();
    assert.deepEqual(ticket().allowed_decisions, allowedDecisions("validated", true));
  });
});
