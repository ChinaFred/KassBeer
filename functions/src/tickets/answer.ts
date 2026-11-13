/**
 * « Répondre » (`answerTicketAnalysis`, ADR-008, T3, P34) : l'administrateur publie ses
 * précisions à la dernière analyse sur l'Issue, et le ticket repasse à « Reçu ». Copie de
 * `answerTicketDecision` de Kass'Dalle (`functions/src/tickets/decisions.ts`), adaptée au
 * bail des décisions de Kass'Beer (`decision_lease_until`, partagé avec les décisions T2).
 *
 * 1. `requireAdmin` (P30), puis les arguments : `ticketId`, `answer` (taille brute, puis
 *    5 à 4 000 caractères après nettoyage, texte publié par `publicText`, P24).
 * 2. Transaction : ticket existant, `answerPrecondition`, aucun bail actif ; bail de deux
 *    minutes posé.
 * 3. Issue et commentaires relus. Issue fermée : l'état lu est appliqué, refus. Aucune
 *    analyse sur un ticket au-delà de « Reçu » : refus.
 * 4. Commentaire `## Précisions de l'administrateur`, sauf si une précision du compte
 *    16348852 porte déjà ce texte après la dernière analyse (second appel, nouvel essai
 *    après un délai dépassé, création réussie dont la réponse s'est perdue, P26) ;
 *    identifiant ajouté à `answer_comment_ids`. Une création en échec sans statut 4xx
 *    (réseau, 5xx) relit les commentaires avant de conclure que rien n'a été publié.
 * 5. Ticket au-delà de « Reçu » : étiquette `statut:à-analyser` posée, puis
 *    `statut:analysé` et `validé` retirées.
 * 6. Transaction : ticket `analyzed` ou `validated` ramené à `received`, `answer_reset_at`
 *    posé, `allowed_decisions` réécrit, bail retiré.
 * 7. Au mieux : lancements en cours du ticket clos (`retry_after` ramené à l'heure de la
 *    réponse, T4), puis relevé des analyses.
 *
 * Le texte de la réponse n'est jamais journalisé (P34).
 */

import { HttpsError } from "firebase-functions/v2/https";

import { requireAdmin, requireBoundedText, type AuthLike, type MemberLookup } from "../auth";
import { COLL_TICKETS, GITHUB_MAINTAINER_ID } from "../config";
import { firestore } from "../firestore";
import { logError, logInfo, type LogEntry } from "../logging";
import { analysisRef, recordAnswerCommentId, refreshAnalyses } from "./analyses";
import {
  ANSWER_RAW_MAX_CHARS,
  analysisAnswerState,
  answerCommentBody,
  answerPrecondition,
  readAnswerCommentIds,
  readAnswerText,
  type SameAnswer,
} from "./analysisModel";
import { allowedDecisions } from "./decisionModel";
import { DECISION_LEASE_MS } from "./decisions";
import {
  GithubError,
  githubClient,
  type FetchLike,
  type GithubClient,
  type GithubErrorKind,
} from "./github";
import { applyIssue } from "./issueState";
import { closeRunningLaunches } from "./launch";
import {
  LABEL_ANALYZED,
  LABEL_TO_ANALYZE,
  LABEL_VALIDATED,
  type CommentView,
  type IssueView,
} from "./model";
import { isPlausibleTicketId } from "./publish";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

// ── Arguments ───────────────────────────────────────────────────────────────

export const TICKET_ID_INVALID = "Identifiant de ticket invalide.";

/** `ticketId` d'une requête. Lève `invalid-argument` (`details.field = "ticketId"`). Pure. */
export function readTicketIdArg(data: unknown): string {
  const raw = (data as Record<string, unknown> | null | undefined)?.ticketId;
  const value = requireBoundedText(raw, {
    field: "ticketId",
    max: 128,
    required: true,
    label: "Identifiant du ticket",
  });
  if (!isPlausibleTicketId(value)) {
    throw new HttpsError("invalid-argument", TICKET_ID_INVALID, {
      field: "ticketId",
      reason: TICKET_ID_INVALID,
    });
  }
  return value;
}

