// Contrôle des descriptions aromatiques des levures (ADR-017, P62), partagé par le générateur
// (generer-aromes.mjs --nature culture) et l'écrivain (ecrire.mjs) : données envoyées,
// périmètre, styles du prompt, empreinte, sortie du modèle et entrée de
// import/ingest/aromes/levures/aromes.json. Tiré de lib/aromes/natures/culture.mjs au portage
// sur le moteur commun (ADR-019) sans changer les données envoyées, l'empreinte, la liste des
// descripteurs ni les règles ; le texte passe par les règles communes de
// lib/redaction/texte.mjs (NFC, catégorie Unicode Cf retirée, contrôle sur la forme NFKC).
// N'importe pas le SDK d'Anthropic (P54).
//
// Une erreur est un chemin et une règle, jamais le texte contrôlé.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { reglesEnveloppe } from "../redaction/entree.mjs";
import { ErreurRedaction } from "../redaction/tarif.mjs";
import {
  estObjet,
  jsonCanonique,
  lireListeFermee,
  longueur,
  nettoyerTexte,
  reglesBlocTexte,
  reglesDescripteurs,
  sha256,
} from "../redaction/texte.mjs";
import { controlerDocument } from "../validation.mjs";

/// Collection écrite par ecrire.mjs depuis import/ingest/aromes/levures/aromes.json.
export const COLLECTION_AROMES_LEVURES = "beer_culture_aromas";

/// Nom du poste de coût (catalogue « Coûts variables », ADR-017 section 6).
export const POSTE_LEVURES = "culture_aroma_generation";

/// Version du prompt des levures : un changement de texte la fait monter, ce qui change
/// l'empreinte des entrées et fait régénérer.
export const PROMPT_VERSION_LEVURES = 1;

/// Modèle décidé par l'utilisateur (ADR-013, repris par ADR-017).
export const MODELE = "claude-fable-5-2";

/// Borne la réflexion et la réponse ensemble, et la borne haute de l'estimation.
export const MAX_TOKENS = 4000;

export const STATUTS = ["described", "unknown"];
export const CONFIANCES = ["high", "medium", "low"];

/// Nombre de descripteurs d'une entrée `described`.
export const DESCRIPTEURS_MIN = 1;
export const DESCRIPTEURS_MAX = 8;

/// Types de levure hors du périmètre (décision 1 de l'utilisateur du 2026-11-21) : levures
/// de vin, de cidre, d'hydromel et de saké. Une levure du groupe y entre quand même ; une
/// levure sans type est dans le périmètre.
export const TYPES_HORS_PERIMETRE = ["other", "wine", "champagne", "malolactic"];

/// Textes d'une entrée, dans l'ordre d'affichage : profil, bas de plage, haut de plage.
export const TEXTES_LEVURE = ["profile", "cool", "warm"];

/// Styles conseillés d'une entrée, au plus.
export const STYLES_MAX = 6;

/// Liste fermée des 32 descripteurs des levures (`{key, label}`), acceptée par
/// l'utilisateur le 2026-11-21. Seul endroit où elle vit.
export const DESCRIPTEURS_LEVURES = lireListeFermee(
  new URL("./descripteurs.json", import.meta.url),
);

const LIBELLES = new Map(DESCRIPTEURS_LEVURES.map((d) => [d.key, d.label]));

/// Identifiant d'une levure de beer_cultures/.
export const ID_LEVURE = /^culture-[a-z0-9]+(-[a-z0-9]+)*$/;

/// Vrai si la levure [data] (`beer_cultures/{id}` préparé) est dans le périmètre par son
/// type ; le générateur y ajoute les levures du groupe.
export function dansPerimetreLevure(data) {
  return !TYPES_HORS_PERIMETRE.includes(data?.type);
}

const nombreOuNull = (v) => (typeof v === "number" && Number.isFinite(v) ? v : null);

/// Plage `{minimum: {value}, maximum: {value}}` ramenée à `[min, max]`, ou null si les deux
/// bornes manquent.
function plage(p) {
  const min = nombreOuNull(p?.minimum?.value);
  const max = nombreOuNull(p?.maximum?.value);
  return min === null && max === null ? null : [min, max];
}

/// Données d'une levure envoyées au modèle (ADR-017, section 2), tirées de
/// `beer_cultures/{id}` préparé : rien d'autre ne part (ni notes, ni provenance).
export function donneesEnvoyeesLevure(data) {
  return {
    name: data.name,
    aliases: Array.isArray(data.aliases) ? data.aliases : [],
    producer: data.producer ?? null,
    product_id: data.product_id ?? null,
    type: data.type ?? null,
    form: data.form ?? null,
    attenuation_pct: plage(data.attenuation),
    temperature_c: plage(data.temperature_range),
    flocculation: data.flocculation ?? null,
  };
}

/// Caractères de contrôle et bidirectionnels : un nom de style qui en porte ajouterait une
/// ligne au prompt système, après « Liste des styles ». Règle de la v0.1.93 gardée telle
/// quelle : l'élargir changerait la liste des styles, donc l'empreinte des levures déjà
/// rédigées.
const CARACTERES_INTERDITS_NOM_STYLE = /[\u0000-\u001F\u007F‪-‮⁦-⁩]/u;

