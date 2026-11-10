import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Correspondance des valeurs stockées des recettes (exigences-techniques.md)
/// et des enums du paquet : écrite une fois, dans les enums. Le moment d'un
/// houblon (`timing` BeerJSON) se lit dans l'application.
void main() {
  test('fermentable_additions[].type', () {
    expect(FermentableKind.fromStored('grain'), FermentableKind.malt);
    expect(FermentableKind.fromStored('sugar'), FermentableKind.sugar);
    expect(FermentableKind.malt.storedValue, 'grain');
  });

  test('hop_additions[].form', () {
    expect(HopForm.fromStored('pellet'), HopForm.pellet);
    expect(HopForm.fromStored('leaf'), HopForm.whole);
  });

  test('aller-retour de chaque valeur', () {
    for (final k in FermentableKind.values) {
      expect(FermentableKind.fromStored(k.storedValue), k);
    }
    for (final f in HopForm.values) {
      expect(HopForm.fromStored(f.storedValue), f);
    }
  });

  test('valeur inconnue ou retirée du modèle refusée', () {
    expectInvalid(() => FermentableKind.fromStored('extract'), 'extract');
    expectInvalid(() => FermentableKind.fromStored('malt'), 'nom de l\'enum');
    expectInvalid(() => HopForm.fromStored('whole'), 'nom de l\'enum');
    expectInvalid(() => HopForm.fromStored(''), 'vide');
  });

  test(
    'le champ fautif est nommé, la valeur stockée ne figure pas dans l\x27erreur',
    () {
      expect(
        () => HopForm.fromStored('plug'),
        throwsA(
          isA<BrewingInputException>()
              .having((e) => e.field, 'field', 'hop_additions[].form')
              .having((e) => e.value, 'value', 'plug'.length)
              .having((e) => e.toString(), 'toString', isNot(contains('plug'))),
        ),
      );
      expect(
        () => FermentableKind.fromStored('extract'),
        throwsA(
          isA<BrewingInputException>().having(
            (e) => e.field,
            'field',
            'fermentable_additions[].type',
          ),
        ),
      );
    },
  );
}
