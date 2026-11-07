import 'errors.dart';

/// Une étape prévue du jour de brassage.
class PlannedStep {
  /// Crée une étape de durée [duration].
  PlannedStep({required this.id, required this.duration}) {
    if (duration.isNegative) {
      throw BrewingInputException('duration', duration, 'durée négative');
    }
  }

  /// Identifiant de l'étape.
  final String id;

  /// Durée prévue.
  final Duration duration;
}

/// Heures réellement enregistrées pour une étape (heure de l'appareil).
class StepRecord {
  /// Crée l'enregistrement. Une fin sans début, ou avant le début, est refusée.
  StepRecord({required this.stepId, this.startedAt, this.endedAt}) {
    final start = startedAt;
    final end = endedAt;
    if (end != null && start == null) {
      throw BrewingInputException('endedAt', end, 'fin enregistrée sans début');
    }
    if (start != null && end != null && end.isBefore(start)) {
      throw BrewingInputException(
        'endedAt',
        end,
        'fin antérieure au début ($start)',
      );
    }
  }

  /// Étape concernée.
  final String stepId;

  /// Début réel.
  final DateTime? startedAt;

  /// Fin réelle.
  final DateTime? endedAt;
}

/// État d'une étape à l'instant du calcul.
enum StepStatus {
  /// Terminée : fin enregistrée, ou une étape suivante a commencé.
  done,

  /// En cours : commencée, sans fin, et dernière étape commencée.
  running,

  /// À venir.
  pending,
}

/// Une étape replacée dans le planning recalculé.
class ScheduledStep {
  /// Crée l'étape replacée.
  const ScheduledStep({
    required this.stepId,
    required this.expectedStart,
    required this.start,
    required this.end,
    required this.status,
  });

  /// Étape concernée.
  final String stepId;

  /// Heure de début attendue, d'après l'étape précédente : c'est la colonne
  /// « Heure exécution prévue » des fiches.
  final DateTime expectedStart;

  /// Début réel s'il est enregistré, sinon début recalculé.
  final DateTime start;

  /// Fin réelle si elle est enregistrée, sinon fin recalculée.
  final DateTime end;

  /// État à l'instant du calcul.
  final StepStatus status;
}

/// Recalcule les heures du jour de brassage à l'instant [now].
///
/// Chaque étape commence à la fin de la précédente : sa fin enregistrée, ou
/// son début (réel ou recalculé) plus sa durée prévue. Une étape en cours qui
/// dépasse sa durée finit au plus tôt à [now], et une étape à venir ne commence
/// pas avant [now] : un retard décale les étapes restantes. Fonction pure : les
/// heures se dérivent à l'affichage et ne s'écrivent pas (CLAUDE.md, « Le jour
/// de brassage marche sans réseau »).
List<ScheduledStep> recomputeSchedule({
  required List<PlannedStep> steps,
  required DateTime plannedStart,
  required List<StepRecord> records,
  required DateTime now,
}) {
  final byId = <String, StepRecord>{};
  final ids = {for (final s in steps) s.id};
  if (ids.length != steps.length) {
    throw BrewingInputException(
      'steps',
      steps.map((s) => s.id).toList(),
      'identifiants en double',
    );
  }
  for (final r in records) {
    if (!ids.contains(r.stepId)) {
      throw BrewingInputException('records', r.stepId, 'étape inconnue');
    }
    if (byId.containsKey(r.stepId)) {
      throw BrewingInputException(
        'records',
        r.stepId,
        'étape enregistrée deux fois',
      );
    }
    byId[r.stepId] = r;
  }
  var lastStarted = -1;
  for (var i = 0; i < steps.length; i++) {
    if (byId[steps[i].id]?.startedAt != null) lastStarted = i;
  }

  final result = <ScheduledStep>[];
  var cursor = plannedStart;
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final record = byId[step.id];
    final startedAt = record?.startedAt;
    final endedAt = record?.endedAt;
    final expectedStart = startedAt == null && cursor.isBefore(now)
        ? now
        : cursor;

    final DateTime start;
    final DateTime end;
    final StepStatus status;
    if (startedAt == null) {
      start = expectedStart;
      end = start.add(step.duration);
      status = StepStatus.pending;
    } else if (endedAt != null) {
      start = startedAt;
      end = endedAt;
      status = StepStatus.done;
    } else if (i < lastStarted) {
      start = startedAt;
      end = startedAt.add(step.duration);
      status = StepStatus.done;
    } else {
      start = startedAt;
      final plannedEnd = startedAt.add(step.duration);
      end = plannedEnd.isBefore(now) ? now : plannedEnd;
      status = StepStatus.running;
    }
    result.add(
      ScheduledStep(
        stepId: step.id,
        expectedStart: expectedStart,
        start: start,
        end: end,
        status: status,
      ),
    );
    cursor = end;
  }
  return result;
}

/// État d'un minuteur à un instant donné.
class TimerReading {
  /// Crée la lecture.
  const TimerReading({
    required this.elapsed,
    required this.remaining,
    required this.overrun,
  });

  /// Temps écoulé depuis le début (zéro si [now] précède le début).
  final Duration elapsed;

  /// Temps restant, jamais négatif.
  final Duration remaining;

  /// Dépassement au-delà de la durée, jamais négatif.
  final Duration overrun;

  /// Vrai quand la durée est atteinte.
  bool get isFinished => remaining == Duration.zero;
}

/// Lit un minuteur à partir de son heure de début enregistrée.
///
/// Le minuteur se recalcule à chaque lecture : aucun `Timer` n'en est la source.
TimerReading readTimer({
  required DateTime startedAt,
  required Duration duration,
  required DateTime now,
}) {
  if (duration.isNegative) {
    throw BrewingInputException('duration', duration, 'durée négative');
  }
  final rawElapsed = now.difference(startedAt);
  final elapsed = rawElapsed.isNegative ? Duration.zero : rawElapsed;
  final left = duration - elapsed;
  return TimerReading(
    elapsed: elapsed,
    remaining: left.isNegative ? Duration.zero : left,
    overrun: left.isNegative ? -left : Duration.zero,
  );
}
