import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';

/// Chronologie du jour d'une recette (`brew_steps`) : lecture du document,
/// validation, durées dérivées par `brewing/` (P3 : aucune addition de durée ici).

/// Plafonds de `brew_steps` (`firestore.rules`, spec CH).
const kMaxBrewSteps = 60;
const kBrewStepNameMaxLength = 120;

/// Longueur de `step_key` admise par les règles : une clé plus longue ferait
/// refuser tous les événements de l'étape.
const kBrewStepKeyMaxLength = 100;
const double kBrewStepMaxMinutes = 600;
const double kBrewStepMaxTemp = 100;

/// Une étape de la chronologie. La clé est créée à l'ajout : stable au
/// renommage, au déplacement et au changement de durée (CH6).
@immutable
class BrewStepLine {
  const BrewStepLine({
    required this.key,
    required this.name,
    required this.durationMin,
    this.tempC,
  });

  final String key;
  final String name;

  /// Durée en minutes, de 0 (action sans minuteur) à 600.
  final double durationMin;

  /// Température visée en °C, ou nulle.
  final double? tempC;

  /// Liste blanche des champs écrits : aucun prix ni champ inconnu n'entre dans
  /// un élément de `brew_steps`, que les règles ne lisent pas (P5).
  Map<String, Object?> toFirestore() => {
    'key': key,
    'name': name.trim(),
    'duration_min': durationMin,
    if (tempC != null) 'temp_c': tempC,
  };

  PlannedStep toPlanned() => PlannedStep(
    id: key,
    duration: Duration(seconds: (durationMin * 60).round()),
  );
}

/// Résultat de lecture de `brew_steps` : les étapes, ou la raison de leur
/// illisibilité. Pas d'exception : une chronologie illisible laisse le reste de la
/// recette lisible (CH8), et le dépôt rapporte [problem].
typedef ChronologieLue = ({List<BrewStepLine> steps, String? problem});

ChronologieLue _illisible(String reason) =>
    (steps: const <BrewStepLine>[], problem: reason);

/// Lit la valeur de `brew_steps` : liste de maps, clés présentes et uniques,
/// durées et températures dans leurs bornes.
ChronologieLue readBrewSteps(Object? raw) {
  if (raw == null) return (steps: const <BrewStepLine>[], problem: null);
  if (raw is! List) return _illisible('liste attendue');
  if (raw.length > kMaxBrewSteps) return _illisible('plus de $kMaxBrewSteps');
  final seen = <String>{};
  final steps = <BrewStepLine>[];
  for (final (i, element) in raw.indexed) {
    if (element is! Map) return _illisible('élément $i illisible');
    final key = element['key'];
    if (key is! String || key.isEmpty) return _illisible('clé absente ($i)');
    if (key.length > kBrewStepKeyMaxLength) {
      return _illisible('clé trop longue ($i)');
    }
    if (!seen.add(key)) return _illisible('clé en double ($i)');
    final name = element['name'];
    if (name is! String || name.trim().isEmpty) {
      return _illisible('nom absent ($i)');
    }
    if (name.length > kBrewStepNameMaxLength) {
      return _illisible('nom trop long ($i)');
    }
    final duration = element['duration_min'];
    if (duration is! num ||
        !duration.isFinite ||
        duration < 0 ||
        duration > kBrewStepMaxMinutes) {
      return _illisible('durée hors limites ($i)');
    }
    final temp = element['temp_c'];
    if (temp != null &&
        (temp is! num ||
            !temp.isFinite ||
            temp < 0 ||
            temp > kBrewStepMaxTemp)) {
      return _illisible('température hors limites ($i)');
    }
    steps.add(
      BrewStepLine(
        key: key,
        name: name,
        durationMin: duration.toDouble(),
        tempC: (temp as num?)?.toDouble(),
      ),
    );
  }
  return (steps: List.unmodifiable(steps), problem: null);
}

/// Première erreur d'une chronologie à enregistrer, ou `null` : le dépôt ne
/// l'écrit qu'à cette condition (les règles ne lisent pas les éléments).
String? erreurChronologie(List<BrewStepLine> steps) {
  if (steps.length > kMaxBrewSteps) return '$kMaxBrewSteps étapes au plus.';
  final seen = <String>{};
  for (final (i, s) in steps.indexed) {
    final rank = i + 1;
    if (s.key.isEmpty ||
        s.key.length > kBrewStepKeyMaxLength ||
        !seen.add(s.key)) {
      return 'Étape $rank : clé invalide.';
    }
    if (s.name.trim().isEmpty ||
        s.name.trim().length > kBrewStepNameMaxLength) {
      return 'Étape $rank : nom invalide.';
    }
    if (s.durationMin.isNaN ||
        s.durationMin < 0 ||
        s.durationMin > kBrewStepMaxMinutes) {
      return 'Étape $rank : durée hors de 0 à 600 minutes.';
    }
    final temp = s.tempC;
    if (temp != null && (temp.isNaN || temp < 0 || temp > kBrewStepMaxTemp)) {
      return 'Étape $rank : température hors de 0 à 100 °C.';
    }
  }
  return null;
}

/// Départ fictif des décalages : seuls les écarts servent.
final _depart = DateTime.utc(2000);

/// Horaire de [steps] depuis un départ fictif, calculé par `brewing/`.
List<ScheduledStep> _horaire(List<BrewStepLine> steps) => recomputeSchedule(
  steps: [for (final s in steps) s.toPlanned()],
  plannedStart: _depart,
  records: const [],
  now: _depart,
);

/// Décalage du début de chaque étape depuis le début de la chronologie.
List<Duration> decalagesChronologie(List<BrewStepLine> steps) => [
  for (final s in _horaire(steps)) s.start.difference(_depart),
];

/// Durée totale de la chronologie.
Duration dureeChronologie(List<BrewStepLine> steps) {
  if (steps.isEmpty) return Duration.zero;
  return _horaire(steps).last.end.difference(_depart);
}
