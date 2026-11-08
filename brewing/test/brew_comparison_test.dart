import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('brew_comparison');
  final grists = fixture['grists'] as Map<String, Object?>;
  final plannedFull = fixture['planned_complet'] as Map<String, Object?>;

  FermentableInput input(Map<String, Object?> m) {
    final points = optionalNumber(m['points_per_kg_per_litre']);
    return FermentableInput(
      name: m['name'] as String,
      kind: FermentableKind.values.byName(m['kind'] as String),
      massGrams: number(m['mass_grams']),
      yieldPercent: points == null
          ? optionalNumber(m['yield_percent'])
          : points / sucrosePointsPerKgPerLitre * 100,
    );
  }

  List<FermentableInput> grist(Object? name) =>
      objects(grists[name]).map(input).toList();

  BrewMeasurements measuredOf(Map<String, Object?> m) => BrewMeasurements(
    originalGravity: optionalNumber(m['original_gravity']),
    finalGravity: optionalNumber(m['final_gravity']),
    fermenterVolumeLitres: optionalNumber(m['fermenter_volume_litres']),
    sugarsInWort: m['sugars_in_wort'] as bool?,
  );

  PlannedBrewValues plannedOf(Object? name) {
    if (name == null) return const PlannedBrewValues();
    return PlannedBrewValues(
      originalGravity: number(plannedFull['original_gravity']),
      finalGravity: number(plannedFull['final_gravity']),
      alcoholByVolume: number(plannedFull['alcohol_by_volume']),
      fermenterVolumeLitres: number(plannedFull['fermenter_volume_litres']),
      mashEfficiencyPercent: number(plannedFull['mash_efficiency_percent']),
    );
  }

  void expectLine(
    String id,
    String name,
    ComparisonLine line,
    Map<String, Object?> expected,
  ) {
    final reason = '$id / $name';
    final planned = expected['planned'];
    if (planned == null) {
      expect(line.planned, isNull, reason: reason);
    } else {
      expect(line.planned, closeTo(number(planned), 1e-9), reason: reason);
    }
    final difference = expected['difference'];
    if (difference == null) {
      expect(line.difference, isNull, reason: reason);
    } else {
      expect(
        line.difference,
        closeTo(number(difference), 1e-5),
        reason: reason,
      );
    }
    final measured = expected['measured'];
    final result = line.measured;
    switch (measured) {
      case num():
        expect(result, isA<MeasuredComputed>(), reason: reason);
        expect(
          (result as MeasuredComputed).value,
          closeTo(measured.toDouble(), 1e-5),
          reason: reason,
        );
      case Map<String, Object?>():
        if (measured['impossible'] case final String kind) {
          expect(result, isA<MeasuredImpossible>(), reason: reason);
          expect(
            (result as MeasuredImpossible).kind.name,
            kind,
            reason: reason,
          );
        } else {
          expect(result, isA<MeasuredUnavailable>(), reason: reason);
          final gaps = (result as MeasuredUnavailable).gaps;
          expect(
            gaps.map((g) => g.kind.name).toList(),
            measured['unavailable'],
            reason: reason,
          );
          expect(
            gaps.expand((g) => g.items).map((i) => i.name).toList(),
            measured['items'] ?? const <String>[],
            reason: reason,
          );
        }
      default:
        fail('$reason : attente illisible');
    }
  }

  test('comparaison prévu / mesuré', () {
    for (final c in objects(fixture['cases'])) {
      final comparison = compareBrewWithPlan(
        planned: plannedOf(c['planned']),
        measured: measuredOf(c['measured'] as Map<String, Object?>),
        fermentables: grist(c['grist']),
      );
      final expected = c['expected'] as Map<String, Object?>;
      final lines = {
        'original_gravity': comparison.originalGravity,
        'final_gravity': comparison.finalGravity,
        'alcohol_by_volume': comparison.alcoholByVolume,
        'fermenter_volume': comparison.fermenterVolume,
        'mash_efficiency': comparison.mashEfficiency,
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        expectLine(
          '${c['id']}',
          key,
          lines[key]!,
          value as Map<String, Object?>,
        );
      }
    }
  });

  test('comparaison : valeurs enregistrées hors bornes', () {
    for (final c in objects(fixture['invalid'])) {
      expectInvalid(
        () => compareBrewWithPlan(
          planned: const PlannedBrewValues(),
          measured: measuredOf(c['measured'] as Map<String, Object?>),
          fermentables: grist('ale_blonde_140724'),
        ),
        label(c),
      );
    }
  });

  test('rendement sans exception : une valeur lue', () {
    final grains = [
      Fermentable(
        name: 'Pils',
        kind: FermentableKind.malt,
        massGrams: 5000,
        colorEbc: 3.9,
        potential: ExtractPotential.yieldPercent(80),
      ),
    ];
    final read = readMashEfficiency(
      measuredGravity: 1.05,
      measuredVolumeLitres: 20,
      fermentables: grains,
      sugarsInWort: false,
    );
    expect(read, isA<MashEfficiencyRead>());
  });
}
