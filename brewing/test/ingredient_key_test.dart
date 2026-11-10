import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  test('exemples de la spécification (K1)', () {
    expect(ingredientKey(IngredientNature.malt, 'Pils'), 'malt-pils');
    expect(
      ingredientKey(IngredientNature.sugar, 'Sucre candi ambré'),
      'sucre-candi-ambre',
    );
    expect(
      ingredientKey(IngredientNature.hop, 'HAllertau'),
      'houblon-hallertau',
    );
  });

  test("lettres d'Europe centrale et du Nord sans accents (K1)", () {
    expect(ingredientKey(IngredientNature.hop, 'Žatec'), 'houblon-zatec');
    expect(
      ingredientKey(IngredientNature.hop, 'Žatec'),
      ingredientKey(IngredientNature.hop, 'Zatec'),
    );
    expect(
      ingredientKey(IngredientNature.malt, 'Słód pilzneński'),
      'malt-slod-pilznenski',
    );
    expect(ingredientKey(IngredientNature.malt, 'ŁŁ'), 'malt-ll');
    expect(ingredientKey(IngredientNature.hop, 'Ğ'), 'houblon-g');
    expect(ingredientKey(IngredientNature.malt, 'Bærsk'), 'malt-baersk');
  });

  test('un préfixe par nature', () {
    expect(ingredientKey(IngredientNature.yeast, 'US-05'), 'levure-us-05');
    expect(
      ingredientKey(IngredientNature.addition, 'Coriandre'),
      'ajout-coriandre',
    );
    expect(IngredientNature.values.map((n) => n.prefix), [
      'malt',
      'sucre',
      'houblon',
      'levure',
      'ajout',
    ]);
  });

  test('accents retirés, composés ou décomposés', () {
    expect(
      ingredientKey(IngredientNature.addition, 'Écorce d\'orange amère'),
      'ajout-ecorce-d-orange-amere',
    );
    expect(
      ingredientKey(IngredientNature.addition, 'Cœur de pêche'),
      'ajout-coeur-de-peche',
    );
    // « é » écrit « e » + accent combinant U+0301.
    expect(
      ingredientKey(IngredientNature.malt, 'Café torréfié'),
      'malt-cafe-torrefie',
    );
  });

  test('casse mêlée et ponctuation : même clé (K4)', () {
    final keys = {
      ingredientKey(IngredientNature.hop, 'Saaz'),
      ingredientKey(IngredientNature.hop, 'SAAZ'),
      ingredientKey(IngredientNature.hop, '  saaz  '),
      ingredientKey(IngredientNature.hop, '--Saaz!'),
    };
    expect(keys, {'houblon-saaz'});
  });

  test('tirets réduits, aucun en bord', () {
    expect(
      ingredientKey(IngredientNature.malt, ' Munich  (17.7 EBC) '),
      'malt-munich-17-7-ebc',
    );
  });

  test('un attribut dans le nom donne une autre clé', () {
    expect(
      ingredientKey(IngredientNature.hop, 'Saaz 2.9%'),
      isNot(ingredientKey(IngredientNature.hop, 'Saaz')),
    );
  });

  test('préfixe non répété quand le nom commence par lui', () {
    expect(
      ingredientKey(IngredientNature.malt, 'Malt Pale Ale'),
      'malt-pale-ale',
    );
    expect(ingredientKey(IngredientNature.malt, 'Malt'), 'malt');
    expect(
      ingredientKey(IngredientNature.hop, 'Houblon du jardin'),
      'houblon-du-jardin',
    );
    // « Malted » ne commence pas par le mot « malt ».
    expect(
      ingredientKey(IngredientNature.malt, 'Malted oats'),
      'malt-malted-oats',
    );
    // Le préfixe d'une autre nature reste dans le nom.
    expect(
      ingredientKey(IngredientNature.sugar, 'Malt extract'),
      'sucre-malt-extract',
    );
  });

  test('clé de 100 caractères au plus, sans tiret final (K5)', () {
    final key = ingredientKey(IngredientNature.malt, 'a' * 94 + ' bcdef');
    expect(key.length, lessThanOrEqualTo(maxIngredientKeyLength));
    expect(key, 'malt-${'a' * 94}');
    final long = ingredientKey(IngredientNature.hop, 'x' * 300);
    expect(long.length, maxIngredientKeyLength);
    expect(long, startsWith('houblon-x'));
  });

  test('nom sans lettre ni chiffre refusé (K3)', () {
    for (final name in ['', '   ', '---', '!?', '%']) {
      expectInvalid(() => ingredientKey(IngredientNature.malt, name), name);
    }
  });

  test('nature d\'un fermentescible', () {
    expect(
      IngredientNature.ofFermentable(FermentableKind.malt),
      IngredientNature.malt,
    );
    expect(
      IngredientNature.ofFermentable(FermentableKind.sugar),
      IngredientNature.sugar,
    );
    // Nature à préciser (type BeerJSON other) : clé de sucre.
    expect(IngredientNature.ofFermentable(null), IngredientNature.sugar);
  });

  test('isValidIngredientName : même règle que ingredientKey (K3)', () {
    for (final name in ['Pils', 'Žatec', '60', ' a ', 'US-05']) {
      expect(isValidIngredientName(name), isTrue, reason: name);
      expect(ingredientKey(IngredientNature.malt, name), isNotEmpty);
    }
    for (final name in ['', '   ', '---', '%!', '日本']) {
      expect(isValidIngredientName(name), isFalse, reason: name);
      expect(
        () => ingredientKey(IngredientNature.malt, name),
        throwsA(isA<BrewingInputException>()),
        reason: name,
      );
    }
  });

  test('nature lue sur le préfixe de la clé', () {
    for (final nature in IngredientNature.values) {
      for (final name in ['Pils', 'Malt', 'Sucre', 'Houblon', 'Levure']) {
        expect(
          natureOfKey(ingredientKey(nature, name)),
          nature,
          reason: '${nature.prefix} / $name',
        );
      }
    }
    expect(natureOfKey('sucre-malt'), IngredientNature.sugar);
    expect(natureOfKey('maltose'), isNull);
    expect(natureOfKey('autre-chose'), isNull);
    expect(natureOfKey(''), isNull);
  });
}
