/**
 * Publication d'un ticket `pending` en Issue (ADR-006, CA9 à CA17). Appelée par le
 * déclencheur de création et par la tâche horaire.
 *
 * 1. Transaction : le ticket doit être `pending`, sans numéro d'Issue, sans bail actif.
 *    Au premier essai, le plafond du jour de Paris est décidé et compté une fois pour
 *    toutes (`send_quota_day`) : au-delà, le ticket passe `over_quota`. Puis bail de deux
 *    minutes (`send_lease_until`).
 * 2. Un essai précédent a commencé (`send_attempts` > 0 ou un bail déjà posé) : l'Issue
 *    est d'abord cherchée par la référence du ticket, pour ne pas la publier deux fois.
 * 3. Succès : `received`, numéro et adresse de l'Issue, sans `status_changed_at` (la
 *    pastille ne s'allume pas à ce passage).
 * 4. Échec : `last_send_error`, `send_attempts` + 1, au dixième `send_failed`. Un jeton
 *    refusé ou une limite de débit n'usent pas les essais.
 */

import {
  COLL_MEMBERS,
  COLL_TICKET_QUOTAS,
  COLL_TICKETS,
  GITHUB_REPO_FULL_NAME,
  GROUP_DAILY_LIMIT,
  MAX_SEND_ATTEMPTS,
  MEMBER_DAILY_LIMIT,
  QUOTA_TTL_DAYS,
  SEND_LEASE_MS,
} from "../config";
import { firestore } from "../firestore";
import { describeError, logError, logInfo, logWarn } from "../logging";
import { GithubError, githubClient, type FetchLike } from "./github";
import {
  buildIssueBody,
  buildIssueTitle,
  creationLabels,
  groupQuotaDocId,
  isTicketPlatform,
  isTicketType,
  memberQuotaDocId,
  parisDay,
  quotaRefusal,
  readCount,
  type QuotaReason,
} from "./model";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

export type PublishOutcome =
  "published" | "skipped" | "over_quota" | "failed" | "send_failed" | "token" | "invalid";

