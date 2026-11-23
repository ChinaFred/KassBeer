/**
 * Lancement d'une session Claude Code sur un ticket, par une Routine (ADR-008, T4 et T5, P35,
 * P36, P41, P43, P44, P47) : « Lancer l'analyse » (ticket Reçu), « Lancer le développement »
 * (ticket Validé), « Relancer le développement » (`reprise`, ticket En cours à CI rouge) et
 * « Livrer » (`livraison`, ticket En cours à PR prête), appelés par `launchTicketAnalysis`,
 * `launchTicketDevelopment` (`mode: "start"` ou `"resume"`) et `launchTicketDelivery` après
 * `requireAdmin`.
 * Copie de `functions/src/tickets/launch.ts` de Kass'Dalle, adaptée : bail des décisions de
 * Kass'Beer (`decision_lease_until`), plafond `LAUNCHES_PER_DAY` de `config.ts`, compte
 * fondateur reconnu par `members/{email}.founder` (jamais par un e-mail écrit dans le code,
 * P15) et compté à part (`FOUNDER_LAUNCHES_PER_DAY`), pas de type Question, règle « en
 * cours » réduite à `retry_after`.
 *
 * Dans l'ordre :
 *  1. secrets de la routine présents et identifiant bien formé, sinon « Lancement non
 *     configuré » : rien compté, rien envoyé ;
 *  2. transaction sur le ticket : existant, `launchPrecondition` (statut, Issue, règle des
 *     décisions permises recalculée), aucun bail actif, aucun lancement qui le bloque en
 *     cours (`runningLaunch`, historique lu dans la transaction) ; reprise : verrou des
 *     livraisons non tenu par ce ticket, `admin/delivery.relaunch_ready` vrai (P47) ; bail
 *     posé (210 s pour une livraison, 150 s sinon) ;
 *  2 bis. livraison seulement, rien compté en cas de refus (P43) : PR ouvertes, fichiers et
 *     runs de la CI relus sur GitHub (état écrit dans `admin/delivery`), une seule PR
 *     éligible, aucun fichier sensible, CI verte ; puis verrou global des livraisons
 *     (`delivery_running`, P44) ;
 *  3. plafond du jour (P36) : transaction sur `ticket_quotas/launch_{AAAAMMJJ}` (ou
 *     `launch_founder_{AAAAMMJJ}` pour le fondateur) et `ticket_status/launches` ; refus au
 *     plafond du compteur de l'appelant ;
 *  4. Issue relue sur GitHub : fermée, ou étiquettes qui donnent un autre statut → l'état
 *     relu est appliqué, rien n'est lancé ;
 *  5. entrée d'historique écrite `unknown` AVANT l'appel : une fonction coupée pendant
 *     l'appel laisse une trace comptée qui bloque jusqu'à `retry_after` ;
 *  6. appel unique de l'API (`fireRoutine`, 30 s, jamais rejoué) ;
 *  7. entrée mise à jour : `launched` (compté), `failed` (compteur rendu, `retry_after`
 *     ramené à l'heure du lancement), ou laissée `unknown` (compté, bloque) sans réponse ou
 *     sur un 5xx.
 * Le compteur est rendu quand rien n'est parti (refus, panne avant l'appel, refus de l'API).
 * Le bail est libéré à la fin, réussite ou échec.
 *
 * File des livraisons (amendement du 2026-11-22) : `launchTicketDelivery` reçoit `mode`
 * (`start`, `queue`, `unqueue`, `resume_queue`, `handleDeliveryCall`) ; « Mettre en file » refait les contrôles
 * de P43 sans rien compter (`queueTicketDelivery`) ; la tâche `startQueuedDelivery` fait partir
 * la tête de file (`runQueuedDelivery`), compte le lancement au départ sur le compteur de
 * l'auteur de l'accord, relu à ce moment.
 *
 * Rien n'est écrit dans `tickets/{id}`, que l'auteur lit : ni lien de session, ni uid de
 * l'administrateur. Le jeton n'est jamais journalisé (P35).
 */

import { randomUUID } from "node:crypto";

import type { DocumentSnapshot } from "firebase-admin/firestore";
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

import {
  firestoreMemberLookup,
  memberKeyOf,
  requireAdmin,
  requireBoundedText,
  type AuthLike,
  type MemberLookup,
} from "../auth";
import {
  COLL_TICKET_QUOTAS,
  DELIVERY_QUEUE_MAX,
  COLL_TICKET_STATUS,
  COLL_TICKETS,
  LAUNCH_COST_CENTER,
  QUOTA_TTL_DAYS,
  TICKET_ADMIN_SUBCOLLECTION,
  TICKET_LAUNCHES_DOC,
  TICKET_STATUS_GITHUB_DOC,
  TICKET_STATUS_LAUNCHES_DOC,
} from "../config";
import { firestore, type FirestoreKit } from "../firestore";
import { logError, logInfo, logWarn, type LogEntry } from "../logging";
import { readTicketIdArg } from "./answer";
import {
  DELIVERY_ACTIONS_FORBIDDEN_MESSAGE,
  DELIVERY_NO_PR_MESSAGE,
  DELIVERY_NOTHING,
  QUEUE_EXIT_HEAD_CHANGED,
  QUEUE_EXIT_NOT_ADMIN,
  QUEUE_EXIT_RELAUNCHED,
  claimDeliveryLock,
  deliveryCiNotGreenMessage,
  deliveryFilesUnreadableMessage,
  deliveryLockFields,
  deliveryLockHeld,
  deliveryMultiplePrMessage,
  deliveryQueueDeparture,
  deliveryRef,
  deliverySensitiveMessage,
  dequeueHead,
  dequeueInTransaction,
  enqueueDelivery,
  readDelivery,
  readDeliveryLock,
  readDeliveryQueue,
  releaseDeliveryLock,
  resumeHaltedQueue,
  sameQueueEntry,
  sensitiveDeliveryPath,
  unqueueDelivery,
  writeDeliveryState,
  type DeliveryQueueEntryView,
  type QueueRestore,
  type DeliveryQueueRefusal,
  type DeliveryQueueStop,
} from "./delivery";
import {
  GithubActionsForbidden,
  GithubError,
  githubClient,
  type FetchLike,
  type GithubClient,
} from "./github";
import { applyIssue } from "./issueState";
import {
  LAUNCH_FROM_STATUS,
  LAUNCH_HISTORY_MAX,
  LAUNCH_REASON_MAX,
  ROUTINE_INVALID_FIELD,
  closeRunningEntries,
  launchCommandText,
  launchFitsQuota,
  launchLimitOf,
  launchPoolOf,
  launchPrecondition,
  launchQuotaDocId,
  launchEntryViews,
  launchQuotaMessage,
  launchRawEntries,
  launchRetryAfterMs,
  launchRunningMessage,
  nextLaunchStatus,
  readLaunchCount,
  refreshedLaunchStatus,
  runningLaunch,
  type LaunchAction,
  type LaunchPool,
} from "./launchModel";
import { parisDay, statusFromIssue, type IssueView } from "./model";
import {
  ROUTINE_SERVER_ERROR_MESSAGE,
  fireRoutine,
  routineConfig,
  routineFailureMessage,
  type FireOutcome,
  type RoutineFailureKind,
  type RoutineFetch,
} from "./routine";
import { markTokenInvalid, recordTokenAccepted } from "./tokenStatus";

/**
 * Bail d'un lancement sur le ticket (`decision_lease_until`, partagé avec les décisions et
 * « Répondre ») : plus long que le délai de la callable (120 s). Un bail expiré veut dire
 * une fonction arrêtée.
 */
export const LAUNCH_LEASE_MS = 150 * 1000;

/** Bail d'une livraison : plus long que le délai de `launchTicketDelivery` (180 s, P43). */
export const DELIVERY_LEASE_MS = 210 * 1000;

/**
 * Bail d'un départ de la file (`startQueuedDelivery`, point 8) : plus long que le délai de la
 * tâche (300 s).
 */
export const QUEUED_DELIVERY_LEASE_MS = 330 * 1000;

