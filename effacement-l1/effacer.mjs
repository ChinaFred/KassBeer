#!/usr/bin/env node
// Effacement des recettes et des brassins avant le passage au modèle BeerJSON (ADR-005,
// « Calendrier et passage en production », livraison L1). Outil à usage unique : il sort
// du dépôt à la livraison suivante.
//
//   node effacer.mjs rapport --projet <id>
//   node effacer.mjs effacer --projet <id> [--sauvegarde <dossier>]
//
// Lancer la commande depuis PowerShell ou Windows Terminal. Sous Git Bash (mintty),
// `process.stdin.isTTY` peut manquer : l'outil ne voit pas de terminal et refuse
// l'effacement en production.
//
// `rapport` lit sans rien écrire : nombre de recettes, chaque brassin avec son statut, sa
// date, son nombre d'événements et son coût figé (users/{owner_uid}/brew_costs/{id}), les
// événements orphelins (brassin absent) et les documents hors modèle.
// `effacer` refait le rapport, refuse si un brassin est en cours (`brewing`) ou si un
// document est hors modèle, copie recipes/ et brews/ (événements compris) en JSON dans
// import/backup/, demande le nom du projet, refait le rapport et refuse si un document a
// changé depuis la copie, efface recipes/ et brews/ par recursiveDelete et les coûts figés
// un par un, puis vérifie que equipment/, users/ (hors des coûts effacés), members/ et
// error_reports/ ont gardé le même nombre de documents.
//
// Aucun document sous users/ n'est lu avec ses champs (décision du 2026-11-10) : les coûts
// figés et les autres documents des comptes se lisent sans champ (fieldMask vide), pour
// leur existence et leur date de modification. Aucun prix ne passe par l'outil, et les
// coûts figés effacés ne sont pas dans la copie.
//
// Identifiants : `gcloud auth application-default login`. Une clé JSON
// (GOOGLE_APPLICATION_CREDENTIALS) est refusée. Cibles permises : le projet kassbeer, ou
// un projet demo- avec FIRESTORE_EMULATOR_HOST (l'outil parle alors à l'émulateur et à lui
// seul). En production, la confirmation se tape dans un terminal : une entrée standard
// redirigée est refusée. Une sauvegarde dans un arbre Git est refusée, sauf dans import/ de
// ce dépôt, que son .gitignore ignore.
//
// Codes de sortie : 0 fait, 1 usage ou lancement refusé, 2 brassin en cours, 3 nom du
// projet refusé, 4 collection protégée modifiée ou effacement incomplet, 5 document hors
// modèle, ou recipes/, brews/ et coûts figés différents de la copie.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

/// Collections effacées.
export const EFFACEES = ["recipes", "brews"];

/// Collections qui ne doivent pas changer.
export const PROTEGEES = ["equipment", "users", "members", "error_reports"];

/// Projet de production, seul projet réel permis.
export const PROJET_PRODUCTION = "kassbeer";

const RACINE_DEPOT = resolve(fileURLToPath(new URL("../", import.meta.url)));
const DOSSIER_SAUVEGARDE = join(RACINE_DEPOT, "import", "backup");

export class Refus extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

export function lireArguments(argv) {
  const [commande, ...reste] = argv;
  const options = {};
  for (let i = 0; i < reste.length; i += 2) {
    const cle = reste[i];
    const valeur = reste[i + 1];
    if (!cle?.startsWith("--") || valeur === undefined) {
      throw new Refus(1, `Argument illisible : ${cle ?? ""}`);
    }
    options[cle.slice(2)] = valeur;
  }
  if (!["rapport", "effacer"].includes(commande) || !options.projet) {
    throw new Refus(
      1,
      "Usage : node effacer.mjs rapport --projet <id>\n" +
        "        node effacer.mjs effacer --projet <id> [--sauvegarde <dossier>]",
    );
  }
  return { commande, projet: options.projet, sauvegarde: options.sauvegarde };
}

