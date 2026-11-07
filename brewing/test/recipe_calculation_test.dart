import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Entrées d'un cas, après application de `base`.
Map<String, Object?> _inputsOf(
  Map<String, Object?> inputs,
  Map<String, Map<String, Object?>> byId,
) {
  final base = inputs['base'] as String?;
  if (base == null) return inputs;
  return {
    ..._inputsOf(byId[base]!['inputs'] as Map<String, Object?>, byId),
    ...inputs,
  }..remove('base');
}

RecipeInput _recipe(Map<String, Object?> m) => RecipeInput(
  batchVolumeLitres: optionalNumber(m['batch_volume_l']),
  boilMinutes: optionalNumber(m['boil_time_min']),
  fermentables: objects(m['fermentables'])
      .map(
        (f) => FermentableInput(
          name: f['name'] as String,
          kind: FermentableKind.values.byName(f['kind'] as String),
          massGrams: number(f['mass_grams']),
          colorEbc: optionalNumber(f['color_ebc']),
          yieldPercent: optionalNumber(f['yield_percent']),
        ),
      )
      .toList(),
  hops: objects(m['hops'])
      .map(
        (h) => HopInput(
          name: h['name'] as String,
          massGrams: number(h['mass_grams']),
          use: HopUse.values.byName(h['use'] as String),
          form: HopForm.values.byName(h['form'] as String),
          alphaPercent: optionalNumber(h['alpha_percent']),
          minutes: optionalNumber(h['minutes']),
        ),
      )
      .toList(),
  yeasts: objects(m['yeasts'])
      .map(
        (y) => YeastInput(
          name: y['name'] as String,
          attenuationPercent: optionalNumber(y['attenuation_percent']),
        ),
      )
      .toList(),
);

RecipeCalculation _compute(Map<String, Object?> inputs) => computeRecipe(
  recipe: _recipe(inputs),
  mashEfficiencyPercent: optionalNumber(inputs['mash_efficiency_pct']),
);

/// Lignes `[[place, nom], …]` d'une fixture.
List<IngredientRef> _refs(Object? value) => [
  for (final pair
      in (value as List<Object?>? ?? const []).cast<List<Object?>>())
    IngredientRef((pair[0] as num).toInt(), pair[1] as String),
];

/// Données manquantes d'une fixture, en texte comparable.
List<String> _expectedMissing(Object? value) => [
  for (final m in objects(value))
    '${m['kind']} ${_refs(m['items']).map((r) => '${r.index}:${r.name}')}',
];

List<String> _actualMissing(List<MissingInput> missing) => [
  for (final m in missing)
    '${m.kind.name} ${m.items.map((r) => '${r.index}:${r.name}')}',
];

void _expectIndicator(
  CalculationResult actual,
  Object? expected,
  double tolerance,
  String where,
) {
  if (expected is num) {
    expect(actual, isA<CalculationComputed>(), reason: where);
    expect(
      (actual as CalculationComputed).value,
      closeTo(expected.toDouble(), tolerance),
      reason: where,
    );
    return;
  }
  final missing = (expected as Map<String, Object?>)['missing'];
  expect(actual, isA<CalculationUnavailable>(), reason: where);
  expect(
    _actualMissing((actual as CalculationUnavailable).missing),
    _expectedMissing(missing),
    reason: where,
  );
}

void main() {
  final fixture = loadFixture('recipe');
  final cases = objects(fixture['cases']);
  final byId = {for (final c in cases) c['id'] as String: c};

  test('calculs et données manquantes de chaque indicateur', () {
    for (final c in cases) {
      final result = _compute(
        _inputsOf(c['inputs'] as Map<String, Object?>, byId),
      );
      final expected = c['expected'] as Map<String, Object?>;
      final tolerance = optionalNumber(c['tolerance']) ?? 1e-9;
      final indicators = {
        'original_gravity': result.originalGravity,
        'final_gravity': result.finalGravity,
        'alcohol_by_volume': result.alcoholByVolume,
        'bitterness_ibu': result.bitternessIbu,
        'color_ebc': result.colorEbc,
      };
      for (final MapEntry(:key, :value) in indicators.entries) {
        if (!expected.containsKey(key)) continue;
        _expectIndicator(value, expected[key], tolerance, '${label(c)} / $key');
      }
      if (expected.containsKey('hop_ibu')) {
        final hopIbu = (expected['hop_ibu'] as List<Object?>).cast<num>();
        expect(result.hopBitterness.length, hopIbu.length, reason: label(c));
        for (var i = 0; i < hopIbu.length; i++) {
          expect(result.hopBitterness[i].hop.index, i, reason: label(c));
          expect(
            result.hopBitterness[i].ibu,
            closeTo(hopIbu[i].toDouble(), tolerance),
            reason: '${label(c)} / houblon $i',
          );
        }
      }
      if (expected.containsKey('boil_gravity')) {
        final boil = optionalNumber(expected['boil_gravity']);
        if (boil == null) {
          expect(result.boilGravity, isNull, reason: label(c));
        } else {
          expect(result.boilGravity, closeTo(boil, tolerance));
        }
      }
      if (expected.containsKey('hops_longer_than_boil')) {
        expect(
          result.hopsLongerThanBoil,
          _refs(expected['hops_longer_than_boil']),
          reason: label(c),
        );
      }
      if (expected.containsKey('missing_inputs')) {
        expect(
          _actualMissing(result.missingInputs),
          _expectedMissing(expected['missing_inputs']),
          reason: '${label(c)} / missing_inputs',
        );
      }
    }
  });

  test('l\'IBU totale est la somme des houblons', () {
    final result = _compute(
      byId['complete']!['inputs'] as Map<String, Object?>,
    );
    final total = result.hopBitterness.fold(0.0, (s, h) => s + h.ibu);
    expect(
      (result.bitternessIbu as CalculationComputed).value,
      closeTo(total, 1e-12),
    );
  });

  test('calculs de la recette = fonctions du paquet', () {
    final inputs = byId['complete']!['inputs'] as Map<String, Object?>;
    final result = _compute(inputs);
    final og = (result.originalGravity as CalculationComputed).value;
    expect(
      og,
      closeTo(
        predictedOriginalGravity(
          fermentables: [
            Fermentable(
              name: 'Pils',
              kind: FermentableKind.malt,
              massGrams: 5000,
              colorEbc: 3.9,
              potential: ExtractPotential.yieldPercent(80),
            ),
            Fermentable(
              name: 'Sucre candi clair',
              kind: FermentableKind.sugar,
              massGrams: 500,
              colorEbc: 2,
              potential: ExtractPotential.yieldPercent(100),
            ),
          ],
          mashEfficiencyPercent: 75,
          volumeLitres: 23,
        ),
        1e-12,
      ),
    );
    expect(
      (result.finalGravity as CalculationComputed).value,
      closeTo(
        predictedFinalGravity(originalGravity: og, attenuationPercent: 78),
        1e-12,
      ),
    );
  });

  test('calculs : entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(
        () => _compute(_inputsOf(c['inputs'] as Map<String, Object?>, byId)),
        label(c),
      );
    }
  });
}
