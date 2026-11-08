import 'errors.dart';

/// Une étape prévue du jour de brassage.
class PlannedStep {
  /// Crée une étape de durée [duration].
  PlannedStep({required this.id, required this.duration}) {
    if (duration.isNegative) {
      throw BrewingInputException('duration', duration, 'durée négative');
    }
  }

  /// Identifiant de l'étape (clé `brew_steps[].key` de la recette).
  final String id;

  /// Durée prévue.
  final Duration duration;
}

/// Heures réellement enregistrées pour une étape (heure de l'appareil).
class StepRecord {
  /// Crée l'enregistrement. Une fin sans début, ou avant le début, est refusée.
  ///
  /// [skipped] : l'étape est marquée sautée (événement `step_skipped`). Les
  /// identifiants d'événement sont facultatifs ; [stepRecordsFromEvents] les
  /// renseigne pour que l'écran corrige ou supprime le bon document.
  StepRecord({
    required this.stepId,
    this.startedAt,
    this.endedAt,
    this.skipped = false,
    this.startEventId,
    this.endEventId,
    this.skipEventIds = const [],
  }) {
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

  /// Vrai si l'étape est marquée sautée. Un début enregistré l'emporte.
  final bool skipped;

  /// Événement `step_started` retenu pour [startedAt].
  final String? startEventId;

  /// Événement `step_ended` retenu pour [endedAt].
  final String? endEventId;

  /// Événements `step_skipped` de l'étape, par heure croissante.
  final List<String> skipEventIds;
}

/// État d'une étape à l'instant du calcul.
enum StepStatus {
  /// Faite : fin enregistrée, ou commencée sans fin alors qu'une autre étape a
  /// commencé plus tard.
  done,

  /// En cours : commencée, sans fin, et début sans fin le plus récent.
  running,

  /// À venir : jamais commencée, et aucune étape plus loin n'a commencé.
  pending,

  /// Sautée : marquée sautée (`step_skipped`) et jamais commencée. Durée nulle.
  skipped,

  /// Non faite : jamais commencée, sans saut, alors qu'une étape plus loin a
  /// commencé. Durée nulle ; elle reste démarrable.
  notDone,
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

  /// Heure de début attendue, d'après l'étape précédente dans l'ordre de la
  /// chronologie : c'est la colonne « Heure exécution prévue » des fiches.
  final DateTime expectedStart;

  /// Début réel s'il est enregistré, sinon début recalculé.
  final DateTime start;

  /// Fin réelle si elle est enregistrée, sinon fin recalculée. Égale à [start]
  /// pour une étape sautée ou non faite.
  final DateTime end;

