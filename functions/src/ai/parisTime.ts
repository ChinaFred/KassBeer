/**
 * Jours et mois de Paris pour le socle IA (ADR-016, section 6) : jour du plafond, minuit
 * suivant (`resets_at`), mois des comptes et leur échéance (`expires_at`). Le client ne fait
 * aucun calcul de jour : il compare l'heure à `resets_at`.
 */

import { parisDay } from "../tickets/model";

export { parisDay };

const PARIS_PARTS = new Intl.DateTimeFormat("en-GB", {
  timeZone: "Europe/Paris",
  hourCycle: "h23",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

/** Écart de l'heure de Paris sur UTC à l'instant `atMs`, en millisecondes. Pure. */
export function parisOffsetMs(atMs: number): number {
  const parts = PARIS_PARTS.formatToParts(new Date(atMs));
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? "0");
  const asUtc = Date.UTC(
    get("year"),
    get("month") - 1,
    get("day"),
    get("hour"),
    get("minute"),
    get("second"),
  );
  return asUtc - Math.floor(atMs / 1000) * 1000;
}

/**
 * Minuit, heure de Paris, du jour civil `year-month-day` (mois de 1 à 12, débordement
 * permis : le mois 13 est janvier de l'année suivante). Le changement d'heure a lieu à 2 h
 * ou 3 h : l'écart relu à minuit suffit. Pure.
 */
export function parisMidnightMs(year: number, month: number, day: number): number {
  const utcMidnight = Date.UTC(year, month - 1, day);
  const guess = utcMidnight - parisOffsetMs(utcMidnight);
  return utcMidnight - parisOffsetMs(guess);
}

/** Minuit de Paris qui suit l'instant `atMs` (début du jour suivant). Pure. */
export function nextParisMidnightMs(atMs: number): number {
  const day = parisDay(new Date(atMs));
  return parisMidnightMs(
    Number(day.slice(0, 4)),
    Number(day.slice(4, 6)),
    Number(day.slice(6, 8)) + 1,
  );
}

/** Mois de Paris, `AAAA-MM`. Pure. */
export function parisMonth(atMs: number): string {
  const day = parisDay(new Date(atMs));
  return `${day.slice(0, 4)}-${day.slice(4, 6)}`;
}
