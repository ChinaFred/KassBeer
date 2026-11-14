import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  FAILURE_ISSUE_MISSING,
  FAILURE_RATE_LIMIT,
  FAILURE_TOKEN,
  REJECT_DELIVERY_RUNNING,
  REJECT_LEASE_TAKEN,
  REJECT_NO_ISSUE,
  REJECT_NOT_ALLOWED,
  REJECT_TICKET_MISSING,
  allowedDecisions,
  allowedDecisionsUpToDate,
  commentCarriesDecision,
  decisionCommentBody,
  decisionFailure,
  decisionPlan,
  decisionStart,
  decisionTextOfComment,
  failureReason,
  isValidatedByApp,
  keepsAppValidation,
  readDecisionText,
  replyTextOfComment,
  statusAfterDecision,
  type DecisionAction,
  type DecisionStartInput,
  type LatestDecision,
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
  action: DecisionAction,
  ticket: Partial<NonNullable<DecisionStartInput["ticket"]>> | null = {},
  latest: Partial<LatestDecision> | null = null,
): DecisionStartInput {
  return {
    action,
    ticket:
      ticket === null
        ? null
        : {
            status: "received",
            validatedByAppAt: null,
            leaseUntilMs: null,
            issueNumber: 12,
            deliveryRunning: false,
            ...ticket,
          },
    latest:
      latest === null
        ? null
        : {
            id: "dec_1",
            action,
            state: "failed",
            leaseUntilMs: null,
            stepsDone: [],
            text: "Hors du périmètre de l'application.",
            commentId: null,
            ...latest,
          },
    nowMs: NOW,
  };
}

const refused = (code: string, machine: string, reason: string) => ({
  kind: "refuse",
  code,
  machine,
  reason,
});

