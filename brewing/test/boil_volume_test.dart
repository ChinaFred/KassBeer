import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Nombre d'une fixture, « Infinity » compris (JSON n'a pas d'infini).
double _nombre(Object? value) =>
    value == 'Infinity' ? double.infinity : number(value);

double _volume(Map<String, Object?> c) => preBoilVolumeLitres(
  batchLitres: _nombre(c['batch_litres']),
  boilMinutes: _nombre(c['boil_minutes']),
  boilOffLitresPerHour: _nombre(c['boil_off_litres_per_hour']),
  trubLossLitres: _nombre(c['trub_loss_litres']),
  kettleDeadSpaceLitres: _nombre(c['kettle_dead_space_litres']),
);

void main() {
  final fixture = loadFixture('boil_volume');

  test('volume avant ébullition : cas de la fixture', () {
    final cases = objects(fixture['cases']);
    expect(cases, isNotEmpty);
    for (final c in cases) {
      expectCase(c, _volume(c));
    }
  });

  test('entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(() => _volume(c), label(c));
    }
  });
}
