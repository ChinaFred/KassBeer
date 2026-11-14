/**
 * Règles pures des lancements de sessions Claude Code (ADR-008, T4 et T5, P35, P36, P41, P43,
 * P47), reprises
 * de `functions/src/tickets/rules.ts` de Kass'Dalle (« Lancements de sessions »). Aucune
 * lecture ni écriture ici : `launch.ts` lit et écrit.
 */

import { LAUNCHES_PER_DAY } from "../config";
import {
  LAUNCH_ANALYSIS_ACTION,
  LAUNCH_DELIVERY_ACTION,
  LAUNCH_DEVELOPMENT_ACTION,
  RELAUNCH_DEVELOPMENT_ACTION,
  allowedDecisions,
  isValidatedByApp,
  type AllowedDecision,
} from "./decisionModel";
import type { TicketStatus } from "./model";

// ── Actions et texte envoyé ─────────────────────────────────────────────────

/**
 * Les lancements : `analyse` (ticket Reçu) et `developpement` (ticket Validé), de T4 ;
 * `livraison` (« Livrer ») et `reprise` (« Relancer le développement »), ticket En cours, de
 * T5. La valeur est aussi le premier mot du texte envoyé à la routine.
 */
export const LAUNCH_ACTIONS = ["analyse", "developpement", "livraison", "reprise"] as const;
export type LaunchAction = (typeof LAUNCH_ACTIONS)[number];

/** Seule forme de texte envoyée à une routine (P35). */
export const LAUNCH_TEXT_PATTERN = /^(analyse|developpement|livraison|reprise) #[1-9][0-9]{0,6}$/;

/**
 * Routine qui reçoit chaque action : la livraison et la reprise partent par la routine de
 * développement (ADR-008, « Livraison » ; P25, P35). Aucune routine de livraison à part.
 */
export const LAUNCH_ROUTINE: Record<LaunchAction, "analyse" | "developpement"> = {
  analyse: "analyse",
  developpement: "developpement",
  livraison: "developpement",
  reprise: "developpement",
};

/**
 * Le texte envoyé à la routine : `<action> #N`, `N` tiré de
 * `github_issue_number` écrit par le serveur. Lève si le résultat ne suit pas
 * [LAUNCH_TEXT_PATTERN] : rien d'autre ne part. Pure.
 */
export function launchCommandText(action: LaunchAction, issueNumber: number): string {
  const text = `${action} #${issueNumber}`;
  if (!LAUNCH_TEXT_PATTERN.test(text)) {
    throw new Error(`texte de lancement refusé : ${JSON.stringify(text)}`);
  }
  return text;
}

/** Le statut que le ticket doit avoir pour lancer, et garder pendant le lancement. */
export const LAUNCH_FROM_STATUS: Record<LaunchAction, TicketStatus> = {
  analyse: "received",
  developpement: "validated",
  livraison: "in_progress",
  reprise: "in_progress",
};

/** L'entrée de `allowed_decisions` qui offre le lancement au client. */
export const LAUNCH_DECISION: Record<LaunchAction, AllowedDecision> = {
  analyse: LAUNCH_ANALYSIS_ACTION,
  developpement: LAUNCH_DEVELOPMENT_ACTION,
  livraison: LAUNCH_DELIVERY_ACTION,
  reprise: RELAUNCH_DEVELOPMENT_ACTION,
};

/**
 * Délai après lequel un lancement peut être relancé (`retry_after`) : 1 h pour une analyse,
 * 3 h pour un développement, une reprise ou une livraison (P36). C'est aussi l'échéance du
 * verrou des livraisons (P44).
 */
export const LAUNCH_RETRY_MS: Record<LaunchAction, number> = {
  analyse: 60 * 60 * 1000,
  developpement: 3 * 60 * 60 * 1000,
  livraison: 3 * 60 * 60 * 1000,
  reprise: 3 * 60 * 60 * 1000,
};

/**
 * Les entrées en cours qui bloquent chaque lancement du même ticket. Analyse et premier
 * développement : la même action seule (T4, inchangé). Livraison : une livraison ou une
 * reprise (`reprise_running`, décision 12 du 2026-11-14). Reprise : un développement, une
 * reprise ou une livraison (P47, décision 10).
 */
export const LAUNCH_BLOCKED_BY: Record<LaunchAction, readonly LaunchAction[]> = {
  analyse: ["analyse"],
  developpement: ["developpement"],
  livraison: ["livraison", "reprise"],
  reprise: ["developpement", "reprise", "livraison"],
};

/** Entrées gardées dans `tickets/{id}/admin/launches`, plus récente en tête (P41). */
export const LAUNCH_HISTORY_MAX = 20;

/** Longueur gardée d'une raison d'échec dans l'historique (P41). */
export const LAUNCH_REASON_MAX = 300;

/** Échéance d'un lancement : l'instant à partir duquel il peut être relancé. Pure. */
export function launchRetryAfterMs(action: LaunchAction, launchedAtMs: number): number {
  return launchedAtMs + LAUNCH_RETRY_MS[action];
}

// ── Précondition ────────────────────────────────────────────────────────────

