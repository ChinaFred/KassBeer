import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

/// Lit `test/fixtures/<name>.json`.
Map<String, Object?> loadFixture(String name) {
  final file = File('test/fixtures/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// Liste d'objets d'une fixture.
List<Map<String, Object?>> objects(Object? value) =>
    (value as List<Object?>).cast<Map<String, Object?>>();

/// Nombre d'une fixture.
double number(Object? value) => (value as num).toDouble();

/// Nombre facultatif d'une fixture.
double? optionalNumber(Object? value) => (value as num?)?.toDouble();

/// Libellé d'un cas, pour les messages d'échec.
String label(Map<String, Object?> c) =>
    '${c['id'] ?? c['text'] ?? c['reason'] ?? c}';

/// Vérifie [actual] contre `expected` / `tolerance`, puis contre `fiche_value`
/// / `fiche_tolerance` quand la fiche donne une valeur.
void expectCase(Map<String, Object?> c, double actual) {
  expect(
    actual,
    closeTo(number(c['expected']), number(c['tolerance'])),
    reason: label(c),
  );
  final fiche = c['fiche_value'];
  if (fiche is num) {
    expect(
      actual,
      closeTo(fiche.toDouble(), number(c['fiche_tolerance'])),
      reason: '${label(c)} : valeur de la fiche non retrouvée',
    );
  }
}

/// Fermentescible décrit dans une fixture.
Fermentable fermentable(Map<String, Object?> m) {
  final yieldPercent = optionalNumber(m['yield_percent']);
  return Fermentable(
    name: m['name'] as String,
    kind: FermentableKind.values.byName(m['kind'] as String),
    massGrams: number(m['mass_grams']),
    colorEbc: number(m['color_ebc']),
    potential: yieldPercent != null
        ? ExtractPotential.yieldPercent(yieldPercent)
        : ExtractPotential.pointsPerKgPerLitre(
            number(m['points_per_kg_per_litre']),
          ),
  );
}

/// Liste de fermentescibles d'une fixture.
List<Fermentable> fermentables(Object? value) =>
    objects(value).map(fermentable).toList();

/// Houblon décrit dans une fixture.
Hop hop(Map<String, Object?> m) => Hop(
  name: m['name'] as String,
  alphaPercent: number(m['alpha_percent']),
  massGrams: number(m['mass_grams']),
  use: HopUse.values.byName(m['use'] as String),
  form: HopForm.values.byName(m['form'] as String),
  boilMinutes: number(m['boil_minutes']),
);

/// Vérifie que [body] lève [BrewingInputException].
void expectInvalid(void Function() body, String reason) {
  expect(body, throwsA(isA<BrewingInputException>()), reason: reason);
}
