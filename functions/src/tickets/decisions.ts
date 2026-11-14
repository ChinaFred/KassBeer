/**
 * Application d'une décision de l'administrateur (ADR-006, lot T2). Appelée par les
 * déclencheurs de `tickets/{ticketId}/decisions/{decisionId}` (création, reprise demandée)
 * et par la passe horaire (décision `applying` au bail expiré). Aucune callable (P25).
 *
 * 1. Transaction : la décision est prise (`decisionClaimVerdict`, verrou des livraisons lu
 *    pour Refuser et Clore, P44) ; bail de deux minutes
 *    sur le ticket (`decision_lease_until`) et sur la décision (`lease_until`), état
 *    `applying`. Sinon `rejected` avec son motif, ou rien (rejeu).
 * 2. Relecture de l'Issue ; pour `refuse` et `close`, recherche du commentaire qui porte
 *    la ligne `Décision <id>` (essai précédent). Issue déjà fermée par un autre geste :
 *    l'état lu est appliqué au ticket, la décision passe `rejected`.
 * 3. à 5. Commentaire, étiquette, fermeture, dans cet ordre ; ce qui est fait est sauté.
 * 6. Transaction : statut, `reply_text`, `reply_at`, `allowed_decisions`,
 *    `status_changed_at` du ticket, baux retirés, décision `applied`.
 * 7. Au mieux (ADR-008, P32) : `validated_at` de `admin/analysis` après Valider, puis
 *    relevé des analyses et précisions de l'Issue. Un échec est journalisé, la décision
 *    reste faite.
 *
 * Un échec laisse la décision `failed` avec `steps_done` et `error_reason`, et retire les
 * baux. Un jeton refusé pose `token_invalid_since`. Chaque écriture finale vérifie que le
 * bail est encore le sien : un essai repris par un autre ne l'écrase pas.
 */

import type { DocumentReference, Transaction } from "firebase-admin/firestore";

import { COLL_TICKETS, GITHUB_MAINTAINER_ID, REPLY_MAX_CHARS } from "../config";
import { firestore } from "../firestore";
import { logError, logInfo, logWarn } from "../logging";
import {
  FAILURE_TICKET_NOT_WRITTEN,
  REJECT_ISSUE_CLOSED,
  actionHasComment,
  allowedDecisions,
  commentCarriesDecision,
  decisionClaimVerdict,
  decisionCommentBody,
  decisionPlan,
  failureReason,
  isPlausibleDecisionId,
  replyTextOfComment,
  statusAfterDecision,
  type DecisionAction,
  type DecisionStep,
  type FailureKind,
} from "./decisionModel";
import { recordValidatedAt, refreshAnalyses } from "./analyses";
import { deliveryRunningFor } from "./delivery";
import { GithubError, githubClient, type FetchLike, type GithubClient } from "./github";
import { applyIssue } from "./issueState";
import { isPlausibleTicketId } from "./publish";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

export const COLL_DECISIONS = "decisions";

/**
 * Bail d'une décision. Plus long que le délai d'exécution des fonctions (60 s) : un bail
 * expiré veut dire que la fonction s'est arrêtée.
 */
export const DECISION_LEASE_MS = 2 * 60 * 1000;

export type DecisionOutcome = "applied" | "rejected" | "skipped" | "failed" | "token" | "invalid";

export interface Refs {
  ticket: DocumentReference;
  decision: DocumentReference;
}

async function refsOf(ticketId: string, decisionId: string): Promise<Refs> {
  const { db } = await firestore();
  const ticket = db.collection(COLL_TICKETS).doc(ticketId);
  return { ticket, decision: ticket.collection(COLL_DECISIONS).doc(decisionId) };
}

export type Claim =
  | { kind: "skip" }
  | { kind: "rejected" }
  | {
      kind: "claimed";
      action: DecisionAction;
      text: string | null;
      issueNumber: number;
      leaseUntilMs: number;
      /** `comment_id` écrit par un essai précédent, ou `null`. */
      knownCommentId: number | null;
    };

