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
  /// Début noté et fin retenue : [ActualStepDuration.actualMinutes] est connue.
  measured,

  /// Étape prévue à 0 min (« Fait ») : ni réel ni écart.
  action,

  /// Sautée, non faite ou à venir : pas de durée réelle.
  none,

  /// En cours.
  running,

  /// Commencée à une heure notée, sans fin retenue : ni fin enregistrée, ni
  /// début noté de l'étape suivante. Réel inconnu.
  missingEnd,

  /// Commencée à une heure estimée (`time_estimated`) : réel inconnu.
  estimated,
}

/// Prévu et réel d'une étape, en minutes entières, et ses heures.
class ActualStepDuration {
  /// Crée le résultat. [actualMinutes] n'est donné que pour
  /// [ActualStepKind.measured].
  const ActualStepDuration({
    required this.kind,
    required this.plannedMinutes,
    this.actualMinutes,
    this.startDeltaMinutes,
    this.theoreticalStart,
    this.end,
  });

  /// Nature.
  final ActualStepKind kind;

  /// Durée prévue, arrondie à la minute la plus proche.
  final int plannedMinutes;

  /// Durée réelle (fin retenue moins début noté), arrondie à la minute la
  /// plus proche ; nulle sans début noté et fin.
  final int? actualMinutes;

  /// Début noté moins début du plan d'origine, arrondi : positif en retard,
  /// négatif en avance. Nul sans début noté.
  final int? startDeltaMinutes;

  /// Heure théorique de début ([theoreticalStarts]) ; nulle sans ancre.
  final DateTime? theoreticalStart;

  /// Fin retenue d'une étape [ActualStepKind.measured] : fin enregistrée, ou
  /// début noté de l'étape suivante. Nulle pour les autres natures.
  final DateTime? end;

  /// Réel moins prévu, en minutes ; nul sans réel.
  int? get deltaMinutes {
    final actual = actualMinutes;
    return actual == null ? null : actual - plannedMinutes;
  }
}

/// Nature de la durée réelle d'une journée.
enum ActualDayKind {
  /// Aucune étape n'a début noté et fin : la journée n'a que son prévu.
  none,

  /// Réel connu, toutes les étapes commencées ont leur réel.
  measured,

  /// Réel connu du premier début à la dernière fin, mais des étapes
  /// intermédiaires sont sans réel ([ActualDayDuration.stepsWithoutTime]).
  partial,

  /// Une étape est en cours.
  running,

  /// Première étape commencée à une heure estimée : réel inconnu.
  startNotNoted,

  /// Dernière étape commencée sans fin retenue : réel inconnu.
  endNotNoted,
}

/// Prévu et réel d'une journée et de ses étapes, en minutes entières.
class ActualDayDuration {
  /// Crée le résultat.
  const ActualDayDuration({
    required this.kind,
    required this.plannedMinutes,
    required this.steps,
    this.stepsWithoutTime = 0,
    this.actualMinutes,
    this.betweenStepsMinutes,
  });

  /// Nature.
  final ActualDayKind kind;

  /// Somme des durées prévues, étapes sautées comprises, arrondie.
  final int plannedMinutes;

  /// Temps écoulé du premier début à la dernière fin, arrondi ; nul hors de
  /// [ActualDayKind.measured] et [ActualDayKind.partial].
  final int? actualMinutes;

  /// [actualMinutes] moins la somme des réels arrondis des étapes : le temps
  /// passé entre les étapes. Négatif quand des étapes se chevauchent. Nul hors
  /// de [ActualDayKind.measured].
  final int? betweenStepsMinutes;

  /// Étapes commencées sans réel ([ActualStepKind.estimated],
  /// [ActualStepKind.missingEnd]) entre la première et la dernière, pour
  /// [ActualDayKind.partial].
  final int stepsWithoutTime;

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

  /// Début noté : début retenu qui n'est pas une heure estimée.
  DateTime? get _notedStart {
    final r = record;
    return r == null || r.startEstimated ? null : r.startedAt;
  }
}

/// Minutes entières les plus proches de [duration] : 30 s comptent pour une
/// minute de plus.
int _minutes(Duration duration) {
  const minute = Duration.microsecondsPerMinute;
  return (duration.inMicroseconds + minute ~/ 2) ~/ minute;
}

