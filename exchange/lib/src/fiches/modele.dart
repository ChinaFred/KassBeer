import 'package:brewing/brewing.dart' show CostUnit, FeeBasis;

import '../compte_rendu.dart';

/// Types du format `kassbeer_fiches` v1 : fiches Excel préparées pour
/// Admin › Import (v0.6). Aucun texte affiché ici : l'application écrit les
/// libellés. Un texte tiré du fichier est une donnée, affichée en texte
/// simple, jamais interprétée (P9).

/// Raison du refus d'un fichier de fiches entier.
enum RaisonFichierFiches {
  /// Plus de 10 Mo.
  tropGros,

  /// Ni `beerjson` ni `kassbeer_fiches` lisibles : ce n'est pas un fichier de
  /// fiches.
  pasUnFichierDeFiches,

  /// `format_version` autre que 1.
  versionInconnue,

  /// Plus de [kMaxFiches] fiches.
  tropDeFiches,

  /// Deux fiches portent le même `fiche_id`.
  identifiantEnDouble,
}

/// Nature du refus d'une fiche. Le chemin du champ accompagne le code : aucune
/// valeur du fichier, donc aucun prix, n'entre dans un refus.
enum CodeRefusFiche {
  /// Champ inconnu du format.
  champInconnu,

  /// Champ obligatoire absent.
  champAbsent,

  /// Valeur d'un type inattendu (texte à la place d'un nombre…).
  typeInattendu,

  /// Valeur hors des bornes des règles ou du format.
  horsBornes,

  /// Identifiant ou date mal écrit.
  formatInvalide,

  /// Clé d'étape, identifiant d'événement ou clé de prix en double.
  enDouble,

  /// `step_key` absente de `brew_steps`.
  etapeInconnue,

  /// Mesure retenue qui ne désigne aucun événement du bon type.
  evenementInconnu,

  /// Texte qui contient une adresse web (FO5).
  adresseWeb,

  /// Texte lu par le groupe (nom, notes, note d'événement, étape, équipement,
  /// sucre de resucrage, nom et notes de la recette) qui contient un montant
  /// (« € », « EUR », « euro ») : les prix ne quittent pas le coût figé (P5,
  /// P9).
  montant,

  /// `recipe_index` hors de la liste des recettes du fichier.
  recetteAbsente,

  /// Recette refusée par la lecture BeerJSON ([RefusFiche.refusRecette]).
  recetteRefusee,

  /// Même `recipe_doc_id` qu'une fiche précédente, avec une autre recette ou
  /// une autre chronologie.
  recetteIncoherente,
}

/// Refus d'une fiche : [chemin] du champ (`events[12].measured_at`) et [code].
class RefusFiche {
  /// Crée le refus.
  const RefusFiche(this.chemin, this.code, {this.refusRecette});

  /// Chemin du champ dans l'entrée de la fiche.
  final String chemin;

  /// Nature du refus.
  final CodeRefusFiche code;

  /// Raison de la lecture BeerJSON, pour [CodeRefusFiche.recetteRefusee].
  final Refus? refusRecette;

  @override
  String toString() => 'RefusFiche($chemin, ${code.name})';
}

/// Une étape de la chronologie de la fiche (`brew_steps`).
class EtapeFiche {
  /// Crée l'étape.
  const EtapeFiche({
    required this.key,
    required this.name,
    required this.durationMin,
    this.tempC,
  });

  /// Clé de l'étape, unique dans la fiche.
  final String key;

  /// Nom de l'étape.
  final String name;

  /// Durée en minutes, de 0 à 600.
  final double durationMin;

  /// Température visée en °C, de 0 à 100, ou `null`.
  final double? tempC;
}

/// Nature d'un événement de fiche. Les fiches ne notent qu'une heure par
/// ligne : aucune fin ni saut d'étape (CR8).
enum NatureEvenementFiche {
  /// Début d'étape (`step_started`).
  debutEtape('step_started'),

  /// Mesure (`measurement`).
  mesure('measurement'),

  /// Note (`note`).
  note('note');

  const NatureEvenementFiche(this.valeur);

  /// Valeur du fichier, et de `kind` dans Firestore.
  final String valeur;
}

/// Type d'une mesure (`measure_type`).
enum TypeMesureFiche {
  /// °C, de 0 à 110.
  temperature('temperature'),

  /// SG, de 0,980 à 1,200.
  densite('gravity'),

  /// Litres, au-delà de 0 et jusqu'à 1 000.
  volume('volume'),

  /// pH, de 0 à 14.
  ph('ph');

  const TypeMesureFiche(this.valeur);

  /// Valeur du fichier, et de `measure_type` dans Firestore.
  final String valeur;
}

/// Origine de l'heure d'un événement, fixée par la préparation (CR5, CR6,
/// CR12). L'application ne calcule aucune date.
enum OrigineHeure {
  /// Heure notée dans la fiche.
  fiche('fiche'),

