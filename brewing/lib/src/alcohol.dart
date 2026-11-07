import 'errors.dart';
import 'gravity.dart';

/// Coefficient de la formule du degré : ABV (% vol) = (OG − FG) × 131,25.
const double abvFactor = 131.25;

/// Degré d'alcool (% vol) à partir des densités initiale et finale (SG).
///
/// Lève [BrewingInputException] si [finalGravity] dépasse [originalGravity].
double alcoholByVolume({
  required double originalGravity,
  required double finalGravity,
}) {
  requireRange('originalGravity', originalGravity, minGravity, maxGravity);
  requireRange('finalGravity', finalGravity, minGravity, maxGravity);
  if (finalGravity > originalGravity) {
    throw BrewingInputException(
      'finalGravity',
      finalGravity,
      'la densité finale dépasse la densité initiale ($originalGravity)',
    );
  }
  return (originalGravity - finalGravity) * abvFactor;
}

/// Sucre de resucrage ajouté à la mise en bouteille.
class PrimingSugar {
  /// [gramsPerLitre] : dose de sucre par litre de bière embouteillée.
  /// [pointsPerKgPerLitre] : potentiel du sucre employé (saccharose : voir
  /// `sucrosePointsPerKgPerLitre`). Le paquet ne choisit pas le sucre à la place
  /// du brasseur.
  PrimingSugar({
    required this.gramsPerLitre,
    required this.pointsPerKgPerLitre,
  }) {
    requireNonNegative('gramsPerLitre', gramsPerLitre);
    requirePositive('pointsPerKgPerLitre', pointsPerKgPerLitre);
  }

  /// Grammes de sucre par litre.
  final double gramsPerLitre;

  /// Potentiel du sucre, en points par kilogramme et par litre.
  final double pointsPerKgPerLitre;

  /// Points de densité apportés, tout le sucre étant fermenté.
  double get points => gramsPerLitre / 1000 * pointsPerKgPerLitre;
}

/// Degré après refermentation en bouteille (% vol).
///
/// Le sucre de resucrage, entièrement fermenté, ajoute ses points à l'écart
/// OG − FG. Sans donnée de resucrage ([priming] nul), le résultat est nul :
/// aucune hausse forfaitaire n'est appliquée.
double? alcoholByVolumeAfterBottling({
  required double abvBeforeBottling,
  PrimingSugar? priming,
}) {
  requireRange('abvBeforeBottling', abvBeforeBottling, 0, 100);
  if (priming == null) return null;
  return abvBeforeBottling + priming.points / 1000 * abvFactor;
}
