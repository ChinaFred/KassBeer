import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  FAILURE_ISSUE_MISSING,
  FAILURE_RATE_LIMIT,
  FAILURE_TOKEN,
  REJECT_INVALID,
  REJECT_LEASE_TAKEN,
  REJECT_NO_ISSUE,
  REJECT_NOT_ALLOWED,
  REJECT_TICKET_MISSING,
  allowedDecisions,
  allowedDecisionsUpToDate,
  commentCarriesDecision,
  decisionClaimVerdict,
  decisionCommentBody,
  decisionPlan,
  failureReason,
  isPlausibleDecisionId,
  isResumableByPass,
  isRetryRequest,
  isValidatedByApp,
  keepsAppValidation,
  PENDING_DECISION_GRACE_MS,
  stalePendingCutoffMs,
  replyTextOfComment,
  statusAfterDecision,
  textFitsAction,
  type DecisionClaimInput,
} from "../src/tickets/decisionModel";
import { runOnGithub, type Claim, type Refs } from "../src/tickets/decisions";
import { githubClient, type FetchLike } from "../src/tickets/github";
import { TICKET_STATUSES, lastReply, type CommentView } from "../src/tickets/model";

const OWNER = 16348852;
const NOW = Date.parse("2026-11-11T10:00:00Z");
const TOKEN = "github_pat_11AAAAAAAAAAAAAAAAAAAA_secretsecretsecretsecret";

describe("décisions permises par statut (P26)", () => {
  it("received : refuser, clore, répondre, lancer l'analyse ; pas valider (T4, P42)", () =>
    assert.deepEqual(allowedDecisions("received"), [
      "refuse",
      "close",
      "answer",
      "launch_analysis",
    ]));
  it("analyzed : valider, refuser, clore, répondre", () =>
    assert.deepEqual(allowedDecisions("analyzed"), ["validate", "refuse", "close", "answer"]));
  it("validated dans l'application : refuser, clore, répondre, lancer le développement ; in_progress : refuser, clore", () => {
    assert.deepEqual(allowedDecisions("validated", true), [
      "refuse",
      "close",
      "answer",
      "launch_development",
    ]);
    assert.deepEqual(allowedDecisions("in_progress"), ["refuse", "close"]);
  });
  it("validated sur GitHub seul : valider, refuser, clore, répondre ; pas de lancement (2026-11-13)", () =>
    assert.deepEqual(allowedDecisions("validated"), ["validate", "refuse", "close", "answer"]));
  it("validation de l'application : posée, gardée en validated et in_progress seuls", () => {
    assert.equal(isValidatedByApp(null), false);
    assert.equal(isValidatedByApp(undefined), false);
    assert.equal(isValidatedByApp({ seconds: 1 }), true);
    assert.deepEqual(
      TICKET_STATUSES.filter((s) => keepsAppValidation(s)),
      ["validated", "in_progress"],
    );
  });
  it("autres statuts : aucune", () => {
    for (const s of TICKET_STATUSES) {
      if (["received", "analyzed", "validated", "in_progress"].includes(s)) continue;
      assert.deepEqual(allowedDecisions(s), [], s);
    }
    assert.deepEqual(allowedDecisions(undefined), []);
  });
  it("liste à jour : même contenu, même ordre", () => {
    assert.equal(allowedDecisionsUpToDate(["refuse", "close"], "in_progress"), true);
    assert.equal(allowedDecisionsUpToDate(["close", "refuse"], "in_progress"), false);
    assert.equal(allowedDecisionsUpToDate(["refuse", "close"], "validated"), false);
    assert.equal(
      allowedDecisionsUpToDate(["validate", "refuse", "close", "answer"], "validated", true),
      false,
    );
    assert.equal(allowedDecisionsUpToDate(undefined, "refused"), false);
    assert.equal(allowedDecisionsUpToDate([], "refused"), true);
    assert.equal(allowedDecisionsUpToDate(["validate"], "refused"), false);
  });
  it("statut visé par chaque action", () => {
    assert.equal(statusAfterDecision("validate"), "validated");
    assert.equal(statusAfterDecision("refuse"), "refused");
    assert.equal(statusAfterDecision("close"), "closed");
  });
});