/** Le bail posé par un lancement. Pure. */
export function launchLeaseMs(action: LaunchAction): number {
  return action === "livraison" ? DELIVERY_LEASE_MS : LAUNCH_LEASE_MS;
}

// ── Ce que rend la callable ─────────────────────────────────────────────────

/**
 * Réponse d'un lancement abouti (`launched`) ou au résultat inconnu (`unknown`). Un refus
 * est une `HttpsError`. `sessionUrl` : lien `https://claude.ai/…` de la session, absent si
 * l'API n'en rend pas. `reason` : message d'un résultat inconnu venu d'un 5xx.
 */
export type LaunchResult =
  { outcome: "launched"; sessionUrl?: string } | { outcome: "unknown"; reason?: string };

export const LAUNCH_NOT_CONFIGURED_MESSAGE =
  "Lancement non configuré : ajoutez l'identifiant et le jeton de la routine dans Secret Manager.";
export const LAUNCH_TICKET_MISSING = "Ce ticket n'existe plus.";
export const LAUNCH_LEASE_TAKEN = "Une décision est déjà en cours sur ce ticket.";
export const LAUNCH_TICKET_CHANGED_MESSAGE = "Le ticket a changé sur GitHub. Rien n'a été lancé.";
export const LAUNCH_NOT_RECORDED_MESSAGE =
  "Le lancement n'a pas pu être préparé. Rien n'a été lancé.";
export const LAUNCH_INTERNAL_MESSAGE =
  "Le lancement a échoué. Regardez la section Lancements avant de relancer.";
/** Reprise refusée : la CI de la PR n'est plus en échec (P47). */
export const REPRISE_CI_NOT_RED_MESSAGE =
  "La CI de la pull request n'est pas en échec. Rien n'a été lancé ni décompté.";
/** Reprise refusée : une livraison de ce ticket est en cours (P47). */
export const REPRISE_DELIVERY_RUNNING_MESSAGE =
  "Une livraison est en cours sur ce ticket. Rien n'a été lancé ni décompté.";
/** `mode` de `launchTicketDevelopment` hors `start` et `resume` (P47). */
export const LAUNCH_MODE_INVALID = "Mode de lancement : « start » ou « resume » attendu.";
/** `mode` de `launchTicketDelivery` hors `start`, `queue`, `unqueue` et `resume_queue` (P43). */
export const DELIVERY_MODE_INVALID =
  "Mode de livraison : « start », « queue », « unqueue » ou « resume_queue » attendu.";
/** « Relancer la file » refusé : le ticket n'est pas en tête de file. */
export const QUEUE_RESUME_NOT_HEAD_MESSAGE =
  "Ce ticket n'est pas en tête de la file des livraisons. Rien n'a été relancé.";
/** « Livrer » refusé : la file n'est pas vide (point 5). */
export const DELIVERY_QUEUE_AHEAD_MESSAGE = `D'autres livraisons attendent : appuyez sur « Mettre en file ». ${DELIVERY_NOTHING}`;
/** Refus de « Mettre en file » (point 4). */
export const DELIVERY_QUEUE_REFUSALS: Record<
  DeliveryQueueRefusal,
  { reason: string; machine: string }
> = {
  already: { reason: "Ce ticket est déjà dans la file.", machine: "delivery_queue_already" },
  running_here: {
    reason: "Une livraison est en cours sur ce ticket. Rien n'a été mis en file.",
    machine: "delivery_running",
  },
  full: {
    reason: `La file compte déjà ${DELIVERY_QUEUE_MAX} livraisons. Rien n'a été mis en file.`,
    machine: "delivery_queue_full",
  },
  lock_free: {
    reason: "La livraison précédente est finie : appuyez sur « Livrer ».",
    machine: "delivery_lock_free",
  },
};
/** Départ refusé : la tête de la PR a changé depuis l'accord (point 8). */
export const QUEUE_HEAD_CHANGED_MESSAGE = `Le code de la PR a changé depuis l'accord. ${DELIVERY_NOTHING}`;

/**
 * Refus rendu au client : `details.reason` (français) et `details.code` (stable), plus les
 * champs de `extra` (`limit` pour le plafond).
 */
function refusal(
  code: FunctionsErrorCode,
  reason: string,
  machine: string,
  extra: Record<string, unknown> = {},
): HttpsError {
  return new HttpsError(code, reason, { reason, code: machine, ...extra });
}

/** Code et motif d'un échec GitHub avant l'appel : rien n'a été lancé. Pure. */
export function launchGithubFailure(kind: string): {
  code: FunctionsErrorCode;
  reason: string;
  machine: string;
} {
  switch (kind) {
    case "token":
      return {
        code: "failed-precondition",
        reason: "GitHub refuse le jeton. Rien n'a été lancé.",
        machine: "github_token",
      };
    case "not_found":
      return {
        code: "not-found",
        reason: "L'Issue n'existe plus sur GitHub. Rien n'a été lancé.",
        machine: "issue_not_found",
      };
    case "rate_limit":
      return {
        code: "unavailable",
        reason: "GitHub limite les appels. Réessayez dans quelques minutes. Rien n'a été lancé.",
        machine: "github_rate_limit",
      };
    default:
      return {
        code: "unavailable",
        reason: "GitHub ne répond pas. Réessayez. Rien n'a été lancé.",
        machine: "github_unavailable",
      };
  }
}

/** Code stable et code HTTP rendus pour un refus de l'API des routines. Pure. */
export function routineFailureCode(failure: RoutineFailureKind): {
  code: FunctionsErrorCode;
  machine: string;
} {
  switch (failure) {
    case "rate_limit":
      return { code: "resource-exhausted", machine: "routine_rate_limited" };
    case "token":
    case "not_found":
      return { code: "failed-precondition", machine: "routine_invalid" };
    case "paused":
      return { code: "failed-precondition", machine: "routine_paused" };
    case "rejected":
      return { code: "failed-precondition", machine: "routine_failed" };
  }
}

// ── Dépendances (remplacées par les tests) ──────────────────────────────────

export type Logger = (level: "error" | "warn" | "info", entry: LogEntry) => void;

const defaultLogger: Logger = (level, entry) => {
  if (level === "error") logError(entry);
  else if (level === "warn") logWarn(entry);
  else logInfo(entry);
};

export interface LaunchDeps {
  /** Identifiant et jeton de la routine de l'action, lus à l'appel. */
  routine: () => { id: string; token: string };
  /** Jeton GitHub, lu à l'appel. */
  githubToken: () => string;
  kit?: () => Promise<FirestoreKit>;
  fetchGithub?: FetchLike;
  fetchRoutine?: RoutineFetch;
  nowMs?: () => number;
  log?: Logger;
  applyIssue?: (client: GithubClient, doc: DocumentSnapshot, issue: IssueView) => Promise<void>;
  markTokenInvalid?: (error: GithubError | null) => Promise<void>;
  recordTokenAccepted?: (client: GithubClient) => Promise<void>;
}

interface Ctx {
  kit: FirestoreKit;
  now: () => number;
  log: Logger;
  ticketId: string;
  action: LaunchAction;
  /** Compteur du jour de l'appelant. */
  pool: LaunchPool;
  /** Bail posé sur le ticket ; absent : `launchLeaseMs(action)`. */
  leaseMs?: number;
}

function base(ctx: Ctx, message: string, extra: LogEntry["extra"] = {}): LogEntry {
  return {
    message,
    feature: "tickets",
    ticketId: ctx.ticketId,
    extra: { action: ctx.action, cost_center: LAUNCH_COST_CENTER, pool: ctx.pool, ...extra },
  };
}

// ── Firestore ───────────────────────────────────────────────────────────────

function ticketRef(kit: FirestoreKit, ticketId: string) {
  return kit.db.collection(COLL_TICKETS).doc(ticketId);
}

function launchesRef(kit: FirestoreKit, ticketId: string) {
  return ticketRef(kit, ticketId).collection(TICKET_ADMIN_SUBCOLLECTION).doc(TICKET_LAUNCHES_DOC);
}

