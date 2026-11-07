import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('final_gravity');

  double fgOf(Map<String, Object?> inputs) => predictedFinalGravity(
    originalGravity: number(inputs['original_gravity']),
    attenuationPercent: number(inputs['attenuation_percent']),
  );

  test('densité finale prévue par l\'atténuation', () {
    for (final c in objects(fixture['cases'])) {
      expectCase(c, fgOf(c['inputs'] as Map<String, Object?>));
    }
  });

  test('densité finale : entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(() => fgOf(c['inputs'] as Map<String, Object?>), label(c));
    }
  });

  test('atténuation 0 % : degré nul', () {
    final fg = predictedFinalGravity(
      originalGravity: 1.06,
      attenuationPercent: 0,
    );
    expect(
      alcoholByVolume(originalGravity: 1.06, finalGravity: fg),
      closeTo(0, 1e-12),
    );
  });
}