/**
 * `answer` d'une requête, rendu en texte publié. Lève `invalid-argument`
 * (`details.field = "answer"`, `details.reason` en français). Pure.
 */
export function readAnswerArg(data: unknown): string {
  const raw = (data as Record<string, unknown> | null | undefined)?.answer;
  const value = requireBoundedText(raw, {
    field: "answer",
    max: ANSWER_RAW_MAX_CHARS,
    required: true,
    label: "Réponse",
  });
  const read = readAnswerText(value);
  if (!read.ok) {
    throw new HttpsError("invalid-argument", read.reason, { field: "answer", reason: read.reason });
  }
  return read.text;
}

// ── Erreurs rendues ─────────────────────────────────────────────────────────

/**
 * Erreur rendue au client : `details.reason` (français), `details.code` (stable) et, quand la
 * précision est déjà sur l'Issue, `details.partial: true` (le texte ne doit plus changer).
 */
function refusal(
  code: "failed-precondition" | "not-found" | "unavailable" | "aborted" | "internal",
  reason: string,
  machine: string,
  partial = false,
): HttpsError {
  return new HttpsError(code, reason, { reason, code: machine, ...(partial ? { partial } : {}) });
}

export const ANSWER_TICKET_MISSING = "Ce ticket n'existe plus.";
export const ANSWER_LEASE_TAKEN = "Une décision est déjà en cours sur ce ticket.";
export const ANSWER_ISSUE_CLOSED = "Ce ticket a déjà été clos sur GitHub.";
export const ANSWER_NO_ANALYSIS = "Aucune analyse à laquelle répondre.";
export const ANSWER_PARTIAL = "Réponse publiée, mais le statut n'a pas changé. Réessayez.";
export const ANSWER_NOT_WRITTEN =
  "Réponse publiée sur GitHub, mais le ticket n'a pas été mis à jour. Réessayez.";
export const ANSWER_INTERNAL = "La réponse n'a pas pu être publiée. Réessayez.";

/** Code et motif d'un échec GitHub avant la publication : rien n'a été publié. Pure. */
export function answerGithubFailure(kind: GithubErrorKind | "other"): {
  code: "failed-precondition" | "not-found" | "unavailable";
  reason: string;
  machine: string;
} {
  switch (kind) {
    case "token":
      return {
        code: "failed-precondition",
        reason: "GitHub refuse le jeton. Rien n'a été publié.",
        machine: "github_token",
      };
    case "not_found":
      return {
        code: "not-found",
        reason: "L'Issue n'existe plus sur GitHub.",
        machine: "issue_not_found",
      };
    case "rate_limit":
      return {
        code: "unavailable",
        reason: "GitHub limite les appels. Réessayez dans quelques minutes. Rien n'a été publié.",
        machine: "github_rate_limit",
      };
    default:
      return {
        code: "unavailable",
        reason: "GitHub ne répond pas. Réessayez. Rien n'a été publié.",
        machine: "github_unavailable",
      };
  }
}

// ── Étapes sur GitHub ───────────────────────────────────────────────────────

export type AnswerRun =
  | { kind: "closed"; issue: IssueView }
  | { kind: "no_analysis" }
  | { kind: "done"; commentId: number | null; alreadyPublished: boolean; commentCount: number };

/** Échec d'une étape sur GitHub ; `published` : le commentaire est sur l'Issue. */
export class AnswerStepFailure extends Error {
  constructor(
    readonly cause: unknown,
    readonly published: boolean,
  ) {
    super("étape GitHub de la réponse en échec");
  }
}

/**
 * Après une création de commentaire en échec : relit les commentaires et rend la précision
 * qui porte déjà le texte, ou `null`. Une erreur avec un statut 4xx dit que GitHub a refusé
 * la création : rien n'est relu. Précision retrouvée : l'erreur de la création, gardée, passe
 * par `report` (`logError`). Une relecture en échec est journalisée et rend `null`
 * (l'appelant lève l'erreur de la création). Exportée pour les tests.
 */
