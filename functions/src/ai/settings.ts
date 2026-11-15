/**
 * Politique de l'IA (`ai_config/policy`) et grille tarifaire (`ai_config/pricing`) : lecture
 * et validation (ADR-016, sections 4 et 5 ; P57, P58).
 *
 * Le même code valide une valeur reçue par `saveAiSettings` et un document relu par un poste
 * à chaque appel. Une valeur hors forme ou hors bornes est refusée avec le chemin du champ en
 * faute (`field`) : le formulaire de Moteur d'IA l'affiche. Aucun tarif, aucun modèle par
 * défaut dans ce fichier : sans réglage lisible, le poste refuse (ADR-016, section 4).
 */

import { AI_MAX_TURNS } from "../config";
import { AI_COST_CENTERS, costCenterLabel, isAiCostCenter, type AiCostCenter } from "./costCenters";

/** Identifiant d'un modèle Claude (ADR-016, section 5). */
export const MODEL_ID_PATTERN = /^claude-[a-z0-9-]{1,60}$/;

/** Efforts acceptés par l'API (`output_config.effort`), à revoir avec l'API. */
export const AI_EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;
export type AiEffort = (typeof AI_EFFORTS)[number];

/** Modèles au plus dans la grille. */
export const PRICING_MAX_MODELS = 20;
/** Tarif le plus haut accepté, en dollars par million de jetons. */
export const PRICE_MAX_USD_PER_MTOK = 1000;
/** Longueur de `source` de la grille. */
export const PRICING_SOURCE_MAX = 200;
/** Longueur du libellé d'un modèle. */
export const MODEL_LABEL_MAX = 80;

export const PRICE_FIELDS = [
  "input_usd_per_mtok",
  "output_usd_per_mtok",
  "cache_write_usd_per_mtok",
  "cache_read_usd_per_mtok",
] as const;

export interface AiFeaturePolicy {
  model: string;
  /** `null` : aucun `output_config.effort` envoyé (modèle sans effort). */
  effort: AiEffort | null;
  members_enabled: boolean;
  turns_per_day: number;
  founder_turns_per_day: number;
  turns_per_conversation: number;
}

export interface AiPolicy {
  version: 1;
  features: Partial<Record<AiCostCenter, AiFeaturePolicy>>;
}

export interface AiModelPrice {
  label: string;
  input_usd_per_mtok: number;
  output_usd_per_mtok: number;
  cache_write_usd_per_mtok: number;
  cache_read_usd_per_mtok: number;
  efforts: AiEffort[];
}

export interface AiPricing {
  version: 1;
  checked_on: string;
  source: string;
  models: Record<string, AiModelPrice>;
}

/** Motif d'une politique illisible, journalisé sans contenu (ADR-016, section 4). */
export type SettingsMotif = "missing" | "unreadable" | "out_of_bounds";

export type Checked<T> =
  { ok: true; value: T } | { ok: false; field: string; message: string; motif: SettingsMotif };

/** Champs écrits par le serveur à l'enregistrement, admis à la relecture seulement. */
const STORED_ONLY_KEYS = ["updated_at", "updated_by_uid"];

const FEATURE_KEYS = [
  "model",
  "effort",
  "members_enabled",
  "turns_per_day",
  "founder_turns_per_day",
  "turns_per_conversation",
] as const;

const TURN_FIELDS = ["turns_per_day", "founder_turns_per_day", "turns_per_conversation"] as const;

const MODEL_KEYS = ["label", ...PRICE_FIELDS, "efforts"] as const;

type Fail = Extract<Checked<never>, { ok: false }>;

