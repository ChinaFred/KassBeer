/**
 * État d'une Issue appliqué à son ticket : statut, décisions permises, réponse
 * « Réponse : » du compte 16348852, PR de livraison et version. Appelé par la passe
 * horaire (`sync.ts`) et par une décision qui trouve son Issue déjà fermée
 * (`decisions.ts`).
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
import { allowedDecisions, allowedDecisionsUpToDate } from "./decisionModel";
import { GithubError, type GithubClient } from "./github";
import {
  closingCommitFromEvents,
  isPublishedStatus,
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

/** Dernière réponse du compte propriétaire, lue de la dernière page vers la première. */
async function findReply(client: GithubClient, issue: IssueView) {
  for await (const page of client.lastCommentsFirst(issue.number, issue.comments)) {
    const reply = lastReply(page, GITHUB_MAINTAINER_ID, REPLY_MAX_CHARS);
    if (reply !== null) return reply;
  }
  return null;
}

/** Applique l'état d'une Issue à son ticket. Lève en cas d'échec : rien n'est écrit. */
export async function applyIssue(
  client: GithubClient,
  doc: DocumentSnapshot,
  issue: IssueView,
): Promise<void> {
  const { FieldValue, Timestamp } = await firestore();
  const data = doc.data() ?? {};
  const current = data.status;
  if (!isPublishedStatus(current)) return;
  const next = nextStatus(current, statusFromIssue(issue));
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
  // Réécrit à chaque changement de statut, et posé sur un ticket qui ne l'a pas (T2).
  if (next !== current || !allowedDecisionsUpToDate(data.allowed_decisions, next)) {
    update.allowed_decisions = allowedDecisions(next);
  }
  if (data.issue_missing_since != null) update.issue_missing_since = FieldValue.delete();

  if (issue.comments > 0 && issue.updatedAt !== data.github_updated_at) {
    const reply = await findReply(client, issue);
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

  await doc.ref.update(update);
  if (next !== current) {
    logInfo({
      message: `Tickets : Issue #${issue.number}, ${current} → ${next}`,
      feature: "tickets",
      ticketId: doc.id,
    });
  }
}