export async function findAfterFailedCreate(
  client: GithubClient,
  issueNumber: number,
  createError: unknown,
  stateOf: (comments: CommentView[]) => { same: SameAnswer | null },
  report: (entry: LogEntry) => void = logError,
): Promise<SameAnswer | null> {
  if (
    createError instanceof GithubError &&
    createError.status !== null &&
    createError.status >= 400 &&
    createError.status < 500
  ) {
    return null;
  }
  try {
    // Le nombre de commentaires est relu : la page des plus récents en dépend.
    const fresh = await client.getIssue(issueNumber);
    const comments =
      fresh.comments > 0 ? await client.recentComments(issueNumber, fresh.comments) : [];
    const same = stateOf(comments).same;
    if (same !== null) {
      // L'erreur de la création est gardée, pas levée : elle est journalisée ici (statut et
      // message de GitHub, déjà expurgés de tout jeton ; jamais le texte de la réponse).
      report({
        message: "Tickets : création du commentaire en échec, précision trouvée à la relecture",
        feature: "tickets",
        error: createError,
        extra: {
          issue: issueNumber,
          comment_id: same.commentId,
          status: createError instanceof GithubError ? createError.status : null,
        },
      });
    }
    return same;
  } catch (err) {
    logError({
      message: "Tickets : commentaires non relus après une création en échec",
      feature: "tickets",
      error: err,
      extra: { issue: issueNumber },
    });
    return null;
  }
}

/**
 * Étapes 3 à 5 sur GitHub. `recordId` enregistre l'identifiant du commentaire publié (il ne
 * lève pas). Exportée pour les tests.
 */
export async function answerOnGithub(
  client: GithubClient,
  issueNumber: number,
  status: string,
  body: string,
  answerIds: ReadonlySet<number>,
  recordId: (commentId: number | null) => Promise<void>,
): Promise<AnswerRun> {
  let published = false;
  try {
    const issue = await client.getIssue(issueNumber);
    if (issue.state === "closed") return { kind: "closed", issue };
    const comments =
      issue.comments > 0 ? await client.recentComments(issueNumber, issue.comments) : [];
    const state = analysisAnswerState(comments, GITHUB_MAINTAINER_ID, answerIds, body);
    const beforeAnalysis = status === "received";
    if (!state.hasAnalysis && !beforeAnalysis) return { kind: "no_analysis" };
    let commentId: number | null = null;
    let commentCount = issue.comments;
    if (state.same === null) {
      try {
        commentId = (await client.createComment(issueNumber, body)).id;
      } catch (err) {
        const found = await findAfterFailedCreate(client, issueNumber, err, (c) =>
          analysisAnswerState(c, GITHUB_MAINTAINER_ID, answerIds, body),
        );
        if (found === null) throw err;
        commentId = found.commentId;
      }
      published = true;
      commentCount++;
      await recordId(commentId);
    } else {
      published = true;
      // Précision du compte non enregistrée : son identifiant rejoint `answer_comment_ids`.
      if (!state.same.verified && state.same.commentId !== null) {
        await recordId(state.same.commentId);
      }
    }
    // Ordre de Kass'Dalle : `statut:à-analyser` d'abord, puis les deux retraits. Aucun état
    // intermédiaire ne dépasse le statut de départ.
    if (!beforeAnalysis) {
      if (!issue.labels.includes(LABEL_TO_ANALYZE)) {
        await client.addLabels(issueNumber, [LABEL_TO_ANALYZE]);
      }
      if (issue.labels.includes(LABEL_ANALYZED))
        await client.removeLabel(issueNumber, LABEL_ANALYZED);
      if (issue.labels.includes(LABEL_VALIDATED)) {
        await client.removeLabel(issueNumber, LABEL_VALIDATED);
      }
    }
    return { kind: "done", commentId, alreadyPublished: state.samePublished, commentCount };
  } catch (err) {
    throw new AnswerStepFailure(err, published);
  }
}

// ── Firestore ───────────────────────────────────────────────────────────────

async function ticketRef(ticketId: string) {
  const { db } = await firestore();
  return db.collection(COLL_TICKETS).doc(ticketId);
}

interface Lease {
  issueNumber: number;
  status: string;
  leaseUntilMs: number;
}

