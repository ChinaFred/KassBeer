import 'dart:convert';
import 'dart:io';

import 'package:exchange/ingestion.dart';
import 'package:test/test.dart';

/// Houblons des recettes du groupe (ADR-013, décisions 9 à 11) : noms lus,
/// résolus par IndexBibliotheque.resoudre (nom et alias), non résolus avec leur
/// raison. Fixtures écrites à la main (P20).

Object? _fixture(String nom) =>
    jsonDecode(File('test/fixtures/houblons_recettes/$nom').readAsStringSync());

void main() {
  test(
    'fixture : résolus par nom et alias, non résolus aucun et plusieurs',
    () {
      final noms = _fixture('noms-houblons.json');
      final resultat = houblonsRecettes(
        lireNomsHoublons(noms),
        indexHoublons(_fixture('beer_hops.json')),
        origine: origineNomsHoublons(noms),
      );
      expect(resultat, _fixture('attendu.json'));
    },
  );

  test("un alias résout vers le document qui le porte, sans doublon d'id", () {
    final index = indexHoublons(_fixture('beer_hops.json'));
    final r = houblonsRecettes(['Fictif Doré', 'houblon-fictif'], index);
    expect(r['resolus'], [
      {
        'id': 'hop-houblon-fictif',
        'noms': ['Fictif Doré', 'houblon-fictif'],
      },
    ]);
    expect(r['non_resolus'], isEmpty);
  });

  test('correspondances : 0, 1 ou 2', () {
    final index = indexHoublons(_fixture('beer_hops.json'));
    expect(index.correspondances('Houblon Inconnu'), 0);
    expect(index.correspondances('Saaz Fictif'), 1);
    expect(index.correspondances('Imaginaire'), 2);
    expect(index.correspondances(''), 0);
  });

  test(
    'origine : cible et date recopiées, inconnues pour une liste à la main',
    () {
      expect(
        origineNomsHoublons({
          'target': 'production',
          'generated_at': '2026-11-14T10:00:00.000Z',
          'noms': <Object?>[],
        }),
        (cible: 'production', genereLe: '2026-11-14T10:00:00.000Z'),
      );
      expect(origineNomsHoublons(['Saaz']), (cible: null, genereLe: null));
      expect(origineNomsHoublons({'target': 'autre', 'generated_at': 'hier'}), (
        cible: null,
        genereLe: null,
      ));
      final r = houblonsRecettes([
        'Saaz Fictif',
      ], indexHoublons(_fixture('beer_hops.json')));
      expect(r['target'], isNull);
      expect(r['generated_at'], isNull);
    },
  );

  test("liste de noms écrite à la main pour l'essai", () {
    expect(lireNomsHoublons(['Cascade ', 'Saaz']), ['Cascade', 'Saaz']);
  });

  test('fichier de noms mal formé : refusé', () {
    expect(
      () => lireNomsHoublons({'autre': <Object?>[]}),
      throwsFormatException,
    );
    expect(() => lireNomsHoublons([1]), throwsFormatException);
    expect(() => lireNomsHoublons(['  ']), throwsFormatException);
    expect(() => lireNomsHoublons(['x' * 121]), throwsFormatException);
    expect(
      () => lireNomsHoublons(List.filled(kMaxNomsHoublons + 1, 'a')),
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
}
