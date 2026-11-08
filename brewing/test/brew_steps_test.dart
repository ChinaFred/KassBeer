import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<BrewStepDraft> _run(Map<String, Object?> c) => defaultBrewSteps(
  mashSteps: [
    for (final m in objects(c['mash_steps']))
      MashStepInput(
        tempC: optionalNumber(m['temp_c']),
        durationMinutes: optionalNumber(m['duration_minutes']),
      ),
  ],
  boilMinutes: optionalNumber(c['boil_minutes']),
  hops: [
    for (final h in objects(c['hops']))
      HopInput(
        name: h['name'] as String,
        massGrams: number(h['mass_grams']),
        use: HopUse.values.byName(h['use'] as String),
        form: HopForm.pellet,
        minutes: optionalNumber(h['minutes']),
      ),
  ],
);

void main() {
  final fixture = loadFixture('brew_steps');

  test('chronologie préremplie', () {
    for (final c in objects(fixture['cases'])) {
      final result = _run(c);
      final expected = objects(c['expected']);
      expect(result.length, expected.length, reason: label(c));
      for (var i = 0; i < expected.length; i++) {
        final e = expected[i];
        final r = result[i];
        final at = '${label(c)} / étape $i';
        expect(r.kind.name, e['kind'], reason: at);
        expect(r.sourceIndex, e['source_index'], reason: at);
        expect(
          r.durationMinutes,
          optionalNumber(e['duration_minutes']),
          reason: at,
        );
        expect(r.tempC, optionalNumber(e['temp_c']), reason: at);
        expect(r.problem?.name, e['problem'], reason: at);
      }
    }
  });

  test('chronologie préremplie : entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(() => _run(c), label(c));
    }
  });
}
