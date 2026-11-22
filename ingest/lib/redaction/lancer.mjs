// Point d'entrée commun des générateurs (generer-aromes.mjs, generer-divers.mjs) : passe la
// nature au moteur avec le processus courant, affiche le message d'une erreur, clé retirée,
// et pose le code de sortie : 0 fini ; 1 échec ; 2 utilisation refusée (tarif, budget,
// confirmation…) ; 3 réponses en erreur ou refusées au contrôle (voir rapport.json).

import { masquerCle } from "./client.mjs";
import { generer } from "./moteur.mjs";
import { ErreurRedaction } from "./tarif.mjs";

/// Lance le générateur de [natures] (une nature, ou un objet clé → nature choisie par
/// --nature) sur le processus courant.
export async function lancerGenerateur(natures) {
  const cle = process.env.ANTHROPIC_API_KEY;
  try {
    const rapport = await generer({
      natures,
      argv: process.argv.slice(2),
      env: process.env,
      entree: process.stdin,
      sortie: process.stdout,
    });
    if ((rapport.erreurs?.length ?? 0) + (rapport.refus?.length ?? 0) > 0) process.exitCode = 3;
  } catch (erreur) {
    // Message seul, clé retirée : ni pile ni objet d'erreur du SDK à l'écran.
    if (erreur instanceof ErreurRedaction) {
      console.error(masquerCle(erreur.message, cle));
      process.exitCode = 2;
    } else {
      console.error(
        `Échec de la génération : ${masquerCle(`${erreur?.name}: ${erreur?.message}`, cle)}`,
      );
      process.exitCode = 1;
    }
  }
}