async function claim(refs: Refs, now: Date): Promise<Claim> {
  const kit = await firestore();
  const { db, FieldValue, Timestamp } = kit;
  const millis = (v: unknown) => (v instanceof Timestamp ? v.toMillis() : null);
  return db.runTransaction(async (tx): Promise<Claim> => {
    const [decisionSnap, ticketSnap, deliveryRunning] = await Promise.all([
      tx.get(refs.decision),
      tx.get(refs.ticket),
      // P44 : Refuser et Clore rejetés pendant une livraison de ce ticket.
      deliveryRunningFor(tx, kit, refs.ticket.id, now.getTime()),
    ]);
    if (!decisionSnap.exists) return { kind: "skip" };
    const d = decisionSnap.data() ?? {};
    const t = ticketSnap.exists ? (ticketSnap.data() ?? {}) : null;
    const verdict = decisionClaimVerdict({
      decision: {
        state: d.state,
        action: d.action,
        text: d.text,
        leaseUntilMs: millis(d.lease_until),
        retryRequested: d.retry_requested_at != null,
      },
      ticket:
        t === null
          ? null
          : {
              status: t.status,
              allowedDecisions: t.allowed_decisions,
              validatedByAppAt: t.validated_by_app_at,
              leaseUntilMs: millis(t.decision_lease_until),
              issueNumber: t.github_issue_number,
              deliveryRunning,
            },
      nowMs: now.getTime(),
    });
    const nowTs = Timestamp.fromDate(now);
    if (verdict.kind === "skip") return { kind: "skip" };
    if (verdict.kind === "reject") {
      tx.update(refs.decision, {
        state: "rejected",
        error_reason: verdict.reason,
        retry_requested_at: FieldValue.delete(),
        lease_until: FieldValue.delete(),
        updated_at: nowTs,
      });
      return { kind: "rejected" };
    }
    const leaseUntilMs = now.getTime() + DECISION_LEASE_MS;
    const lease = Timestamp.fromMillis(leaseUntilMs);
    tx.update(refs.ticket, { decision_lease_until: lease, updated_at: nowTs });
    tx.update(refs.decision, {
      state: "applying",
      lease_until: lease,
      // Retirée à la prise : l'échec suivant n'est pas repris sans nouvelle demande.
      retry_requested_at: FieldValue.delete(),
      error_reason: FieldValue.delete(),
      updated_at: nowTs,
    });
    return {
      kind: "claimed",
      action: verdict.action,
      text: typeof d.text === "string" ? d.text : null,
      issueNumber: verdict.issueNumber,
      leaseUntilMs,
      knownCommentId:
        typeof d.comment_id === "number" && Number.isSafeInteger(d.comment_id)
          ? d.comment_id
          : null,
    };
  });
}

/**
 * Écrit l'issue d'un essai seulement si le bail posé à la prise est encore le sien :
 * décision `applying` et `lease_until` inchangé. Rend `false` sinon (rien n'est écrit).
 */
async function writeIfLeaseHeld(
  refs: Refs,
  leaseUntilMs: number,
  write: (tx: Transaction, ticket: Record<string, unknown> | null) => void,
): Promise<boolean> {
  const { db, Timestamp } = await firestore();
  return db.runTransaction(async (tx) => {
    const [decisionSnap, ticketSnap] = await Promise.all([
      tx.get(refs.decision),
      tx.get(refs.ticket),
    ]);
    const lease = decisionSnap.get("lease_until");
    const held =
      decisionSnap.get("state") === "applying" &&
      lease instanceof Timestamp &&
      lease.toMillis() === leaseUntilMs;
    if (!held) return false;
    const ticket = ticketSnap.exists ? (ticketSnap.data() ?? {}) : null;
    write(tx, ticket);
    return true;
  });
}

