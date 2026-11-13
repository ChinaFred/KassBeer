/**
 * Lancement d'une session Claude Code sur un ticket, par une Routine (ADR-008, T4, P35, P36,
 * P41) : « Lancer l'analyse » (ticket Reçu) et « Lancer le développement » (ticket Validé),
 * appelés par `launchTicketAnalysis` et `launchTicketDevelopment` après `requireAdmin`.
 * Copie de `functions/src/tickets/launch.ts` de Kass'Dalle, adaptée : bail des décisions de
 * Kass'Beer (`decision_lease_until`), plafond `LAUNCHES_PER_DAY` de `config.ts`, pas de
 * compte fondateur, pas de type Question, règle « en cours » réduite à `retry_after`.
 *
 * Dans l'ordre :
 *  1. secrets de la routine présents et identifiant bien formé, sinon « Lancement non
 *     configuré » : rien compté, rien envoyé ;
 *  2. transaction sur le ticket : existant, `launchPrecondition` (statut, Issue, règle des
 *     décisions permises recalculée), aucun bail actif, aucun lancement du même type en
 *     cours (`runningLaunch`, historique lu dans la transaction) ; bail posé ;
 *  3. plafond du jour (P36) : transaction sur `ticket_quotas/launch_{AAAAMMJJ}` et
 *     `ticket_status/launches` ; refus au plafond ;
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
 * Rien n'est écrit dans `tickets/{id}`, que l'auteur lit : ni lien de session, ni uid de
 * l'administrateur. Le jeton n'est jamais journalisé (P35).
 */

import { randomUUID } from "node:crypto";

import type { DocumentSnapshot } from "firebase-admin/firestore";
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

import { requireAdmin, type AuthLike, type MemberLookup } from "../auth";
import {
  COLL_TICKET_QUOTAS,
  COLL_TICKET_STATUS,
  COLL_TICKETS,
  LAUNCH_COST_CENTER,
  LAUNCHES_PER_DAY,
  QUOTA_TTL_DAYS,
  TICKET_ADMIN_SUBCOLLECTION,
  TICKET_LAUNCHES_DOC,
  TICKET_STATUS_LAUNCHES_DOC,
} from "../config";
import { firestore, type FirestoreKit } from "../firestore";
import { logError, logInfo, logWarn, type LogEntry } from "../logging";
import { readTicketIdArg } from "./answer";
import { GithubError, githubClient, type FetchLike, type GithubClient } from "./github";
import { applyIssue } from "./issueState";
import {
  LAUNCH_FROM_STATUS,
  LAUNCH_HISTORY_MAX,
  LAUNCH_REASON_MAX,
  ROUTINE_INVALID_FIELD,
  closeRunningEntries,
  launchCommandText,
  launchFitsQuota,
  launchPrecondition,
  launchQuotaDocId,
  launchQuotaMessage,
  launchRetryAfterMs,
  launchRunningMessage,
  nextLaunchStatus,
  readLaunchCount,
  refreshedLaunchStatus,
  runningLaunch,
  type LaunchAction,
  type LaunchEntryView,
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
}

