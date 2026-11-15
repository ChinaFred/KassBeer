// Liste des noms de houblons des recettes du groupe (ADR-013, décisions 9 et 10), en lecture
// seule : lit recipes/*.recipe.ingredients.hop_additions[].name et
// brews/*.recipe_snapshot.recipe.ingredients.hop_additions[].name, et n'écrit que les noms,
// triés et sans doublon, dans import/ingest/aromes/noms-houblons.json. Aucun identifiant
// de recette, de brassin ni de membre, aucune quantité ni prix ne sort. Aucune écriture
// dans Firestore. Mêmes garde-fous que ecrire.mjs (émulateur par défaut, production sur
// option, ADC d'un compte utilisateur, saisie du nom du projet).

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

/// Fichier écrit par défaut.
export const FICHIER_NOMS = fileURLToPath(
  new URL("../../import/ingest/aromes/noms-houblons.json", import.meta.url),
);

/// Longueur maximale d'un nom gardé (borne de `name` dans les règles).
const NOM_MAX = 120;

/// Champs lus : seule la liste des houblons, pas le reste du document.
const CHAMP_RECETTE = "recipe.ingredients.hop_additions";
const CHAMP_BRASSIN = "recipe_snapshot.recipe.ingredients.hop_additions";

/// Noms de houblons d'une liste `hop_additions` lue ([lignes], valeur Firestore), ajoutés à
/// [noms]. Rend le nombre de lignes écartées (nom absent, vide ou trop long).
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
/// --sortie <fichier>. --simulation, --dossier, --rapports et --aromes sont refusés.
export function lireOptionsLister(argv, env) {
  const reste = [];
  let sortie = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--sortie") {
      sortie = argv[++i];
      if (sortie === undefined || sortie.startsWith("--")) {
        throw new ErreurOptions("--sortie demande une valeur.");
      }
    } else if (["--simulation", "--dossier", "--rapports", "--aromes"].includes(argv[i])) {
      throw new ErreurOptions(`Option inconnue : ${argv[i]} (lecture seule, rien n'est écrit).`);
    } else {
      reste.push(argv[i]);
    }
  }
  const cible = lireOptions(reste, env);
  return { cible: cible.cible, projet: cible.projet, sortie };
}

/// Exécute la liste. Rend `{target, project, recettes, brassins, ecartees, noms, fichier}`.
export async function listerHoublons({
  argv,
  env,
  entree,
  sortie,
  maintenant = () => new Date(),
  lireIdentifiants = (chemin) => readFileSync(chemin, "utf8"),
}) {
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
    const recettes = await db.collection("recipes").select(CHAMP_RECETTE).get();
    for (const d of recettes.docs) ecartees += ajouterNoms(d.get(CHAMP_RECETTE), noms);
    const brassins = await db.collection("brews").select(CHAMP_BRASSIN).get();
    for (const d of brassins.docs) ecartees += ajouterNoms(d.get(CHAMP_BRASSIN), noms);
    const liste = [...noms].sort();
    const fichier = resolve(options.sortie ?? FICHIER_NOMS);
    mkdirSync(dirname(fichier), { recursive: true });
    writeFileSync(
      fichier,
      `${JSON.stringify(
        {
          format: "kassbeer_noms_houblons",
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
