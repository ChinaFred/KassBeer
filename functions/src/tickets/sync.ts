/**
 * Passe horaire des tickets (ADR-006, CA26 à CA31, T2) :
 *
 * 1. `allowed_decisions` posé une fois sur les tickets écrits avant T2 (marque
 *    `allowed_decisions_backfilled_at` dans `ticket_status/github`) ;
 * 2. relance des tickets `send_failed` dont l'admin a demandé un nouvel essai
 *    (`retry_requested_at`) : `send_attempts` à 0, `pending`, puis nouvel essai ;
 * 3. renvoi des tickets `pending` (20 au plus), par `publishTicket` ;
 * 4. reprise des décisions restées `applying` après l'expiration de leur bail, et des
 *    décisions encore `pending` cinq minutes après leur création ;
 * 5. Issues `source:app` modifiées depuis le curseur `issues_cursor` de
 *    `ticket_status/github`, les plus anciennes d'abord : statut, décisions permises,
 *    réponse « Réponse : » du compte 16348852, PR de livraison et version ;
 * 6. avec le reste des 30 Issues de la passe : tickets à Issue ouverte les moins
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
  ISSUES_PER_PASS,
  PENDING_PER_PASS,
  TICKET_STATUS_GITHUB_DOC,
} from "../config";
import { firestore } from "../firestore";
import { logError, logInfo } from "../logging";
import {
  allowedDecisions,
  allowedDecisionsUpToDate,
  isResumableByPass,
  stalePendingCutoffMs,
} from "./decisionModel";
import { COLL_DECISIONS, applyDecision } from "./decisions";
import { GithubError, githubClient, type FetchLike, type GithubClient } from "./github";
import { applyIssue } from "./issueState";
import { LABEL_SOURCE_APP, OPEN_STATUSES, type IssueView } from "./model";
import { publishTicket } from "./publish";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

/** Décisions `applying` reprises au plus par passe. */
const DECISIONS_PER_PASS = 20;

/** Tickets lus par page lors de la pose initiale de `allowed_decisions`. */
const BACKFILL_PAGE = 200;

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

/**
 * Étape 1 : `allowed_decisions` posé sur chaque ticket qui ne l'a pas ou dont la liste ne
 * suit pas le statut, une seule fois (tickets écrits avant T2). Ensuite, chaque
 * changement de statut l'écrit. Chaque ticket est corrigé en transaction : un statut
 * changé entre-temps n'est pas écrasé. Ne lève pas.
 */
