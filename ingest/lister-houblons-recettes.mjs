// Noms des houblons des recettes du groupe (ADR-013), en lecture seule : recipes/ et brews/
// (recette figée), vers import/ingest/aromes/noms-houblons.json. Puis, dans exchange/ :
// dart run bin/lister_houblons_recettes.dart (résolution vers beer_hops/).
//
//   Émulateur (par défaut) :
//     npx firebase --config ../firebase.json emulators:exec --only firestore \
//       --project demo-kassbeer "node lister-houblons-recettes.mjs"
//   Production (identifiants ADC, saisie du nom du projet) :
//     node lister-houblons-recettes.mjs --production --projet kassbeer
//
// Codes de sortie : 0 liste écrite ; 1 échec ; 2 utilisation refusée.

import { listerHoublons } from "./lib/lister.mjs";
import { ErreurOptions } from "./lib/options.mjs";

try {
  const r = await listerHoublons({
    argv: process.argv.slice(2),
    env: process.env,
    entree: process.stdin,
    sortie: process.stdout,
  });
  console.log(`Cible : ${r.target}, projet ${r.project} (lecture seule)`);
  console.log(
    `${r.recettes} recettes et ${r.brassins} brassins lus : ${r.noms} noms de houblons` +
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
