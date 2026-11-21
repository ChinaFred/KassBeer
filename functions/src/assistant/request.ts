/**
 * Argument de `recipeAssistantTurn` lu en liste blanche, bornes, et requête envoyée au modèle
 * (ADR-015, sections 3 à 5 et amendements ; P59).
 *
 * Tout refus a lieu avant la réservation du tour : rien n'est compté. Le serveur ne lit pas
 * BeerJSON et ne calcule rien de brassage : il borne la taille et la profondeur, garde les
 * clés de `RecipeType` au premier niveau de `recipe`, et retire partout les champs de personne
 * et de prix (`owner_*`, `created_at`, `updated_at`, prix, stock, coût, e-mail, uid).
 */

import { HttpsError } from "firebase-functions/v2/https";

import { requireBoundedText } from "../auth";
import { AI_MAX_TURNS } from "../config";
import type { ClaudeMessage } from "../ai/claude";
import type { ClaudeTurnRequest } from "../ai/run";
import type { AiFeaturePolicy } from "../ai/settings";
import { jsonDepth, jsonLength } from "../ai/json";
import {
  ASSISTANT_PROMPT_VERSION,
  ASSISTANT_SYSTEM_PROMPT,
  SUMMARY_INSTRUCTION,
  dataBlock,
  type DataBlock,
} from "./prompt";
import { assistantOutputFormat } from "./proposition";

// ── Bornes (ADR-015, section 4 et amendements) ──────────────────────────────

export const ARG_KEYS = [
  "conversationId",
  "history",
  "message",
  "recipe",
  "calculs",
  "equipment",
  "style",
  "aromas",
  "mode",
  "summary",
] as const;

export const CONVERSATION_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;
export const MESSAGE_MAX_CHARS = 1500;
export const REPLAY_MAX_CHARS = 6000;
export const SUMMARY_MAX_CHARS = 6000;
export const RECIPE_MAX_CHARS = 64_000;
/** `equipment`, `style` et `calculs`, chacun. */
export const SIDE_MAX_CHARS = 8000;
export const AROMAS_MAX = 20;
export const AROMA_TEXT_MAX_CHARS = 400;
/** Taille d'une entrée d'arôme sérialisée (descripteurs et usages compris). */
export const AROMA_ENTRY_MAX_CHARS = 4000;
export const TURN_TOTAL_MAX_CHARS = 120_000;
export const SUMMARY_TOTAL_MAX_CHARS = 160_000;
export const TURN_MAX_TOKENS = 4000;
export const SUMMARY_MAX_TOKENS = 2000;
export const CALL_TIMEOUT_MS = 90_000;
/** Profondeur JSON au plus de `recipe` ; 6 pour les autres objets. */
export const RECIPE_MAX_DEPTH = 12;
export const SIDE_MAX_DEPTH = 6;

/** Clés de `RecipeType` gardées, sans `author`, `coauthor` ni `created` (noms, date). */
export const RECIPE_KEYS = [
  "name",
  "type",
  "batch_size",
  "efficiency",
  "style",
  "ingredients",
  "mash",
  "notes",
  "original_gravity",
  "final_gravity",
  "alcohol_by_volume",
  "ibu_estimate",
  "color_estimate",
  "beer_pH",
  "carbonation",
  "apparent_attenuation",
  "fermentation",
  "packaging",
  "boil",
  "taste",
  "calories_per_pint",
];

/** Segments d'un nom de champ qui le font retirer partout (prix, stock, coût, identité). */
const PRIVATE_SEGMENTS = [
  "price",
  "prices",
  "prix",
  "cost",
  "costs",
  "cout",
  "coût",
  "stock",
  "inventory",
  "email",
  "uid",
];

export type AssistantMode = "turn" | "summary";

/** Un message de `history`, tel que le client l'envoie : `{role, text}`. */
export interface HistoryEntry {
  role: "user" | "assistant";
  text: string;
}

export interface AssistantArgs {
  mode: AssistantMode;
  conversationId: string;
  history: HistoryEntry[];
  message: string | null;
  summary: string | null;
  recipe: Record<string, unknown>;
  calculs: Record<string, unknown> | null;
  equipment: Record<string, unknown> | null;
  style: Record<string, unknown> | null;
  aromas: Record<string, unknown>[] | null;
  /** Rang du tour dans la conversation (1 pour le premier). */
  turn: number;
  /** `turns_per_conversation` de la politique. */
  turnsPerConversation: number;
}

