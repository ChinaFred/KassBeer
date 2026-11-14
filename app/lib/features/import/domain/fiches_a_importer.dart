import 'package:exchange/exchange.dart';
import 'package:exchange/fiches.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../brews/domain/brew_event.dart';
import '../../costs/domain/brew_cost.dart';
import '../../costs/domain/cost_evaluation.dart';
import '../../costs/domain/fee.dart';
import '../../costs/domain/price.dart';
import '../../recipes/domain/chronologie.dart';
import '../../recipes/domain/recipe.dart';

/// Admin › Import (v0.6) : fiches Excel préparées en JSON, lues par
/// `package:exchange/fiches.dart`, comparées à ce qui est déjà enregistré,
/// puis écrites sous le compte de l'administrateur. Ce fichier ne lit rien et
/// n'écrit rien : il prépare les documents et le plan d'écriture d'une fiche.
/// Aucune formule de brassage ici : le coût figé passe par [evaluerFigeage],
/// donc par `brewing/` (P3). Aucune date n'est calculée : chaque heure vient
/// du fichier (Q2).

/// Identifiant du brassin d'une fiche (ID1).
String brewIdDeFiche(String ficheId) => 'fiche-$ficheId';

/// `imported_from` d'une recette importée d'une fiche.
String importedFromRecette(String ficheId) => 'Fiche Excel · $ficheId';

/// Préfixe de la marque de fin d'un brassin de [ficheId].
String _prefixeMarque(String ficheId) => 'Fiche Excel · $ficheId · ';

/// `imported_from` d'un brassin complet (CR3) : fiche et empreinte de son
/// entrée et de sa recette, 200 caractères au plus.
String marqueDeFin(String ficheId, String empreinte) =>
    '${_prefixeMarque(ficheId)}$empreinte';

/// Brassin déjà enregistré à l'identifiant d'une fiche, lu sur le serveur.
@immutable
class BrassinExistant {
  const BrassinExistant({
    required this.ownerUid,
    this.importedFrom,
    this.brewedAt,
    this.bottlesCount,
    this.packagedVolumeL,
    this.primingSugarName,
    this.notes,
    this.ogEventId,
    this.fgEventId,
    this.fermenterVolumeEventId,
    this.eventIds = const {},
  });

  final String ownerUid;
  final String? importedFrom;
  final DateTime? brewedAt;
  final int? bottlesCount;
  final double? packagedVolumeL;
  final String? primingSugarName;
  final String? notes;
  final String? ogEventId;
  final String? fgEventId;
  final String? fermenterVolumeEventId;

  /// Identifiants des événements déjà écrits.
  final Set<String> eventIds;
}

/// Ce que le serveur porte aux identifiants du fichier (EC3).
@immutable
class EtatServeur {
  const EtatServeur({
    this.recettes = const {},
    this.brassins = const {},
    this.coutsFiges = const {},
    this.evenementsDAutrui = const {},
  });

  /// Propriétaire de chaque recette existante, par identifiant.
  final Map<String, String> recettes;

  /// Brassins existants, par identifiant.
  final Map<String, BrassinExistant> brassins;

  /// Brassins dont le coût figé de l'administrateur existe.
  final Set<String> coutsFiges;

  /// Brassins dont un événement appartient à un autre compte, brassin présent
  /// ou non (S2).
  final Set<String> evenementsDAutrui;
}

/// État d'une fiche à l'analyse (EC4).
enum EtatFiche { nouvelle, aCompleter, dejaImportee, contenuDifferent, refusee }

/// Raison du refus d'une fiche.
@immutable
sealed class RefusImport {
  const RefusImport();
}

/// Refus du lecteur `kassbeer_fiches`.
class RefusDeLecture extends RefusImport {
  const RefusDeLecture(this.refus);

  final RefusFiche refus;
}

/// Recette lue par `exchange/` que l'application ne relit pas (déjà
/// rapporté).
class RecetteNonRelue extends RefusImport {
  const RecetteNonRelue();
}

