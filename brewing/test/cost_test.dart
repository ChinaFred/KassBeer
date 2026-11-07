import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<CostLine> _lines(Object? value) => objects(value)
    .map(
      (m) => CostLine(
        name: m['name'] as String,
        quantity: number(m['quantity']),
        unitPrice: optionalNumber(m['unit_price']),
      ),
    )
    .toList();

CostResult _costOf(Map<String, Object?> inputs) => computeCost(
  lines: _lines(inputs['lines']),
  volumeLitres: number(inputs['volume_litres']),
);

void main() {
  final fixture = loadFixture('cost');

  test('coût des fiches', () {
    for (final c in objects(fixture['cases'])) {
      final result = _costOf(c['inputs'] as Map<String, Object?>);
      final expected = c['expected'] as Map<String, Object?>;
      final missing = expected['missing'];
      if (missing != null) {
        expect(result, isA<CostUnavailable>(), reason: label(c));
        expect(
          (result as CostUnavailable).linesWithoutPrice,
          (missing as List<Object?>).cast<String>(),
          reason: label(c),
        );
        continue;
      }
      expect(result, isA<CostComputed>(), reason: label(c));
      final computed = result as CostComputed;
      final tolerance = number(c['tolerance']);
      expect(computed.total, closeTo(number(expected['total']), tolerance));
      expect(
        computed.perLitre,
        closeTo(number(expected['per_litre']), tolerance),
      );
      expect(
        computed.perBottle33cl,
        closeTo(number(expected['per_bottle_33cl']), tolerance),
      );
      final fiche = c['fiche_value'] as Map<String, Object?>?;
      if (fiche != null) {
        expect(
          computed.total,
          closeTo(number(fiche['total']), number(c['fiche_tolerance'])),
          reason: '${label(c)} : total de la fiche non retrouvé',
        );
      }
    }
  });

  test('coût : entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(
        () => _costOf(c['inputs'] as Map<String, Object?>),
        label(c),
      );
    }
  });
}