export const CONVERSATION_FULL_MESSAGE =
  "La conversation est trop longue : résumez-la pour continuer.";

/**
 * Refus d'un argument : `details.field` (chemin), `details.reason` `too_long` (borne
 * dépassée) ou `invalid_argument` (forme), message en français.
 */
function invalid(field: string, message: string, reason = "invalid_argument"): HttpsError {
  return new HttpsError("invalid-argument", message, { field, reason, counted: false });
}

function tooLong(field: string, message: string): HttpsError {
  return invalid(field, message, "too_long");
}

/**
 * Garde de taille brute d'un texte (P30, P59) : forme et longueur contrôlées ici pour rendre
 * une raison stable (`too_long`), puis `requireBoundedText`.
 */
function boundedText(
  value: unknown,
  opts: { field: string; max: number; required: boolean; label: string },
): string | null {
  if (value === undefined || value === null) {
    if (opts.required) throw invalid(opts.field, `${opts.label} : valeur requise.`);
    return null;
  }
  if (typeof value !== "string") throw invalid(opts.field, `${opts.label} : un texte est attendu.`);
  if (value.length > opts.max) {
    throw tooLong(opts.field, `${opts.label} : ${opts.max} caractères au plus.`);
  }
  return requireBoundedText(value, opts) ?? null;
}

function conversationFull(): HttpsError {
  return new HttpsError("failed-precondition", CONVERSATION_FULL_MESSAGE, {
    reason: "conversation_full",
    counted: false,
  });
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Vrai pour un nom de champ à retirer partout (P59). Pure. */
export function isPrivateKey(key: string): boolean {
  const lower = key.toLowerCase();
  if (lower.startsWith("owner_") || lower === "created_at" || lower === "updated_at") return true;
  return lower.split(/[_\-.]/).some((segment) => PRIVATE_SEGMENTS.includes(segment));
}

/** Copie sans les champs privés, à toute profondeur. Pure. */
export function withoutPrivateFields(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(withoutPrivateFields);
  if (!isPlainObject(value)) return value;
  const out: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value)) {
    if (!isPrivateKey(key)) out[key] = withoutPrivateFields(child);
  }
  return out;
}

/** `recipe` réduite aux clés de `RecipeType` gardées, sans champ privé. Pure. */
export function cleanRecipe(recipe: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of RECIPE_KEYS) {
    if (key in recipe) out[key] = withoutPrivateFields(recipe[key]);
  }
  return out;
}

/** Objet JSON borné en taille brute et en profondeur, ou `null` s'il est absent. */
function readObject(
  value: unknown,
  field: string,
  label: string,
  opts: { maxChars: number; maxDepth: number; required: boolean },
): Record<string, unknown> | null {
  if (value === undefined || value === null) {
    if (opts.required) throw invalid(field, `${label} : valeur requise.`);
    return null;
  }
  if (!isPlainObject(value)) throw invalid(field, `${label} : un objet est attendu.`);
  const size = jsonLength(value);
  if (size === null || size > opts.maxChars) {
    throw tooLong(field, `${label} : ${opts.maxChars} caractères au plus.`);
  }
  if (jsonDepth(value, opts.maxDepth) > opts.maxDepth) {
    throw tooLong(field, `${label} : structure trop profonde.`);
  }
  return value;
}

/** Vrai si une chaîne de `value` dépasse `max` caractères, à toute profondeur. Pure. */
function hasLongText(value: unknown, max: number): boolean {
  if (typeof value === "string") return value.length > max;
  if (value === null || typeof value !== "object") return false;
  return Object.values(value as Record<string, unknown>).some((child) => hasLongText(child, max));
}

function readAromas(value: unknown): Record<string, unknown>[] | null {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value)) throw invalid("aromas", "Arômes : une liste est attendue.");
  if (value.length > AROMAS_MAX) {
    throw tooLong("aromas", `Arômes : ${AROMAS_MAX} houblons au plus.`);
  }
  return value.map((entry, i) => {
    const field = `aromas.${i}`;
    const obj = readObject(entry, field, "Arôme", {
      maxChars: AROMA_ENTRY_MAX_CHARS,
      maxDepth: SIDE_MAX_DEPTH,
      required: true,
    }) as Record<string, unknown>;
    if (hasLongText(obj, AROMA_TEXT_MAX_CHARS)) {
      throw tooLong(field, `Arôme : ${AROMA_TEXT_MAX_CHARS} caractères au plus par texte.`);
    }
    return withoutPrivateFields(obj) as Record<string, unknown>;
  });
}

