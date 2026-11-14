/**
 * Échantillonnage d'une ligne de journal répétée, repris de Kass'Dalle
 * (`functions/src/utils/logSampler.ts`).
 *
 * Un refus répété (signature de webhook invalide, secret absent) n'écrit qu'un relevé par
 * intervalle et par instance au plus, qui porte le nombre de refus depuis le précédent. Un
 * envoi massif de requêtes n'écrit donc qu'une ligne par minute, et le nombre reste lisible.
 * Les refus d'une rafale arrêtée avant la fin de l'intervalle ne sont écrits qu'au relevé
 * suivant de la même instance.
 */

/** Un relevé par intervalle au plus, avec le nombre d'événements depuis le précédent. */
export class LogSampler {
  private pending = 0;
  private lastLoggedAt: number | null = null;

  constructor(private readonly intervalMs = 60_000) {}

  /** Compte un événement ; rend le nombre à journaliser, ou `null` s'il faut se taire. */
  record(now: number): number | null {
    this.pending++;
    if (this.lastLoggedAt !== null && now - this.lastLoggedAt < this.intervalMs) return null;
    const count = this.pending;
    this.pending = 0;
    this.lastLoggedAt = now;
    return count;
  }
}
