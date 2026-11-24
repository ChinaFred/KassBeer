import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/error_report_service.dart';
import '../domain/recipe.dart';
import 'recipe_calculations_view.dart';

/// Valeurs calculées d'une recette pour sa ligne de la liste : degré, couleur
/// et teinte, tirés de `computeRecipe` par [evaluerRecette], comme la fiche.
@immutable
class ApercuRecette {
  const ApercuRecette({
    this.degre,
    this.ebc,
    this.teinte,
    this.calculImpossible = false,
  });

  /// Degré prévu (% vol) ; `null` s'il ne se calcule pas (équipement absent,
  /// sans rendement, hors cache, donnée manquante).
  final double? degre;

  /// Couleur prévue (EBC) ; `null` si elle ne se calcule pas.
  final double? ebc;

  /// Teinte `0xRRGGBB` de [ebc] ; `null` sans couleur.
  final int? teinte;

  /// `brewing/` a refusé une valeur de la recette (« Calcul impossible »).
  final bool calculImpossible;
}

/// Aperçu de [recipe] avec l'équipement [equipement]. Une valeur refusée par
/// `brewing/` passe par `reportError` une fois par recette et par champ
/// ([reported], partagé avec la fiche et l'éditeur).
ApercuRecette apercuDe(
  Recipe recipe,
  EquipementRecette equipement, {
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  final calculs = evaluerRecette(
    recipe.content,
    equipement,
    errors: errors,
    reported: reported,
    recipeKey: recipe.id,
  );
  final calcul = calculs.calculOuNul;
  if (calcul == null) return const ApercuRecette(calculImpossible: true);
  double? valeur(CalculationResult r) => switch (r) {
    CalculationComputed(:final value) => value,
    CalculationUnavailable() => null,
  };
  final ebc = valeur(calcul.colorEbc);
  int? teinte;
  if (ebc != null) {
    try {
      teinte = teinteEbc(ebc);
    } on BrewingInputException catch (error, stackTrace) {
      // Sans teinte, la ligne garde le repère du livre.
      if (reported.add('${recipe.id}|teinte')) {
        errors.reportError(
          feature: 'recipes.list_color',
          error: error,
          stackTrace: stackTrace,
          context: 'couleur refusée par brewing : ${error.field}',
        );
      }
    }
  }
  return ApercuRecette(
    degre: valeur(calcul.alcoholByVolume),
    ebc: ebc,
    teinte: teinte,
  );
}