/// Contrôles faits avant toute connexion. [env] : variables d'environnement ; [tty] :
/// vrai si l'entrée standard est un terminal. Rend le dossier de sauvegarde.
export function verifierLancement({ commande, projet, sauvegarde }, env, tty) {
  if (env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Refus(
      1,
      "GOOGLE_APPLICATION_CREDENTIALS posé : refusé. Aucune clé JSON ; identifiants par " +
        "gcloud auth application-default login.",
    );
  }
  const emulateur = env.FIRESTORE_EMULATOR_HOST;
  // Un projet demo- n'existe que dans l'émulateur : sans lui, c'est une erreur de
  // commande, pas une écriture en production.
  if (projet.startsWith("demo-")) {
    if (!emulateur) {
      throw new Refus(
        1,
        `Projet ${projet} sans FIRESTORE_EMULATOR_HOST : refusé.`,
      );
    }
  } else if (projet !== PROJET_PRODUCTION) {
    throw new Refus(
      1,
      `Projet ${projet} refusé : seuls ${PROJET_PRODUCTION} et un projet demo- avec ` +
        "FIRESTORE_EMULATOR_HOST sont permis.",
    );
  }
  const production = !emulateur;
  if (commande === "effacer" && production && !tty) {
    throw new Refus(
      1,
      "Effacement en production : le nom du projet se tape dans un terminal, entrée " +
        "standard redirigée refusée. Lancez la commande depuis PowerShell ou Windows " +
        "Terminal : Git Bash (mintty) n'est pas reconnu comme terminal.",
    );
  }
  return dossierSauvegarde(sauvegarde, projet);
}

/// Nom du fichier de la copie, horodaté.
export function nomCopie(projet, date = new Date()) {
  return `${projet}-${date.toISOString().replace(/[:.]/g, "-")}.json`;
}

/// Variables qui changent le dépôt que Git découvre : retirées pour que `rev-parse` et
/// `check-ignore` jugent le seul dossier de la copie.
const VARIABLES_GIT_ECARTEES = [
  "GIT_DIR",
  "GIT_WORK_TREE",
  "GIT_COMMON_DIR",
  "GIT_INDEX_FILE",
  "GIT_CEILING_DIRECTORIES",
  "GIT_DISCOVERY_ACROSS_FILESYSTEM",
];

function git(args) {
  const env = { ...process.env, LC_ALL: "C", LANGUAGE: "C" };
  for (const nom of VARIABLES_GIT_ECARTEES) delete env[nom];
  const r = spawnSync("git", args, { encoding: "utf8", env });
  if (r.error) {
    throw new Refus(
      1,
      `git introuvable (${r.error.message}) : sauvegarde refusée.`,
    );
  }
  return r;
}

