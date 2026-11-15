// Contrôle des descriptions aromatiques des houblons (ADR-013, section 4), partagé par le
// générateur (generer-aromes.mjs) et l'écrivain (ecrire.mjs). N'importe pas le SDK
// d'Anthropic : ecrire.mjs et les tests chargent ce fichier sans lui (P54).
//
// Une erreur est un chemin et une règle, jamais le texte contrôlé : les rapports ne
// recopient aucun texte rendu par le modèle.

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

/// Collection écrite par ecrire.mjs depuis import/ingest/aromes/aromes.json.
export const COLLECTION_AROMES = "beer_hop_aromas";

/// Les cinq usages d'un houblon (ADR-013, décision 4), dans l'ordre d'affichage de la fiche :
/// premier moût, amérisant, fin d'ébullition, whirlpool, houblonnage à cru.
export const USAGES = ["first_wort", "bittering", "late_boil", "whirlpool", "dry_hop"];

export const STATUTS = ["described", "unknown"];
export const CONFIANCES = ["high", "medium", "low"];
export const EFFORTS = ["low", "medium", "high", "xhigh", "max"];

/// Bornes d'un texte d'usage, en caractères (points de code).
export const TEXTE_MIN = 40;
export const TEXTE_MAX = 400;

/// Nombre de descripteurs d'une entrée `described`.
export const DESCRIPTEURS_MIN = 1;
export const DESCRIPTEURS_MAX = 8;

/// Ligne de provenance d'une entrée générée.
export const SOURCE_PROVENANCE = "claude-api";
export const LICENCE_PROVENANCE = "Texte généré pour Kass'Beer";

/// Liste fermée des descripteurs (`{key, label}`), lue une fois. Seul endroit où elle vit :
/// le document porte le libellé, l'application ne fait que l'afficher.
export const DESCRIPTEURS = JSON.parse(
  readFileSync(new URL("./descripteurs.json", import.meta.url), "utf8"),
);

const LIBELLES = new Map(DESCRIPTEURS.map((d) => [d.key, d.label]));

const ID_HOUBLON = /^hop-[a-z0-9]+(-[a-z0-9]+)*$/;
const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const VERSION = new RegExp(
  `^claude-[a-z0-9-]{1,60} / prompt [1-9][0-9]{0,3} / effort (${EFFORTS.join("|")})$`,
);

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

/// Règles enfreintes par un texte d'usage déjà nettoyé (liste vide s'il est bon). Une
/// comparaison à un autre houblon est permise (ADR-013, décision 8).
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

/// Données d'un houblon envoyées au modèle (ADR-013, section 3), tirées de
/// `beer_hops/{id}` préparé : rien d'autre ne part.
export function donneesEnvoyees(data) {
  return {
    name: data.name,
    aliases: Array.isArray(data.aliases) ? data.aliases : [],
    origin: data.origin ?? null,
    alpha_acid_pct: data.alpha_acid?.value ?? null,
    beta_acid_pct: data.beta_acid?.value ?? null,
    purpose: data.purpose ?? null,
  };
}

/// Empreinte des entrées d'une génération : données envoyées, version du prompt, modèle,
/// effort (ADR-013, « Idempotence »).
export function empreinteEntree(donnees, { promptVersion, modele, effort }) {
  return sha256(
    jsonCanonique({ hop: donnees, prompt_version: promptVersion, model: modele, effort }),
  );
}

/// Empreinte du contenu d'une entrée de aromes.json, calculée par ecrire.mjs.
export function empreinteContenu(data) {
  return sha256(jsonCanonique(data));
}

