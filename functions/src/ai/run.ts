/**
 * Un tour d'IA facturé, de bout en bout (ADR-016, section 2 ; P57) : `runClaudeTurn`.
 *
 * Dans l'ordre, après la garde de la callable (`requireMember` ou `requireAdmin`) :
 *  1. poste dans `AI_COST_CENTERS`, sinon refus avant tout appel ;
 *  2. politique `ai_config/policy` relue : absente, illisible ou hors bornes → refus
 *     `failed-precondition` `ai_policy_unavailable`, rien compté, `logError` échantillonné ;
 *  3. poste fermé (`members_enabled` faux) pour un non-admin → `permission-denied`
 *     `ai_feature_closed` ;
 *  4. `build` lit et borne les arguments du poste (un refus n'est pas compté) et construit la
 *     requête avec le modèle et l'effort de la politique ;
 *  5. tour réservé en transaction (`ai_quotas/{uid}`), refus `quota_exhausted` au plafond ;
 *  6. un appel (`callClaude`), jamais rejoué ;
 *  7. tour rendu sur un refus 4xx ou une connexion impossible ; gardé sinon ;
 *  8. coût calculé avec la grille `ai_config/pricing` (sans grille ou sans ligne : appel compté
 *     sans montant), comptes du mois écrits (`ai_usage/`), journal de l'appel.
 *
 * Le client ne reçoit jamais le corps d'une erreur d'Anthropic : `details.reason` (code
 * stable), `details.counted` et, quand un tour a été réservé, `details.quota`.
 */

import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

import { AI_POLICY_DOC, AI_PRICING_DOC, COLL_AI_CONFIG } from "../config";
import { firestore, type FirestoreKit } from "../firestore";
import { LogSampler } from "../logSampler";
import { logError, logInfo, logWarn, type LogEntry } from "../logging";
import {
  callClaude,
  type ClaudeFetch,
  type ClaudeMessage,
  type ClaudeOutcome,
  type ClaudeRejection,
  type ClaudeSystemBlock,
} from "./claude";
import { isAiCostCenter, type AiCostCenter } from "./costCenters";
import { parisMonth } from "./parisTime";
import { callCostUsd } from "./pricing";
import { dailyLimit, releaseTurn, reserveTurn, type QuotaView, type Reservation } from "./quota";
import { featurePolicy, readPricing, type AiFeaturePolicy } from "./settings";
import { recordUsage, type UsageDelta } from "./usage";

/** L'appelant, tel que la garde l'a vérifié. `email` : clé de `members/`, en minuscules. */
export interface AiCaller {
  uid: string;
  email: string;
  isAdmin: boolean;
  founder: boolean;
}

/** Ce que le poste envoie ; modèle et effort viennent de la politique. */
export interface ClaudeTurnRequest {
  system: readonly ClaudeSystemBlock[];
  messages: readonly ClaudeMessage[];
  maxTokens: number;
  timeoutMs: number;
  /** Identifiant de corrélation du journal (conversation), sans contenu. */
  correlationId: string;
  /** Version du prompt du poste, notée au journal. */
  promptVersion: number;
}

export interface ClaudeTurnResult {
  text: string;
  stopReason: string | null;
  quota: QuotaView;
  model: string;
}

export type Logger = (level: "error" | "warn" | "info", entry: LogEntry) => void;

const defaultLogger: Logger = (level, entry) => {
  if (level === "error") logError(entry);
  else if (level === "warn") logWarn(entry);
  else logInfo(entry);
};

export interface RunDeps {
  /** Clé de l'API, lue au premier appel (`ANTHROPIC_API_KEY.value()`). */
  apiKey: () => string;
  kit?: () => Promise<FirestoreKit>;
  fetchImpl?: ClaudeFetch;
  nowMs?: () => number;
  log?: Logger;
}

export const POLICY_UNAVAILABLE_MESSAGE =
  "Les réglages de l'IA manquent. L'administrateur les enregistre dans Admin › Moteur d'IA.";
export const FEATURE_CLOSED_MESSAGE =
  "Cette fonction d'IA est réservée à l'administrateur pour l'instant.";
export const NO_ANSWER_MESSAGE = "L'IA n'a pas rendu de réponse lisible.";
export const AI_UNAVAILABLE_MESSAGE = "L'IA est indisponible pour l'instant. Réessayez.";

/** Échantillonneurs : une ligne par minute et par instance au plus (ADR-016, section 4). */
let policySampler = new LogSampler();
let pricingSampler = new LogSampler();

function refusal(
  code: FunctionsErrorCode,
  message: string,
  reason: string,
  extra: Record<string, unknown> = {},
): HttpsError {
  return new HttpsError(code, message, { reason, ...extra });
}

function quotaDetails(q: QuotaView): Record<string, unknown> {
  return {
    limit: q.limit,
    remaining: q.remaining,
    resets_at: new Date(q.resetsAtMs).toISOString(),
  };
}

