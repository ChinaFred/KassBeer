/**
 * État d'une Issue appliqué à son ticket : statut, décisions permises, réponse
 * « Réponse : » du compte 16348852, analyses et précisions (`admin/analysis`, P32), PR de
 * livraison et version. Appelé par la passe horaire (`sync.ts`), par le webhook
 * (`webhook.ts`) et par une décision qui trouve son Issue déjà fermée (`decisions.ts`).
 */

import type { DocumentSnapshot } from "firebase-admin/firestore";

import {
  GITHUB_MAINTAINER_ID,
  GITHUB_REPO_FULL_NAME,
  PUBSPEC_PATH,
  REPLY_MAX_CHARS,
} from "../config";
import { firestore } from "../firestore";
import { logError, logInfo } from "../logging";
import { writeTicketAnalyses } from "./analyses";
import {
  allowedDecisions,
  allowedDecisionsUpToDate,
  isValidatedByApp,
  keepsAppValidation,
} from "./decisionModel";
import { GithubError, type GithubClient } from "./github";
import {
  closingCommitFromEvents,
  isPublishedStatus,
  isStaleIssueSnapshot,
  lastReply,
  nextStatus,
  pickDeliveredPr,
  pubspecVersionName,
  statusFromIssue,
  type IssueView,
} from "./model";

interface Delivery {
  prNumber: number | null;
  prUrl: string | null;
  version: string | null;
}

/** PR fusionnée qui a fermé l'Issue et version de `app/pubspec.yaml` à son commit. */
async function findDelivery(client: GithubClient, issueNumber: number): Promise<Delivery> {
  const sha = closingCommitFromEvents(await client.listIssueEvents(issueNumber));
  if (sha === null) return { prNumber: null, prUrl: null, version: null };
  const pr = pickDeliveredPr(
    await client.pullsForCommit(sha),
    issueNumber,
    GITHUB_MAINTAINER_ID,
    GITHUB_REPO_FULL_NAME,
  );
  if (pr === null) return { prNumber: null, prUrl: null, version: null };
  let version: string | null = null;
  try {
    const text = await client.fileAtCommit(PUBSPEC_PATH, pr.mergeCommitSha ?? sha);
    version = text === null ? null : pubspecVersionName(text);
  } catch (err) {
    if (!(err instanceof GithubError) || err.kind !== "not_found") throw err;
    logError({
      message: `Tickets : ${PUBSPEC_PATH} absent au commit de livraison de l'Issue #${issueNumber}`,
      feature: "tickets",
      error: err,
    });
  }
  return { prNumber: pr.number, prUrl: pr.url, version };
}

/**
 * Applique l'état d'une Issue à son ticket. Les commentaires sont relus quand l'Issue a
 * changé depuis la dernière lecture, ou toujours avec `forceComments` (commentaire modifié
 * ou supprimé, qui ne change pas `updated_at` de l'Issue) : réponse « Réponse : » et
 * analyses en une lecture. Un état antérieur au dernier retour à « Reçu » d'une réponse de
 * l'admin (`answer_reset_at`) ne change pas le statut. Lève en cas d'échec : les analyses
 * sont écrites avant le ticket, et un échec laisse `github_updated_at` inchangé pour que la
 * passe suivante relise.
 */
