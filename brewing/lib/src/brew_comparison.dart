import 'alcohol.dart';
import 'errors.dart';
import 'fermentables.dart';
import 'gravity.dart';
import 'recipe_calculation.dart';

/// Mesures retenues d'un brassin. Une donnée absente reste nulle : aucune
/// valeur prévue ne la remplace.
class BrewMeasurements {
  /// Crée les mesures. [originalGravity] et [finalGravity] en SG décimal,
  /// [fermenterVolumeLitres] en litres.
  const BrewMeasurements({
    this.originalGravity,
    this.finalGravity,
    this.fermenterVolumeLitres,
    this.sugarsInWort,
  });

  /// Densité initiale retenue.
  final double? originalGravity;

  /// Densité finale retenue.
  final double? finalGravity;

  /// Volume en fermenteur retenu.
  final double? fermenterVolumeLitres;

  /// Vrai si les sucres étaient dans le moût à la mesure ; nul sans réponse.
  final bool? sugarsInWort;
}

/// Valeurs prévues d'un brassin, tirées de sa copie figée ; nulle si elle est
/// indisponible.
class PlannedBrewValues {
  /// Crée les valeurs.
  const PlannedBrewValues({
    this.originalGravity,
    this.finalGravity,
    this.alcoholByVolume,
    this.fermenterVolumeLitres,
    this.mashEfficiencyPercent,
  });

  /// Densité initiale prévue (SG).
  final double? originalGravity;

  /// Densité finale prévue (SG).
  final double? finalGravity;

  /// Degré prévu (% vol).
  final double? alcoholByVolume;

  /// Volume prévu en fermenteur (L).
  final double? fermenterVolumeLitres;

  /// Rendement d'empâtage de l'équipement figé (%).
  final double? mashEfficiencyPercent;
}

/// Donnée qui manque à une valeur mesurée. Le texte est choisi par l'écran.
enum MeasurementGapKind {
  /// Aucune densité initiale retenue.
  originalGravity,

  /// Aucune densité finale retenue.
  finalGravity,

  /// Aucun volume en fermenteur retenu.
  fermenterVolume,

  /// Rendement d'extrait non renseigné ([MeasurementGap.items] : les lignes).
  extractYield,

  /// Le brasseur n'a pas dit si les sucres étaient dans le moût.
  sugarsInWort,

  /// Aucun malt : le rendement d'empâtage ne s'applique pas.
  noMalt,
}

/// Une donnée manquante et les lignes qu'elle concerne.
class MeasurementGap {
  /// Crée la donnée manquante.
  const MeasurementGap(this.kind, [this.items = const []]);

  /// Nature de la donnée.
  final MeasurementGapKind kind;

  /// Lignes concernées, vide quand la donnée porte sur le brassin entier.
  final List<IngredientRef> items;
}

/// Raison d'un calcul impossible sur des données saisies.
enum MeasuredImpossibleKind {
  /// La densité finale dépasse la densité initiale.
  finalAboveOriginal,

  /// Les sucres expliquent à eux seuls la densité mesurée.
  sugarsExplainGravity,
}

/// Résultat d'une ligne mesurée.
sealed class MeasuredResult {
  const MeasuredResult();
}

/// Valeur obtenue.
class MeasuredComputed extends MeasuredResult {
  /// Crée le résultat.
  const MeasuredComputed(this.value);

  /// Valeur, dans l'unité de la ligne.
  final double value;
}

/// Valeur indisponible : des données manquent.
class MeasuredUnavailable extends MeasuredResult {
  /// Crée le résultat.
  const MeasuredUnavailable(this.gaps);

  /// Données manquantes, jamais vide.
  final List<MeasurementGap> gaps;
}

/// Calcul impossible sur des données saisies, sans exception ni rapport.
class MeasuredImpossible extends MeasuredResult {
  /// Crée le résultat.
  const MeasuredImpossible(this.kind);

  /// Raison.
  final MeasuredImpossibleKind kind;
}

/// Une ligne du tableau « Prévu / Mesuré / Écart ».
class ComparisonLine {
  /// Crée la ligne.
  const ComparisonLine({
    required this.planned,
    required this.measured,
    required this.difference,
  });

  /// Valeur prévue, nulle si elle est indisponible.
  final double? planned;

  /// Valeur mesurée, ou ce qui lui manque.
  final MeasuredResult measured;

  /// Mesuré moins prévu ; nul si l'un des deux manque.
  final double? difference;
}

/// Le tableau « Prévu / Mesuré / Écart » d'un brassin.
class BrewComparison {
  /// Crée le tableau.
  const BrewComparison({
    required this.originalGravity,
    required this.finalGravity,
    required this.alcoholByVolume,
    required this.fermenterVolume,
    required this.mashEfficiency,
  });

  /// Densité initiale, écart en points.
  final ComparisonLine originalGravity;

  /// Densité finale, écart en points.
  final ComparisonLine finalGravity;

  /// Degré, écart en % vol.
  final ComparisonLine alcoholByVolume;

  /// Volume en fermenteur, écart en litres.
  final ComparisonLine fermenterVolume;

  /// Rendement d'empâtage, écart en points.
  final ComparisonLine mashEfficiency;
}

