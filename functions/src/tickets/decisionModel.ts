/**
 * Règles pures des décisions de l'administrateur (ADR-006, lot T2 ; ADR-008, lot T7) :
 * décisions permises par statut, précondition de `validateTicket`, `refuseTicket` et
 * `closeTicket`, texte de Refuser et de Clore, gabarit du commentaire, reconnaissance de ce
 * qui est déjà fait sur GitHub, étapes à faire et message d'échec. Aucune lecture ni écriture
 * ici : `decisions.ts` lit et écrit.
 */

import {
  LABEL_CLOSED,
  LABEL_VALIDATED,
  replyFromComment,
  type CommentView,
  type IssueView,
  type TicketStatus,
} from "./model";
import { cleanMultiline, publicText } from "./text";

export const DECISION_ACTIONS = ["validate", "refuse", "close"] as const;
export type DecisionAction = (typeof DECISION_ACTIONS)[number];

export function isDecisionAction(value: unknown): value is DecisionAction {
  return typeof value === "string" && (DECISION_ACTIONS as readonly string[]).includes(value);
}

// ── Décisions permises ──────────────────────────────────────────────────────

/**
 * « Répondre » (`answerTicketAnalysis`, ADR-008, T3) : une callable qui n'écrit aucun
 * document de `decisions/`. Elle figure dans `allowed_decisions`, que le client lit à part
 * des trois décisions.
 */
export const ANSWER_ACTION = "answer";

/**
 * « Lancer l'analyse » et « Lancer le développement » (`launchTicketAnalysis`,
 * `launchTicketDevelopment`, ADR-008, T4) : des callables qui n'écrivent aucun document de
 * `decisions/`. Le client lit ces entrées à part, comme `answer`.
 */
export const LAUNCH_ANALYSIS_ACTION = "launch_analysis";
export const LAUNCH_DEVELOPMENT_ACTION = "launch_development";

/**
 * « Livrer » (`launchTicketDelivery`) et « Relancer le développement »
 * (`launchTicketDevelopment`, `mode: "resume"`), ADR-008, T5 : des callables, comme les
 * lancements de T4. Offerts sur un ticket `in_progress` validé dans l'application seul
 * (décisions de l'utilisateur du 2026-11-14) ; le serveur recontrôle chaque appel (P43, P47).
 */
export const LAUNCH_DELIVERY_ACTION = "launch_delivery";
export const RELAUNCH_DEVELOPMENT_ACTION = "relaunch_development";

export type AllowedDecision =
  | DecisionAction
  | typeof ANSWER_ACTION
  | typeof LAUNCH_ANALYSIS_ACTION
  | typeof LAUNCH_DEVELOPMENT_ACTION
  | typeof LAUNCH_DELIVERY_ACTION
  | typeof RELAUNCH_DEVELOPMENT_ACTION;

/**
 * Vrai si `validated_by_app_at` est posé : Valider a été appliqué depuis l'application
 * (`validateTicket`) depuis le dernier retour du ticket sous `validated`.
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
 * `received`, le développement depuis `validated` (`launchPrecondition` de Kass'Dalle) ;
 * livrer et relancer le développement depuis `in_progress` validé dans l'application seul
 * (T5). Écrites par le serveur à chaque changement de statut ; le client ne les calcule pas
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
      return validatedByApp
        ? ["refuse", "close", LAUNCH_DELIVERY_ACTION, RELAUNCH_DEVELOPMENT_ACTION]
        : ["refuse", "close"];
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
export const REJECT_ISSUE_CLOSED = "Ce ticket a déjà été clos sur GitHub.";
/** Refuser ou Clore pendant la livraison de ce ticket (P44, décision du 2026-11-14). */
export const REJECT_DELIVERY_RUNNING = "Une livraison est en cours sur ce ticket. Attendez sa fin.";

/** Décision la plus récente du ticket (`requested_at` décroissant), telle que lue. */
export interface LatestDecision {
  id: string;
  action: unknown;
  state: unknown;
  /** `lease_until` de la décision, en millisecondes, ou `null`. */
  leaseUntilMs: number | null;
  stepsDone: unknown;
  text: unknown;
  commentId: unknown;
}

export interface DecisionStartInput {
  action: DecisionAction;
  /** `null` si le ticket n'existe pas. */
  ticket: {
    status: unknown;
    /** `validated_by_app_at` du ticket, tel que lu. */
    validatedByAppAt: unknown;
    /** `decision_lease_until` du ticket, en millisecondes, ou `null`. */
    leaseUntilMs: number | null;
    issueNumber: unknown;
    /**
     * Vrai si `ticket_status/launches.delivery_running` porte ce ticket et que son échéance
     * est future : Refuser et Clore sont refusés (P44).
     */
    deliveryRunning: boolean;
  } | null;
  latest: LatestDecision | null;
  nowMs: number;
}

