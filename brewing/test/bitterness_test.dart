import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('ibu');

  double ibuOf(Map<String, Object?> inputs) => tinsethIbu(
    hops: objects(inputs['hops']).map(hop).toList(),
    volumeLitres: number(inputs['volume_litres']),
    boilGravity: number(inputs['boil_gravity']),
  );

  test('utilisation de Tinseth', () {
    for (final c in objects(fixture['utilization'])) {
      expect(
        tinsethUtilization(
          boilMinutes: number(c['boil_minutes']),
          boilGravity: number(c['boil_gravity']),
        ),
        closeTo(number(c['expected']), number(c['tolerance'])),
      );
    }
  });

  test('IBU', () {
    for (final c in objects(fixture['cases'])) {
      expectCase(c, ibuOf(c['inputs'] as Map<String, Object?>));
    }
  });

  test('IBU : entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      final m = c['hop'] as Map<String, Object?>;
      expectInvalid(
        () => tinsethIbuForHop(
          hop: hop(m),
          volumeLitres: optionalNumber(c['volume_litres']) ?? 20,
          boilGravity: 1.050,
        ),
        label(c),
      );
    }
  });

  test('pellets = cônes × 1,1', () {
    Hop make(HopForm form) => Hop(
      name: 'Magnum',
      alphaPercent: 12,
      massGrams: 25,
      use: HopUse.boil,
      form: form,
      boilMinutes: 60,
    );
    final whole = tinsethIbuForHop(
      hop: make(HopForm.whole),
      volumeLitres: 20,
      boilGravity: 1.06,
    );
    final pellet = tinsethIbuForHop(
      hop: make(HopForm.pellet),
      volumeLitres: 20,
      boilGravity: 1.06,
    );
    expect(pellet, closeTo(whole * 1.1, 1e-9));
  });
}