  /// Heure réelle de la ligne précédente (CR5).
  lignePrecedente('ligne_precedente'),

  /// Heure de début du plan (CR5).
  debutBrassage('debut_brassage'),

  /// Relevé sans heure, à 12:00 du jour noté (CR6).
  midi('midi'),

  /// Densité finale de l'en-tête, datée du jour du brassage + 28 jours, à
  /// 12:00 (CR12).
  estimeeJ28('estimee_j28');

  const OrigineHeure(this.valeur);

  /// Valeur du fichier.
  final String valeur;
}

/// Un événement de la fiche : début d'étape, mesure ou note.
class EvenementFiche {
  /// Crée l'événement.
  const EvenementFiche({
    required this.id,
    required this.nature,
    required this.measuredAt,
    required this.origineHeure,
    this.stepKey,
    this.typeMesure,
    this.valeur,
    this.note,
    this.fermentation = false,
  });

  /// Identifiant du document `events/{id}`, fixé par la préparation.
  final String id;

  /// Nature.
  final NatureEvenementFiche nature;

  /// Étape concernée, ou `null` pour une mesure ou une note sans étape.
  final String? stepKey;

  /// Type d'une mesure.
  final TypeMesureFiche? typeMesure;

  /// Valeur d'une mesure, unités du système international.
  final double? valeur;

  /// Note, 2 000 caractères au plus.
  final String? note;

  /// Heure de la mesure, écrite par la préparation avec son décalage.
  final DateTime measuredAt;

  /// Vrai pour un relevé de fermentation (`phase: fermentation`).
  final bool fermentation;

  /// Origine de [measuredAt].
  final OrigineHeure origineHeure;
}

/// Type de la copie d'équipement d'un brassin importé (EQ2).
enum TypeEquipementFiche {
  /// Installation à cuves (`multi_vessel`).
  cuves('multi_vessel'),

  /// Tout-en-un, « Brew in bag » (`all_in_one`).
  toutEnUn('all_in_one');

  const TypeEquipementFiche(this.valeur);

  /// Valeur du fichier, et de `kind` dans Firestore.
  final String valeur;
}

/// Brassin de la fiche.
class BrassinFiche {
  /// Crée le brassin.
  const BrassinFiche({
    required this.name,
    required this.plannedFor,
    required this.startAt,
    required this.equipementNom,
    required this.equipementType,
    this.notes,
    this.bottlesCount,
    this.packagedVolumeL,
    this.primingSugarName,
  });

  /// Nom du brassin, 120 caractères au plus.
  final String name;

  /// Jour du brassage.
  final DateTime plannedFor;

  /// Heure de début du plan (CR4).
  final DateTime startAt;

  /// Notes du brassin, lues par le groupe : aucun prix (DR4).
  final String? notes;

  /// Nombre de bouteilles, de 1 à 9 999.
  final int? bottlesCount;

  /// Volume conditionné, en litres.
  final double? packagedVolumeL;

  /// Nature du sucre de resucrage, 80 caractères au plus.
  final String? primingSugarName;

  /// Nom de la copie d'équipement.
  final String equipementNom;

  /// Type de la copie d'équipement.
  final TypeEquipementFiche equipementType;
}

/// Prix d'un ingrédient noté dans la fiche (Q1). Lu par Admin › Import seul,
/// écrit dans le seul coût figé de l'administrateur (P9).
class PrixFiche {
  /// Crée le prix.
  const PrixFiche({
    required this.key,
    required this.name,
    required this.priceEur,
    required this.quantity,
    required this.unit,
  });

  /// Clé d'ingrédient (`ingredientKey`).
  final String key;

  /// Nom de l'ingrédient.
  final String name;

  /// Prix payé, en euros.
  final double priceEur;

  /// Quantité achetée, dans [unit].
  final double quantity;

  /// Gramme, sachet ou litre.
  final CostUnit unit;
}

/// Frais noté dans la fiche (eau, électricité, détergent, embouteillage).
class FraisFiche {
  /// Crée le frais.
  const FraisFiche({
    required this.name,
    required this.amountEur,
    required this.basis,
  });

  /// Nom du frais, 60 caractères au plus.
  final String name;

  /// Montant, en euros.
  final double amountEur;

  /// Par brassin ou par bouteille.
  final FeeBasis basis;
}

/// Prix et frais d'une fiche.
class CoutFiche {
  /// Crée le coût.
  const CoutFiche({
    required this.prix,
    required this.frais,
    this.totalFicheEur,
  });

  /// Prix des ingrédients.
  final List<PrixFiche> prix;

  /// Frais hors ingrédients.
  final List<FraisFiche> frais;

  /// Total noté dans la fiche, pour l'écart (CO3).
  final double? totalFicheEur;
}

/// Correction validée par l'utilisateur pendant la préparation (PR4).
class CorrectionFiche {
  /// Crée la correction.
  const CorrectionFiche({
    required this.sujet,
    required this.valeurFiche,
    required this.valeurImportee,
    required this.raison,
  });