/// Dossier de la copie : import/backup/ par défaut. Un dossier du dépôt hors de import/
/// est refusé : la copie contient des données du groupe, et import/ est ignoré par Git.
/// Dans un arbre Git, seul import/ de ce dépôt est accepté, et le fichier de la copie doit y
/// être ignoré (`git check-ignore`) ; un autre dépôt ou worktree est refusé.
export function dossierSauvegarde(sauvegarde, projet) {
  const dossier = sauvegarde ? resolve(sauvegarde) : DOSSIER_SAUVEGARDE;
  const egal = (a, b) =>
    process.platform === "win32"
      ? a.toLowerCase() === b.toLowerCase()
      : a === b;
  const chemin = relative(RACINE_DEPOT, dossier);
  const horsDepot =
    chemin === ".." || chemin.startsWith(`..${sep}`) || isAbsolute(chemin);
  const premier = chemin.split(sep)[0];
  if (!horsDepot && !egal(premier, "import")) {
    throw new Refus(
      1,
      `Sauvegarde dans le dépôt hors de import/ (${dossier}) : refusé.`,
    );
  }
  let existant = dossier;
  while (!existsSync(existant) && dirname(existant) !== existant)
    existant = dirname(existant);
  const arbre = git(["-C", existant, "rev-parse", "--show-toplevel"]);
  if (arbre.status !== 0) {
    // Seul « not a git repository » vaut « hors d'un arbre Git » (messages en anglais par
    // LC_ALL=C). Toute autre erreur est refusée : dépôt écarté pour son propriétaire
    // (safe.directory), chemin trop long pour git, dossier illisible.
    if (
      arbre.status !== 128 ||
      !/not a git repository/i.test(arbre.stderr) ||
      /safe\.directory/.test(arbre.stderr)
    ) {
      throw new Refus(
        1,
        `Sauvegarde dans ${dossier}, git rev-parse en échec (${arbre.stderr.trim()}) : refusé.`,
      );
    }
    return dossier;
  }
  // Dans un arbre Git, seul import/ de ce dépôt est accepté : son .gitignore versionné
  // l'ignore. Un autre dépôt ou worktree est refusé même si Git y ignore le dossier, car une
  // configuration Git de l'environnement (fichier d'exclusion global, GIT_CONFIG_*) peut
  // faire paraître ignoré un dossier suivi.
  const racine = resolve(arbre.stdout.trim());
  if (horsDepot || !egal(racine, resolve(RACINE_DEPOT))) {
    throw new Refus(
      1,
      `Sauvegarde dans l'arbre Git ${racine}, hors de import/ de ce dépôt (${dossier}) : refusé.`,
    );
  }
  const fichier = join(dossier, nomCopie(projet ?? "projet"));
  const ignore = git(["-C", existant, "check-ignore", "-q", "--", fichier]);
  if (ignore.status !== 0) {
    throw new Refus(
      1,
      `Sauvegarde dans l'arbre Git ${arbre.stdout.trim()}, fichier non ignoré par Git ` +
        `(${fichier}) : refusé.`,
    );
  }
  return dossier;
}

export function ouvrir(projet) {
  const emulateur = process.env.FIRESTORE_EMULATOR_HOST;
  const app = initializeApp(
    emulateur
      ? { projectId: projet }
      : { projectId: projet, credential: applicationDefault() },
    `effacement-${Date.now()}`,
  );
  return {
    db: getFirestore(app),
    cible: emulateur
      ? `émulateur ${emulateur}, projet ${projet}`
      : `PRODUCTION, projet ${projet}`,
  };
}

function dateDe(data) {
  for (const champ of ["brewed_at", "planned_for", "created_at"]) {
    if (data[champ] instanceof Timestamp) {
      return `${champ} ${data[champ].toDate().toISOString()}`;
    }
  }
  return "sans date";
}

/// Instantanés de [refs] lus sans aucun champ (fieldMask vide) : existence et date de
/// modification seules. Sert pour tout document sous users/ (coûts figés, prix).
async function lireSansChamp(db, refs) {
  if (refs.length === 0) return [];
  return db.getAll(...refs, { fieldMask: [] });
}

/// Documents présents sous [collection], sous-collections comprises, dans [documents]
/// (chemin → instantané). listDocuments rend aussi un document absent qui porte des
/// sous-collections (brassin effacé qui garde des events/) : ses descendants sont lus.
async function parcourir(collection, documents) {
  for (const ref of await collection.listDocuments()) {
    const snap = await ref.get();
    if (snap.exists) documents.set(ref.path, snap);
    for (const sous of await ref.listCollections())
      await parcourir(sous, documents);
  }
}

/// Identifiant de compte utilisable dans un chemin users/{uid}/… .
const uidLisible = (uid) =>
  typeof uid === "string" && uid !== "" && !uid.includes("/");