/// Un document d'un autre membre porte l'identifiant de la recette ou du
/// brassin : l'écriture serait refusée par les règles.
class DocumentDUnAutreMembre extends RefusImport {
  const DocumentDUnAutreMembre();
}

/// Coût figé d'une fiche, préparé à l'analyse.
@immutable
sealed class CoutDeFiche {
  const CoutDeFiche();
}

/// La fiche ne donne aucun prix.
class SansPrix extends CoutDeFiche {
  const SansPrix();
}

/// Coût calculé par `brewing/` avec les prix et frais de la fiche (Q1).
class CoutCalcule extends CoutDeFiche {
  const CoutCalcule(this.cout, {this.totalFicheEur});

  final BrewCost cout;

  /// Total noté dans la fiche, pour l'écart (CO3).
  final double? totalFicheEur;
}

/// Coût impossible à figer (CO2), avec ses raisons.
class CoutImpossible extends CoutDeFiche {
  const CoutImpossible(this.raisons, {this.totalFicheEur});

  final List<RaisonCout> raisons;
  final double? totalFicheEur;
}

/// Une fiche du fichier, prête pour l'aperçu et l'écriture.
@immutable
class FicheAImporter {
  const FicheAImporter({
    required this.source,
    this.fiche,
    this.refus,
    this.recette,
    this.modifications = const [],
    this.reprises = const [],
    this.evenements = const [],
    this.brewedAt,
    this.cout = const SansPrix(),
  });

  /// Entrée du fichier : rang, identifiant, empreinte.
  final FicheDuFichier source;

  /// Fiche lue, ou `null` si le lecteur l'a refusée.
  final FicheLue? fiche;

  /// Raison du refus, ou `null`.
  final RefusImport? refus;

  /// Recette relue par l'application : sous-arbre `recipe` complété par la
  /// Bibliothèque, chronologie de la fiche, sans équipement (EQ1).
  final RecipeContent? recette;

  /// Changements faits à la lecture de la recette.
  final List<Modification> modifications;

  /// Valeurs reprises de la Bibliothèque.
  final List<ValeurReprise> reprises;

  /// Événements à écrire, sous l'administrateur, identifiants du fichier.
  final List<BrewEvent> evenements;

  /// Heure du premier début d'étape, sinon début du plan (CR4).
  final DateTime? brewedAt;

  /// Coût figé de la fiche.
  final CoutDeFiche cout;

  String get brewId => brewIdDeFiche(fiche?.ficheId ?? '');

  /// Marque de fin attendue sur le brassin (CR3).
  String? get marque {
    final f = fiche;
    return f == null ? null : marqueDeFin(f.ficheId, source.empreinte);
  }

  /// Vrai si aucun début d'étape ne date le brassage (CR4).
  bool get brassageDateParLePlan =>
      fiche != null &&
      !fiche!.evenements.any(
        (e) => e.nature == NatureEvenementFiche.debutEtape,
      );
}

/// Prépare chaque fiche de [lu] pour [uid] (l'administrateur). [index] :
/// index de la Bibliothèque, comme Recettes › Importer (FO2). Une recette
/// lue par `exchange/` que l'application ne relit pas est rapportée sans son
/// contenu et refuse sa fiche.
List<FicheAImporter> preparerFiches(
  FichierFiches lu, {
  required String uid,
  required IndexImport index,
  required ErrorReportService errors,
  required Set<String> reported,
}) => [for (final f in lu.fiches) _preparer(f, uid, index, errors, reported)];