async function backfillAllowedDecisions(): Promise<void> {
  try {
    const { db, FieldPath, Timestamp } = await firestore();
    const statusRef = db.collection(COLL_TICKET_STATUS).doc(TICKET_STATUS_GITHUB_DOC);
    if ((await statusRef.get()).get("allowed_decisions_backfilled_at") != null) return;
    let fixed = 0;
    let last: DocumentSnapshot | null = null;
    for (;;) {
      let query = db
        .collection(COLL_TICKETS)
        .orderBy(FieldPath.documentId())
        .select("status", "allowed_decisions")
        .limit(BACKFILL_PAGE);
      if (last !== null) query = query.startAfter(last);
      const page = await query.get();
      for (const doc of page.docs) {
        if (allowedDecisionsUpToDate(doc.get("allowed_decisions"), doc.get("status"))) continue;
        await db.runTransaction(async (tx) => {
          const fresh = await tx.get(doc.ref);
          if (!fresh.exists) return;
          const status = fresh.get("status");
          if (allowedDecisionsUpToDate(fresh.get("allowed_decisions"), status)) return;
          tx.update(doc.ref, { allowed_decisions: allowedDecisions(status) });
        });
        fixed++;
      }
      if (page.docs.length < BACKFILL_PAGE) break;
      last = page.docs[page.docs.length - 1];
    }
    await statusRef.set({ allowed_decisions_backfilled_at: Timestamp.now() }, { merge: true });
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
 * Étape 2 : tickets `send_failed` avec `retry_requested_at` (relance demandée par
 * l'admin). En transaction : `pending`, `send_attempts` à 0, `send_retried_at` posé (la
 * publication cherche d'abord une Issue déjà créée), `retry_requested_at` retiré. Puis
 * nouvel essai dans la même passe. `status_changed_at` ne change pas : la pastille du
 * membre ne s'allume pas pour une relance. Rend `token` si le jeton est refusé.
 */
async function retryFailedSends(token: string, fetchImpl?: FetchLike): Promise<"ok" | "token"> {
  let docs: DocumentSnapshot[];
  try {
    const { db } = await firestore();
    const snap = await db
      .collection(COLL_TICKETS)
      .where("status", "==", "send_failed")
      .orderBy("retry_requested_at")
      .limit(PENDING_PER_PASS)
      .get();
    docs = snap.docs;
  } catch (err) {
    logError({ message: "Tickets : relances d'envoi illisibles", feature: "tickets", error: err });
    return "ok";
  }
  for (const doc of docs) {
    let reset: boolean;
    try {
      const { db, FieldValue, Timestamp } = await firestore();
      reset = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (fresh.get("status") !== "send_failed") return false;
        if (!(fresh.get("retry_requested_at") instanceof Timestamp)) return false;
        const now = Timestamp.now();
        tx.update(doc.ref, {
          status: "pending",
          allowed_decisions: allowedDecisions("pending"),
          send_attempts: 0,
          send_retried_at: now,
          retry_requested_at: FieldValue.delete(),
          send_lease_until: FieldValue.delete(),
          updated_at: now,
        });
        return true;
      });
    } catch (err) {
      logError({
        message: "Tickets : relance d'envoi non enregistrée",
        feature: "tickets",
        ticketId: doc.id,
        error: err,
      });
      continue;
    }
    if (!reset) continue;
    logInfo({
      message: "Tickets : relance d'envoi demandée par l'admin",
      feature: "tickets",
      ticketId: doc.id,
    });
    if ((await publishTicket(doc.id, token, fetchImpl)) === "token") return "token";
  }
  return "ok";
}

/**
 * Étape 4 : décisions restées `applying` après l'expiration de leur bail (fonction
 * arrêtée en cours de route), et décisions encore `pending` cinq minutes après leur
 * création (déclencheur arrêté avant la prise, sans rejeu). Chacune est reprise par
 * `applyDecision`, dont la transaction de prise tranche. Rend `token` si le jeton est
 * refusé.
 */
async function resumeStuckDecisions(token: string, fetchImpl?: FetchLike): Promise<"ok" | "token"> {
  let docs: DocumentSnapshot[];
  try {
    const { db, Timestamp } = await firestore();
    const now = Date.now();
    const [applying, pending] = await Promise.all([
      db
        .collectionGroup(COLL_DECISIONS)
        .where("state", "==", "applying")
        .where("lease_until", "<", Timestamp.fromMillis(now))
        .orderBy("lease_until")
        .limit(DECISIONS_PER_PASS)
        .get(),
      db
        .collectionGroup(COLL_DECISIONS)
        .where("state", "==", "pending")
        .where("requested_at", "<", Timestamp.fromMillis(stalePendingCutoffMs(now)))
        .orderBy("requested_at")
        .limit(DECISIONS_PER_PASS)
        .get(),
    ]);
    const millis = (v: unknown) => (v instanceof Timestamp ? v.toMillis() : null);
    docs = [...applying.docs, ...pending.docs].filter((doc) =>
      isResumableByPass({
        state: doc.get("state"),
        leaseUntilMs: millis(doc.get("lease_until")),
        requestedAtMs: millis(doc.get("requested_at")),
        nowMs: now,
      }),
    );
  } catch (err) {
    logError({
      message: "Tickets : décisions à reprendre illisibles",
      feature: "tickets",
      error: err,
    });
    return "ok";
  }
  for (const doc of docs) {
    const ticket = doc.ref.parent.parent;
    if (ticket === null || ticket.parent.id !== COLL_TICKETS) continue;
    logInfo({
      message: `Tickets : décision ${doc.get("state")} reprise par la passe horaire`,
      feature: "tickets",
      ticketId: ticket.id,
      extra: { decisionId: doc.id },
    });
    if ((await applyDecision(ticket.id, doc.id, token, fetchImpl)) === "token") return "token";
  }
  return "ok";
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

    await backfillAllowedDecisions();
    if ((await retryFailedSends(trimmed, fetchImpl)) === "token") return;

    const pending = await db
      .collection(COLL_TICKETS)
      .where("status", "==", "pending")
      .orderBy("created_at")
      .limit(PENDING_PER_PASS)
      .get();
    for (const doc of pending.docs) {
      if ((await publishTicket(doc.id, trimmed, fetchImpl)) === "token") return;
    }

    if ((await resumeStuckDecisions(trimmed, fetchImpl)) === "token") return;

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