/// Contrôle de la sortie structurée du modèle ([sortie], objet déjà décodé). Rend
/// `{regles, resultat}` : `regles` vide et `resultat` `{status, confidence?, descriptors,
/// uses}` (descripteurs `{key, label}`, textes nettoyés) si la sortie est bonne.
export function controlerSortieModele(sortie) {
  const regles = [];
  const r = (chemin, regle) => regles.push(`${chemin} : ${regle}`);
  const cles = ["status", "confidence", "descriptors", "uses"];
  if (!estObjet(sortie)) return { regles: ["sortie : objet attendu"], resultat: null };
  for (const k of Object.keys(sortie)) if (!cles.includes(k)) r("sortie", `clé non permise ${k}`);
  for (const k of cles) if (!(k in sortie)) r("sortie", `clé absente ${k}`);
  if (!STATUTS.includes(sortie.status)) r("status", "valeur hors de la liste");
  if (!estObjet(sortie.uses)) r("uses", "objet attendu");
  if (!Array.isArray(sortie.descriptors)) r("descriptors", "liste attendue");
  if (regles.length > 0) return { regles, resultat: null };

  const uses = {};
  for (const [k, v] of Object.entries(sortie.uses)) {
    if (!USAGES.includes(k)) {
      r("uses", `usage non permis ${k}`);
    } else if (v !== null) {
      if (typeof v !== "string") r(`uses.${k}`, "texte ou null attendu");
      else uses[k] = { text: nettoyerTexte(v) };
    }
  }
  const resultat = { status: sortie.status, descriptors: [], uses: {} };
  if (sortie.status === "described") {
    if (sortie.confidence !== null) resultat.confidence = sortie.confidence;
    resultat.descriptors = sortie.descriptors.map((key) => ({ key, label: LIBELLES.get(key) }));
    resultat.uses = uses;
  } else {
    if (sortie.confidence !== null) r("confidence", "null attendu pour unknown");
    if (sortie.descriptors.length > 0) r("descriptors", "vide attendu pour unknown");
    if (Object.keys(uses).length > 0) r("uses", "aucun texte attendu pour unknown");
  }
  regles.push(...reglesContenu(resultat));
  return { regles, resultat: regles.length === 0 ? resultat : null };
}

/// Règles de `status`, `confidence`, `descriptors` et `uses` d'une entrée.
function reglesContenu(data) {
  const regles = [];
  const r = (chemin, regle) => regles.push(`${chemin} : ${regle}`);
  if (!STATUTS.includes(data.status)) {
    r("status", "valeur hors de la liste");
    return regles;
  }
  const descripteurs = data.descriptors;
  if (!Array.isArray(descripteurs)) {
    r("descriptors", "liste attendue");
  } else {
    const vus = new Set();
    descripteurs.forEach((d, i) => {
      const c = `descriptors[${i}]`;
      if (!estObjet(d) || Object.keys(d).sort().join(",") !== "key,label") {
        r(c, "{key, label} attendu");
        return;
      }
      if (!LIBELLES.has(d.key)) r(`${c}.key`, "hors de la liste fermée");
      else if (d.label !== LIBELLES.get(d.key)) r(`${c}.label`, "différent de la liste");
      if (vus.has(d.key)) r(`${c}.key`, "en double");
      vus.add(d.key);
    });
  }
  if (!estObjet(data.uses)) {
    r("uses", "objet attendu");
    return regles;
  }
  for (const [k, v] of Object.entries(data.uses)) {
    const c = `uses.${k}`;
    if (!USAGES.includes(k)) {
      r("uses", `usage non permis ${k}`);
      continue;
    }
    if (!estObjet(v) || Object.keys(v).join(",") !== "text" || typeof v.text !== "string") {
      r(c, "{text} attendu");
      continue;
    }
    if (v.text !== nettoyerTexte(v.text)) r(`${c}.text`, "texte non nettoyé (NFC, contrôles)");
    for (const regle of reglesTexte(v.text)) r(`${c}.text`, regle);
  }
  if (data.status === "described") {
    if (!CONFIANCES.includes(data.confidence)) r("confidence", "high, medium ou low attendu");
    const n = Array.isArray(descripteurs) ? descripteurs.length : 0;
    if (n < DESCRIPTEURS_MIN || n > DESCRIPTEURS_MAX) {
      r("descriptors", `${DESCRIPTEURS_MIN} à ${DESCRIPTEURS_MAX} entrées attendues`);
    }
    if (Object.keys(data.uses).length === 0) r("uses", "au moins un usage attendu");
  } else {
    if ("confidence" in data) r("confidence", "absente attendue pour unknown");
    if (Array.isArray(descripteurs) && descripteurs.length > 0) {
      r("descriptors", "vide attendu pour unknown");
    }
    if (Object.keys(data.uses).length > 0) r("uses", "aucun texte attendu pour unknown");
  }
  return regles;
}

