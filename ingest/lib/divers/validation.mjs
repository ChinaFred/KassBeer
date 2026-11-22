// Contrôle des descriptions des divers (ADR-018, section 3, P63), partagé par le générateur
// (generer-divers.mjs) et l'écrivain (ecrire.mjs). N'importe pas le SDK d'Anthropic :
// ecrire.mjs et les tests chargent ce fichier sans lui (P54). Les règles de texte et les
// empreintes communes aux natures viennent de lib/redaction/texte.mjs.
//
// Une erreur est un chemin et une règle, jamais le texte contrôlé : les rapports ne
// recopient aucun texte rendu par le modèle.

import { readFileSync } from "node:fs";
import { reglesEnveloppe } from "../redaction/entree.mjs";
import {
  formeControlee,
  jsonCanonique,
  nettoyerTexte,
  reglesTexte,
  sha256,
} from "../redaction/texte.mjs";

/// Collection écrite par ecrire.mjs depuis import/ingest/divers/descriptions.json.
export const COLLECTION_DIVERS = "beer_misc_descriptions";

/// Les cinq moments de l'éditeur de recette (OtherUse, ADR-018, décision 3), dans l'ordre
/// d'affichage de la fiche. Le traitement de l'eau de brassage ou de rinçage est rangé sous
/// `mash`.
export const MOMENTS = ["mash", "boil", "after_boil", "fermentation", "bottling"];

export const STATUTS = ["described", "unknown"];
export const CONFIANCES = ["high", "medium", "low"];

/// Nombre de rôles d'une entrée `described`.
export const ROLES_MIN = 1;
export const ROLES_MAX = 3;

/// Bornes du résumé, en caractères ; les autres textes suivent TEXTE_MIN et TEXTE_MAX.
export const RESUME_MIN = 40;
export const RESUME_MAX = 300;

/// Liste fermée des rôles (`{key, label}`), lue une fois. Seul endroit où elle vit : le
/// document porte le libellé, l'application ne fait que l'afficher.
export const ROLES = JSON.parse(readFileSync(new URL("./roles.json", import.meta.url), "utf8"));

const LIBELLES = new Map(ROLES.map((d) => [d.key, d.label]));

/// Identifiant d'un divers de beer_miscs/.
export const ID_DIVERS = /^misc-[a-z0-9]+(-[a-z0-9]+)*$/;

// Unités de dose refusées (ADR-018, décision 1, liste élargie par la décision de
// l'utilisateur du 2026-11-21) : symboles et mots, les plus longs d'abord.
const UNITES_DOSE =
  "(?:g\\s*/\\s*l|ppm|ppb|kilogrammes?|milligrammes?|grammes?|centilitres?|d[ée]cilitres?|" +
  "hectolitres?|millilitres?|litres?|onces?|cuill[eè]res?|cuil\\.?|c\\.\\s*[àa]\\.?\\s*(?:caf[ée]|soupe|c\\.?|s\\.?)|c\\s+à\\s*(?:caf[ée]|soupe)|" +
  "sachets?|pastilles?|gouttes?|comprim[ée]s?|tablettes?|capsules?|dosettes?|tbsps?|tsps?|" +
  "pour[\\s-]*cent|kgs?|mgs?|cls?|dls?|hls?|mls?|grs?|ozs?|g|l|%)";

// Nombres écrits en lettres : un ou une à vingt, dizaines jusqu'à soixante, cent, mille, demi,
// quart ; combinés par une espace, un trait d'union ou « et » (« dix-sept », « quatre-vingts »,
// « un demi »).
const NOMBRE_LETTRES =
  "(?:une?|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|treize|quatorze|" +
  "quinze|seize|vingts?|trente|quarante|cinquante|soixante|cents?|milles?|demie?|quarts?)";

// Une lettre ou une apostrophe juste après l'unité la rend inopérante (« 2 lots »,
// « 5,2 l'hiver »).
const FIN_UNITE = "(?![\\p{L}'’])";

/// Nombre en chiffres suivi d'une unité de dose (« 2 g/l », « 80 % », « 1,5 kg »).
const DOSE_CHIFFRES = new RegExp(`\\d(?:[.,]\\d+)?\\s*(?:-\\s*)?${UNITES_DOSE}${FIN_UNITE}`, "iu");

