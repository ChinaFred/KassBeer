import 'dart:convert';
import 'dart:io';

import 'package:exchange/src/schema.dart';
import 'package:test/test.dart';

/// Valeurs de [propriete] dans [definition] de [fichier], au commit figé.
Set<String> _enum(String fichier, String definition, String propriete) {
  final json =
      jsonDecode(
            File('../schemas/beerjson-4370892d44/$fichier').readAsStringSync(),
          )
          as Map<String, Object?>;
  final defs = json[r'$defs'] as Map<String, Object?>;
  final def = defs[definition] as Map<String, Object?>;
  final props = def['properties'] as Map<String, Object?>;
  final prop = props[propriete] as Map<String, Object?>;
  return {for (final v in prop['enum'] as List<Object?>) v as String};
}

void main() {
  test('valeurs énumérées : celles du schéma figé', () {
    expect(kTypesRecette, _enum('recipe.json', 'RecipeType', 'type'));
    expect(
      kTypesFermentable,
      _enum('fermentable.json', 'FermentableBase', 'type'),
    );
    expect(kFormesHoublon, _enum('hop.json', 'HopVarietyBase', 'form'));
    expect(kTypesLevure, _enum('culture.json', 'CultureBase', 'type'));
    expect(kFormesLevure, _enum('culture.json', 'CultureBase', 'form'));
    expect(kTypesAjout, _enum('misc.json', 'MiscellaneousBase', 'type'));
    expect(kTypesPalier, _enum('mash_step.json', 'MashStepType', 'type'));
    final timing =
        (jsonDecode(
                  File(
                    '../schemas/beerjson-4370892d44/timing.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>)[r'$defs']
            as Map<String, Object?>;
    final use = timing['UseType'] as Map<String, Object?>;
    expect(kUsages, {
      for (final v in use['enum'] as List<Object?>) v as String,
    });
  });

  test('version écrite : une version du schéma figé', () {
    final units =
        (jsonDecode(
                  File(
                    '../schemas/beerjson-4370892d44/measureable_units.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>)[r'$defs']
            as Map<String, Object?>;
    final version = units['VersionType'] as Map<String, Object?>;
    expect(version['enum'] as List<Object?>, contains(kVersionEcrite));
  });
}