function statusRef(kit: FirestoreKit) {
  return kit.db.collection(COLL_TICKET_STATUS).doc(TICKET_STATUS_LAUNCHES_DOC);
}

function quotaRef(kit: FirestoreKit, day: string, pool: LaunchPool = "group") {
  return kit.db.collection(COLL_TICKET_QUOTAS).doc(launchQuotaDocId(day, pool));
}

/** Code stable d'un refus « en cours » : `reprise_running` quand une reprise bloque. Pure. */
export function runningRefusalCode(action: LaunchAction, blocking: LaunchAction): string {
  if (action === "livraison" && blocking === "reprise") return "reprise_running";
  if (action === "reprise" && blocking === "livraison") return "reprise_blocked_by_delivery";
  return "running";
}

/** Étape 2 : précondition, « en cours » et bail, en une transaction. Rend le numéro d'Issue. */
async function claimLaunch(ctx: Ctx): Promise<{ issueNumber: number; leaseUntilMs: number }> {
  const { db, Timestamp } = ctx.kit;
  const ref = ticketRef(ctx.kit, ctx.ticketId);
  const historyRef = launchesRef(ctx.kit, ctx.ticketId);
  const resume = ctx.action === "reprise";
  return db.runTransaction(async (tx) => {
    const [snap, history, delivery, status] = await Promise.all([
      tx.get(ref),
      tx.get(historyRef),
      resume ? tx.get(deliveryRef(ctx.kit, ctx.ticketId)) : Promise.resolve(null),
      resume ? tx.get(statusRef(ctx.kit)) : Promise.resolve(null),
    ]);
    if (!snap.exists) throw refusal("not-found", LAUNCH_TICKET_MISSING, "ticket_not_found");
    const data = snap.data() ?? {};
    const issueNumber = data.github_issue_number;
    const hasIssue =
      typeof issueNumber === "number" && Number.isSafeInteger(issueNumber) && issueNumber > 0;
    const refused = launchPrecondition(
      { status: data.status, hasIssue, validatedByAppAt: data.validated_by_app_at },
      ctx.action,
    );
    if (refused !== null) throw refusal("failed-precondition", refused, "not_launchable");
    const nowMs = ctx.now();
    const lease = data.decision_lease_until;
    if (lease instanceof Timestamp && lease.toMillis() > nowMs) {
      throw refusal("failed-precondition", LAUNCH_LEASE_TAKEN, "decision_in_progress");
    }
    const running = runningLaunch(
      launchEntryViews(ctx.kit, launchRawEntries(history.data())),
      ctx.action,
      nowMs,
    );
    if (running !== null) {
      throw refusal(
        "failed-precondition",
        launchRunningMessage(running.action, running.atMs, running.retryAfterMs),
        runningRefusalCode(ctx.action, running.action),
      );
    }
    if (resume) {
      // P47 : aucune livraison de ce ticket en cours, CI de la PR en échec (écrit par le
      // serveur dans `admin/delivery`, P45).
      const millis = (v: unknown) => (v instanceof Timestamp ? v.toMillis() : null);
      const lock = readDeliveryLock(status?.get("delivery_running"), millis);
      if (lock !== null && lock.ticketId === ctx.ticketId && deliveryLockHeld(lock, nowMs)) {
        throw refusal(
          "failed-precondition",
          REPRISE_DELIVERY_RUNNING_MESSAGE,
          "reprise_blocked_by_delivery",
        );
      }
      if (delivery?.get("relaunch_ready") !== true) {
        throw refusal("failed-precondition", REPRISE_CI_NOT_RED_MESSAGE, "reprise_ci_not_red");
      }
      // P47 : une reprise retire le ticket de la file des livraisons, dans la transaction du bail.
      dequeueInTransaction(tx, ctx.kit, status?.data(), ctx.ticketId, QUEUE_EXIT_RELAUNCHED, nowMs);
    }
    const leaseUntilMs = nowMs + (ctx.leaseMs ?? launchLeaseMs(ctx.action));
    tx.update(ref, { decision_lease_until: Timestamp.fromMillis(leaseUntilMs) });
    return { issueNumber: issueNumber as number, leaseUntilMs };
  });
}

/** Retire le bail s'il est encore le sien. Au mieux : il expire seul. */
async function releaseLease(ctx: Ctx, leaseUntilMs: number): Promise<void> {
  try {
    const { db, FieldValue, Timestamp } = ctx.kit;
    const ref = ticketRef(ctx.kit, ctx.ticketId);
    await db.runTransaction(async (tx) => {
      const lease = (await tx.get(ref)).get("decision_lease_until");
      if (lease instanceof Timestamp && lease.toMillis() === leaseUntilMs) {
        tx.update(ref, { decision_lease_until: FieldValue.delete() });
      }
    });
  } catch (err) {
    ctx.log("error", {
      ...base(ctx, "Tickets : bail du lancement non libéré (expire seul)"),
      error: err,
    });
  }
}

/**
 * Étape 3 : compte le lancement si le plafond le permet, en transaction : compteur du jour
 * de l'appelant et `ticket_status/launches`. Lève `resource-exhausted` au plafond.
 */
async function reserveLaunch(ctx: Ctx, day: string): Promise<void> {
  const { db, Timestamp } = ctx.kit;
  const qRef = quotaRef(ctx.kit, day, ctx.pool);
  const sRef = statusRef(ctx.kit);
  const limit = launchLimitOf(ctx.pool);
  await db.runTransaction(async (tx) => {
    const [quota, status] = await Promise.all([tx.get(qRef), tx.get(sRef)]);
    const count = readLaunchCount(quota.get("count"));
    if (!launchFitsQuota(count, limit)) {
      throw refusal("resource-exhausted", launchQuotaMessage(limit), "quota_exceeded", { limit });
    }
    tx.set(
      qRef,
      {
        day,
        count: count + 1,
        expires_at: Timestamp.fromMillis(ctx.now() + QUOTA_TTL_DAYS * 86_400_000),
      },
      { merge: true },
    );
    tx.set(sRef, nextLaunchStatus(status.data() ?? {}, day, count + 1, 1, ctx.pool), {
      merge: true,
    });
  });
}

/** Rend un lancement compté qui n'est pas parti. Au mieux, journalisé. */
async function releaseLaunch(ctx: Ctx, day: string): Promise<void> {
  const { db } = ctx.kit;
  const qRef = quotaRef(ctx.kit, day, ctx.pool);
  const sRef = statusRef(ctx.kit);
  try {
    await db.runTransaction(async (tx) => {
      const [quota, status] = await Promise.all([tx.get(qRef), tx.get(sRef)]);
      const count = readLaunchCount(quota.get("count"));
      const next = Math.max(0, count - 1);
      if (quota.exists) tx.update(qRef, { count: next });
      tx.set(sRef, nextLaunchStatus(status.data() ?? {}, day, next, -1, ctx.pool), {
        merge: true,
      });
    });
  } catch (err) {
    ctx.log("error", {
      ...base(ctx, `Tickets : lancement non parti resté compté pour le ${day}`),
      error: err,
    });
  }
}

/** Étape 5 : ajoute une entrée en tête de l'historique, vingt au plus. Lève sur une panne. */
async function recordLaunch(ctx: Ctx, entry: Record<string, unknown>): Promise<void> {
  const { db, FieldValue } = ctx.kit;
  const ref = launchesRef(ctx.kit, ctx.ticketId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const list = [entry, ...launchRawEntries(snap.data())].slice(0, LAUNCH_HISTORY_MAX);
    tx.set(ref, { entries: list, updated_at: FieldValue.serverTimestamp() });
  });
}

/** Met à jour l'entrée `id`. Au mieux : l'entrée reste `unknown`, comptée, et bloque. */
async function updateLaunch(ctx: Ctx, id: string, patch: Record<string, unknown>): Promise<void> {
  const { db, FieldValue } = ctx.kit;
  const ref = launchesRef(ctx.kit, ctx.ticketId);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const list = launchRawEntries(snap.data()).map((e) => (e.id === id ? { ...e, ...patch } : e));
      tx.set(ref, { entries: list, updated_at: FieldValue.serverTimestamp() });
    });
  } catch (err) {
    ctx.log("error", {
      ...base(ctx, `Tickets : résultat du lancement ${id} non enregistré (reste « inconnu »)`, {
        patch_state: typeof patch.state === "string" ? patch.state : null,
      }),
      error: err,
    });
  }
}