/** Refus d'une décision avant tout appel à GitHub : code de `HttpsError`, code stable, motif. */
export interface DecisionRefusal {
  kind: "refuse";
  code: "not-found" | "failed-precondition";
  machine: string;
  reason: string;
}

export type DecisionStart =
  | DecisionRefusal
  /** Déjà fait (réponse perdue puis second appui) : rien n'est publié. */
  | { kind: "done"; status: TicketStatus }
  | {
      kind: "start";
      issueNumber: number;
      /**
       * Décision reprise (même identifiant, même ligne `Décision <id>`), ou `null` : une
       * nouvelle décision est créée. `keepText` : le commentaire est déjà publié, le texte
       * stocké est gardé et le texte reçu ignoré.
       */
      resume: { id: string; keepText: boolean; knownCommentId: number | null } | null;
    };

function refuse(code: DecisionRefusal["code"], machine: string, reason: string): DecisionRefusal {
  return { kind: "refuse", code, machine, reason };
}

/** Vrai si `stepsDone` lu dans une décision contient l'étape `step`. Pure. */
function hasStep(stepsDone: unknown, step: DecisionStep): boolean {
  return Array.isArray(stepsDone) && stepsDone.includes(step);
}

/**
 * Ce que fait `validateTicket`, `refuseTicket` ou `closeTicket` (ADR-008, T7, P53), lu dans
 * la transaction du bail avec le ticket, le verrou des livraisons et la décision la plus
 * récente du ticket. Dans l'ordre :
 *
 * 1. ticket absent : `not-found` ;
 * 2. déjà fait : Valider sur un ticket validé dans l'application ; Refuser ou Clore sur un
 *    ticket déjà au statut visé dont la dernière décision de cette action est `applied` ;
 * 3. Issue absente, bail actif : refus ;
 * 4. reprise de la décision la plus récente si elle est de la même action et `failed`,
 *    `pending` (écrite par un client d'avant T7, jamais prise), ou `applying` au bail
 *    expiré ;
 * 5. action absente de `allowedDecisions(status, validatedByApp)` recalculé, sans lire la
 *    liste stockée (P42) : refus, sauf pour une reprise sur un ticket déjà au statut visé
 *    (la passe horaire a pu relire l'Issue fermée par l'essai précédent) ;
 * 6. Refuser ou Clore pendant une livraison de ce ticket : refus (P44). Pure.
 */
export function decisionStart(input: DecisionStartInput): DecisionStart {
  const { action, ticket, latest, nowMs } = input;
  if (ticket === null) return refuse("not-found", "ticket_missing", REJECT_TICKET_MISSING);
  const byApp = isValidatedByApp(ticket.validatedByAppAt);
  const target = statusAfterDecision(action);
  const sameAction = latest !== null && latest.action === action;
  if (action === "validate" ? ticket.status === target && byApp : ticket.status === target) {
    if (action === "validate" || (sameAction && latest?.state === "applied")) {
      return { kind: "done", status: target };
    }
  }
  const issueNumber = ticket.issueNumber;
  if (typeof issueNumber !== "number" || !Number.isSafeInteger(issueNumber) || issueNumber < 1) {
    return refuse("failed-precondition", "no_issue", REJECT_NO_ISSUE);
  }
  if (ticket.leaseUntilMs !== null && ticket.leaseUntilMs > nowMs) {
    return refuse("failed-precondition", "decision_in_progress", REJECT_LEASE_TAKEN);
  }
  const resumable =
    sameAction &&
    (latest.state === "failed" ||
      latest.state === "pending" ||
      (latest.state === "applying" &&
        (latest.leaseUntilMs === null || latest.leaseUntilMs <= nowMs)));
  const alreadyThere = resumable && ticket.status === target && !(action === "validate" && byApp);
  const allowed = (allowedDecisions(ticket.status, byApp) as string[]).includes(action);
  if (!allowed && !alreadyThere) {
    return refuse("failed-precondition", "not_allowed", REJECT_NOT_ALLOWED);
  }
  // Une Issue fermée ou refusée pendant que la session fusionne la PR qui la ferme laisserait
  // un ticket clos avec une PR livrée (P44).
  if (ticket.deliveryRunning && action !== "validate" && !alreadyThere) {
    return refuse("failed-precondition", "delivery_running", REJECT_DELIVERY_RUNNING);
  }
  if (!resumable) return { kind: "start", issueNumber, resume: null };
  const commentId = latest.commentId;
  return {
    kind: "start",
    issueNumber,
    resume: {
      id: latest.id,
      keepText:
        actionHasComment(action) &&
        hasStep(latest.stepsDone, "comment") &&
        typeof latest.text === "string",
      knownCommentId:
        typeof commentId === "number" && Number.isSafeInteger(commentId) ? commentId : null,
    },
  };
}

