// Tarif et estimation du poste hop_aroma_generation (ADR-013, section 5). Le tarif vient de
// import/ingest/aromes/tarif.json, écrit par l'admin avec sa date et sa source ; aucun
// tarif n'est écrit dans le code. Sans fichier lisible, ou s'il a plus de 90 jours, aucune
// estimation, donc aucun envoi.

import { readFileSync } from "node:fs";
import { estDate } from "./validation.mjs";

/// Nom du poste de coût, porté par chaque rapport (catalogue « Coûts variables »).
export const POSTE = "hop_aroma_generation";

/// Âge maximal du tarif, en jours.
export const AGE_MAX_TARIF_JOURS = 90;

export const MESSAGE_TARIF_INCONNU = "Tarif inconnu : estimation impossible";

/// Prix lus, en dollars par million de jetons.
const PRIX = ["input", "output", "cache_write", "cache_read", "batch_input", "batch_output"];

/// Erreur d'utilisation de generer-aromes.mjs : message montré tel quel, code de sortie 2.
export class ErreurAromes extends Error {}

/// Lit le tarif de [chemin] pour [modele] à la date [maintenant]. Lève ErreurAromes
/// (« Tarif inconnu : estimation impossible », avec la raison) si le fichier manque, est
/// illisible, vise un autre modèle, ou a plus de 90 jours.
export function lireTarif(chemin, modele, maintenant, lire = (c) => readFileSync(c, "utf8")) {
  const refus = (raison) => new ErreurAromes(`${MESSAGE_TARIF_INCONNU} (${raison}).`);
  let tarif;
  try {
    tarif = JSON.parse(lire(chemin));
  } catch (erreur) {
    throw refus(`${chemin} : ${erreur.code ?? erreur.name}`);
  }
  if (tarif === null || typeof tarif !== "object") throw refus("objet attendu");
  if (tarif.model !== modele) throw refus(`modèle ${modele} attendu`);
  if (!estDate(tarif.date)) throw refus("date AAAA-MM-JJ attendue");
  if (typeof tarif.source !== "string" || tarif.source.trim() === "") {
    throw refus("source attendue");
  }
  const age = (maintenant.getTime() - Date.parse(`${tarif.date}T00:00:00Z`)) / 86_400_000;
  if (age < -1) throw refus("date dans le futur");
  if (age > AGE_MAX_TARIF_JOURS) {
    throw refus(`relevé du ${tarif.date}, plus de ${AGE_MAX_TARIF_JOURS} jours`);
  }
  const prix = tarif.usd_per_million_tokens;
  if (prix === null || typeof prix !== "object") throw refus("usd_per_million_tokens attendu");
  for (const cle of PRIX) {
    if (typeof prix[cle] !== "number" || !Number.isFinite(prix[cle]) || prix[cle] < 0) {
      throw refus(`usd_per_million_tokens.${cle} : nombre positif attendu`);
    }
  }
  return { model: tarif.model, date: tarif.date, source: tarif.source, prix };
}

/// Borne haute d'un envoi : pour chaque houblon, jetons d'entrée comptés × tarif d'entrée
/// (écriture du cache comprise en appels directs) + max_tokens × tarif de sortie. Rend le
/// montant total et le nombre de houblons qui tiennent dans [budget] (dans l'ordre).
export function borneHaute(jetonsEntree, { tarif, mode, maxTokens, budget = null }) {
  const p = tarif.prix;
  const entree = mode === "lot" ? p.batch_input : Math.max(p.input, p.cache_write);
  const sortie = mode === "lot" ? p.batch_output : p.output;
  let total = 0;
  let tiennent = 0;
  for (const n of jetonsEntree) {
    total += (n * entree + maxTokens * sortie) / 1_000_000;
    if (budget === null || total <= budget) tiennent++;
  }
  return { montant: arrondi(total), tiennent };
}

/// Montant d'un usage relu dans les réponses (`usage` cumulé), au tarif de [mode].
export function montantUsage(usage, tarif, mode) {
  const p = tarif.prix;
  const m =
    mode === "lot"
      ? // Aucun cache demandé en lot ; un jeton de cache relevé est compté au prix d'entrée.
        (usage.input_tokens + usage.cache_creation_input_tokens + usage.cache_read_input_tokens) *
          p.batch_input +
        usage.output_tokens * p.batch_output
      : usage.input_tokens * p.input +
        usage.cache_creation_input_tokens * p.cache_write +
        usage.cache_read_input_tokens * p.cache_read +
        usage.output_tokens * p.output;
  return arrondi(m / 1_000_000);
}

const arrondi = (montant) => Math.round(montant * 10_000) / 10_000;
