/**
 * Propositions de l'assistant de recette (ADR-015, section 6, lot A2 ; P59, P61).
 *
 * Liste fermée des opérations, copie de `test-fixtures/recipe_assistant_operations.json`
 * (`functions/test/proposition.test.ts` vérifie l'égalité et rejoue `reading_cases`). Le
 * client en tient une seconde copie (`exchange/lib/src/proposition.dart`), qui applique la
 * proposition. Le serveur n'applique rien et ne lit pas BeerJSON : il en tire le catalogue
 * des opérations écrit dans le prompt (`operationsCatalog`) et écarte une proposition hors de
 * ce catalogue, ou de plus de `MAX_OPERATIONS` opérations (`readProposition`). Les bornes des valeurs (`minimum`,
 * `maximum`, longueurs) ne sont pas dans le format : le client refuse l'opération seule.
 */

import { logError, type LogEntry } from "../logging";

type FieldSpec =
  | { type: "string"; min_length: number; max_length: number }
  | { type: "enum"; values: readonly string[] }
  | { type: "number"; minimum?: number; exclusive_minimum?: number; maximum: number }
  | { type: "integer"; minimum: number; maximum: number };

interface OperationSpec {
  fields: Readonly<Record<string, FieldSpec>>;
  required: readonly string[];
}

export const MAX_OPERATIONS = 30;

/** Segment de chemin d'un champ hors liste, à la place de la clé écrite par le modèle. */
export const UNKNOWN_FIELD = "<champ inconnu>";
export const RESUME_MAX_CHARS = 500;

const NAME: FieldSpec = { type: "string", min_length: 1, max_length: 120 };
const INDEX: FieldSpec = { type: "integer", minimum: 0, maximum: 49 };
const STEP_INDEX: FieldSpec = { type: "integer", minimum: 0, maximum: 19 };
const GRAMS: FieldSpec = { type: "number", exclusive_minimum: 0, maximum: 1000000 };
const PERCENT: FieldSpec = { type: "number", exclusive_minimum: 0, maximum: 100 };
const MINUTES: FieldSpec = { type: "integer", minimum: 0, maximum: 600 };
const FERMENTABLE_TYPES: FieldSpec = {
  type: "enum",
  values: ["grain", "sugar", "dry extract", "extract", "fruit", "juice", "honey", "other"],
};
const HOP_FORMS: FieldSpec = {
  type: "enum",
  values: ["pellet", "leaf", "leaf (wet)", "plug", "powder", "extract"],
};

const FERMENTABLE: Record<string, FieldSpec> = {
  name: NAME,
  type: FERMENTABLE_TYPES,
  amount_g: GRAMS,
  color_ebc: { type: "number", minimum: 0, maximum: 2000 },
  yield_pct: PERCENT,
};
const HOP: Record<string, FieldSpec> = {
  name: NAME,
  form: HOP_FORMS,
  amount_g: GRAMS,
  use: { type: "enum", values: ["boil", "whirlpool", "dry_hop"] },
  time_min: MINUTES,
  days: { type: "number", exclusive_minimum: 0, maximum: 365 },
  alpha_acid_pct: PERCENT,
};
const MISC: Record<string, FieldSpec> = {
  name: NAME,
  amount_g: GRAMS,
  amount_l: { type: "number", exclusive_minimum: 0, maximum: 1000 },
  moment: { type: "enum", values: ["mash", "boil", "after_boil", "fermentation", "bottling"] },
  time_min: MINUTES,
};
const MASH_STEP: Record<string, FieldSpec> = {
  name: NAME,
  temperature_c: { type: "number", minimum: 0, maximum: 100 },
  time_min: MINUTES,
};
const REMOVE: OperationSpec = { fields: { index: INDEX, name: NAME }, required: ["index", "name"] };