/** Retire le bail du ticket s'il est celui de cette décision. */
function releaseTicketLease(
  tx: Transaction,
  refs: Refs,
  ticket: Record<string, unknown> | null,
  leaseUntilMs: number,
  extra: Record<string, unknown>,
  deleteField: unknown,
): void {
  if (ticket === null) return;
  const lease = ticket.decision_lease_until as { toMillis?: () => number } | undefined;
  const ours = typeof lease?.toMillis === "function" && lease.toMillis() === leaseUntilMs;
  if (!ours && Object.keys(extra).length === 0) return;
  tx.update(refs.ticket, { ...(ours ? { decision_lease_until: deleteField } : {}), ...extra });
}

async function recordFailure(
  refs: Refs,
  ticketId: string,
  leaseUntilMs: number,
  reason: string,
  stepsDone: readonly DecisionStep[],
  commentId: number | null,
): Promise<void> {
  try {
    const { FieldValue, Timestamp } = await firestore();
    const now = Timestamp.now();
    const written = await writeIfLeaseHeld(refs, leaseUntilMs, (tx, ticket) => {
      tx.update(refs.decision, {
        state: "failed",
        error_reason: reason,
        steps_done: [...stepsDone],
        ...(commentId !== null ? { comment_id: commentId } : {}),
        lease_until: FieldValue.delete(),
        updated_at: now,
      });
      releaseTicketLease(tx, refs, ticket, leaseUntilMs, {}, FieldValue.delete());
    });
    if (!written) {
      logWarn({
        message: "Tickets : échec de décision non écrit, bail repris par un autre essai",
        feature: "tickets",
        ticketId,
        extra: { decisionId: refs.decision.id },
      });
    }
  } catch (err) {
    // Les baux expirent seuls en deux minutes ; la passe horaire reprend la décision.
    logError({
      message: "Tickets : échec de décision non enregistré",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { decisionId: refs.decision.id },
    });
  }
}

/**
 * Commentaire déjà publié par un essai précédent (ligne `Décision <id>` d'un commentaire
 * du compte 16348852), ou `null`. Avec `knownCommentId` (`comment_id` de la décision), ce
 * seul commentaire est relu : supprimé (404 ou 410), il est à republier sans relire les
 * pages ; modifié au point de perdre sa ligne, les pages sont relues (cinq de 100 au plus).
 */
export async function findPublishedComment(
  client: GithubClient,
  issueNumber: number,
  commentCount: number,
  decisionId: string,
  knownCommentId: number | null,
): Promise<{ id: number | null } | null> {
  if (knownCommentId !== null) {
    const known = await client.getComment(knownCommentId);
    if (known === null) return null;
    if (commentCarriesDecision(known, decisionId, GITHUB_MAINTAINER_ID)) {
      return { id: known.id ?? knownCommentId };
    }
  }
  if (commentCount < 1) return null;
  for await (const page of client.lastCommentsFirst(issueNumber, commentCount)) {
    for (const comment of page) {
      if (commentCarriesDecision(comment, decisionId, GITHUB_MAINTAINER_ID)) {
        return { id: comment.id };
      }
    }
  }
  return null;
}

export type GithubRun =
  | {
      kind: "done";
      stepsDone: DecisionStep[];
      commentId: number | null;
      commentBody: string | null;
      /** Nombre de commentaires de l'Issue après la décision, pour le relevé des analyses. */
      commentCount: number;
    }
  | { kind: "closed_elsewhere"; stepsDone: DecisionStep[] };

class StepFailure extends Error {
  constructor(
    readonly cause: unknown,
    readonly stepsDone: DecisionStep[],
    readonly commentId: number | null,
  ) {
    super("étape GitHub en échec");
  }
}