export async function applyIssue(
  client: GithubClient,
  doc: DocumentSnapshot,
  issue: IssueView,
  opts: { forceComments?: boolean } = {},
): Promise<void> {
  const { FieldValue, Timestamp } = await firestore();
  const data = doc.data() ?? {};
  const current = data.status;
  if (!isPublishedStatus(current)) return;
  const resetAt = data.answer_reset_at;
  const stale = isStaleIssueSnapshot(
    issue.updatedAt,
    resetAt instanceof Timestamp ? resetAt.toMillis() : null,
  );
  const next = stale ? current : nextStatus(current, statusFromIssue(issue));
  const now = Timestamp.now();
  const update: Record<string, unknown> = {
    github_checked_at: now,
    github_updated_at: issue.updatedAt,
    updated_at: now,
  };
  if (next !== current) {
    update.status = next;
    update.status_changed_at = now;
  }
  // Une validation de l'application ne survit pas à un statut hors `validated` et
  // `in_progress`, ni un champ resté posé sur un ticket qui n'était pas validé : un `validé`
  // reposé plus tard sur GitHub ne permet pas de lancer.
  const byApp =
    keepsAppValidation(current) &&
    keepsAppValidation(next) &&
    isValidatedByApp(data.validated_by_app_at);
  if (!byApp && isValidatedByApp(data.validated_by_app_at)) update.validated_by_app_at = null;
  // Réécrit à chaque changement de statut, et posé sur un ticket qui ne l'a pas (T2).
  if (next !== current || !allowedDecisionsUpToDate(data.allowed_decisions, next, byApp)) {
    update.allowed_decisions = allowedDecisions(next, byApp);
  }
  if (data.issue_missing_since != null) update.issue_missing_since = FieldValue.delete();

  if (opts.forceComments === true || issue.updatedAt !== data.github_updated_at) {
    const comments =
      issue.comments > 0 ? await client.recentComments(issue.number, issue.comments) : [];
    await writeTicketAnalyses(doc.id, comments);
    const reply = lastReply(comments, GITHUB_MAINTAINER_ID, REPLY_MAX_CHARS);
    if (reply !== null && reply.text !== data.reply_text) {
      const atMs = reply.at === null ? Number.NaN : Date.parse(reply.at);
      update.reply_text = reply.text;
      update.reply_at = Number.isNaN(atMs) ? now : Timestamp.fromMillis(atMs);
      update.status_changed_at = now;
    }
  }

  if (next === "delivered" && (current !== "delivered" || data.delivered_checked_at == null)) {
    const delivery = await findDelivery(client, issue.number);
    update.delivered_pr_number = delivery.prNumber;
    update.delivered_pr_url = delivery.prUrl;
    update.delivered_version = delivery.version;
    update.delivered_checked_at = now;
  } else if (current === "delivered" && next !== "delivered") {
    update.delivered_pr_number = FieldValue.delete();
    update.delivered_pr_url = FieldValue.delete();
    update.delivered_version = FieldValue.delete();
    update.delivered_checked_at = FieldValue.delete();
  }

  // Le statut est recalculé sur le ticket relu en transaction : une réponse de l'admin
  // (`answer_reset_at`) ou une décision écrite pendant la lecture de GitHub n'est pas
  // écrasée. Si le statut relu diffère de celui de la lecture, les champs de livraison
  // attendent la passe suivante.
  const { db } = await firestore();
  const written = await db.runTransaction(async (tx) => {
    const fresh = await tx.get(doc.ref);
    if (!fresh.exists) return null;
    const f = fresh.data() ?? {};
    const freshCurrent = f.status;
    if (!isPublishedStatus(freshCurrent)) return null;
    const freshReset = f.answer_reset_at;
    const freshStale = isStaleIssueSnapshot(
      issue.updatedAt,
      freshReset instanceof Timestamp ? freshReset.toMillis() : null,
    );
    const freshNext = freshStale ? freshCurrent : nextStatus(freshCurrent, statusFromIssue(issue));
    const out: Record<string, unknown> = { ...update };
    delete out.status;
    delete out.allowed_decisions;
    delete out.validated_by_app_at;
    if (freshCurrent !== current || freshNext !== next) {
      for (const k of Object.keys(out)) if (k.startsWith("delivered_")) delete out[k];
      if (out.status_changed_at !== undefined && out.reply_text === undefined) {
        delete out.status_changed_at;
      }
    }
    if (freshNext !== freshCurrent) {
      out.status = freshNext;
      out.status_changed_at = now;
    }
    const freshByApp =
      keepsAppValidation(freshCurrent) &&
      keepsAppValidation(freshNext) &&
      isValidatedByApp(f.validated_by_app_at);
    if (!freshByApp && isValidatedByApp(f.validated_by_app_at)) out.validated_by_app_at = null;
    if (
      freshNext !== freshCurrent ||
      !allowedDecisionsUpToDate(f.allowed_decisions, freshNext, freshByApp)
    ) {
      out.allowed_decisions = allowedDecisions(freshNext, freshByApp);
    }
    tx.update(doc.ref, out);
    return { from: freshCurrent, to: freshNext };
  });
  if (written !== null && written.to !== written.from) {
    logInfo({
      message: `Tickets : Issue #${issue.number}, ${written.from} → ${written.to}`,
      feature: "tickets",
      ticketId: doc.id,
    });
  }
}