/**
 * Pose ou efface `{analysis|development}_invalid_since`. Un lancement réussi de la routine de
 * développement efface aussi `delivery_queue_halted` (file arrêtée par un refus de la
 * routine). Au mieux, journalisé.
 */
async function setRoutineInvalid(ctx: Ctx, invalid: boolean): Promise<void> {
  const field = ROUTINE_INVALID_FIELD[ctx.action];
  const { db, Timestamp } = ctx.kit;
  const ref = statusRef(ctx.kit);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const patch: Record<string, unknown> = {};
      const current = snap.get(field);
      const isSet = current instanceof Timestamp;
      if (invalid && !isSet) patch[field] = Timestamp.fromMillis(ctx.now());
      if (!invalid && current !== null && current !== undefined) patch[field] = null;
      const halted = snap.get("delivery_queue_halted");
      if (
        !invalid &&
        field === ROUTINE_INVALID_FIELD.livraison &&
        halted !== null &&
        halted !== undefined
      ) {
        patch.delivery_queue_halted = null;
      }
      if (Object.keys(patch).length > 0) tx.set(ref, patch, { merge: true });
    });
  } catch (err) {
    ctx.log("error", {
      ...base(
        ctx,
        invalid
          ? "Tickets : refus de la routine non enregistré"
          : "Tickets : alerte de la routine non effacée",
      ),
      error: err,
    });
  }
}

// ── Livraison (P43) ─────────────────────────────────────────────────────────

/**
 * Étape 2 bis : contrôles d'une livraison avant tout comptage, relus sur GitHub : une seule
 * PR éligible, liste de ses fichiers lue en entier, aucun fichier sensible, CI verte.
 * L'état relu est écrit dans `admin/delivery` (au mieux). Lève un refus
 * `failed-precondition` avec son code stable ; un échec GitHub suit `launchGithubFailure`.
 * `expectedHead` (départ de la file) : tête de la PR relue à l'accord ; une autre tête refuse
 * en `delivery_queue_head_changed`, avant la lecture des fichiers. Rend le numéro et la tête de
 * la PR.
 */
async function checkDeliveryLaunch(
  ctx: Ctx,
  issueNumber: number,
  deps: LaunchDeps,
  expectedHead?: string,
): Promise<{ prNumber: number; headSha: string | null }> {
  const token = deps.githubToken().trim();
  const markInvalid = deps.markTokenInvalid ?? markTokenInvalid;
  if (token.length === 0) {
    await markInvalid(null);
    const f = launchGithubFailure("token");
    throw refusal(f.code, f.reason, f.machine);
  }
  const client = githubClient(token, deps.fetchGithub);
  const github = async <T>(what: string, work: () => Promise<T>): Promise<T> => {
    try {
      return await work();
    } catch (err) {
      const kind = err instanceof GithubError ? err.kind : "other";
      ctx.log("error", {
        ...base(ctx, `Tickets : ${what} avant la livraison`, { kind }),
        error: err,
      });
      if (err instanceof GithubActionsForbidden) {
        // Jeton sans « Actions : lecture » : panne à part, sans `token_invalid_since` (P25).
        throw refusal(
          "failed-precondition",
          DELIVERY_ACTIONS_FORBIDDEN_MESSAGE,
          "github_actions_forbidden",
        );
      }
      if (kind === "token") await markInvalid(err as GithubError);
      const f = launchGithubFailure(kind);
      throw refusal(f.code, f.reason, f.machine);
    }
  };
  const reading = await github("pull requests non relues", () =>
    readDelivery(ctx.kit, client, issueNumber, LAUNCH_FROM_STATUS.livraison),
  );
  try {
    await writeDeliveryState(ctx.kit, ctx.ticketId, reading.state);
  } catch (err) {
    ctx.log("error", {
      ...base(ctx, "Tickets : état « PR prête » relu à la livraison, non écrit"),
      error: err,
    });
  }
  const refuse = (message: string, machine: string): never => {
    ctx.log(
      "info",
      base(ctx, `Tickets : livraison refusée (${machine})`, { pr: reading.state.pr_number }),
    );
    throw refusal("failed-precondition", message, machine);
  };
  const count = reading.state.eligible_pr_count;
  if (count > 1) refuse(deliveryMultiplePrMessage(count, issueNumber), "delivery_multiple_prs");
  const pr = reading.pr;
  if (pr === null) return refuse(DELIVERY_NO_PR_MESSAGE, "delivery_no_pr");
  if (expectedHead !== undefined && pr.headSha !== expectedHead) {
    refuse(QUEUE_HEAD_CHANGED_MESSAGE, QUEUE_EXIT_HEAD_CHANGED);
  }
  const files = await github("fichiers de la pull request non relus", () =>
    client.listPullRequestFiles(pr.number),
  );
  if (!files.complete) {
    refuse(deliveryFilesUnreadableMessage(pr.number), "delivery_files_unreadable");
  }
  const sensitive = sensitiveDeliveryPath(files.files);
  if (sensitive !== null) {
    refuse(deliverySensitiveMessage(pr.number, sensitive), "delivery_sensitive_files");
  }
  if (!reading.state.ready) refuse(deliveryCiNotGreenMessage(pr.number), "delivery_ci_not_green");
  return { prNumber: pr.number, headSha: pr.headSha };
}

// ── Lancement ───────────────────────────────────────────────────────────────

/** Étape 4 : Issue relue. Lève un refus si le ticket a changé ou si GitHub échoue. */
async function checkIssue(ctx: Ctx, issueNumber: number, deps: LaunchDeps): Promise<void> {
  const token = deps.githubToken().trim();
  const markInvalid = deps.markTokenInvalid ?? markTokenInvalid;
  if (token.length === 0) {
    await markInvalid(null);
    const f = launchGithubFailure("token");
    throw refusal(f.code, f.reason, f.machine);
  }
  const client = githubClient(token, deps.fetchGithub);
  let issue: IssueView;
  try {
    issue = await client.getIssue(issueNumber);
  } catch (err) {
    const kind = err instanceof GithubError ? err.kind : "other";
    ctx.log("error", {
      ...base(ctx, "Tickets : Issue non relue avant le lancement", { issue: issueNumber, kind }),
      error: err,
    });
    if (kind === "token") await markInvalid(err as GithubError);
    const f = launchGithubFailure(kind);
    throw refusal(f.code, f.reason, f.machine);
  }
  await (deps.recordTokenAccepted ?? recordTokenAccepted)(client);
  const remote = statusFromIssue(issue);
  const fromStatus = LAUNCH_FROM_STATUS[ctx.action];
  if (issue.state === "open" && remote === fromStatus) return;
  try {
    const snap = await ticketRef(ctx.kit, ctx.ticketId).get();
    if (snap.exists) await (deps.applyIssue ?? applyIssue)(client, snap, issue);
  } catch (err) {
    ctx.log("error", {
      ...base(ctx, "Tickets : état relu de l'Issue non appliqué au ticket"),
      error: err,
    });
  }
  ctx.log("warn", {
    ...base(ctx, `Tickets : lancement annulé, l'Issue #${issueNumber} dit ${remote}`, {
      issue_state: issue.state,
    }),
  });
  throw refusal("failed-precondition", LAUNCH_TICKET_CHANGED_MESSAGE, "ticket_changed");
}

/**
 * Lance la routine de `action` sur le ticket. Rend `launched` ou `unknown` ; lève une
 * `HttpsError` (motif dans `details.reason`, code stable dans `details.code`) pour tout
 * refus. `pool` : compteur du jour de l'appelant (`launchPoolOf`, d'après `requireAdmin`).
 */