/** Étapes 2 à 5 sur GitHub. Exportée pour les tests ; `refs` ne sert qu'à une Issue fermée. */
export async function runOnGithub(
  client: GithubClient,
  refs: Refs,
  decisionId: string,
  claimed: Extract<Claim, { kind: "claimed" }>,
): Promise<GithubRun> {
  const stepsDone: DecisionStep[] = [];
  let commentId: number | null = null;
  try {
    const issue = await client.getIssue(claimed.issueNumber);
    const body =
      actionHasComment(claimed.action) && claimed.text !== null
        ? decisionCommentBody(claimed.text, decisionId)
        : null;
    const found = actionHasComment(claimed.action)
      ? await findPublishedComment(
          client,
          issue.number,
          issue.comments,
          decisionId,
          claimed.knownCommentId,
        )
      : null;
    if (found !== null) {
      stepsDone.push("comment");
      commentId = found.id;
    }
    const plan = decisionPlan(claimed.action, issue, found !== null);
    if (plan.kind === "reject_closed") {
      const ticketSnap = await refs.ticket.get();
      if (ticketSnap.exists) await applyIssue(client, ticketSnap, issue);
      return { kind: "closed_elsewhere", stepsDone };
    }
    if (plan.comment) {
      if (body === null) throw new Error("commentaire sans texte");
      commentId = (await client.createComment(issue.number, body)).id;
      stepsDone.push("comment");
    }
    if (plan.label !== null) {
      await client.addLabels(issue.number, [plan.label]);
      stepsDone.push("label");
    }
    if (plan.close !== null) {
      await client.closeIssue(issue.number, plan.close);
      stepsDone.push("close");
    }
    const commentCount = issue.comments + (plan.comment ? 1 : 0);
    return { kind: "done", stepsDone, commentId, commentBody: body, commentCount };
  } catch (err) {
    throw new StepFailure(err, stepsDone, commentId);
  }
}

/**
 * Étape 7, au mieux : `validated_at` après Valider, puis relevé des analyses (P32). Ne
 * lève pas.
 */
async function afterDecision(
  client: GithubClient,
  ticketId: string,
  claimed: Extract<Claim, { kind: "claimed" }>,
  run: Extract<GithubRun, { kind: "done" }>,
): Promise<void> {
  try {
    if (claimed.action === "validate") await recordValidatedAt(ticketId, Date.now());
    await refreshAnalyses(client, ticketId, claimed.issueNumber, run.commentCount);
  } catch (err) {
    logError({
      message: "Tickets : analyses non relevées après la décision",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { action: claimed.action },
    });
  }
}

/**
 * Applique la décision `decisionId` du ticket `ticketId`. Ne lève pas : chaque erreur est
 * journalisée et le résultat dit ce qui s'est passé.
 */