/// Nombre en lettres suivi d'une unité de dose (« cinq grammes », « un demi sachet »,
/// « un quart de sachet »).
const DOSE_LETTRES = new RegExp(
  `(?<![\\p{L}])${NOMBRE_LETTRES}(?:(?:\\s*-\\s*|\\s+et\\s+|\\s+)${NOMBRE_LETTRES})*` +
    `(?:\\s+|\\s*-\\s*)(?:(?:de|d['’])\\s*)?${UNITES_DOSE}${FIN_UNITE}`,
  "giu",
);

/// « un sachet » et « une sachet » seuls : un contenant (infusion en cuve), pas une dose
/// (décision de l'utilisateur du 2026-11-22). « un demi sachet », « deux sachets » restent
/// des doses, comme « un sachet » suivi d'une quantité ou d'un rapport : SUITE_QUANTITE
/// (décisions de l'utilisateur du 2026-11-22, après deux relectures de securite). Une barre
/// oblique (« / », « ⁄ », « ∕ », « ⧸ »), « × », « + » ou un chiffre (« 2x », « ½ ») juste après comptent ; sinon toute
/// ponctuation et tout symbole sont sautés avant le mot de liaison (« (ou deux) », « — voire
/// deux », « : par brassin »), puis « et » suivi d'un nombre (« et demi », « et quart », « et un »,
/// « et deux », « et 1/2 »), « ou », « voire », « à », « par », « pour », « fois », « x » suivi d'un
/// nombre (« x2 », « x deux ») et un nombre suivi de « fois » (« deux fois », « 3 fois ») comptent.
const SACHET_CONTENANT = /^une?\s+sachet$/iu;
/// Fin de phrase : « . », « ! » ou « ? » suivi d'une espace et d'une majuscule. La phrase
/// suivante n'est pas lue (« Dans un sachet. À la fin, retirer. » accepté ; décision de
/// l'utilisateur du 2026-11-22).
const FIN_PHRASE = /[.!?]\s+(?=\p{Lu})/u;
const SUITE_SYMBOLE = /^\s*[/⁄∕⧸×+\d]/u;
const SUITE_QUANTITE = new RegExp(
  `^[\\s\\p{P}\\p{S}]*(?:et\\s+(?:demie?|quarts?|\\d|${NOMBRE_LETTRES})|ou|voire|à|par|pour|fois|x\\s*\\d|` +
    `x\\s+${NOMBRE_LETTRES}|\\d+\\s*fois|${NOMBRE_LETTRES}\\s+fois)(?![\\p{L}])`,
  "iu",
);

const estObjet = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const longueur = (t) => [...t].length;

/// Vrai si [texte] contient une dose : nombre en chiffres ou en lettres suivi d'une unité de
/// dose, contrôlé sur la forme nettoyée et NFKC (« ５ g », « 5\u200Bg »).
export function contientDose(texte) {
  const t = formeControlee(texte);
  if (DOSE_CHIFFRES.test(t)) return true;
  // DOSE_LETTRES porte le drapeau `g` pour matchAll : ne pas l'employer avec .test ou .exec.
  for (const m of t.matchAll(DOSE_LETTRES)) {
    if (!SACHET_CONTENANT.test(m[0])) return true;
    const suite = t.slice(m.index + m[0].length).split(FIN_PHRASE)[0];
    if (SUITE_SYMBOLE.test(suite) || SUITE_QUANTITE.test(suite)) return true;
  }
  return false;
}

/// Règles d'un texte de divers : celles de texte.mjs, plus le refus d'une dose.
export function reglesTexteDivers(texte, bornes) {
  const regles = reglesTexte(texte, bornes);
  if (contientDose(texte)) regles.push("dose chiffrée");
  return regles;
}

/// Données d'un divers envoyées au modèle (ADR-018, section 2), tirées de `beer_miscs/{id}`
/// préparé : rien d'autre ne part.
export function donneesEnvoyees(data) {
  return {
    name: data.name,
    aliases: Array.isArray(data.aliases) ? data.aliases : [],
    label_fr: data.label_fr ?? null,
    type: data.type ?? null,
  };
}

