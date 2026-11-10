/**
 * Passe horaire des tickets (ADR-006, CA26 à CA31) :
 *
 * 1. renvoi des tickets `pending` (20 au plus), par `publishTicket` ;
 * 2. Issues `source:app` modifiées depuis le curseur `issues_cursor` de
 *    `ticket_status/github`, les plus anciennes d'abord : statut, réponse « Réponse : »
 *    du compte 16348852, PR de livraison et version ;
 * 3. avec le reste des 30 Issues de la passe : tickets à Issue ouverte les moins
 *    récemment relus, Issue lue une à une. Une Issue disparue (404 ou 410, dépôt
 *    joignable) laisse le statut et pose `issue_missing_since`.
 *
 * Un jeton refusé arrête la passe. Chaque ticket est traité seul : une erreur est
 * journalisée et la passe continue.
 */

import type { DocumentSnapshot } from "firebase-admin/firestore";

import {
  COLL_TICKET_STATUS,
  COLL_TICKETS,
  GITHUB_MAINTAINER_ID,
  GITHUB_REPO_FULL_NAME,
  ISSUES_PER_PASS,
  PENDING_PER_PASS,
  PUBSPEC_PATH,
  REPLY_MAX_CHARS,
  TICKET_STATUS_GITHUB_DOC,
} from "../config";
import { firestore } from "../firestore";
import { logError, logInfo } from "../logging";
import { GithubError, githubClient, type FetchLike, type GithubClient } from "./github";
import {
  LABEL_SOURCE_APP,
  OPEN_STATUSES,
  closingCommitFromEvents,
  isPublishedStatus,
  lastReply,
  nextStatus,
  pickDeliveredPr,
  pubspecVersionName,
  statusFromIssue,
  type IssueView,
} from "./model";
import { publishTicket } from "./publish";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

/** Marge du curseur : une Issue modifiée pendant la passe précédente est relue. */
const CURSOR_MARGIN_MS = 10 * 60 * 1000;

class TokenRefused extends Error {
  constructor(readonly cause: GithubError) {
    super("jeton refusé");
  }
}

function isTokenError(err: unknown): err is GithubError {
  return err instanceof GithubError && err.kind === "token";
}

/**
 * Nouveau curseur après une lecture de la liste. Page pleine : la date de la dernière
 * Issue lue (une seconde de plus si elle n'avance pas). Sinon : début de la passe moins la
 * marge. Pure.
 */
export function nextCursor(
  issues: readonly Pick<IssueView, "updatedAt">[],
  perPage: number,
  previous: string | null,
  passStart: Date,
): string {
  const fallback = new Date(passStart.getTime() - CURSOR_MARGIN_MS).toISOString();
  if (issues.length < perPage) return fallback;
  const last = issues[issues.length - 1].updatedAt;
  const lastMs = last === null ? Number.NaN : Date.parse(last);
  if (Number.isNaN(lastMs)) return fallback;
  const previousMs = previous === null ? Number.NaN : Date.parse(previous);
  const ms = !Number.isNaN(previousMs) && lastMs <= previousMs ? previousMs + 1000 : lastMs;
  return new Date(ms).toISOString();
}

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
async function applyIssue(
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

/** Relit une Issue et l'applique ; une Issue disparue pose `issue_missing_since`. */
async function refreshOne(client: GithubClient, doc: DocumentSnapshot): Promise<void> {
  const issueNumber = doc.get("github_issue_number");
  if (typeof issueNumber !== "number") return;
  let issue: IssueView;
  try {
    issue = await client.getIssue(issueNumber);
  } catch (err) {
    if (!(err instanceof GithubError) || err.kind !== "not_found") throw err;
    const { Timestamp } = await firestore();
    const now = Timestamp.now();
    const firstTime = doc.get("issue_missing_since") == null;
    // Journalisée à chaque passe : l'erreur reste visible tant que l'Issue manque.
    logError({
      message: `Tickets : Issue #${issueNumber} disparue (HTTP ${err.status}), statut gardé`,
      feature: "tickets",
      ticketId: doc.id,
      error: err,
      extra: { first_time: firstTime },
    });
    await doc.ref.update({
      github_checked_at: now,
      updated_at: now,
      ...(firstTime ? { issue_missing_since: now } : {}),
    });
    return;
  }
  await applyIssue(client, doc, issue);
}

async function guarded(ticketId: string, work: () => Promise<void>): Promise<void> {
  try {
    await work();
  } catch (err) {
    if (isTokenError(err)) throw new TokenRefused(err);
    logError({
      message: "Tickets : relecture de l'Issue en échec",
      feature: "tickets",
      ticketId,
      error: err,
    });
  }
}

/** Étape 2 : Issues modifiées depuis le curseur. Rend les numéros traités. */
async function syncUpdatedIssues(client: GithubClient, passStart: Date): Promise<Set<number>> {
  const { db } = await firestore();
  const statusRef = db.collection(COLL_TICKET_STATUS).doc(TICKET_STATUS_GITHUB_DOC);
  const cursorValue = (await statusRef.get()).get("issues_cursor");
  const cursor = typeof cursorValue === "string" ? cursorValue : null;
  let issues: IssueView[];
  try {
    issues = await client.listIssuesUpdatedSince(LABEL_SOURCE_APP, cursor, ISSUES_PER_PASS);
  } catch (err) {
    if (isTokenError(err)) throw new TokenRefused(err);
    throw err;
  }
  const handled = new Set<number>();
  if (issues.length > 0) {
    const byNumber = new Map(issues.map((i) => [i.number, i]));
    const snap = await db
      .collection(COLL_TICKETS)
      .where("github_issue_number", "in", [...byNumber.keys()])
      .get();
    for (const doc of snap.docs) {
      const issue = byNumber.get(doc.get("github_issue_number"));
      if (issue === undefined) continue;
      handled.add(issue.number);
      await guarded(doc.id, () => applyIssue(client, doc, issue));
    }
  }
  await statusRef.set(
    { issues_cursor: nextCursor(issues, ISSUES_PER_PASS, cursor, passStart) },
    { merge: true },
  );
  return handled;
}

/** Passe complète. Ne lève pas. */
export async function runHourlyPass(token: string, fetchImpl?: FetchLike): Promise<void> {
  const passStart = new Date();
  try {
    const trimmed = token.trim();
    if (trimmed.length === 0) {
      await markTokenInvalid(null);
      return;
    }
    const { db } = await firestore();

    const pending = await db
      .collection(COLL_TICKETS)
      .where("status", "==", "pending")
      .orderBy("created_at")
      .limit(PENDING_PER_PASS)
      .get();
    for (const doc of pending.docs) {
      if ((await publishTicket(doc.id, trimmed, fetchImpl)) === "token") return;
    }

    const client = githubClient(trimmed, fetchImpl);
    const handled = await syncUpdatedIssues(client, passStart);
    const budget = ISSUES_PER_PASS - handled.size;
    if (budget > 0) {
      const open = await db
        .collection(COLL_TICKETS)
        .where("status", "in", [...OPEN_STATUSES])
        .orderBy("github_checked_at")
        .limit(budget)
        .get();
      for (const doc of open.docs) {
        if (handled.has(doc.get("github_issue_number"))) continue;
        await guarded(doc.id, () => refreshOne(client, doc));
      }
    }
    await recordTokenAccepted(client);
  } catch (err) {
    if (err instanceof TokenRefused) {
      await markTokenInvalid(err.cause);
      return;
    }
    logError({ message: "Tickets : passe horaire interrompue", feature: "tickets", error: err });
  }
}