FicheAImporter _preparer(
  FicheDuFichier source,
  String uid,
  IndexImport index,
  ErrorReportService errors,
  Set<String> reported,
) {
  final FicheLue fiche;
  switch (source.resultat) {
    case FicheRefusee(:final refus):
      return FicheAImporter(source: source, refus: RefusDeLecture(refus));
    case FicheAcceptee(fiche: final lue):
      fiche = lue;
  }
  final completee = completerRecette(fiche.recette.recipe, index);
  final RecipeContent recette;
  try {
    recette = RecipeContent.fromFirestore({
      'format_version': 1,
      'imported_from': importedFromRecette(fiche.ficheId),
      'brew_steps': [
        for (final e in fiche.etapes)
          BrewStepLine(
            key: e.key,
            name: e.name,
            durationMin: e.durationMin,
            tempC: e.tempC,
          ).toFirestore(),
      ],
      'recipe': completee.recipe,
    });
  } on DocumentIllisible catch (error, stackTrace) {
    // Le champ fautif est un chemin, sans valeur ni prix.
    errors.reportError(
      feature: 'import.fiches',
      error: error,
      stackTrace: stackTrace,
      context: 'fiche n° ${source.numero}, recette relue illisible',
    );
    return FicheAImporter(
      source: source,
      fiche: fiche,
      refus: const RecetteNonRelue(),
    );
  }
  final evenements = [
    for (final e in fiche.evenements)
      BrewEvent(
        id: e.id,
        ownerUid: uid,
        kind: switch (e.nature) {
          NatureEvenementFiche.debutEtape => BrewEventKind.started,
          NatureEvenementFiche.mesure => BrewEventKind.measurement,
          NatureEvenementFiche.note => BrewEventKind.note,
        },
        stepKey: e.stepKey,
        measureType: switch (e.typeMesure) {
          null => null,
          TypeMesureFiche.temperature => MeasureType.temperature,
          TypeMesureFiche.densite => MeasureType.gravity,
          TypeMesureFiche.volume => MeasureType.volume,
          TypeMesureFiche.ph => MeasureType.ph,
        },
        value: e.valeur,
        note: e.note,
        measuredAt: e.measuredAt,
        phase: e.fermentation ? PhaseEvenement.fermentation : null,
      ),
  ];
  DateTime? premier;
  for (final e in fiche.evenements) {
    if (e.nature != NatureEvenementFiche.debutEtape) continue;
    if (premier == null || e.measuredAt.isBefore(premier)) {
      premier = e.measuredAt;
    }
  }
  final brewedAt = premier ?? fiche.brassin.startAt;
  return FicheAImporter(
    source: source,
    fiche: fiche,
    recette: recette,
    modifications: fiche.recette.modifications,
    reprises: completee.reprises,
    evenements: List.unmodifiable(evenements),
    brewedAt: brewedAt,
    cout: _cout(fiche, recette, brewedAt, errors, reported),
  );
}

/// Coût figé avec les prix et frais de la fiche (Q1, CO1), comme au figeage
/// de la v0.5 : quantités de la copie figée, valeurs d'embouteillage de la
/// fiche, `computed_at` au jour du brassage. Les prix ne vont nulle part
/// ailleurs que dans ce coût (P9).
CoutDeFiche _cout(
  FicheLue fiche,
  RecipeContent recette,
  DateTime brewedAt,
  ErrorReportService errors,
  Set<String> reported,
) {
  final cout = fiche.cout;
  if (cout == null) return const SansPrix();
  final prix = ListeLue<Price>(
    documents: [
      for (final p in cout.prix)
        DocumentValide(
          p.key,
          Price(
            key: p.key,
            name: p.name,
            priceEur: p.priceEur,
            quantity: p.quantity,
            unit: p.unit,
          ),
        ),
    ],
    fromCache: false,
  );
  final frais = ListeLue<Fee>(
    documents: [
      for (final (i, f) in cout.frais.indexed)
        DocumentValide(
          'fiche-${i + 1}',
          Fee(
            id: 'fiche-${i + 1}',
            name: f.name,
            amountEur: f.amountEur,
            basis: f.basis,
          ),
        ),
    ],
    fromCache: false,
  );
  final evaluation = evaluerFigeage(
    brewId: brewIdDeFiche(fiche.ficheId),
    recipe: recette,
    bottlesCount: fiche.brassin.bottlesCount,
    packagedVolumeL: fiche.brassin.packagedVolumeL,
    primingSugarG: null,
    primingSugarName: fiche.brassin.primingSugarName,
    prices: prix,
    fees: frais,
    kind: FreezeKind.initial,
    now: brewedAt,
    errors: errors,
    reported: reported,
  );
  return switch (evaluation) {
    FigeagePossible(:final cout) => CoutCalcule(
      cout,
      totalFicheEur: fiche.cout?.totalFicheEur,
    ),
    FigeageImpossible(:final raisons) => CoutImpossible(
      raisons,
      totalFicheEur: fiche.cout?.totalFicheEur,
    ),
  };
}