/// Compte rendu sans écriture. Rend aussi les documents lus de recipes/ et brews/
/// ([documents], chemin → instantané) et les coûts figés lus sans champ ([coutsFiges]) :
/// la copie, la relecture après la confirmation et l'effacement partent de ce relevé. Les
/// événements sont ceux de brews/{id}/events, jamais un collectionGroup("events"), qui
/// compterait aussi un events/ sous users/.
export async function rapport(db) {
  const documents = new Map();
  for (const nom of EFFACEES) await parcourir(db.collection(nom), documents);
  let recettes = 0;
  const ids = [];
  const evenements = new Map();
  const orphelins = [];
  const horsModele = [];
  for (const chemin of documents.keys()) {
    const [racine, id, sous, , ...reste] = chemin.split("/");
    if (sous === undefined) {
      if (racine === "recipes") recettes += 1;
      else ids.push(id);
    } else if (racine === "brews" && sous === "events" && reste.length === 0) {
      evenements.set(id, (evenements.get(id) ?? 0) + 1);
      if (!documents.has(`brews/${id}`)) orphelins.push(chemin);
    } else {
      horsModele.push(chemin);
    }
  }
  const refsCouts = ids.map((id) => {
    const uid = documents.get(`brews/${id}`).data().owner_uid;
    return uidLisible(uid) ? db.doc(`users/${uid}/brew_costs/${id}`) : null;
  });
  const coutsFiges = new Map();
  for (const snap of await lireSansChamp(db, refsCouts.filter(Boolean))) {
    if (snap.exists) coutsFiges.set(snap.ref.path, snap);
  }
  const brassins = [];
  const couts = [];
  for (const [i, id] of ids.entries()) {
    const data = documents.get(`brews/${id}`).data();
    let cout = "propriétaire illisible";
    const ref = refsCouts[i];
    if (ref) {
      const existe = coutsFiges.has(ref.path);
      cout = existe ? "coût figé" : "sans coût figé";
      if (existe) couts.push(ref.path);
    }
    brassins.push({
      id,
      statut: typeof data.status === "string" ? data.status : "illisible",
      date: dateDe(data),
      evenements: evenements.get(id) ?? 0,
      cout,
    });
  }
  let totalEvenements = 0;
  for (const n of evenements.values()) totalEvenements += n;
  return {
    recettes,
    brassins,
    evenements: totalEvenements,
    orphelins,
    horsModele,
    couts,
    documents,
    coutsFiges,
  };
}

export function afficherRapport(
  { recettes, brassins, orphelins, horsModele, couts },
  ecrire,
) {
  ecrire(`Recettes : ${recettes}`);
  ecrire(`Brassins : ${brassins.length}`);
  for (const b of brassins) {
    ecrire(
      `  ${b.id} · ${b.statut} · ${b.date} · ${b.evenements} événement(s) · ${b.cout}`,
    );
  }
  ecrire(`Coûts figés : ${couts.length}`);
  ecrire(`Événements orphelins (brassin absent) : ${orphelins.length}`);
  for (const chemin of orphelins) ecrire(`  ${chemin}`);
  if (horsModele.length > 0) {
    ecrire(`Documents hors modèle : ${horsModele.length}`);
    for (const chemin of horsModele) ecrire(`  ${chemin}`);
  }
}

/// Nombre de documents sous [collection], sous-collections comprises, hors des chemins
/// de [exclus]. Un document absent qui porte des sous-collections (users/{uid}) n'est
/// pas compté, ses sous-collections le sont. Les documents sont lus sans champ.
export async function compterArbre(collection, exclus = new Set()) {
  const refs = await collection.listDocuments();
  let total = 0;
  for (const snap of await lireSansChamp(collection.firestore, refs)) {
    if (!exclus.has(snap.ref.path) && snap.exists) total += 1;
  }
  for (const ref of refs) {
    for (const sous of await ref.listCollections())
      total += await compterArbre(sous, exclus);
  }
  return total;
}

/// Collections protégées ; users/ est compté hors des coûts figés à effacer ([exclus]).
export async function compterProtegees(db, exclus) {
  const comptes = {};
  for (const nom of PROTEGEES)
    comptes[nom] = await compterArbre(db.collection(nom), exclus);
  return comptes;
}

function enJson(valeur) {
  if (valeur instanceof Timestamp)
    return { __timestamp__: valeur.toDate().toISOString() };
  if (Array.isArray(valeur)) return valeur.map(enJson);
  if (valeur !== null && typeof valeur === "object") {
    return Object.fromEntries(
      Object.entries(valeur).map(([k, v]) => [k, enJson(v)]),
    );
  }
  return valeur;
}

