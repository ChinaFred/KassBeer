import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Heure d'une fixture : « HH:MM » le jour [date], ou « AAAA-MM-JJTHH:MM ».
DateTime _at(String date, String time) =>
    DateTime.parse(time.contains('T') ? time : '${date}T$time:00');

/// Inverse de [_at] : « HH:MM » le jour [date], sinon avec la date.
String _format(String date, DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hhmm = '${two(t.hour)}:${two(t.minute)}';
  final day = '${t.year}-${two(t.month)}-${two(t.day)}';
  return day == date ? hhmm : '${day}T$hhmm';
}

List<PlannedStep> _steps(Object? raw) => objects(raw)
    .map(
      (s) => PlannedStep(
        id: s['id'] as String,
        duration: Duration(minutes: (s['duration_minutes'] as num).toInt()),
      ),
    )
    .toList();

List<StepRecord> _records(Map<String, Object?> c, String date) {
  final records = <StepRecord>[];
  for (final s in objects(c['steps'])) {
    final started = s['started_at'] as String?;
    final ended = s['ended_at'] as String?;
    final skipped = (s['skipped'] as bool?) ?? false;
    if (started == null && ended == null && !skipped) continue;
    records.add(
      StepRecord(
        stepId: s['id'] as String,
        startedAt: started == null ? null : _at(date, started),
        endedAt: ended == null ? null : _at(date, ended),
        skipped: skipped,
      ),
    );
  }
  for (final r in objects(c['records'] ?? const <Object?>[])) {
    records.add(
      StepRecord(
        stepId: r['step_id'] as String,
        skipped: (r['skipped'] as bool?) ?? false,
      ),
    );
  }
  return records;
}

List<ScheduledStep> _run(
  Map<String, Object?> c,
  String date,
  List<StepRecord> records,
) => recomputeSchedule(
  steps: _steps(c['steps']),
  plannedStart: _at(date, (c['planned_start'] as String?) ?? '10:00'),
  records: records,
  now: _at(date, (c['now'] as String?) ?? '10:00'),
);

/// Compare [result] aux étapes attendues [expected] d'un cas.
void _expectSchedule(
  List<ScheduledStep> result,
  Object? expected,
  String date,
  String where,
) {
  final steps = objects(expected);
  expect(result.length, steps.length, reason: where);
  for (var i = 0; i < steps.length; i++) {
    final e = steps[i];
    final r = result[i];
    final at = '$where / ${e['id']}';
    expect(r.stepId, e['id'], reason: at);
    expect(_format(date, r.expectedStart), e['expected_start'], reason: at);
    expect(r.status.name, e['status'], reason: at);
    if (e['start'] != null) {
      expect(_format(date, r.start), e['start'], reason: at);
    }
    if (e['end'] != null) expect(_format(date, r.end), e['end'], reason: at);
  }
}

StepEvent _event(Map<String, Object?> e, String date) => StepEvent(
  id: e['id'] as String,
  kind: StepEventKind.fromStored(e['kind'] as String),
  stepKey: e['step_key'] as String,
  measuredAt: _at(date, e['measured_at'] as String),
);