/// Empreinte des entrées d'une génération : données envoyées, version du prompt, modèle,
/// effort (comme ADR-013, clé `misc`).
export function empreinteEntree(donnees, { promptVersion, modele, effort }) {
  return sha256(
    jsonCanonique({ misc: donnees, prompt_version: promptVersion, model: modele, effort }),
  );
}

const CLES_SORTIE = [
  "status",
  "confidence",
  "summary",
  "roles",
  "moments",
  "changes_taste",
  "taste",
];

/// Contrôle de la sortie structurée du modèle ([sortie], objet déjà décodé). Rend
/// `{regles, resultat}` : `regles` vide et `resultat` (rôles `{key, label}`, textes nettoyés
/// en `{text}`, valeurs null retirées) si la sortie est bonne.
export function controlerSortieModele(sortie) {
  const regles = [];
  const r = (chemin, regle) => regles.push(`${chemin} : ${regle}`);
  if (!estObjet(sortie)) return { regles: ["sortie : objet attendu"], resultat: null };
  for (const k of Object.keys(sortie)) {
    if (!CLES_SORTIE.includes(k)) r("sortie", `clé non permise ${k}`);
  }
  for (const k of CLES_SORTIE) if (!(k in sortie)) r("sortie", `clé absente ${k}`);
  if (!STATUTS.includes(sortie.status)) r("status", "valeur hors de la liste");
  if (!estObjet(sortie.moments)) r("moments", "objet attendu");
  if (!Array.isArray(sortie.roles)) r("roles", "liste attendue");
  for (const k of ["summary", "taste"]) {
    if (sortie[k] !== null && typeof sortie[k] !== "string") r(k, "texte ou null attendu");
  }
  if (sortie.changes_taste !== null && typeof sortie.changes_taste !== "boolean") {
    r("changes_taste", "booléen ou null attendu");
  }
  if (regles.length > 0) return { regles, resultat: null };

  const moments = {};
  for (const [k, v] of Object.entries(sortie.moments)) {
    if (!MOMENTS.includes(k)) {
      r("moments", `moment non permis ${k}`);
    } else if (v !== null) {
      if (typeof v !== "string") r(`moments.${k}`, "texte ou null attendu");
      else moments[k] = { text: nettoyerTexte(v) };
    }
  }
  const resultat = { status: sortie.status, roles: [], moments: {} };
  if (sortie.status === "described") {
    if (sortie.confidence !== null) resultat.confidence = sortie.confidence;
    if (sortie.summary !== null) resultat.summary = nettoyerTexte(sortie.summary);
    resultat.roles = sortie.roles.map((key) => ({ key, label: LIBELLES.get(key) }));
    resultat.moments = moments;
    if (sortie.changes_taste !== null) resultat.changes_taste = sortie.changes_taste;
    if (sortie.taste !== null) resultat.taste = { text: nettoyerTexte(sortie.taste) };
  } else {
    for (const k of ["confidence", "summary", "changes_taste", "taste"]) {
      if (sortie[k] !== null) r(k, "null attendu pour unknown");
    }
    if (sortie.roles.length > 0) r("roles", "vide attendu pour unknown");
    if (Object.keys(moments).length > 0) r("moments", "aucun texte attendu pour unknown");
  }
  regles.push(...reglesContenu(resultat));
  return { regles, resultat: regles.length === 0 ? resultat : null };
}

/// Règles d'un champ `{text}` au [chemin].
function reglesBloc(chemin, v, r) {
  if (!estObjet(v) || Object.keys(v).join(",") !== "text" || typeof v.text !== "string") {
    r(chemin, "{text} attendu");
    return;
  }
  if (v.text !== nettoyerTexte(v.text)) r(`${chemin}.text`, "texte non nettoyé (NFC, contrôles)");
  for (const regle of reglesTexteDivers(v.text)) r(`${chemin}.text`, regle);
}

