/**
 * Passe horaire des tickets (ADR-006, CA26 à CA31, T2) :
 *
 * 1. `allowed_decisions` réécrit une fois par version de la règle (tickets écrits avant
 *    T2, liste de T3 : `analyzed`, `answer`, puis liste de T4 : Valider depuis `analyzed`
 *    seul, lancements) ; marque
 *    `allowed_decisions_backfill_version` dans `ticket_status/github` ;
 * 2. renvoi des tickets `pending` (20 au plus), par `publishTicket` ;
 * 3. Issues `source:app` modifiées depuis le curseur `issues_cursor` de
 *    `ticket_status/github`, les plus anciennes d'abord : statut, décisions permises,
 *    réponse « Réponse : » du compte 16348852, analyses et précisions (P32), PR de
 *    livraison et version ;
 * 4. avec le reste des 30 Issues de la passe : tickets à Issue ouverte les moins
 *    récemment relus, Issue et commentaires lus un à un (un commentaire modifié ne
 *    change pas la date de l'Issue). Une Issue disparue (404 ou 410, dépôt joignable)
 *    laisse le statut et pose `issue_missing_since` ;
 * 5. livraison (T5, P46) : verrou des livraisons libéré si son ticket n'est plus
 *    `in_progress` ; état « PR prête » de chaque ticket `in_progress` (30 au plus), liste
 *    des PR ouvertes lue une fois et partagée.
 *
 * Avant tout, sans GitHub : `ticket_status/launches` remis au jour de Paris (T4).
 *
 * Depuis T7 (ADR-008), la passe ne relance aucun envoi et ne reprend aucune décision :
 * l'admin le fait par `retryTicketSend` et par un nouvel appel de la décision.
 *
 * Un jeton refusé arrête la passe. Chaque ticket est traité seul : une erreur est
 * journalisée et la passe continue.
 */

import type { DocumentSnapshot } from "firebase-admin/firestore";

import {
  COLL_TICKET_STATUS,
  COLL_TICKETS,
  ISSUES_PER_PASS,
  PENDING_PER_PASS,
  TICKET_STATUS_GITHUB_DOC,
} from "../config";
import { firestore } from "../firestore";
import { logError, logInfo } from "../logging";
import {
  allowedDecisions,
  allowedDecisionsUpToDate,
  isValidatedByApp,
  keepsAppValidation,
} from "./decisionModel";
import { GithubError, githubClient, type FetchLike, type GithubClient } from "./github";
import {
  refreshTicketDelivery,
  releaseDeliveryLockIfLeft,
  type OpenPullRequests,
} from "./delivery";
import { applyIssue } from "./issueState";
import { refreshLaunchStatus } from "./launch";
import { LABEL_SOURCE_APP, OPEN_STATUSES, type IssueView } from "./model";
import { publishTicket } from "./publish";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

/** Tickets lus par page lors de la pose initiale de `allowed_decisions`. */
const BACKFILL_PAGE = 200;

/**
 * Version de la règle `allowedDecisions` : à chaque changement de la règle, la pose
 * initiale repasse une fois sur tous les tickets. 2 : statut `analyzed` et `answer`
 * (ADR-008, T3). 3 : Valider depuis `analyzed` seul, `launch_analysis` et
 * `launch_development` (ADR-008, T4). 4 : `launch_development` réservé à un ticket validé
 * dans l'application (`validated_by_app_at`), Valider offert sinon (ADR-008, 2026-11-13).
 * 5 : `launch_delivery` et `relaunch_development` sur un ticket `in_progress` validé dans
 * l'application (ADR-008, T5).
 */
export const ALLOWED_DECISIONS_VERSION = 5;

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
  await applyIssue(client, doc, issue, { forceComments: true });
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

/** Étape 3 : Issues modifiées depuis le curseur. Rend les numéros traités. */
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

/**
 * Étape 1 : `allowed_decisions` posé sur chaque ticket qui ne l'a pas ou dont la liste ne
 * suit pas le statut, une fois par version de la règle (`ALLOWED_DECISIONS_VERSION`).
 * Ensuite, chaque changement de statut l'écrit. Chaque ticket est corrigé en transaction : un statut
 * changé entre-temps n'est pas écrasé. Ne lève pas. Exportée pour les tests.
 */
