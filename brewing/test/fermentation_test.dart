import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('fermentation');

  test('série d\'un relevé', () {
    for (final c in objects(fixture['cases'])) {
      final brewedAt = DateTime.parse(c['brewed_at'] as String);
      final points = fermentationSeries(
        brewedAt: brewedAt,
        readings: [
          for (final r in objects(c['readings']))
            FermentationReading(
              measuredAt: DateTime.parse(r['measured_at'] as String),
              gravity: optionalNumber(r['gravity']),
              temperature: optionalNumber(r['temperature']),
            ),
        ],
      );
      final expected = objects(c['expected']);
      expect(points.length, expected.length, reason: label(c));
      for (final (i, e) in expected.indexed) {
        final p = points[i];
        final reason = '${label(c)} [$i]';
        expect(
          p.measuredAt,
          DateTime.parse(e['measured_at'] as String),
          reason: reason,
        );
        expect(p.dayNumber, e['day_number'], reason: reason);
        expect(
          p.dayOffset,
          closeTo(number(e['day_offset']), 1e-6),
          reason: reason,
        );
        expect(p.gravity, optionalNumber(e['gravity']), reason: reason);
        expect(p.temperature, optionalNumber(e['temperature']), reason: reason);
        final change = optionalNumber(e['gravity_change_points']);
        if (change == null) {
          expect(p.gravityChangePoints, isNull, reason: reason);
        } else {
          expect(p.gravityChangePoints, closeTo(change, 1e-6), reason: reason);
        }
      }
    }
  });

  test('J+N : la partie entière de dayOffset vaut dayNumber', () {
    final brewedAt = DateTime(2026, 11, 8, 15, 20);
    for (final at in [
      DateTime(2026, 11, 8, 23, 59),
      DateTime(2026, 11, 9),
      DateTime(2026, 11, 30, 12),
    ]) {
      final point = fermentationSeries(
        brewedAt: brewedAt,
        readings: [FermentationReading(measuredAt: at, gravity: 1.05)],
      ).single;
      expect(point.dayOffset.floor(), point.dayNumber);
      expect(
        fermentationDayNumber(brewedAt: brewedAt, at: at),
        point.dayNumber,
      );
    }
  });

  test('un relevé ni densité ni température est refusé', () {
    expect(
      () => FermentationReading(measuredAt: DateTime(2026, 11, 9)),
      throwsA(isA<BrewingInputException>()),
    );
  });
}
