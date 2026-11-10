/**
 * Journal des Cloud Functions, écrit par `firebase-functions/logger` (sortie structurée
 * lue par Cloud Logging). Aucun client `@google-cloud/logging` : il tire gRPC au
 * démarrage (leçon 5).
 *
 * `logError` est la fonction de journalisation de chaque `catch` (CLAUDE.md, « Règles de
 * code »). Un jeton GitHub n'entre jamais dans un journal (P25) : `redactSecrets` retire
 * tout ce qui a la forme d'un jeton avant l'écriture.
 */

import * as logger from "firebase-functions/logger";

export type LogExtra = Record<string, string | number | boolean | null>;

export interface LogEntry {
  message: string;
  /** Domaine fonctionnel, `tickets` pour ADR-006. */
  feature: string;
  error?: unknown;
  ticketId?: string;
  extra?: LogExtra;
}

const TOKEN_PATTERN = /\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,})\b/g;
const BEARER_PATTERN = /\bBearer\s+[A-Za-z0-9._-]{8,}/gi;

/** Le texte sans rien qui ait la forme d'un jeton GitHub. Pure. */
export function redactSecrets(text: string): string {
  return text.replace(TOKEN_PATTERN, "[jeton retiré]").replace(BEARER_PATTERN, "Bearer [retiré]");
}

/** Description lisible d'une erreur, bornée, sans jeton. Pure. */
export function describeError(error: unknown): string {
  if (error instanceof Error) {
    return redactSecrets(`${error.name}: ${error.message}`).slice(0, 1000);
  }
  return redactSecrets(String(error)).slice(0, 1000);
}

function payload(entry: LogEntry): Record<string, unknown> {
  const out: Record<string, unknown> = { feature: entry.feature };
  if (entry.ticketId !== undefined) out.ticketId = entry.ticketId;
  if (entry.error !== undefined) {
    out.errorDescription = describeError(entry.error);
    if (entry.error instanceof Error && typeof entry.error.stack === "string") {
      out.stack = redactSecrets(entry.error.stack).slice(0, 4000);
    }
  }
  if (entry.extra !== undefined) {
    for (const [key, value] of Object.entries(entry.extra)) {
      out[key] = typeof value === "string" ? redactSecrets(value) : value;
    }
  }
  return out;
}

export function logError(entry: LogEntry): void {
  logger.error(redactSecrets(entry.message), payload(entry));
}

export function logWarn(entry: LogEntry): void {
  logger.warn(redactSecrets(entry.message), payload(entry));
}

export function logInfo(entry: LogEntry): void {
  logger.info(redactSecrets(entry.message), payload(entry));
}
