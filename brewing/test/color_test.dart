import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('color');

  double ebcOf(Map<String, Object?> inputs) => moreyColorEbc(
    fermentables: fermentables(inputs['fermentables']),
    volumeLitres: number(inputs['volume_litres']),
  );

  test('EBC de Morey', () {
    for (final c in objects(fixture['cases'])) {
      expectCase(c, ebcOf(c['inputs'] as Map<String, Object?>));
    }
  });

  test('EBC : entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(() => ebcOf(c['inputs'] as Map<String, Object?>), label(c));
    }
  });
}