/** Étape 2 : bail pris en transaction, après la précondition. */
async function claimAnswer(ticketId: string): Promise<Lease> {
  const { db, Timestamp } = await firestore();
  const ref = await ticketRef(ticketId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw refusal("not-found", ANSWER_TICKET_MISSING, "ticket_not_found");
    const data = snap.data() ?? {};
    const issueNumber = data.github_issue_number;
    const hasIssue =
      typeof issueNumber === "number" && Number.isSafeInteger(issueNumber) && issueNumber > 0;
    const refused = answerPrecondition({ status: data.status, hasIssue });
    if (refused !== null) throw refusal("failed-precondition", refused, "not_answerable");
    const lease = data.decision_lease_until;
    const nowMs = Date.now();
    if (lease instanceof Timestamp && lease.toMillis() > nowMs) {
      throw refusal("failed-precondition", ANSWER_LEASE_TAKEN, "decision_in_progress");
    }
    const leaseUntilMs = nowMs + DECISION_LEASE_MS;
    tx.update(ref, { decision_lease_until: Timestamp.fromMillis(leaseUntilMs) });
    return { issueNumber: issueNumber as number, status: String(data.status), leaseUntilMs };
  });
}

/**
 * Étape 6 : ticket `analyzed` ou `validated` ramené à `received`, `answer_reset_at` posé,
 * bail retiré s'il est encore le sien. Rend le statut écrit ou lu.
 */
async function resetAndRelease(ticketId: string, leaseUntilMs: number): Promise<string> {
  const { db, FieldValue, Timestamp } = await firestore();
  const ref = await ticketRef(ticketId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new Error("ticket disparu pendant la réponse");
    const data = snap.data() ?? {};
    const now = Timestamp.now();
    const update: Record<string, unknown> = {};
    const lease = data.decision_lease_until;
    if (lease instanceof Timestamp && lease.toMillis() === leaseUntilMs) {
      update.decision_lease_until = FieldValue.delete();
    }
    let status = String(data.status);
    if (status === "analyzed" || status === "validated") {
      status = "received";
      update.status = status;
      update.answer_reset_at = now;
      update.status_changed_at = now;
      update.allowed_decisions = allowedDecisions(status);
      // Retour à `received` : une validation de l'application ne vaut plus.
      update.validated_by_app_at = null;
      update.updated_at = now;
    }
    if (Object.keys(update).length > 0) tx.update(ref, update);
    return status;
  });
}

/** Retire le bail s'il est encore le sien. Au mieux : il expire seul en deux minutes. */
async function releaseLease(ticketId: string, leaseUntilMs: number): Promise<void> {
  try {
    const { db, FieldValue, Timestamp } = await firestore();
    const ref = await ticketRef(ticketId);
    await db.runTransaction(async (tx) => {
      const lease = (await tx.get(ref)).get("decision_lease_until");
      if (lease instanceof Timestamp && lease.toMillis() === leaseUntilMs) {
        tx.update(ref, { decision_lease_until: FieldValue.delete() });
      }
    });
  } catch (err) {
    logError({
      message: "Tickets : bail de la réponse non libéré (expire seul en 2 min)",
      feature: "tickets",
      ticketId,
      error: err,
    });
  }
}

/** Lit `answer_comment_ids` de `admin/analysis`. */
async function readAnswerIds(ticketId: string): Promise<Set<number>> {
  const ref = await analysisRef(ticketId);
  return readAnswerCommentIds((await ref.get()).get("answer_comment_ids"));
}

/** Ajoute l'identifiant publié à `answer_comment_ids`. Au mieux, journalisé. */
async function rememberAnswerComment(ticketId: string, commentId: number | null): Promise<void> {
  try {
    if (commentId === null) throw new Error("réponse de GitHub sans identifiant de commentaire");
    await recordAnswerCommentId(ticketId, commentId);
  } catch (err) {
    // La précision s'affichera « Non publiée depuis l'application ».
    logError({
      message: "Tickets : précision publiée mais son identifiant n'est pas enregistré",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { comment_id: commentId },
    });
  }
}

/**
 * Étapes 2 à 7 pour un ticket et un texte déjà lus. Rend le statut du ticket après la
 * réponse. Lève une `HttpsError` (motif en français dans `details.reason`).
 */