/// Règles de `status`, `confidence`, `summary`, `roles`, `moments`, `changes_taste` et
/// `taste` d'une entrée.
function reglesContenu(data) {
  const regles = [];
  const r = (chemin, regle) => regles.push(`${chemin} : ${regle}`);
  if (!STATUTS.includes(data.status)) {
    r("status", "valeur hors de la liste");
    return regles;
  }
  const roles = data.roles;
  if (!Array.isArray(roles)) {
    r("roles", "liste attendue");
  } else {
    const vus = new Set();
    roles.forEach((d, i) => {
      const c = `roles[${i}]`;
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
  if (!estObjet(data.moments)) {
    r("moments", "objet attendu");
    return regles;
  }
  for (const [k, v] of Object.entries(data.moments)) {
    if (!MOMENTS.includes(k)) {
      r("moments", `moment non permis ${k}`);
      continue;
    }
    reglesBloc(`moments.${k}`, v, r);
  }
  if ("summary" in data) {
    if (typeof data.summary !== "string") {
      r("summary", "texte attendu");
    } else {
      if (data.summary !== nettoyerTexte(data.summary)) {
        r("summary", "texte non nettoyé (NFC, contrôles)");
      }
      for (const regle of reglesTexteDivers(data.summary, { min: RESUME_MIN, max: RESUME_MAX })) {
        r("summary", regle);
      }
    }
  }
  if ("taste" in data) reglesBloc("taste", data.taste, r);
  if (data.status === "described") {
    if (!CONFIANCES.includes(data.confidence)) r("confidence", "high, medium ou low attendu");
    if (!("summary" in data)) r("summary", "résumé attendu");
    const n = Array.isArray(roles) ? roles.length : 0;
    if (n < ROLES_MIN || n > ROLES_MAX) r("roles", `${ROLES_MIN} à ${ROLES_MAX} entrées attendues`);
    if (Object.keys(data.moments).length === 0) r("moments", "au moins un moment attendu");
    if (typeof data.changes_taste !== "boolean") r("changes_taste", "booléen attendu");
    else if (data.changes_taste && !("taste" in data)) r("taste", "attendu si changes_taste");
    else if (!data.changes_taste && "taste" in data)
      r("taste", "absent attendu sans changes_taste");
  } else {
    for (const k of ["confidence", "summary", "changes_taste", "taste"]) {
      if (k in data) r(k, "absent attendu pour unknown");
    }
    if (Array.isArray(roles) && roles.length > 0) r("roles", "vide attendu pour unknown");
    if (Object.keys(data.moments).length > 0) r("moments", "aucun texte attendu pour unknown");
  }
  return regles;
}

const CLES_ENTREE = [
  "misc_name",
  ...CLES_SORTIE,
  "reviewed",
  "reviewed_at",
  "provenance",
  "input_sha256",
];
const CLES_OBLIGATOIRES = [
  "misc_name",
  "status",
  "roles",
  "moments",
  "reviewed",
  "provenance",
  "input_sha256",
];

/// Erreurs d'une entrée de descriptions.json ([doc] `{id, data}`), liste vide si elle est
/// bonne. Mêmes règles au générateur, avant l'écriture de descriptions.json, et à
/// l'écrivain, avant Firestore.
export function controlerEntreeDivers(doc) {
  const erreurs = [];
  const r = (chemin, regle) => erreurs.push(`${chemin} : ${regle}`);
  if (!estObjet(doc) || typeof doc.id !== "string" || !estObjet(doc.data)) {
    return ["document : {id, data} attendu"];
  }
  if (doc.id.length > 200 || !ID_DIVERS.test(doc.id)) r("id", "identifiant de divers attendu");
  const d = doc.data;
  for (const k of Object.keys(d)) if (!CLES_ENTREE.includes(k)) r("data", `clé non permise ${k}`);
  for (const k of CLES_OBLIGATOIRES) if (!(k in d)) r("data", `clé absente ${k}`);
  if (erreurs.length > 0) return erreurs;
  if (typeof d.misc_name !== "string" || longueur(d.misc_name) < 1 || longueur(d.misc_name) > 120) {
    r("misc_name", "texte de 1 à 120 caractères attendu");
  }
  erreurs.push(...reglesContenu(d));
  erreurs.push(...reglesEnveloppe(doc, "divers"));
  return erreurs;
}