export async function launchTicketSession(
  ticketId: string,
  action: LaunchAction,
  uid: string,
  deps: LaunchDeps,
  pool: LaunchPool = "group",
): Promise<LaunchResult> {
  const kit = await (deps.kit ?? firestore)();
  const ctx: Ctx = {
    kit,
    now: deps.nowMs ?? Date.now,
    log: deps.log ?? defaultLogger,
    ticketId,
    action,
    pool,
  };

  // 1. Routine configurée, sinon rien compté, rien envoyé.
  const secrets = deps.routine();
  const config = routineConfig(secrets.id, secrets.token);
  if (config === null) {
    ctx.log("error", base(ctx, "Tickets : lancement refusé, routine non configurée"));
    throw refusal("failed-precondition", LAUNCH_NOT_CONFIGURED_MESSAGE, "not_configured");
  }

  // 2. Précondition, « en cours », bail.
  const { issueNumber, leaseUntilMs } = await claimLaunch(ctx);

  let reservedDay: string | null = null;
  let keepCount = false;
  // Livraison : instant du lancement, fixé à la prise du verrou.
  let lockedAtMs: number | null = null;
  let previousLast: unknown = null;
  try {
    // 2 bis. Livraison : PR, fichiers et CI relus, puis verrou global (P43, P44) ; refus si la
    // file des livraisons n'est pas vide (point 5).
    if (action === "livraison") {
      await checkDeliveryLaunch(ctx, issueNumber, deps);
      const plannedAtMs = ctx.now();
      const claimed = await claimDeliveryLock(
        kit,
        ticketId,
        issueNumber,
        plannedAtMs,
        (message, other) =>
          refusal("failed-precondition", message, "delivery_running_elsewhere", {
            ticketId: other,
          }),
        (waiting) =>
          refusal("failed-precondition", DELIVERY_QUEUE_AHEAD_MESSAGE, "delivery_queue_ahead", {
            waiting,
          }),
      );
      previousLast = claimed.previousLast;
      lockedAtMs = plannedAtMs;
    }

    // 3. Plafond du jour.
    const day = parisDay(new Date(ctx.now()));
    await reserveLaunch(ctx, day);
    reservedDay = day;

    // 4. Issue relue sur GitHub.
    await checkIssue(ctx, issueNumber, deps);

    // 5. Trace écrite avant l'appel.
    const text = launchCommandText(action, issueNumber);
    const atMs = lockedAtMs ?? ctx.now();
    const id = randomUUID();
    const { Timestamp } = kit;
    try {
      await recordLaunch(ctx, {
        id,
        action,
        state: "unknown",
        at: Timestamp.fromMillis(atMs),
        by_uid: uid,
        retry_after: Timestamp.fromMillis(launchRetryAfterMs(action, atMs)),
      });
    } catch (err) {
      ctx.log("error", {
        ...base(ctx, "Tickets : historique non écrit, lancement abandonné"),
        error: err,
      });
      throw refusal("internal", LAUNCH_NOT_RECORDED_MESSAGE, "not_recorded");
    }

    // 6. Appel unique. À partir d'ici, une session a pu partir.
    const outcome: FireOutcome = await fireRoutine(config, text, {
      fetchImpl: deps.fetchRoutine,
      nowMs: ctx.now,
      // Journaux des `catch` de `routine.ts` : poste de coût et action, comme les autres.
      log: (entry) => ctx.log("error", base(ctx, entry.message, entry.extra)),
    });
    keepCount = true;
    return await settleLaunch(ctx, issueNumber, id, atMs, outcome, () => {
      keepCount = false;
    });
  } finally {
    if (reservedDay !== null && !keepCount) await releaseLaunch(ctx, reservedDay);
    if (lockedAtMs !== null && !keepCount) {
      await releaseDeliveryLock(kit, ticketId, lockedAtMs, previousLast);
    }
    await releaseLease(ctx, leaseUntilMs);
  }
}

/** Étape 7 : enregistre le résultat de l'appel et le traduit pour le client. */
async function settleLaunch(
  ctx: Ctx,
  issueNumber: number,
  id: string,
  atMs: number,
  outcome: FireOutcome,
  uncount: () => void,
): Promise<LaunchResult> {
  if (outcome.kind === "launched") {
    await updateLaunch(ctx, id, {
      state: "launched",
      ...(outcome.sessionUrl !== null ? { session_url: outcome.sessionUrl } : {}),
    });
    await setRoutineInvalid(ctx, false);
    if (outcome.note !== null) {
      ctx.log("warn", {
        ...base(ctx, `Tickets : session lancée pour l'Issue #${issueNumber}, réponse sans lien`, {
          note: outcome.note,
        }),
      });
    }
    ctx.log("info", base(ctx, `Tickets : session lancée pour l'Issue #${issueNumber}`));
    return outcome.sessionUrl !== null
      ? { outcome: "launched", sessionUrl: outcome.sessionUrl }
      : { outcome: "launched" };
  }

  if (outcome.kind === "unknown") {
    // Délai, réseau ou 5xx : la session a pu partir. L'entrée reste `unknown`, comptée,
    // et bloque un nouveau lancement jusqu'à `retry_after`.
    const serverError = outcome.status !== null;
    ctx.log("error", {
      ...base(
        ctx,
        serverError
          ? `Tickets : lancement en HTTP ${outcome.status}, résultat inconnu`
          : "Tickets : lancement sans réponse, résultat inconnu",
        { issue: issueNumber, status: outcome.status, detail: outcome.detail },
      ),
    });
    if (serverError) {
      await updateLaunch(ctx, id, { reason: ROUTINE_SERVER_ERROR_MESSAGE });
      return { outcome: "unknown", reason: ROUTINE_SERVER_ERROR_MESSAGE };
    }
    return { outcome: "unknown" };
  }

  const message = routineFailureMessage(outcome.failure, outcome.retryMinutes);
  uncount();
  ctx.log("error", {
    ...base(
      ctx,
      `Tickets : lancement refusé par l'API (HTTP ${outcome.status}, ${outcome.failure})`,
      {
        issue: issueNumber,
        status: outcome.status,
        failure: outcome.failure,
        detail: outcome.detail,
      },
    ),
  });
  await updateLaunch(ctx, id, {
    state: "failed",
    reason: message.slice(0, LAUNCH_REASON_MAX),
    // Un échec ne bloque rien : l'échéance est l'heure du lancement.
    retry_after: ctx.kit.Timestamp.fromMillis(atMs),
  });
  if (outcome.failure === "token" || outcome.failure === "not_found") {
    await setRoutineInvalid(ctx, true);
  }
  const { code, machine } = routineFailureCode(outcome.failure);
  throw refusal(code, message, machine);
}

// ── Callable ────────────────────────────────────────────────────────────────

/**
 * `mode` de `launchTicketDevelopment` (P47) : `start` (absent : `start`, anciens clients) ou
 * `resume`, comparés exactement ; jamais déduit du statut. Lève `invalid-argument`. Pure.
 */
export function readLaunchMode(data: unknown): "start" | "resume" {
  const raw = (data as Record<string, unknown> | null | undefined)?.mode;
  const value = requireBoundedText(raw, { field: "mode", max: 16, label: "Mode de lancement" });
  if (value === undefined || value === "start") return "start";
  if (value === "resume") return "resume";
  throw new HttpsError("invalid-argument", LAUNCH_MODE_INVALID, {
    field: "mode",
    reason: LAUNCH_MODE_INVALID,
  });
}

/**
 * `launchTicketDevelopment` : garde (P30), puis `mode` (P47) avant toute autre lecture ;
 * `resume` lance une reprise (`reprise #N`), sinon un développement (`developpement #N`).
 */
export async function handleDevelopmentCall(
  req: AuthLike & { data?: unknown },
  deps: LaunchDeps & { lookup?: MemberLookup },
): Promise<LaunchResult> {
  return handleLaunchCall(
    req,
    (data) => (readLaunchMode(data) === "resume" ? "reprise" : "developpement"),
    deps,
  );
}

/**
 * Corps commun des callables : garde (P30), action (`mode` lu après la garde pour le
 * développement), argument `ticketId`, lancement. Les refus attendus (`HttpsError`) passent
 * tels quels ; toute autre panne est journalisée et rendue en `internal` : le client ne sait
 * pas si la session est partie, et le dit.
 */