export async function answerTicket(
  ticketId: string,
  publishedText: string,
  token: string,
  fetchImpl?: FetchLike,
): Promise<{ status: string }> {
  const lease = await claimAnswer(ticketId);
  const log = { feature: "tickets", ticketId };
  let leaseReleased = false;
  try {
    const trimmed = token.trim();
    if (trimmed.length === 0) {
      await markTokenInvalid(null);
      const f = answerGithubFailure("token");
      throw refusal(f.code, f.reason, f.machine);
    }
    const client = githubClient(trimmed, fetchImpl);
    const answerIds = await readAnswerIds(ticketId);
    const body = answerCommentBody(publishedText);

    let run: AnswerRun;
    try {
      run = await answerOnGithub(client, lease.issueNumber, lease.status, body, answerIds, (id) =>
        rememberAnswerComment(ticketId, id),
      );
    } catch (err) {
      const failure = err instanceof AnswerStepFailure ? err : new AnswerStepFailure(err, false);
      const kind = failure.cause instanceof GithubError ? failure.cause.kind : "other";
      logError({
        ...log,
        message: "Tickets : réponse à l'analyse en échec sur GitHub",
        error: failure.cause,
        extra: { kind, published: failure.published, issue: lease.issueNumber },
      });
      if (kind === "token") await markTokenInvalid(failure.cause as GithubError);
      if (failure.published)
        throw refusal("aborted", ANSWER_PARTIAL, "answer_published_labels_failed", true);
      const f = answerGithubFailure(kind);
      throw refusal(f.code, f.reason, f.machine);
    }

    if (run.kind === "closed") {
      try {
        const snap = await (await ticketRef(ticketId)).get();
        if (snap.exists) await applyIssue(client, snap, run.issue);
      } catch (err) {
        logError({ ...log, message: "Tickets : Issue fermée non appliquée au ticket", error: err });
      }
      throw refusal("failed-precondition", ANSWER_ISSUE_CLOSED, "issue_closed");
    }
    if (run.kind === "no_analysis") {
      throw refusal("failed-precondition", ANSWER_NO_ANALYSIS, "no_analysis");
    }

    let status: string;
    try {
      status = await resetAndRelease(ticketId, lease.leaseUntilMs);
      leaseReleased = true;
    } catch (err) {
      logError({
        ...log,
        message: "Tickets : précision publiée, ticket non ramené à Reçu",
        error: err,
      });
      throw refusal("internal", ANSWER_NOT_WRITTEN, "ticket_not_updated", true);
    }
    // Le ticket revient à « Reçu » : les lancements en cours ne bloquent plus une nouvelle
    // analyse (ADR-008, T4, Kass'Dalle).
    if (lease.status !== "received" && status === "received") {
      await closeRunningLaunches(ticketId);
    }
    try {
      await refreshAnalyses(client, ticketId, lease.issueNumber, run.commentCount);
    } catch (err) {
      logError({ ...log, message: "Tickets : analyses non relevées après la réponse", error: err });
    }
    await recordTokenAccepted(client);
    logInfo({
      ...log,
      message: `Tickets : précision publiée sur l'Issue #${lease.issueNumber}, ticket ${status}`,
      extra: { already_published: run.alreadyPublished },
    });
    return { status };
  } finally {
    if (!leaseReleased) await releaseLease(ticketId, lease.leaseUntilMs);
  }
}

/**
 * Corps de la callable : garde, arguments, réponse. Toute erreur hors `HttpsError` est
 * journalisée et rendue en `internal`. `lookup` et `fetchImpl` sont remplacés par les tests.
 */
export async function handleAnswerCall(
  req: AuthLike & { data?: unknown },
  token: () => string,
  deps: { lookup?: MemberLookup; fetchImpl?: FetchLike } = {},
): Promise<{ status: string }> {
  await requireAdmin(req, deps.lookup);
  const ticketId = readTicketIdArg(req.data);
  const text = readAnswerArg(req.data);
  try {
    return await answerTicket(ticketId, text, token(), deps.fetchImpl);
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logError({
      message: "Tickets : réponse à l'analyse non publiée",
      feature: "tickets",
      ticketId,
      error: err,
    });
    throw refusal("internal", ANSWER_INTERNAL, "internal");
  }
}
