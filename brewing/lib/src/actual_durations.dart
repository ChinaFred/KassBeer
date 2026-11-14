import 'errors.dart';
import 'schedule.dart';

/// Plus petite durée, en minutes, qu'une étape de modèle de processus reçoit
/// d'un brassin.
const minStepUpdateMinutes = 1;

/// Plus grande durée, en minutes, qu'une étape de modèle de processus reçoit
/// d'un brassin : la borne d'une étape de chronologie.
const maxStepUpdateMinutes = 600;

/// Nature de la durée réelle d'une étape.
enum ActualStepKind {
  /// Début et fin enregistrés : [ActualStepDuration.actualMinutes] est connue.
  measured,

  /// Étape prévue à 0 min (« Fait ») : ni réel ni écart.
  action,

  /// Sautée, non faite ou à venir : pas de durée réelle.
  none,

  /// En cours.
  running,

  /// Commencée sans fin retenue : faite sans heure de fin, ou restée en cours
  /// dans une journée close.
  missingEnd,
}

/// Prévu et réel d'une étape, en minutes entières.
class ActualStepDuration {
  /// Crée le résultat. [actualMinutes] n'est donné que pour
  /// [ActualStepKind.measured].
  const ActualStepDuration({
    required this.kind,
    required this.plannedMinutes,
    this.actualMinutes,
  });

  /// Nature.
  final ActualStepKind kind;

  /// Durée prévue, arrondie à la minute la plus proche.
  final int plannedMinutes;

  /// Durée réelle (fin retenue moins début retenu), arrondie à la minute la
  /// plus proche ; nulle sans début et fin.
  final int? actualMinutes;

  /// Réel moins prévu, en minutes ; nul sans réel.
  int? get deltaMinutes {
    final actual = actualMinutes;
    return actual == null ? null : actual - plannedMinutes;
  }
}

/// Nature de la durée réelle d'une journée.
enum ActualDayKind {
  /// Aucune étape n'a début et fin : la journée n'a que son prévu.
  none,

  /// Réel connu.
  measured,

  /// Une étape est en cours.
  running,

  /// Une étape a commencé sans fin retenue.
  missingEnd,
}

/// Prévu et réel d'une journée et de ses étapes, en minutes entières.
class ActualDayDuration {
  /// Crée le résultat.
  const ActualDayDuration({
    required this.kind,
    required this.plannedMinutes,
    required this.steps,
    required this.stepsWithoutEnd,
    this.actualMinutes,
    this.betweenStepsMinutes,
  });

  /// Nature.
  final ActualDayKind kind;

  /// Somme des durées prévues, étapes sautées comprises, arrondie.
  final int plannedMinutes;

  /// Temps écoulé du premier début à la dernière fin, arrondi ; nul hors de
  /// [ActualDayKind.measured].
  final int? actualMinutes;

  /// [actualMinutes] moins la somme des réels arrondis des étapes qui ont début
  /// et fin : le temps passé entre les étapes. Négatif quand des étapes se
  /// chevauchent. Nul hors de [ActualDayKind.measured].
  final int? betweenStepsMinutes;

  /// Nombre d'étapes [ActualStepKind.missingEnd].
  final int stepsWithoutEnd;

  /// Une durée par étape, dans l'ordre reçu.
  final List<ActualStepDuration> steps;

  /// Réel moins prévu ; nul sans réel.
  int? get deltaMinutes {
    final actual = actualMinutes;
    return actual == null ? null : actual - plannedMinutes;
  }
}

/// Une étape vue par [actualDurations] : sa durée prévue, son état calculé par
/// [recomputeSchedule] et son enregistrement réduit par
/// [stepRecordsFromEvents].
class StepTiming {
  /// Crée l'étape. Lève [BrewingInputException] si [planned] est négative.
  StepTiming({required this.planned, required this.status, this.record}) {
    if (planned.isNegative) {
      throw BrewingInputException('planned', planned, 'durée négative');
    }
  }

  /// Durée prévue.
  final Duration planned;

  /// État à l'instant du calcul.
  final StepStatus status;

  /// Heures retenues, ou nul.
  final StepRecord? record;
}

/// Minutes entières les plus proches de [duration] : 30 s comptent pour une
/// minute de plus.
int _minutes(Duration duration) {
  const minute = Duration.microsecondsPerMinute;
  return (duration.inMicroseconds + minute ~/ 2) ~/ minute;
}

