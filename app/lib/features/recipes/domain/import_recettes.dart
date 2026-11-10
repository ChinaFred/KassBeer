import 'package:exchange/exchange.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import 'recipe.dart';

/// Recette d'un fichier, prête pour l'aperçu de Recettes › Importer : lue par
/// `exchange/`, puis relue par `RecipeContent.fromFirestore`, la lecture stricte
/// de l'application. Aucune écriture avant « Importer ».
class RecetteAImporter {
  const RecetteAImporter({
    required this.source,
    required this.content,
    required this.refus,
    required this.modifications,
    required this.dejaImportee,
    required this.importeeLe,
  });

  final RecetteDuFichier source;

  /// Recette lue, ou `null` si elle est refusée.
  final RecipeContent? content;

  /// Raison du refus, ou `null`.
  final Refus? refus;

  /// Changements faits à la lecture.
  final List<Modification> modifications;

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

/// Recettes de [lu], dans l'ordre du fichier. [miennes] : recettes de
/// l'importateur, lues dans le cache ou du serveur, qui donnent « Déjà
/// importée ». Une recette lue par `exchange/` que l'application ne relit pas
/// est une anomalie : elle est rapportée sans son contenu et refusée.
List<RecetteAImporter> preparerImport(
  FichierLu lu, {
  required List<Recipe> miennes,
  required ErrorReportService errors,
}) => [for (final r in lu.recettes) _preparer(lu.format, r, miennes, errors)];

RecetteAImporter _preparer(
  FormatFichier format,
  RecetteDuFichier r,
  List<Recipe> miennes,
  ErrorReportService errors,
) {
  Recipe? deja;
  for (final m in miennes) {
    if (estImporteeDe(m.content.importedFrom, r.empreinte)) {
      deja = m;
      break;
    }
  }
  final resultat = r.resultat;
  RecipeContent? content;
  Refus? refus;
  var modifications = const <Modification>[];
  switch (resultat) {
    case RecetteRefusee(refus: final raison):
      refus = raison;
    case RecetteLue(:final recipe, modifications: final modifs):
      modifications = modifs;
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
      }
  }
  return RecetteAImporter(
    source: r,
    content: content,
    refus: refus,
    modifications: modifications,
    dejaImportee: deja != null,
    importeeLe: deja?.createdAt,
  );
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
