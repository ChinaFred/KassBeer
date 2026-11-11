import 'package:exchange/exchange.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../library/domain/referentiel.dart';
import 'recipe.dart';

/// Recette d'un fichier, prête pour l'aperçu de Recettes › Importer : lue par
/// `exchange/`, complétée par la Bibliothèque (`completerRecette`), puis relue
/// par `RecipeContent.fromFirestore`, la lecture stricte de l'application.
/// Aucune écriture avant « Importer ».
class RecetteAImporter {
  const RecetteAImporter({
    required this.source,
    required this.recipe,
    required this.content,
    required this.refus,
    required this.modifications,
    required this.dejaImportee,
    required this.importeeLe,
    this.reprises = const [],
    this.nonResolus = const [],
  });

  final RecetteDuFichier source;

  /// Sous-arbre `recipe` lu et complété, ou `null` si la recette est refusée
  /// par `exchange/`.
  final Map<String, Object?>? recipe;

  /// Recette lue, ou `null` si elle est refusée.
  final RecipeContent? content;

  /// Raison du refus, ou `null`.
  final Refus? refus;

  /// Changements faits à la lecture.
  final List<Modification> modifications;

  /// Valeurs absentes du fichier, reprises de la Bibliothèque.
  final List<ValeurReprise> reprises;

  /// Noms qu'aucune entrée de la Bibliothèque ne résout, signalés après
  /// l'import (`import_unresolved/`).
  final List<NomNonResolu> nonResolus;

  /// Vrai si l'importateur a déjà une recette de même empreinte.
  final bool dejaImportee;

  /// Date de création de cette recette ; `null` si elle attend le serveur.
  final DateTime? importeeLe;

  /// Nom affiché : celui du fichier, ou « Recette sans nom (n° 3) ».
  String get nom => source.nom ?? 'Recette sans nom (n° ${source.numero})';

  bool get refusee => content == null;

  /// Cochée à l'ouverture de l'aperçu : ni refusée, ni déjà importée, ni en
  /// double dans le fichier.
  bool get cocheeParDefaut => !refusee && !dejaImportee && !source.enDouble;
}

/// Index d'un import, lus dans la Bibliothèque à l'ouverture de l'écran.
/// [incomplet] : au moins un index manque ; les noms de sa liste ne sont ni
/// complétés ni signalés. [vide] : chaque index manquant est absent du serveur
/// (Bibliothèque pas encore remplie) ; faux si l'un d'eux n'a pas pu être lu
/// (hors ligne, illisible, panne).
/// [nonLues] : natures dont l'index manque, dans l'ordre malts, houblons,
/// ajouts, levures.
typedef IndexLus = ({
  IndexImport index,
  bool incomplet,
  bool vide,
  List<NatureReferentiel> nonLues,
});

/// Noms non résolus signalés au plus par import (ADR-005, E6) ; les suivants
/// sont comptés au compte rendu.
const kMaxSignalements = 200;

/// Liste de recette résolue par l'index de [nature], ou `null` pour les
/// styles.
ListeRecette? listeDe(NatureReferentiel nature) => switch (nature) {
  NatureReferentiel.fermentables => ListeRecette.malts,
  NatureReferentiel.hops => ListeRecette.houblons,
  NatureReferentiel.cultures => ListeRecette.levures,
  NatureReferentiel.miscs => ListeRecette.ajouts,
  NatureReferentiel.styles => null,
};

/// Index d'`exchange/` tiré de l'index lu [index] (malts, houblons, levures
/// ou ajouts). Lève [ArgumentError] pour l'index des styles.
IndexBibliotheque indexBibliotheque(IndexReferentiel index) {
  final liste = listeDe(index.nature);
  if (liste == null) throw ArgumentError.value(index.nature, 'index');
  return IndexBibliotheque(liste, [
    for (final e in index.entrees)
      switch (e) {
        EntreeFermentable() => EntreeBibliotheque(
          id: e.id,
          nom: e.name,
          alias: e.aliases,
          type: e.type,
          rendement: e.yieldPct,
          couleur: e.colorEbc,
        ),
        EntreeHoublon() => EntreeBibliotheque(
          id: e.id,
          nom: e.name,
          alias: e.aliases,
          alpha: e.alphaPct,
          forme: e.form,
        ),
        EntreeLevure() => EntreeBibliotheque(
          id: e.id,
          nom: e.name,
          alias: e.aliases,
          producteur: e.producer,
          reference: e.productId,
          type: e.type,
          forme: e.form,
          attenuation: e.attenuationPct,
        ),
        EntreeDivers() => EntreeBibliotheque(
          id: e.id,
          nom: e.name,
          alias: e.aliases,
          type: e.type,
        ),
        EntreeStyle() => EntreeBibliotheque(
          id: e.id,
          nom: e.name,
          alias: e.aliases,
        ),
      },
  ]);
}

