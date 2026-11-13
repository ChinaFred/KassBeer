import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { HttpsError } from "firebase-functions/v2/https";

import {
  ANALYSIS_MAX_CHARS,
  ANSWER_NOT_ALLOWED,
  ANSWER_RAW_MAX_CHARS,
  ANSWER_NO_ISSUE,
  ANSWER_TITLE,
  ANSWER_TOO_LONG,
  ANSWER_TOO_SHORT,
  analysesFromComments,
  analysisAnswerState,
  answerCommentBody,
  answerPrecondition,
  nextValidatedAt,
  readAnswerCommentIds,
  readAnswerText,
  truncateAnalysis,
} from "../src/tickets/analysisModel";
import {
  AnswerStepFailure,
  answerGithubFailure,
  answerOnGithub,
  findAfterFailedCreate,
  handleAnswerCall,
  readAnswerArg,
  readTicketIdArg,
} from "../src/tickets/answer";
import { allowedDecisions } from "../src/tickets/decisionModel";
import { GithubError, githubClient, type FetchLike } from "../src/tickets/github";
import type { LogEntry } from "../src/logging";
import {
  creationLabels,
  isStaleIssueSnapshot,
  nextStatus,
  statusFromIssue,
  type CommentView,
} from "../src/tickets/model";

const OWNER = 16348852;
const TOKEN = "github_pat_11AAAAAAAAAAAAAAAAAAAA_secretsecretsecretsecret";

const comment = (
  id: number,
  body: string,
  createdAt: string,
  authorId: number = OWNER,
): CommentView => ({ id, authorId, body, createdAt, updatedAt: createdAt });

describe("statut analyzed et étiquettes (ADR-008, P32)", () => {
  const open = { state: "open" as const, stateReason: null };
  it("publication : statut:à-analyser posée", () =>
    assert.deepEqual(creationLabels("bug"), ["source:app", "type:bug", "statut:à-analyser"]));
  it("statut:analysé : analyzed", () =>
    assert.equal(statusFromIssue({ ...open, labels: ["statut:analysé"] }), "analyzed"));
  it("validé l'emporte sur statut:analysé, statut:en-cours sur les deux", () => {
    assert.equal(statusFromIssue({ ...open, labels: ["statut:analysé", "validé"] }), "validated");
    assert.equal(
      statusFromIssue({ ...open, labels: ["statut:analysé", "validé", "statut:en-cours"] }),
      "in_progress",
    );
  });
  it("statut:à-analyser seule : received", () =>
    assert.equal(statusFromIssue({ ...open, labels: ["statut:à-analyser"] }), "received"));
  it("rang : received < analyzed < validated, sans recul", () => {
    assert.equal(nextStatus("received", "analyzed"), "analyzed");
    assert.equal(nextStatus("analyzed", "validated"), "validated");
    assert.equal(nextStatus("analyzed", "received"), "analyzed");
    assert.equal(nextStatus("validated", "analyzed"), "validated");
  });
  it("état d'Issue antérieur ou égal au retour à Reçu : ignoré", () => {
    const reset = Date.parse("2026-11-12T10:00:00Z");
    assert.equal(isStaleIssueSnapshot("2026-11-12T09:59:59Z", reset), true);
    assert.equal(isStaleIssueSnapshot("2026-11-12T10:00:00Z", reset), true);
    assert.equal(isStaleIssueSnapshot("2026-11-12T10:00:01Z", reset), false);
    assert.equal(isStaleIssueSnapshot(null, reset), false);
    assert.equal(isStaleIssueSnapshot("2026-11-12T09:00:00Z", null), false);
  });
});

describe("décisions permises avec answer (ADR-008)", () => {
  it("received : valider (jusqu'à T4), refuser, clore, répondre", () =>
    assert.deepEqual(allowedDecisions("received"), ["validate", "refuse", "close", "answer"]));
  it("analyzed : valider, refuser, clore, répondre", () =>
    assert.deepEqual(allowedDecisions("analyzed"), ["validate", "refuse", "close", "answer"]));
  it("validated : refuser, clore, répondre", () =>
    assert.deepEqual(allowedDecisions("validated"), ["refuse", "close", "answer"]));
  it("in_progress : refuser, clore", () =>
    assert.deepEqual(allowedDecisions("in_progress"), ["refuse", "close"]));
});