/// Prévu et réel des étapes d'une journée, et de la journée (ADR-010).
///
/// Durée réelle d'une étape : fin retenue moins début retenu
/// ([StepRecord.endedAt], jamais la fin estimée [ScheduledStep.end]), arrondie
/// à la minute la plus proche. Une étape prévue à 0 min reste une action, sans
/// réel ni écart. Une étape commencée sans fin est en cours si [recomputeSchedule]
/// la rend en cours et que la journée n'est pas close ([dayClosed] : brassage
/// terminé, journée terminée) ; sinon elle est sans heure de fin.
///
/// Journée : réel du premier début à la dernière fin, seulement quand une étape
/// au moins a début et fin, qu'aucune n'est en cours et qu'aucune n'a commencé
/// sans fin. Les heures sont des instants : un changement d'heure ou minuit ne
/// changent pas le temps écoulé.
///
/// Lève [BrewingInputException] pour une étape faite ou en cours sans début.
ActualDayDuration actualDurations({
  required List<StepTiming> steps,
  bool dayClosed = false,
}) {
  final results = <ActualStepDuration>[];
  var planned = Duration.zero;
  var measuredSum = 0;
  var complete = false;
  var running = false;
  var withoutEnd = 0;
  DateTime? firstStart;
  DateTime? lastEnd;
  for (final (i, step) in steps.indexed) {
    planned += step.planned;
    final plannedMinutes = _minutes(step.planned);
    final record = step.record;
    final start = record?.startedAt;
    final end = record?.endedAt;
    final started =
        step.status == StepStatus.done || step.status == StepStatus.running;
    if (started && start == null) {
      throw BrewingInputException(
        'steps[$i].record',
        step.status.name,
        'étape commencée sans début enregistré',
      );
    }
    int? actual;
    if (start != null && end != null) {
      actual = _minutes(end.difference(start));
      complete = true;
      measuredSum += actual;
      if (firstStart == null || start.isBefore(firstStart)) firstStart = start;
      if (lastEnd == null || end.isAfter(lastEnd)) lastEnd = end;
    }
    // Une action s'enregistre début et fin d'un coup : sans fin, elle ne
    // retient pas la journée.
    final ActualStepKind kind;
    if (step.planned == Duration.zero) {
      kind = ActualStepKind.action;
      actual = null;
    } else if (!started) {
      kind = ActualStepKind.none;
    } else if (actual != null) {
      kind = ActualStepKind.measured;
    } else if (step.status == StepStatus.running && !dayClosed) {
      kind = ActualStepKind.running;
      running = true;
    } else {
      kind = ActualStepKind.missingEnd;
      withoutEnd++;
    }
    results.add(
      ActualStepDuration(
        kind: kind,
        plannedMinutes: plannedMinutes,
        actualMinutes: actual,
      ),
    );
  }

  final ActualDayKind dayKind;
  int? actual;
  int? between;
  if (!complete) {
    dayKind = ActualDayKind.none;
  } else if (running) {
    dayKind = ActualDayKind.running;
  } else if (withoutEnd > 0) {
    dayKind = ActualDayKind.missingEnd;
  } else {
    dayKind = ActualDayKind.measured;
    actual = _minutes(lastEnd!.difference(firstStart!));
    between = actual - measuredSum;
  }
  return ActualDayDuration(
    kind: dayKind,
    plannedMinutes: _minutes(planned),
    actualMinutes: actual,
    betweenStepsMinutes: between,
    stepsWithoutEnd: withoutEnd,
    steps: List.unmodifiable(results),
  );
}

/// Raison pour laquelle une durée réelle n'est pas proposée à une étape de
/// modèle de processus.
enum DurationUpdateIssue {
  /// Pas de durée réelle ([ActualStepKind.measured] seul en a une).
  noActual,

  /// Hors de [minStepUpdateMinutes] à [maxStepUpdateMinutes].
  outOfBounds,

  /// Égale à la durée actuelle du modèle arrondie à la minute.
  unchanged,
}

/// Durée d'une étape de modèle de processus en minutes entières, à la minute
/// la plus proche (30 s vers le haut) : la valeur que l'écran affiche et que
/// [durationUpdateIssue] compare.
///
/// Lève [BrewingInputException] si [minutes] est négative ou non finie.
int roundedStepMinutes(double minutes) {
  requireNonNegative('minutes', minutes);
  return minutes.round();
}

/// Raison de ne pas proposer [actual] à une étape de modèle de durée
/// [currentMinutes], ou `null` si elle se propose. Les raisons se vérifient
/// dans l'ordre de [DurationUpdateIssue].
///
/// Lève [BrewingInputException] si [currentMinutes] est négative ou non finie.
DurationUpdateIssue? durationUpdateIssue({
  required ActualStepDuration actual,
  required double currentMinutes,
}) {
  requireNonNegative('currentMinutes', currentMinutes);
  final minutes = actual.actualMinutes;
  if (actual.kind != ActualStepKind.measured || minutes == null) {
    return DurationUpdateIssue.noActual;
  }
  if (minutes < minStepUpdateMinutes || minutes > maxStepUpdateMinutes) {
    return DurationUpdateIssue.outOfBounds;
  }
  if (minutes == roundedStepMinutes(currentMinutes)) {
    return DurationUpdateIssue.unchanged;
  }
  return null;
}
