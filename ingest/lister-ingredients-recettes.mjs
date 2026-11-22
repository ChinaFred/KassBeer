// Noms des houblons (--nature hop, par défaut, ADR-013), des levures (--nature culture,
// ADR-017) ou des divers (--nature misc, ADR-018) des recettes du groupe, en lecture seule :
// recipes/ et brews/ (recette figée), vers import/ingest/aromes/noms-houblons.json,
// import/ingest/aromes/levures/noms-levures.json ou import/ingest/divers/noms-divers.json.
// Puis, dans exchange/ : dart run bin/lister_ingredients_recettes.dart --nature <même nature>
// (résolution vers beer_hops/, beer_cultures/ ou beer_miscs/).
//
//   Émulateur (par défaut) :
//     npx firebase --config ../firebase.json emulators:exec --only firestore \
//       --project demo-kassbeer "node lister-ingredients-recettes.mjs --nature culture"
//   Production (identifiants ADC, saisie du nom du projet) :
//     node lister-ingredients-recettes.mjs --nature culture --production --projet kassbeer
//
// Codes de sortie : 0 liste écrite ; 1 échec ; 2 utilisation refusée.

import { listerIngredients } from "./lib/lister.mjs";

const MOTS = { hop: "houblons", culture: "levures", misc: "divers" };
import { ErreurOptions } from "./lib/options.mjs";

try {
  const r = await listerIngredients({
    argv: process.argv.slice(2),
    env: process.env,
    entree: process.stdin,
    sortie: process.stdout,
  });
  console.log(`Cible : ${r.target}, projet ${r.project} (lecture seule)`);
  console.log(
    `${r.recettes} recettes et ${r.brassins} brassins lus : ${r.noms} noms de ` +
      `${MOTS[r.nature]}` +
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
