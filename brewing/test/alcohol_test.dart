import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('abv');

  double abvOf(Map<String, Object?> inputs) => alcoholByVolume(
    originalGravity: number(inputs['original_gravity']),
    finalGravity: number(inputs['final_gravity']),
  );

  test('degré des fiches', () {
    for (final c in objects(fixture['cases'])) {
      expectCase(c, abvOf(c['inputs'] as Map<String, Object?>));
    }
  });

  test('degré : entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(() => abvOf(c['inputs'] as Map<String, Object?>), label(c));
    }
  });

  test('degré après refermentation en bouteille', () {
    for (final c in objects(fixture['bottling_cases'])) {
      final inputs = c['inputs'] as Map<String, Object?>;
      final priming = inputs['priming'] as Map<String, Object?>?;
      final result = alcoholByVolumeAfterBottling(
        abvBeforeBottling: number(inputs['abv_before']),
        priming: priming == null
            ? null
            : PrimingSugar(
                gramsPerLitre: number(priming['grams_per_litre']),
                pointsPerKgPerLitre: number(priming['points_per_kg_per_litre']),
              ),
      );
      if (c['expected'] == null) {
        expect(result, isNull, reason: label(c));
      } else {
        expectCase(c, result!);
      }
    }
  });

  test('divergences : le calcul ne retrouve pas la fiche', () {
    for (final d in objects(fixture['divergences'])) {
      final inputs = d['inputs'] as Map<String, Object?>?;
      if (inputs == null) continue;
      final computed = abvOf(inputs);
      expect(computed, closeTo(number(d['computed']), 1e-6));
      expect(
        (computed - number(d['fiche_value'])).abs(),
        greaterThan(0.07),
        reason: '${d['source']} : divergence qui n\'en est plus une',
      );
    }
  });
}
