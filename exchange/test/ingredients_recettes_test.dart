import 'dart:convert';
import 'dart:io';

import 'package:exchange/exchange.dart' show IndexBibliotheque;
import 'package:exchange/ingestion.dart';
import 'package:test/test.dart';

/// Ingrédients des recettes du groupe : houblons (ADR-013, décisions 9 à 11)
/// et divers (ADR-018). Noms lus, résolus par IndexBibliotheque.resoudre (nom
/// et alias), non résolus avec leur raison. Fixtures écrites à la main (P20).

Object? _fixture(String dossier, String nom) =>
    jsonDecode(File('test/fixtures/$dossier/$nom').readAsStringSync());

Object? _houblons(String nom) => _fixture('houblons_recettes', nom);
Object? _divers(String nom) => _fixture('divers_recettes', nom);

void main() {
  group('houblons', () {
    IndexBibliotheque index() =>
        indexIngredients(NatureRecettes.houblons, _houblons('beer_hops.json'));

    test(
      'fixture : résolus par nom et alias, non résolus aucun et plusieurs',
      () {
        final noms = _houblons('noms-houblons.json');
        final resultat = ingredientsRecettes(
          NatureRecettes.houblons,
          lireNomsIngredients(noms),
          index(),
          origine: origineNoms(noms),
        );
        expect(resultat, _houblons('attendu.json'));
      },
    );

    test(
      "un alias résout vers le document qui le porte, sans doublon d'id",
      () {
        final r = ingredientsRecettes(NatureRecettes.houblons, [
          'Fictif Doré',
          'houblon-fictif',
        ], index());
        expect(r['resolus'], [
          {
            'id': 'hop-houblon-fictif',
            'noms': ['Fictif Doré', 'houblon-fictif'],
          },
        ]);
        expect(r['non_resolus'], isEmpty);
      },
    );

    test('correspondances : 0, 1 ou 2', () {
      expect(index().correspondances('Houblon Inconnu'), 0);
      expect(index().correspondances('Saaz Fictif'), 1);
      expect(index().correspondances('Imaginaire'), 2);
      expect(index().correspondances(''), 0);
    });

    test('beer_hops.json mal formé : refusé', () {
      expect(
        () => indexIngredients(NatureRecettes.houblons, {}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'beer_hops.json : liste attendue',
          ),
        ),
      );
      expect(
        () => indexIngredients(NatureRecettes.houblons, [
          {'id': 'hop-x'},
        ]),
        throwsFormatException,
      );
    });
  });

  group('divers', () {
    IndexBibliotheque index() =>
        indexIngredients(NatureRecettes.divers, _divers('beer_miscs.json'));

    test(
      'fixture : résolus par identifiant, nom et alias ; non résolus aucun et plusieurs',
      () {
        final noms = _divers('noms-divers.json');
        final resultat = ingredientsRecettes(
          NatureRecettes.divers,
          lireNomsIngredients(noms),
          index(),
          origine: origineNoms(noms),
        );
        expect(resultat, _divers('attendu.json'));
      },
    );

    test('format kassbeer_divers_recettes, lu par ingest/', () {
      final r = ingredientsRecettes(NatureRecettes.divers, [
        'Sel Fictif',
      ], index());
      expect(r['format'], 'kassbeer_divers_recettes');
      expect(r['resolus'], [
        {
          'id': 'misc-sel-fictif',
          'noms': ['Sel Fictif'],
        },
      ]);
    });

    test('correspondances : 0, 1 ou 2', () {
      expect(index().correspondances('Poudre Inconnue'), 0);
      expect(index().correspondances('Algue Fictive'), 1);
      expect(index().correspondances('Minéral'), 2);
    });

    test('beer_miscs.json mal formé : refusé', () {
      expect(
        () => indexIngredients(NatureRecettes.divers, {}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'beer_miscs.json : liste attendue',
          ),
        ),
      );
    });
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
      final r = ingredientsRecettes(
        NatureRecettes.houblons,
        ['Saaz Fictif'],
        indexIngredients(NatureRecettes.houblons, _houblons('beer_hops.json')),
      );
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
}