/** Code, message et raison rendus pour un refus 4xx de l'API. Pure. */
export function rejectionRefusal(rejection: ClaudeRejection): {
  code: FunctionsErrorCode;
  message: string;
  reason: string;
} {
  switch (rejection) {
    case "credit_exhausted":
      return {
        code: "resource-exhausted",
        message: "Crédit de l'IA épuisé pour ce mois.",
        reason: "ai_credit_exhausted",
      };
    case "rate_limited":
      return {
        code: "resource-exhausted",
        message: "L'IA reçoit trop de demandes. Réessayez dans une minute.",
        reason: "ai_rate_limited",
      };
    case "key_invalid":
      return {
        code: "failed-precondition",
        message: "La clé de l'IA est refusée. L'administrateur la remplace dans Secret Manager.",
        reason: "ai_key_invalid",
      };
    case "model_unavailable":
      return {
        code: "failed-precondition",
        message: "Le modèle réglé n'est pas disponible. Changez-le dans Admin › Moteur d'IA.",
        reason: "ai_model_unavailable",
      };
    case "request_rejected":
      return {
        code: "failed-precondition",
        message: "L'IA a refusé la demande.",
        reason: "ai_request_rejected",
      };
  }
}

/** Lit le réglage du poste ; refuse sans rien compter s'il manque (ADR-016, section 4). */
async function loadFeature(
  kit: FirestoreKit,
  costCenter: AiCostCenter,
  now: number,
  log: Logger,
): Promise<AiFeaturePolicy> {
  let raw: unknown;
  try {
    const snap = await kit.db.collection(COLL_AI_CONFIG).doc(AI_POLICY_DOC).get();
    raw = snap.exists ? snap.data() : undefined;
  } catch (err) {
    log("error", {
      message: "IA : politique illisible (Firestore)",
      feature: "ai",
      error: err,
      extra: { cost_center: costCenter },
    });
    throw refusal("unavailable", AI_UNAVAILABLE_MESSAGE, "ai_unavailable", { counted: false });
  }
  const feature = featurePolicy(raw, costCenter);
  if (feature.ok) return feature.value;
  const count = policySampler.record(now);
  if (count !== null) {
    log("error", {
      message: "IA : politique absente ou illisible, appel refusé",
      feature: "ai",
      extra: { cost_center: costCenter, motif: feature.motif, field: feature.field, count },
    });
  }
  throw refusal("failed-precondition", POLICY_UNAVAILABLE_MESSAGE, "ai_policy_unavailable", {
    counted: false,
  });
}

/** Montant de l'appel, ou `null` (grille absente, illisible, modèle absent). Au mieux. */
async function priceOf(
  kit: FirestoreKit,
  model: string,
  outcome: Extract<ClaudeOutcome, { kind: "answered" }>,
  now: number,
  log: Logger,
): Promise<number | null> {
  if (outcome.usage === null) return null;
  let raw: unknown;
  try {
    const snap = await kit.db.collection(COLL_AI_CONFIG).doc(AI_PRICING_DOC).get();
    raw = snap.exists ? snap.data() : undefined;
  } catch (err) {
    log("error", {
      message: "IA : grille tarifaire illisible (Firestore)",
      feature: "ai",
      error: err,
    });
    return null;
  }
  const pricing = readPricing(raw, { stored: true });
  const line = pricing.ok ? pricing.value.models[model] : undefined;
  if (line === undefined) {
    const count = pricingSampler.record(now);
    if (count !== null) {
      log("warn", {
        message: "IA : tarifs en panne, appel compté sans montant",
        feature: "ai",
        extra: {
          model,
          motif: pricing.ok ? "model_missing" : pricing.motif,
          field: pricing.ok ? `models.${model}` : pricing.field,
          count,
        },
      });
    }
    return null;
  }
  return callCostUsd(outcome.usage, line);
}

/**
 * Exécute un tour d'IA facturé (voir l'en-tête du module). `build` reçoit le réglage du poste
 * et lève une `HttpsError` pour un argument refusé : rien n'est alors compté.
 */