function input(
  decision: Partial<DecisionClaimInput["decision"]> = {},
  ticket: Partial<NonNullable<DecisionClaimInput["ticket"]>> | null = {},
): DecisionClaimInput {
  return {
    decision: {
      state: "pending",
      action: "refuse",
      text: "Hors du périmètre de l'application.",
      leaseUntilMs: null,
      retryRequested: false,
      ...decision,
    },
    ticket:
      ticket === null
        ? null
        : {
            status: "received",
            allowedDecisions: ["refuse", "close", "answer", "launch_analysis"],
            leaseUntilMs: null,
            issueNumber: 12,
            ...ticket,
          },
    nowMs: NOW,
  };
}

describe("prise d'une décision (transitions)", () => {
  it("pending, action permise : prise", () =>
    assert.deepEqual(decisionClaimVerdict(input()), {
      kind: "claim",
      action: "refuse",
      issueNumber: 12,
      resumed: false,
    }));

  it("applied et rejected : rejeu sans effet", () => {
    assert.equal(decisionClaimVerdict(input({ state: "applied" })).kind, "skip");
    assert.equal(decisionClaimVerdict(input({ state: "rejected" })).kind, "skip");
  });

  it("applying au bail actif : rien ; au bail expiré : reprise", () => {
    assert.deepEqual(decisionClaimVerdict(input({ state: "applying", leaseUntilMs: NOW + 1 })), {
      kind: "skip",
      why: "in_progress",
    });
    const resumed = decisionClaimVerdict(input({ state: "applying", leaseUntilMs: NOW - 1 }));
    assert.equal(resumed.kind, "claim");
    assert.equal(resumed.kind === "claim" && resumed.resumed, true);
  });

  it("failed : rien sans reprise demandée, reprise avec", () => {
    assert.deepEqual(decisionClaimVerdict(input({ state: "failed" })), {
      kind: "skip",
      why: "failed_without_retry",
    });
    assert.equal(
      decisionClaimVerdict(input({ state: "failed", retryRequested: true })).kind,
      "claim",
    );
  });

  it("état inconnu : rien", () =>
    assert.equal(decisionClaimVerdict(input({ state: "done" })).kind, "skip"));

  it("action hors liste du statut : rejected", () =>
    assert.deepEqual(
      decisionClaimVerdict(
        input(
          { action: "validate", text: undefined },
          { status: "validated", allowedDecisions: ["refuse", "close"] },
        ),
      ),
      { kind: "reject", reason: REJECT_NOT_ALLOWED },
    ));

  it("P42 : received dont la liste stockée (T3) contient validate, Valider rejeté", () =>
    assert.deepEqual(
      decisionClaimVerdict(
        input(
          { action: "validate", text: undefined },
          { status: "received", allowedDecisions: ["validate", "refuse", "close", "answer"] },
        ),
      ),
      { kind: "reject", reason: REJECT_NOT_ALLOWED },
    ));

  it("validated sur GitHub seul : Valider pris ; déjà validé dans l'application : rejeté", () => {
    assert.deepEqual(
      decisionClaimVerdict(
        input(
          { action: "validate", text: undefined },
          { status: "validated", allowedDecisions: allowedDecisions("validated") },
        ),
      ),
      { kind: "claim", action: "validate", issueNumber: 12, resumed: false },
    );
    assert.deepEqual(
      decisionClaimVerdict(
        input(
          { action: "validate", text: undefined },
          {
            status: "validated",
            allowedDecisions: allowedDecisions("validated"),
            validatedByAppAt: { seconds: 1 },
          },
        ),
      ),
      { kind: "reject", reason: REJECT_NOT_ALLOWED },
    );
  });

  it("P42 : analyzed, Valider pris", () =>
    assert.deepEqual(
      decisionClaimVerdict(
        input(
          { action: "validate", text: undefined },
          { status: "analyzed", allowedDecisions: allowedDecisions("analyzed") },
        ),
      ),
      { kind: "claim", action: "validate", issueNumber: 12, resumed: false },
    ));

  it("P42 : action absente de la liste stockée mais permise par la règle, rejetée", () =>
    assert.deepEqual(
      decisionClaimVerdict(
        input(
          { action: "validate", text: undefined },
          { status: "analyzed", allowedDecisions: ["refuse", "close"] },
        ),
      ),
      { kind: "reject", reason: REJECT_NOT_ALLOWED },
    ));

  it("allowed_decisions absent : rejected", () =>
    assert.deepEqual(decisionClaimVerdict(input({}, { allowedDecisions: undefined })), {
      kind: "reject",
      reason: REJECT_NOT_ALLOWED,
    }));

  it("bail d'une autre décision actif : rejected ; bail expiré : prise", () => {
    assert.deepEqual(decisionClaimVerdict(input({}, { leaseUntilMs: NOW + 1000 })), {
      kind: "reject",
      reason: REJECT_LEASE_TAKEN,
    });
    assert.equal(decisionClaimVerdict(input({}, { leaseUntilMs: NOW - 1000 })).kind, "claim");
  });

  it("ticket absent ou sans Issue : rejected", () => {
    assert.deepEqual(decisionClaimVerdict(input({}, null)), {
      kind: "reject",
      reason: REJECT_TICKET_MISSING,
    });
    assert.deepEqual(decisionClaimVerdict(input({}, { issueNumber: null })), {
      kind: "reject",
      reason: REJECT_NO_ISSUE,
    });
  });

  it("action ou texte illisible : rejected", () => {
    for (const d of [
      { action: "delete" },
      { action: "validate", text: "un motif" },
      { action: "refuse", text: undefined },
      { action: "close", text: "     " },
      { action: "close", text: "x".repeat(2001) },
    ]) {
      assert.deepEqual(decisionClaimVerdict(input(d)), { kind: "reject", reason: REJECT_INVALID });
    }
  });

  it("reprise sur un ticket déjà au statut visé : prise (passe horaire passée avant)", () => {
    const retried = input(
      { state: "failed", retryRequested: true },
      { status: "refused", allowedDecisions: [] },
    );
    assert.equal(decisionClaimVerdict(retried).kind, "claim");
    // Une première prise sur un ticket déjà refusé est rejetée.
    assert.equal(
      decisionClaimVerdict(input({}, { status: "refused", allowedDecisions: [] })).kind,
      "reject",
    );
  });

  it("texte : présent pour refuse et close, absent pour validate", () => {
    assert.equal(textFitsAction("validate", undefined), true);
    assert.equal(textFitsAction("validate", "texte"), false);
    assert.equal(textFitsAction("refuse", "Motif valable"), true);
    assert.equal(textFitsAction("close", "x".repeat(2000)), true);
    assert.equal(textFitsAction("close", "🍺".repeat(2000)), true);
  });

  it("reprise demandée : retry_requested_at posé après et changé", () => {
    assert.equal(isRetryRequest(null, NOW), true);
    assert.equal(isRetryRequest(NOW - 5, NOW), true);
    assert.equal(isRetryRequest(NOW, NOW), false);
    assert.equal(isRetryRequest(NOW, null), false);
    assert.equal(isRetryRequest(null, null), false);
  });

  it("identifiant de décision : [A-Za-z0-9_-]{1,128}", () => {
    assert.equal(isPlausibleDecisionId("aB3_x-9"), true);
    assert.equal(isPlausibleDecisionId("a/b"), false);
    assert.equal(isPlausibleDecisionId(""), false);
    assert.equal(isPlausibleDecisionId("a".repeat(129)), false);
  });
});

