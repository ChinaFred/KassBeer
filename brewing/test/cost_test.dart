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
  volumeLitres: optionalNumber(inputs['volume_litres']),
);

void _expectOptional(Object? expected, double? actual, double tolerance) {
  if (expected == null) {
    expect(actual, isNull);
  } else {
    expect(actual, closeTo(number(expected), tolerance));
  }
}

IngredientNature _nature(String prefix) =>
    IngredientNature.values.firstWhere((n) => n.prefix == prefix);

CostItem _item(Map<String, Object?> m) => CostItem(
  key: m['key'] as String,
  name: m['name'] as String,
  quantity: number(m['quantity']),
  unit: CostUnit.fromStored(m['unit'] as String),
);

/// Vérifie qu'aucune erreur ne porte la valeur reçue (SE3) : ni dans `value`, ni
/// dans le texte de l'erreur.
Matcher _throwsWithoutValue(List<String> hidden) => throwsA(
  isA<BrewingInputException>()
      .having((e) => e.value, 'value', isNull)
      .having(
        (e) => e.toString(),
        'toString',
        allOf([for (final h in hidden) isNot(contains(h))]),
      ),
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
      _expectOptional(expected['per_litre'], computed.perLitre, tolerance);
      _expectOptional(
        expected['per_bottle_33cl'],
        computed.perBottle33cl,
        tolerance,
      );
      final lineCosts = expected['line_costs'] as List<Object?>?;
      if (lineCosts != null) {
        expect(computed.lineCosts.length, lineCosts.length, reason: label(c));
        for (final (i, cost) in lineCosts.indexed) {
          expect(computed.lineCosts[i], closeTo(number(cost), tolerance));
        }
      }
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

  group('prix unitaire d\'un achat (PR7, LI8)', () {
    final section = fixture['unit_prices'] as Map<String, Object?>;

    test('cas', () {
      for (final c in objects(section['cases'])) {
        final price = unitPriceFor(
          priceEur: number(c['price_eur']),
          quantity: number(c['quantity']),
          purchaseUnit: CostUnit.fromStored(c['purchase_unit'] as String),
          lineUnit: CostUnit.fromStored(c['line_unit'] as String),
        );
        if (c['incompatible'] == true) {
          expect(price, isNull, reason: label(c));
          continue;
        }
        expect(price, isNotNull, reason: label(c));
        expectCase(c, price!);
        expect(
          unitPrice(
            priceEur: number(c['price_eur']),
            quantity: number(c['quantity']),
          ),
          price,
        );
      }
    });

    test('entrées invalides', () {
      for (final c in objects(section['invalid'])) {
        expectInvalid(
          () => unitPrice(
            priceEur: number(c['price_eur']),
            quantity: number(c['quantity']),
          ),
          label(c),
        );
      }
    });
  });

  group('regroupement par clé (LI2)', () {
    final section = fixture['grouping'] as Map<String, Object?>;

    test('cas', () {
      for (final c in objects(section['cases'])) {
        final grouped = groupCostItems(objects(c['items']).map(_item).toList());
        final expected = objects(c['expected']);
        expect(grouped.length, expected.length, reason: label(c));
        for (final (i, e) in expected.indexed) {
          expect(grouped[i].key, e['key'], reason: label(c));
          expect(grouped[i].name, e['name'], reason: label(c));
          expect(grouped[i].quantity, number(e['quantity']), reason: label(c));
        }
        final prices = (c['unit_price'] as Map<String, Object?>).map(
          (k, v) => MapEntry(k, number(v)),
        );
        final result = computeCost(
          lines: [
            for (final g in grouped)
              CostLine(
                name: g.name,
                quantity: g.quantity,
                unitPrice: prices[g.key],
              ),
          ],
          volumeLitres: null,
        );
        final missing = c['expected_missing'] as List<Object?>?;
        if (missing != null) {
          expect(
            (result as CostUnavailable).linesWithoutPrice,
            missing.cast<String>(),
            reason: label(c),
          );
          continue;
        }
        final cost = c['expected_cost'] as Map<String, Object?>;
        final tolerance = number(c['tolerance']);
        final computed = result as CostComputed;
        expect(computed.total, closeTo(number(cost['total']), tolerance));
        for (final (i, v) in (cost['line_costs'] as List<Object?>).indexed) {
          expect(computed.lineCosts[i], closeTo(number(v), tolerance));
        }
      }
    });

    test('entrées invalides', () {
      for (final c in objects(section['invalid'])) {
        expectInvalid(
          () => groupCostItems(objects(c['items']).map(_item).toList()),
          label(c),
        );
      }
    });
  });

  group('quantité d\'un frais (FR4, CR3)', () {
    final section = fixture['fee_quantities'] as Map<String, Object?>;

    double quantityOf(Map<String, Object?> c) {
      final volume = optionalNumber(c['volume_litres']);
      return feeQuantity(
        FeeBasis.fromStored(c['basis'] as String),
        bottles: volume != null
            ? bottles33clIn(volume)
            : optionalNumber(c['bottles']),
      );
    }

    test('cas', () {
      for (final c in objects(section['cases'])) {
        expectCase(c, quantityOf(c));
      }
    });

    test('entrées invalides', () {
      for (final c in objects(section['invalid'])) {
        expectInvalid(() => quantityOf(c), label(c));
      }
    });
  });

  group('coût par bouteille réelle (CB13)', () {
    final section = fixture['per_bottle'] as Map<String, Object?>;

    test('cas, et valeur arrondie de la fiche', () {
      for (final c in objects(section['cases'])) {
        final value = costPerBottle(
          total: number(c['total']),
          bottles: number(c['bottles']).toInt(),
        );
        expectCase(c, value);
        expect(
          (value * 100).round() / 100,
          number(c['fiche_value']),
          reason: '${label(c)} : arrondi au centime',
        );
      }
    });

    test('entrées invalides', () {
      for (final c in objects(section['invalid'])) {
        expectInvalid(
          () => costPerBottle(
            total: number(c['total']),
            bottles: number(c['bottles']).toInt(),
          ),
          label(c),
        );
      }
    });
  });

  group('coût par litre (CB12, CB14)', () {
    final section = fixture['per_litre'] as Map<String, Object?>;

    test('cas', () {
      for (final c in objects(section['cases'])) {
        expectCase(
          c,
          costPerLitre(
            total: number(c['total']),
            volumeLitres: number(c['volume_litres']),
          ),
        );
      }
    });

    test('entrées invalides', () {
      for (final c in objects(section['invalid'])) {
        expectInvalid(
          () => costPerLitre(
            total: number(c['total']),
            volumeLitres: number(c['volume_litres']),
          ),
          label(c),
        );
      }
    });
  });

  test('coût d\'un brassin et d\'une recette des fiches (FIN2, FIN3)', () {
    final section = fixture['brew_cases'] as Map<String, Object?>;
    for (final c in objects(section['cases'])) {
      final ingredients = objects(c['ingredients']);
      final prices = <String, double>{};
      final items = <CostItem>[];
      for (final m in ingredients) {
        final key = ingredientKey(
          _nature(m['nature'] as String),
          m['name'] as String,
        );
        prices[key] = number(m['unit_price']);
        items.add(
          CostItem(
            key: key,
            name: m['name'] as String,
            quantity: number(m['quantity']),
            unit: CostUnit.fromStored(m['unit'] as String),
          ),
        );
      }
      final volume = number(c['volume_litres']);
      final realBottles = optionalNumber(c['bottles']);
      final bottles = realBottles ?? bottles33clIn(volume);
      final lines = [
        for (final g in groupCostItems(items))
          CostLine(
            name: g.name,
            quantity: g.quantity,
            unitPrice: prices[g.key],
          ),
        for (final f in objects(c['fees']))
          CostLine(
            name: f['name'] as String,
            quantity: feeQuantity(
              FeeBasis.fromStored(f['basis'] as String),
              bottles: bottles,
            ),
            unitPrice: number(f['amount_eur']),
          ),
      ];
      final result = computeCost(lines: lines, volumeLitres: volume);
      expect(result, isA<CostComputed>(), reason: label(c));
      final computed = result as CostComputed;
      final expected = c['expected'] as Map<String, Object?>;
      final tolerance = number(c['tolerance']);
      expect(
        computed.total,
        closeTo(number(expected['total']), tolerance),
        reason: label(c),
      );
      expect(
        computed.perLitre,
        closeTo(number(expected['per_litre']), tolerance),
        reason: label(c),
      );
      if (expected['per_bottle_33cl'] != null) {
        expect(
          computed.perBottle33cl,
          closeTo(number(expected['per_bottle_33cl']), tolerance),
          reason: label(c),
        );
      }
      if (realBottles != null) {
        final perBottle = costPerBottle(
          total: computed.total,
          bottles: realBottles.toInt(),
        );
        expect(
          perBottle,
          closeTo(number(expected['per_bottle']), tolerance),
          reason: label(c),
        );
        final fiche = c['fiche_value'] as Map<String, Object?>;
        expect(
          computed.total,
          closeTo(number(fiche['total']), number(c['fiche_tolerance'])),
          reason: '${label(c)} : total de la fiche non retrouvé',
        );
        expect(
          (perBottle * 100).round() / 100,
          number(fiche['per_bottle']),
          reason: '${label(c)} : coût par bouteille de la fiche',
        );
      }
    }
  });

  test('aucune erreur du coût ne porte un prix ni un montant (SE3)', () {
    expect(
      () => CostLine(name: 'Pils', quantity: 1, unitPrice: -0.0123),
      _throwsWithoutValue(['0.0123']),
    );
    expect(
      () => CostLine(name: 'Pils', quantity: 1, unitPrice: double.nan),
      _throwsWithoutValue(['NaN']),
    );
    expect(
      () => CostLine(name: 'Pils', quantity: 1, unitPrice: double.infinity),
      _throwsWithoutValue(['Infinity']),
    );
    expect(
      () => CostLine(name: 'Pils', quantity: -4321, unitPrice: 0.002),
      _throwsWithoutValue(['4321']),
    );
    expect(
      () => unitPrice(priceEur: -47.5, quantity: 25000),
      _throwsWithoutValue(['47.5']),
    );
    expect(
      () => unitPrice(priceEur: 47.5, quantity: 0),
      _throwsWithoutValue(['47.5']),
    );
    expect(
      () => computeCost(lines: const [], volumeLitres: -17.25),
      _throwsWithoutValue(['17.25']),
    );
    expect(
      () => costPerBottle(total: -40.84, bottles: 50),
      _throwsWithoutValue(['40.84']),
    );
    expect(
      () => costPerLitre(total: -40.84, volumeLitres: 17),
      _throwsWithoutValue(['40.84']),
    );
    expect(
      () => feeQuantity(FeeBasis.perBottle, bottles: -51),
      _throwsWithoutValue(['51']),
    );
    expect(
      () => CostItem(
        key: 'malt-pils',
        name: 'Pils',
        quantity: -987,
        unit: CostUnit.gram,
      ),
      _throwsWithoutValue(['987']),
    );
  });

  test('valeurs stockées des unités et des bases', () {
    expect(CostUnit.values.map((u) => u.storedValue), [
      'g',
      'unit',
      'brew',
      'bottle',
    ]);
    expect(CostUnit.purchaseUnits, [CostUnit.gram, CostUnit.unit]);
    expect(FeeBasis.values.map((b) => b.storedValue), [
      'per_brew',
      'per_bottle',
    ]);
    expect(FeeBasis.perBrew.unit, CostUnit.brew);
    expect(FeeBasis.perBottle.unit, CostUnit.bottle);
    expect(
      () => CostUnit.fromStored('kwh'),
      throwsA(isA<BrewingInputException>()),
    );
    expect(
      () => FeeBasis.fromStored('per_litre'),
      throwsA(isA<BrewingInputException>()),
    );
    expect(yeastSachetsPerLine, 1);
  });
}