export async function runClaudeTurn(
  args: {
    costCenter: string;
    caller: AiCaller;
    build: (feature: AiFeaturePolicy) => ClaudeTurnRequest;
  },
  deps: RunDeps,
): Promise<ClaudeTurnResult> {
  const log = deps.log ?? defaultLogger;
  const nowMs = deps.nowMs ?? Date.now;
  if (!isAiCostCenter(args.costCenter)) {
    log("error", {
      message: "IA : poste de coût inconnu, appel refusé",
      feature: "ai",
      extra: { cost_center: String(args.costCenter).slice(0, 80) },
    });
    throw refusal("failed-precondition", AI_UNAVAILABLE_MESSAGE, "ai_cost_center_unknown", {
      counted: false,
    });
  }
  const costCenter = args.costCenter;
  const kit = await (deps.kit ?? firestore)();
  const feature = await loadFeature(kit, costCenter, nowMs(), log);
  if (!feature.members_enabled && !args.caller.isAdmin) {
    throw refusal("permission-denied", FEATURE_CLOSED_MESSAGE, "ai_feature_closed", {
      counted: false,
    });
  }
  const request = args.build(feature);

  let reservation: Reservation;
  try {
    reservation = await reserveTurn(kit, {
      uid: args.caller.uid,
      costCenter,
      limit: dailyLimit(feature, args.caller.founder),
      nowMs: nowMs(),
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    log("error", {
      message: "IA : réservation du tour en échec",
      feature: "ai",
      error: err,
      extra: { cost_center: costCenter },
    });
    throw refusal("unavailable", AI_UNAVAILABLE_MESSAGE, "ai_unavailable", { counted: false });
  }
  const quota: QuotaView = {
    limit: reservation.limit,
    remaining: reservation.remaining,
    resetsAtMs: reservation.resetsAtMs,
  };

  const startedAt = nowMs();
  const outcome = await callClaude(
    {
      model: feature.model,
      effort: feature.effort,
      system: request.system,
      messages: request.messages,
      maxTokens: request.maxTokens,
      timeoutMs: request.timeoutMs,
    },
    deps.apiKey(),
    { fetchImpl: deps.fetchImpl, log: (entry) => log("error", entry) },
  );
  const durationMs = nowMs() - startedAt;
  const journal = (extra: LogEntry["extra"]): LogEntry => ({
    message: "IA : appel",
    feature: "ai",
    extra: {
      cost_center: costCenter,
      uid: args.caller.uid,
      model: feature.model,
      effort: feature.effort,
      duration_ms: durationMs,
      correlation_id: request.correlationId,
      prompt_version: request.promptVersion,
      ...extra,
    },
  });

  if (outcome.kind === "rejected" || outcome.kind === "not_sent") {
    try {
      await releaseTurn(kit, { uid: args.caller.uid, costCenter, day: reservation.day });
      quota.remaining += 1;
    } catch (err) {
      log("error", {
        message: "IA : tour non rendu après un appel non facturé (reste compté)",
        feature: "ai",
        error: err,
        extra: { cost_center: costCenter },
      });
    }
    log(
      "warn",
      journal({
        outcome: outcome.kind,
        status: outcome.kind === "rejected" ? outcome.status : null,
        detail: outcome.detail,
      }),
    );
    if (outcome.kind === "not_sent") {
      throw refusal("unavailable", "L'IA est injoignable. Réessayez.", "ai_unreachable", {
        counted: false,
        quota: quotaDetails(quota),
      });
    }
    const r = rejectionRefusal(outcome.rejection);
    throw refusal(r.code, r.message, r.reason, { counted: false, quota: quotaDetails(quota) });
  }

  const month = parisMonth(nowMs());
  let delta: UsageDelta;
  let costUsd: number | null = null;
  if (outcome.kind === "failed") {
    delta = { kind: "failed" };
  } else {
    costUsd = await priceOf(kit, feature.model, outcome, nowMs(), log);
    delta = { kind: "answered", usage: outcome.usage, costUsd };
  }
  try {
    await recordUsage(kit, {
      uid: args.caller.uid,
      email: args.caller.email,
      costCenter,
      month,
      delta,
    });
  } catch (err) {
    log("error", {
      message: "IA : comptes du mois non écrits",
      feature: "ai",
      error: err,
      extra: { cost_center: costCenter, month },
    });
  }

  if (outcome.kind === "failed") {
    log(
      "warn",
      journal({
        outcome: "failed",
        failure: outcome.failure,
        status: outcome.status,
        detail: outcome.detail,
      }),
    );
    const timeout = outcome.failure === "timeout";
    throw refusal(
      timeout ? "deadline-exceeded" : "unavailable",
      timeout ? "L'IA n'a pas répondu à temps. Le tour est compté." : AI_UNAVAILABLE_MESSAGE,
      timeout ? "ai_timeout" : "ai_failed",
      { counted: true, quota: quotaDetails(quota) },
    );
  }

  const usage = outcome.usage;
  log(
    "info",
    journal({
      outcome: "answered",
      stop_reason: outcome.stopReason,
      input_tokens: usage?.input_tokens ?? null,
      cache_write_tokens: usage?.cache_creation_input_tokens ?? null,
      cache_read_tokens: usage?.cache_read_input_tokens ?? null,
      output_tokens: usage?.output_tokens ?? null,
      cost_usd: costUsd,
      unpriced: costUsd === null,
    }),
  );
  if (
    outcome.stopReason === "refusal" ||
    outcome.stopReason === "max_tokens" ||
    outcome.text.trim().length === 0
  ) {
    throw refusal("aborted", NO_ANSWER_MESSAGE, "ai_no_answer", {
      counted: true,
      quota: quotaDetails(quota),
    });
  }
  return { text: outcome.text, stopReason: outcome.stopReason, quota, model: feature.model };
}

/** Échantillonneurs remis à zéro (tests). */
export function resetRunSamplers(): void {
  policySampler = new LogSampler();
  pricingSampler = new LogSampler();
}