function fail(field: string, message: string, motif: SettingsMotif = "unreadable"): Fail {
  return { ok: false, field, message, motif };
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Le premier champ hors de la liste, ou `null`. */
function unknownKey(
  obj: Record<string, unknown>,
  allowed: readonly string[],
  prefix: string,
): Fail | null {
  const key = Object.keys(obj).find((k) => !allowed.includes(k));
  return key === undefined ? null : fail(prefix + key, "Champ inconnu.");
}

function isEffort(value: unknown): value is AiEffort {
  return typeof value === "string" && (AI_EFFORTS as readonly string[]).includes(value);
}

function readFeature(raw: unknown, prefix: string): Checked<AiFeaturePolicy> {
  if (!isPlainObject(raw)) return fail(prefix.slice(0, -1), "Réglage du poste illisible.");
  const extra = unknownKey(raw, FEATURE_KEYS, prefix);
  if (extra !== null) return extra;
  const model = raw.model;
  if (typeof model !== "string" || !MODEL_ID_PATTERN.test(model)) {
    return fail(`${prefix}model`, "Identifiant de modèle invalide (claude-…).");
  }
  const effort = raw.effort;
  if (effort !== null && !isEffort(effort)) {
    return fail(`${prefix}effort`, `Effort inconnu : ${AI_EFFORTS.join(", ")} ou aucun.`);
  }
  const membersEnabled = raw.members_enabled;
  if (typeof membersEnabled !== "boolean") {
    return fail(`${prefix}members_enabled`, "Ouverture aux membres : vrai ou faux attendu.");
  }
  const turns: Record<string, number> = {};
  for (const key of TURN_FIELDS) {
    const value = raw[key];
    if (typeof value !== "number" || !Number.isInteger(value)) {
      return fail(`${prefix}${key}`, "Nombre entier attendu.");
    }
    if (value < 1 || value > AI_MAX_TURNS) {
      return fail(`${prefix}${key}`, `Entre 1 et ${AI_MAX_TURNS}.`, "out_of_bounds");
    }
    turns[key] = value;
  }
  return {
    ok: true,
    value: {
      model,
      effort,
      members_enabled: membersEnabled,
      turns_per_day: turns.turns_per_day,
      founder_turns_per_day: turns.founder_turns_per_day,
      turns_per_conversation: turns.turns_per_conversation,
    },
  };
}

/**
 * Lit une politique : `stored` admet les champs écrits par le serveur (`updated_at`,
 * `updated_by_uid`). Postes connus seuls, réglages complets, plafonds entiers de 1 à
 * `AI_MAX_TURNS`, `members_enabled` booléen strict. Pure.
 */
export function readPolicy(raw: unknown, opts: { stored: boolean }): Checked<AiPolicy> {
  if (raw === undefined || raw === null)
    return fail("", "Aucune politique enregistrée.", "missing");
  if (!isPlainObject(raw)) return fail("", "Politique illisible.");
  const extra = unknownKey(
    raw,
    ["version", "features", ...(opts.stored ? STORED_ONLY_KEYS : [])],
    "",
  );
  if (extra !== null) return extra;
  if (raw.version !== 1) return fail("version", "Version 1 attendue.");
  if (!isPlainObject(raw.features)) return fail("features", "Liste des postes illisible.");
  const features: Partial<Record<AiCostCenter, AiFeaturePolicy>> = {};
  for (const [key, value] of Object.entries(raw.features)) {
    if (!isAiCostCenter(key)) return fail(`features.${key}`, "Poste inconnu.");
    const feature = readFeature(value, `features.${key}.`);
    if (!feature.ok) return feature;
    features[key] = feature.value;
  }
  return { ok: true, value: { version: 1, features } };
}

/**
 * Le réglage d'un poste, ou le motif de refus : document absent, illisible, poste absent,
 * valeur hors bornes (ADR-016, section 4). Pure.
 */
export function featurePolicy(raw: unknown, costCenter: AiCostCenter): Checked<AiFeaturePolicy> {
  const policy = readPolicy(raw, { stored: true });
  if (!policy.ok) return policy;
  const feature = policy.value.features[costCenter];
  if (feature === undefined) {
    return fail(`features.${costCenter}`, "Poste absent de la politique.", "missing");
  }
  return { ok: true, value: feature };
}

function readModel(raw: unknown, prefix: string): Checked<AiModelPrice> {
  if (!isPlainObject(raw)) return fail(prefix.slice(0, -1), "Ligne du modèle illisible.");
  const extra = unknownKey(raw, MODEL_KEYS, prefix);
  if (extra !== null) return extra;
  const label = raw.label;
  if (typeof label !== "string" || label.trim().length === 0 || label.length > MODEL_LABEL_MAX) {
    return fail(`${prefix}label`, `Libellé de 1 à ${MODEL_LABEL_MAX} caractères.`);
  }
  const prices: Record<string, number> = {};
  for (const key of PRICE_FIELDS) {
    const value = raw[key];
    if (typeof value !== "number" || !Number.isFinite(value)) {
      return fail(`${prefix}${key}`, "Nombre attendu.");
    }
    if (value < 0 || value > PRICE_MAX_USD_PER_MTOK) {
      return fail(`${prefix}${key}`, `Tarif de 0 à ${PRICE_MAX_USD_PER_MTOK} $.`, "out_of_bounds");
    }
    prices[key] = value;
  }
  const efforts = raw.efforts;
  if (!Array.isArray(efforts)) return fail(`${prefix}efforts`, "Liste d'efforts attendue.");
  const seen: AiEffort[] = [];
  for (const effort of efforts) {
    if (!isEffort(effort)) {
      return fail(`${prefix}efforts`, `Effort inconnu : ${AI_EFFORTS.join(", ")}.`);
    }
    if (seen.includes(effort)) return fail(`${prefix}efforts`, `Effort en double : ${effort}.`);
    seen.push(effort);
  }
  return {
    ok: true,
    value: {
      label,
      input_usd_per_mtok: prices.input_usd_per_mtok,
      output_usd_per_mtok: prices.output_usd_per_mtok,
      cache_write_usd_per_mtok: prices.cache_write_usd_per_mtok,
      cache_read_usd_per_mtok: prices.cache_read_usd_per_mtok,
      efforts: seen,
    },
  };
}

function isCalendarDate(text: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return false;
  const at = new Date(`${text}T00:00:00Z`);
  return !Number.isNaN(at.getTime()) && at.toISOString().slice(0, 10) === text;
}

/**
 * Lit une grille : `checked_on` en `AAAA-MM-JJ`, `source` de 200 caractères au plus,
 * 20 modèles au plus aux identifiants `claude-…`, tarifs finis de 0 à 1 000, efforts de la
 * liste `AI_EFFORTS` sans doublon. Pure.
 */
export function readPricing(raw: unknown, opts: { stored: boolean }): Checked<AiPricing> {
  if (raw === undefined || raw === null) return fail("", "Aucune grille enregistrée.", "missing");
  if (!isPlainObject(raw)) return fail("", "Grille illisible.");
  const allowed = ["version", "checked_on", "source", "models"];
  const extra = unknownKey(raw, opts.stored ? [...allowed, ...STORED_ONLY_KEYS] : allowed, "");
  if (extra !== null) return extra;
  if (raw.version !== 1) return fail("version", "Version 1 attendue.");
  const checkedOn = raw.checked_on;
  if (typeof checkedOn !== "string" || !isCalendarDate(checkedOn)) {
    return fail("checked_on", "Date de vérification AAAA-MM-JJ attendue.");
  }
  const source = raw.source;
  if (typeof source !== "string" || source.length > PRICING_SOURCE_MAX) {
    return fail("source", `Source de ${PRICING_SOURCE_MAX} caractères au plus.`);
  }
  if (!isPlainObject(raw.models)) return fail("models", "Liste des modèles illisible.");
  const entries = Object.entries(raw.models);
  if (entries.length > PRICING_MAX_MODELS) {
    return fail("models", `${PRICING_MAX_MODELS} modèles au plus.`, "out_of_bounds");
  }
  const models: Record<string, AiModelPrice> = {};
  for (const [id, value] of entries) {
    if (!MODEL_ID_PATTERN.test(id)) return fail(`models.${id}`, "Identifiant de modèle invalide.");
    const line = readModel(value, `models.${id}.`);
    if (!line.ok) return line;
    models[id] = line.value;
  }
  return { ok: true, value: { version: 1, checked_on: checkedOn, source, models } };
}

export interface SettingsConflict {
  field: string;
  message: string;
}

/**
 * Premier réglage de la politique que la grille ne permet pas (enregistrement de la
 * politique, P58) : modèle absent de la grille, effort absent de `efforts` de sa ligne, ou
 * effort posé pour un modèle sans effort. `null` si tout concorde. Pure.
 */
export function policyConflict(policy: AiPolicy, pricing: AiPricing): SettingsConflict | null {
  for (const center of AI_COST_CENTERS) {
    const feature = policy.features[center.key];
    if (feature === undefined) continue;
    const line = pricing.models[feature.model];
    if (line === undefined) {
      return {
        field: `features.${center.key}.model`,
        message: "Ce modèle n'est pas dans la grille tarifaire.",
      };
    }
    if (line.efforts.length === 0 && feature.effort !== null) {
      return {
        field: `features.${center.key}.effort`,
        message: "Ce modèle n'accepte pas d'effort : choisissez « aucun ».",
      };
    }
    if (
      line.efforts.length > 0 &&
      (feature.effort === null || !line.efforts.includes(feature.effort))
    ) {
      return {
        field: `features.${center.key}.effort`,
        message: `Effort à choisir parmi : ${line.efforts.join(", ")}.`,
      };
    }
  }
  return null;
}

/**
 * Premier changement de la grille qui rendrait la politique enregistrée invalide
 * (enregistrement de la grille, amendement « cadrage du lot A1 » d'ADR-016) : modèle retiré
 * alors qu'un poste s'en sert, effort retiré alors qu'un poste l'a choisi, efforts ajoutés à un
 * modèle qu'un poste utilise sans effort. Couvre chaque cas de `policyConflict` : `null` ici
 * veut dire `policyConflict(policy, pricing) === null`. Pure.
 */
export function pricingConflict(policy: AiPolicy, pricing: AiPricing): SettingsConflict | null {
  for (const center of AI_COST_CENTERS) {
    const feature = policy.features[center.key];
    if (feature === undefined) continue;
    const label = costCenterLabel(center.key);
    const line = pricing.models[feature.model];
    if (line === undefined) {
      return {
        field: `models.${feature.model}`,
        message: `Ce modèle sert au poste « ${label} » : choisissez-en un autre d'abord.`,
      };
    }
    if (feature.effort !== null && !line.efforts.includes(feature.effort)) {
      return {
        field: `models.${feature.model}.efforts`,
        message: `L'effort « ${feature.effort} » sert au poste « ${label} » : changez-le d'abord.`,
      };
    }
    if (feature.effort === null && line.efforts.length > 0) {
      return {
        field: `models.${feature.model}.efforts`,
        message: `Le poste « ${label} » utilise ce modèle sans effort : passez-le sur un autre modèle avant d'ajouter des efforts.`,
      };
    }
  }
  return null;
}
