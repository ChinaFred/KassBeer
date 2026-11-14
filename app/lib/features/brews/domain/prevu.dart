import 'package:brewing/brewing.dart'
    show
        CalculationComputed,
        CalculationResult,
        PlannedBrewValues,
        RecipeCalculation;

import 'brew.dart';

double? _valeur(CalculationResult result) =>
    result is CalculationComputed ? result.value : null;

/// Valeurs prévues du brassin : copie figée, jamais une mesure (RR8).
/// [calcul] : calcul de la recette figée par `computeRecipe` (P3), ou nul s'il
/// a été refusé ; une valeur que le calcul ne donne pas reste nulle.
PlannedBrewValues prevuDe(Brew brew, RecipeCalculation? calcul) =>
    PlannedBrewValues(
      originalGravity: calcul == null ? null : _valeur(calcul.originalGravity),
      finalGravity: calcul == null ? null : _valeur(calcul.finalGravity),
      alcoholByVolume: calcul == null ? null : _valeur(calcul.alcoholByVolume),
      fermenterVolumeLitres: brew.recipe.batchVolumeL,
      mashEfficiencyPercent: brew.equipment.mashEfficiencyPct,
    );
