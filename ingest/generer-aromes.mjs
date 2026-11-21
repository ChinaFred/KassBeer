// Descriptions aromatiques des houblons (ADR-013) : génération par l'API Messages
// d'Anthropic (modèle claude-fable-5-2), depuis le poste de l'admin. Passe la nature
// « houblon » (lib/aromes/nature.mjs) au moteur commun (lib/redaction/, ADR-018). Lit
// import/ingest/prepare/beer_hops.json, import/ingest/aromes/ et le tarif commun
// import/ingest/tarif.json ; ne lit ni n'écrit Firestore (l'écriture passe par ecrire.mjs).
// Poste de coût : hop_aroma_generation.
//
//   node generer-aromes.mjs --essai [n] --seulement ../import/ingest/aromes/houblons-essai.json
//   node generer-aromes.mjs --lot --seulement ../import/ingest/aromes/houblons-recettes.json --budget-usd 4
//   node generer-aromes.mjs --lot --budget-usd 15           (houblons nouveaux ou changés)
//   node generer-aromes.mjs --nouveaux --budget-usd 1       (houblons sans entrée, 20 au plus)
//   node generer-aromes.mjs --suivre <id du lot>
//   node generer-aromes.mjs --relire                        (réécrit a-relire.md)
//
// Clé : ANTHROPIC_API_KEY dans l'environnement, jamais affichée. Codes de sortie : 0 fini ;
// 1 échec ; 2 utilisation refusée (tarif, budget, confirmation…) ; 3 réponses en erreur ou
// refusées au contrôle (voir rapport.json), posés par lib/redaction/lancer.mjs.

import { NATURE_HOUBLON } from "./lib/aromes/nature.mjs";
import { lancerGenerateur } from "./lib/redaction/lancer.mjs";

await lancerGenerateur(NATURE_HOUBLON);