/** Opérations permises, dans l'ordre de la fixture. Aucune sur `notes`, `author`, `brew_steps`. */
export const PROPOSITION_OPERATIONS: Readonly<Record<string, OperationSpec>> = {
  set_name: { fields: { value: NAME }, required: ["value"] },
  set_type: {
    fields: {
      value: {
        type: "enum",
        values: [
          "all grain",
          "partial mash",
          "extract",
          "cider",
          "kombucha",
          "soda",
          "mead",
          "wine",
          "other",
        ],
      },
    },
    required: ["value"],
  },
  set_style_name: { fields: { value: NAME }, required: ["value"] },
  set_batch_size_l: {
    fields: { value: { type: "number", exclusive_minimum: 0, maximum: 10000 } },
    required: ["value"],
  },
  set_boil_time_min: { fields: { value: MINUTES }, required: ["value"] },
  add_fermentable: { fields: FERMENTABLE, required: ["name", "type", "amount_g"] },
  update_fermentable: {
    fields: { index: INDEX, ...FERMENTABLE },
    required: ["index", "name", "type", "amount_g"],
  },
  remove_fermentable: REMOVE,
  add_hop: { fields: HOP, required: ["name", "form", "amount_g", "use"] },
  update_hop: {
    fields: { index: INDEX, ...HOP },
    required: ["index", "name", "form", "amount_g", "use"],
  },
  remove_hop: REMOVE,
  add_misc: { fields: MISC, required: ["name", "moment"] },
  update_misc: { fields: { index: INDEX, ...MISC }, required: ["index", "name", "moment"] },
  remove_misc: REMOVE,
  set_culture: {
    fields: {
      name: NAME,
      type: {
        type: "enum",
        values: [
          "ale",
          "lager",
          "wheat",
          "wine",
          "champagne",
          "kveik",
          "brett",
          "lacto",
          "pedio",
          "bacteria",
          "malolactic",
          "mixed-culture",
          "spontaneous",
          "other",
        ],
      },
      form: { type: "enum", values: ["dry", "liquid", "slant", "culture", "dregs"] },
      attenuation_pct: PERCENT,
    },
    required: ["name"],
  },
  add_mash_step: { fields: MASH_STEP, required: ["name", "temperature_c", "time_min"] },
  update_mash_step: {
    fields: { index: STEP_INDEX, ...MASH_STEP },
    required: ["index", "name", "temperature_c", "time_min"],
  },
  remove_mash_step: {
    fields: { index: STEP_INDEX, name: NAME },
    required: ["index", "name"],
  },
};

/** Libellé du type d'un champ dans le catalogue du prompt. Pure. */
function fieldLabel(spec: FieldSpec): string {
  switch (spec.type) {
    case "string":
      return "texte";
    case "enum":
      return spec.values.join(" | ");
    case "number":
      return "nombre";
    case "integer":
      return "entier";
  }
}

/**
 * Catalogue des opérations écrit dans le prompt, tiré de `PROPOSITION_OPERATIONS` : une ligne
 * par opération, `?` après un champ facultatif. Le format de sortie ne porte plus les
 * opérations (grammaire trop grosse pour l'API, voir `assistantOutputFormat`) : le modèle les
 * lit ici, et `readProposition` les contrôle. Pure.
 */
export function operationsCatalog(): string {
  return Object.entries(PROPOSITION_OPERATIONS)
    .map(([op, spec]) => {
      const fields = Object.entries(spec.fields).map(
        ([key, field]) => `${key}${spec.required.includes(key) ? "" : "?"} (${fieldLabel(field)})`,
      );
      return `- ${op} : ${fields.join(", ")}`;
    })
    .join("\n");
}

/**
 * Format de sortie d'un tour (`output_config.format`) : deux textes requis, `reponse` et
 * `proposition` (vide, ou le JSON d'un objet `{resume, operations}`), aucun champ facultatif ni
 * union. Le format à dix-huit variantes d'opérations dépassait la limite de compilation des
 * sorties structurées (400 « Schema is too complex for compilation », décision de
 * l'utilisateur du 2026-11-22) : la proposition est relue par `readProposition`. Pure.
 */
export function assistantOutputFormat(): Record<string, unknown> {
  return {
    type: "json_schema",
    schema: {
      type: "object",
      additionalProperties: false,
      required: ["reponse", "proposition"],
      properties: {
        reponse: { type: "string" },
        proposition: { type: "string" },
      },
    },
  };
}

export interface ProposedOperation {
  op: string;
  [field: string]: unknown;
}