describe("relevé des analyses (P32)", () => {
  it("analyses et précisions du compte 16348852 seules, ordre chronologique", () => {
    const { entries, skipped } = analysesFromComments(
      [
        comment(3, "## Précisions de l'administrateur\n\nOui.", "2026-11-12T10:03:00Z"),
        comment(1, "## Analyse\n\nLe minuteur repart.", "2026-11-12T10:01:00Z"),
        comment(2, "## Analyse\n\nFaux.", "2026-11-12T10:02:00Z", 999),
        comment(4, "Réponse : merci", "2026-11-12T10:04:00Z"),
        comment(5, "   ## Analyse — compléments", "2026-11-12T10:05:00Z"),
      ],
      OWNER,
      new Set([3]),
    );
    assert.equal(skipped, 0);
    assert.deepEqual(
      entries.map((e) => [e.comment_id, e.kind]),
      [
        [1, "analysis"],
        [3, "reply"],
        [5, "analysis"],
      ],
    );
    assert.equal(entries[2].body, "## Analyse — compléments");
  });

  it("précision absente de answer_comment_ids : unverified_reply", () => {
    const { entries } = analysesFromComments(
      [comment(7, "## Précisions de l'administrateur\n\nx", "2026-11-12T10:00:00Z")],
      OWNER,
    );
    assert.equal(entries[0].kind, "unverified_reply");
  });

  it("titre composé en NFD reconnu (NFC)", () => {
    const nfd = "## Précisions\n\nx";
    const { entries } = analysesFromComments(
      [comment(8, nfd, "2026-11-12T10:00:00Z")],
      OWNER,
      new Set([8]),
    );
    assert.equal(entries[0].kind, "reply");
  });

  it("dix entrées au plus, les plus récentes ; skipped_count compte le reste", () => {
    const many = Array.from({ length: 13 }, (_, i) =>
      comment(i + 1, `## Analyse ${i + 1}`, `2026-11-12T10:${String(i).padStart(2, "0")}:00Z`),
    );
    const { entries, skipped } = analysesFromComments(many, OWNER);
    assert.equal(entries.length, 10);
    assert.equal(skipped, 3);
    assert.equal(entries[0].comment_id, 4);
    assert.equal(entries[9].comment_id, 13);
  });

  it("coupe à la dernière ligne vide avant la limite", () => {
    const body = `## Analyse\n\n${"a".repeat(100)}\n\n${"b".repeat(ANALYSIS_MAX_CHARS)}`;
    const cut = truncateAnalysis(body);
    assert.equal(cut.truncated, true);
    assert.equal(cut.body, `## Analyse\n\n${"a".repeat(100)}`);
    assert.deepEqual(truncateAnalysis("court"), { body: "court", truncated: false });
  });

  it("sans ligne vide : coupe à la limite, sans séparer une paire de substitution", () => {
    const body = `${"a".repeat(9)}😀😀`;
    assert.equal(truncateAnalysis(body, 10).body, "a".repeat(9));
  });

  it("answer_comment_ids lus sans supposer leur forme", () =>
    assert.deepEqual([...readAnswerCommentIds([1, "2", 3.5, null, 4])], [1, 4]));

  it("validated_at ne recule pas", () => {
    assert.equal(nextValidatedAt(null, 10), 10);
    assert.equal(nextValidatedAt(10, 5), null);
    assert.equal(nextValidatedAt(10, 10), null);
    assert.equal(nextValidatedAt(10, 20), 20);
  });
});