  /// État à l'instant du calcul.
  final StepStatus status;
}

/// Recalcule les heures du jour de brassage à l'instant [now].
///
/// Chaque étape commence à la fin de l'étape précédente dans l'ordre de la
/// chronologie : sa fin enregistrée, ou son début réel plus sa durée prévue.
/// L'étape en cours est l'étape commencée sans fin dont le début est le plus
/// récent (à égalité, la plus loin) : elle finit au plus tôt à [now]. Une autre
/// étape commencée sans fin est faite, à son début plus sa durée. Une étape
/// sautée, ou non faite (jamais commencée alors qu'une étape plus loin a
/// commencé), dure zéro. Une étape à venir ne commence ni avant [now], ni avant
/// la fin de l'étape en cours : un retard, ou un retour en arrière, décale les
/// étapes restantes.
///
/// Fonction pure : les heures se dérivent à l'affichage et ne s'écrivent pas
/// (CLAUDE.md, « Le jour de brassage marche sans réseau »). Lève
/// [BrewingInputException] si deux étapes ont le même identifiant, ou si
/// [records] nomme une étape inconnue ou deux fois la même : réduire d'abord
/// les événements par [stepRecordsFromEvents].
List<ScheduledStep> recomputeSchedule({
  required List<PlannedStep> steps,
  required DateTime plannedStart,
  required List<StepRecord> records,
  required DateTime now,
}) {
  final ids = _requireUniqueIds(steps);
  final byId = <String, StepRecord>{};
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
  var running = -1;
  DateTime? runningStart;
  for (var i = 0; i < steps.length; i++) {
    final record = byId[steps[i].id];
    final startedAt = record?.startedAt;
    if (startedAt == null) continue;
    lastStarted = i;
    if (record?.endedAt != null) continue;
    final latest = runningStart;
    if (latest == null || !startedAt.isBefore(latest)) {
      running = i;
      runningStart = startedAt;
    }
  }
  // Fin de l'étape en cours, et plus tôt début d'une étape à venir.
  var earliestPending = now;
  final currentStart = runningStart;
  if (currentStart != null) {
    final plannedEnd = currentStart.add(steps[running].duration);
    if (plannedEnd.isAfter(now)) earliestPending = plannedEnd;
  }

  final result = <ScheduledStep>[];
  var cursor = plannedStart;
  for (var i = 0; i < steps.length; i++) {
    final step = steps[i];
    final record = byId[step.id];
    final startedAt = record?.startedAt;
    final endedAt = record?.endedAt;

    var expectedStart = cursor;
    final DateTime start;
    final DateTime end;
    final StepStatus status;
    if (startedAt != null) {
      start = startedAt;
      if (endedAt != null) {
        end = endedAt;
        status = StepStatus.done;
      } else if (i == running) {
        end = earliestPending;
        status = StepStatus.running;
      } else {
        end = startedAt.add(step.duration);
        status = StepStatus.done;
      }
    } else if (record?.skipped ?? false) {
      start = cursor;
      end = cursor;
      status = StepStatus.skipped;
    } else if (i < lastStarted) {
      start = cursor;
      end = cursor;
      status = StepStatus.notDone;
    } else {
      if (expectedStart.isBefore(earliestPending)) {
        expectedStart = earliestPending;
      }
      start = expectedStart;
      end = start.add(step.duration);
      status = StepStatus.pending;
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

/// Identifiants de [steps], après vérification qu'aucun n'est en double.
Set<String> _requireUniqueIds(List<PlannedStep> steps) {
  final ids = {for (final s in steps) s.id};
  if (ids.length != steps.length) {
    throw BrewingInputException(
      'steps',
      steps.map((s) => s.id).toList(),
      'identifiants en double',
    );
  }
  return ids;
}

/// Nature d'un événement d'étape (`brews/{id}/events/{eventId}.kind`).
enum StepEventKind {
  /// Début d'étape. Valeur stockée : `step_started`.
  started('step_started'),

  /// Fin d'étape. Valeur stockée : `step_ended`.
  ended('step_ended'),

  /// Étape marquée sautée. Valeur stockée : `step_skipped`.
  skipped('step_skipped');

  const StepEventKind(this.storedValue);

  /// Valeur du champ `kind` d'un événement.
  final String storedValue;

  /// Nature correspondant à la valeur stockée [value].
  ///
  /// Lève [BrewingInputException] sur une valeur inconnue, dont celles des
  /// événements qui ne portent pas sur une étape (`measurement`, `note`).
  static StepEventKind fromStored(String value) =>
      enumFromStored(values, (k) => k.storedValue, 'events.kind', value);
}

/// Un événement d'étape enregistré par un appareil.
class StepEvent {
  /// Crée l'événement. [measuredAt] : heure de l'appareil.
  const StepEvent({
    required this.id,
    required this.kind,
    required this.stepKey,
    required this.measuredAt,
  });

  /// Identifiant du document, créé par l'appareil.
  final String id;

  /// Début, fin ou saut.
  final StepEventKind kind;

  /// Étape concernée (`step_key`).
  final String stepKey;

  /// Heure de l'appareil (`measured_at`).
  final DateTime measuredAt;
}

/// Raison pour laquelle un événement d'étape n'est pas retenu.
enum StepEventIssueKind {
  /// Début d'une étape qui a un début plus ancien (deux appareils hors ligne).
  duplicateStart,

  /// Fin d'une étape qui a une fin plus récente.
  duplicateEnd,

  /// Fin d'une étape sans début.
  endWithoutStart,

  /// Fin antérieure au début retenu de l'étape.
  endBeforeStart,

  /// Événement d'une étape absente de la chronologie.
  unknownStep,
}

/// Événement d'étape non retenu, et sa raison.
class StepEventIssue {
  /// Crée l'anomalie.
  const StepEventIssue(this.kind, this.event);

  /// Raison.
  final StepEventIssueKind kind;

  /// Événement non retenu.
  final StepEvent event;
}

/// Résultat de [stepRecordsFromEvents].
class StepEventReduction {
  /// Crée le résultat.
  const StepEventReduction({required this.records, required this.issues});

  /// Un enregistrement par étape qui a un début ou un saut, dans l'ordre de la
  /// chronologie. Se passe tel quel à [recomputeSchedule].
  final List<StepRecord> records;

  /// Événements non retenus, par heure croissante puis par identifiant.
  final List<StepEventIssue> issues;
}

/// Réduit les événements d'étape d'un brassin en un enregistrement par étape.
///
/// Pour chaque étape de [steps] : le début le plus ancien (à égalité, le plus
/// petit identifiant), la dernière fin à ou après ce début, et les sauts. Les
/// autres événements sont rendus dans [StepEventReduction.issues] : débuts et
/// fins en double, fin sans début ou avant le début, étape inconnue. Deux
/// appareils hors ligne produisent ces cas : la fonction ne lève pas pour eux,
/// et le résultat est le même sur chaque appareil.
///
/// Lève [BrewingInputException] si deux étapes de [steps] ont le même
/// identifiant (chronologie illisible).
StepEventReduction stepRecordsFromEvents({
  required List<PlannedStep> steps,
  required List<StepEvent> events,
}) {
  final ids = _requireUniqueIds(steps);
  final issues = <StepEventIssue>[];
  final byStep = <String, List<StepEvent>>{};
  for (final e in events.toList()..sort(_byTimeThenId)) {
    if (ids.contains(e.stepKey)) {
      (byStep[e.stepKey] ??= []).add(e);
    } else {
      issues.add(StepEventIssue(StepEventIssueKind.unknownStep, e));
    }
  }

  final records = <StepRecord>[];
  for (final step in steps) {
    final stepEvents = byStep[step.id];
    if (stepEvents == null) continue;
    final starts = [
      for (final e in stepEvents)
        if (e.kind == StepEventKind.started) e,
    ];
    final skips = [
      for (final e in stepEvents)
        if (e.kind == StepEventKind.skipped) e.id,
    ];
    final start = starts.isEmpty ? null : starts.first;
    for (final duplicate in starts.skip(1)) {
      issues.add(StepEventIssue(StepEventIssueKind.duplicateStart, duplicate));
    }

    StepEvent? end;
    for (final e in stepEvents) {
      if (e.kind != StepEventKind.ended) continue;
      if (start == null) {
        issues.add(StepEventIssue(StepEventIssueKind.endWithoutStart, e));
      } else if (e.measuredAt.isBefore(start.measuredAt)) {
        issues.add(StepEventIssue(StepEventIssueKind.endBeforeStart, e));
      } else {
        final previous = end;
        if (previous != null) {
          issues.add(StepEventIssue(StepEventIssueKind.duplicateEnd, previous));
        }
        end = e;
      }
    }

    if (start == null && skips.isEmpty) continue;
    records.add(
      StepRecord(
        stepId: step.id,
        startedAt: start?.measuredAt,
        endedAt: end?.measuredAt,
        skipped: skips.isNotEmpty,
        startEventId: start?.id,
        endEventId: end?.id,
        skipEventIds: skips,
      ),
    );
  }
  return StepEventReduction(
    records: records,
    issues: issues..sort((a, b) => _byTimeThenId(a.event, b.event)),
  );
}

/// Ordre des événements : heure croissante, puis identifiant.
int _byTimeThenId(StepEvent a, StepEvent b) {
  final byTime = a.measuredAt.compareTo(b.measuredAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
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