describe("gabarit du commentaire (P24)", () => {
  const body = decisionCommentBody(
    "Hors périmètre. Écrivez à jean@exemple.fr ou @quelquun, voir #12. <img src=x> ![i](http://x)",
    "dec_1",
  );

  it("« Réponse : <texte> », ligne vide, « Décision <id> »", () => {
    assert.match(body, /^Réponse : Hors périmètre\./);
    assert.match(body, /\n\nDécision dec_1$/);
  });

  it("texte nettoyé : ni adresse, ni mention, ni renvoi, ni balisage actif", () => {
    assert.ok(!body.includes("exemple.fr"));
    assert.ok(body.includes("[adresse retirée]"));
    assert.ok(!/@quelquun/.test(body));
    assert.ok(!/#12/.test(body));
    assert.ok(!body.includes("<img"));
    assert.ok(!body.includes("!["));
  });

  it("reply_text égal à celui que la passe horaire relira", () => {
    const stored = replyTextOfComment(body, OWNER, 2000);
    const relu = lastReply(
      [{ id: 1, authorId: OWNER, body, createdAt: null, updatedAt: null }],
      OWNER,
      2000,
    );
    assert.equal(stored, relu?.text);
    assert.ok(stored !== null && !stored.includes("Décision dec_1"));
    assert.ok(stored !== null && stored.startsWith("Hors périmètre."));
  });
});

describe("reconnaissance de ce qui est fait (P26)", () => {
  const mine: CommentView = {
    id: 7,
    authorId: OWNER,
    body: "Réponse : Hors périmètre.\n\nDécision dec_1",
    createdAt: null,
    updatedAt: null,
  };

  it("commentaire du propriétaire avec la ligne : reconnu", () =>
    assert.equal(commentCarriesDecision(mine, "dec_1", OWNER), true));
  it("fin de ligne Windows : reconnu", () =>
    assert.equal(
      commentCarriesDecision(
        { ...mine, body: "Réponse : x\r\n\r\nDécision dec_1" },
        "dec_1",
        OWNER,
      ),
      true,
    ));
  it("autre décision, ou ligne dans une phrase : non reconnu", () => {
    assert.equal(commentCarriesDecision(mine, "dec_2", OWNER), false);
    assert.equal(
      commentCarriesDecision({ ...mine, body: "Voir Décision dec_1 plus haut" }, "dec_1", OWNER),
      false,
    );
  });
  it("même ligne écrite par un autre compte : non reconnu", () =>
    assert.equal(commentCarriesDecision({ ...mine, authorId: 999 }, "dec_1", OWNER), false));

  const open = { state: "open" as const, stateReason: null, labels: ["source:app"] };

  it("validate : étiquette validé à poser, ou déjà posée", () => {
    assert.deepEqual(decisionPlan("validate", open, false), {
      kind: "apply",
      comment: false,
      label: "validé",
      close: null,
    });
    assert.deepEqual(decisionPlan("validate", { ...open, labels: ["validé"] }, false), {
      kind: "apply",
      comment: false,
      label: null,
      close: null,
    });
  });

  it("refuse : commentaire puis fermeture not_planned ; commentaire déjà publié sauté", () => {
    assert.deepEqual(decisionPlan("refuse", open, false), {
      kind: "apply",
      comment: true,
      label: null,
      close: "not_planned",
    });
    assert.deepEqual(decisionPlan("refuse", open, true), {
      kind: "apply",
      comment: false,
      label: null,
      close: "not_planned",
    });
  });

  it("close : commentaire, étiquette statut:clos, fermeture completed ; étiquette posée sautée", () => {
    assert.deepEqual(decisionPlan("close", open, false), {
      kind: "apply",
      comment: true,
      label: "statut:clos",
      close: "completed",
    });
    assert.deepEqual(decisionPlan("close", { ...open, labels: ["statut:clos"] }, true), {
      kind: "apply",
      comment: false,
      label: null,
      close: "completed",
    });
  });

  it("Issue fermée par cette décision (essai interrompu) : rien à refaire", () => {
    const nothing = { kind: "apply", comment: false, label: null, close: null };
    assert.deepEqual(
      decisionPlan("refuse", { state: "closed", stateReason: "not_planned", labels: [] }, true),
      nothing,
    );
    assert.deepEqual(
      decisionPlan(
        "close",
        { state: "closed", stateReason: "completed", labels: ["statut:clos"] },
        true,
      ),
      nothing,
    );
  });

  it("Issue fermée par un autre geste : rejected (cas « déjà clos sur GitHub »)", () => {
    const delivered = { state: "closed" as const, stateReason: "completed", labels: [] };
    assert.deepEqual(decisionPlan("validate", delivered, false), { kind: "reject_closed" });
    assert.deepEqual(decisionPlan("refuse", delivered, false), { kind: "reject_closed" });
    assert.deepEqual(decisionPlan("close", delivered, false), { kind: "reject_closed" });
    // Fermée not_planned sans le commentaire de cette décision : refusée ailleurs.
    assert.deepEqual(
      decisionPlan("refuse", { state: "closed", stateReason: "not_planned", labels: [] }, false),
      { kind: "reject_closed" },
    );
    // Close : statut:clos posé ailleurs, sans le commentaire de cette décision.
    assert.deepEqual(
      decisionPlan(
        "close",
        { state: "closed", stateReason: "completed", labels: ["statut:clos"] },
        false,
      ),
      { kind: "reject_closed" },
    );
  });
});

describe("message d'échec montré à l'admin", () => {
  it("jeton : « Jeton GitHub refusé ou expiré. »", () =>
    assert.equal(failureReason("refuse", ["comment"], "token"), FAILURE_TOKEN));
  it("Issue absente", () =>
    assert.equal(failureReason("validate", [], "not_found"), FAILURE_ISSUE_MISSING));
  it("motif publié, Issue non fermée", () =>
    assert.equal(
      failureReason("refuse", ["comment"], "other"),
      "Motif publié, mais l'Issue n'a pas été fermée. Réessayez.",
    ));
  it("commentaire publié, Issue non close", () =>
    assert.match(failureReason("close", ["comment", "label"], "network"), /^Commentaire publié/));
  it("limite de débit", () => {
    assert.equal(failureReason("validate", [], "rate_limit"), FAILURE_RATE_LIMIT);
    assert.ok(failureReason("refuse", ["comment"], "rate_limit").startsWith(FAILURE_RATE_LIMIT));
  });
  it("rien de publié", () =>
    assert.match(failureReason("validate", [], "other"), /rien n'a été publié/));
});

describe("client GitHub : écritures des décisions", () => {
  function recorder(status: number, body: unknown) {
    const calls: Array<{ url: string; method: string; body: unknown }> = [];
    const fake: FetchLike = async (url, init) => {
      calls.push({
        url,
        method: String(init.method),
        body: typeof init.body === "string" ? JSON.parse(init.body) : null,
      });
      return new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      });
    };
    return { calls, fake };
  }

  it("commentaire : POST /issues/N/comments, identifiant rendu", async () => {
    const { calls, fake } = recorder(201, { id: 991 });
    const out = await githubClient(TOKEN, fake).createComment(12, "Réponse : x\n\nDécision d");
    assert.deepEqual(out, { id: 991 });
    assert.equal(calls[0].method, "POST");
    assert.match(calls[0].url, /\/repos\/ChinaFred\/KassBeer\/issues\/12\/comments$/);
    assert.deepEqual(calls[0].body, { body: "Réponse : x\n\nDécision d" });
  });

  it("étiquette : POST /issues/N/labels", async () => {
    const { calls, fake } = recorder(200, []);
    await githubClient(TOKEN, fake).addLabels(12, ["validé"]);
    assert.match(calls[0].url, /\/issues\/12\/labels$/);
    assert.deepEqual(calls[0].body, { labels: ["validé"] });
  });

  it("fermeture : PATCH /issues/N avec state_reason", async () => {
    const { calls, fake } = recorder(200, {});
    await githubClient(TOKEN, fake).closeIssue(12, "not_planned");
    assert.equal(calls[0].method, "PATCH");
    assert.match(calls[0].url, /\/issues\/12$/);
    assert.deepEqual(calls[0].body, { state: "closed", state_reason: "not_planned" });
  });

  it("refus 401 : GithubError de type jeton, sans le jeton dans le message", async () => {
    const { fake } = recorder(401, { message: "Bad credentials" });
    await assert.rejects(githubClient(TOKEN, fake).closeIssue(12, "completed"), (err: Error) => {
      assert.equal((err as { kind?: string }).kind, "token");
      assert.ok(!err.message.includes(TOKEN));
      return true;
    });
  });
});

describe("reprise par la passe horaire", () => {
  it("pending créée depuis plus de cinq minutes : reprise", () => {
    assert.equal(PENDING_DECISION_GRACE_MS, 5 * 60 * 1000);
    assert.equal(stalePendingCutoffMs(NOW), NOW - 300_000);
    const at = (requestedAtMs: number | null) =>
      isResumableByPass({ state: "pending", leaseUntilMs: null, requestedAtMs, nowMs: NOW });
    assert.equal(at(NOW - 300_001), true);
    assert.equal(at(NOW - 300_000), false);
    assert.equal(at(NOW - 60_000), false);
    assert.equal(at(null), false);
  });
  it("applying au bail expiré : reprise ; au bail actif : non", () => {
    const lease = (leaseUntilMs: number | null) =>
      isResumableByPass({ state: "applying", leaseUntilMs, requestedAtMs: null, nowMs: NOW });
    assert.equal(lease(NOW - 1), true);
    assert.equal(lease(NOW + 1), false);
  });
  it("applied, rejected, failed : non", () => {
    for (const state of ["applied", "rejected", "failed"]) {
      assert.equal(
        isResumableByPass({
          state,
          leaseUntilMs: null,
          requestedAtMs: NOW - 3_600_000,
          nowMs: NOW,
        }),
        false,
      );
    }
  });
  it("une décision pending reprise est prise comme à sa création", () =>
    assert.equal(decisionClaimVerdict(input({ state: "pending" })).kind, "claim"));
});

describe("reprise d'une décision avec comment_id (P26)", () => {
  const claimed = (knownCommentId: number | null): Extract<Claim, { kind: "claimed" }> => ({
    kind: "claimed",
    action: "refuse",
    text: "Hors du périmètre de l'application.",
    issueNumber: 12,
    leaseUntilMs: NOW + 120_000,
    knownCommentId,
  });
  // L'Issue ouverte n'utilise pas `refs` (seule une Issue fermée relit le ticket).
  const refs = {} as Refs;

  function fakeGithub(knownComment: { status: number; body: unknown }) {
    const calls: Array<{ method: string; path: string }> = [];
    const json = (status: number, body: unknown) =>
      new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      });
    const fake: FetchLike = async (url, init) => {
      const path = new URL(url).pathname;
      const method = String(init.method);
      calls.push({ method, path });
      if (method === "GET" && path.endsWith("/issues/12")) {
        return json(200, {
          number: 12,
          state: "open",
          state_reason: null,
          labels: [{ name: "source:app" }],
          comments: 601,
          updated_at: "2026-11-11T09:00:00Z",
        });
      }
      if (method === "GET" && path.endsWith("/issues/comments/991")) {
        return json(knownComment.status, knownComment.body);
      }
      if (method === "GET" && path.endsWith("/issues/12/comments")) {
        // 600 commentaires d'autres comptes, sans la ligne de la décision.
        return json(
          200,
          Array.from({ length: 100 }, (_, i) => ({
            id: i,
            user: { id: 4242 },
            body: "+1",
          })),
        );
      }
      if (method === "POST" && path.endsWith("/issues/12/comments")) return json(201, { id: 992 });
      if (method === "PATCH" && path.endsWith("/issues/12")) return json(200, {});
      return json(500, { message: `inattendu ${method} ${path}` });
    };
    return { calls, client: githubClient(TOKEN, fake) };
  }

  const count = (calls: Array<{ method: string; path: string }>, method: string, suffix: string) =>
    calls.filter((c) => c.method === method && c.path.endsWith(suffix)).length;

  it("commentaire connu toujours là : aucune page relue, aucun createComment", async () => {
    const { calls, client } = fakeGithub({
      status: 200,
      body: {
        id: 991,
        user: { id: OWNER },
        body: "Réponse : Hors du périmètre de l'application.\n\nDécision dec_1",
      },
    });
    const run = await runOnGithub(client, refs, "dec_1", claimed(991));
    assert.equal(count(calls, "GET", "/issues/comments/991"), 1);
    assert.equal(count(calls, "GET", "/issues/12/comments"), 0);
    assert.equal(count(calls, "POST", "/issues/12/comments"), 0);
    assert.equal(count(calls, "PATCH", "/issues/12"), 1);
    assert.equal(run.kind, "done");
    assert.equal(run.kind === "done" && run.commentId, 991);
    assert.deepEqual(run.stepsDone, ["comment", "close"]);
  });

  it("commentaire connu supprimé (404) : republié, sans relire les pages", async () => {
    const { calls, client } = fakeGithub({ status: 404, body: { message: "Not Found" } });
    const run = await runOnGithub(client, refs, "dec_1", claimed(991));
    assert.equal(count(calls, "GET", "/issues/12/comments"), 0);
    assert.equal(count(calls, "POST", "/issues/12/comments"), 1);
    assert.equal(run.kind === "done" && run.commentId, 992);
  });

  it("commentaire connu d'un autre compte : pages relues, puis publication", async () => {
    const { calls, client } = fakeGithub({
      status: 200,
      body: { id: 991, user: { id: 4242 }, body: "Réponse : x\n\nDécision dec_1" },
    });
    await runOnGithub(client, refs, "dec_1", claimed(991));
    assert.ok(count(calls, "GET", "/issues/12/comments") >= 1);
    assert.equal(count(calls, "POST", "/issues/12/comments"), 1);
  });

  it("sans comment_id : pages relues avant de publier", async () => {
    const { calls, client } = fakeGithub({ status: 500, body: {} });
    await runOnGithub(client, refs, "dec_1", claimed(null));
    assert.equal(count(calls, "GET", "/issues/comments/991"), 0);
    assert.equal(count(calls, "GET", "/issues/12/comments"), 5);
    assert.equal(count(calls, "POST", "/issues/12/comments"), 1);
  });
});
