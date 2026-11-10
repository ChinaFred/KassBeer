import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/features/recipes/domain/beerjson.dart';

/// Valeurs de [property] dans la définition [definition] de [file], au commit
/// figé du schéma BeerJSON (ADR-005).
List<String> schemaEnum(String file, String definition, String property) {
  final json =
      jsonDecode(
            File('../schemas/beerjson-4370892d44/$file').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final defs = json[r'$defs'] as Map<String, dynamic>;
  final def = defs[definition] as Map<String, dynamic>;
  final props = def['properties'] as Map<String, dynamic>;
  final prop = props[property] as Map<String, dynamic>;
  return [for (final v in prop['enum'] as List<dynamic>) v as String];
}

void main() {
  final cases = <String, (EnumerationBeerJson, List<String>)>{
    'RecipeType.type': (
      typesRecette,
      schemaEnum('recipe.json', 'RecipeType', 'type'),
    ),
    'CultureBase.type': (
      typesLevure,
      schemaEnum('culture.json', 'CultureBase', 'type'),
    ),
    'CultureBase.form': (
      formesLevure,
      schemaEnum('culture.json', 'CultureBase', 'form'),
    ),
    'MiscellaneousBase.type': (
      typesAjout,
      schemaEnum('misc.json', 'MiscellaneousBase', 'type'),
    ),
    'MashStepType.type': (
      typesPalier,
      schemaEnum('mash_step.json', 'MashStepType', 'type'),
    ),
    'FermentableBase.type': (
      typesFermentable,
      schemaEnum('fermentable.json', 'FermentableBase', 'type'),
    ),
    'HopVarietyBase.form': (
      formesHoublon,
      schemaEnum('hop.json', 'HopVarietyBase', 'form'),
    ),
  };

  for (final MapEntry(key: name, value: (values, schema)) in cases.entries) {
    group(name, () {
      test('un libellé français pour chaque valeur du schéma figé', () {
        expect(values.libelles.keys.toSet(), schema.toSet());
        for (final v in schema) {
          expect(values.libelle(v), isNot(v), reason: v);
        }
      });

      test('valeurs proposées : toutes du schéma, sans doublon', () {
        expect(values.proposees.toSet(), hasLength(values.proposees.length));
        for (final v in values.proposees) {
          expect(values.accepte(v), isTrue, reason: v);
        }
      });
    });
  }

  test('palier : libellé long dans le menu seulement', () {
    expect(typesPalier.libelle('infusion'), 'Infusion');
    expect(
      typesPalier.libelleMenu('infusion'),
      'Infusion (eau chaude ajoutée)',
    );
    expect(typesPalier.libelleMenu('sparge'), 'Rinçage');
  });

  test(
    'malt et houblon : chaque valeur lue a sa nature ou sa forme de calcul',
    () {
      expect(
        typesFermentable.libelles.keys.toSet(),
        FermentableKind.ofBeerJsonType.keys.toSet(),
      );
      expect(
        formesHoublon.libelles.keys.toSet(),
        HopForm.ofBeerJsonForm.keys.toSet(),
      );
      expect(typesFermentable.proposees, [
        FermentableKind.malt.storedValue,
        FermentableKind.sugar.storedValue,
      ]);
      expect(formesHoublon.proposees, [
        HopForm.pellet.storedValue,
        HopForm.whole.storedValue,
      ]);
    },
  );

  test('levure : libellés des valeurs non proposées', () {
    expect(typesLevure.proposees, isNot(contains('wheat')));
    expect(typesLevure.libelle('wheat'), 'Levure de blanche');
    expect(formesLevure.proposees, ['dry', 'liquid']);
    expect(formesLevure.libelle('dregs'), 'Lie');
  });
}
