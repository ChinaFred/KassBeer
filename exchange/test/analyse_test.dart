import 'dart:convert';

import 'package:exchange/exchange.dart';
import 'package:test/test.dart';

import 'support/description.dart';

List<int> _json(Object? value) => utf8.encode(jsonEncode(value));

Map<String, Object?> _recette(String nom) => {
  'name': nom,
  'ingredients': {'fermentable_additions': <Object?>[]},
};

Map<String, Object?> _fichier(
  List<Object?> recettes, {
  Object? version = 2.01,
}) => {
  'beerjson': {'version': version, 'recipes': recettes},
};

String _empreinte(Object? recette) => lireEmpreinte(recette).empreinte;

RaisonFichier? _refus(List<int> octets) => switch (analyserFichier(octets)) {
  FichierRefuse(:final raison) => raison,
  FichierLu() => null,
};

void main() {
  group('taille', () {
    test('plus de 10 Mo : refusé avant toute lecture, taille rendue', () {
      final octets = List<int>.filled(kMaxOctetsParFichier + 1, 0x20);
      final analyse = analyserFichier(octets) as FichierRefuse;
      expect(analyse.raison, RaisonFichier.tropGros);
      expect(analyse.taille, kMaxOctetsParFichier + 1);
    });

    test('10 Mo tout juste : lu', () {
      final debut = _json(_fichier([_recette('A')]));
      final octets = [
        ...debut,
        ...List<int>.filled(kMaxOctetsParFichier - debut.length, 0x20),
      ];
      expect(analyserFichier(octets), isA<FichierLu>());
    });
  });

  group('format détecté par le contenu', () {
    test('BeerJSON avec BOM UTF-8 et espaces de tête', () {
      final octets = [
        0xEF,
        0xBB,
        0xBF,
        0x0A,
        ..._json(_fichier([_recette('A')])),
      ];
      final lu = analyserFichier(octets) as FichierLu;
      expect(lu.format, FormatFichier.beerJson);
      expect(lu.recettes.single.nom, 'A');
    });

    test('fichier vide ou blanc : illisible', () {
      expect(_refus(const []), RaisonFichier.illisible);
      expect(_refus(utf8.encode('  \n')), RaisonFichier.illisible);
    });

    test('texte quelconque : illisible', () {
      expect(_refus(utf8.encode('Recette : IPA')), RaisonFichier.illisible);
    });

    test('JSON qui n\'est pas du BeerJSON', () {
      expect(
        _refus(_json({'recipes': <Object?>[]})),
        RaisonFichier.jsonNonBeerJson,
      );
      expect(_refus(_json([1, 2])), RaisonFichier.jsonNonBeerJson);
      expect(_refus(_json({'beerjson': 'x'})), RaisonFichier.jsonNonBeerJson);
    });

    test(
      'BeerXML reconnu sur son premier élément, déclaration et commentaire compris',
      () {
        for (final xml in [
          '<?xml version="1.0" encoding="ISO-8859-1"?>\n<!-- x -->\n<RECIPES><RECIPE>',
          '<RECIPE><NAME>A</NAME></RECIPE>',
        ]) {
          expect(
            _refus(latin1.encode(xml)),
            RaisonFichier.beerXml,
            reason: xml,
          );
        }
      },
    );

    test('BeerSmith (.bsmx) reconnu', () {
      expect(
        _refus(
          utf8.encode('<Recipe><_PERMID_>0</_PERMID_><F_R_NAME>A</F_R_NAME>'),
        ),
        RaisonFichier.bsmx,
      );
      expect(_refus(utf8.encode('<Selections><Data>')), RaisonFichier.bsmx);
    });

    test('autre XML : illisible', () {
      expect(_refus(utf8.encode('<html><body>')), RaisonFichier.illisible);
    });

    test(
      'JSON mal formé et UTF-8 invalide : FormatException, rapportée par l\'appelant',
      () {
        expect(
          () => analyserFichier(utf8.encode('{"beerjson": ')),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => analyserFichier([0x7B, 0x22, 0xC3, 0x28, 0x22, 0x7D]),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('version', () {
    for (final v in [1.0, 1, 2.01, 2.06, 3, '2.01']) {
      test('$v : lue', () {
        expect(
          analyserFichier(_json(_fichier([_recette('A')], version: v))),
          isA<FichierLu>(),
        );
      });
    }

    for (final (v, affichee) in [
      (4, '4'),
      (0.9, '0.9'),
      ('abc', 'abc'),
      (null, null),
    ]) {
      test('$v : non prise en charge', () {
        final r =
            analyserFichier(_json(_fichier([_recette('A')], version: v)))
                as FichierRefuse;
        expect(r.raison, RaisonFichier.versionInconnue);
        expect(r.version, affichee);
      });
    }
  });

  group('recettes', () {
    test('aucune recette', () {
      expect(
        _refus(
          _json({
            'beerjson': {'version': 2.01},
          }),
        ),
        RaisonFichier.aucuneRecette,
      );
      expect(_refus(_json(_fichier([]))), RaisonFichier.aucuneRecette);
    });

    test('plus de 500 : les 500 premières, total gardé', () {
      final recettes = [for (var i = 0; i < 501; i++) _recette('R$i')];
      final lu = analyserFichier(_json(_fichier(recettes))) as FichierLu;
      expect(lu.recettes, hasLength(kMaxRecettesParFichier));
      expect(lu.total, 501);
      expect(lu.tronque, isTrue);
      expect(lu.recettes.last.nom, 'R499');
    });

    test('même contenu deux fois : la seconde en double, même empreinte', () {
      final lu =
          analyserFichier(
                _json(_fichier([_recette('A'), _recette('B'), _recette('A')])),
              )
              as FichierLu;
      expect([for (final r in lu.recettes) r.enDouble], [false, false, true]);
      expect(lu.recettes[0].empreinte, lu.recettes[2].empreinte);
      expect(lu.recettes[0].empreinte, isNot(lu.recettes[1].empreinte));
      expect(
        lu.recettes[0].empreinte,
        matches(RegExp(r'^sha256:[0-9a-f]{64}$')),
      );
    });

    test('recette qui n\'est pas un objet : refusée, illisible', () {
      final lu = analyserFichier(_json(_fichier(['texte']))) as FichierLu;
      final r = lu.recettes.single.resultat as RecetteRefusee;
      expect(decrire(r.refus), 'RecetteIllisible');
    });
  });

  group('empreinte', () {
    test(
      'indépendante de l\'ordre des clés et de l\'écriture d\'un entier',
      () {
        expect(
          _empreinte({
            'a': 20,
            'b': [1.5, 'x'],
          }),
          _empreinte({
            'b': [1.5, 'x'],
            'a': 20.0,
          }),
        );
        expect(_empreinte({'a': 20}), isNot(_empreinte({'a': 21})));
      },
    );

    test('imported_from : format et empreinte, 200 caractères au plus', () {
      final e = _empreinte({'name': 'A'});
      final valeur = importedFrom(FormatFichier.beerJson, e);
      expect(valeur, 'BeerJSON · $e');
      expect(valeur.length, lessThanOrEqualTo(200));
      expect(estImporteeDe(valeur, e), isTrue);
      expect(estImporteeDe('fiche.xlsx', e), isFalse);
      expect(estImporteeDe(null, e), isFalse);
    });
  });

  String niveaux(int n) => '${'[' * n}${']' * n}';
  List<int> fichierAvec(String x) => utf8.encode(
    '{"beerjson": {"version": 2.01, "recipes": [{"name": "A", "x": $x}]}}',
  );

  group('revue de sécurité de la v0.1.19 : profondeur', () {
    test('1 000 000 de niveaux dans recipes : refusé avant jsonDecode', () {
      final texte =
          '{"beerjson": {"version": 2.01, "recipes": ${niveaux(1000000)}}}';
      expect(_refus(utf8.encode(texte)), RaisonFichier.illisible);
    });

    test('un crochet dans une chaîne ne compte pas', () {
      final lu =
          analyserFichier(fichierAvec('"${'[' * 100}\\"${'{' * 100}"'))
              as FichierLu;
      expect(lu.recettes.single.resultat, isA<RecetteLue>());
    });

    test('limite du fichier : 36 niveaux lus, 37 refusés', () {
      // La racine, beerjson, recipes et la recette font 4 niveaux.
      expect(
        analyserFichier(fichierAvec(niveaux(kMaxProfondeurFichier - 4))),
        isA<FichierLu>(),
      );
      expect(
        _refus(fichierAvec(niveaux(kMaxProfondeurFichier - 3))),
        RaisonFichier.illisible,
      );
    });

    test(
      '3 : version imbriquée ou très longue : non prise en charge, non affichée',
      () {
        for (final version in [
          niveaux(30),
          '[${List.filled(10000, '1').join(',')}]',
          '"${'9' * 10000}"',
        ]) {
          final texte =
              '{"beerjson": {"version": $version, "recipes": [{"name": "A"}]}}';
          final r = analyserFichier(utf8.encode(texte)) as FichierRefuse;
          expect(r.raison, RaisonFichier.versionInconnue);
          expect(r.version, isNull);
        }
        // Sur 10 000 niveaux, la borne de profondeur refuse le fichier avant.
        final profond =
            '{"beerjson": {"version": ${niveaux(10000)}, "recipes": []}}';
        expect(_refus(utf8.encode(profond)), RaisonFichier.illisible);
      },
    );
  });

  group('revue de sécurité de la v0.1.19 : en-tête XML', () {
    test(
      '4 096 octets de déclarations puis <1 : illisible en moins de 100 ms',
      () {
        for (final motif in ['<?a?>', '<!--a-->']) {
          final tete = motif * (4096 ~/ motif.length);
          final chrono = Stopwatch()..start();
          expect(_refus(utf8.encode('$tete<1')), RaisonFichier.illisible);
          chrono.stop();
          expect(chrono.elapsedMilliseconds, lessThan(100), reason: motif);
        }
      },
    );

    test('déclaration ou commentaire non fermés : illisible', () {
      expect(
        _refus(utf8.encode('<?xml ${'?' * 4000}')),
        RaisonFichier.illisible,
      );
      expect(
        _refus(utf8.encode('<!-- ${'-' * 4000}')),
        RaisonFichier.illisible,
      );
    });

    test('RECIPES reconnu après un en-tête et un commentaire', () {
      expect(
        _refus(
          utf8.encode(
            '<?xml version="1.0"?>\n<!-- exporté -->\n<!DOCTYPE x>\n<RECIPES>',
          ),
        ),
        RaisonFichier.beerXml,
      );
    });
  });

  test('2 : 32 niveaux lus, 33 refusés', () {
    String niveaux(int n) => '${'[' * n}${']' * n}';
    // La recette elle-même est le premier niveau.
    Object? recette(int n) =>
        jsonDecode('{"name": "A", "ingredients": {}, "x": ${niveaux(n)}}');
    expect(lireEmpreinte(recette(31)).tropProfond, isFalse);
    expect(lireEmpreinte(recette(32)).tropProfond, isTrue);
  });
}
