/**
 * `tickets/{id}/admin/analysis` (ADR-008, T3, P32) : écrit par le serveur seul (SDK Admin),
 * lu par l'administrateur seul (`firestore.rules`). Champs :
 *
 * - `analyses` : dix entrées au plus, ordre chronologique, `{comment_id, kind, body,
 *   created_at, updated_at, truncated}` (`analysisModel.ts`) ;
 * - `skipped_count` : entrées reconnues écartées au-delà de dix ;
 * - `checked_at` : dernière relecture des commentaires ;
 * - `validated_at` : dernier « validé » connu (webhook ou décision Valider), ne recule pas ;
 * - `answer_comment_ids` : identifiants des commentaires publiés par `answerTicketAnalysis`.
 *
 * Le relevé est appelé par le webhook, la passe horaire (`applyIssue`) et chaque décision.
 */

import {
  COLL_TICKETS,
  GITHUB_MAINTAINER_ID,
  TICKET_ADMIN_SUBCOLLECTION,
  TICKET_ANALYSIS_DOC,
} from "../config";
import { firestore } from "../firestore";
import { analysesFromComments, nextValidatedAt, readAnswerCommentIds } from "./analysisModel";
import type { GithubClient } from "./github";
import type { CommentView } from "./model";

export async function analysisRef(ticketId: string) {
  const { db } = await firestore();
  return db
    .collection(COLL_TICKETS)
    .doc(ticketId)
    .collection(TICKET_ADMIN_SUBCOLLECTION)
    .doc(TICKET_ANALYSIS_DOC);
}

/**
 * Réécrit `analyses`, `skipped_count` et `checked_at` depuis les commentaires lus. Les
 * identifiants de `answer_comment_ids` sont lus dans la même transaction. Écriture
 * fusionnée : `validated_at` et `answer_comment_ids` restent tels quels. Lève sur une panne
 * Firestore ; l'appelant journalise.
 */
export async function writeTicketAnalyses(
  ticketId: string,
  comments: readonly CommentView[],
): Promise<number> {
  const { db, FieldValue, Timestamp } = await firestore();
  const ref = await analysisRef(ticketId);
  const toTimestamp = (iso: string | null) => {
    if (iso === null) return null;
    const ms = Date.parse(iso);
    return Number.isNaN(ms) ? null : Timestamp.fromMillis(ms);
  };
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const answerIds = readAnswerCommentIds(snap.get("answer_comment_ids"));
    const { entries, skipped } = analysesFromComments(comments, GITHUB_MAINTAINER_ID, answerIds);
    tx.set(
      ref,
      {
        analyses: entries.map((a) => ({
          comment_id: a.comment_id,
          kind: a.kind,
          body: a.body,
          created_at: toTimestamp(a.created_at),
          updated_at: toTimestamp(a.updated_at),
          truncated: a.truncated,
        })),
        skipped_count: skipped,
        checked_at: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return entries.filter((a) => a.kind === "analysis").length;
  });
}

/** Relit les commentaires de l'Issue (500 derniers au plus) et réécrit les analyses. */
export async function refreshAnalyses(
  client: GithubClient,
  ticketId: string,
  issueNumber: number,
  commentCount: number,
): Promise<CommentView[]> {
  const comments = commentCount > 0 ? await client.recentComments(issueNumber, commentCount) : [];
  await writeTicketAnalyses(ticketId, comments);
  return comments;
}

/**
 * Ajoute l'identifiant d'un commentaire publié par « Répondre » à `answer_comment_ids`, en
 * transaction (P34). Lève sur une panne Firestore.
 */
export async function recordAnswerCommentId(ticketId: string, commentId: number): Promise<void> {
  const { db, FieldValue } = await firestore();
  const ref = await analysisRef(ticketId);
  await db.runTransaction(async (tx) => {
    await tx.get(ref);
    tx.set(ref, { answer_comment_ids: FieldValue.arrayUnion(commentId) }, { merge: true });
  });
}

/** Écrit `validated_at` s'il avance (`nextValidatedAt`), en transaction. Lève sur une panne. */
export async function recordValidatedAt(ticketId: string, atMs: number): Promise<void> {
  const { db, Timestamp } = await firestore();
  const ref = await analysisRef(ticketId);
  await db.runTransaction(async (tx) => {
    const stored = (await tx.get(ref)).get("validated_at");
    const next = nextValidatedAt(stored instanceof Timestamp ? stored.toMillis() : null, atMs);
    if (next === null) return;
    tx.set(ref, { validated_at: Timestamp.fromMillis(next) }, { merge: true });
  });
}