export async function handleLaunchCall(
  req: AuthLike & { data?: unknown },
  actionOf: LaunchAction | ((data: unknown) => LaunchAction),
  deps: LaunchDeps & { lookup?: MemberLookup },
): Promise<LaunchResult> {
  const { uid, founder } = await requireAdmin(req, deps.lookup);
  const action = typeof actionOf === "function" ? actionOf(req.data) : actionOf;
  const ticketId = readTicketIdArg(req.data);
  return guardedLaunch(ticketId, action, deps, () =>
    launchTicketSession(ticketId, action, uid, deps, launchPoolOf(founder)),
  );
}

/** Les refus attendus passent tels quels ; toute autre panne est journalisée, en `internal`. */
async function guardedLaunch<T>(
  ticketId: string,
  action: LaunchAction,
  deps: LaunchDeps,
  work: () => Promise<T>,
): Promise<T> {
  try {
    return await work();
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    (deps.log ?? defaultLogger)("error", {
      message: "Tickets : lancement en échec inattendu",
      feature: "tickets",
      ticketId,
      error: err,
      extra: { action, cost_center: LAUNCH_COST_CENTER },
    });
    throw refusal("internal", LAUNCH_INTERNAL_MESSAGE, "internal");
  }
}

// ── File des livraisons (amendement du 2026-11-22) ──────────────────────────

/** Mode de `launchTicketDelivery` : « Livrer », « Mettre en file », « Retirer de la file ». */
export type DeliveryMode = "start" | "queue" | "unqueue" | "resume_queue";

/**
 * `mode` de `launchTicketDelivery` (P43) : `start` (absent : `start`, anciens clients),
 * `queue`, `unqueue` ou `resume_queue` (« Relancer la file »), comparés exactement ; jamais déduit du verrou ni du statut. Lève
 * `invalid-argument`. Pure.
 */
export function readDeliveryMode(data: unknown): DeliveryMode {
  const raw = (data as Record<string, unknown> | null | undefined)?.mode;
  const value = requireBoundedText(raw, { field: "mode", max: 16, label: "Mode de livraison" });
  if (value === undefined || value === "start") return "start";
  if (value === "queue" || value === "unqueue" || value === "resume_queue") return value;
  throw new HttpsError("invalid-argument", DELIVERY_MODE_INVALID, {
    field: "mode",
    reason: DELIVERY_MODE_INVALID,
  });
}

/** Réponse de « Mettre en file » et de « Retirer de la file ». */
export type DeliveryQueueResult =
  | { outcome: "queued"; position: number; total: number }
  | { outcome: "unqueued"; changed: boolean }
  /** « Relancer la file » : `changed: false` si la file n'était pas arrêtée (rien écrit). */
  | { outcome: "queue_resumed"; changed: boolean };

/**
 * `launchTicketDelivery` : garde (P30), puis `mode` avant toute autre lecture, puis
 * `ticketId`. `start` : « Livrer » ; `queue` : « Mettre en file », e-mail de l'accord tiré du
 * jeton vérifié ; `unqueue` : « Retirer de la file » ; `resume_queue` : « Relancer la file ».
 */
export async function handleDeliveryCall(
  req: AuthLike & { data?: unknown },
  deps: LaunchDeps & { lookup?: MemberLookup },
): Promise<LaunchResult | DeliveryQueueResult> {
  const { uid, founder } = await requireAdmin(req, deps.lookup);
  const mode = readDeliveryMode(req.data);
  const ticketId = readTicketIdArg(req.data);
  return guardedLaunch(ticketId, "livraison", deps, async () => {
    if (mode === "start") {
      return launchTicketSession(ticketId, "livraison", uid, deps, launchPoolOf(founder));
    }
    if (mode === "unqueue") return unqueueTicketDelivery(ticketId, deps);
    if (mode === "resume_queue") return resumeTicketQueue(ticketId, deps);
    // `requireAdmin` a vérifié le jeton : sa clé de `members/` existe.
    const email = memberKeyOf(req.auth?.token) as string;
    return queueTicketDelivery(ticketId, uid, email, deps);
  });
}

/**
 * « Mettre en file » (point 4) : précondition et bail, contrôles de P43 dans l'ordre de
 * « Livrer », puis `enqueueDelivery` (file non pleine, ticket absent de la file, qui ne tient
 * pas le verrou ; refus `delivery_lock_free` quand « Livrer » suffit). Rien n'est compté.
 */
export async function queueTicketDelivery(
  ticketId: string,
  uid: string,
  email: string,
  deps: LaunchDeps,
): Promise<DeliveryQueueResult> {
  const kit = await (deps.kit ?? firestore)();
  const ctx: Ctx = {
    kit,
    now: deps.nowMs ?? Date.now,
    log: deps.log ?? defaultLogger,
    ticketId,
    action: "livraison",
    pool: "group",
  };
  const { issueNumber, leaseUntilMs } = await claimLaunch(ctx);
  try {
    const pr = await checkDeliveryLaunch(ctx, issueNumber, deps);
    if (pr.headSha === null) {
      // Une CI verte exige une tête lue : ce cas ne passe pas `ready`.
      throw refusal(
        "failed-precondition",
        deliveryCiNotGreenMessage(pr.prNumber),
        "delivery_ci_not_green",
      );
    }
    const placed = await enqueueDelivery(
      kit,
      {
        ticketId,
        issueNumber,
        prNumber: pr.prNumber,
        headSha: pr.headSha,
        byUid: uid,
        byEmail: email,
      },
      ctx.now(),
      (kind) => {
        const r = DELIVERY_QUEUE_REFUSALS[kind];
        return refusal("failed-precondition", r.reason, r.machine);
      },
    );
    ctx.log(
      "info",
      base(ctx, `Tickets : livraison mise en file (${placed.position} sur ${placed.total})`, {
        pr: pr.prNumber,
      }),
    );
    return { outcome: "queued", ...placed };
  } finally {
    await releaseLease(ctx, leaseUntilMs);
  }
}

/**
 * « Relancer la file » (décisions 9 et 10) : efface `delivery_queue_halted` et
 * `development_invalid_since` quand `ticketId` est en tête ; aucun lancement, aucun décompte,
 * aucun appel à GitHub ni à la routine. Refus `delivery_queue_not_head` si le ticket n'est pas
 * en tête ; `changed: false` sans écriture si aucun des deux champs n'est posé.
 */
export async function resumeTicketQueue(
  ticketId: string,
  deps: LaunchDeps,
): Promise<DeliveryQueueResult> {
  const kit = await (deps.kit ?? firestore)();
  const outcome = await resumeHaltedQueue(kit, ticketId);
  if (outcome === "not_head") {
    throw refusal("failed-precondition", QUEUE_RESUME_NOT_HEAD_MESSAGE, "delivery_queue_not_head");
  }
  if (outcome === "cleared") {
    (deps.log ?? defaultLogger)("info", {
      message: "Tickets : file des livraisons relancée",
      feature: "tickets",
      ticketId,
      extra: { action: "livraison", cost_center: LAUNCH_COST_CENTER },
    });
  }
  return { outcome: "queue_resumed", changed: outcome === "cleared" };
}

/** « Retirer de la file » (point 6) : aucun appel à GitHub ni à la routine. */
export async function unqueueTicketDelivery(
  ticketId: string,
  deps: LaunchDeps,
): Promise<DeliveryQueueResult> {
  const kit = await (deps.kit ?? firestore)();
  const changed = await unqueueDelivery(kit, ticketId, (deps.nowMs ?? Date.now)());
  if (changed) {
    (deps.log ?? defaultLogger)("info", {
      message: "Tickets : livraison retirée de la file",
      feature: "tickets",
      ticketId,
      extra: { action: "livraison", cost_center: LAUNCH_COST_CENTER },
    });
  }
  return { outcome: "unqueued", changed };
}

