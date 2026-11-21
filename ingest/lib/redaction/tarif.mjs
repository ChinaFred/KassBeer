// Tarif et estimation des textes rédigés par l'API (ADR-013, section 5 ; ADR-017, section 1).
// Le tarif vient de import/ingest/tarif.json, commun à toutes les natures, écrit par l'admin
// avec sa date et sa source ; aucun tarif n'est écrit dans le code. Sans fichier lisible, ou
// s'il a plus de 90 jours, aucune estimation, donc aucun envoi. Le nom du poste de coût vient
// de la nature, jamais de ce fichier.

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { estDate } from "./texte.mjs";

/// Âge maximal du tarif, en jours.
export const AGE_MAX_TARIF_JOURS = 90;

export const MESSAGE_TARIF_INCONNU = "Tarif inconnu : estimation impossible";

/// Prix lus, en dollars par million de jetons.
const PRIX = ["input", "output", "cache_write", "cache_read", "batch_input", "batch_output"];

/// Erreur d'utilisation d'un générateur (generer-aromes.mjs…) : message montré tel quel,
/// code de sortie 2.
export class ErreurRedaction extends Error {}

/// Nom du fichier de tarif, dans le dossier parent de celui de la nature
/// (import/ingest/tarif.json par défaut).
export const FICHIER_TARIF = "tarif.json";

/// Chemins du tarif d'une nature dont les fichiers vivent dans [dossierNature] : `chemin`, le
/// seul lu, et `ancien`, l'emplacement d'avant ADR-017 (import/ingest/aromes/tarif.json),
/// qui n'est plus lu.
export function cheminsTarif(dossierNature) {
  return {
    chemin: join(dossierNature, "..", FICHIER_TARIF),
    ancien: join(dossierNature, FICHIER_TARIF),
  };
}

/// Lit le tarif commun pour [dossierNature] (voir cheminsTarif). Si seul l'ancien fichier
/// existe, refus « Tarif inconnu » qui dit de le déplacer : aucun repli sur l'ancien
/// emplacement. Rend aussi `ancienIgnore` : vrai si l'ancien fichier existe à côté du
/// nouveau, pour le signaler à l'écran.
export function lireTarifCommun(dossierNature, modele, maintenant, existe = existsSync) {
  const { chemin, ancien } = cheminsTarif(dossierNature);
  if (!existe(chemin) && existe(ancien)) {
    throw new ErreurRedaction(
      `${MESSAGE_TARIF_INCONNU} (${chemin} absent ; ${ancien} n'est plus lu depuis ADR-017 : ` +
        `déplacez-le d'un dossier vers le haut, dans ${chemin}).`,
    );
  }
  return {
    tarif: lireTarif(chemin, modele, maintenant),
    chemin,
    ancien,
    ancienIgnore: existe(ancien),
  };
}

/// Lit le tarif de [chemin] pour [modele] à la date [maintenant]. Lève ErreurRedaction
/// (« Tarif inconnu : estimation impossible », avec la raison) si le fichier manque, est
/// illisible, vise un autre modèle, ou a plus de 90 jours.
export function lireTarif(chemin, modele, maintenant, lire = (c) => readFileSync(c, "utf8")) {
  const refus = (raison) => new ErreurRedaction(`${MESSAGE_TARIF_INCONNU} (${raison}).`);
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

/// Borne haute d'un envoi : pour chaque entrée, jetons d'entrée comptés × tarif d'entrée
/// (écriture du cache comprise en appels directs) + max_tokens × tarif de sortie. Rend le
/// montant total et le nombre d'entrées qui tiennent dans [budget] (dans l'ordre).
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