const CLES_ENTREE = [
  "hop_name",
  "status",
  "confidence",
  "descriptors",
  "uses",
  "reviewed",
  "reviewed_at",
  "provenance",
  "input_sha256",
];
const CLES_OBLIGATOIRES = [
  "hop_name",
  "status",
  "descriptors",
  "uses",
  "reviewed",
  "provenance",
  "input_sha256",
];

/// Erreurs d'une entrée de aromes.json ([doc] `{id, data}`), liste vide si elle est bonne.
/// Mêmes règles au générateur, avant l'écriture de aromes.json, et à l'écrivain, avant
/// Firestore.
export function controlerEntreeArome(doc) {
  const erreurs = [];
  const r = (chemin, regle) => erreurs.push(`${chemin} : ${regle}`);
  if (!estObjet(doc) || typeof doc.id !== "string" || !estObjet(doc.data)) {
    return ["document : {id, data} attendu"];
  }
  if (doc.id.length > 200 || !ID_HOUBLON.test(doc.id)) r("id", "identifiant de houblon attendu");
  const d = doc.data;
  for (const k of Object.keys(d)) if (!CLES_ENTREE.includes(k)) r("data", `clé non permise ${k}`);
  for (const k of CLES_OBLIGATOIRES) if (!(k in d)) r("data", `clé absente ${k}`);
  if (erreurs.length > 0) return erreurs;
  if (typeof d.hop_name !== "string" || longueur(d.hop_name) < 1 || longueur(d.hop_name) > 120) {
    r("hop_name", "texte de 1 à 120 caractères attendu");
  }
  erreurs.push(...reglesContenu(d));
  if (typeof d.reviewed !== "boolean") r("reviewed", "booléen attendu");
  if (d.reviewed === true && !estDate(d.reviewed_at)) {
    r("reviewed_at", "date AAAA-MM-JJ attendue pour une entrée relue");
  }
  if (d.reviewed === false && "reviewed_at" in d) r("reviewed_at", "absente attendue si non relue");
  if (!/^[0-9a-f]{64}$/.test(d.input_sha256 ?? "")) r("input_sha256", "64 hexadécimaux attendus");
  const p = d.provenance;
  if (!Array.isArray(p) || p.length !== 1 || !estObjet(p[0])) {
    r("provenance", "une ligne attendue");
  } else {
    const l = p[0];
    const cles = ["source", "source_id", "version", "licence", "retrieved"];
    if (Object.keys(l).sort().join(",") !== [...cles].sort().join(",")) {
      r("provenance[0]", "clés source, source_id, version, licence, retrieved attendues");
    } else {
      if (l.source !== SOURCE_PROVENANCE) r("provenance[0].source", `${SOURCE_PROVENANCE} attendu`);
      if (l.source_id !== doc.id) r("provenance[0].source_id", "identifiant du houblon attendu");
      if (typeof l.version !== "string" || !VERSION.test(l.version)) {
        r("provenance[0].version", "« <modèle> / prompt <n> / effort <e> » attendu");
      }
      if (l.licence !== LICENCE_PROVENANCE) r("provenance[0].licence", "licence attendue");
      if (!estDate(l.retrieved)) r("provenance[0].retrieved", "date AAAA-MM-JJ attendue");
    }
  }
  return erreurs;
}