/// Heure théorique de début de chaque étape d'une journée.
///
/// Une étape commence au dernier début noté qui la précède ([notedStarts],
/// une étape avec un début noté compte pour elle-même), plus la durée prévue
/// de chaque étape entre les deux, celle de l'étape notée comprise. Une étape
/// sans heure notée compte sa durée prévue ; une étape sautée ([skipped])
/// compte zéro. Sans début noté avant elle, l'ancre est [anchor] (heure de
/// début prévue) ; sans ancre, l'heure est nulle. Les heures sont des
/// instants : un changement d'heure ne décale rien.
///
/// Sert à dater une étape citée sans heure (import des fiches) et à afficher
/// l'heure d'une étape non notée. Fonction pure : rien ne s'écrit à
/// l'affichage (P2).
///
/// Lève [BrewingInputException] si les listes n'ont pas la même longueur ou si
/// une durée est négative.
List<DateTime?> theoreticalStarts({
  required List<Duration> planned,
  required List<DateTime?> notedStarts,
  List<bool>? skipped,
  DateTime? anchor,
}) {
  if (notedStarts.length != planned.length ||
      (skipped != null && skipped.length != planned.length)) {
    throw BrewingInputException(
      'notedStarts',
      notedStarts.length,
      'une heure par étape attendue (${planned.length})',
    );
  }
  final result = <DateTime?>[];
  var cursor = anchor;
  for (final (i, duration) in planned.indexed) {
    if (duration.isNegative) {
      throw BrewingInputException('planned[$i]', duration, 'durée négative');
    }
    final noted = notedStarts[i];
    if (noted != null) cursor = noted;
    result.add(cursor);
    final skip = skipped?[i] ?? false;
    final at = cursor;
    if (at != null && !skip) cursor = at.add(duration);
  }
  return List.unmodifiable(result);
}

