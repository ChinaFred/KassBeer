import 'errors.dart';
import 'schedule.dart';

/// Point d'une température visée du jour de brassage.
class TargetTemperaturePoint {
  /// Crée le point.
  const TargetTemperaturePoint({
    required this.at,
    required this.celsius,
    required this.stepIndex,
  });

  /// Heure du point : début ou fin de l'étape.
  final DateTime at;

  /// Température visée de l'étape, en °C.
  final double celsius;

  /// Place de l'étape dans la chronologie de la journée.
  final int stepIndex;
}

/// Séries des températures visées d'une journée de brassage, rendues par
/// [brewDayTemperatureSeries].
class BrewDayTemperatureSeries {
  /// Crée les séries.
  const BrewDayTemperatureSeries({
    required this.origin,
    required this.planned,
    required this.recomputed,
    required this.plannedStarts,
    required this.delay,
  });

  /// Premier début d'étape enregistré, ou nul avant le brassage.
  final DateTime? origin;

  /// Visée du plan de départ : une liste de points par tracé continu. Vide
  /// sans [origin].
  final List<List<TargetTemperaturePoint>> planned;

  /// Visée recalculée : une liste de points par tracé continu.
  final List<List<TargetTemperaturePoint>> recomputed;

  /// Début de chaque étape dans le plan de départ, dans l'ordre de la
  /// chronologie ; nul sans [origin].
  final List<DateTime>? plannedStarts;

  /// Fin la plus tardive recalculée moins la fin du plan de départ, jamais
  /// négative ; nulle sans [origin].
  final Duration? delay;
}

/// Températures visées d'une journée de brassage, pour la courbe du jour.
///
/// [steps] : étapes de la journée, dans l'ordre ; [targetCelsius] : température
/// visée de chacune, ou nulle ; [schedule] : résultat de [recomputeSchedule]
/// sur ces étapes.
///
/// Origine : le plus ancien début d'une étape faite ou en cours. Plan de
/// départ : chaque étape commence à l'origine plus les durées prévues des
/// étapes précédentes, sans retard. Visée recalculée : début et fin de
/// [schedule] (réels pour une étape faite, recalculés pour une étape à venir) ;
/// une étape sautée ou non faite n'a aucun point.
///
/// Forme : une étape qui a une température donne un palier, deux points à son
/// début et à sa fin, ou un seul point pour une durée nulle. Les points de deux
/// étapes qui se suivent et ont une température forment un même tracé : la
/// rampe va de la fin de l'une au début de l'autre. Le tracé s'interrompt sur
/// une étape sans température, sautée ou non faite, et quand l'étape suivante
/// commence avant le dernier point (étape faite dans le désordre).
///
/// Lève [BrewingInputException] si les trois listes n'ont pas la même
/// longueur, si [schedule] ne suit pas l'ordre de [steps], ou si une
/// température n'est pas finie.
BrewDayTemperatureSeries brewDayTemperatureSeries({
  required List<PlannedStep> steps,
  required List<double?> targetCelsius,
  required List<ScheduledStep> schedule,
}) {
  if (targetCelsius.length != steps.length) {
    throw BrewingInputException(
      'targetCelsius',
      targetCelsius.length,
      'une température par étape attendue (${steps.length})',
    );
  }
  if (schedule.length != steps.length) {
    throw BrewingInputException(
      'schedule',
      schedule.length,
      'une heure par étape attendue (${steps.length})',
    );
  }
  for (var i = 0; i < steps.length; i++) {
    if (schedule[i].stepId != steps[i].id) {
      throw BrewingInputException(
        'schedule[$i].stepId',
        schedule[i].stepId,
        'ordre différent de la chronologie',
      );
    }
    final t = targetCelsius[i];
    if (t != null && !t.isFinite) {
      throw BrewingInputException(
        'targetCelsius[$i]',
        t,
        'température non finie',
      );
    }
  }

  DateTime? origin;
  for (final s in schedule) {
    if (s.status != StepStatus.done && s.status != StepStatus.running) {
      continue;
    }
    final o = origin;
    if (o == null || s.start.isBefore(o)) origin = s.start;
  }

  final recomputed = _polylines([
    for (var i = 0; i < steps.length; i++)
      schedule[i].status == StepStatus.skipped ||
              schedule[i].status == StepStatus.notDone
          ? null
          : (schedule[i].start, schedule[i].end),
  ], targetCelsius);

  final o = origin;
  if (o == null) {
    return BrewDayTemperatureSeries(
      origin: null,
      planned: const [],
      recomputed: recomputed,
      plannedStarts: null,
      delay: null,
    );
  }
  final starts = <DateTime>[];
  final spans = <(DateTime, DateTime)>[];
  var cursor = o;
  for (final step in steps) {
    starts.add(cursor);
    final end = cursor.add(step.duration);
    spans.add((cursor, end));
    cursor = end;
  }
  var latest = o;
  for (final s in schedule) {
    if (s.end.isAfter(latest)) latest = s.end;
  }
  final overrun = latest.difference(cursor);
  return BrewDayTemperatureSeries(
    origin: o,
    planned: _polylines(spans, targetCelsius),
    recomputed: recomputed,
    plannedStarts: List.unmodifiable(starts),
    delay: overrun.isNegative ? Duration.zero : overrun,
  );
}

/// Tracés continus des étapes de [spans] (début, fin ; nul : aucun point) qui
/// ont une température dans [targets].
List<List<TargetTemperaturePoint>> _polylines(
  List<(DateTime, DateTime)?> spans,
  List<double?> targets,
) {
  final lines = <List<TargetTemperaturePoint>>[];
  var current = <TargetTemperaturePoint>[];
  void close() {
    if (current.isNotEmpty) lines.add(List.unmodifiable(current));
    current = [];
  }

  for (var i = 0; i < spans.length; i++) {
    final span = spans[i];
    final celsius = targets[i];
    if (span == null || celsius == null) {
      close();
      continue;
    }
    final (start, end) = span;
    if (current.isNotEmpty && start.isBefore(current.last.at)) close();
    current.add(
      TargetTemperaturePoint(at: start, celsius: celsius, stepIndex: i),
    );
    if (end.isAfter(start)) {
      current.add(
        TargetTemperaturePoint(at: end, celsius: celsius, stepIndex: i),
      );
    }
  }
  close();
  return List.unmodifiable(lines);
}