/// État de [f] face au serveur (EC4), et raison d'un refus.
({EtatFiche etat, RefusImport? refus}) etatDe(
  FicheAImporter f,
  EtatServeur serveur, {
  required String uid,
}) {
  final fiche = f.fiche;
  if (f.refus != null || fiche == null) {
    return (etat: EtatFiche.refusee, refus: f.refus);
  }
  final proprietaireRecette = serveur.recettes[fiche.recipeDocId];
  final brassin = serveur.brassins[f.brewId];
  if ((proprietaireRecette != null && proprietaireRecette != uid) ||
      (brassin != null && brassin.ownerUid != uid) ||
      serveur.evenementsDAutrui.contains(f.brewId)) {
    return (etat: EtatFiche.refusee, refus: const DocumentDUnAutreMembre());
  }
  if (brassin == null) return (etat: EtatFiche.nouvelle, refus: null);
  final marque = brassin.importedFrom;
  if (marque == null) return (etat: EtatFiche.aCompleter, refus: null);
  if (marque == f.marque) return (etat: EtatFiche.dejaImportee, refus: null);
  return (etat: EtatFiche.contenuDifferent, refus: null);
}

/// Vrai si l'état se coche, et se coche par défaut (EC4).
bool cochable(EtatFiche etat) =>
    etat == EtatFiche.nouvelle || etat == EtatFiche.aCompleter;

// ---------------------------------------------------------------- Plan

/// Étape d'écriture d'une fiche, nommée au compte rendu (EC8, EC10).
enum EtapeEcriture {
  recette('recette'),
  brassin('brassin'),
  dateDeBrassage('date de brassage'),
  embouteillage('embouteillage'),
  notes('notes'),
  evenements('événements'),
  mesuresRetenues('mesures retenues'),
  cout('coût figé'),
  marque('marque de fin');

  const EtapeEcriture(this.libelle);

  final String libelle;
}

/// Une écriture du plan d'une fiche : un document, une modification ou un lot.
@immutable
sealed class EcritureImport {
  const EcritureImport(this.etape);

  final EtapeEcriture etape;
}

/// Création de `recipes/{id}`.
class CreationRecette extends EcritureImport {
  const CreationRecette(this.recipeId, this.content)
    : super(EtapeEcriture.recette);

  final String recipeId;
  final RecipeContent content;
}

/// Création de `brews/{id}`, statut `done`, sans `imported_from` (CR3).
class CreationBrassin extends EcritureImport {
  const CreationBrassin({
    required this.brewId,
    required this.recipeId,
    required this.name,
    required this.plannedFor,
    required this.recette,
    required this.equipementNom,
    required this.equipementType,
  }) : super(EtapeEcriture.brassin);

  final String brewId;
  final String recipeId;
  final String name;
  final DateTime plannedFor;
  final RecipeContent recette;
  final String equipementNom;
  final TypeEquipementFiche equipementType;
}

/// Modification d'un groupe de champs de `brews/{id}` : une écriture par
/// groupe (budget des règles, `firestore.rules`). Valeurs Dart : `DateTime`,
/// nombres, textes.
class ModificationBrassin extends EcritureImport {
  const ModificationBrassin(super.etape, this.brewId, this.champs);

  final String brewId;
  final Map<String, Object> champs;
}

/// Lot de 10 événements au plus, dans un `WriteBatch`.
class LotEvenements extends EcritureImport {
  const LotEvenements(this.brewId, this.numero, this.evenements)
    : super(EtapeEcriture.evenements);

  final String brewId;

  /// Rang du lot, à partir de 1.
  final int numero;
  final List<BrewEvent> evenements;
}