function readHistory(value: unknown, maxEntries: number): HistoryEntry[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw invalid("history", "Historique : une liste est attendue.");
  // Garde de taille avant de lire les messages ; la borne de la conversation suit.
  if (value.length > maxEntries) throw tooLong("history", "Historique trop long.");
  return value.map((entry, i) => {
    const field = `history.${i}`;
    if (!isPlainObject(entry)) throw invalid(field, "Message illisible.");
    const extra = Object.keys(entry).find((k) => k !== "role" && k !== "text");
    if (extra !== undefined) throw invalid(`${field}.${extra}`, "Champ inconnu.");
    const role = i % 2 === 0 ? "user" : "assistant";
    if (entry.role !== role) {
      throw invalid(`${field}.role`, "Historique : rôles alternés, en commençant par user.");
    }
    const text = boundedText(entry.text, {
      field: `${field}.text`,
      max: role === "user" ? MESSAGE_MAX_CHARS : REPLAY_MAX_CHARS,
      required: true,
      label: "Message",
    });
    if (text === null || text.trim().length === 0) throw invalid(`${field}.text`, "Message vide.");
    return { role, text };
  });
}

/**
 * Lit l'argument d'un tour (P59). Lève `invalid-argument` (`details.field`) ou
 * `failed-precondition` `conversation_full`, avant toute réservation. Pure.
 */
export function readAssistantArgs(data: unknown, feature: AiFeaturePolicy): AssistantArgs {
  if (!isPlainObject(data)) throw invalid("", "Argument illisible.");
  const extra = Object.keys(data).find((k) => !(ARG_KEYS as readonly string[]).includes(k));
  if (extra !== undefined) throw invalid(extra, "Champ inconnu.");

  const rawMode = data.mode;
  if (rawMode !== undefined && rawMode !== "turn" && rawMode !== "summary") {
    throw invalid("mode", "Mode : « turn » ou « summary ».");
  }
  const mode: AssistantMode = rawMode === "summary" ? "summary" : "turn";

  const conversationId = boundedText(data.conversationId, {
    field: "conversationId",
    max: 64,
    required: true,
    label: "Conversation",
  });
  if (conversationId === null || !CONVERSATION_ID_PATTERN.test(conversationId)) {
    throw invalid("conversationId", "Conversation : identifiant invalide.");
  }

  let message: string | null = null;
  if (mode === "summary") {
    if (data.message !== undefined) {
      throw invalid("message", "Résumé : aucun message n'est attendu.");
    }
  } else {
    message = boundedText(data.message, {
      field: "message",
      max: MESSAGE_MAX_CHARS,
      required: true,
      label: "Message",
    });
    if (message === null || message.trim().length === 0) {
      throw invalid("message", "Message vide.");
    }
  }

  const summary = boundedText(data.summary, {
    field: "summary",
    max: SUMMARY_MAX_CHARS,
    required: false,
    label: "Résumé",
  });

  const limit = feature.turns_per_conversation;
  const history = readHistory(data.history, 2 * AI_MAX_TURNS);
  if (mode === "summary" && history.length > 2 * limit) {
    throw tooLong("history", `Résumé : ${2 * limit} messages au plus.`);
  }
  if (history.length % 2 !== 0) {
    throw invalid("history", "Historique : il doit finir par une réponse de l'assistant.");
  }
  if (mode === "summary" && history.length < 2) {
    throw invalid("history", "Résumé : au moins un échange est attendu.");
  }

  const recipe = readObject(data.recipe, "recipe", "Recette", {
    maxChars: RECIPE_MAX_CHARS,
    maxDepth: RECIPE_MAX_DEPTH,
    required: true,
  }) as Record<string, unknown>;
  const side = (field: "calculs" | "equipment" | "style", label: string) => {
    const obj = readObject(data[field], field, label, {
      maxChars: SIDE_MAX_CHARS,
      maxDepth: SIDE_MAX_DEPTH,
      required: false,
    });
    return obj === null ? null : (withoutPrivateFields(obj) as Record<string, unknown>);
  };
  const calculs = side("calculs", "Calculs");
  const equipment = side("equipment", "Équipement");
  const style = side("style", "Style");
  const aromas = readAromas(data.aromas);

  if (mode === "turn" && history.length > 2 * (limit - 1)) throw conversationFull();

  const args: AssistantArgs = {
    mode,
    conversationId,
    history,
    message,
    summary,
    recipe: cleanRecipe(recipe),
    calculs,
    equipment,
    style,
    aromas,
    turn: history.length / 2 + 1,
    turnsPerConversation: limit,
  };
  const total = jsonLength(sentPayload(args)) ?? Number.POSITIVE_INFINITY;
  if (mode === "turn" && total > TURN_TOTAL_MAX_CHARS) throw conversationFull();
  if (mode === "summary" && total > SUMMARY_TOTAL_MAX_CHARS) {
    throw tooLong("history", "Conversation trop longue pour être résumée.");
  }
  return args;
}

