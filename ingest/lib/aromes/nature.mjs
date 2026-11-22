// Nature « houblon » du moteur de rédaction (ADR-013 ; ADR-018, section 1) : descriptions
// aromatiques des houblons, écrites dans beer_hop_aromas/ par ecrire.mjs. Ce fichier dit au
// moteur (lib/redaction/moteur.mjs) ce qui est propre aux houblons : poste de coût,
// fichiers, données envoyées, empreinte, prompt, contrôle, a-relire.md. N'importe pas le
// SDK d'Anthropic.
//
// Fichiers de import/ingest/aromes/ (jamais versionnés) :
//   aromes.json              entrées {id, data}, copie de référence, corrigée à la main
//   houblons-recettes.json   houblons des recettes du groupe (exchange/bin/lister_ingredients_recettes.dart)
//   lot-<id>.json            table custom_id → houblon d'un lot de l'API Batches
//   brut/                    réponses de chaque exécution, effort dans le nom
//   rapport.json             dernière exécution : poste, modèle, effort, jetons, montant
//   a-relire.md              houblons du groupe à relire
// Le tarif est lu dans import/ingest/tarif.json, commun aux natures (ADR-018).

import { fileURLToPath } from "node:url";
import { construireEntree } from "../redaction/entree.mjs";
import { MAX_TOKENS, MODELE, parametresRequete, PROMPT_VERSION } from "./prompt.mjs";
import {
  COLLECTION_AROMES,
  controlerEntreeArome,
  controlerSortieModele,
  donneesEnvoyees,
  empreinteEntree,
  ID_HOUBLON,
  USAGES,
} from "./validation.mjs";

/// Libellés des usages dans a-relire.md.
const LIBELLES_USAGES = {
  first_wort: "Premier moût",
  bittering: "Amérisant",
  late_boil: "Fin d'ébullition",
  whirlpool: "Whirlpool",
  dry_hop: "Houblonnage à cru",
};

export const NATURE_HOUBLON = Object.freeze({
  /// Valeur de --nature (generer-aromes.mjs, lister-ingredients-recettes.mjs) et du champ
  /// `nature` d'un lot.
  cle: "hop",
  /// Poste de coût porté par chaque rapport (catalogue « Coûts variables »).
  poste: "hop_aroma_generation",
  adr: "ADR-013",
  script: "generer-aromes.mjs",
  /// Commande de la nature, citée dans les messages (« Suivi : node … --suivre <id> »).
  commande: "generer-aromes.mjs",
  /// Option qui remplace le dossier de la nature, et dossier par défaut.
  optionDossier: "--aromes",
  dossierDefaut: fileURLToPath(new URL("../../../import/ingest/aromes/", import.meta.url)),
  sousDossier: null,
  /// Référentiel préparé (import/ingest/prepare/), fichier des entrées, liste du groupe.
  referentiel: "beer_hops.json",
  fichierEntrees: "aromes.json",
  fichierGroupe: "houblons-recettes.json",
  formatGroupe: "kassbeer_houblons_recettes",
  scriptGroupe: "lister_ingredients_recettes.dart --nature hop",
  motifId: ID_HOUBLON,
  prefixeId: "hop-",
  /// Préfixe des custom_id d'un lot (h0001…) et nom de l'ingrédient dans la table du lot.
  /// --suivre accepte un lot sans champ `nature` (lot d'avant ADR-017, sans champ `nature`).
  lotsSansNature: true,
  prefixeCustomId: "h",
  champNom: "hop_name",
  mots: { un: "houblon", des: "houblons", Des: "Houblons", fichierExemple: "houblons.json" },
  /// Entrées par lancement, au plus (ADR-013, plafond 3 ; ADR-018, section 6).
  maxEntrees: 500,
  modele: MODELE,
  maxTokens: MAX_TOKENS,
  promptVersion: PROMPT_VERSION,
  donneesEnvoyees,
  empreinteEntree,
  parametresRequete,
  controlerSortieModele,
  controlerEntree: controlerEntreeArome,
  /// Entrée de aromes.json tirée d'une sortie contrôlée du modèle.
  construireEntree: (cible, resultat, { effort, date }) =>
    construireEntree(cible, resultat, {
      champNom: "hop_name",
      modele: MODELE,
      promptVersion: PROMPT_VERSION,
      effort,
      date,
    }),
  /// Refus de ecrire.mjs (lib/execution.mjs, trierRedigees).
  refus: {
    absent: "houblon absent de beer_hops.json",
    nonRelu: "houblon des recettes du groupe non relu",
  },
  /// Écriture par ecrire.mjs (lib/execution.mjs).
  ecriture: {
    collection: COLLECTION_AROMES,
    option: "aromes",
    nomDossier: "aromes",
    sousDossier: null,
    referentielCollection: "beer_hops",
    champFichier: "aromas_file",
    champSansDescription: "hops_without_aroma",
    sansDescription: "sans description aromatique",
  },
  relecture: {
    titre: "# Descriptions aromatiques à relire",
    intro: [
      "Houblons des recettes du groupe (houblons-recettes.json). Corrigez aromes.json, puis posez",
      '`reviewed: true` et `reviewed_at: "AAAA-MM-JJ"` sur chaque entrée relue.',
    ],
    /// Ligne des données envoyées pour un houblon du référentiel.
    donnees(data) {
      const d = donneesEnvoyees(data);
      return (
        `- Données envoyées : origine ${d.origin ?? "inconnue"}, alpha ${d.alpha_acid_pct ?? "?"} %, ` +
        `bêta ${d.beta_acid_pct ?? "?"} %, usage ${d.purpose ?? "inconnu"}` +
        (d.aliases.length > 0 ? `, autres noms : ${d.aliases.join(", ")}` : "")
      );
    },
    /// Lignes du contenu d'une entrée, après la ligne d'état.
    contenu(a) {
      const lignes = [];
      if (Array.isArray(a.descriptors) && a.descriptors.length > 0) {
        lignes.push(`- Descripteurs : ${a.descriptors.map((x) => x.label).join(", ")}`);
      }
      for (const u of USAGES) {
        if (a.uses?.[u]) lignes.push(`- ${LIBELLES_USAGES[u]} : ${a.uses[u].text}`);
      }
      return lignes;
    },
  },
});
