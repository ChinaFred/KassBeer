// Noms des divers des recettes du groupe (ADR-017), en lecture seule : recipes/ et brews/
// (recette figée), miscellaneous_additions[].name, vers
// import/ingest/divers/noms-divers.json. Puis, dans exchange/ :
// dart run bin/lister_divers_recettes.dart (résolution vers beer_miscs/).
//
//   Émulateur (par défaut) :
//     npx firebase --config ../firebase.json emulators:exec --only firestore \
//       --project demo-kassbeer "node lister-divers-recettes.mjs"
//   Production (identifiants ADC, saisie du nom du projet) :
//     node lister-divers-recettes.mjs --production --projet kassbeer
//
// Codes de sortie : 0 liste écrite ; 1 échec ; 2 utilisation refusée.

import { lancerListe } from "./lib/lister.mjs";

await lancerListe("divers");
