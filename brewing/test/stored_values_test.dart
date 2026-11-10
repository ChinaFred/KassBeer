import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

/// Correspondance des valeurs BeerJSON des recettes (exigences-techniques.md)
/// et des natures et formes de calcul du paquet : écrite une fois, dans les
/// enums. Le moment d'un houblon (`timing` BeerJSON) se lit dans l'application.
void main() {
  test('fermentable_additions[].type : nature de calcul', () {
    expect(FermentableKind.ofType('grain'), FermentableKind.malt);
    for (final type in ['sugar', 'extract', 'dry extract', 'honey']) {
      expect(FermentableKind.ofType(type), FermentableKind.sugar, reason: type);
    }
    expect(FermentableKind.ofType('fruit'), FermentableKind.sugar);
    expect(FermentableKind.ofType('juice'), FermentableKind.sugar);
    expect(FermentableKind.ofType('other'), isNull);
    expect(FermentableKind.ofBeerJsonType.keys, hasLength(8));
  });

  test('hop_additions[].form : forme de calcul', () {
    expect(HopForm.ofBeerJson('pellet'), HopForm.pellet);
    expect(HopForm.ofBeerJson('leaf'), HopForm.whole);
    expect(HopForm.ofBeerJson('plug'), HopForm.whole);
    for (final form in ['powder', 'extract', 'leaf (wet)']) {
      expect(HopForm.ofBeerJson(form), isNull, reason: form);
    }
    expect(HopForm.ofBeerJsonForm.keys, hasLength(6));
  });

  test('valeur écrite de chaque nature et forme : relue à l\'identique', () {
    for (final k in FermentableKind.values) {
      expect(FermentableKind.ofType(k.storedValue), k);
    }
    for (final f in HopForm.values) {
      expect(HopForm.ofBeerJson(f.storedValue), f);
    }
    expect(FermentableKind.malt.storedValue, 'grain');
    expect(HopForm.whole.storedValue, 'leaf');
  });

  test('valeur hors du schéma refusée, sans le texte dans l\'erreur', () {
    final calls = <(Object? Function(), String)>[
      (() => FermentableKind.ofType('malt'), 'fermentable_additions[].type'),
      (() => FermentableKind.ofType(''), 'fermentable_additions[].type'),
      (() => HopForm.ofBeerJson('whole'), 'hop_additions[].form'),
      (() => HopForm.ofBeerJson('cônes'), 'hop_additions[].form'),
    ];
    for (final (call, field) in calls) {
      expect(
        call,
        throwsA(
          isA<BrewingInputException>()
              .having((e) => e.field, 'field', field)
              .having((e) => e.toString(), 'texte', isNot(contains('cônes')))
              .having((e) => e.toString(), 'texte', isNot(contains('whole'))),
        ),
      );
    }
  });
}