export async function backfillAllowedDecisions(): Promise<void> {
  try {
    const { db, FieldPath, Timestamp } = await firestore();
    const statusRef = db.collection(COLL_TICKET_STATUS).doc(TICKET_STATUS_GITHUB_DOC);
    if (
      (await statusRef.get()).get("allowed_decisions_backfill_version") ===
      ALLOWED_DECISIONS_VERSION
    ) {
      return;
    }
    let fixed = 0;
    let last: DocumentSnapshot | null = null;
    for (;;) {
      let query = db
        .collection(COLL_TICKETS)
        .orderBy(FieldPath.documentId())
        .select("status", "allowed_decisions", "validated_by_app_at")
        .limit(BACKFILL_PAGE);
      if (last !== null) query = query.startAfter(last);
      const page = await query.get();
      for (const doc of page.docs) {
        const byAppOf = (snap: DocumentSnapshot) =>
          keepsAppValidation(snap.get("status")) &&
          isValidatedByApp(snap.get("validated_by_app_at"));
        if (allowedDecisionsUpToDate(doc.get("allowed_decisions"), doc.get("status"), byAppOf(doc)))
          continue;
        await db.runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          if (!fresh.exists) return;
          const status = fresh.get("status");
          const byApp = byAppOf(fresh);
          if (allowedDecisionsUpToDate(fresh.get("allowed_decisions"), status, byApp)) return;
          tx.update(doc.ref, { allowed_decisions: allowedDecisions(status, byApp) });
        });
        fixed++;
      }
      if (page.docs.length < BACKFILL_PAGE) break;
      last = page.docs[page.docs.length - 1];
    }
    await statusRef.set(
      {
        allowed_decisions_backfill_version: ALLOWED_DECISIONS_VERSION,
        allowed_decisions_backfilled_at: Timestamp.now(),
      },
      { merge: true },
    );
    logInfo({
      message: `Tickets : décisions permises posées sur ${fixed} ticket(s)`,
      feature: "tickets",
    });
  } catch (err) {
    // La marque n'est pas posée : la passe suivante reprend.
    logError({
      message: "Tickets : pose initiale des décisions permises en échec",
      feature: "tickets",
      error: err,
    });
  }
}

/**
 * Étape 5 : verrou des livraisons libéré si son ticket n'est plus `in_progress`, puis état
 * « PR prête » de chaque ticket `in_progress` (P46). La liste des PR ouvertes est lue une
 * fois, au premier ticket. Chaque ticket est traité seul ; un jeton refusé arrête la passe.
 */
async function refreshDeliveries(client: GithubClient): Promise<void> {
  const kit = await firestore();
  await releaseDeliveryLockIfLeft(kit, null, Date.now());
  const snap = await kit.db
    .collection(COLL_TICKETS)
    .where("status", "==", "in_progress")
    .limit(ISSUES_PER_PASS)
    .get();
  let openPrs: OpenPullRequests | null = null;
  for (const doc of snap.docs) {
    const issueNumber = doc.get("github_issue_number");
    if (typeof issueNumber !== "number") continue;
    await guarded(doc.id, async () => {
      openPrs ??= await client.listOpenPullRequests();
      await refreshTicketDelivery(kit, client, doc.id, issueNumber, openPrs);
    });
  }
}

/** Passe complète. Ne lève pas. */
export async function runHourlyPass(token: string, fetchImpl?: FetchLike): Promise<void> {
  const passStart = new Date();
  // Sans GitHub : compteurs des lancements remis au jour de Paris (ADR-008, T4).
  await refreshLaunchStatus();
  try {
    const trimmed = token.trim();
    if (trimmed.length === 0) {
      await markTokenInvalid(null);
      return;
    }
    const { db } = await firestore();

    await backfillAllowedDecisions();

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
    await refreshDeliveries(client);
    await recordTokenAccepted(client);
  } catch (err) {
    if (err instanceof TokenRefused) {
      await markTokenInvalid(err.cause);
      return;
    }
    logError({ message: "Tickets : passe horaire interrompue", feature: "tickets", error: err });
  }
}