/// Compare les mesures retenues d'un brassin à ses valeurs prévues.
///
/// [fermentables] : malts et sucres de la copie figée. Une donnée manquante et
/// les deux calculs impossibles sur des données saisies sont rendus sans
/// exception. Une valeur enregistrée hors limites lève
/// [BrewingInputException] : l'appelant la rapporte.
BrewComparison compareBrewWithPlan({
  required PlannedBrewValues planned,
  required BrewMeasurements measured,
  required List<FermentableInput> fermentables,
}) {
  final og = measured.originalGravity;
  final fg = measured.finalGravity;
  final volume = measured.fermenterVolumeLitres;
  if (og != null) {
    requireRange('originalGravity', og, minGravity, maxGravity);
  }
  if (fg != null) requireRange('finalGravity', fg, minGravity, maxGravity);
  if (volume != null) requirePositive('fermenterVolumeLitres', volume);

  double points(double sg) => sgToPoints(sg);
  return BrewComparison(
    originalGravity: _line(
      planned.originalGravity,
      _gravity(og, MeasurementGapKind.originalGravity),
      (m, p) => points(m) - points(p),
    ),
    finalGravity: _line(
      planned.finalGravity,
      _gravity(fg, MeasurementGapKind.finalGravity),
      (m, p) => points(m) - points(p),
    ),
    alcoholByVolume: _line(
      planned.alcoholByVolume,
      _alcohol(og, fg),
      (m, p) => m - p,
    ),
    fermenterVolume: _line(
      planned.fermenterVolumeLitres,
      _gravity(volume, MeasurementGapKind.fermenterVolume),
      (m, p) => m - p,
    ),
    mashEfficiency: _line(
      planned.mashEfficiencyPercent,
      _efficiency(measured, fermentables),
      (m, p) => m - p,
    ),
  );
}

ComparisonLine _line(
  double? planned,
  MeasuredResult measured,
  double Function(double measured, double planned) difference,
) => ComparisonLine(
  planned: planned,
  measured: measured,
  difference: planned != null && measured is MeasuredComputed
      ? difference(measured.value, planned)
      : null,
);

MeasuredResult _gravity(double? value, MeasurementGapKind missing) =>
    value == null
    ? MeasuredUnavailable(List.unmodifiable([MeasurementGap(missing)]))
    : MeasuredComputed(value);

MeasuredResult _alcohol(double? og, double? fg) {
  final gaps = [
    if (og == null) const MeasurementGap(MeasurementGapKind.originalGravity),
    if (fg == null) const MeasurementGap(MeasurementGapKind.finalGravity),
  ];
  if (gaps.isNotEmpty) return MeasuredUnavailable(List.unmodifiable(gaps));
  if (fg! > og!) {
    return const MeasuredImpossible(MeasuredImpossibleKind.finalAboveOriginal);
  }
  return MeasuredComputed(
    alcoholByVolume(originalGravity: og, finalGravity: fg),
  );
}

MeasuredResult _efficiency(
  BrewMeasurements measured,
  List<FermentableInput> fermentables,
) {
  const noMalt = MeasuredUnavailable([
    MeasurementGap(MeasurementGapKind.noMalt),
  ]);
  bool isMalt(FermentableInput f) => f.kind == FermentableKind.malt;
  if (!fermentables.any((f) => isMalt(f) && f.massGrams > 0)) return noMalt;

  final og = measured.originalGravity;
  final volume = measured.fermenterVolumeLitres;
  final inWort = measured.sugarsInWort;
  // Un sucre hors du moût n'entre pas dans le calcul : son rendement d'extrait
  // peut manquer.
  final withoutYield = [
    for (final (i, f) in fermentables.indexed)
      if (f.yieldPercent == null && (isMalt(f) || inWort != false))
        IngredientRef(i, f.name),
  ];
  final hasSugar = fermentables.any((f) => !isMalt(f));
  final gaps = [
    if (og == null) const MeasurementGap(MeasurementGapKind.originalGravity),
    if (volume == null)
      const MeasurementGap(MeasurementGapKind.fermenterVolume),
    if (withoutYield.isNotEmpty)
      MeasurementGap(
        MeasurementGapKind.extractYield,
        List.unmodifiable(withoutYield),
      ),
    if (hasSugar && inWort == null)
      const MeasurementGap(MeasurementGapKind.sugarsInWort),
  ];
  if (gaps.isNotEmpty) return MeasuredUnavailable(List.unmodifiable(gaps));

  final reading = readMashEfficiency(
    measuredGravity: og!,
    measuredVolumeLitres: volume!,
    fermentables: [
      for (final f in fermentables)
        if (isMalt(f) || inWort == true)
          Fermentable(
            name: f.name,
            kind: f.kind,
            massGrams: f.massGrams,
            // La couleur n'entre pas dans le rendement : une couleur absente ne
            // change pas le résultat.
            colorEbc: f.colorEbc ?? 0,
            potential: ExtractPotential.yieldPercent(f.yieldPercent!),
          ),
    ],
    sugarsInWort: inWort == true,
  );
  return switch (reading) {
    MashEfficiencyRead(:final percent) => MeasuredComputed(percent),
    MashEfficiencySugarsExplainGravity() => const MeasuredImpossible(
      MeasuredImpossibleKind.sugarsExplainGravity,
    ),
    MashEfficiencyWithoutMalt() => noMalt,
  };
}
