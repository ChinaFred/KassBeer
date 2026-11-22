// Règles de texte et empreintes communes aux natures rédigées par l'API (ADR-013, ADR-018),
// tirées de lib/aromes/validation.mjs. N'importe pas le SDK d'Anthropic : l'écrivain
// (ecrire.mjs) et les tests chargent ce fichier sans lui (P54).
//
// Une erreur est une règle, jamais le texte contrôlé : les rapports ne recopient aucun texte
// rendu par le modèle.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

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

export const estObjet = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
export const longueur = (t) => [...t].length;

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

/// Règles d'un texte `{text}` au [chemin] : forme, nettoyage, puis reglesTexte.
export function reglesBlocTexte(chemin, v) {
  if (!estObjet(v) || Object.keys(v).join(",") !== "text" || typeof v.text !== "string") {
    return [`${chemin} : {text} attendu`];
  }
  const regles = [];
  if (v.text !== nettoyerTexte(v.text)) {
    regles.push(`${chemin}.text : texte non nettoyé (NFC, contrôles)`);
  }
  for (const regle of reglesTexte(v.text)) regles.push(`${chemin}.text : ${regle}`);
  return regles;
}

/// Liste fermée de descripteurs `{key, label}` du fichier JSON [url], lue une fois par la
/// nature qui la porte (descripteurs des houblons, des levures).
export function lireListeFermee(url) {
  return JSON.parse(readFileSync(url, "utf8"));
}

/// Règles d'une liste `descriptors` (`{key, label}`, clé dans [libelles], libellé recopié,
/// sans doublon). Le nombre d'entrées se contrôle avec le statut.
export function reglesDescripteurs(descripteurs, libelles) {
  if (!Array.isArray(descripteurs)) return ["descriptors : liste attendue"];
  const regles = [];
  const r = (chemin, regle) => regles.push(`${chemin} : ${regle}`);
  const vus = new Set();
  descripteurs.forEach((d, i) => {
    const c = `descriptors[${i}]`;
    if (!estObjet(d) || Object.keys(d).sort().join(",") !== "key,label") {
      r(c, "{key, label} attendu");
      return;
    }
    if (!libelles.has(d.key)) r(`${c}.key`, "hors de la liste fermée");
    else if (d.label !== libelles.get(d.key)) r(`${c}.label`, "différent de la liste");
    if (vus.has(d.key)) r(`${c}.key`, "en double");
    vus.add(d.key);
  });
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
