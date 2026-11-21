// Nature `hop` du générateur des descriptions aromatiques (ADR-013) : ce qui dépend des
// houblons, rassemblé pour generation.mjs. Le prompt reste dans ../prompt.mjs et le contrôle
// dans ../validation.mjs (P55) ; ce fichier les nomme sans les changer. N'importe pas le SDK.

import { MODELE, parametresRequete, PROMPT_VERSION } from "../prompt.mjs";
import {
  COLLECTION_AROMES,
  controlerEntreeArome,
  controlerSortieModele,
  donneesEnvoyees,
  empreinteEntree,
  USAGES,
} from "../validation.mjs";

const LIBELLES_USAGES = {
  first_wort: "Premier moût",
  bittering: "Amérisant",
  late_boil: "Fin d'ébullition",
  whirlpool: "Whirlpool",
  dry_hop: "Houblonnage à cru",
};

/// Description de la nature `hop` lue par generation.mjs.
export const NATURE_HOUBLON = Object.freeze({
  cle: "hop",
  collection: COLLECTION_AROMES,
  /// Nom du poste de coût, porté par chaque rapport (catalogue « Coûts variables »).
  poste: "hop_aroma_generation",
  /// Fichier préparé lu dans import/ingest/prepare/.
  referentiel: "beer_hops.json",
  /// Sous-dossier de import/ingest/aromes/ (null : le dossier lui-même).
  sousDossier: null,
  motifId: /^hop-[a-z0-9]+(-[a-z0-9]+)*$/,
  prefixeId: "hop-…",
  /// Première lettre des custom_id d'un lot (h0001…).
  prefixeLot: "h",
  /// Champ du nom copié dans l'entrée et dans la table d'un lot.
  champNom: "hop_name",
  fichierGroupe: "houblons-recettes.json",
  formatGroupe: "kassbeer_houblons_recettes",
  scriptGroupe: "lister_ingredients_recettes.dart",
  mots: { un: "houblon", des: "houblons", Des: "Houblons", de: "de houblon" },
  /// Refus de ecrire.mjs (lib/execution.mjs, trierAromes).
  refus: {
    absent: "houblon absent de beer_hops.json",
    nonRelu: "houblon des recettes du groupe non relu",
  },
  promptVersion: PROMPT_VERSION,
  /// Types exclus du périmètre (null : tout le référentiel).
  typesExclus: null,
  dansPerimetre: () => true,
  contexte: () => ({}),
  donneesEnvoyees,
  empreinte: (donnees, { effort }) =>
    empreinteEntree(donnees, { promptVersion: PROMPT_VERSION, modele: MODELE, effort }),
  requete: (donnees, { effort, cache }) => parametresRequete(donnees, { effort, cache }),
  controlerSortie: (sortie) => controlerSortieModele(sortie),
  controlerEntree: (doc) => controlerEntreeArome(doc),
  /// Ligne « Données envoyées » de a-relire.md.
  ligneDonnees(data) {
    const d = donneesEnvoyees(data);
    return (
      `- Données envoyées : origine ${d.origin ?? "inconnue"}, alpha ${d.alpha_acid_pct ?? "?"} %, ` +
      `bêta ${d.beta_acid_pct ?? "?"} %, usage ${d.purpose ?? "inconnu"}` +
      (d.aliases.length > 0 ? `, autres noms : ${d.aliases.join(", ")}` : "")
    );
  },
  /// Lignes des textes d'une entrée dans a-relire.md.
  lignesTextes(arome) {
    return USAGES.filter((u) => arome.uses?.[u]).map(
      (u) => `- ${LIBELLES_USAGES[u]} : ${arome.uses[u].text}`,
    );
  },
});
