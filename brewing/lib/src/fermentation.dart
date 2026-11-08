import 'errors.dart';
import 'gravity.dart';

/// Un relevé de fermentation : une densité, une température, ou les deux.
class FermentationReading {
  /// Crée le relevé. [gravity] en SG décimal, [temperature] en °C.
  ///
  /// Lève [BrewingInputException] si les deux valeurs manquent.
  FermentationReading({
    required this.measuredAt,
    this.gravity,
    this.temperature,
  }) {
    if (gravity == null && temperature == null) {
      throw BrewingInputException(
        'fermentationReading',
        null,
        'ni densité ni température',
      );
    }
  }

  /// Heure de la mesure, sur l'appareil.
  final DateTime measuredAt;

  /// Densité en SG décimal, ou nulle si elle n'a pas été relevée.
  final double? gravity;

  /// Température en °C, ou nulle si elle n'a pas été relevée.
  final double? temperature;
}

/// Un point de la série : la liste et la courbe lisent les mêmes nombres.
class FermentationPoint {
  /// Crée le point.
  const FermentationPoint({
    required this.measuredAt,
    required this.dayOffset,
    required this.dayNumber,
    required this.gravity,
    required this.temperature,
    required this.gravityChangePoints,
  });

  /// Heure de la mesure, sur l'appareil.
  final DateTime measuredAt;

  /// Jours calendaires depuis le brassage, plus la fraction de la journée
  /// locale. Sa partie entière vaut [dayNumber].
  final double dayOffset;

  /// Numéro de jour affiché (J+N) : écart en jours calendaires.
  final int dayNumber;

  /// Densité en SG décimal, ou nulle si elle n'a pas été relevée.
  final double? gravity;

  /// Température en °C, ou nulle si elle n'a pas été relevée.
  final double? temperature;

  /// Écart en points avec la densité relevée précédente ; nul pour la première
  /// densité et pour un point sans densité.
  final double? gravityChangePoints;
}

/// Numéro de jour (J+N) de [at] : écart en jours calendaires depuis [brewedAt].
///
/// Compté sur les dates locales : une journée de changement d'heure compte
/// pour un jour.
int fermentationDayNumber({required DateTime brewedAt, required DateTime at}) {
  final start = DateTime.utc(brewedAt.year, brewedAt.month, brewedAt.day);
  final end = DateTime.utc(at.year, at.month, at.day);
  return end.difference(start).inDays;
}

double _fractionOfDay(DateTime at) {
  const secondsPerDay = 86400.0;
  return (at.hour * 3600 + at.minute * 60 + at.second) / secondsPerDay;
}

/// Série d'un relevé, triée par heure de mesure ; à heure égale, l'ordre de
/// [readings] est gardé.
List<FermentationPoint> fermentationSeries({
  required DateTime brewedAt,
  required List<FermentationReading> readings,
}) {
  final ordered = [...readings.indexed]
    ..sort((a, b) {
      final byTime = a.$2.measuredAt.compareTo(b.$2.measuredAt);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  double? previousGravity;
  final points = <FermentationPoint>[];
  for (final (_, reading) in ordered) {
    final gravity = reading.gravity;
    final previous = previousGravity;
    final dayNumber = fermentationDayNumber(
      brewedAt: brewedAt,
      at: reading.measuredAt,
    );
    points.add(
      FermentationPoint(
        measuredAt: reading.measuredAt,
        dayOffset: dayNumber + _fractionOfDay(reading.measuredAt),
        dayNumber: dayNumber,
        gravity: gravity,
        temperature: reading.temperature,
        gravityChangePoints: gravity == null || previous == null
            ? null
            : sgToPoints(gravity) - sgToPoints(previous),
      ),
    );
    if (gravity != null) previousGravity = gravity;
  }
  return List.unmodifiable(points);
}
