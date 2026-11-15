/**
 * Postes de coût de l'IA (ADR-016, section 3 ; CLAUDE.md, « Coûts variables »).
 *
 * Liste fermée : un appel sous un autre nom est refusé avant tout `fetch` (P57). Copie de
 * `test-fixtures/ai_cost_centers.json`, rejouée par `functions/test/ai.test.ts` ; le client en
 * tient une seconde copie pour ses libellés (`postes_ia.dart`). Un poste retiré du code reste
 * dans la fixture et ici, pour que les mois passés gardent leur libellé.
 */

export const AI_COST_CENTERS = [
  { key: "recipe_assistant_turn", label: "Assistant de recette", adr: "ADR-015" },
] as const;

export type AiCostCenter = (typeof AI_COST_CENTERS)[number]["key"];

/** Vrai pour une clé de la liste fermée. Pure. */
export function isAiCostCenter(value: unknown): value is AiCostCenter {
  return typeof value === "string" && AI_COST_CENTERS.some((c) => c.key === value);
}

/** Libellé d'un poste (messages de `saveAiSettings`). Pure. */
export function costCenterLabel(key: AiCostCenter): string {
  return AI_COST_CENTERS.find((c) => c.key === key)?.label ?? key;
}