/** Identifiant de document plausible : il entre dans le corps de l'Issue, qui part en public. */
export function isPlausibleTicketId(value: string): boolean {
  return /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

/** Adresse de l'Issue, construite depuis son numéro. */
export function issueUrl(issueNumber: number): string {
  return `https://github.com/${GITHUB_REPO_FULL_NAME}/issues/${issueNumber}`;
}

/** Marge avant `created_at` pour la liste des Issues lue avant une republication. */
const LOOKUP_MARGIN_MS = 10 * 60 * 1000;

/**
 * Début de la liste lue avant une republication : `created_at` du ticket moins dix
 * minutes, ou `null` (toute la liste, bornée) s'il est illisible. Pure.
 */
export function lookupSince(createdAt: unknown): string | null {
  const toMillis = (createdAt as { toMillis?: unknown } | null)?.toMillis;
  if (typeof toMillis !== "function") return null;
  const ms = Number(toMillis.call(createdAt));
  return Number.isFinite(ms) ? new Date(ms - LOOKUP_MARGIN_MS).toISOString() : null;
}

type Claim =
  | { kind: "skip" }
  | { kind: "over_quota"; reason: QuotaReason }
  | { kind: "claimed"; data: Record<string, unknown>; lookupFirst: boolean };

async function claim(ticketId: string, now: Date): Promise<Claim> {
  const { db, Timestamp } = await firestore();
  const ref = db.collection(COLL_TICKETS).doc(ticketId);
  return db.runTransaction(async (tx): Promise<Claim> => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { kind: "skip" };
    const data = snap.data() ?? {};
    if (data.status !== "pending" || data.github_issue_number != null) return { kind: "skip" };
    const lease = data.send_lease_until;
    if (lease instanceof Timestamp && lease.toMillis() > now.getTime()) return { kind: "skip" };

    const nowTs = Timestamp.fromDate(now);
    const update: Record<string, unknown> = {
      send_lease_until: Timestamp.fromMillis(now.getTime() + SEND_LEASE_MS),
      updated_at: nowTs,
    };

    if (typeof data.send_quota_day !== "string") {
      // Toutes les lectures avant la première écriture de la transaction.
      const day = parisDay(now);
      const email = typeof data.author_email === "string" ? data.author_email : "";
      const uid = typeof data.author_uid === "string" ? data.author_uid : "";
      const member = email ? await tx.get(db.collection(COLL_MEMBERS).doc(email)) : null;
      const isAdmin = member?.get("role") === "admin";
      if (!isAdmin) {
        const memberRef = db.collection(COLL_TICKET_QUOTAS).doc(memberQuotaDocId(uid, day));
        const groupRef = db.collection(COLL_TICKET_QUOTAS).doc(groupQuotaDocId(day));
        const [memberSnap, groupSnap] = await Promise.all([tx.get(memberRef), tx.get(groupRef)]);
        const memberCount = readCount(memberSnap.data());
        const groupCount = readCount(groupSnap.data());
        const refusal = quotaRefusal({
          isAdmin,
          memberCount,
          groupCount,
          memberLimit: MEMBER_DAILY_LIMIT,
          groupLimit: GROUP_DAILY_LIMIT,
        });
        if (refusal !== null) {
          tx.update(ref, {
            status: "over_quota",
            over_quota_reason: refusal,
            send_quota_day: day,
            status_changed_at: nowTs,
            updated_at: nowTs,
          });
          return { kind: "over_quota", reason: refusal };
        }
        const expiresAt = Timestamp.fromMillis(now.getTime() + QUOTA_TTL_DAYS * 86_400_000);
        tx.set(memberRef, { count: memberCount + 1, day, expires_at: expiresAt });
        tx.set(groupRef, { count: groupCount + 1, day, expires_at: expiresAt });
      }
      update.send_quota_day = day;
    }

    tx.update(ref, update);
    const attempts = typeof data.send_attempts === "number" ? data.send_attempts : 0;
    return { kind: "claimed", data, lookupFirst: attempts > 0 || lease != null };
  });
}

async function recordPublished(ticketId: string, issueNumber: number): Promise<void> {
  const { db, FieldValue, Timestamp } = await firestore();
  const now = Timestamp.now();
  await db
    .collection(COLL_TICKETS)
    .doc(ticketId)
    .update({
      status: "received",
      github_issue_number: issueNumber,
      github_url: issueUrl(issueNumber),
      github_checked_at: now,
      last_send_error: FieldValue.delete(),
      send_lease_until: FieldValue.delete(),
      updated_at: now,
    });
}

/** Enregistre un échec. Rend `send_failed` si le plafond d'essais est atteint. */
async function recordFailure(
  ticketId: string,
  data: Record<string, unknown>,
  message: string,
  countsAsAttempt: boolean,
): Promise<"failed" | "send_failed"> {
  const { db, FieldValue, Timestamp } = await firestore();
  const now = Timestamp.now();
  const before = typeof data.send_attempts === "number" ? data.send_attempts : 0;
  const attempts = countsAsAttempt ? before + 1 : before;
  const exhausted = attempts >= MAX_SEND_ATTEMPTS;
  await db
    .collection(COLL_TICKETS)
    .doc(ticketId)
    .update({
      send_attempts: attempts,
      last_send_error: message.slice(0, 300),
      send_lease_until: FieldValue.delete(),
      updated_at: now,
      ...(exhausted ? { status: "send_failed", status_changed_at: now } : {}),
    });
  return exhausted ? "send_failed" : "failed";
}