/** Ce que fait une exécution de `startQueuedDelivery`. */
export type QueuedDeliveryOutcome =
  | { kind: "idle"; reason: DeliveryQueueStop }
  /** Panne passagère, plafond atteint, routine non configurée : entrée gardée. */
  | { kind: "kept"; ticketId: string; reason: string }
  /** Refus propre au ticket : entrée retirée, `queue_exit` noté, rien compté. */
  | { kind: "exited"; ticketId: string; code: string }
  /** Exécution superposée ou « Livrer » passé entre-temps : rien compté. */
  | { kind: "raced"; ticketId: string }
  | { kind: "launched" | "unknown"; ticketId: string };

/** Codes de refus qui font sortir la tête de file ; tout autre refus la garde (point 8). */
export const QUEUE_EXIT_CODES: Record<string, string> = {
  not_launchable: "not_allowed",
  ticket_not_found: "not_allowed",
  ticket_changed: "not_allowed",
  issue_not_found: "issue_not_found",
  reprise_running: "reprise_running",
  delivery_no_pr: "delivery_no_pr",
  delivery_multiple_prs: "delivery_multiple_prs",
  delivery_files_unreadable: "delivery_files_unreadable",
  delivery_sensitive_files: "delivery_sensitive_files",
  delivery_ci_not_green: "delivery_ci_not_green",
  [QUEUE_EXIT_HEAD_CHANGED]: QUEUE_EXIT_HEAD_CHANGED,
};

/**
 * Refus de la routine au départ qui arrêtent la file (`delivery_queue_halted`), entrée remise
 * en tête : routine en pause ou appel refusé (décision de l'utilisateur du 2026-11-22). Le
 * jeton refusé arrête la file par `development_invalid_since`.
 */
export const QUEUE_HALT_CODES: readonly string[] = ["routine_paused", "routine_failed"];

/** Code d'une erreur pour un journal : `code` ou nom seuls, jamais le message. Pure. */
function errorCodeOf(err: unknown): string {
  if (err !== null && typeof err === "object") {
    const code = (err as { code?: unknown }).code;
    if (typeof code === "string" || typeof code === "number") return String(code).slice(0, 60);
    const name = (err as { name?: unknown }).name;
    if (typeof name === "string") return name.slice(0, 60);
  }
  return "inconnu";
}

/** Code stable d'un refus, ou `null` pour une panne qui n'est pas une `HttpsError`. Pure. */
function refusalCode(err: unknown): string | null {
  if (!(err instanceof HttpsError)) return null;
  const code = (err.details as Record<string, unknown> | undefined)?.code;
  return typeof code === "string" ? code : null;
}

/**
 * Départ de la tête de file (`startQueuedDelivery`, point 8). Première lecture :
 * `ticket_status/launches` seul ; arrêt sans autre lecture si la file est vide, si le verrou
 * tient, si la livraison précédente n'a pas rendu son compte rendu, ou si le jeton de la
 * routine de développement est refusé ou si la file est arrêtée (`delivery_queue_halted`). Puis,
 * avant tout appel à GitHub : `ticket_status/github.token_invalid_since` (arrêt si posé),
 * `members/{by_email}` relu (administrateur, compteur), plafond du jour de ce compteur lu sans
 * décompte (arrêt s'il est atteint). Puis une tentative sur la tête : bail de 330 s, contrôles de P43, tête de la PR égale à
 * l'accord, Issue relue ; puis une transaction relit la tête, le verrou, la condition de fin
 * et le plafond, retire l'entrée, prend le verrou et compte ensemble ; entrée d'historique
 * `unknown` (`queued: true`, `by_uid` de l'accord), appel unique de la routine.
 */
export async function runQueuedDelivery(
  deps: LaunchDeps & { lookup?: MemberLookup },
): Promise<QueuedDeliveryOutcome> {
  const kit = await (deps.kit ?? firestore)();
  const now = deps.nowMs ?? Date.now;
  const log = deps.log ?? defaultLogger;
  const millis = (v: unknown) => (v instanceof kit.Timestamp ? v.toMillis() : null);

  const statusSnap = await statusRef(kit).get();
  const first = deliveryQueueDeparture(statusSnap.data() ?? {}, now(), millis);
  if ("stop" in first) return { kind: "idle", reason: first.stop };
  const head = first.head;
  const rawHead = readDeliveryQueue(statusSnap.get("delivery_queue"), millis).raw[0];
  const ticketId = head.ticketId;
  const entry = (message: string, extra: LogEntry["extra"] = {}): LogEntry => ({
    message,
    feature: "tickets",
    ticketId,
    extra: { action: "livraison", cost_center: LAUNCH_COST_CENTER, queued: true, ...extra },
  });
  const exit = async (code: string): Promise<QueuedDeliveryOutcome> => {
    try {
      await dequeueHead(kit, head, code, now());
    } catch (err) {
      log("error", { ...entry(`Tickets : sortie de file (${code}) non écrite`), error: err });
      return { kind: "kept", ticketId, reason: "firestore" };
    }
    log("info", entry(`Tickets : livraison sortie de la file (${code})`));
    return { kind: "exited", ticketId, code };
  };
  const fate = (err: unknown, step: string): Promise<QueuedDeliveryOutcome> => {
    const code = refusalCode(err);
    const exitCode = code === null ? undefined : QUEUE_EXIT_CODES[code];
    if (exitCode !== undefined) return exit(exitCode);
    // Panne passagère (GitHub, Firestore, jeton refusé, bail tenu) : entrée gardée.
    log(code === null ? "error" : "warn", {
      ...entry(`Tickets : départ de la file reporté (${step})`, { code }),
      ...(code === null ? { error: err } : {}),
    });
    return Promise.resolve({ kind: "kept", ticketId, reason: code ?? "internal" });
  };

  const secrets = deps.routine();
  const config = routineConfig(secrets.id, secrets.token);
  if (config === null) {
    log("error", entry("Tickets : départ de la file reporté, routine non configurée"));
    return { kind: "kept", ticketId, reason: "not_configured" };
  }
  // Jeton GitHub refusé : aucune tentative tant qu'il n'est pas remplacé.
  try {
    const github = await kit.db.collection(COLL_TICKET_STATUS).doc(TICKET_STATUS_GITHUB_DOC).get();
    const invalid = github.get("token_invalid_since");
    if (invalid !== null && invalid !== undefined) {
      return { kind: "kept", ticketId, reason: "github_token" };
    }
  } catch (err) {
    return fate(err, "ticket_status/github non relu");
  }
  if (
    head.byEmail === null ||
    head.byUid === null ||
    head.queuedAtMs === null ||
    head.headSha === null
  ) {
    return exit("not_allowed");
  }

  // Compte de l'accord relu : toujours administrateur, compteur du fondateur ou du groupe.
  let member: Record<string, unknown> | null;
  try {
    member = await (deps.lookup ?? firestoreMemberLookup)(head.byEmail);
  } catch (err) {
    // Code d'erreur seul : ni l'objet erreur ni l'e-mail de l'accord dans le journal.
    log(
      "error",
      entry("Tickets : départ de la file reporté, members/ non relu", {
        code: errorCodeOf(err),
      }),
    );
    return { kind: "kept", ticketId, reason: "members_unreadable" };
  }
  if (member === null || member.role !== "admin") return exit(QUEUE_EXIT_NOT_ADMIN);
  const pool = launchPoolOf(member.founder === true);
  // Plafond du compteur de l'accord, lu sans décompte avant tout appel à GitHub ; la
  // transaction du départ le relit.
  try {
    const quota = await quotaRef(kit, parisDay(new Date(now())), pool).get();
    if (!launchFitsQuota(readLaunchCount(quota.get("count")), launchLimitOf(pool))) {
      return { kind: "kept", ticketId, reason: "quota_exceeded" };
    }
  } catch (err) {
    return fate(err, "plafond non relu");
  }
  const ctx: Ctx = {
    kit,
    now,
    log,
    ticketId,
    action: "livraison",
    pool,
    leaseMs: QUEUED_DELIVERY_LEASE_MS,
  };

  let claimed: { issueNumber: number; leaseUntilMs: number };
  try {
    claimed = await claimLaunch(ctx);
  } catch (err) {
    return fate(err, "bail");
  }
  try {
    try {
      await checkDeliveryLaunch(ctx, claimed.issueNumber, deps, head.headSha);
      await checkIssue(ctx, claimed.issueNumber, deps);
    } catch (err) {
      return await fate(err, "contrôles");
    }
    return await departFromQueue(ctx, head, rawHead, claimed.issueNumber, config, deps);
  } finally {
    await releaseLease(ctx, claimed.leaseUntilMs);
  }
}

