// Descriptions des divers (ADR-017) : moment, rôle et goût, sans dose, rédigés par l'API
// Messages d'Anthropic (modèle claude-fable-5-2), depuis le poste de l'admin. Passe la
// nature « divers » (lib/divers/nature.mjs) au moteur commun (lib/redaction/). Lit
// import/ingest/prepare/beer_miscs.json, import/ingest/divers/ et le tarif commun
// import/ingest/tarif.json ; ne lit ni n'écrit Firestore (l'écriture passe par ecrire.mjs).
// Poste de coût : misc_description_generation.
//
//   node generer-divers.mjs --essai [n] --seulement ../import/ingest/divers/divers-essai.json
//   node generer-divers.mjs --lot --seulement ../import/ingest/divers/divers-recettes.json --budget-usd 2
//   node generer-divers.mjs --lot --budget-usd 6            (divers nouveaux ou changés)
//   node generer-divers.mjs --nouveaux --budget-usd 1       (divers sans entrée, 20 au plus)
//   node generer-divers.mjs --suivre <id du lot>
//   node generer-divers.mjs --relire                        (réécrit a-relire.md)
//
// Clé : ANTHROPIC_API_KEY dans l'environnement, jamais affichée. Codes de sortie : 0 fini ;
// 1 échec ; 2 utilisation refusée (tarif, budget, confirmation…) ; 3 réponses en erreur ou
// refusées au contrôle (voir rapport.json), posés par lib/redaction/lancer.mjs.

import { NATURE_DIVERS } from "./lib/divers/nature.mjs";
import { lancerGenerateur } from "./lib/redaction/lancer.mjs";

await lancerGenerateur(NATURE_DIVERS);
