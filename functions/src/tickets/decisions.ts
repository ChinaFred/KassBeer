/**
 * Application d'une décision de l'administrateur (ADR-006, lot T2 ; ADR-008, lot T7).
 * Appelée par les callables `validateTicket`, `refuseTicket` et `closeTicket`
 * (`decisionCalls.ts`), pendant l'appel ; aucun déclencheur, aucune reprise par la tâche
 * horaire.
 *
 * 1. Transaction : ticket, verrou des livraisons (P44) et décision la plus récente du ticket
 *    lus ; précondition (`decisionStart`) ; bail de deux minutes sur le ticket
 *    (`decision_lease_until`) et sur la décision (`lease_until`), état `applying`. La
 *    décision est créée (identifiant tiré par le serveur) ou reprise (même identifiant).
 *    Sinon refus en `HttpsError`, ou réponse « déjà fait ».
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
 * Un échec laisse la décision `failed` avec `steps_done` et `error_reason`, retire les baux
 * et lève une `HttpsError` (`details.partial` si le commentaire est publié). Un jeton refusé
 * pose `token_invalid_since`. Chaque écriture finale vérifie que le bail est encore le sien.
 * Le texte de la décision n'est jamais journalisé (P53).
 */

import type { DocumentReference, Transaction } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { COLL_TICKETS, GITHUB_MAINTAINER_ID, REPLY_MAX_CHARS } from "../config";
import { firestore } from "../firestore";
import { logError, logInfo, logWarn } from "../logging";
import {
  FAILURE_TICKET_NOT_WRITTEN,
  REJECT_ISSUE_CLOSED,
  actionHasComment,
  allowedDecisions,
  commentCarriesDecision,
  decisionCommentBody,
  decisionFailure,
  decisionTextOfComment,
  decisionPlan,
  decisionStart,
  failureReason,
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
import type { TicketStatus } from "./model";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

export const COLL_DECISIONS = "decisions";

/**
 * Bail d'une décision. Plus long que le délai des callables (60 s) : un bail expiré veut
 * dire que la fonction s'est arrêtée.
 */
export const DECISION_LEASE_MS = 2 * 60 * 1000;

/** Réponse des callables de décision. `changed: false` : déjà fait, rien publié. */
export type DecisionResult =
  | { status: TicketStatus; changed: false }
  | {
      status: TicketStatus;
      changed: true;
      decisionId: string;
      /**
       * Vrai si le commentaire publié par un essai précédent est gardé et que le texte reçu
       * en diffère : le nouveau texte n'est pas publié (P53).
       */
      textKept: boolean;
    };

export interface Refs {
  ticket: DocumentReference;
  decision: DocumentReference;
}

/** Erreur rendue au client : `details.reason` (français), `details.code` (stable). */
function refusal(
  code: "failed-precondition" | "not-found" | "unavailable" | "aborted" | "internal",
  reason: string,
  machine: string,
  partial = false,
): HttpsError {
  return new HttpsError(code, reason, { reason, code: machine, ...(partial ? { partial } : {}) });
}

export type Claim =
  | { kind: "done"; status: TicketStatus }
  | {
      kind: "claimed";
      refs: Refs;
      action: DecisionAction;
      /** Texte publié (Refuser, Clore) : le texte stocké si le commentaire est publié. */
      text: string | null;
      /** Texte reçu par cet appel (Refuser, Clore), `null` pour Valider. */
      receivedText: string | null;
      issueNumber: number;
      leaseUntilMs: number;
      /** `comment_id` écrit par un essai précédent, ou `null`. */
      knownCommentId: number | null;
      /** Vrai si la décision reprend un essai dont le commentaire est publié. */
      storedTextKept: boolean;
    };

/**
 * Étape 1. `text` : texte reçu, déjà lu (`readDecisionText`), `null` pour Valider. Lève une
 * `HttpsError` pour un refus.
 */
async function claim(
  ticketId: string,
  action: DecisionAction,
  text: string | null,
  uid: string,
  now: Date,
): Promise<Claim> {
  const kit = await firestore();
  const { db, FieldValue, Timestamp } = kit;
  const ticketRef = db.collection(COLL_TICKETS).doc(ticketId);
  const decisions = ticketRef.collection(COLL_DECISIONS);
  const millis = (v: unknown) => (v instanceof Timestamp ? v.toMillis() : null);
  return db.runTransaction(async (tx): Promise<Claim> => {
    const [ticketSnap, latestSnap, deliveryRunning] = await Promise.all([
      tx.get(ticketRef),
      tx.get(decisions.orderBy("requested_at", "desc").limit(1)),
      // P44 : Refuser et Clore refusés pendant une livraison de ce ticket.
      deliveryRunningFor(tx, kit, ticketId, now.getTime()),
    ]);
    const t = ticketSnap.exists ? (ticketSnap.data() ?? {}) : null;
    const latestDoc = latestSnap.docs[0];
    const latest =
      latestDoc === undefined
        ? null
        : {
            id: latestDoc.id,
            action: latestDoc.get("action"),
            state: latestDoc.get("state"),
            leaseUntilMs: millis(latestDoc.get("lease_until")),
            stepsDone: latestDoc.get("steps_done"),
            text: latestDoc.get("text"),
            commentId: latestDoc.get("comment_id"),
          };
    const start = decisionStart({
      action,
      ticket:
        t === null
          ? null
          : {
              status: t.status,
              validatedByAppAt: t.validated_by_app_at,
              leaseUntilMs: millis(t.decision_lease_until),
              issueNumber: t.github_issue_number,
              deliveryRunning,
            },
      latest,
      nowMs: now.getTime(),
    });
    if (start.kind === "refuse") throw refusal(start.code, start.reason, start.machine);
    if (start.kind === "done") return { kind: "done", status: start.status };

    const nowTs = Timestamp.fromDate(now);
    const leaseUntilMs = now.getTime() + DECISION_LEASE_MS;
    const lease = Timestamp.fromMillis(leaseUntilMs);
    const resume = start.resume;
    const decisionRef = resume === null ? decisions.doc() : decisions.doc(resume.id);
    tx.update(ticketRef, { decision_lease_until: lease, updated_at: nowTs });
    let published = text;
    if (resume === null) {
      tx.set(decisionRef, {
        action,
        ...(text !== null ? { text } : {}),
        state: "applying",
        requested_by_uid: uid,
        requested_at: nowTs,
        lease_until: lease,
        updated_at: nowTs,
      });
    } else {
      if (resume.keepText) published = String(latest?.text);
      tx.update(decisionRef, {
        state: "applying",
        lease_until: lease,
        error_reason: FieldValue.delete(),
        ...(!resume.keepText && text !== null ? { text } : {}),
        updated_at: nowTs,
      });
    }
    return {
      kind: "claimed",
      refs: { ticket: ticketRef, decision: decisionRef },
      action,
      text: published,
      receivedText: text,
      issueNumber: start.issueNumber,
      leaseUntilMs,
      knownCommentId: resume?.knownCommentId ?? null,
      storedTextKept: resume?.keepText ?? false,
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
  publishedText: string | null = null,
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
        ...(publishedText !== null ? { text: publishedText } : {}),
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
    // Les baux expirent seuls en deux minutes ; l'admin reprend la décision par un nouvel appel.
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
 * du compte 16348852), avec son texte, ou `null`. Avec `knownCommentId` (`comment_id` de la
 * décision), ce seul commentaire est relu : supprimé (404 ou 410), il est à republier sans
 * relire les pages ; modifié au point de perdre sa ligne, les pages sont relues (cinq de 100
 * au plus).
 */
export async function findPublishedComment(
  client: GithubClient,
  issueNumber: number,
  commentCount: number,
  decisionId: string,
  knownCommentId: number | null,
): Promise<{ id: number | null; body: string } | null> {
  if (knownCommentId !== null) {
    const known = await client.getComment(knownCommentId);
    if (known === null) return null;
    if (commentCarriesDecision(known, decisionId, GITHUB_MAINTAINER_ID)) {
      return { id: known.id ?? knownCommentId, body: known.body ?? "" };
    }
  }
  if (commentCount < 1) return null;
  for await (const page of client.lastCommentsFirst(issueNumber, commentCount)) {
    for (const comment of page) {
      if (commentCarriesDecision(comment, decisionId, GITHUB_MAINTAINER_ID)) {
        return { id: comment.id, body: comment.body ?? "" };
      }
    }
  }
  return null;
}

type Claimed = Extract<Claim, { kind: "claimed" }>;

export type GithubRun =
  | {
      kind: "done";
      stepsDone: DecisionStep[];
      commentId: number | null;
      /** Texte du commentaire tel qu'il est sur l'Issue (publié ou retrouvé). */
      commentBody: string | null;
      /** Nombre de commentaires de l'Issue après la décision, pour le relevé des analyses. */
      commentCount: number;
      /** Texte du commentaire d'un essai précédent retrouvé sur l'Issue, ou `null`. */
      publishedText: string | null;
      /** Vrai si ce commentaire retrouvé diffère du texte reçu : il est gardé. */
      textKept: boolean;
    }
  | { kind: "closed_elsewhere"; stepsDone: DecisionStep[] };

class StepFailure extends Error {
  constructor(
    readonly cause: unknown,
    readonly stepsDone: DecisionStep[],
    readonly commentId: number | null,
    readonly publishedText: string | null = null,
  ) {
    super("étape GitHub en échec");
  }
}

/** Étapes 2 à 5 sur GitHub. Exportée pour les tests ; `refs.ticket` ne sert qu'à une Issue fermée. */
export async function runOnGithub(client: GithubClient, claimed: Claimed): Promise<GithubRun> {
  const decisionId = claimed.refs.decision.id;
  const stepsDone: DecisionStep[] = [];
  let commentId: number | null = null;
  let publishedText: string | null = null;
  let textKept = false;
  try {
    const issue = await client.getIssue(claimed.issueNumber);
    let body =
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
      // Le texte publié par l'essai précédent fait foi pour `reply_text` et pour le `text`
      // de la décision ; un texte reçu différent n'est pas publié.
      publishedText = decisionTextOfComment(found.body, GITHUB_MAINTAINER_ID);
      const received =
        claimed.receivedText === null
          ? null
          : decisionTextOfComment(
              decisionCommentBody(claimed.receivedText, decisionId),
              GITHUB_MAINTAINER_ID,
            );
      textKept = received !== null && received !== publishedText;
      body = found.body;
    } else if (claimed.storedTextKept) {
      // Commentaire supprimé depuis : le texte stocké est republié, pas le texte reçu.
      textKept = claimed.receivedText !== null && claimed.receivedText !== claimed.text;
    }
    const plan = decisionPlan(claimed.action, issue, found !== null);
    if (plan.kind === "reject_closed") {
      const ticketSnap = await claimed.refs.ticket.get();
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
    return {
      kind: "done",
      stepsDone,
      commentId,
      commentBody: body,
      commentCount,
      publishedText,
      textKept,
    };
  } catch (err) {
    throw new StepFailure(err, stepsDone, commentId, publishedText);
  }
}

/**
 * Étape 7, au mieux : `validated_at` après Valider, puis relevé des analyses (P32). Ne
 * lève pas.
 */
async function afterDecision(
  client: GithubClient,
  ticketId: string,
  claimed: Claimed,
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
 * Applique `action` sur le ticket `ticketId` pendant l'appel de l'administrateur `uid`.
 * `text` : texte lu (`readDecisionText`) pour Refuser et Clore, `null` pour Valider. Rend le
 * statut ; lève une `HttpsError` pour un refus ou un échec, déjà journalisé.
 */
export async function decideTicket(
  ticketId: string,
  action: DecisionAction,
  text: string | null,
  uid: string,
  token: string,
  fetchImpl?: FetchLike,
): Promise<DecisionResult> {
  const claimed = await claim(ticketId, action, text, uid, new Date());
  if (claimed.kind === "done") return { status: claimed.status, changed: false };
  const refs = claimed.refs;
  const decisionId = refs.decision.id;
  const log = { feature: "tickets", ticketId, extra: { decisionId, action } };

  const trimmed = token.trim();
  if (trimmed.length === 0) {
    await markTokenInvalid(null);
    await recordFailure(
      refs,
      ticketId,
      claimed.leaseUntilMs,
      failureReason(action, [], "token"),
      [],
      null,
    );
    const f = decisionFailure(action, [], "token");
    throw refusal(f.code, f.reason, f.machine);
  }

  const client = githubClient(trimmed, fetchImpl);
  let run: GithubRun;
  try {
    run = await runOnGithub(client, claimed);
  } catch (err) {
    const failure = err instanceof StepFailure ? err : new StepFailure(err, [], null);
    const cause = failure.cause;
    const kind: FailureKind = cause instanceof GithubError ? cause.kind : "other";
    logError({
      ...log,
      message: "Tickets : décision en échec sur GitHub",
      error: cause,
      extra: { ...log.extra, kind, steps: failure.stepsDone.join(",") },
    });
    if (kind === "token") await markTokenInvalid(cause as GithubError);
    const f = decisionFailure(action, failure.stepsDone, kind);
    await recordFailure(
      refs,
      ticketId,
      claimed.leaseUntilMs,
      f.reason,
      failure.stepsDone,
      failure.commentId,
      failure.publishedText,
    );
    throw refusal(f.code, f.reason, f.machine, f.partial);
  }

  const status = statusAfterDecision(action);
  let written: boolean;
  try {
    const { FieldValue, Timestamp } = await firestore();
    const now = Timestamp.now();
    written = await writeIfLeaseHeld(refs, claimed.leaseUntilMs, (tx, ticket) => {
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
        ...(run.publishedText !== null ? { text: run.publishedText } : {}),
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
          // Valider depuis l'application : seul chemin qui pose `validated_by_app_at` et
          // ouvre « Lancer le développement » (ADR-008, 2026-11-13). Refuser et Clore
          // l'effacent.
          allowed_decisions: allowedDecisions(status, action === "validate"),
          validated_by_app_at: action === "validate" ? now : null,
          updated_at: now,
          ...(changed ? { status_changed_at: now } : {}),
          ...(reply !== null && changed ? { reply_text: reply, reply_at: now } : {}),
        },
        FieldValue.delete(),
      );
    });
  } catch (err) {
    logError({ ...log, message: "Tickets : décision faite sur GitHub, non écrite", error: err });
    await recordFailure(
      refs,
      ticketId,
      claimed.leaseUntilMs,
      FAILURE_TICKET_NOT_WRITTEN,
      run.stepsDone,
      run.kind === "done" ? run.commentId : null,
      run.kind === "done" ? run.publishedText : null,
    );
    throw refusal(
      "internal",
      FAILURE_TICKET_NOT_WRITTEN,
      "ticket_not_written",
      run.stepsDone.includes("comment"),
    );
  }
  if (!written) {
    // Le bail a expiré et un autre appel l'a repris : il écrira l'issue.
    logWarn({ ...log, message: "Tickets : décision faite, bail repris par un autre essai" });
    throw refusal(
      "internal",
      FAILURE_TICKET_NOT_WRITTEN,
      "ticket_not_written",
      run.stepsDone.includes("comment"),
    );
  }
  await recordTokenAccepted(client);
  if (run.kind === "closed_elsewhere") {
    logInfo({ ...log, message: "Tickets : Issue déjà fermée sur GitHub, décision refusée" });
    throw refusal("failed-precondition", REJECT_ISSUE_CLOSED, "issue_closed");
  }
  await afterDecision(client, ticketId, claimed, run);
  logInfo({
    ...log,
    message: `Tickets : décision ${action} appliquée sur l'Issue #${claimed.issueNumber}`,
    extra: {
      ...log.extra,
      stored_text_kept: claimed.storedTextKept,
      published_text_kept: run.textKept,
    },
  });
  return { status, changed: true, decisionId, textKept: run.textKept };
}