function base(ctx: Ctx, message: string, extra: LogEntry["extra"] = {}): LogEntry {
  return {
    message,
    feature: "tickets",
    ticketId: ctx.ticketId,
    extra: { action: ctx.action, cost_center: LAUNCH_COST_CENTER, ...extra },
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

function quotaRef(kit: FirestoreKit, day: string) {
  return kit.db.collection(COLL_TICKET_QUOTAS).doc(launchQuotaDocId(day));
}

/** Les entrées brutes de l'historique (objets seuls). */
function rawEntries(data: Record<string, unknown> | undefined): Record<string, unknown>[] {
  const list = data?.entries;
  if (!Array.isArray(list)) return [];
  return list.filter(
    (e): e is Record<string, unknown> => e !== null && typeof e === "object" && !Array.isArray(e),
  );
}

/** Les entrées lues sans supposer leur forme. */
export function launchEntryViews(
  kit: Pick<FirestoreKit, "Timestamp">,
  entries: readonly Record<string, unknown>[],
): LaunchEntryView[] {
  const ms = (v: unknown) => (v instanceof kit.Timestamp ? v.toMillis() : null);
  return entries.map((e) => ({
    id: e.id,
    action: e.action,
    state: e.state,
    at_ms: ms(e.at),
    retry_after_ms: ms(e.retry_after),
  }));
}

/** Étape 2 : précondition, « en cours » et bail, en une transaction. Rend le numéro d'Issue. */
async function claimLaunch(ctx: Ctx): Promise<{ issueNumber: number; leaseUntilMs: number }> {
  const { db, Timestamp } = ctx.kit;
  const ref = ticketRef(ctx.kit, ctx.ticketId);
  const historyRef = launchesRef(ctx.kit, ctx.ticketId);
  return db.runTransaction(async (tx) => {
    const [snap, history] = await Promise.all([tx.get(ref), tx.get(historyRef)]);
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
      launchEntryViews(ctx.kit, rawEntries(history.data())),
      ctx.action,
      nowMs,
    );
    if (running !== null) {
      throw refusal(
        "failed-precondition",
        launchRunningMessage(ctx.action, running.atMs, running.retryAfterMs),
        "running",
      );
    }
    const leaseUntilMs = nowMs + LAUNCH_LEASE_MS;
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
 * et `ticket_status/launches`. Lève `resource-exhausted` au plafond.
 */
async function reserveLaunch(ctx: Ctx, day: string): Promise<void> {
  const { db, Timestamp } = ctx.kit;
  const qRef = quotaRef(ctx.kit, day);
  const sRef = statusRef(ctx.kit);
  await db.runTransaction(async (tx) => {
    const [quota, status] = await Promise.all([tx.get(qRef), tx.get(sRef)]);
    const count = readLaunchCount(quota.get("count"));
    if (!launchFitsQuota(count, LAUNCHES_PER_DAY)) {
      throw refusal("resource-exhausted", launchQuotaMessage(LAUNCHES_PER_DAY), "quota_exceeded", {
        limit: LAUNCHES_PER_DAY,
      });
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
    tx.set(sRef, nextLaunchStatus(status.data() ?? {}, day, count + 1, 1), { merge: true });
  });
}

/** Rend un lancement compté qui n'est pas parti. Au mieux, journalisé. */
async function releaseLaunch(ctx: Ctx, day: string): Promise<void> {
  const { db } = ctx.kit;
  const qRef = quotaRef(ctx.kit, day);
  const sRef = statusRef(ctx.kit);
  try {
    await db.runTransaction(async (tx) => {
      const [quota, status] = await Promise.all([tx.get(qRef), tx.get(sRef)]);
      const count = readLaunchCount(quota.get("count"));
      const next = Math.max(0, count - 1);
      if (quota.exists) tx.update(qRef, { count: next });
      tx.set(sRef, nextLaunchStatus(status.data() ?? {}, day, next, -1), { merge: true });
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
    const list = [entry, ...rawEntries(snap.data())].slice(0, LAUNCH_HISTORY_MAX);
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
      const list = rawEntries(snap.data()).map((e) => (e.id === id ? { ...e, ...patch } : e));
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

/** Pose ou efface `{analysis|development}_invalid_since`. Au mieux, journalisé. */
async function setRoutineInvalid(ctx: Ctx, invalid: boolean): Promise<void> {
  const field = ROUTINE_INVALID_FIELD[ctx.action];
  const { db, Timestamp } = ctx.kit;
  const ref = statusRef(ctx.kit);
  try {
    await db.runTransaction(async (tx) => {
      const current = (await tx.get(ref)).get(field);
      const isSet = current instanceof Timestamp;
      if (invalid === isSet) return;
      if (!invalid && (current === null || current === undefined)) return;
      tx.set(ref, { [field]: invalid ? Timestamp.fromMillis(ctx.now()) : null }, { merge: true });
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
 * refus.
 */
export async function launchTicketSession(
  ticketId: string,
  action: LaunchAction,
  uid: string,
  deps: LaunchDeps,
): Promise<LaunchResult> {
  const kit = await (deps.kit ?? firestore)();
  const ctx: Ctx = {
    kit,
    now: deps.nowMs ?? Date.now,
    log: deps.log ?? defaultLogger,
    ticketId,
    action,
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
  try {
    // 3. Plafond du jour.
    const day = parisDay(new Date(ctx.now()));
    await reserveLaunch(ctx, day);
    reservedDay = day;

    // 4. Issue relue sur GitHub.
    await checkIssue(ctx, issueNumber, deps);

    // 5. Trace écrite avant l'appel.
    const text = launchCommandText(action, issueNumber);
    const atMs = ctx.now();
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
 * Corps commun des deux callables : garde (P30), argument `ticketId`, lancement. Les refus
 * attendus (`HttpsError`) passent tels quels ; toute autre panne est journalisée et rendue
 * en `internal` : le client ne sait pas si la session est partie, et le dit.
 */
export async function handleLaunchCall(
  req: AuthLike & { data?: unknown },
  action: LaunchAction,
  deps: LaunchDeps & { lookup?: MemberLookup },
): Promise<LaunchResult> {
  const { uid } = await requireAdmin(req, deps.lookup);
  const ticketId = readTicketIdArg(req.data);
  try {
    return await launchTicketSession(ticketId, action, uid, deps);
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
      const entries = rawEntries(snap.data());
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
 * Passe horaire : `ticket_status/launches` remis au jour de Paris (`day`, `count_day` lu
 * dans le compteur du jour, `month`, `per_day`), pour que l'admin lise le plafond du jour
 * avant le premier lancement. Au mieux, journalisé.
 */
export async function refreshLaunchStatus(
  kitOf: () => Promise<FirestoreKit> = firestore,
  nowMs: () => number = Date.now,
): Promise<void> {
  try {
    const kit = await kitOf();
    const day = parisDay(new Date(nowMs()));
    const qRef = quotaRef(kit, day);
    const sRef = statusRef(kit);
    await kit.db.runTransaction(async (tx) => {
      const [quota, status] = await Promise.all([tx.get(qRef), tx.get(sRef)]);
      const next = refreshedLaunchStatus(
        status.data() ?? {},
        day,
        readLaunchCount(quota.get("count")),
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
