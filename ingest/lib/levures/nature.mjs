// Nature « levure » du moteur de rédaction (ADR-017 ; ADR-019, section 2) : descriptions
// aromatiques des levures, écrites dans beer_culture_aromas/ par ecrire.mjs. Ce fichier dit au
// moteur (lib/redaction/moteur.mjs) ce qui est propre aux levures : poste de coût, fichiers,
// périmètre par type, styles du prompt (contexte), données envoyées, empreinte, prompt,
// contrôle, a-relire.md. N'importe pas le SDK d'Anthropic.
//
// Fichiers de import/ingest/aromes/levures/ (jamais versionnés) :
//   aromes.json              entrées {id, data}, copie de référence, corrigée à la main
//   noms-levures.json        noms des levures des recettes (lister-ingredients-recettes.mjs --nature culture)
//   levures-recettes.json    levures des recettes du groupe (exchange/bin/lister_ingredients_recettes.dart --nature culture)
//   lot-<id>.json            table custom_id → levure d'un lot de l'API Batches
//   brut/                    réponses de chaque exécution, effort dans le nom
//   rapport.json             dernière exécution : poste, modèle, effort, jetons, montant
//   a-relire.md              levures du groupe à relire
// Le tarif est lu dans import/ingest/tarif.json, commun aux natures (ADR-019).

import { fileURLToPath } from "node:url";
import { construireEntree } from "../redaction/entree.mjs";
import { parametresRequeteLevure } from "./prompt.mjs";
import {
  COLLECTION_AROMES_LEVURES,
  contexteLevures,
  contexteStyles,
  controlerEntreeAromeLevure,
  controlerSortieLevure,
  dansPerimetreLevure,
  donneesEnvoyeesLevure,
  empreinteEntreeLevure,
  ID_LEVURE,
  MAX_TOKENS,
  MODELE,
  POSTE_LEVURES,
  PROMPT_VERSION_LEVURES,
  TEXTES_LEVURE,
  TYPES_HORS_PERIMETRE,
} from "./validation.mjs";

const LIBELLES_TEXTES = { profile: "Profil", cool: "En bas de plage", warm: "En haut de plage" };

const textePlage = (p, unite) =>
  p === null ? "inconnue" : `${p[0] ?? "?"} à ${p[1] ?? "?"} ${unite}`;

