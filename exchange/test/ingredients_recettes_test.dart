import 'dart:convert';
import 'dart:io';

import 'package:exchange/exchange.dart'
    show EntreeBibliotheque, IndexBibliotheque, ListeRecette;
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

  test('levures : raison aucun pour des candidats partiels ou un autre '
      'producteur, plusieurs pour une référence partagée', () {
    final index = IndexBibliotheque(ListeRecette.levures, const [
      EntreeBibliotheque(
        id: 'culture-labo-fictif-k9-un',
        nom: 'K9 Un',
        producteur: 'Labo Fictif',
        reference: 'K9',
      ),
      EntreeBibliotheque(
        id: 'culture-autre-fictif-k9-deux',
        nom: 'K9 Deux',
        producteur: 'Autre Fictif',
        reference: 'K9',
      ),
      EntreeBibliotheque(
        id: 'culture-seche-fictive-z23-lager',
        nom: 'Lager Z',
        producteur: 'Sèche Fictive',
        reference: 'Z23',
      ),
      EntreeBibliotheque(
        id: 'culture-labo-sans-ref-belle-gamme',
        nom: 'Belle Gamme',
        producteur: 'Labo Sans Ref',
      ),
      EntreeBibliotheque(
        id: 'culture-labo-sans-ref-flacon-belle-gamme',
        nom: 'Flacon Belle Gamme Douce',
        producteur: 'Labo Sans Ref',
      ),
    ]);
    // Producteur sans aucune référence, reconnu dans le nom.
    expect(index.resoudre('Labo Sans Ref Z23'), isNull);
    expect(index.resoudre('Lager Z23')?.id, 'culture-seche-fictive-z23-lager');
    final resultat = ingredientsRecettes([
      'Gamme Belle',
      'Ma levure K9',
      'Labo Sans Ref Z23',
    ], index);
    final raisons = {
      for (final n in resultat['non_resolus']! as List<Object?>)
        (n! as Map)['nom']: (n as Map)['raison'],
    };
    expect(raisons, {
      'Gamme Belle': 'aucun',
      'Ma levure K9': 'plusieurs',
      'Labo Sans Ref Z23': 'aucun',
    });
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