describe("précondition des callables de décision (P42, P44, P53)", () => {
  it("refuse sur un ticket reçu, sans décision : nouvelle décision", () =>
    assert.deepEqual(decisionStart(input("refuse")), {
      kind: "start",
      issueNumber: 12,
      resume: null,
    }));

  it("ticket absent : not-found ; sans Issue : no_issue", () => {
    assert.deepEqual(
      decisionStart(input("refuse", null)),
      refused("not-found", "ticket_missing", REJECT_TICKET_MISSING),
    );
    assert.deepEqual(
      decisionStart(input("refuse", { issueNumber: null })),
      refused("failed-precondition", "no_issue", REJECT_NO_ISSUE),
    );
  });

  it("bail actif : decision_in_progress ; bail expiré : prise", () => {
    assert.deepEqual(
      decisionStart(input("refuse", { leaseUntilMs: NOW + 1000 })),
      refused("failed-precondition", "decision_in_progress", REJECT_LEASE_TAKEN),
    );
    assert.equal(decisionStart(input("refuse", { leaseUntilMs: NOW - 1000 })).kind, "start");
  });

  it("P42 : Valider sur un ticket reçu refusé, la liste stockée n'est pas lue", () =>
    assert.deepEqual(
      decisionStart(input("validate", { status: "received" })),
      refused("failed-precondition", "not_allowed", REJECT_NOT_ALLOWED),
    ));

  it("P42 : Valider sur un ticket analysé, ou validé sur GitHub seul : prise", () => {
    assert.equal(decisionStart(input("validate", { status: "analyzed" })).kind, "start");
    assert.equal(decisionStart(input("validate", { status: "validated" })).kind, "start");
  });

  it("déjà fait : Valider sur un ticket validé dans l'application, sans rien publier", () =>
    assert.deepEqual(
      decisionStart(input("validate", { status: "validated", validatedByAppAt: { seconds: 1 } })),
      { kind: "done", status: "validated" },
    ));

  it("déjà fait : Refuser sur un ticket refusé dont la dernière décision Refuser est appliquée", () => {
    assert.deepEqual(decisionStart(input("refuse", { status: "refused" }, { state: "applied" })), {
      kind: "done",
      status: "refused",
    });
    // Refusé sur GitHub, sans décision de l'application : refus.
    assert.deepEqual(
      decisionStart(input("refuse", { status: "refused" })),
      refused("failed-precondition", "not_allowed", REJECT_NOT_ALLOWED),
    );
  });

  it("P44 : Refuser et Clore refusés pendant une livraison de ce ticket", () => {
    for (const action of ["refuse", "close"] as const) {
      const ticket = { status: "in_progress", validatedByAppAt: { seconds: 1 } };
      assert.deepEqual(
        decisionStart(input(action, { ...ticket, deliveryRunning: true })),
        refused("failed-precondition", "delivery_running", REJECT_DELIVERY_RUNNING),
      );
      assert.equal(
        decisionStart(input(action, { ...ticket, deliveryRunning: false })).kind,
        "start",
      );
    }
  });

  it("reprise : dernière décision de même action failed, même identifiant", () =>
    assert.deepEqual(decisionStart(input("refuse", {}, { commentId: 991 })), {
      kind: "start",
      issueNumber: 12,
      resume: { id: "dec_1", keepText: false, knownCommentId: 991 },
    }));

  it("reprise : commentaire publié, texte stocké gardé", () => {
    const start = decisionStart(input("close", {}, { stepsDone: ["comment"] }));
    assert.equal(start.kind === "start" && start.resume?.keepText, true);
  });

  it("reprise : applying au bail expiré repris ; au bail actif, ticket au bail actif refusé", () => {
    const expired = decisionStart(
      input("refuse", {}, { state: "applying", leaseUntilMs: NOW - 1 }),
    );
    assert.equal(expired.kind === "start" && expired.resume?.id, "dec_1");
    assert.deepEqual(
      decisionStart(
        input("refuse", { leaseUntilMs: NOW + 1 }, { state: "applying", leaseUntilMs: NOW + 1 }),
      ),
      refused("failed-precondition", "decision_in_progress", REJECT_LEASE_TAKEN),
    );
  });

  it("reprise : pending écrite avant T7, reprise ; autre action ou décision appliquée : nouvelle", () => {
    const pending = decisionStart(input("refuse", {}, { state: "pending" }));
    assert.equal(pending.kind === "start" && pending.resume?.id, "dec_1");
    const other = decisionStart(input("refuse", {}, { action: "close" }));
    assert.equal(other.kind === "start" && other.resume, null);
    const applied = decisionStart(input("refuse", {}, { state: "applied" }));
    assert.equal(applied.kind === "start" && applied.resume, null);
  });

  it("reprise sur un ticket déjà au statut visé (passe horaire passée) : prise", () => {
    const retried = decisionStart(input("refuse", { status: "refused" }, { state: "failed" }));
    assert.equal(retried.kind, "start");
  });
});

describe("texte de Refuser et de Clore (P53)", () => {
  it("5 à 4 000 caractères comptés en points de code", () => {
    assert.equal(readDecisionText("refuse", "12345").ok, true);
    assert.equal(readDecisionText("refuse", "m".repeat(4000)).ok, true);
    assert.equal(readDecisionText("close", "\u{1F37A}".repeat(4000)).ok, true);
    assert.deepEqual(readDecisionText("refuse", "1234"), {
      ok: false,
      reason: "Le motif doit faire au moins 5 caractères.",
    });
    assert.deepEqual(readDecisionText("close", "m".repeat(4001)), {
      ok: false,
      reason: "Le commentaire ne doit pas dépasser 4 000 caractères.",
    });
  });

  it("espaces seuls ou caractères de contrôle seuls : trop court", () => {
    assert.equal(readDecisionText("refuse", "      ").ok, false);
    assert.equal(readDecisionText("refuse", "\u0000\u0001\u0002\u0003\u0004\u0005").ok, false);
  });

  it("texte nettoyé : bords retirés, NFC, retours à la ligne gardés", () =>
    assert.deepEqual(
      readDecisionText("refuse", "  Hors pe\u0301rime\u0300tre.\nVoir plus tard.  "),
      {
        ok: true,
        text: "Hors périmètre.\nVoir plus tard.",
      },
    ));
});

