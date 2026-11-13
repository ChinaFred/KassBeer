/**
 * Règles pures des décisions de l'administrateur (ADR-006, lot T2) : décisions permises
 * par statut, prise d'une décision, gabarit du commentaire, reconnaissance de ce qui est
 * déjà fait sur GitHub, étapes à faire et message d'échec. Aucune lecture ni écriture ici :
 * `decisions.ts` lit et écrit.
 */

import {
  LABEL_CLOSED,
  LABEL_VALIDATED,
  replyFromComment,
  type CommentView,
  type IssueView,
  type TicketStatus,
} from "./model";
import { publicText } from "./text";

export const DECISION_ACTIONS = ["validate", "refuse", "close"] as const;
export type DecisionAction = (typeof DECISION_ACTIONS)[number];

export function isDecisionAction(value: unknown): value is DecisionAction {
  return typeof value === "string" && (DECISION_ACTIONS as readonly string[]).includes(value);
}

/** Identifiant de décision plausible : il part sur le dépôt public (ligne « Décision »). */
export function isPlausibleDecisionId(value: string): boolean {
  return /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

// ── Décisions permises ──────────────────────────────────────────────────────

/**
 * « Répondre » (`answerTicketAnalysis`, ADR-008, T3) : une callable, pas un document de
 * `decisions/` (les règles refusent `answer` dans `decisions/`). Elle figure dans
 * `allowed_decisions`, que le client lit à part des trois actions des documents.
 */
export const ANSWER_ACTION = "answer";

/**
 * « Lancer l'analyse » et « Lancer le développement » (`launchTicketAnalysis`,
 * `launchTicketDevelopment`, ADR-008, T4) : des callables, jamais des documents de
 * `decisions/` (les règles les refusent). Le client lit ces entrées à part, comme `answer`.
 */
export const LAUNCH_ANALYSIS_ACTION = "launch_analysis";
export const LAUNCH_DEVELOPMENT_ACTION = "launch_development";

export type AllowedDecision =
  | DecisionAction
  | typeof ANSWER_ACTION
  | typeof LAUNCH_ANALYSIS_ACTION
  | typeof LAUNCH_DEVELOPMENT_ACTION;

/**
 * Vrai si `validated_by_app_at` est posé : Valider a été appliqué depuis l'application
 * (décision `validate` de `decisions/`) depuis le dernier retour du ticket sous `validated`.
 * Une étiquette `validé` posée sur GitHub ne le pose pas (ADR-008, décision de
 * l'utilisateur du 2026-11-13). Pure.
 */
export function isValidatedByApp(validatedByAppAt: unknown): boolean {
  return validatedByAppAt !== null && validatedByAppAt !== undefined;
}

/**
 * Statuts qui gardent `validated_by_app_at` : `validated` et `in_progress`. Tout autre
 * statut écrit l'efface, pour qu'un `validé` reposé plus tard sur GitHub ne suffise pas à
 * lancer le développement. Pure.
 */
export function keepsAppValidation(status: unknown): boolean {
  return status === "validated" || status === "in_progress";
}

/**
 * Les décisions que permet un statut (ADR-006, « Décisions de l'administrateur » ; ADR-008,
 * « Statuts », lot T4) : Valider depuis `analyzed`, et depuis `validated` tant que la
 * validation ne vient pas de l'application (`validatedByApp` faux : étiquette posée sur
 * GitHub) ; lancer le développement depuis `validated` validé dans l'application seul ; Répondre depuis `received`,
 * `analyzed` et `validated` (`answerPrecondition` de Kass'Dalle) ; lancer l'analyse depuis
 * `received`, le développement depuis `validated` (`launchPrecondition` de Kass'Dalle).
 * Écrites par le serveur à chaque changement de statut ; le client ne les calcule pas
 * (P26). Le serveur la recalcule à chaque décision et à chaque lancement (P42).
 */
export function allowedDecisions(status: unknown, validatedByApp = false): AllowedDecision[] {
  switch (status) {
    case "received":
      return ["refuse", "close", ANSWER_ACTION, LAUNCH_ANALYSIS_ACTION];
    case "analyzed":
      return ["validate", "refuse", "close", ANSWER_ACTION];
    case "validated":
      return validatedByApp
        ? ["refuse", "close", ANSWER_ACTION, LAUNCH_DEVELOPMENT_ACTION]
        : ["validate", "refuse", "close", ANSWER_ACTION];
    case "in_progress":
      return ["refuse", "close"];
    default:
      return [];
  }
}

/** Vrai si `stored` est déjà la liste attendue pour `status`, dans le même ordre. */
export function allowedDecisionsUpToDate(
  stored: unknown,
  status: unknown,
  validatedByApp = false,
): boolean {
  const wanted = allowedDecisions(status, validatedByApp);
  return (
    Array.isArray(stored) &&
    stored.length === wanted.length &&
    stored.every((value, i) => value === wanted[i])
  );
}

/** Statut du ticket une fois la décision appliquée. */
export function statusAfterDecision(action: DecisionAction): TicketStatus {
  switch (action) {
    case "validate":
      return "validated";
    case "refuse":
      return "refused";
    case "close":
      return "closed";
  }
}

// ── Prise de la décision (étape 1) ──────────────────────────────────────────

export const REJECT_NOT_ALLOWED = "Cette décision n'est plus possible pour ce statut.";
export const REJECT_LEASE_TAKEN = "Une décision est déjà en cours sur ce ticket.";
export const REJECT_TICKET_MISSING = "Ce ticket n'existe plus.";
export const REJECT_NO_ISSUE = "Ce ticket n'a pas encore d'Issue GitHub.";
export const REJECT_INVALID = "Décision illisible.";
export const REJECT_ISSUE_CLOSED = "Ce ticket a déjà été clos sur GitHub.";

export interface DecisionClaimInput {
  decision: {
    state: unknown;
    action: unknown;
    text: unknown;
    /** `lease_until` de la décision, en millisecondes, ou `null`. */
    leaseUntilMs: number | null;
    /** Vrai si `retry_requested_at` est posé. */
    retryRequested: boolean;
  };
  /** `null` si le ticket n'existe plus. */
  ticket: {
    status: unknown;
    allowedDecisions: unknown;
    /** `validated_by_app_at` du ticket, tel que lu. */
    validatedByAppAt?: unknown;
    /** `decision_lease_until` du ticket, en millisecondes, ou `null`. */
    leaseUntilMs: number | null;
    issueNumber: unknown;
  } | null;
  nowMs: number;
}

export type DecisionClaimVerdict =
  | { kind: "skip"; why: "done" | "in_progress" | "failed_without_retry" | "unknown_state" }
  | { kind: "reject"; reason: string }
  | { kind: "claim"; action: DecisionAction; issueNumber: number; resumed: boolean };

/**
 * Ce que fait le déclencheur d'une décision lue en transaction avec son ticket.
 *
 * - `applied` et `rejected` : rien (rejeu) ; `applying` au bail actif : rien ;
 *   `failed` sans reprise demandée : rien.
 * - `pending`, `failed` avec reprise, `applying` au bail expiré : la décision est prise,
 *   sauf si le ticket n'existe plus, n'a pas d'Issue, porte le bail d'une autre décision,
 *   ou si son statut ne permet plus l'action : absente de `allowed_decisions` stocké, ou de
 *   `allowedDecisions(status)` recalculé (P42).
 *
 * Une reprise (`failed` ou `applying`) sur un ticket déjà au statut visé passe aussi :
 * la passe horaire a pu appliquer ce qu'un essai précédent a fait sur GitHub, et la
 * reconnaissance des étapes faites empêche une double publication. Pure.
 */
export function decisionClaimVerdict(input: DecisionClaimInput): DecisionClaimVerdict {
  const { decision, ticket, nowMs } = input;
  const state = decision.state;
  if (state === "applied" || state === "rejected") return { kind: "skip", why: "done" };
  let resumed = false;
  if (state === "applying") {
    if (decision.leaseUntilMs !== null && decision.leaseUntilMs > nowMs) {
      return { kind: "skip", why: "in_progress" };
    }
    resumed = true;
  } else if (state === "failed") {
    if (!decision.retryRequested) return { kind: "skip", why: "failed_without_retry" };
    resumed = true;
  } else if (state !== "pending") {
    return { kind: "skip", why: "unknown_state" };
  }

  const action = decision.action;
  if (!isDecisionAction(action) || !textFitsAction(action, decision.text)) {
    return { kind: "reject", reason: REJECT_INVALID };
  }
  if (ticket === null) return { kind: "reject", reason: REJECT_TICKET_MISSING };
  const issueNumber = ticket.issueNumber;
  if (typeof issueNumber !== "number" || !Number.isSafeInteger(issueNumber) || issueNumber < 1) {
    return { kind: "reject", reason: REJECT_NO_ISSUE };
  }
  // Une décision reprise après l'expiration de son bail retrouve le bail du ticket
  // expiré lui aussi (posés ensemble) ; un bail actif est celui d'une autre décision.
  if (ticket.leaseUntilMs !== null && ticket.leaseUntilMs > nowMs) {
    return { kind: "reject", reason: REJECT_LEASE_TAKEN };
  }
  const stored = Array.isArray(ticket.allowedDecisions)
    ? (ticket.allowedDecisions as unknown[])
    : [];
  // P42 : la liste stockée peut dater d'une règle plus ancienne (elle n'est réécrite qu'au
  // changement de statut ou par la passe horaire) ; la règle du code tranche aussi.
  const allowed =
    stored.includes(action) &&
    (
      allowedDecisions(ticket.status, isValidatedByApp(ticket.validatedByAppAt)) as string[]
    ).includes(action);
  // Une reprise de Valider sur un ticket déjà `validated` passe seulement si la validation
  // de l'application n'est pas encore écrite (sinon il n'y a rien à refaire).
  const alreadyThere =
    resumed &&
    ticket.status === statusAfterDecision(action) &&
    !(action === "validate" && isValidatedByApp(ticket.validatedByAppAt));
  if (!allowed && !alreadyThere) {
    return { kind: "reject", reason: REJECT_NOT_ALLOWED };
  }
  return { kind: "claim", action, issueNumber, resumed };
}

/**
 * Texte présent pour `refuse` et `close`, absent pour `validate`. Les règles bornent la
 * longueur (5 à 2 000) ; le serveur refuse en plus un texte fait d'espaces, qui
 * publierait un commentaire vide, et compte les caractères comme l'écran. Pure.
 */
export function textFitsAction(action: DecisionAction, text: unknown): boolean {
  if (action === "validate") return text === undefined || text === null;
  return typeof text === "string" && text.trim().length > 0 && Array.from(text).length <= 2000;
}

/**
 * Vrai si la mise à jour d'une décision est une reprise demandée par l'administrateur :
 * `retry_requested_at` posé après, absent ou différent avant. Les écritures du serveur
 * (état, bail, motif) déclenchent aussi `onDocumentUpdated` et ne font rien. Pure.
 */
export function isRetryRequest(beforeMs: number | null, afterMs: number | null): boolean {
  return afterMs !== null && afterMs !== beforeMs;
}

// ── Reprise par la passe horaire ────────────────────────────────────────────

/**
 * Délai après lequel une décision encore `pending` est reprise par la passe horaire : le
 * déclencheur de création (60 s au plus, sans rejeu) s'est arrêté avant la prise.
 */
export const PENDING_DECISION_GRACE_MS = 5 * 60 * 1000;

/** Date limite de `requested_at` d'une décision `pending` à reprendre. Pure. */
export function stalePendingCutoffMs(nowMs: number): number {
  return nowMs - PENDING_DECISION_GRACE_MS;
}

/**
 * Vrai si la passe horaire reprend cette décision : `applying` au bail expiré, ou
 * `pending` créée depuis plus de cinq minutes. La transaction de prise tranche ensuite si
 * le déclencheur tourne encore. Pure.
 */
export function isResumableByPass(args: {
  state: unknown;
  leaseUntilMs: number | null;
  requestedAtMs: number | null;
  nowMs: number;
}): boolean {
  if (args.state === "applying") {
    return args.leaseUntilMs === null || args.leaseUntilMs <= args.nowMs;
  }
  if (args.state === "pending") {
    return args.requestedAtMs !== null && args.requestedAtMs < stalePendingCutoffMs(args.nowMs);
  }
  return false;
}

// ── Commentaire publié (P24) ────────────────────────────────────────────────

/** Ligne qui identifie le commentaire d'une décision. */
export function decisionLine(decisionId: string): string {
  return `Décision ${decisionId}`;
}

/**
 * Commentaire d'une décision, sur un gabarit fixe : `Réponse : <texte nettoyé>`, une
 * ligne vide, puis `Décision <id>`. Le texte passe par `publicText` (adresses e-mail,
 * mentions, renvois, balisage, P24). Pure.
 */
export function decisionCommentBody(text: string, decisionId: string): string {
  return `Réponse : ${publicText(text).trim()}\n\n${decisionLine(decisionId)}`;
}

/**
 * Le `reply_text` du ticket pour ce commentaire : celui que la passe horaire relira sur
 * GitHub (`replyFromComment`). Les deux écritures donnent le même texte : la passe
 * horaire ne réécrit pas `reply_text` et n'allume pas la pastille une seconde fois. Pure.
 */
export function replyTextOfComment(
  body: string,
  maintainerId: number,
  maxChars: number,
): string | null {
  return replyFromComment({ authorId: maintainerId, body }, maintainerId, maxChars);
}

/**
 * Vrai si un commentaire du compte `maintainerId` porte la ligne `Décision <id>` : un
 * essai précédent l'a déjà publié (P26). Un commentaire d'un autre compte ne compte pas.
 * Pure.
 */
export function commentCarriesDecision(
  comment: Pick<CommentView, "authorId" | "body">,
  decisionId: string,
  maintainerId: number,
): boolean {
  if (comment.authorId !== maintainerId || typeof comment.body !== "string") return false;
  const marker = decisionLine(decisionId);
  return comment.body.split(/\r?\n/).some((line) => line.trim() === marker);
}

// ── Étapes sur GitHub (étapes 2 à 5) ────────────────────────────────────────

export type DecisionStep = "comment" | "label" | "close";

export type DecisionPlan =
  | { kind: "reject_closed" }
  | {
      kind: "apply";
      comment: boolean;
      label: string | null;
      close: "completed" | "not_planned" | null;
    };

/**
 * Ce qu'il reste à faire sur l'Issue relue, dans l'ordre commentaire → étiquette →
 * fermeture. Ce qui est déjà fait compte comme fait : commentaire qui porte la ligne
 * `Décision <id>`, étiquette posée, Issue fermée de la façon voulue.
 *
 * Une Issue déjà fermée rejette la décision, sauf quand la fermeture est celle de cette
 * décision (essai précédent interrompu après la fermeture) : `refuse` fermée
 * `not_planned` avec son commentaire, `close` fermée avec `statut:clos` et son
 * commentaire. Pure.
 */
export function decisionPlan(
  action: DecisionAction,
  issue: Pick<IssueView, "state" | "stateReason" | "labels">,
  commentPublished: boolean,
): DecisionPlan {
  if (action === "validate") {
    if (issue.state === "closed") return { kind: "reject_closed" };
    return {
      kind: "apply",
      comment: false,
      label: issue.labels.includes(LABEL_VALIDATED) ? null : LABEL_VALIDATED,
      close: null,
    };
  }
  if (action === "refuse") {
    if (issue.state === "closed") {
      return issue.stateReason === "not_planned" && commentPublished
        ? { kind: "apply", comment: false, label: null, close: null }
        : { kind: "reject_closed" };
    }
    return { kind: "apply", comment: !commentPublished, label: null, close: "not_planned" };
  }
  const labelled = issue.labels.includes(LABEL_CLOSED);
  if (issue.state === "closed") {
    return labelled && commentPublished
      ? { kind: "apply", comment: false, label: null, close: null }
      : { kind: "reject_closed" };
  }
  return {
    kind: "apply",
    comment: !commentPublished,
    label: labelled ? null : LABEL_CLOSED,
    close: "completed",
  };
}

/** Vrai si l'action publie un commentaire et doit chercher celui d'un essai précédent. */
export function actionHasComment(action: DecisionAction): boolean {
  return action !== "validate";
}

// ── Échec ───────────────────────────────────────────────────────────────────

export type FailureKind = "token" | "rate_limit" | "not_found" | "network" | "other";

export const FAILURE_TOKEN = "Jeton GitHub refusé ou expiré.";
export const FAILURE_RATE_LIMIT = "GitHub limite les appels pour l'instant. Réessayez plus tard.";
export const FAILURE_ISSUE_MISSING = "L'Issue de ce ticket est introuvable sur GitHub.";
export const FAILURE_TICKET_NOT_WRITTEN =
  "Décision faite sur GitHub, mais le ticket n'a pas été mis à jour. Réessayez.";

/**
 * Message montré à l'administrateur après un échec (`error_reason`). Il dit ce qui est
 * déjà publié ; jamais le jeton ni le message brut de GitHub. Pure.
 */
export function failureReason(
  action: DecisionAction,
  stepsDone: readonly DecisionStep[],
  kind: FailureKind,
): string {
  if (kind === "token") return FAILURE_TOKEN;
  if (kind === "not_found") return FAILURE_ISSUE_MISSING;
  const prefix = kind === "rate_limit" ? `${FAILURE_RATE_LIMIT} ` : "";
  const commented = stepsDone.includes("comment");
  if (action === "refuse" && commented) {
    return `${prefix}Motif publié, mais l'Issue n'a pas été fermée. Réessayez.`;
  }
  if (action === "close" && commented) {
    return `${prefix}Commentaire publié, mais l'Issue n'a pas été close. Réessayez.`;
  }
  if (kind === "rate_limit") return FAILURE_RATE_LIMIT;
  return "GitHub n'a pas répondu, rien n'a été publié. Réessayez.";
}
