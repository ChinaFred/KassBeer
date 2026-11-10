import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  final fixture = loadFixture('conversions');
  final conversions = <String, (String, double Function(double))>{
    'plato_to_sg': ('plato', platoToSg),
    'sg_to_plato': ('sg', sgToPlato),
    'srm_to_ebc': ('srm', srmToEbc),
    'ebc_to_srm': ('ebc', ebcToSrm),
    'lovibond_to_ebc': ('lovibond', lovibondToEbc),
    'ebc_to_lovibond': ('ebc', ebcToLovibond),
    'potential_to_yield': ('potential', potentialToYieldPercent),
  };

  for (final MapEntry(key: name, value: (input, convert))
      in conversions.entries) {
    test(name, () {
      final cases = objects(fixture[name]);
      expect(cases, isNotEmpty, reason: name);
      for (final c in cases) {
        expectCase(c, convert(number(c[input])));
      }
    });
  }

  test('Lovibond : aller-retour exact', () {
    for (final ebc in <double>[0, 3.9, 25, 1300]) {
      expect(lovibondToEbc(ebcToLovibond(ebc)), closeTo(ebc, 1e-9));
    }
  });

  test('Plato : aller-retour à 0,01 °P près', () {
    for (final plato in <double>[2, 8, 12, 18, 25]) {
      expect(sgToPlato(platoToSg(plato)), closeTo(plato, 0.01));
    }
  });

  test('entrées invalides', () {
    for (final c in objects(fixture['invalid'])) {
      final (_, convert) = conversions[c['conversion'] as String]!;
      expectInvalid(() => convert(number(c['value'])), label(c));
    }
    expectInvalid(() => platoToSg(double.nan), 'NaN');
    expectInvalid(() => srmToEbc(double.infinity), 'infini');
  });
}