describe("texte d'un commentaire de décision retrouvé (P53)", () => {
  it("préfixe et ligne Décision retirés", () =>
    assert.equal(
      decisionTextOfComment("Réponse : Hors périmètre.\n\nDécision dec_1", OWNER),
      "Hors périmètre.",
    ));
  it("borné à 4 000 points de code, même pour un commentaire allongé sur GitHub", () => {
    const text = decisionTextOfComment(`Réponse : ${"m".repeat(10_000)}\n\nDécision d`, OWNER);
    assert.equal(Array.from(text ?? "").length, 4000);
    assert.ok(text?.endsWith("…"));
  });
  it("coupe sans séparer une paire de substitution", () => {
    const text = decisionTextOfComment(
      `Réponse : ${"\u{1F37A}".repeat(5000)}\n\nDécision d`,
      OWNER,
    );
    assert.equal(Array.from(text ?? "").length, 4000);
    assert.ok(text?.endsWith("\u{1F37A}…"));
  });
  it("commentaire sans forme de réponse : null", () =>
    assert.equal(decisionTextOfComment("Je regarde.", OWNER), null));
});

describe("échec sur GitHub rendu au client (P53)", () => {
  it("commentaire publié : aborted, partiel", () =>
    assert.deepEqual(decisionFailure("refuse", ["comment"], "network"), {
      code: "aborted",
      machine: "refuse_partial",
      reason: "Motif publié, mais l'Issue n'a pas été fermée. Réessayez.",
      partial: true,
    }));
  it("rien publié : jeton, Issue absente, limite, GitHub muet", () => {
    assert.equal(decisionFailure("validate", [], "token").machine, "github_token");
    assert.equal(decisionFailure("validate", [], "not_found").code, "not-found");
    assert.equal(decisionFailure("close", [], "rate_limit").machine, "github_rate_limit");
    assert.equal(decisionFailure("close", [], "other").code, "unavailable");
    assert.equal(decisionFailure("close", [], "other").partial, false);
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

describe("reprise d'une décision avec comment_id (P26)", () => {
  // L'Issue ouverte ne relit pas le ticket (seule une Issue fermée le relit).
  const refs = { decision: { id: "dec_1" } } as unknown as Refs;
  const claimed = (knownCommentId: number | null): Extract<Claim, { kind: "claimed" }> => ({
    kind: "claimed",
    refs,
    action: "refuse",
    text: "Hors du périmètre de l'application.",
    receivedText: "Hors du périmètre de l'application.",
    issueNumber: 12,
    leaseUntilMs: NOW + 120_000,
    knownCommentId,
    storedTextKept: false,
  });

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
    const run = await runOnGithub(client, claimed(991));
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
    const run = await runOnGithub(client, claimed(991));
    assert.equal(count(calls, "GET", "/issues/12/comments"), 0);
    assert.equal(count(calls, "POST", "/issues/12/comments"), 1);
    assert.equal(run.kind === "done" && run.commentId, 992);
  });

  it("commentaire connu d'un autre compte : pages relues, puis publication", async () => {
    const { calls, client } = fakeGithub({
      status: 200,
      body: { id: 991, user: { id: 4242 }, body: "Réponse : x\n\nDécision dec_1" },
    });
    await runOnGithub(client, claimed(991));
    assert.ok(count(calls, "GET", "/issues/12/comments") >= 1);
    assert.equal(count(calls, "POST", "/issues/12/comments"), 1);
  });

  it("sans comment_id : pages relues avant de publier", async () => {
    const { calls, client } = fakeGithub({ status: 500, body: {} });
    await runOnGithub(client, claimed(null));
    assert.equal(count(calls, "GET", "/issues/comments/991"), 0);
    assert.equal(count(calls, "GET", "/issues/12/comments"), 5);
    assert.equal(count(calls, "POST", "/issues/12/comments"), 1);
  });
});