/// Recettes de [lu], dans l'ordre du fichier. [miennes] : recettes de
/// l'importateur, lues dans le cache ou du serveur, qui donnent « Déjà
/// importée ». [index] : index de la Bibliothèque lus à l'ouverture. Une
/// recette lue par `exchange/` que l'application ne relit pas est une
/// anomalie : elle est rapportée sans son contenu et refusée.
List<RecetteAImporter> preparerImport(
  FichierLu lu, {
  required List<Recipe> miennes,
  required ErrorReportService errors,
  IndexImport index = const IndexImport(),
}) => [
  for (final r in lu.recettes) _preparer(lu.format, r, miennes, errors, index),
];

RecetteAImporter _preparer(
  FormatFichier format,
  RecetteDuFichier r,
  List<Recipe> miennes,
  ErrorReportService errors,
  IndexImport index,
) {
  Recipe? deja;
  for (final m in miennes) {
    if (estImporteeDe(m.content.importedFrom, r.empreinte)) {
      deja = m;
      break;
    }
  }
  final resultat = r.resultat;
  Map<String, Object?>? recipe;
  RecipeContent? content;
  Refus? refus;
  var modifications = const <Modification>[];
  var reprises = const <ValeurReprise>[];
  var nonResolus = const <NomNonResolu>[];
  switch (resultat) {
    case RecetteRefusee(refus: final raison):
      refus = raison;
    case RecetteLue(recipe: final lue, modifications: final modifs):
      modifications = modifs;
      final completee = completerRecette(lue, index);
      recipe = completee.recipe;
      reprises = completee.reprises;
      nonResolus = completee.nonResolus;
      try {
        content = RecipeContent.fromFirestore({
          'format_version': 1,
          'imported_from': importedFrom(format, r.empreinte),
          'recipe': recipe,
        });
      } on DocumentIllisible catch (error, stackTrace) {
        // Le champ fautif est un chemin (`recipe.ingredients…`), sans valeur.
        errors.reportError(
          feature: 'exchange.read',
          error: error,
          stackTrace: stackTrace,
          context:
              'format ${format.nom}, recette n° ${r.numero} relue illisible',
        );
        refus = const RecetteIllisible();
        reprises = const [];
        nonResolus = const [];
      }
  }
  return RecetteAImporter(
    source: r,
    recipe: recipe,
    content: content,
    refus: refus,
    modifications: modifications,
    reprises: reprises,
    nonResolus: nonResolus,
    dejaImportee: deja != null,
    importeeLe: deja?.createdAt,
  );
}

/// Noms non résolus des recettes [importees], une fois chacun.
List<NomNonResolu> nonResolusDe(Iterable<RecetteAImporter> importees) {
  final noms = <String, NomNonResolu>{};
  for (final r in importees) {
    for (final n in r.nonResolus) {
      noms.putIfAbsent(n.empreinte, () => n);
    }
  }
  return List.unmodifiable(noms.values);
}

/// [content] avec l'équipement choisi dans l'aperçu (`null` : aucun).
RecipeContent avecEquipement(RecipeContent content, String? equipmentId) =>
    RecipeContent(
      name: content.name,
      type: content.type,
      author: content.author,
      style: content.style,
      notes: content.notes,
      batchVolumeL: content.batchVolumeL,
      boilTimeMin: content.boilTimeMin,
      grainTempC: content.grainTempC,
      equipmentId: equipmentId,
      fermentables: content.fermentables,
      hops: content.hops,
      others: content.others,
      yeasts: content.yeasts,
      mashSteps: content.mashSteps,
      brewSteps: content.brewSteps,
      importedFrom: content.importedFrom,
    );