/// Copie JSON des documents du relevé : recipes/ et brews/ (événements compris). Les
/// coûts figés n'y sont pas (décision du 2026-11-10). Rend le chemin du fichier.
export function sauvegarder(releve, projet, dossier) {
  const documents = {};
  for (const [chemin, snap] of releve.documents)
    documents[chemin] = enJson(snap.data());
  mkdirSync(dossier, { recursive: true });
  const fichier = join(dossier, nomCopie(projet));
  writeFileSync(fichier, `${JSON.stringify({ projet, documents }, null, 2)}\n`);
  return { fichier, nombre: Object.keys(documents).length };
}

/// Chemins ajoutés, retirés ou modifiés (updateTime) entre deux relevés, coûts figés
/// compris.
export function ecarts(avant, apres) {
  const tous = (r) => new Map([...r.documents, ...r.coutsFiges]);
  const [a, b] = [tous(avant), tous(apres)];
  const liste = [];
  for (const [chemin, snap] of a) {
    const autre = b.get(chemin);
    if (!autre) liste.push(`${chemin} retiré`);
    else if (!autre.updateTime.isEqual(snap.updateTime))
      liste.push(`${chemin} modifié`);
  }
  for (const chemin of b.keys()) {
    if (!a.has(chemin)) liste.push(`${chemin} ajouté`);
  }
  return liste;
}

/// Documents restants sous recipes/ et brews/, sous-collections comprises, et coûts figés
/// encore présents.
async function compterRestes(db, couts) {
  const restes = {};
  for (const nom of EFFACEES)
    restes[nom] = await compterArbre(db.collection(nom));
  const lus = await lireSansChamp(
    db,
    couts.map((chemin) => db.doc(chemin)),
  );
  restes["coûts figés"] = lus.filter((snap) => snap.exists).length;
  return restes;
}

const nombres = (r) => ({
  recipes: r.recettes,
  brews: r.brassins.length,
  events: r.evenements,
  couts: r.couts.length,
});
const memesNombres = (a, b) =>
  JSON.stringify(nombres(a)) === JSON.stringify(nombres(b));
const decrire = (r) => {
  const n = nombres(r);
  return (
    `${n.recipes} recette(s), ${n.brews} brassin(s), ${n.events} événement(s), ` +
    `${n.couts} coût(s) figé(s)`
  );
};

function refuserEnCours(releve, quand) {
  const enCours = releve.brassins.filter((b) => b.statut === "brewing");
  if (enCours.length > 0) {
    throw new Refus(
      2,
      `Brassin en cours${quand} (${enCours.map((b) => b.id).join(", ")}) : rien n'est effacé.`,
    );
  }
}

