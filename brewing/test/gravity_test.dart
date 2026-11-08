import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('gravity');

  test('constante du saccharose', () {
    final constants = fixture['constants'] as Map<String, Object?>;
    expect(
      sucrosePointsPerKgPerLitre,
      closeTo(number(constants['sucrose_points_per_kg_per_litre']), 1e-6),
    );
  });

  test('densité initiale prévue', () {
    for (final c in objects(fixture['original_gravity'])) {
      final inputs = c['inputs'] as Map<String, Object?>;
      expectCase(
        c,
        predictedOriginalGravity(
          fermentables: fermentables(inputs['fermentables']),
          mashEfficiencyPercent: number(inputs['mash_efficiency_percent']),
          volumeLitres: number(inputs['volume_litres']),
        ),
      );
    }
  });

  test('densité initiale : entrées invalides', () {
    for (final c in objects(fixture['original_gravity_invalid'])) {
      final inputs = c['inputs'] as Map<String, Object?>;
      expectInvalid(
        () => predictedOriginalGravity(
          fermentables: fermentables(inputs['fermentables']),
          mashEfficiencyPercent: number(inputs['mash_efficiency_percent']),
          volumeLitres: number(inputs['volume_litres']),
        ),
        label(c),
      );
    }
  });

  MashEfficiencyReading readCase(Map<String, Object?> inputs) =>
      readMashEfficiency(
        measuredGravity: number(inputs['measured_gravity']),
        measuredVolumeLitres: number(inputs['measured_volume_litres']),
        fermentables: fermentables(inputs['fermentables']),
        sugarsInWort: inputs['sugars_in_wort'] as bool,
      );

  test('rendement d\'empâtage mesuré', () {
    for (final c in objects(fixture['mash_efficiency'])) {
      final result = readCase(c['inputs'] as Map<String, Object?>);
      expect(result, isA<MashEfficiencyRead>(), reason: label(c));
      expectCase(c, (result as MashEfficiencyRead).percent);
    }
  });

  test('rendement d\'empâtage : sans valeur calculable', () {
    for (final c in objects(fixture['mash_efficiency_invalid'])) {
      final inputs = c['inputs'] as Map<String, Object?>;
      switch (c['outcome']) {
        case 'without_malt':
          expect(
            readCase(inputs),
            isA<MashEfficiencyWithoutMalt>(),
            reason: label(c),
          );
        case 'sugars_explain_gravity':
          expect(
            readCase(inputs),
            isA<MashEfficiencySugarsExplainGravity>(),
            reason: label(c),
          );
        case 'throws':
          expectInvalid(() => readCase(inputs), label(c));
        default:
          fail('${label(c)} : résultat attendu inconnu');
      }
    }
  });

  test('prévision puis mesure : le rendement revient', () {
    final grist = [
      Fermentable(
        name: 'Pils',
        kind: FermentableKind.malt,
        massGrams: 5400,
        colorEbc: 3.9,
        potential: ExtractPotential.yieldPercent(81),
      ),
      Fermentable(
        name: 'Candi',
        kind: FermentableKind.sugar,
        massGrams: 460,
        colorEbc: 2,
        potential: ExtractPotential.yieldPercent(100),
      ),
    ];
    final og = predictedOriginalGravity(
      fermentables: grist,
      mashEfficiencyPercent: 68,
      volumeLitres: 19,
    );
    final measured = readMashEfficiency(
      measuredGravity: og,
      measuredVolumeLitres: 19,
      fermentables: grist,
      sugarsInWort: true,
    );
    expect((measured as MashEfficiencyRead).percent, closeTo(68, 1e-9));
  });
}
