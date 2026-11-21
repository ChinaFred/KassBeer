// Nature « divers » du moteur de rédaction (ADR-017) : descriptions des divers (moment, rôle,
// goût, sans dose), écrites dans beer_misc_descriptions/ par ecrire.mjs. Ce fichier dit au
// moteur (lib/redaction/moteur.mjs) ce qui est propre aux divers : poste de coût, fichiers,
// données envoyées, empreinte, prompt, contrôle, a-relire.md. N'importe pas le SDK
// d'Anthropic.
//
// Fichiers de import/ingest/divers/ (jamais versionnés) :
//   descriptions.json   entrées {id, data}, copie de référence, corrigée à la main
//   noms-divers.json    noms des divers des recettes (lister-divers-recettes.mjs)
//   divers-recettes.json  divers des recettes du groupe (exchange/bin/lister_divers_recettes.dart)
//   lot-<id>.json       table custom_id → divers d'un lot de l'API Batches
//   brut/               réponses de chaque exécution, effort dans le nom
//   rapport.json        dernière exécution : poste, modèle, effort, jetons, montant
//   a-relire.md         divers du groupe à relire
// Le tarif est lu dans import/ingest/tarif.json, commun aux natures.

import { fileURLToPath } from "node:url";
import { construireEntree } from "../redaction/entree.mjs";
import { MAX_TOKENS, MODELE, parametresRequete, PROMPT_VERSION } from "./prompt.mjs";
import {
  COLLECTION_DIVERS,
  controlerEntreeDivers,
  controlerSortieModele,
  donneesEnvoyees,
  empreinteEntree,
  ID_DIVERS,
  MOMENTS,
} from "./validation.mjs";

/// Libellés des moments dans a-relire.md, ceux d'OtherUse dans l'éditeur de recette.
const LIBELLES_MOMENTS = {
  mash: "Empâtage",
  boil: "Ébullition",
  after_boil: "Après ébullition",
  fermentation: "Fermentation",
  bottling: "Embouteillage",
};

export const NATURE_DIVERS = Object.freeze({
  /// Poste de coût porté par chaque rapport (catalogue « Coûts variables »).
  poste: "misc_description_generation",
  adr: "ADR-017",
  script: "generer-divers.mjs",
  /// Option qui remplace le dossier de la nature, et dossier par défaut.
  optionDossier: "--divers",
  dossierDefaut: fileURLToPath(new URL("../../../import/ingest/divers/", import.meta.url)),
  /// Référentiel préparé (import/ingest/prepare/), fichier des entrées, liste du groupe.
  referentiel: "beer_miscs.json",
  fichierEntrees: "descriptions.json",
  fichierGroupe: "divers-recettes.json",
  formatGroupe: "kassbeer_divers_recettes",
  scriptGroupe: "lister_divers_recettes.dart",
  motifId: ID_DIVERS,
  prefixeId: "misc-",
  /// Préfixe des custom_id d'un lot (m0001…) et nom de l'ingrédient dans la table du lot.
  prefixeCustomId: "m",
  champNom: "misc_name",
  mots: { un: "divers", des: "divers", Des: "Divers", fichierExemple: "divers.json" },
  modele: MODELE,
  maxTokens: MAX_TOKENS,
  promptVersion: PROMPT_VERSION,
  donneesEnvoyees,
  empreinteEntree,
  parametresRequete,
  controlerSortieModele,
  controlerEntree: controlerEntreeDivers,
  /// Entrée de descriptions.json tirée d'une sortie contrôlée du modèle.
  construireEntree: (cible, resultat, { effort, date }) =>
    construireEntree(cible, resultat, {
      champNom: "misc_name",
      modele: MODELE,
      promptVersion: PROMPT_VERSION,
      effort,
      date,
    }),
  /// Écriture par ecrire.mjs (lib/execution.mjs).
  ecriture: {
    collection: COLLECTION_DIVERS,
    option: "divers",
    nomDossier: "divers",
    referentielCollection: "beer_miscs",
    scriptNoms: "lister-divers-recettes.mjs",
    champFichier: "misc_descriptions_file",
    champSansDescription: "miscs_without_description",
    sansDescription: "sans description",
  },
  relecture: {
    titre: "# Descriptions des divers à relire",
    intro: [
      "Divers des recettes du groupe (divers-recettes.json). Corrigez descriptions.json, puis posez",
      '`reviewed: true` et `reviewed_at: "AAAA-MM-JJ"` sur chaque entrée relue.',
      "Vérifiez qu'aucun texte ne donne de dose et que chaque moment est juste.",
    ],
    /// Ligne des données envoyées pour un divers du référentiel.
    donnees(data) {
      const d = donneesEnvoyees(data);
      return (
        `- Données envoyées : type ${d.type ?? "inconnu"}, libellé ${d.label_fr ?? "aucun"}` +
        (d.aliases.length > 0 ? `, autres noms : ${d.aliases.join(", ")}` : "")
      );
    },
    /// Lignes du contenu d'une entrée, après la ligne d'état.
    contenu(a) {
      const lignes = [];
      if (typeof a.summary === "string") lignes.push(`- Résumé : ${a.summary}`);
      if (Array.isArray(a.roles) && a.roles.length > 0) {
        lignes.push(`- Rôles : ${a.roles.map((x) => x.label).join(", ")}`);
      }
      for (const m of MOMENTS) {
        if (a.moments?.[m]) lignes.push(`- ${LIBELLES_MOMENTS[m]} : ${a.moments[m].text}`);
      }
      if (a.changes_taste === true && a.taste) lignes.push(`- Goût : ${a.taste.text}`);
      if (a.changes_taste === false) lignes.push("- Goût : aucun");
      return lignes;
    },
  },
});