describe("texte de « Répondre » (P24, P34)", () => {
  const ok = (raw: string) => {
    const r = readAnswerText(raw);
    assert.ok(r.ok, raw);
    return r.text;
  };
  it("4 caractères : refusé ; 5 : accepté", () => {
    assert.deepEqual(readAnswerText("abcd"), { ok: false, reason: ANSWER_TOO_SHORT });
    assert.equal(ok("abcde"), "abcde");
  });
  it("4 000 caractères : accepté ; 4 001 : refusé", () => {
    assert.equal(ok("x".repeat(4000)).length, 4000);
    assert.deepEqual(readAnswerText("x".repeat(4001)), { ok: false, reason: ANSWER_TOO_LONG });
  });
  it("caractères comptés comme l'écran (points de code)", () =>
    assert.equal(Array.from(ok("😀".repeat(4000))).length, 4000));
  it("espaces de bord et caractères de contrôle ne comptent pas", () => {
    assert.deepEqual(readAnswerText("  ab\u0000c  "), { ok: false, reason: ANSWER_TOO_SHORT });
  });
  it("e-mail remplacé", () =>
    assert.equal(ok("Écrire à jean@exemple.fr svp"), "Écrire à [adresse retirée] svp"));
  it("mention et renvoi neutralisés", () => {
    const text = ok("Voir @ChinaFred et #12");
    assert.ok(!text.includes("@ChinaFred"));
    assert.ok(!text.includes("#12"));
  });
  it("HTML neutralisé, commentaire HTML seul : trop court", () => {
    assert.ok(!ok("<img src=x onerror=y> texte").includes("<img"));
    assert.deepEqual(readAnswerText("<!-- caché -->"), { ok: false, reason: ANSWER_TOO_SHORT });
  });
  it("gabarit fixe du commentaire", () =>
    assert.equal(answerCommentBody("Oui."), `${ANSWER_TITLE}\n\nOui.`));
  it("précondition : statut et Issue", () => {
    assert.equal(answerPrecondition({ status: "received", hasIssue: true }), null);
    assert.equal(answerPrecondition({ status: "analyzed", hasIssue: true }), null);
    assert.equal(answerPrecondition({ status: "validated", hasIssue: true }), null);
    assert.equal(answerPrecondition({ status: "in_progress", hasIssue: true }), ANSWER_NOT_ALLOWED);
    assert.equal(answerPrecondition({ status: "pending", hasIssue: true }), ANSWER_NOT_ALLOWED);
    assert.equal(answerPrecondition({ status: "analyzed", hasIssue: false }), ANSWER_NO_ISSUE);
  });
});

describe("arguments de answerTicketAnalysis (P30, P34)", () => {
  const field = (fn: () => unknown) => {
    try {
      fn();
    } catch (err) {
      assert.ok(err instanceof HttpsError);
      assert.equal(err.code, "invalid-argument");
      return (err.details as { field: string }).field;
    }
    return null;
  };
  it("ticketId absent, trop long ou hors [A-Za-z0-9_-] : champ ticketId", () => {
    assert.equal(
      field(() => readTicketIdArg({})),
      "ticketId",
    );
    assert.equal(
      field(() => readTicketIdArg({ ticketId: "a".repeat(129) })),
      "ticketId",
    );
    assert.equal(
      field(() => readTicketIdArg({ ticketId: "../x" })),
      "ticketId",
    );
    assert.equal(
      field(() => readTicketIdArg(null)),
      "ticketId",
    );
    assert.equal(readTicketIdArg({ ticketId: "t-1_A" }), "t-1_A");
  });
  it("answer absent, non textuel, trop long en brut ou après nettoyage : champ answer", () => {
    assert.equal(
      field(() => readAnswerArg({})),
      "answer",
    );
    assert.equal(
      field(() => readAnswerArg({ answer: 5 })),
      "answer",
    );
    assert.equal(
      field(() => readAnswerArg({ answer: "x".repeat(ANSWER_RAW_MAX_CHARS + 1) })),
      "answer",
    );
    assert.equal(
      field(() => readAnswerArg({ answer: "x".repeat(4001) })),
      "answer",
    );
    assert.equal(
      field(() => readAnswerArg({ answer: "abcd" })),
      "answer",
    );
  });

  it("bout en bout : 2 600 émojis acceptés, 4 001 points de code refusés", () => {
    const emojis = "\u{1F37A}".repeat(2600);
    // 5 200 unités UTF-16 : au-delà de l'ancienne borne brute de 5 000.
    assert.equal(emojis.length, 5200);
    assert.equal(readAnswerArg({ answer: emojis }), emojis);
    const max = "\u{1F37A}".repeat(4000);
    assert.equal(readAnswerArg({ answer: max }), max);
    const reason = (value: string) => {
      try {
        readAnswerArg({ answer: value });
      } catch (err) {
        assert.ok(err instanceof HttpsError);
        return (err.details as { reason: string }).reason;
      }
      return null;
    };
    assert.equal(reason("\u{1F37A}".repeat(4001)), ANSWER_TOO_LONG);
    assert.equal(reason("é".repeat(4001)), ANSWER_TOO_LONG);
    assert.equal(reason("x".repeat(ANSWER_RAW_MAX_CHARS + 1)), "Réponse : texte trop long.");
  });

  it("non admin refusé avant toute lecture des arguments", async () => {
    let reads = 0;
    const lookup = async () => {
      reads++;
      return { role: "brewer" };
    };
    const req = {
      auth: {
        uid: "u",
        token: {
          email: "brasseur@example.com",
          email_verified: true,
          firebase: { sign_in_provider: "google.com" },
        },
      },
      data: { ticketId: "../x", answer: 42 },
    };
    await assert.rejects(
      handleAnswerCall(req, () => TOKEN, { lookup }),
      (err: HttpsError) => err.code === "permission-denied",
    );
    assert.equal(reads, 1);
    await assert.rejects(
      handleAnswerCall({ data: req.data }, () => TOKEN, { lookup }),
      (err: HttpsError) => err.code === "unauthenticated",
    );
  });

  it("échec GitHub avant publication : code et motif", () => {
    assert.equal(answerGithubFailure("token").code, "failed-precondition");
    assert.equal(answerGithubFailure("not_found").code, "not-found");
    assert.equal(answerGithubFailure("rate_limit").code, "unavailable");
    assert.equal(answerGithubFailure("other").machine, "github_unavailable");
  });
});

