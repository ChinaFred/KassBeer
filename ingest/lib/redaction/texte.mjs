// Règles de texte et empreintes communes aux natures rédigées par l'API (ADR-013, ADR-017),
// tirées de lib/aromes/validation.mjs. N'importe pas le SDK d'Anthropic : l'écrivain
// (ecrire.mjs) et les tests chargent ce fichier sans lui (P54).
//
// Une erreur est une règle, jamais le texte contrôlé : les rapports ne recopient aucun texte
// rendu par le modèle.

import { createHash } from "node:crypto";

/// Efforts permis par l'option --effort et dans la version d'une provenance.
export const EFFORTS = ["low", "medium", "high", "xhigh", "max"];

/// Bornes d'un texte, en caractères (points de code).
export const TEXTE_MIN = 40;
export const TEXTE_MAX = 400;

const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

// Contrôles C0 et C1, et marques et contrôles bidirectionnels (P9).
const CONTROLES = /[\u0000-\u001f\u007f-\u009f؜‎‏‪-‮⁦-⁩]/gu;

const estObjet = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const longueur = (t) => [...t].length;

/// Vrai si [texte] est une date réelle `AAAA-MM-JJ`.
export function estDate(texte) {
  const m = typeof texte === "string" ? DATE.exec(texte) : null;
  if (!m) return false;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.toISOString().slice(0, 10) === texte;
}

/// Texte en NFC, caractères de contrôle et bidirectionnels retirés, espaces de bord retirées.
export function nettoyerTexte(texte) {
  return texte.normalize("NFC").replace(CONTROLES, "").trim();
}

/// Règles enfreintes par un texte déjà nettoyé (liste vide s'il est bon). Une comparaison à
/// un autre ingrédient est permise (ADR-013, décision 8).
export function reglesTexte(texte) {
  const regles = [];
  const n = longueur(texte);
  if (n < TEXTE_MIN || n > TEXTE_MAX) regles.push(`longueur ${TEXTE_MIN} à ${TEXTE_MAX}`);
  if (/https?:\/\/|\bwww\./iu.test(texte)) regles.push("adresse web");
  else if (/\b[a-z0-9-]+\.(com|net|org|fr|de|eu|io|uk|us|nz|au|be|ch|cz)\b/iu.test(texte)) {
    regles.push("adresse web");
  }
  if (texte.includes("@")) regles.push("@");
  if (/[<>`]/u.test(texte) || /(^|\n)\s*[#*]/u.test(texte)) regles.push("balisage");
  if (texte.includes("€") || texte.includes("$")) regles.push("symbole monétaire");
  if (/(^|[^\p{L}])(eur|euros?)(?![\p{L}])/iu.test(texte)) regles.push("monnaie");
  return regles;
}

/// JSON canonique : clés triées à chaque niveau.
export function jsonCanonique(valeur) {
  if (Array.isArray(valeur)) return `[${valeur.map(jsonCanonique).join(",")}]`;
  if (estObjet(valeur)) {
    const cles = Object.keys(valeur).sort();
    return `{${cles.map((k) => `${JSON.stringify(k)}:${jsonCanonique(valeur[k])}`).join(",")}}`;
  }
  return JSON.stringify(valeur);
}

export const sha256 = (texte) => createHash("sha256").update(texte).digest("hex");
