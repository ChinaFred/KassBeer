// Liste des noms d'ingrédients des recettes du groupe, en lecture seule, pour une nature
// rédigée : houblons (ADR-013, décisions 9 et 10) ou divers (ADR-018). Lit
// recipes/*.recipe.ingredients.<liste>[].name et
// brews/*.recipe_snapshot.recipe.ingredients.<liste>[].name (<liste> : hop_additions ou
// miscellaneous_additions), et n'écrit que les noms, triés et sans doublon, dans
// import/ingest/aromes/noms-houblons.json ou import/ingest/divers/noms-divers.json. Aucun
// identifiant de recette, de brassin ni de membre, aucune quantité ni prix ne sort. Aucune
// écriture dans Firestore. Mêmes garde-fous que ecrire.mjs (émulateur par défaut,
// production sur option, ADC d'un compte utilisateur, saisie du nom du projet).

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  cheminIdentifiants,
  confirmerProduction,
  controlerIdentifiants,
  ErreurOptions,
  lireOptions,
} from "./options.mjs";

/// Listes lues, par nature : liste BeerJSON des ingrédients, fichier écrit par défaut et son
/// format.
export const LISTES = Object.freeze({
  houblons: {
    liste: "hop_additions",
    fichier: fileURLToPath(
      new URL("../../import/ingest/aromes/noms-houblons.json", import.meta.url),
    ),
    format: "kassbeer_noms_houblons",
    mots: "houblons",
  },
  divers: {
    liste: "miscellaneous_additions",
    fichier: fileURLToPath(new URL("../../import/ingest/divers/noms-divers.json", import.meta.url)),
    format: "kassbeer_noms_divers",
    mots: "divers",
  },
});

/// Longueur maximale d'un nom gardé (borne de `name` dans les règles).
const NOM_MAX = 120;

/// Noms d'une liste d'ingrédients lue ([lignes], valeur Firestore), ajoutés à [noms]. Rend
/// le nombre de lignes écartées (nom absent, vide ou trop long).
export function ajouterNoms(lignes, noms) {
  let ecartees = 0;
  if (!Array.isArray(lignes)) return 0;
  for (const l of lignes) {
    const nom = typeof l?.name === "string" ? l.name.normalize("NFC").trim() : "";
    if (nom.length === 0 || [...nom].length > NOM_MAX) ecartees++;
    else noms.add(nom);
  }
  return ecartees;
}

/// Lit [argv] : options de ecrire.mjs pour la cible (--production --projet kassbeer), plus
/// --sortie <fichier>. --simulation, --dossier, --rapports, --aromes et --divers sont
/// refusés.
export function lireOptionsLister(argv, env) {
  const reste = [];
  let sortie = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--sortie") {
      sortie = argv[++i];
      if (sortie === undefined || sortie.startsWith("--")) {
        throw new ErreurOptions("--sortie demande une valeur.");
      }
    } else if (
      ["--simulation", "--dossier", "--rapports", "--aromes", "--divers"].includes(argv[i])
    ) {
      throw new ErreurOptions(`Option inconnue : ${argv[i]} (lecture seule, rien n'est écrit).`);
    } else {
      reste.push(argv[i]);
    }
  }
  const cible = lireOptions(reste, env);
  return { cible: cible.cible, projet: cible.projet, sortie };
}

/// Exécute la liste de [nature] (clé de LISTES). Rend `{target, project, recettes,
/// brassins, ecartees, noms, fichier}`.
export async function listerNoms({
  nature,
  argv,
  env,
  entree,
  sortie,
  maintenant = () => new Date(),
  lireIdentifiants = (chemin) => readFileSync(chemin, "utf8"),
}) {
  if (!Object.hasOwn(LISTES, nature)) throw new Error(`nature de liste inconnue : ${nature}`);
  const { liste: champ, fichier: fichierDefaut, format } = LISTES[nature];
  const champRecette = `recipe.ingredients.${champ}`;
  const champBrassin = `recipe_snapshot.recipe.ingredients.${champ}`;
  const options = lireOptionsLister(argv, env);
  if (options.cible === "production") {
    controlerIdentifiants(cheminIdentifiants(env), lireIdentifiants);
    const confirme = await confirmerProduction(options.projet, entree, sortie);
    if (!confirme) throw new ErreurOptions("Nom du projet non confirmé : rien n'est lu.");
  }
  const { deleteApp, initializeApp } = await import("firebase-admin/app");
  const { getFirestore } = await import("firebase-admin/firestore");
  const app = initializeApp({ projectId: options.projet }, `lister-${process.pid}-${Date.now()}`);
  try {
    const db = getFirestore(app);
    const noms = new Set();
    let ecartees = 0;
    // Champs lus : seule la liste de la nature, pas le reste du document.
    const recettes = await db.collection("recipes").select(champRecette).get();
    for (const d of recettes.docs) ecartees += ajouterNoms(d.get(champRecette), noms);
    const brassins = await db.collection("brews").select(champBrassin).get();
    for (const d of brassins.docs) ecartees += ajouterNoms(d.get(champBrassin), noms);
    const liste = [...noms].sort();
    const fichier = resolve(options.sortie ?? fichierDefaut);
    mkdirSync(dirname(fichier), { recursive: true });
    writeFileSync(
      fichier,
      `${JSON.stringify(
        {
          format,
          version: 1,
          generated_at: maintenant().toISOString(),
          target: options.cible,
          noms: liste,
        },
        null,
        2,
      )}\n`,
    );
    return {
      target: options.cible,
      project: options.projet,
      recettes: recettes.size,
      brassins: brassins.size,
      ecartees,
      noms: liste.length,
      fichier,
    };
  } finally {
    await deleteApp(app);
  }
}

/// Point d'entrée de lister-houblons-recettes.mjs et lister-divers-recettes.mjs : liste de
/// [nature] sur le processus courant, résumé à l'écran. Codes de sortie : 0 liste écrite ;
/// 1 échec ; 2 utilisation refusée.
export async function lancerListe(nature) {
  try {
    const r = await listerNoms({
      nature,
      argv: process.argv.slice(2),
      env: process.env,
      entree: process.stdin,
      sortie: process.stdout,
    });
    console.log(`Cible : ${r.target}, projet ${r.project} (lecture seule)`);
    console.log(
      `${r.recettes} recettes et ${r.brassins} brassins lus : ${r.noms} noms de ${LISTES[nature].mots}` +
        (r.ecartees > 0 ? `, ${r.ecartees} lignes sans nom lisible écartées` : "") +
        ".",
    );
    console.log(`Liste : ${r.fichier}`);
  } catch (erreur) {
    if (erreur instanceof ErreurOptions) {
      console.error(erreur.message);
      process.exitCode = 2;
    } else {
      console.error("Échec de la liste :", erreur);
      process.exitCode = 1;
    }
  }
}