/// Coût figé `users/{uid}/brew_costs/{brewId}`, `freeze_kind: initial`.
class FigeageCout extends EcritureImport {
  const FigeageCout(this.cout) : super(EtapeEcriture.cout);

  final BrewCost cout;
}

/// Événements au plus par lot (CR3).
const kEvenementsParLot = 10;

/// Plan d'écriture de [f], dans l'ordre de CR3 : recette si [recetteAbsente],
/// brassin s'il n'existe pas, modifications par groupe, événements absents
/// par lots de 10, mesures retenues, coût figé s'il manque, marque de fin. Un
/// groupe déjà écrit avec les mêmes valeurs n'est pas réécrit (ID3).
List<EcritureImport> planDeFiche(
  FicheAImporter f, {
  required BrassinExistant? existant,
  required bool recetteAbsente,
  required bool coutFige,
}) {
  final fiche = f.fiche!;
  final recette = f.recette!;
  final brewId = f.brewId;
  final plan = <EcritureImport>[
    if (recetteAbsente) CreationRecette(fiche.recipeDocId, recette),
    if (existant == null)
      CreationBrassin(
        brewId: brewId,
        recipeId: fiche.recipeDocId,
        name: fiche.brassin.name,
        plannedFor: fiche.brassin.plannedFor,
        recette: recette,
        equipementNom: fiche.brassin.equipementNom,
        equipementType: fiche.brassin.equipementType,
      ),
  ];
  void groupe(EtapeEcriture etape, Map<String, Object?> voulus) {
    final champs = <String, Object>{
      for (final MapEntry(:key, :value) in voulus.entries)
        if (value != null && !_egal(_valeurExistante(existant, key), value))
          key: value,
    };
    if (champs.isNotEmpty) plan.add(ModificationBrassin(etape, brewId, champs));
  }

  final b = fiche.brassin;
  groupe(EtapeEcriture.dateDeBrassage, {'brewed_at': f.brewedAt});
  groupe(EtapeEcriture.embouteillage, {
    'bottles_count': b.bottlesCount,
    'packaged_volume_l': b.packagedVolumeL,
    'priming_sugar_name': b.primingSugarName,
  });
  groupe(EtapeEcriture.notes, {'notes': b.notes});
  final deja = existant?.eventIds ?? const <String>{};
  final absents = [
    for (final e in f.evenements)
      if (!deja.contains(e.id)) e,
  ];
  for (var i = 0; i < absents.length; i += kEvenementsParLot) {
    final fin = i + kEvenementsParLot < absents.length
        ? i + kEvenementsParLot
        : absents.length;
    plan.add(
      LotEvenements(
        brewId,
        i ~/ kEvenementsParLot + 1,
        absents.sublist(i, fin),
      ),
    );
  }
  groupe(EtapeEcriture.mesuresRetenues, {
    'og_event_id': fiche.ogEventId,
    'fg_event_id': fiche.fgEventId,
    'fermenter_volume_event_id': fiche.fermenterVolumeEventId,
  });
  if (f.cout case CoutCalcule(:final cout) when !coutFige) {
    plan.add(FigeageCout(cout));
  }
  plan.add(
    ModificationBrassin(EtapeEcriture.marque, brewId, {
      'imported_from': f.marque!,
    }),
  );
  return plan;
}

Object? _valeurExistante(BrassinExistant? b, String champ) => switch (champ) {
  _ when b == null => null,
  'brewed_at' => b.brewedAt,
  'bottles_count' => b.bottlesCount,
  'packaged_volume_l' => b.packagedVolumeL,
  'priming_sugar_name' => b.primingSugarName,
  'notes' => b.notes,
  'og_event_id' => b.ogEventId,
  'fg_event_id' => b.fgEventId,
  'fermenter_volume_event_id' => b.fermenterVolumeEventId,
  _ => null,
};

bool _egal(Object? existant, Object voulu) => switch ((existant, voulu)) {
  (final DateTime a, final DateTime b) => a.isAtSameMomentAs(b),
  (final num a, final num b) => a == b,
  _ => existant == voulu,
};