/// Effacement complet ; [demander] lit la réponse de l'utilisateur.
export async function effacer(db, projet, { dossier, demander, ecrire }) {
  const avant = await rapport(db);
  afficherRapport(avant, ecrire);
  refuserEnCours(avant, "");
  // Un document hors de recipes/{id}, brews/{id} et brews/{id}/events/{id} n'entre pas
  // dans le modèle : l'outil ne l'efface pas sans qu'on l'ait regardé.
  if (avant.horsModele.length > 0) {
    throw new Refus(
      5,
      `Documents hors modèle (${avant.horsModele.join(", ")}) : rien n'est copié ni effacé.`,
    );
  }
  const exclus = new Set(avant.couts);
  const protegeesAvant = await compterProtegees(db, exclus);
  const copie = sauvegarder(avant, projet, dossier);
  ecrire(`Copie : ${copie.nombre} documents dans ${copie.fichier}`);
  const reponse = await demander(
    `Tapez le nom du projet (${projet}) pour effacer recipes/, brews/ et les coûts figés : `,
  );
  if (reponse.trim() !== projet) {
    throw new Refus(3, "Nom du projet différent : rien n'est effacé.");
  }
  // Une écriture pendant la confirmation rend la copie inexacte : le rapport est refait,
  // et chaque document est comparé à celui de la copie.
  const confirme = await rapport(db);
  refuserEnCours(confirme, " depuis la copie");
  const changes = ecarts(avant, confirme);
  if (changes.length > 0 || !memesNombres(avant, confirme)) {
    throw new Refus(
      5,
      `Avant la copie : ${decrire(avant)}. Après la confirmation : ${decrire(confirme)}. ` +
        `Copie : ${copie.nombre} documents. Écarts : ${changes.join(", ") || "aucun"}. ` +
        "Rien n'est effacé, relancez la commande.",
    );
  }
  for (const nom of EFFACEES) await db.recursiveDelete(db.collection(nom));
  // Un coût figé modifié depuis la relecture n'est pas effacé : la suppression échoue sur
  // sa date de modification, le coût reste, et le contrôle des restes le signale (code 4).
  const nonEffaces = [];
  for (const chemin of avant.couts) {
    try {
      await db
        .doc(chemin)
        .delete({ lastUpdateTime: avant.coutsFiges.get(chemin).updateTime });
    } catch (erreur) {
      nonEffaces.push(`${chemin} (${erreur.message})`);
    }
  }
  ecrire(`Effacés : ${decrire(avant)}.`);
  // Écrit même quand le coût a disparu entre-temps et que l'outil sort en code 0 : chemin
  // et message de l'erreur, sans valeur du document.
  if (nonEffaces.length > 0)
    ecrire(`Coûts figés non effacés : ${nonEffaces.join(", ")}.`);
  const restes = Object.entries(await compterRestes(db, avant.couts)).filter(
    ([, n]) => n > 0,
  );
  const protegeesApres = await compterProtegees(db, exclus);
  const changees = PROTEGEES.filter(
    (nom) => protegeesAvant[nom] !== protegeesApres[nom],
  );
  for (const nom of PROTEGEES) {
    const libelle = nom === "users" ? "users (hors coûts figés effacés)" : nom;
    ecrire(
      `${libelle} : ${protegeesAvant[nom]} avant, ${protegeesApres[nom]} après.`,
    );
  }
  if (restes.length > 0 || changees.length > 0) {
    throw new Refus(
      4,
      [
        restes.length > 0
          ? `Documents restants : ${restes.map(([k, n]) => `${k} ${n}`).join(", ")}.`
          : "",
        nonEffaces.length > 0
          ? `Coûts figés non effacés : ${nonEffaces.join(", ")}.`
          : "",
        changees.length > 0
          ? `Collections protégées modifiées : ${changees.join(", ")}.`
          : "",
      ]
        .filter(Boolean)
        .join(" "),
    );
  }
  return { avant: nombres(avant), protegees: protegeesApres, copie };
}

async function main() {
  const ecrire = (ligne) => process.stdout.write(`${ligne}\n`);
  const args = lireArguments(process.argv.slice(2));
  const { commande, projet } = args;
  const dossier = verifierLancement(
    args,
    process.env,
    process.stdin.isTTY === true,
  );
  const { db, cible } = ouvrir(projet);
  ecrire(`Cible : ${cible}`);
  if (commande === "rapport") {
    afficherRapport(await rapport(db), ecrire);
    ecrire("Rapport seul : rien n'est écrit.");
    return;
  }
  await effacer(db, projet, {
    dossier,
    demander,
    ecrire,
  });
  ecrire("Effacement terminé.");
}

/// Pose [question] et rend la ligne tapée. L'entrée standard n'est lue qu'ici : une
/// réponse envoyée d'avance (tests) attend dans le tampon.
async function demander(question) {
  const lecteur = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  try {
    return await lecteur.question(question);
  } finally {
    lecteur.close();
  }
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main().then(
    () => process.exit(0),
    (erreur) => {
      process.stderr.write(`${erreur.message}\n`);
      process.exit(erreur instanceof Refus ? erreur.code : 1);
    },
  );
}