/// Styles du prompt tirés des documents de beer_styles.json préparé ([documents] : liste
/// `{id, data}`) : `{styles: [{code, name}] triés, noms: Map code → nom, stylesSha256,
/// refuses}`. `code` est l'identifiant du style (`bjcp2021-21a`). Chaque document passe
/// d'abord le contrôle de beer_styles de lib/validation.mjs, comme à l'écrivain : un document
/// refusé, ou un identifiant en double (second et suivants), n'entre ni dans la liste
/// envoyée au modèle ni dans celle des codes acceptés ; son identifiant va dans `refuses`. Un
/// nom qui porte un caractère de contrôle ou bidirectionnel est refusé de même.
export function contexteStyles(documents) {
  if (!Array.isArray(documents)) throw new Error("beer_styles.json : liste attendue");
  const vus = new Set();
  const refuses = [];
  const styles = [];
  for (const d of documents) {
    const id = typeof d?.id === "string" ? d.id : null;
    if (
      controlerDocument("beer_styles", d).length > 0 ||
      id === null ||
      vus.has(id) ||
      CARACTERES_INTERDITS_NOM_STYLE.test(d.data.name)
    ) {
      refuses.push(id);
    } else {
      styles.push({ code: id, name: d.data.name });
    }
    if (id !== null) vus.add(id);
  }
  styles.sort((a, b) => (a.code < b.code ? -1 : a.code > b.code ? 1 : 0));
  return {
    styles,
    noms: new Map(styles.map((s) => [s.code, s.name])),
    stylesSha256: sha256(jsonCanonique(styles)),
    refuses,
  };
}

/// Contexte d'une génération : styles de beer_styles.json préparé dans [dossierPrepare],
/// contrôlés par contexteStyles. Lève ErreurRedaction si aucun style n'est accepté : sans
/// liste, aucun style ne peut être proposé. Les refusés sont dans `refuses`, affichés par le
/// moteur (messageContexte de la nature).
export function contexteLevures(dossierPrepare) {
  const chemin = join(dossierPrepare, "beer_styles.json");
  const contexte = contexteStyles(JSON.parse(readFileSync(chemin, "utf8")));
  if (contexte.styles.length === 0) {
    throw new ErreurRedaction(`${chemin} : aucun style, la liste du prompt serait vide.`);
  }
  return contexte;
}

/// Empreinte des entrées d'une génération : données envoyées, version du prompt, modèle,
/// effort et SHA-256 de la liste des styles du prompt (ADR-017, section 3). Inchangée au
/// portage sur le moteur commun (ADR-019) : test figé dans test/aromes-levures.test.mjs.
export function empreinteEntreeLevure(donnees, { effort, stylesSha256 }) {
  return sha256(
    jsonCanonique({
      culture: donnees,
      prompt_version: PROMPT_VERSION_LEVURES,
      model: MODELE,
      effort,
      styles_sha256: stylesSha256,
    }),
  );
}

/// Contrôle de la sortie structurée du modèle. Rend `{regles, resultat}` : `resultat`
/// `{status, confidence?, descriptors, texts, styles}` (descripteurs `{key, label}`, styles
/// `{code, name}`, textes nettoyés) si la sortie est bonne.
export function controlerSortieLevure(sortie, contexte) {
  const regles = [];
  const r = (chemin, regle) => regles.push(`${chemin} : ${regle}`);
  const cles = ["status", "confidence", "descriptors", "texts", "styles"];
  if (!estObjet(sortie)) return { regles: ["sortie : objet attendu"], resultat: null };
  for (const k of Object.keys(sortie)) if (!cles.includes(k)) r("sortie", `clé non permise ${k}`);
  for (const k of cles) if (!(k in sortie)) r("sortie", `clé absente ${k}`);
  if (!STATUTS.includes(sortie.status)) r("status", "valeur hors de la liste");
  if (!estObjet(sortie.texts)) r("texts", "objet attendu");
  if (!Array.isArray(sortie.descriptors)) r("descriptors", "liste attendue");
  if (!Array.isArray(sortie.styles)) r("styles", "liste attendue");
  if (regles.length > 0) return { regles, resultat: null };

  const texts = {};
  for (const [k, v] of Object.entries(sortie.texts)) {
    if (!TEXTES_LEVURE.includes(k)) r("texts", `texte non permis ${k}`);
    else if (v !== null) {
      if (typeof v !== "string") r(`texts.${k}`, "texte ou null attendu");
      else texts[k] = { text: nettoyerTexte(v) };
    }
  }
  const styles = [];
  sortie.styles.forEach((code, i) => {
    if (typeof code !== "string" || !contexte.noms.has(code)) {
      r(`styles[${i}]`, "hors de la liste fermée");
    } else styles.push({ code, name: contexte.noms.get(code) });
  });
  const resultat = { status: sortie.status, descriptors: [], texts: {}, styles: [] };
  if (sortie.status === "described") {
    if (sortie.confidence !== null) resultat.confidence = sortie.confidence;
    resultat.descriptors = sortie.descriptors.map((key) => ({ key, label: LIBELLES.get(key) }));
    resultat.texts = texts;
    resultat.styles = styles;
  } else {
    if (sortie.confidence !== null) r("confidence", "null attendu pour unknown");
    if (sortie.descriptors.length > 0) r("descriptors", "vide attendu pour unknown");
    if (Object.keys(texts).length > 0) r("texts", "aucun texte attendu pour unknown");
    if (sortie.styles.length > 0) r("styles", "vide attendu pour unknown");
  }
  if (regles.length > 0) return { regles, resultat: null };
  regles.push(...reglesContenuLevure(resultat, contexte));
  return { regles, resultat: regles.length === 0 ? resultat : null };
}

