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

// Contrôles C0 et C1, et caractères de format invisibles (catégorie Unicode Cf) : marques
// et contrôles bidirectionnels (P9), espaces et liants sans chasse (U+200B à U+200D,
// U+2060), marque d'ordre des octets (U+FEFF), trait d'union conditionnel…
const CONTROLES = /[\u0000-\u001f\u007f-\u009f\p{Cf}]/gu;

const estObjet = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const longueur = (t) => [...t].length;

/// Vrai si [texte] est une date réelle `AAAA-MM-JJ`.
export function estDate(texte) {
  const m = typeof texte === "string" ? DATE.exec(texte) : null;
  if (!m) return false;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.toISOString().slice(0, 10) === texte;
}

/// Texte en NFC, caractères de contrôle et de format invisibles retirés, espaces de bord
/// retirées. Un texte stocké doit être égal à sa forme nettoyée (« texte non nettoyé »).
export function nettoyerTexte(texte) {
  return texte.normalize("NFC").replace(CONTROLES, "").trim();
}

/// Forme contrôlée d'un texte : nettoyée, puis en NFKC, qui ramène les formes pleine chasse
/// et de compatibilité (« ５ », « ｇ », « ＄ », « ＠ ») à leur forme courante. Les règles de
/// contenu (adresse web, @, balisage, monnaie, dose) portent sur elle ; le texte stocké reste
/// en NFC.
export function formeControlee(texte) {
  return nettoyerTexte(texte).normalize("NFKC");
}

/// Règles enfreintes par un texte déjà nettoyé (liste vide s'il est bon). Une comparaison à
/// un autre ingrédient est permise (ADR-013, décision 8). [min] et [max] : bornes de
/// longueur, TEXTE_MIN et TEXTE_MAX par défaut (le résumé d'un divers s'arrête à 300).
export function reglesTexte(texte, { min = TEXTE_MIN, max = TEXTE_MAX } = {}) {
  const regles = [];
  const n = longueur(texte);
  if (n < min || n > max) regles.push(`longueur ${min} à ${max}`);
  const t = formeControlee(texte);
  if (/https?:\/\/|\bwww\./iu.test(t)) regles.push("adresse web");
  else if (/\b[a-z0-9-]+\.(com|net|org|fr|de|eu|io|uk|us|nz|au|be|ch|cz)\b/iu.test(t)) {
    regles.push("adresse web");
  }
  if (t.includes("@")) regles.push("@");
  if (/[<>`]/u.test(t) || /(^|\n)\s*[#*]/u.test(t)) regles.push("balisage");
  if (t.includes("€") || t.includes("$")) regles.push("symbole monétaire");
  if (/(^|[^\p{L}])(eur|euros?)(?![\p{L}])/iu.test(t)) regles.push("monnaie");
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

/// Empreinte du contenu d'une entrée rédigée (aromes.json, descriptions.json), calculée par
/// ecrire.mjs : un document de même empreinte n'est pas réécrit.
export const empreinteContenu = (data) => sha256(jsonCanonique(data));
