import 'errors.dart';

/// Densité la plus basse acceptée (SG). Une bière très sèche descend vers 0,996.
const double minGravity = 0.980;

/// Densité la plus haute acceptée (SG).
const double maxGravity = 1.200;

/// Convertit une densité SG décimale en points : 1.0579 → 57.9.
double sgToPoints(double sg) {
  requireRange('sg', sg, minGravity, maxGravity);
  return (sg - 1) * 1000;
}

/// Convertit des points en densité SG décimale : 57.9 → 1.0579.
///
/// C'est aussi la lecture de la colonne « Densité (1000 +) » des fiches (65 → 1.065).
double pointsToSg(double points) {
  requireRange(
    'points',
    points,
    (minGravity - 1) * 1000,
    (maxGravity - 1) * 1000,
  );
  return 1 + points / 1000;
}

/// Lit une densité écrite comme dans les fiches.
///
/// Formes acceptées : « 1057,9 » ou « 1090 » (densité × 1000), « 1.052 » ou
/// « 1,07 » (SG décimal). La virgule et le point sont des séparateurs décimaux ;
/// les espaces sont ignorés. Un texte vide, illisible ou hors de
/// [minGravity]–[maxGravity] lève [BrewingInputException].
double parseGravity(String text) {
  final cleaned = text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) {
    throw BrewingInputException('gravity', text, 'densité illisible');
  }
  final value = double.parse(cleaned);
  final sg = value >= 900 ? value / 1000 : value;
  if (sg < minGravity || sg > maxGravity) {
    throw BrewingInputException(
      'gravity',
      text,
      'densité hors de l\'intervalle $minGravity – $maxGravity',
    );
  }
  return sg;
}
