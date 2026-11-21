/**
 * Mesure d'un argument JSON reçu par une callable d'IA (ADR-016, ADR-015) : taille en
 * caractères de sa forme sérialisée, profondeur. Les bornes vivent chez l'appelant.
 */

import { logError } from "../logging";

/** Taille du JSON de `value`, en unités UTF-16 ; `null` s'il ne se sérialise pas. */
export function jsonLength(value: unknown): number | null {
  try {
    const text = JSON.stringify(value);
    return typeof text === "string" ? text.length : 0;
  } catch (err) {
    // Valeur circulaire ou `BigInt` : impossible depuis une callable (JSON reçu), refusée par
    // l'appelant.
    logError({
      message: "IA : argument non sérialisable",
      feature: "ai",
      extra: { error_name: err instanceof Error ? err.name : typeof err },
    });
    return null;
  }
}

/** Profondeur d'une valeur JSON (un scalaire vaut 0), arrêtée au-delà de `max`. Pure. */
export function jsonDepth(value: unknown, max: number): number {
  if (value === null || typeof value !== "object") return 0;
  if (max < 0) return 1;
  let deepest = 0;
  for (const child of Object.values(value as Record<string, unknown>)) {
    deepest = Math.max(deepest, jsonDepth(child, max - 1));
    if (deepest > max) break;
  }
  return deepest + 1;
}