export interface Proposition {
  resume: string;
  operations: ProposedOperation[];
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** Vrai si `value` a le type du champ (bornes non vérifiées). Pure. */
function hasType(spec: FieldSpec, value: unknown): boolean {
  switch (spec.type) {
    case "string":
      return typeof value === "string";
    case "enum":
      return typeof value === "string" && spec.values.includes(value);
    case "number":
      return typeof value === "number" && Number.isFinite(value);
    case "integer":
      return typeof value === "number" && Number.isInteger(value);
  }
}

/**
 * Lit une proposition au format de sortie : objet `{resume, operations}` seul, résumé de 1 à
 * `RESUME_MAX_CHARS` caractères, de 1 à `MAX_OPERATIONS` opérations de la liste fermée, champs
 * requis présents, aucun autre champ, chaque champ de son type. Rend le chemin du premier champ
 * en faute (sans valeur, avec `UNKNOWN_FIELD` pour un champ hors liste), pour le journal. Même règle que `lireProposition` du client. Pure.
 */
export function readProposition(
  value: unknown,
): { ok: true; value: Proposition } | { ok: false; path: string } {
  if (!isPlainObject(value)) return { ok: false, path: "" };
  if (Object.keys(value).some((k) => k !== "resume" && k !== "operations")) {
    return { ok: false, path: "" };
  }
  const { resume, operations } = value;
  if (typeof resume !== "string" || resume.length === 0 || resume.length > RESUME_MAX_CHARS) {
    return { ok: false, path: "resume" };
  }
  if (!Array.isArray(operations) || operations.length === 0) {
    return { ok: false, path: "operations" };
  }
  if (operations.length > MAX_OPERATIONS) return { ok: false, path: "operations" };
  const read: ProposedOperation[] = [];
  for (const [i, o] of operations.entries()) {
    const path = `operations.${i}`;
    if (!isPlainObject(o)) return { ok: false, path };
    const op = o.op;
    const spec =
      typeof op === "string" && Object.hasOwn(PROPOSITION_OPERATIONS, op)
        ? PROPOSITION_OPERATIONS[op]
        : undefined;
    if (spec === undefined) return { ok: false, path: `${path}.op` };
    for (const [key, field] of Object.entries(o)) {
      if (key === "op") continue;
      const f = Object.hasOwn(spec.fields, key) ? spec.fields[key] : undefined;
      // Le chemin ne cite que des noms de la liste fermée : une clé écrite par le modèle
      // n'entre jamais dans le journal.
      if (f === undefined) return { ok: false, path: `${path}.${UNKNOWN_FIELD}` };
      if (!hasType(f, field)) return { ok: false, path: `${path}.${key}` };
    }
    const missing = spec.required.find((k) => !(k in o));
    if (missing !== undefined) return { ok: false, path: `${path}.${missing}` };
    read.push({ ...o, op } as ProposedOperation);
  }
  return { ok: true, value: { resume, operations: read } };
}

/**
 * Sortie d'un tour lue : `reponse` (texte) et la proposition, ou `null` si la sortie n'est pas
 * un objet JSON avec un texte `reponse` non vide. Une proposition hors format est rendue
 * `null`, avec le chemin du champ en faute dans `rejectedPath`. Un JSON illisible est
 * journalisé par `log`, sans le texte.
 */
export function readTurnOutput(
  text: string,
  log: (entry: LogEntry) => void = logError,
): { reponse: string; proposition: Proposition | null; rejectedPath: string | null } | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    // Le message d'erreur de `JSON.parse` cite un extrait du texte : seul le nom part au
    // journal, aucun texte du modèle (P57).
    log({
      message: "Assistant : sortie du modèle illisible (JSON)",
      feature: "assistant",
      extra: { error_name: err instanceof Error ? err.name : typeof err },
    });
    return null;
  }
  if (!isPlainObject(parsed)) return null;
  const reponse = parsed.reponse;
  if (typeof reponse !== "string" || reponse.trim().length === 0) return null;
  const brut = parsed.proposition;
  if (brut === null || brut === undefined)
    return { reponse, proposition: null, rejectedPath: null };
  if (typeof brut !== "string") return { reponse, proposition: null, rejectedPath: "proposition" };
  if (brut.trim().length === 0) return { reponse, proposition: null, rejectedPath: null };
  let proposition: unknown;
  try {
    proposition = JSON.parse(brut);
  } catch (err) {
    // Même règle que la sortie entière : seul le nom de l'erreur part au journal (P57).
    log({
      message: "Assistant : proposition du modèle illisible (JSON)",
      feature: "assistant",
      extra: { error_name: err instanceof Error ? err.name : typeof err },
    });
    return { reponse, proposition: null, rejectedPath: "proposition" };
  }
  const read = readProposition(proposition);
  return read.ok
    ? { reponse, proposition: read.value, rejectedPath: null }
    : {
        reponse,
        proposition: null,
        rejectedPath: read.path === "" ? "proposition" : `proposition.${read.path}`,
      };
}
