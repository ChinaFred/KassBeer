// Liste des noms d'ingrédients des recettes du groupe, en lecture seule : houblons
// (--nature hop, ADR-013, décisions 9 et 10), levures (--nature culture, ADR-017) ou divers
// (--nature misc, ADR-018 ; ADR-019). Lit recipes/*.recipe.ingredients.<liste>[].name et
// brews/*.recipe_snapshot.recipe.ingredients.<liste>[].name (hop_additions,
// culture_additions ou miscellaneous_additions), et n'écrit que les noms, triés et sans
// doublon, dans import/ingest/aromes/noms-houblons.json,
// import/ingest/aromes/levures/noms-levures.json ou import/ingest/divers/noms-divers.json.
// Aucun identifiant de recette, de brassin ni de membre, aucune quantité ni prix ne sort.
// Aucune écriture dans Firestore. Mêmes garde-fous que ecrire.mjs (émulateur par défaut,
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

/// Natures listées : liste lue dans `ingredients`, fichier écrit par défaut, format.
export const NATURES_LISTE = {
  hop: {
    liste: "hop_additions",
    fichier: fileURLToPath(
      new URL("../../import/ingest/aromes/noms-houblons.json", import.meta.url),
    ),
    format: "kassbeer_noms_houblons",
  },
  culture: {
    liste: "culture_additions",
    fichier: fileURLToPath(
      new URL("../../import/ingest/aromes/levures/noms-levures.json", import.meta.url),
    ),
    format: "kassbeer_noms_levures",
  },
  misc: {
    liste: "miscellaneous_additions",
    fichier: fileURLToPath(new URL("../../import/ingest/divers/noms-divers.json", import.meta.url)),
    format: "kassbeer_noms_divers",
  },
};

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
/// --nature hop|culture|misc (hop par défaut) et --sortie <fichier>. --simulation, --dossier,
/// --rapports, --aromes, --divers et --supprimer-absents sont refusés.
export function lireOptionsLister(argv, env) {
  const reste = [];
  let sortie = null;
  let nature = "hop";
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--nature") {
      nature = argv[++i];
      if (!(nature in NATURES_LISTE)) {
        throw new ErreurOptions(`--nature : ${Object.keys(NATURES_LISTE).join(", ")}.`);
      }
    } else if (argv[i] === "--sortie") {
      sortie = argv[++i];
      if (sortie === undefined || sortie.startsWith("--")) {
        throw new ErreurOptions("--sortie demande une valeur.");
      }
    } else if (
      [
        "--simulation",
        "--dossier",
        "--rapports",
        "--aromes",
        "--divers",
        "--supprimer-absents",
      ].includes(argv[i])
    ) {
      throw new ErreurOptions(`Option inconnue : ${argv[i]} (lecture seule, rien n'est écrit).`);
    } else {
      reste.push(argv[i]);
    }
  }
  const cible = lireOptions(reste, env);
  return { cible: cible.cible, projet: cible.projet, sortie, nature };
}

/// Exécute la liste. Rend `{target, project, nature, recettes, brassins, ecartees, noms,
/// fichier}`.
export async function listerIngredients({
  argv,
  env,
  entree,
  sortie,
  maintenant = () => new Date(),
  lireIdentifiants = (chemin) => readFileSync(chemin, "utf8"),
}) {
  const options = lireOptionsLister(argv, env);
  const nature = NATURES_LISTE[options.nature];
  // Champs lus : seule la liste de la nature, pas le reste du document.
  const champRecette = `recipe.ingredients.${nature.liste}`;
  const champBrassin = `recipe_snapshot.recipe.ingredients.${nature.liste}`;
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
    const recettes = await db.collection("recipes").select(champRecette).get();
    for (const d of recettes.docs) ecartees += ajouterNoms(d.get(champRecette), noms);
    const brassins = await db.collection("brews").select(champBrassin).get();
    for (const d of brassins.docs) ecartees += ajouterNoms(d.get(champBrassin), noms);
    const liste = [...noms].sort();
    const fichier = resolve(options.sortie ?? nature.fichier);
    mkdirSync(dirname(fichier), { recursive: true });
    writeFileSync(
      fichier,
      `${JSON.stringify(
        {
          format: nature.format,
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
      nature: options.nature,
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
