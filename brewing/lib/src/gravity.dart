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

/// Lecture d'une densité saisie, sans exception ([readGravity]).
sealed class GravityReading {
  const GravityReading();
}

/// Densité lue, dans [minGravity]–[maxGravity].
class GravityRead extends GravityReading {
  /// Crée la lecture.
  const GravityRead(this.sg);

  /// Densité en SG décimal.
  final double sg;
}

/// Texte illisible : vide, signe, lettres, deux séparateurs décimaux.
class GravityUnreadable extends GravityReading {
  /// Crée la lecture.
  const GravityUnreadable();
}

/// Nombre lu, densité hors de [minGravity]–[maxGravity].
class GravityOutOfRange extends GravityReading {
  /// Crée la lecture.
  const GravityOutOfRange(this.sg);

  /// Densité lue, en SG décimal (« 1250 » → 1.25, « 65 » → 65).
  final double sg;
}

/// Lit une densité écrite comme dans les fiches, sans lever d'exception.
///
/// Formes acceptées : « 1057,9 » ou « 1090 » (densité × 1000), « 1.052 » ou
/// « 1,07 » (SG décimal). La virgule et le point sont des séparateurs décimaux ;
/// les espaces sont ignorés. Seule définition de la règle, lue par
/// [parseGravity]. Sert à la saisie : une faute de frappe
/// n'est pas une erreur à journaliser.
GravityReading readGravity(String text) {
  final cleaned = text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) {
    return const GravityUnreadable();
  }
  final value = double.parse(cleaned);
  final sg = value >= 900 ? value / 1000 : value;
  if (sg < minGravity || sg > maxGravity) return GravityOutOfRange(sg);
  return GravityRead(sg);
}

/// Lit une densité écrite comme dans les fiches (règle de [readGravity]).
///
/// Un texte vide, illisible ou hors de [minGravity]–[maxGravity] lève
/// [BrewingInputException].
double parseGravity(String text) => switch (readGravity(text)) {
  GravityRead(:final sg) => sg,
  GravityUnreadable() => throw BrewingInputException(
    'gravity',
    text,
    'densité illisible',
  ),
  GravityOutOfRange() => throw BrewingInputException(
    'gravity',
    text,
    'densité hors de l\'intervalle $minGravity – $maxGravity',
  ),
};