  /// Ce qui est corrigé (« Citra, quantité »).
  final String sujet;

  /// Valeur lue dans la fiche.
  final String valeurFiche;

  /// Valeur importée.
  final String valeurImportee;

  /// Raison de la correction.
  final String raison;
}

/// Fiche lue.
class FicheLue {
  /// Crée la fiche.
  const FicheLue({
    required this.ficheId,
    required this.recipeIndex,
    required this.recipeDocId,
    required this.recette,
    required this.etapes,
    required this.brassin,
    required this.evenements,
    this.ogEventId,
    this.fgEventId,
    this.fermenterVolumeEventId,
    this.cout,
    this.corrections = const [],
    this.deductions = const [],
    this.divergences = const [],
    this.nonImporte = const [],
  });

  /// Identifiant de la fiche (`^[a-z0-9-]{1,60}$`).
  final String ficheId;

  /// Rang de la recette dans `beerjson.recipes`, à partir de 0.
  final int recipeIndex;

  /// Identifiant du document `recipes/{id}`.
  final String recipeDocId;

  /// Recette lue par la lecture BeerJSON.
  final RecetteLue recette;

  /// Chronologie de la recette (`brew_steps`).
  final List<EtapeFiche> etapes;

  /// Brassin.
  final BrassinFiche brassin;

  /// Événements, dans l'ordre du fichier.
  final List<EvenementFiche> evenements;

  /// Densité initiale retenue.
  final String? ogEventId;

  /// Densité finale retenue.
  final String? fgEventId;

  /// Volume en fermenteur retenu.
  final String? fermenterVolumeEventId;

  /// Prix et frais, ou `null` si la fiche n'en donne pas.
  final CoutFiche? cout;

  /// Corrections validées (PR4).
  final List<CorrectionFiche> corrections;

  /// Valeurs déduites de la chronologie (PR5).
  final List<String> deductions;

  /// Divergences de la fiche.
  final List<String> divergences;

  /// Ce qui n'est pas importé (CR10).
  final List<String> nonImporte;
}

/// Résultat de la lecture d'une fiche.
sealed class ResultatFiche {
  const ResultatFiche();
}

/// Fiche refusée : les autres restent importables.
class FicheRefusee extends ResultatFiche {
  /// Crée le résultat.
  const FicheRefusee(this.refus);

  /// Raison du refus.
  final RefusFiche refus;
}

/// Fiche acceptée.
class FicheAcceptee extends ResultatFiche {
  /// Crée le résultat.
  const FicheAcceptee(this.fiche);

  /// Fiche lue.
  final FicheLue fiche;
}

/// Une entrée de `kassbeer_fiches.fiches`.
class FicheDuFichier {
  /// Crée l'entrée.
  const FicheDuFichier({
    required this.numero,
    required this.ficheId,
    required this.empreinte,
    required this.resultat,
  });

  /// Rang dans le fichier, à partir de 1.
  final int numero;

  /// `fiche_id` s'il est lisible, sinon `null`.
  final String? ficheId;

  /// Empreinte de l'entrée et de sa recette (`sha256:…`) : un second import
  /// du même contenu la retrouve, un contenu changé en donne une autre.
  final String empreinte;

  /// Fiche lue ou refusée.
  final ResultatFiche resultat;
}

/// Résultat de la lecture d'un fichier de fiches.
sealed class LectureFiches {
  const LectureFiches();
}

/// Fichier refusé entier.
class FichierFichesRefuse extends LectureFiches {
  /// Crée le résultat.
  const FichierFichesRefuse(this.raison, {this.taille, this.ficheId});

  /// Raison.
  final RaisonFichierFiches raison;

  /// Taille en octets, pour [RaisonFichierFiches.tropGros].
  final int? taille;

  /// Identifiant en double, pour [RaisonFichierFiches.identifiantEnDouble].
  final String? ficheId;
}

/// Fichier lu.
class FichierFiches extends LectureFiches {
  /// Crée le résultat.
  const FichierFiches({required this.recettes, required this.fiches});

  /// Recettes de `beerjson`, lues par `analyserFichier`.
  final List<RecetteDuFichier> recettes;

  /// Fiches, dans l'ordre du fichier.
  final List<FicheDuFichier> fiches;
}

/// Nombre de fiches au plus dans un fichier (FO4).
const int kMaxFiches = 50;

/// Événements au plus par fiche (FO4).
const int kMaxEvenementsParFiche = 300;

/// Lignes de prix et de frais au plus, ensemble (`firestore.rules`,
/// `brew_costs.lines`).
const int kMaxLignesCoutFiche = 200;

/// Éléments au plus d'une liste de corrections, déductions, divergences ou de
/// ce qui n'est pas importé (FO4).
const int kMaxElementsListeFiche = 200;