/// Prévu et réel des étapes d'une journée, et de la journée (ADR-010).
///
/// Seule une heure notée compte : un début estimé (`time_estimated`, import
/// d'une fiche) date l'étape sans donner de réel ni d'écart. Fin d'une étape :
/// sa fin enregistrée ([StepRecord.endedAt], « Terminer »), sinon le début noté
/// de l'étape suivante (les étapes sautées passées), jamais la fin estimée
/// [ScheduledStep.end]. Durée réelle : fin moins début noté, arrondie à la
/// minute la plus proche. Une étape prévue à 0 min reste une action, sans réel
/// ni écart. Une étape commencée sans fin est en cours si [recomputeSchedule]
/// la rend en cours et que la journée n'est pas close ([dayClosed] : brassage
/// terminé, journée terminée).
///
/// Écart de début : début noté moins début du plan d'origine (premier début
/// noté de la journée, plus la durée prévue de chaque étape entre les deux) :
/// le retard s'accumule. Heure théorique : [theoreticalStarts], ancrée sur
/// [plannedStart].
///
/// Journée : réel du premier début à la dernière fin, seulement quand une étape
/// au moins a un réel et qu'aucune n'est en cours ; première étape commencée à
/// une heure estimée : début non noté ; dernière sans fin : fin non notée ;
/// étapes intermédiaires sans réel : réel connu, compté à part
/// ([ActualDayKind.partial]). Les heures sont des instants : un changement
/// d'heure ou minuit ne changent pas le temps écoulé.
///
/// Lève [BrewingInputException] pour une étape faite ou en cours sans début.
ActualDayDuration actualDurations({
  required List<StepTiming> steps,
  bool dayClosed = false,
  DateTime? plannedStart,
}) {
  for (final (i, step) in steps.indexed) {
    final started =
        step.status == StepStatus.done || step.status == StepStatus.running;
    if (started && step.record?.startedAt == null) {
      throw BrewingInputException(
        'steps[$i].record',
        step.status.name,
        'étape commencée sans début enregistré',
      );
    }
  }
  final theoretical = theoreticalStarts(
    planned: [for (final s in steps) s.planned],
    notedStarts: [for (final s in steps) s._notedStart],
    skipped: [for (final s in steps) s.status == StepStatus.skipped],
    anchor: plannedStart,
  );
  // Plan d'origine : depuis le premier début noté, durées prévues cumulées.
  final origin = <DateTime?>[];
  DateTime? originCursor;
  for (final step in steps) {
    originCursor ??= step._notedStart;
    origin.add(originCursor);
    final at = originCursor;
    if (at != null) originCursor = at.add(step.planned);
  }

  final results = <ActualStepDuration>[];
  var planned = Duration.zero;
  var measuredSum = 0;
  var complete = false;
  var running = false;
  for (final (i, step) in steps.indexed) {
    planned += step.planned;
    final plannedMinutes = _minutes(step.planned);
    final record = step.record;
    final start = step._notedStart;
    final open =
        step.status == StepStatus.running &&
        !dayClosed &&
        record?.endedAt == null;
    final end = open ? null : record?.endedAt ?? _nextNotedStart(steps, i);
    final started =
        step.status == StepStatus.done || step.status == StepStatus.running;
    int? actual;
    if (start != null && end != null && !end.isBefore(start)) {
      actual = _minutes(end.difference(start));
    }
    final ActualStepKind kind;
    if (step.planned == Duration.zero) {
      kind = ActualStepKind.action;
      actual = null;
    } else if (!started) {
      kind = ActualStepKind.none;
    } else if (record?.startEstimated ?? false) {
      kind = ActualStepKind.estimated;
      actual = null;
    } else if (open) {
      kind = ActualStepKind.running;
      running = true;
      actual = null;
    } else if (actual != null) {
      kind = ActualStepKind.measured;
      complete = true;
      measuredSum += actual;
    } else {
      kind = ActualStepKind.missingEnd;
    }
    final originStart = origin[i];
    results.add(
      ActualStepDuration(
        kind: kind,
        plannedMinutes: plannedMinutes,
        actualMinutes: actual,
        startDeltaMinutes: start == null || originStart == null
            ? null
            : _signedMinutes(start.difference(originStart)),
        theoreticalStart: theoretical[i],
        end: kind == ActualStepKind.measured ? end : null,
      ),
    );
  }

  final startedIndexes = [
    for (final (i, s) in steps.indexed)
      if (s.status == StepStatus.done || s.status == StepStatus.running) i,
  ];
  ActualDayKind dayKind;
  int? actual;
  int? between;
  var withoutTime = 0;
  if (!complete) {
    dayKind = ActualDayKind.none;
  } else if (running) {
    dayKind = ActualDayKind.running;
  } else {
    final first = startedIndexes.first;
    final last = startedIndexes.last;
    final firstStart = steps[first]._notedStart;
    final lastStep = steps[last];
    final lastEnd =
        lastStep.record?.endedAt ??
        (lastStep.planned == Duration.zero ? lastStep._notedStart : null);
    if (firstStart == null) {
      dayKind = ActualDayKind.startNotNoted;
    } else if (lastEnd == null || lastEnd.isBefore(firstStart)) {
      dayKind = ActualDayKind.endNotNoted;
    } else {
      for (final i in startedIndexes) {
        final k = results[i].kind;
        if (k == ActualStepKind.estimated || k == ActualStepKind.missingEnd) {
          withoutTime++;
        }
      }
      actual = _minutes(lastEnd.difference(firstStart));
      if (withoutTime == 0) {
        dayKind = ActualDayKind.measured;
        between = actual - measuredSum;
      } else {
        dayKind = ActualDayKind.partial;
      }
    }
  }
  return ActualDayDuration(
    kind: dayKind,
    plannedMinutes: _minutes(planned),
    actualMinutes: actual,
    betweenStepsMinutes: between,
    stepsWithoutTime: withoutTime,
    steps: List.unmodifiable(results),
  );
}

/// Début noté de l'étape qui suit [index], étapes sautées passées ; nul si
/// cette étape n'a pas de début noté.
DateTime? _nextNotedStart(List<StepTiming> steps, int index) {
  for (var i = index + 1; i < steps.length; i++) {
    if (steps[i].status == StepStatus.skipped) continue;
    return steps[i]._notedStart;
  }
  return null;
}

/// Minutes entières les plus proches de [duration], signe gardé.
int _signedMinutes(Duration duration) =>
    duration.isNegative ? -_minutes(-duration) : _minutes(duration);

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