/** Fin du départ : transaction anti-doublon, trace, appel unique, résultat. */
async function departFromQueue(
  ctx: Ctx,
  head: DeliveryQueueEntryView,
  rawHead: Record<string, unknown>,
  issueNumber: number,
  config: { id: string; token: string },
  deps: LaunchDeps,
): Promise<QueuedDeliveryOutcome> {
  const { kit } = ctx;
  const ticketId = ctx.ticketId;
  const atMs = ctx.now();
  const day = parisDay(new Date(atMs));
  const millis = (v: unknown) => (v instanceof kit.Timestamp ? v.toMillis() : null);
  const qRef = quotaRef(kit, day, ctx.pool);
  const sRef = statusRef(kit);
  const limit = launchLimitOf(ctx.pool);
  let taken: { kind: "taken"; previousLast: unknown } | { kind: "raced" } | { kind: "quota" };
  try {
    taken = await kit.db.runTransaction(async (tx) => {
      const [quota, status] = await Promise.all([tx.get(qRef), tx.get(sRef)]);
      const data = status.data() ?? {};
      const check = deliveryQueueDeparture(data, atMs, millis);
      if ("stop" in check || !sameQueueEntry(check.head, head)) return { kind: "raced" as const };
      const count = readLaunchCount(quota.get("count"));
      if (!launchFitsQuota(count, limit)) return { kind: "quota" as const };
      const rest = readDeliveryQueue(data.delivery_queue, millis).raw.slice(1);
      tx.set(
        qRef,
        {
          day,
          count: count + 1,
          expires_at: kit.Timestamp.fromMillis(atMs + QUOTA_TTL_DAYS * 86_400_000),
        },
        { merge: true },
      );
      tx.set(
        sRef,
        {
          ...nextLaunchStatus(data, day, count + 1, 1, ctx.pool),
          ...deliveryLockFields(kit, ticketId, issueNumber, atMs),
          delivery_queue: rest,
        },
        { merge: true },
      );
      return { kind: "taken" as const, previousLast: data.delivery_last ?? null };
    });
  } catch (err) {
    ctx.log("error", { ...base(ctx, "Tickets : départ de la file non pris"), error: err });
    return { kind: "kept", ticketId, reason: "firestore" };
  }
  if (taken.kind === "raced") {
    ctx.log("info", base(ctx, "Tickets : départ de la file laissé à un autre appel"));
    return { kind: "raced", ticketId };
  }
  if (taken.kind === "quota") {
    ctx.log(
      "info",
      base(ctx, `Tickets : départ de la file en attente, plafond de ${limit} atteint`),
    );
    return { kind: "kept", ticketId, reason: "quota_exceeded" };
  }

  let keepCount = false;
  let restore: QueueRestore | null = null;
  try {
    const id = randomUUID();
    try {
      await recordLaunch(ctx, {
        id,
        action: "livraison",
        state: "unknown",
        at: kit.Timestamp.fromMillis(atMs),
        by_uid: head.byUid,
        queued: true,
        retry_after: kit.Timestamp.fromMillis(launchRetryAfterMs("livraison", atMs)),
      });
    } catch (err) {
      ctx.log("error", {
        ...base(ctx, "Tickets : historique non écrit, départ de la file abandonné"),
        error: err,
      });
      restore = { rawEntry: rawHead, halt: null };
      return { kind: "kept", ticketId, reason: "not_recorded" };
    }
    const outcome: FireOutcome = await fireRoutine(
      config,
      launchCommandText("livraison", issueNumber),
      {
        fetchImpl: deps.fetchRoutine,
        nowMs: ctx.now,
        log: (e) => ctx.log("error", base(ctx, e.message, e.extra)),
      },
    );
    keepCount = true;
    // Seul un refus de l'API (`failed`) dit que rien n'est parti.
    const refused = outcome.kind === "failed";
    try {
      const result = await settleLaunch(ctx, issueNumber, id, atMs, outcome, () => {
        keepCount = false;
      });
      return { kind: result.outcome, ticketId };
    } catch (err) {
      if (!refused) {
        // Une session a pu partir : compteur et verrou gardés, entrée non remise.
        keepCount = true;
        ctx.log("error", {
          ...base(ctx, "Tickets : résultat du départ de la file non enregistré"),
          error: err,
        });
        return { kind: "unknown", ticketId };
      }
      // Refus de l'API : rien n'est parti, entrée remise en tête. Jeton refusé :
      // `development_invalid_since` arrête la file ; routine en pause ou appel refusé :
      // `delivery_queue_halted` l'arrête ; limite de débit : nouvel essai à l'exécution suivante.
      const code = refusalCode(err) ?? "internal";
      restore = {
        rawEntry: rawHead,
        halt: QUEUE_HALT_CODES.includes(code) ? { code, atMs: ctx.now() } : null,
      };
      return { kind: "kept", ticketId, reason: code };
    }
  } finally {
    if (!keepCount) {
      await releaseLaunch(ctx, day);
      await releaseDeliveryLock(kit, ticketId, atMs, taken.previousLast, restore);
    }
  }
}

// ── Après « Répondre », passe horaire ───────────────────────────────────────

/**
 * Après « Répondre » (ticket ramené à `received`) : les lancements en cours du ticket ne
 * bloquent plus (`closeRunningEntries`), comme dans Kass'Dalle, où un lancement antérieur au
 * dernier changement de statut ne compte pas. Au mieux, journalisé.
 */
export async function closeRunningLaunches(
  ticketId: string,
  kitOf: () => Promise<FirestoreKit> = firestore,
  nowMs: () => number = Date.now,
): Promise<void> {
  try {
    const kit = await kitOf();
    const ref = launchesRef(kit, ticketId);
    await kit.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const entries = launchRawEntries(snap.data());
      const next = closeRunningEntries(entries, launchEntryViews(kit, entries), nowMs(), (ms) =>
        kit.Timestamp.fromMillis(ms),
      );
      if (next === null) return;
      tx.set(ref, { entries: next, updated_at: kit.FieldValue.serverTimestamp() });
    });
  } catch (err) {
    logError({
      message: "Tickets : lancements en cours non clos après la réponse",
      feature: "tickets",
      ticketId,
      error: err,
    });
  }
}

/**
 * Passe horaire : `ticket_status/launches` remis au jour de Paris (`day`, `count_day` et
 * `founder_count_day` lus dans les deux compteurs du jour, `month`, `per_day`,
 * `founder_per_day`), pour que l'admin lise le plafond du jour avant le premier lancement.
 * Au mieux, journalisé.
 */
export async function refreshLaunchStatus(
  kitOf: () => Promise<FirestoreKit> = firestore,
  nowMs: () => number = Date.now,
): Promise<void> {
  try {
    const kit = await kitOf();
    const day = parisDay(new Date(nowMs()));
    const qRef = quotaRef(kit, day);
    const fRef = quotaRef(kit, day, "founder");
    const sRef = statusRef(kit);
    await kit.db.runTransaction(async (tx) => {
      const [quota, founderQuota, status] = await Promise.all([
        tx.get(qRef),
        tx.get(fRef),
        tx.get(sRef),
      ]);
      const next = refreshedLaunchStatus(
        status.data() ?? {},
        day,
        readLaunchCount(quota.get("count")),
        readLaunchCount(founderQuota.get("count")),
      );
      if (next !== null) tx.set(sRef, next, { merge: true });
    });
  } catch (err) {
    logError({
      message: "Tickets : compteurs des lancements non remis au jour",
      feature: "tickets",
      error: err,
    });
  }
}