/** Faux GitHub : une Issue, ses commentaires, les écritures relevées. */
function fakeGithub(issue: { labels: string[]; state?: string }, comments: unknown[]) {
  const writes: Array<{ method: string; url: string; body: unknown }> = [];
  const all = [...comments];
  const fetchImpl: FetchLike = async (url, init) => {
    const method = init.method ?? "GET";
    const body = init.body === undefined ? undefined : JSON.parse(String(init.body));
    const json = (status: number, data: unknown) =>
      new Response(JSON.stringify(data), {
        status,
        headers: { "content-type": "application/json" },
      });
    if (method !== "GET") writes.push({ method, url, body });
    if (method === "GET" && /\/issues\/12$/.test(url)) {
      return json(200, {
        number: 12,
        state: issue.state ?? "open",
        state_reason: null,
        labels: issue.labels.map((name) => ({ name })),
        updated_at: "2026-11-12T10:00:00Z",
        comments: all.length,
      });
    }
    if (method === "GET" && /\/issues\/12\/comments\?/.test(url)) return json(200, all);
    if (method === "POST" && /\/issues\/12\/comments$/.test(url)) {
      const created = {
        id: 500 + all.length,
        user: { id: OWNER },
        body: (body as { body: string }).body,
        created_at: "2026-11-12T10:10:00Z",
        updated_at: "2026-11-12T10:10:00Z",
      };
      all.push(created);
      return json(201, created);
    }
    if (method === "POST" && /\/labels$/.test(url)) return json(200, []);
    if (method === "DELETE" && /\/labels\//.test(url)) return json(200, []);
    return json(500, { message: "inattendu" });
  };
  return { fetchImpl, writes, all };
}

const analysisComment = {
  id: 300,
  user: { id: OWNER },
  body: "## Analyse\n\nQuestion : quel écran ?",
  created_at: "2026-11-12T09:00:00Z",
  updated_at: "2026-11-12T09:00:00Z",
};

describe("« Répondre » sur GitHub (P26, P34)", () => {
  const body = answerCommentBody("Le jour de brassage.");

  it("ticket analysé : publie une fois, pose statut:à-analyser, retire statut:analysé", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] }, [analysisComment]);
    const recorded: Array<number | null> = [];
    const run = await answerOnGithub(
      githubClient(TOKEN, gh.fetchImpl),
      12,
      "analyzed",
      body,
      new Set(),
      async (id) => {
        recorded.push(id);
      },
    );
    assert.equal(run.kind, "done");
    assert.deepEqual(recorded, [501]);
    assert.deepEqual(
      gh.writes.map((w) => [w.method, w.url.replace(/^.*\/issues\/12/, "")]),
      [
        ["POST", "/comments"],
        ["POST", "/labels"],
        ["DELETE", `/labels/${encodeURIComponent("statut:analysé")}`],
      ],
    );
    assert.deepEqual(gh.writes[0].body, { body });
  });

  it("double appel : la précision déjà publiée (answer_comment_ids) n'est pas republiée", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé", "validé"] }, [
      analysisComment,
    ]);
    const ids = new Set<number>();
    const client = githubClient(TOKEN, gh.fetchImpl);
    const record = async (id: number | null) => {
      if (id !== null) ids.add(id);
    };
    await answerOnGithub(client, 12, "validated", body, ids, record);
    const second = await answerOnGithub(client, 12, "validated", body, ids, record);
    assert.equal(second.kind === "done" && second.alreadyPublished, true);
    assert.equal(gh.writes.filter((w) => w.url.endsWith("/comments")).length, 1);
  });

  it("précision non enregistrée au même texte : reconnue, enregistrée, pas republiée", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] }, [
      analysisComment,
      { ...analysisComment, id: 301, body, created_at: "2026-11-12T09:30:00Z" },
    ]);
    const recorded: Array<number | null> = [];
    const run = await answerOnGithub(
      githubClient(TOKEN, gh.fetchImpl),
      12,
      "analyzed",
      body,
      new Set(),
      async (id) => {
        recorded.push(id);
      },
    );
    assert.equal(run.kind === "done" && run.alreadyPublished, true);
    assert.deepEqual(recorded, [301]);
    assert.equal(gh.writes.filter((w) => w.url.endsWith("/comments")).length, 0);
  });

  it("précision d'un autre texte, ou d'un autre compte : publiée", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] }, [
      analysisComment,
      {
        ...analysisComment,
        id: 301,
        body: answerCommentBody("Autre texte."),
        created_at: "2026-11-12T09:30:00Z",
      },
      { ...analysisComment, id: 302, user: { id: 1 }, body, created_at: "2026-11-12T09:40:00Z" },
    ]);
    const run = await answerOnGithub(
      githubClient(TOKEN, gh.fetchImpl),
      12,
      "analyzed",
      body,
      new Set(),
      async () => undefined,
    );
    assert.equal(run.kind === "done" && run.alreadyPublished, false);
    assert.equal(gh.writes.filter((w) => w.url.endsWith("/comments")).length, 1);
  });

  it("création réussie mais réponse perdue : relue, enregistrée, aucun second POST", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] }, [analysisComment]);
    // GitHub crée le commentaire, puis la connexion tombe avant la réponse.
    const lost: FetchLike = async (url, init) => {
      const res = await gh.fetchImpl(url, init);
      if (init.method === "POST" && url.endsWith("/comments")) throw new TypeError("fetch failed");
      return res;
    };
    const ids = new Set<number>();
    const record = async (id: number | null) => {
      if (id !== null) ids.add(id);
    };
    const first = await answerOnGithub(
      githubClient(TOKEN, lost),
      12,
      "analyzed",
      body,
      ids,
      record,
    );
    assert.equal(first.kind, "done");
    assert.deepEqual([...ids], [501]);
    const second = await answerOnGithub(
      githubClient(TOKEN, lost),
      12,
      "analyzed",
      body,
      ids,
      record,
    );
    assert.equal(second.kind === "done" && second.alreadyPublished, true);
    assert.equal(gh.writes.filter((w) => w.url.endsWith("/comments")).length, 1);
  });

  it("réponse perdue et relecture en échec : refus, puis second appel sans second POST", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] }, [analysisComment]);
    let created = false;
    const lost: FetchLike = async (url, init) => {
      if (init.method === "POST" && url.endsWith("/comments")) {
        await gh.fetchImpl(url, init);
        created = true;
        throw new TypeError("fetch failed");
      }
      // Relecture après l'échec : GitHub ne répond pas non plus.
      if (created && !first) throw new TypeError("fetch failed");
      return gh.fetchImpl(url, init);
    };
    let first = false;
    const ids = new Set<number>();
    const record = async (id: number | null) => {
      if (id !== null) ids.add(id);
    };
    await assert.rejects(
      answerOnGithub(githubClient(TOKEN, lost), 12, "analyzed", body, ids, record),
      (err: AnswerStepFailure) => err instanceof AnswerStepFailure && !err.published,
    );
    first = true;
    const second = await answerOnGithub(
      githubClient(TOKEN, lost),
      12,
      "analyzed",
      body,
      ids,
      record,
    );
    assert.equal(second.kind === "done" && second.alreadyPublished, true);
    assert.deepEqual([...ids], [501]);
    assert.equal(gh.writes.filter((w) => w.url.endsWith("/comments")).length, 1);
  });

  it("précision retrouvée : l'erreur de la création passe par logError, sans le texte", async () => {
    const gh = fakeGithub({ labels: ["statut:analysé"] }, [
      analysisComment,
      { ...analysisComment, id: 301, body, created_at: "2026-11-12T09:30:00Z" },
    ]);
    const reports: LogEntry[] = [];
    const createError = new GithubError("other", 502, "GitHub HTTP 502 : Bad Gateway");
    const found = await findAfterFailedCreate(
      githubClient(TOKEN, gh.fetchImpl),
      12,
      createError,
      (c) => analysisAnswerState(c, OWNER, new Set(), body),
      (entry) => reports.push(entry),
    );
    assert.deepEqual(found, { commentId: 301, verified: false });
    assert.equal(reports.length, 1);
    assert.equal(reports[0].error, createError);
    assert.deepEqual(reports[0].extra, { issue: 12, comment_id: 301, status: 502 });
    assert.ok(!JSON.stringify(reports[0]).includes("brassage"));
  });

  it("création refusée en 4xx : aucune relecture, rien publié", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:analysé"] }, [analysisComment]);
    const reads: string[] = [];
    const refused: FetchLike = async (url, init) => {
      if (init.method === "POST" && url.endsWith("/comments")) {
        return new Response(JSON.stringify({ message: "Validation Failed" }), { status: 422 });
      }
      if ((init.method ?? "GET") === "GET") reads.push(url);
      return gh.fetchImpl(url, init);
    };
    await assert.rejects(
      answerOnGithub(
        githubClient(TOKEN, refused),
        12,
        "analyzed",
        body,
        new Set(),
        async () => undefined,
      ),
      (err: AnswerStepFailure) => err instanceof AnswerStepFailure && !err.published,
    );
    // Une lecture de l'Issue et une des commentaires, avant la création seulement.
    assert.equal(reads.length, 2);
  });

  it("ticket reçu sans analyse : publie, étiquettes inchangées", async () => {
    const gh = fakeGithub({ labels: ["source:app", "statut:à-analyser"] }, []);
    const run = await answerOnGithub(
      githubClient(TOKEN, gh.fetchImpl),
      12,
      "received",
      body,
      new Set(),
      async () => undefined,
    );
    assert.equal(run.kind, "done");
    assert.deepEqual(
      gh.writes.map((w) => w.method),
      ["POST"],
    );
  });

  it("ticket analysé sans analyse sur l'Issue : rien publié", async () => {
    const gh = fakeGithub({ labels: ["statut:analysé"] }, []);
    const run = await answerOnGithub(
      githubClient(TOKEN, gh.fetchImpl),
      12,
      "analyzed",
      body,
      new Set(),
      async () => undefined,
    );
    assert.equal(run.kind, "no_analysis");
    assert.equal(gh.writes.length, 0);
  });

  it("Issue fermée : rien publié", async () => {
    const gh = fakeGithub({ labels: [], state: "closed" }, [analysisComment]);
    const run = await answerOnGithub(
      githubClient(TOKEN, gh.fetchImpl),
      12,
      "analyzed",
      body,
      new Set(),
      async () => undefined,
    );
    assert.equal(run.kind, "closed");
    assert.equal(gh.writes.length, 0);
  });

  it("étiquettes en échec après la publication : échec partiel signalé", async () => {
    const gh = fakeGithub({ labels: ["statut:analysé"] }, [analysisComment]);
    const failing: FetchLike = async (url, init) =>
      init.method === "POST" && url.endsWith("/labels")
        ? new Response(JSON.stringify({ message: "boom" }), { status: 500 })
        : gh.fetchImpl(url, init);
    await assert.rejects(
      answerOnGithub(
        githubClient(TOKEN, failing),
        12,
        "analyzed",
        body,
        new Set(),
        async () => undefined,
      ),
      (err: AnswerStepFailure) => err instanceof AnswerStepFailure && err.published,
    );
  });

  it("état de la dernière analyse : précision avant la dernière analyse non reconnue", () => {
    const state = analysisAnswerState(
      [
        comment(1, "## Analyse\n\nA", "2026-11-12T09:00:00Z"),
        comment(2, body, "2026-11-12T09:10:00Z"),
        comment(3, "## Analyse\n\nB", "2026-11-12T09:20:00Z"),
      ],
      OWNER,
      new Set([2]),
      body,
    );
    assert.deepEqual(state, { hasAnalysis: true, samePublished: false, same: null });
  });

  it("état de la dernière analyse : réponse enregistrée avant une précision non enregistrée", () => {
    const state = analysisAnswerState(
      [
        comment(1, "## Analyse\n\nA", "2026-11-12T09:00:00Z"),
        comment(2, body, "2026-11-12T09:10:00Z"),
        comment(3, body, "2026-11-12T09:20:00Z"),
      ],
      OWNER,
      new Set([3]),
      body,
    );
    assert.deepEqual(state.same, { commentId: 3, verified: true });
  });
});
