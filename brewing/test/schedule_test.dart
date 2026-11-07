import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

DateTime _at(String date, String hhmm) => DateTime.parse('${date}T$hhmm:00');

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

List<ScheduledStep> _run(Map<String, Object?> c, String date) {
  final raw = objects(c['steps']);
  final steps = raw
      .map(
        (s) => PlannedStep(
          id: s['id'] as String,
          duration: Duration(minutes: (s['duration_minutes'] as num).toInt()),
        ),
      )
      .toList();
  final records = <StepRecord>[];
  for (final s in raw) {
    final started = s['started_at'] as String?;
    final ended = s['ended_at'] as String?;
    if (started == null && ended == null) continue;
    records.add(
      StepRecord(
        stepId: s['id'] as String,
        startedAt: started == null ? null : _at(date, started),
        endedAt: ended == null ? null : _at(date, ended),
      ),
    );
  }
  return recomputeSchedule(
    steps: steps,
    plannedStart: _at(date, (c['planned_start'] as String?) ?? '10:00'),
    records: records,
    now: _at(date, (c['now'] as String?) ?? '10:00'),
  );
}

void main() {
  final fixture = loadFixture('planning');

  test('planning recalculé', () {
    for (final c in objects(fixture['schedule_cases'])) {
      final date = c['date'] as String;
      final result = _run(c, date);
      final expected = objects(c['expected']);
      expect(result.length, expected.length, reason: label(c));
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final r = result[i];
        final where = '${label(c)} / ${e['id']}';
        expect(r.stepId, e['id'], reason: where);
        expect(_hhmm(r.expectedStart), e['expected_start'], reason: where);
        expect(r.status.name, e['status'], reason: where);
        if (e['end'] != null) expect(_hhmm(r.end), e['end'], reason: where);
      }
      final fiche = c['fiche_value'] as List<Object?>?;
      if (fiche != null) {
        expect(
          result.map((r) => _hhmm(r.expectedStart)).toList(),
          fiche,
          reason: '${label(c)} : colonne de la fiche non retrouvée',
        );
      }
      final lastEnd = c['expected_last_end'] as String?;
      if (lastEnd != null) expect(_hhmm(result.last.end), lastEnd);
    }
  });

  test('planning : entrées invalides', () {
    for (final c in objects(fixture['schedule_invalid'])) {
      expectInvalid(() => _run(c, '2026-11-07'), label(c));
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