export async function applyDecision(
  ticketId: string,
  decisionId: string,
  token: string,
  fetchImpl?: FetchLike,
): Promise<DecisionOutcome> {
  if (!isPlausibleTicketId(ticketId) || !isPlausibleDecisionId(decisionId)) {
    logError({
      message: "Tickets : identifiant de décision refusé",
      feature: "tickets",
      extra: { ticketIdLength: ticketId.length, decisionIdLength: decisionId.length },
    });
    return "invalid";
  }
  const log = { feature: "tickets", ticketId, extra: { decisionId } };

  let refs: Refs;
  let claimed: Claim;
  try {
    refs = await refsOf(ticketId, decisionId);
    claimed = await claim(refs, new Date());
  } catch (err) {
    logError({ ...log, message: "Tickets : décision impossible à prendre", error: err });
    return "failed";
  }
  if (claimed.kind === "skip") return "skipped";
  if (claimed.kind === "rejected") {
    logInfo({ ...log, message: "Tickets : décision refusée par le serveur" });
    return "rejected";
  }

  const trimmed = token.trim();
  if (trimmed.length === 0) {
    await markTokenInvalid(null);
    await recordFailure(
      refs,
      ticketId,
      claimed.leaseUntilMs,
      failureReason(claimed.action, [], "token"),
      [],
      null,
    );
    return "token";
  }

  const client = githubClient(trimmed, fetchImpl);
  let run: GithubRun;
  try {
    run = await runOnGithub(client, refs, decisionId, claimed);
  } catch (err) {
    const failure = err instanceof StepFailure ? err : new StepFailure(err, [], null);
    const cause = failure.cause;
    const kind: FailureKind = cause instanceof GithubError ? cause.kind : "other";
    logError({
      ...log,
      message: "Tickets : décision en échec sur GitHub",
      error: cause,
      extra: { decisionId, kind, steps: failure.stepsDone.join(",") },
    });
    if (kind === "token") await markTokenInvalid(cause as GithubError);
    await recordFailure(
      refs,
      ticketId,
      claimed.leaseUntilMs,
      failureReason(claimed.action, failure.stepsDone, kind),
      failure.stepsDone,
      failure.commentId,
    );
    return kind === "token" ? "token" : "failed";
  }

  try {
    const { FieldValue, Timestamp } = await firestore();
    const now = Timestamp.now();
    const written = await writeIfLeaseHeld(refs, claimed.leaseUntilMs, (tx, ticket) => {
      if (run.kind === "closed_elsewhere") {
        tx.update(refs.decision, {
          state: "rejected",
          error_reason: REJECT_ISSUE_CLOSED,
          steps_done: run.stepsDone,
          lease_until: FieldValue.delete(),
          updated_at: now,
        });
        releaseTicketLease(tx, refs, ticket, claimed.leaseUntilMs, {}, FieldValue.delete());
        return;
      }
      const status = statusAfterDecision(claimed.action);
      const reply =
        run.commentBody === null
          ? null
          : replyTextOfComment(run.commentBody, GITHUB_MAINTAINER_ID, REPLY_MAX_CHARS);
      // Un essai repris trouve parfois le ticket déjà à jour (passe horaire passée
      // entre-temps) : `status_changed_at` ne bouge alors pas, la pastille du membre ne se
      // rallume pas.
      const changed =
        ticket !== null &&
        (ticket.status !== status || (reply !== null && ticket.reply_text !== reply));
      tx.update(refs.decision, {
        state: "applied",
        applied_at: now,
        steps_done: run.stepsDone,
        ...(run.commentId !== null ? { comment_id: run.commentId } : {}),
        lease_until: FieldValue.delete(),
        error_reason: FieldValue.delete(),
        updated_at: now,
      });
      releaseTicketLease(
        tx,
        refs,
        ticket,
        claimed.leaseUntilMs,
        {
          status,
          // Valider appliqué depuis l'application : seul chemin qui pose
          // `validated_by_app_at` et ouvre « Lancer le développement » (ADR-008,
          // 2026-11-13). Refuser et Clore l'effacent.
          allowed_decisions: allowedDecisions(status, claimed.action === "validate"),
          validated_by_app_at: claimed.action === "validate" ? now : null,
          updated_at: now,
          ...(changed ? { status_changed_at: now } : {}),
          ...(reply !== null && changed ? { reply_text: reply, reply_at: now } : {}),
        },
        FieldValue.delete(),
      );
    });
    if (!written) {
      logWarn({ ...log, message: "Tickets : décision faite, bail repris par un autre essai" });
      return "skipped";
    }
  } catch (err) {
    logError({ ...log, message: "Tickets : décision faite sur GitHub, non écrite", error: err });
    await recordFailure(
      refs,
      ticketId,
      claimed.leaseUntilMs,
      FAILURE_TICKET_NOT_WRITTEN,
      run.stepsDone,
      run.kind === "done" ? run.commentId : null,
    );
    return "failed";
  }
  await recordTokenAccepted(client);
  if (run.kind === "done") await afterDecision(client, ticketId, claimed, run);
  if (run.kind === "closed_elsewhere") {
    logInfo({ ...log, message: "Tickets : Issue déjà fermée sur GitHub, décision refusée" });
    return "rejected";
  }
  logInfo({
    ...log,
    message: `Tickets : décision ${claimed.action} appliquée sur l'Issue #${claimed.issueNumber}`,
  });
  return "applied";
}