/// Règles de `status`, `confidence`, `descriptors`, `texts` et `styles` d'une entrée.
function reglesContenuLevure(data, contexte) {
  const regles = [];
  const r = (chemin, regle) => regles.push(`${chemin} : ${regle}`);
  if (!STATUTS.includes(data.status)) {
    r("status", "valeur hors de la liste");
    return regles;
  }
  const descripteurs = data.descriptors;
  regles.push(...reglesDescripteurs(descripteurs, LIBELLES));
  if (!estObjet(data.texts)) {
    r("texts", "objet attendu");
    return regles;
  }
  for (const [k, v] of Object.entries(data.texts)) {
    if (!TEXTES_LEVURE.includes(k)) r("texts", `texte non permis ${k}`);
    else regles.push(...reglesBlocTexte(`texts.${k}`, v));
  }
  const styles = data.styles;
  if (!Array.isArray(styles)) {
    r("styles", "liste attendue");
    return regles;
  }
  if (styles.length > STYLES_MAX) r("styles", `${STYLES_MAX} au plus`);
  const vus = new Set();
  styles.forEach((s, i) => {
    const c = `styles[${i}]`;
    if (!estObjet(s) || Object.keys(s).sort().join(",") !== "code,name") {
      r(c, "{code, name} attendu");
      return;
    }
    if (!contexte.noms.has(s.code)) r(`${c}.code`, "style absent de beer_styles.json");
    else if (s.name !== contexte.noms.get(s.code)) r(`${c}.name`, "différent du nom du style");
    if (vus.has(s.code)) r(`${c}.code`, "en double");
    vus.add(s.code);
  });
  if (data.status === "described") {
    if (!CONFIANCES.includes(data.confidence)) r("confidence", "high, medium ou low attendu");
    const n = Array.isArray(descripteurs) ? descripteurs.length : 0;
    if (n < DESCRIPTEURS_MIN || n > DESCRIPTEURS_MAX) {
      r("descriptors", `${DESCRIPTEURS_MIN} à ${DESCRIPTEURS_MAX} entrées attendues`);
    }
    if (!("profile" in data.texts)) r("texts.profile", "obligatoire pour described");
  } else {
    if ("confidence" in data) r("confidence", "absente attendue pour unknown");
    if (Array.isArray(descripteurs) && descripteurs.length > 0) {
      r("descriptors", "vide attendu pour unknown");
    }
    if (Object.keys(data.texts).length > 0) r("texts", "aucun texte attendu pour unknown");
    if (styles.length > 0) r("styles", "vide attendu pour unknown");
  }
  return regles;
}

const CLES_ENTREE = [
  "culture_name",
  "status",
  "confidence",
  "descriptors",
  "texts",
  "styles",
  "reviewed",
  "reviewed_at",
  "provenance",
  "input_sha256",
];
const CLES_OBLIGATOIRES = CLES_ENTREE.filter((k) => k !== "confidence" && k !== "reviewed_at");

/// Erreurs d'une entrée de levures/aromes.json ([doc] `{id, data}`), liste vide si elle est
/// bonne. [contexte] : styles de beer_styles.json préparé (contexteStyles). Mêmes règles au
/// générateur et à l'écrivain.
export function controlerEntreeAromeLevure(doc, contexte) {
  const erreurs = [];
  const r = (chemin, regle) => erreurs.push(`${chemin} : ${regle}`);
  if (!estObjet(doc) || typeof doc.id !== "string" || !estObjet(doc.data)) {
    return ["document : {id, data} attendu"];
  }
  if (doc.id.length > 200 || !ID_LEVURE.test(doc.id)) r("id", "identifiant de levure attendu");
  const d = doc.data;
  for (const k of Object.keys(d)) if (!CLES_ENTREE.includes(k)) r("data", `clé non permise ${k}`);
  for (const k of CLES_OBLIGATOIRES) if (!(k in d)) r("data", `clé absente ${k}`);
  if (erreurs.length > 0) return erreurs;
  if (
    typeof d.culture_name !== "string" ||
    longueur(d.culture_name) < 1 ||
    longueur(d.culture_name) > 120
  ) {
    r("culture_name", "texte de 1 à 120 caractères attendu");
  }
  erreurs.push(...reglesContenuLevure(d, contexte));
  erreurs.push(...reglesEnveloppe(doc, "levure", "identifiant de la levure attendu"));
  return erreurs;
}
