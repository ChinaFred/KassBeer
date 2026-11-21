// Écrivain de l'ingestion (ADR-005, D5). Lit import/ingest/prepare/ (produit par
// `dart run bin/preparer_referentiels.dart` dans exchange/) et écrit les référentiels et
// les recettes publiques par l'Admin SDK ; lit aussi import/ingest/aromes/aromes.json
// (generer-aromes.mjs, ADR-013) et écrit beer_hop_aromas/, puis
// import/ingest/divers/descriptions.json (generer-divers.mjs, ADR-017) et écrit
// beer_misc_descriptions/.
//
//   Émulateur (par défaut) :
//     npx firebase --config ../firebase.json emulators:exec --only firestore \
//       --project demo-kassbeer "node ecrire.mjs"
//   Production (identifiants ADC, confirmation au terminal) :
//     node ecrire.mjs --production --projet kassbeer
//   Compter sans écrire : --simulation.
//   Supprimer les documents absents de la préparation (ADR-014) : --supprimer-absents
//   beer_hops, beer_hop_aromas ou beer_cultures, 30 au plus, confirmation par la saisie de
//   leur nombre ; avec --simulation, la liste seule.
//
// Codes de sortie : 0 tout écrit ; 1 échec (dont une suppression en erreur) ; 2 utilisation
// refusée ; 3 documents refusés par le contrôle (les autres sont écrits, la liste est dans
// le rapport).

import { executer, messageSansDescription, NATURES_REDIGEES } from "./lib/execution.mjs";
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
  for (const nature of NATURES_REDIGEES) {
    const e = nature.ecriture;
    if (rapport[e.champFichier] === "absent") {
      console.log(`${e.collection} : ${nature.fichierEntrees} absent, aucune description écrite`);
    }
  }
  const d = rapport.deletions;
  if (d !== undefined) {
    const verbe = rapport.simulation ? "à supprimer" : "supprimés";
    const nombre = rapport.simulation ? d.candidates.length : d.deleted.length;
    console.log(
      `${d.collection} : ${d.online} en ligne, ${d.prepared} préparés, ${nombre} ${verbe}, ` +
        `${d.ignored.length} ignorés, ${d.errors.length} en erreur`,
    );
    for (const id of rapport.simulation ? d.candidates : d.deleted) console.log(`  ${id}`);
    for (const e of d.errors) console.error(`  ${e.id} : ${e.erreur}`);
    if (d.errors.length > 0) process.exitCode = 1;
  }
  console.log(`Rapport : ${rapport.fichier}`);
  for (const nature of NATURES_REDIGEES) {
    const n = rapport[nature.ecriture.champSansDescription];
    const sansDescription = messageSansDescription(n, nature);
    if (sansDescription !== null) console.log(sansDescription);
  }
  if (rapport.refused.length > 0) {
    console.error(`${rapport.refused.length} documents refusés : voir le rapport.`);
    process.exitCode ??= 3;
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
