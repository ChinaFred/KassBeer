/**
 * Coût d'un appel à Claude (ADR-016, section 5). Seul calcul de coût du projet : le client
 * affiche le montant stocké et ne le recalcule jamais. Aucun tarif dans ce fichier : la ligne
 * du modèle vient de `ai_config/pricing`, lue à l'appel. Sans ligne, aucun montant.
 */

import type { AiModelPrice } from "./settings";

/** Jetons rendus par l'API (`usage`). `output_tokens` compte la réflexion. */
export interface ClaudeUsage {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens: number;
  cache_read_input_tokens: number;
}

/**
 * Montant en dollars : (entrée × tarif d'entrée + écriture du cache × tarif d'écriture
 * + lecture du cache × tarif de lecture + sortie × tarif de sortie) / 1 000 000, arrondi au
 * millionième de dollar. Pure.
 */
export function callCostUsd(usage: ClaudeUsage, price: AiModelPrice): number {
  const total =
    usage.input_tokens * price.input_usd_per_mtok +
    usage.cache_creation_input_tokens * price.cache_write_usd_per_mtok +
    usage.cache_read_input_tokens * price.cache_read_usd_per_mtok +
    usage.output_tokens * price.output_usd_per_mtok;
  return Math.round(total) / 1_000_000;
}
