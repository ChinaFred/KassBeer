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

import { lancerListe } from "./lib/lister.mjs";

await lancerListe("houblons");