export const NATURE_LEVURE = Object.freeze({
  /// Valeur de --nature (generer-aromes.mjs, lister-ingredients-recettes.mjs) et du champ
  /// `nature` d'un lot.
  cle: "culture",
  /// Poste de coût porté par chaque rapport (catalogue « Coûts variables »).
  poste: POSTE_LEVURES,
  adr: "ADR-017",
  script: "generer-aromes.mjs",
  /// Commande de la nature, citée dans les messages (« Suivi : node … --suivre <id> »).
  commande: "generer-aromes.mjs --nature culture",
  /// Option qui remplace le dossier des arômes, dossier par défaut et sous-dossier de la
  /// nature : levures dans import/ingest/aromes/levures/.
  optionDossier: "--aromes",
  dossierDefaut: fileURLToPath(new URL("../../../import/ingest/aromes/", import.meta.url)),
  sousDossier: "levures",
  /// Référentiel préparé (import/ingest/prepare/), fichier des entrées, liste du groupe.
  referentiel: "beer_cultures.json",
  fichierEntrees: "aromes.json",
  fichierGroupe: "levures-recettes.json",
  formatGroupe: "kassbeer_levures_recettes",
  scriptGroupe: "lister_ingredients_recettes.dart --nature culture",
  motifId: ID_LEVURE,
  prefixeId: "culture-",
  /// Préfixe des custom_id d'un lot (c0001…) et nom de l'ingrédient dans la table du lot.
  /// --suivre accepte un lot sans champ `nature` (tout lot de levures porte `nature: "culture"` depuis la v0.1.93).
  lotsSansNature: false,
  prefixeCustomId: "c",
  champNom: "culture_name",
  mots: { un: "levure", des: "levures", Des: "Levures", fichierExemple: "levures.json" },
  /// Entrées par lancement, au plus (décision de l'utilisateur du 2026-11-22 : les 923
  /// levures en un seul lot).
  maxEntrees: 1000,
  modele: MODELE,
  maxTokens: MAX_TOKENS,
  promptVersion: PROMPT_VERSION_LEVURES,
  /// Refus de ecrire.mjs (lib/execution.mjs, trierRedigees).
  refus: {
    absent: "levure absente de beer_cultures.json",
    nonRelu: "levure des recettes du groupe non relue",
  },
  /// Périmètre : levures du groupe, plus celles dont le type n'est pas exclu (ADR-017,
  /// décision 1).
  perimetre: { typesExclus: TYPES_HORS_PERIMETRE, dansPerimetre: dansPerimetreLevure },
  /// Styles du prompt, lus une fois par exécution dans beer_styles.json préparé.
  contexte: contexteLevures,
  messageContexte: (contexte) =>
    contexte.refuses.length > 0
      ? `beer_styles.json : ${contexte.refuses.length} styles refusés au contrôle, absents de ` +
        `la liste du prompt : ${contexte.refuses.slice(0, 20).join(", ")}.`
      : null,
  donneesEnvoyees: donneesEnvoyeesLevure,
  empreinteEntree: (donnees, { effort, contexte }) =>
    empreinteEntreeLevure(donnees, { effort, stylesSha256: contexte.stylesSha256 }),
  parametresRequete: (donnees, { effort, cache, contexte }) =>
    parametresRequeteLevure(donnees, { effort, cache, contexte }),
  controlerSortieModele: controlerSortieLevure,
  controlerEntree: controlerEntreeAromeLevure,
  /// Entrée de levures/aromes.json tirée d'une sortie contrôlée du modèle.
  construireEntree: (cible, resultat, { effort, date }) =>
    construireEntree(cible, resultat, {
      champNom: "culture_name",
      modele: MODELE,
      promptVersion: PROMPT_VERSION_LEVURES,
      effort,
      date,
    }),
  /// Écriture par ecrire.mjs (lib/execution.mjs).
  ecriture: {
    collection: COLLECTION_AROMES_LEVURES,
    option: "aromes",
    nomDossier: "aromes",
    sousDossier: "levures",
    referentielCollection: "beer_cultures",
    champFichier: "culture_aromas_file",
    /// Aucun compte des levures sans description : le périmètre écarte des types entiers.
    champSansDescription: null,
    sansDescription: "sans description aromatique",
    /// Styles acceptés par l'écrivain (trier()), contre lesquels une entrée est contrôlée.
    contexteEcriture: (valides) => contexteStyles(valides.beer_styles),
  },
  relecture: {
    titre: "# Descriptions aromatiques à relire",
    intro: [
      "Levures des recettes du groupe (levures-recettes.json). Corrigez aromes.json, puis posez",
      '`reviewed: true` et `reviewed_at: "AAAA-MM-JJ"` sur chaque entrée relue.',
    ],
    /// Ligne des données envoyées pour une levure du référentiel.
    donnees(data) {
      const d = donneesEnvoyeesLevure(data);
      return (
        `- Données envoyées : producteur ${d.producer ?? "inconnu"}, référence ` +
        `${d.product_id ?? "inconnue"}, type ${d.type ?? "inconnu"}, forme ${d.form ?? "inconnue"}, ` +
        `atténuation ${textePlage(d.attenuation_pct, "%")}, température ` +
        `${textePlage(d.temperature_c, "°C")}, floculation ${d.flocculation ?? "inconnue"}` +
        (d.aliases.length > 0 ? `, autres noms : ${d.aliases.join(", ")}` : "")
      );
    },
    /// Lignes du contenu d'une entrée, après la ligne d'état.
    contenu(a) {
      const lignes = [];
      if (Array.isArray(a.descriptors) && a.descriptors.length > 0) {
        lignes.push(`- Descripteurs : ${a.descriptors.map((x) => x.label).join(", ")}`);
      }
      for (const t of TEXTES_LEVURE) {
        if (a.texts?.[t]) lignes.push(`- ${LIBELLES_TEXTES[t]} : ${a.texts[t].text}`);
      }
      if (Array.isArray(a.styles) && a.styles.length > 0) {
        lignes.push(`- Styles conseillés : ${a.styles.map((s) => s.name).join(", ")}`);
      }
      return lignes;
    },
  },
});