async function safeRecordFailure(
  ticketId: string,
  data: Record<string, unknown>,
  message: string,
  countsAsAttempt: boolean,
): Promise<"failed" | "send_failed"> {
  try {
    return await recordFailure(ticketId, data, message, countsAsAttempt);
  } catch (err) {
    logError({
      message: "Tickets : échec d'envoi non enregistré",
      feature: "tickets",
      ticketId,
      error: err,
    });
    return "failed";
  }
}

/**
 * Publie le ticket s'il est `pending`. Ne lève pas : chaque erreur est journalisée et le
 * résultat dit ce qui s'est passé. `token` vide : le jeton est déclaré absent, le ticket
 * reste `pending` sans changement ni plafond compté.
 */
export async function publishTicket(
  ticketId: string,
  token: string,
  fetchImpl?: FetchLike,
): Promise<PublishOutcome> {
  if (token.trim().length === 0) {
    await markTokenInvalid(null);
    return "token";
  }
  if (!isPlausibleTicketId(ticketId)) {
    logError({
      message: "Tickets : identifiant de ticket refusé",
      feature: "tickets",
      extra: { length: ticketId.length },
    });
    return "invalid";
  }

  let claimed: Claim;
  try {
    claimed = await claim(ticketId, new Date());
  } catch (err) {
    logError({
      message: "Tickets : envoi impossible à préparer",
      feature: "tickets",
      ticketId,
      error: err,
    });
    return "failed";
  }
  if (claimed.kind === "skip") return "skipped";
  if (claimed.kind === "over_quota") {
    logInfo({
      message: "Tickets : plafond du jour atteint, ticket non publié",
      feature: "tickets",
      ticketId,
      extra: { reason: claimed.reason },
    });
    return "over_quota";
  }

  const data = claimed.data;
  if (
    !isTicketType(data.type) ||
    !isTicketPlatform(data.platform) ||
    typeof data.title !== "string" ||
    typeof data.description !== "string"
  ) {
    logError({ message: "Tickets : ticket illisible, non publié", feature: "tickets", ticketId });
    await safeRecordFailure(
      ticketId,
      { send_attempts: MAX_SEND_ATTEMPTS },
      "Ticket illisible.",
      false,
    );
    return "invalid";
  }

  const client = githubClient(token.trim(), fetchImpl);
  let issue: { number: number } | null = null;
  try {
    if (claimed.lookupFirst) {
      issue = await client.findIssueByReference(ticketId, lookupSince(data.created_at));
      if (issue !== null) {
        logWarn({
          message: `Tickets : Issue #${issue.number} déjà créée, rattachée sans nouvel envoi`,
          feature: "tickets",
          ticketId,
        });
      }
    }
    if (issue === null) {
      issue = await client.createIssue({
        title: buildIssueTitle(data.title),
        body: buildIssueBody({
          ticketId,
          type: data.type,
          description: data.description,
          screen: data.screen,
          appVersion: data.app_version,
          platform: data.platform,
        }),
        labels: creationLabels(data.type),
      });
    }
  } catch (err) {
    const kind = err instanceof GithubError ? err.kind : "other";
    logError({
      message: "Tickets : envoi vers GitHub en échec",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { kind },
    });
    if (kind === "token") {
      await safeRecordFailure(ticketId, data, describeError(err), false);
      await markTokenInvalid(err as GithubError);
      return "token";
    }
    return safeRecordFailure(ticketId, data, describeError(err), kind !== "rate_limit");
  }

  try {
    await recordPublished(ticketId, issue.number);
  } catch (err) {
    // L'Issue existe sans que son numéro soit écrit : l'essai suivant la retrouve par sa
    // référence au lieu d'en publier une seconde (le bail reste posé, il le signale).
    logError({
      message: `Tickets : Issue #${issue.number} créée mais non enregistrée`,
      feature: "tickets",
      ticketId,
      error: err,
    });
    return "failed";
  }
  logInfo({
    message: `Tickets : ticket publié en Issue #${issue.number}`,
    feature: "tickets",
    ticketId,
  });
  await recordTokenAccepted(client);
  return "published";
}
