import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Correspondance des valeurs stockées des recettes (exigences-techniques.md)
/// et des enums du paquet : écrite une fois, dans les enums.
void main() {
  test('fermentables[].kind', () {
    expect(FermentableKind.fromStored('grain'), FermentableKind.malt);
    expect(FermentableKind.fromStored('sugar'), FermentableKind.sugar);
    expect(FermentableKind.malt.storedValue, 'grain');
  });

  test('hops[].use', () {
    expect(HopUse.fromStored('boil'), HopUse.boil);
    expect(HopUse.fromStored('whirlpool'), HopUse.afterBoil);
    expect(HopUse.fromStored('dry_hop'), HopUse.dryHop);
  });

  test('hops[].form', () {
    expect(HopForm.fromStored('pellet'), HopForm.pellet);
    expect(HopForm.fromStored('leaf'), HopForm.whole);
  });

  test('aller-retour de chaque valeur', () {
    for (final k in FermentableKind.values) {
      expect(FermentableKind.fromStored(k.storedValue), k);
    }
    for (final u in HopUse.values) {
      expect(HopUse.fromStored(u.storedValue), u);
    }
    for (final f in HopForm.values) {
      expect(HopForm.fromStored(f.storedValue), f);
    }
  });

  test('valeur inconnue ou retirée du modèle refusée', () {
    expectInvalid(() => FermentableKind.fromStored('extract'), 'extract');
    expectInvalid(() => FermentableKind.fromStored('malt'), 'nom de l\'enum');
    expectInvalid(() => HopUse.fromStored('first_wort'), 'first_wort');
    expectInvalid(() => HopUse.fromStored('afterBoil'), 'nom de l\'enum');
    expectInvalid(() => HopForm.fromStored('whole'), 'nom de l\'enum');
    expectInvalid(() => HopForm.fromStored(''), 'vide');
  });

  test(
    'le champ fautif est nommé, la valeur stockée ne figure pas dans l\x27erreur',
    () {
      expect(
        () => HopUse.fromStored('first_wort'),
        throwsA(
          isA<BrewingInputException>()
              .having((e) => e.field, 'field', 'hops.use')
              .having((e) => e.value, 'value', 'first_wort'.length)
              .having(
                (e) => e.toString(),
                'toString',
                isNot(contains('first_wort')),
              ),
        ),
      );
    },
  );
}
