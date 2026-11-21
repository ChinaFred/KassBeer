// Descriptions aromatiques des houblons (ADR-013) et des levures (ADR-017, --nature
// culture) : génération par l'API Messages d'Anthropic (modèle claude-fable-5-2), depuis le
// poste de l'admin. Lit import/ingest/prepare/ (beer_hops.json ; beer_cultures.json et
// beer_styles.json pour les levures) et import/ingest/aromes/ (levures/ pour les levures) ;
// ne lit ni n'écrit Firestore (l'écriture passe par ecrire.mjs). Postes de coût :
// hop_aroma_generation, culture_aroma_generation.
//
//   node generer-aromes.mjs --essai [n] --seulement ../import/ingest/aromes/houblons-essai.json
//   node generer-aromes.mjs --lot --seulement ../import/ingest/aromes/houblons-recettes.json --budget-usd 4
//   node generer-aromes.mjs --lot --budget-usd 15           (houblons nouveaux ou changés)
//   node generer-aromes.mjs --nouveaux --budget-usd 1       (houblons sans entrée, 20 au plus)
//   node generer-aromes.mjs --suivre <id du lot>
//   node generer-aromes.mjs --relire                        (réécrit a-relire.md)
//   node generer-aromes.mjs --nature culture --essai --seulement ../import/ingest/aromes/levures/levures-essai.json
//   node generer-aromes.mjs --nature culture --lot --budget-usd 45   (périmètre de l'ADR-017)
//
// Clé : ANTHROPIC_API_KEY dans l'environnement, jamais affichée. Codes de sortie : 0 fini ;
// 1 échec ; 2 utilisation refusée (tarif, budget, confirmation…) ; 3 réponses en erreur ou
// refusées au contrôle (voir rapport.json).

import { masquerCle } from "./lib/aromes/client.mjs";
import { genererAromes } from "./lib/aromes/generation.mjs";
import { ErreurAromes } from "./lib/aromes/tarif.mjs";

const cle = process.env.ANTHROPIC_API_KEY;
try {
  const rapport = await genererAromes({
    argv: process.argv.slice(2),
    env: process.env,
    entree: process.stdin,
    sortie: process.stdout,
  });
  if ((rapport.erreurs?.length ?? 0) + (rapport.refus?.length ?? 0) > 0) process.exitCode = 3;
} catch (erreur) {
  // Message seul, clé retirée : ni pile ni objet d'erreur du SDK à l'écran.
  if (erreur instanceof ErreurAromes) {
    console.error(masquerCle(erreur.message, cle));
    process.exitCode = 2;
  } else {
    console.error(
      `Échec de la génération : ${masquerCle(`${erreur?.name}: ${erreur?.message}`, cle)}`,
    );
    process.exitCode = 1;
  }
}