/** Ce qui part au modèle, mesuré pour la borne totale. Pure. */
function sentPayload(args: AssistantArgs): Record<string, unknown> {
  return {
    recipe: args.recipe,
    calculs: args.calculs,
    equipment: args.equipment,
    style: args.style,
    aromas: args.aromas,
    summary: args.summary,
    history: args.history,
    message: args.message,
  };
}

/** Blocs de contexte, dans l'ordre de `DATA_BLOCKS`, sans les blocs absents. Pure. */
export function contextText(args: AssistantArgs): string {
  const blocks: [DataBlock, unknown][] = [
    ["RECETTE", args.recipe],
    ["CALCULS", args.calculs],
    ["EQUIPEMENT", args.equipment],
    ["STYLE", args.style],
    ["AROMES", args.aromas],
    ["RESUME", args.summary],
    ["CONVERSATION", args.history.length > 0 ? args.history : null],
  ];
  return blocks
    .filter(([, value]) => value !== null)
    .map(([name, value]) => dataBlock(name, value))
    .join("\n\n");
}

/**
 * Requête du tour : un seul bloc système, les consignes fixes (en cache) ; un seul message
 * `user`, en dernier : les blocs de contexte, puis le bloc `DEMANDE` (mode `turn`) ou la
 * consigne de résumé fixe (mode `summary`). La requête finit toujours par ce message. Mode
 * `turn` : sortie structurée (`assistantOutputFormat`). Pure.
 */
export function buildAssistantRequest(args: AssistantArgs): ClaudeTurnRequest {
  const context = contextText(args);
  const tail = args.mode === "summary" ? SUMMARY_INSTRUCTION : dataBlock("DEMANDE", args.message);
  const last: ClaudeMessage = {
    role: "user",
    content: context.length > 0 ? `${context}\n\n${tail}` : tail,
  };
  return {
    system: [{ text: ASSISTANT_SYSTEM_PROMPT, cache: true }],
    messages: [last],
    maxTokens: args.mode === "summary" ? SUMMARY_MAX_TOKENS : TURN_MAX_TOKENS,
    timeoutMs: CALL_TIMEOUT_MS,
    correlationId: args.conversationId,
    promptVersion: ASSISTANT_PROMPT_VERSION,
    // Lot A2 : un tour rend `{reponse, proposition}` (sortie structurée) ; un résumé reste
    // du texte, sans proposition.
    outputFormat: args.mode === "turn" ? assistantOutputFormat() : null,
  };
}

/**
 * Texte coupé à `max` caractères, à la dernière ligne vide qui précède, sinon au caractère
 * (sans couper une paire de substitution). Pure.
 */
export function cutText(text: string, max: number): { text: string; truncated: boolean } {
  if (text.length <= max) return { text, truncated: false };
  const head = text.slice(0, max);
  const blank = head.lastIndexOf("\n\n");
  if (blank > 0) return { text: head.slice(0, blank).trimEnd(), truncated: true };
  const code = head.charCodeAt(head.length - 1);
  const safe = code >= 0xd800 && code <= 0xdbff ? head.slice(0, -1) : head;
  return { text: safe, truncated: true };
}