export const LAUNCH_NO_ISSUE_MESSAGE = "Ce ticket n'a pas encore d'Issue GitHub.";
export const LAUNCH_NOT_ALLOWED_MESSAGE = "Ce lancement n'est pas possible pour ce statut.";
export const LAUNCH_NOT_VALIDATED_BY_APP_MESSAGE =
  "Validé sur GitHub : validez depuis l'application pour lancer le développement.";
/**
 * Livraison ou reprise d'un ticket En cours que l'application n'a pas validé (décisions 1
 * et 9 du 2026-11-14) : il ne se valide plus depuis l'application.
 */
export const LAUNCH_IN_PROGRESS_NOT_BY_APP_MESSAGE =
  "Ce ticket a été validé sur GitHub : livrez ou corrigez sa pull request sur GitHub.";

/**
 * Ce que décide un lancement avant tout appel : `null` s'il est permis, sinon le message du
 * refus. Une Issue est requise ; le statut doit être celui du lancement, et la règle des
 * décisions permises recalculée doit l'offrir (P42) : la liste stockée n'est pas lue.
 * Kass'Beer n'a pas de type Question. Pure.
 */
export function launchPrecondition(
  args: { status: unknown; hasIssue: boolean; validatedByAppAt?: unknown },
  action: LaunchAction,
): string | null {
  if (!args.hasIssue) return LAUNCH_NO_ISSUE_MESSAGE;
  if (args.status !== LAUNCH_FROM_STATUS[action]) return LAUNCH_NOT_ALLOWED_MESSAGE;
  // Développement : validé dans l'application seul (`validated_by_app_at`), jamais par une
  // étiquette posée sur GitHub (ADR-008, décision de l'utilisateur du 2026-11-13).
  if (
    !allowedDecisions(args.status, isValidatedByApp(args.validatedByAppAt)).includes(
      LAUNCH_DECISION[action],
    )
  ) {
    if (action === "developpement" && args.status === "validated") {
      return LAUNCH_NOT_VALIDATED_BY_APP_MESSAGE;
    }
    return args.status === "in_progress"
      ? LAUNCH_IN_PROGRESS_NOT_BY_APP_MESSAGE
      : LAUNCH_NOT_ALLOWED_MESSAGE;
  }
  return null;
}

// ── Historique et règle « en cours » ───────────────────────────────────────

export type LaunchState = "launched" | "failed" | "unknown";

/** Une entrée d'historique, lue sans supposer sa forme (dates en millisecondes). */
export interface LaunchEntryView {
  id: unknown;
  action: unknown;
  state: unknown;
  at_ms: number | null;
  retry_after_ms: number | null;
}

function isLaunchAction(value: unknown): value is LaunchAction {
  return typeof value === "string" && (LAUNCH_ACTIONS as readonly string[]).includes(value);
}

/**
 * Le lancement en cours qui bloque `action`, ou `null` : une entrée d'une action de
 * `LAUNCH_BLOCKED_BY[action]`, `launched` ou `unknown`, dont `retry_after` est dans le futur.
 * C'est la seule règle, au serveur comme au client : une entrée `failed` porte `retry_after`
 * égal à son heure et ne bloque rien ; « Répondre » et un blocage de livraison relevé
 * ramènent `retry_after` à l'heure du relevé (`closeRunningEntries`). Rend l'entrée la plus
 * récente qui bloque, avec son action. Pure.
 */
export function runningLaunch(
  entries: readonly LaunchEntryView[],
  action: LaunchAction,
  nowMs: number,
): { action: LaunchAction; atMs: number; retryAfterMs: number } | null {
  const blockers = LAUNCH_BLOCKED_BY[action];
  let found: { action: LaunchAction; atMs: number; retryAfterMs: number } | null = null;
  for (const e of entries) {
    if (!isLaunchAction(e.action) || !blockers.includes(e.action)) continue;
    if (e.state !== "launched" && e.state !== "unknown") continue;
    if (e.retry_after_ms === null || e.retry_after_ms <= nowMs) continue;
    const atMs = e.at_ms ?? e.retry_after_ms - LAUNCH_RETRY_MS[e.action];
    if (found === null || atMs > found.atMs) {
      found = { action: e.action, atMs, retryAfterMs: e.retry_after_ms };
    }
  }
  return found;
}

/**
 * L'historique après « Répondre » : chaque entrée `launched` ou `unknown` encore en cours
 * voit son `retry_after` ramené à `nowMs` (Kass'Dalle : un lancement antérieur au dernier
 * changement de statut ne bloque rien). `only` restreint aux entrées choisies (livraison :
 * entrées `livraison` lancées avant un blocage relevé, P45). `null` si rien ne change. Pure.
 */
export function closeRunningEntries(
  entries: readonly Record<string, unknown>[],
  views: readonly LaunchEntryView[],
  nowMs: number,
  toTimestamp: (ms: number) => unknown,
  only: (view: LaunchEntryView) => boolean = () => true,
): Record<string, unknown>[] | null {
  let changed = false;
  const out = entries.map((entry, i) => {
    const v = views[i];
    if (v === undefined || !only(v)) return entry;
    if (v.state !== "launched" && v.state !== "unknown") return entry;
    if (v.retry_after_ms === null || v.retry_after_ms <= nowMs) return entry;
    changed = true;
    return { ...entry, retry_after: toTimestamp(nowMs) };
  });
  return changed ? out : null;
}