void main() {
  final fixture = loadFixture('planning');
  final scheduleCases = {
    for (final c in objects(fixture['schedule_cases'])) c['id']: c,
  };

  test('planning recalculé', () {
    for (final c in scheduleCases.values) {
      final date = c['date'] as String;
      final result = _run(c, date, _records(c, date));
      _expectSchedule(result, c['expected'], date, label(c));
      final fiche = c['fiche_value'] as List<Object?>?;
      if (fiche != null) {
        expect(
          result.map((r) => _format(date, r.expectedStart)).toList(),
          fiche,
          reason: '${label(c)} : colonne de la fiche non retrouvée',
        );
      }
      final lastEnd = c['expected_last_end'] as String?;
      if (lastEnd != null) {
        expect(_format(date, result.last.end), lastEnd, reason: label(c));
      }
    }
  });

  test('planning : entrées invalides', () {
    for (final c in objects(fixture['schedule_invalid'])) {
      expectInvalid(
        () => _run(c, '2026-11-07', _records(c, '2026-11-07')),
        label(c),
      );
    }
  });

  test('enregistrement d\'une étape inconnue refusé', () {
    expectInvalid(
      () => recomputeSchedule(
        steps: [PlannedStep(id: 'a', duration: const Duration(minutes: 5))],
        plannedStart: DateTime(2026, 11, 7, 10),
        records: [
          StepRecord(stepId: 'b', startedAt: DateTime(2026, 11, 7, 10)),
        ],
        now: DateTime(2026, 11, 7, 10),
      ),
      'étape inconnue',
    );
  });

  test('événements réduits en enregistrements par étape', () {
    for (final c in objects(fixture['event_cases'])) {
      final source = scheduleCases[c['schedule_case']];
      final date = (source ?? c)['date'] as String;
      final steps = _steps((source ?? c)['steps']);
      final reduction = stepRecordsFromEvents(
        steps: steps,
        events: [for (final e in objects(c['events'])) _event(e, date)],
      );

      final expected = objects(c['expected_records']);
      expect(reduction.records.length, expected.length, reason: label(c));
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final r = reduction.records[i];
        final at = '${label(c)} / ${e['step_id']}';
        final started = e['started_at'] as String?;
        final ended = e['ended_at'] as String?;
        expect(r.stepId, e['step_id'], reason: at);
        expect(r.startedAt, started == null ? null : _at(date, started));
        expect(r.endedAt, ended == null ? null : _at(date, ended));
        expect(r.skipped, (e['skipped'] as bool?) ?? false, reason: at);
        expect(r.startEventId, e['start_event_id'], reason: at);
        expect(r.endEventId, e['end_event_id'], reason: at);
        expect(
          r.skipEventIds,
          (e['skip_event_ids'] as List<Object?>?) ?? const <Object?>[],
          reason: at,
        );
      }

      expect(
        [
          for (final i in reduction.issues)
            {'kind': i.kind.name, 'event_id': i.event.id},
        ],
        c['expected_issues'],
        reason: label(c),
      );

      // Le planning se calcule sur les enregistrements réduits.
      final schedule = (c['schedule'] as Map<String, Object?>?) ?? source;
      if (schedule != null) {
        final result = recomputeSchedule(
          steps: steps,
          plannedStart: _at(date, schedule['planned_start'] as String),
          records: reduction.records,
          now: _at(date, schedule['now'] as String),
        );
        _expectSchedule(result, schedule['expected'], date, label(c));
      }
    }
  });

  test('événements : chronologie illisible refusée', () {
    for (final c in objects(fixture['event_invalid'])) {
      expectInvalid(
        () => stepRecordsFromEvents(steps: _steps(c['steps']), events: []),
        label(c),
      );
    }
  });

  test('nature d\'événement : valeurs stockées', () {
    expect(StepEventKind.values.map((k) => k.storedValue), [
      'step_started',
      'step_ended',
      'step_skipped',
    ]);
    for (final kind in StepEventKind.values) {
      expect(StepEventKind.fromStored(kind.storedValue), kind);
    }
    expectInvalid(() => StepEventKind.fromStored('measurement'), 'mesure');
    expectInvalid(() => StepEventKind.fromStored('note'), 'note');
  });

  test('minuteur', () {
    for (final c in objects(fixture['timer_cases'])) {
      final reading = readTimer(
        startedAt: DateTime.parse(c['started_at'] as String),
        duration: Duration(minutes: (c['duration_minutes'] as num).toInt()),
        now: DateTime.parse(c['now'] as String),
      );
      final e = c['expected'] as Map<String, Object?>;
      expect(reading.elapsed.inSeconds, e['elapsed_seconds'], reason: label(c));
      expect(
        reading.remaining.inSeconds,
        e['remaining_seconds'],
        reason: label(c),
      );
      expect(reading.overrun.inSeconds, e['overrun_seconds'], reason: label(c));
      expect(reading.isFinished, e['finished'], reason: label(c));
    }
  });

  test('minuteur : durée négative refusée', () {
    expectInvalid(
      () => readTimer(
        startedAt: DateTime(2026),
        duration: const Duration(minutes: -1),
        now: DateTime(2026),
      ),
      'durée négative',
    );
  });
}
