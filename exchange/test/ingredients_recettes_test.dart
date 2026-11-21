import 'dart:convert';
import 'dart:io';

import 'package:exchange/ingestion.dart';
import 'package:test/test.dart';

/// Ingrédients des recettes du groupe : houblons (ADR-013, décisions 9 à 11)
/// et levures (ADR-017). Noms lus, résolus par IndexBibliotheque.resoudre, non
/// résolus avec leur raison et leurs candidats. Fixtures écrites à la main
/// (P20).

Object? _fixture(String nom) => jsonDecode(
  File('test/fixtures/ingredients_recettes/$nom').readAsStringSync(),
);

void main() {
  test(
    'fixture : résolus par nom et alias, non résolus aucun et plusieurs',
    () {
      final noms = _fixture('noms-houblons.json');
      final resultat = ingredientsRecettes(
        lireNomsIngredients(noms),
        indexHoublons(_fixture('beer_hops.json')),
        origine: origineNoms(noms),
      );
      expect(resultat, _fixture('attendu.json'));
    },
  );

  test("un alias résout vers le document qui le porte, sans doublon d'id", () {
    final index = indexHoublons(_fixture('beer_hops.json'));
    final r = ingredientsRecettes(['Fictif Doré', 'houblon-fictif'], index);
    expect(r['resolus'], [
      {
        'id': 'hop-houblon-fictif',
        'noms': ['Fictif Doré', 'houblon-fictif'],
      },
    ]);
    expect(r['non_resolus'], isEmpty);
  });

  test('candidats : aucun, un ou deux', () {
    final index = indexHoublons(_fixture('beer_hops.json'));
    expect(index.candidats('Houblon Inconnu'), isEmpty);
    expect(index.candidats('Saaz Fictif'), ['hop-saaz-fictif']);
    expect(index.candidats('Imaginaire'), [
      'hop-houblon-imaginaire',
      'hop-imaginaire-du-nord',
    ]);
    expect(index.candidats(''), isEmpty);
  });

  test(
    'origine : cible et date recopiées, inconnues pour une liste à la main',
    () {
      expect(
        origineNoms({
          'target': 'production',
          'generated_at': '2026-11-14T10:00:00.000Z',
          'noms': <Object?>[],
        }),
        (cible: 'production', genereLe: '2026-11-14T10:00:00.000Z'),
      );
      expect(origineNoms(['Saaz']), (cible: null, genereLe: null));
      expect(origineNoms({'target': 'autre', 'generated_at': 'hier'}), (
        cible: null,
        genereLe: null,
      ));
      final r = ingredientsRecettes([
        'Saaz Fictif',
      ], indexHoublons(_fixture('beer_hops.json')));
      expect(r['target'], isNull);
      expect(r['generated_at'], isNull);
    },
  );

  test("liste de noms écrite à la main pour l'essai", () {
    expect(lireNomsIngredients(['Cascade ', 'Saaz']), ['Cascade', 'Saaz']);
  });

  test('fichier de noms mal formé : refusé', () {
    expect(
      () => lireNomsIngredients({'autre': <Object?>[]}),
      throwsFormatException,
    );
    expect(() => lireNomsIngredients([1]), throwsFormatException);
    expect(() => lireNomsIngredients(['  ']), throwsFormatException);
    expect(() => lireNomsIngredients(['x' * 121]), throwsFormatException);
    expect(
      () => lireNomsIngredients(List.filled(kMaxNomsIngredients + 1, 'a')),
      throwsFormatException,
    );
  });

  test('beer_hops.json mal formé : refusé', () {
    expect(() => indexHoublons({}), throwsFormatException);
    expect(
      () => indexHoublons([
        {'id': 'hop-x'},
      ]),
      throwsFormatException,
    );
  });

  test('levures : nom, souche lue dans le nom, référence, producteur et '
      'référence ; candidats des noms non résolus', () {
    final noms = _fixture('noms-levures.json');
    final resultat = ingredientsRecettes(
      lireNomsIngredients(noms),
      indexLevures(_fixture('beer_cultures.json')),
      origine: origineNoms(noms),
    );
    expect(resultat, _fixture('attendu-levures.json'));
  });

  test("levures : deux souches d'un même producteur au même nom, aucune "
      'choisie', () {
    final index = indexLevures(_fixture('beer_cultures.json'));
    expect(index.resoudre('Belge Fictive'), isNull);
    expect(index.candidats('Belge Fictive'), [
      'culture-labo-fictif-lf2-belge-fictive',
      'culture-labo-fictif-lf3-belge-fictive',
    ]);
    expect(
      index.resoudre('Labo Fictif LF2')?.id,
      'culture-labo-fictif-lf2-belge-fictive',
    );
  });

  test('beer_cultures.json mal formé : refusé', () {
    expect(() => indexLevures({}), throwsFormatException);
    expect(
      () => indexLevures([
        {'id': 'culture-x'},
      ]),
      throwsFormatException,
    );
  });
}