// ── Texte de Refuser et de Clore ────────────────────────────────────────────

export const DECISION_TEXT_MIN_CHARS = 5;
/** Comme « Répondre » (décision de l'utilisateur du 2026-11-14, P53). */
export const DECISION_TEXT_MAX_CHARS = 4000;
/** Garde de taille brute, avant le nettoyage (`requireBoundedText`). */
export const DECISION_TEXT_RAW_MAX_CHARS = 16_000;

/** Motif du refus d'un texte trop court ou trop long, selon l'action. Pure. */
export function decisionTextLengthReason(action: "refuse" | "close", tooLong: boolean): string {
  const name = action === "refuse" ? "Le motif" : "Le commentaire";
  return tooLong
    ? `${name} ne doit pas dépasser 4 000 caractères.`
    : `${name} doit faire au moins 5 caractères.`;
}

/**
 * Le texte de Refuser ou de Clore, ou le motif du refus. Caractères de contrôle retirés
 * (retours à la ligne gardés), NFC, espaces de bord retirées, 5 à 4 000 caractères comptés
 * comme l'écran (points de code) ; un texte qui ne publie rien de lisible par `publicText`
 * est trop court. Le texte rendu est celui qui est stocké dans la décision : il passe par
 * `publicText` à la publication (`decisionCommentBody`). Pure.
 */
export function readDecisionText(
  action: "refuse" | "close",
  raw: string,
): { ok: true; text: string } | { ok: false; reason: string } {
  const text = cleanMultiline(raw).normalize("NFC").trim();
  const length = Array.from(text).length;
  if (length < DECISION_TEXT_MIN_CHARS) {
    return { ok: false, reason: decisionTextLengthReason(action, false) };
  }
  if (length > DECISION_TEXT_MAX_CHARS) {
    return { ok: false, reason: decisionTextLengthReason(action, true) };
  }
  if (publicText(text).trim().length === 0) {
    return { ok: false, reason: decisionTextLengthReason(action, false) };
  }
  return { ok: true, text };
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
 * Le texte d'un commentaire de décision publié (`Réponse : <texte>`, ligne `Décision <id>`
 * retirée), borné à `DECISION_TEXT_MAX_CHARS` points de code (coupé par « … ») : il remplace
 * le `text` de la décision quand un essai précédent l'a publié. Un commentaire modifié sur
 * GitHub ne fait pas grossir le document au-delà. `null` si le commentaire n'a pas la forme
 * d'une réponse. Pure.
 */
export function decisionTextOfComment(body: string, maintainerId: number): string | null {
  return replyFromComment({ authorId: maintainerId, body }, maintainerId, DECISION_TEXT_MAX_CHARS);
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

/** Erreur rendue au client après un échec sur GitHub (ADR-008, T7, P53). */
export interface DecisionFailure {
  code: "failed-precondition" | "not-found" | "unavailable" | "aborted";
  machine: string;
  reason: string;
  /** Le commentaire est publié : le texte ne doit plus changer. */
  partial: boolean;
}

/**
 * Code de `HttpsError`, code stable et motif d'un échec sur GitHub. Commentaire déjà
 * publié : `aborted`, `refuse_partial` ou `close_partial`, `partial`. Sinon rien n'est
 * publié : jeton refusé, Issue introuvable, limite de débit ou GitHub muet. Pure.
 */
export function decisionFailure(
  action: DecisionAction,
  stepsDone: readonly DecisionStep[],
  kind: FailureKind,
): DecisionFailure {
  const reason = failureReason(action, stepsDone, kind);
  if (stepsDone.includes("comment")) {
    return { code: "aborted", machine: `${action}_partial`, reason, partial: true };
  }
  switch (kind) {
    case "token":
      return { code: "failed-precondition", machine: "github_token", reason, partial: false };
    case "not_found":
      return { code: "not-found", machine: "issue_not_found", reason, partial: false };
    case "rate_limit":
      return { code: "unavailable", machine: "github_rate_limit", reason, partial: false };
    default:
      return { code: "unavailable", machine: "github_unavailable", reason, partial: false };
  }
}
