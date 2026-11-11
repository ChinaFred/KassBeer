// Écrivain de l'ingestion (ADR-005, D5). Lit import/ingest/prepare/ (produit par
// `dart run bin/preparer_referentiels.dart` dans exchange/) et écrit les référentiels et
// les recettes publiques par l'Admin SDK.
//
//   Émulateur (par défaut) :
//     npx firebase --config ../firebase.json emulators:exec --only firestore \
//       --project demo-kassbeer "node ecrire.mjs"
//   Production (identifiants ADC, confirmation au terminal) :
//     node ecrire.mjs --production --projet kassbeer
//   Compter sans écrire : --simulation.
//
// Codes de sortie : 0 tout écrit ; 1 échec ; 2 utilisation refusée ; 3 documents refusés
// par le contrôle (les autres sont écrits, la liste est dans le rapport).

import { executer } from "./lib/execution.mjs";
import { ErreurOptions } from "./lib/options.mjs";

try {
  const rapport = await executer({
    argv: process.argv.slice(2),
    env: process.env,
    entree: process.stdin,
    sortie: process.stdout,
  });
  const mode = rapport.simulation ? " (simulation : rien n'est écrit)" : "";
  console.log(`Cible : ${rapport.target}, projet ${rapport.project}${mode}`);
  for (const [collection, c] of Object.entries(rapport.counts)) {
    console.log(
      `${collection} : ${c.written} écrits, ${c.unchanged} inchangés, ${c.refused} refusés`,
    );
  }
  console.log(`Rapport : ${rapport.fichier}`);
  if (rapport.refused.length > 0) {
    console.error(`${rapport.refused.length} documents refusés : voir le rapport.`);
    process.exitCode = 3;
  }
} catch (erreur) {
  if (erreur instanceof ErreurOptions) {
    console.error(erreur.message);
    process.exitCode = 2;
  } else {
    console.error("Échec de l'écriture :", erreur);
    process.exitCode = 1;
  }
}
