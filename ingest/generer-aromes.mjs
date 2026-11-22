// Descriptions aromatiques des houblons (ADR-013) et des levures (--nature culture, ADR-017) :
// génération par l'API Messages d'Anthropic (modèle claude-fable-5-2), depuis le poste de
// l'admin. Passe les natures « houblon » (lib/aromes/nature.mjs) et « levure »
// (lib/levures/nature.mjs) au moteur commun (lib/redaction/, ADR-019) ; --nature hop par
// défaut. Lit import/ingest/prepare/ (beer_hops.json, ou beer_cultures.json et
// beer_styles.json), import/ingest/aromes/ (levures dans levures/) et le tarif commun
// import/ingest/tarif.json ; ne lit ni n'écrit Firestore (l'écriture passe par ecrire.mjs).
// Postes de coût : hop_aroma_generation, culture_aroma_generation.
//
//   node generer-aromes.mjs --essai [n] --seulement ../import/ingest/aromes/houblons-essai.json
//   node generer-aromes.mjs --lot --seulement ../import/ingest/aromes/houblons-recettes.json --budget-usd 4
//   node generer-aromes.mjs --lot --budget-usd 15           (houblons nouveaux ou changés)
//   node generer-aromes.mjs --nouveaux --budget-usd 1       (houblons sans entrée, 20 au plus)
//   node generer-aromes.mjs --nature culture --lot --budget-usd 50   (levures du périmètre)
//   node generer-aromes.mjs [--nature culture] --suivre <id du lot>
//   node generer-aromes.mjs [--nature culture] --relire     (réécrit a-relire.md)
//
// Clé : ANTHROPIC_API_KEY dans l'environnement, jamais affichée. Codes de sortie : 0 fini ;
// 1 échec ; 2 utilisation refusée (tarif, budget, confirmation…) ; 3 réponses en erreur ou
// refusées au contrôle (voir rapport.json), posés par lib/redaction/lancer.mjs.

import { NATURE_HOUBLON } from "./lib/aromes/nature.mjs";
import { NATURE_LEVURE } from "./lib/levures/nature.mjs";
import { lancerGenerateur } from "./lib/redaction/lancer.mjs";

await lancerGenerateur({ hop: NATURE_HOUBLON, culture: NATURE_LEVURE });
