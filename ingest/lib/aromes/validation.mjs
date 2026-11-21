// Contrôle des descriptions aromatiques des houblons (ADR-013, section 4), partagé par le
// générateur (generer-aromes.mjs) et l'écrivain (ecrire.mjs). N'importe pas le SDK
// d'Anthropic : ecrire.mjs et les tests chargent ce fichier sans lui (P54). Les règles de
// texte et les empreintes communes aux natures viennent de lib/redaction/texte.mjs (ADR-018).
//
// Une erreur est un chemin et une règle, jamais le texte contrôlé : les rapports ne
// recopient aucun texte rendu par le modèle.

import { readFileSync } from "node:fs";
import { reglesEnveloppe } from "../redaction/entree.mjs";
import { jsonCanonique, nettoyerTexte, reglesTexte, sha256 } from "../redaction/texte.mjs";

/// Collection écrite par ecrire.mjs depuis import/ingest/aromes/aromes.json.
export const COLLECTION_AROMES = "beer_hop_aromas";

/// Les cinq usages d'un houblon (ADR-013, décision 4), dans l'ordre d'affichage de la fiche :
/// premier moût, amérisant, fin d'ébullition, whirlpool, houblonnage à cru.
export const USAGES = ["first_wort", "bittering", "late_boil", "whirlpool", "dry_hop"];

export const STATUTS = ["described", "unknown"];
export const CONFIANCES = ["high", "medium", "low"];

/// Nombre de descripteurs d'une entrée `described`.
export const DESCRIPTEURS_MIN = 1;
export const DESCRIPTEURS_MAX = 8;

/// Liste fermée des descripteurs (`{key, label}`), lue une fois. Seul endroit où elle vit :
/// le document porte le libellé, l'application ne fait que l'afficher.
export const DESCRIPTEURS = JSON.parse(
  readFileSync(new URL("./descripteurs.json", import.meta.url), "utf8"),
);

const LIBELLES = new Map(DESCRIPTEURS.map((d) => [d.key, d.label]));

/// Identifiant d'un houblon de beer_hops/.
export const ID_HOUBLON = /^hop-[a-z0-9]+(-[a-z0-9]+)*$/;

const estObjet = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const longueur = (t) => [...t].length;

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
  erreurs.push(...reglesEnveloppe(doc, "houblon"));
  return erreurs;
}