// ── Plafond (P36) ───────────────────────────────────────────────────────────

/** Compteur du jour des lancements : `ticket_quotas/launch_{AAAAMMJJ}`. */
export function launchQuotaDocId(day: string): string {
  return `launch_${day}`;
}

/** Message du plafond du jour (Kass'Dalle). Pure. */
export function launchQuotaMessage(limit: number): string {
  return `Vous avez lancé ${limit} sessions aujourd'hui. Réessayez demain.`;
}

/** Vrai si un lancement de plus passe sous le plafond. Pure. */
export function launchFitsQuota(count: number, limit: number = LAUNCHES_PER_DAY): boolean {
  return count < limit;
}

/** Un compteur lu sans supposer sa forme : entier positif, sinon 0. Pure. */
export function readLaunchCount(raw: unknown): number {
  return typeof raw === "number" && Number.isSafeInteger(raw) && raw > 0 ? raw : 0;
}

/**
 * Les champs de `ticket_status/launches` après un lancement compté (`delta` = 1) ou rendu
 * (`delta` = -1), le jour `day` étant celui où il a été compté et `quotaCount` le compteur
 * du jour après l'écriture (source de `count_day`).
 *
 * Compter : un mois différent repart de zéro. Rendre : un document déjà passé à un autre
 * jour ou à un autre mois garde ses compteurs. Aucun ne descend sous zéro. `per_day` est
 * réécrit à chaque fois. Pure.
 */
export function nextLaunchStatus(
  current: Record<string, unknown>,
  day: string,
  quotaCount: number,
  delta: 1 | -1,
): Record<string, unknown> {
  const month = day.slice(0, 6);
  const out: Record<string, unknown> = { per_day: LAUNCHES_PER_DAY };
  const sameMonth = current.month === month;
  const monthCount = sameMonth ? readLaunchCount(current.count_month) : 0;
  if (delta === 1) {
    out.day = day;
    out.count_day = quotaCount;
    out.month = month;
    out.count_month = monthCount + 1;
    return out;
  }
  if (current.day === day) out.count_day = quotaCount;
  if (sameMonth) out.count_month = Math.max(0, monthCount - 1);
  return out;
}

/**
 * Les champs de `ticket_status/launches` pour le jour `day`, sans lancement : jour et mois
 * remis à jour par la passe horaire, `count_day` égal au compteur du jour. `null` si rien
 * ne change. Pure.
 */
export function refreshedLaunchStatus(
  current: Record<string, unknown>,
  day: string,
  quotaCount: number,
): Record<string, unknown> | null {
  const month = day.slice(0, 6);
  const wanted: Record<string, unknown> = {
    day,
    count_day: quotaCount,
    month,
    count_month: current.month === month ? readLaunchCount(current.count_month) : quotaCount,
    per_day: LAUNCHES_PER_DAY,
  };
  const same = Object.entries(wanted).every(([k, v]) => current[k] === v);
  return same ? null : wanted;
}

/** Champ de `ticket_status/launches` qui signale le jeton refusé d'une routine. */
export const ROUTINE_INVALID_FIELD: Record<LaunchAction, string> = {
  analyse: "analysis_invalid_since",
  developpement: "development_invalid_since",
  livraison: "development_invalid_since",
  reprise: "development_invalid_since",
};

// ── Messages ────────────────────────────────────────────────────────────────

const PARIS_DATE_TIME = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Europe/Paris",
  year: "2-digit",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

function parisParts(ms: number): Record<string, string> {
  const out: Record<string, string> = {};
  for (const p of PARIS_DATE_TIME.formatToParts(new Date(ms))) out[p.type] = p.value;
  return out;
}

/** « 13/10/26 », heure de Paris. Pure. */
export function parisShortDate(ms: number): string {
  const p = parisParts(ms);
  return `${p.day}/${p.month}/${p.year}`;
}

/** « 14:05 », heure de Paris. Pure. */
export function parisHourMinute(ms: number): string {
  const p = parisParts(ms);
  return `${p.hour}:${p.minute}`;
}

const RUNNING_WHAT: Record<LaunchAction, string> = {
  analyse: "Une analyse a été lancée",
  developpement: "Un développement a été lancé",
  livraison: "Une livraison a été lancée",
  reprise: "Une correction de la pull request a été lancée",
};

/**
 * Message d'un lancement refusé parce qu'un lancement qui le bloque est en cours ; `action`
 * est celle de l'entrée en cours. Pure.
 */
export function launchRunningMessage(
  action: LaunchAction,
  launchedAtMs: number,
  retryAfterMs: number,
): string {
  const what = RUNNING_WHAT[action];
  return (
    `${what} le ${parisShortDate(launchedAtMs)} à ${parisHourMinute(launchedAtMs)}. ` +
    `Attendez son résultat ou relancez après ${parisHourMinute(retryAfterMs)}.`
  );
}
