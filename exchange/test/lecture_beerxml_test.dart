import 'dart:convert';

import 'package:exchange/exchange.dart';
import 'package:exchange/src/decodage_xml.dart';
import 'package:test/test.dart';

import 'support/decrire.dart';

/// Lecture du BeerXML 1.0 (L2c d'ADR-005) : encodages, entités, bornes de P9,
/// correspondances de `DATA_SOURCES.md`. Aucun fichier n'est lu : la suite
/// tourne aussi dans un navigateur (`dart test -p chrome`).

/// Fichier BeerXML d'une recette dont [corps] est le contenu de `RECIPE`.
String _fichier(String corps, {String entete = ''}) =>
    '$entete<RECIPES><RECIPE>$corps</RECIPE></RECIPES>';

const _hop =
    '<HOP><NAME>Cascade</NAME><ALPHA>7</ALPHA><AMOUNT>0.02</AMOUNT>'
    '<USE>Boil</USE><TIME>60</TIME><FORM>Pellet</FORM></HOP>';

/// Recette minimale lisible : un nom et un houblon.
String _recette({String nom = 'Essai', String plus = ''}) =>
    _fichier('<NAME>$nom</NAME><HOPS>$_hop</HOPS>$plus');

AnalyseFichier _analyser(String texte) => analyserFichier(utf8.encode(texte));

RaisonFichier? _refus(List<int> octets) => switch (analyserFichier(octets)) {
  FichierRefuse(:final raison) => raison,
  FichierLu() => null,
};

RecetteLue _lue(String texte) {
  final lu = _analyser(texte) as FichierLu;
  return lu.recettes.single.resultat as RecetteLue;
}

List<String> _modifs(String texte) => [
  for (final m in _lue(texte).modifications) decrire(m),
];

String _refusRecette(String texte) {
  final lu = _analyser(texte) as FichierLu;
  return decrire((lu.recettes.single.resultat as RecetteRefusee).refus);
}

Map<String, Object?> _ligne(String texte, String liste, [int i = 0]) {
  final ingredients = _lue(texte).recipe['ingredients']! as Map;
  return (ingredients[liste]! as List)[i] as Map<String, Object?>;
}

Object? _timing(String hop) => _ligne(
  _fichier(
    '<NAME>R</NAME><BOIL_TIME>70</BOIL_TIME>'
    '<HOPS>$hop</HOPS>',
  ),
  'hop_additions',
)['timing'];

String _houblon(String use, {String time = ''}) =>
    '<HOP><NAME>Saaz</NAME><ALPHA>3.5</ALPHA><AMOUNT>0.03</AMOUNT>'
    '<USE>$use</USE>$time<FORM>Leaf</FORM></HOP>';

void main() {
  group('encodage', () {
    test('sans déclaration : UTF-8', () {
      final lu = _analyser(_recette(nom: 'Bière d’été')) as FichierLu;
      expect(lu.format, FormatFichier.beerXml);
      expect(lu.recettes.single.nom, 'Bière d’été');
    });

    test('ISO-8859-1 déclaré : é lu, 0x92 lu comme ’ (BeerSmith)', () {
      final octets = [
        ...latin1.encode(
          '<?xml version="1.0" encoding="ISO-8859-1"?>'
          '<RECIPES><RECIPE><NAME>Ambr',
        ),
        0xE9, 0x65, 0x20, 0x64, 0x92, 0x61, // « ée d’a »
        ...latin1.encode('</NAME><HOPS>$_hop</HOPS></RECIPE></RECIPES>'),
      ];
      final lu = analyserFichier(octets) as FichierLu;
      expect(lu.recettes.single.nom, 'Ambrée d’a');
    });

    test('windows-1252 déclaré : 0x80 lu comme €, 0x9C comme œ', () {
      final octets = [
        ...latin1.encode(
          "<?xml version='1.0' encoding='windows-1252'?>"
          '<RECIPE><NAME>',
        ),
        0x80,
        0x20,
        0x9C,
        ...latin1.encode('uf</NAME><HOPS>$_hop</HOPS></RECIPE>'),
      ];
      final lu = analyserFichier(octets) as FichierLu;
      expect(lu.recettes.single.nom, '€ œuf');
    });

    test('UTF-8 déclaré mais octets invalides : FormatException', () {
      final octets = [
        ...latin1.encode(
          '<?xml version="1.0" encoding="UTF-8"?><RECIPE><NAME>',
        ),
        0xE9,
        ...latin1.encode('</NAME></RECIPE>'),
      ];
      expect(() => analyserFichier(octets), throwsA(isA<FormatException>()));
    });

    test('autre encodage déclaré, ou déclaration illisible : illisible', () {
      for (final entete in [
        '<?xml version="1.0" encoding="UTF-16"?>',
        '<?xml version="1.0" encoding="ISO-8859-15"?>',
        '<?xml version="1.0" encoding=UTF-8?>',
        '<?xml version="1.0" encoding="${'x' * 60}"?>',
      ]) {
        expect(
          _refus(
            utf8.encode(
              _recette().replaceFirst('<RECIPES>', '$entete<RECIPES>'),
            ),
          ),
          RaisonFichier.illisible,
          reason: entete,
        );
      }
    });

    test('encodeDeclare : nom en minuscules, null sans déclaration', () {
      expect(
        encodageDeclare('<?xml version="1.0" encoding = "Latin1" ?><a/>'),
        'latin1',
      );
      expect(encodageDeclare('<?xml version="1.0"?><a/>'), isNull);
      expect(encodageDeclare('<RECIPES>'), isNull);
    });
  });

  group('entités (P9) : aucune entité étendue', () {
    test('entités prédéfinies, numériques et CDATA : lues', () {
      final lu = _lue(
        _fichier(
          '<NAME>A &amp; B &lt;C&gt; &quot;D&quot; &apos;E&apos; &#233;&#xE8;</NAME>'
          '<NOTES><![CDATA[<b>&amp;</b>]]></NOTES><HOPS>$_hop</HOPS>',
        ),
      );
      expect(lu.recipe['name'], 'A & B <C> "D" \'E\' éè');
      expect(lu.recipe['notes'], '<b>&amp;</b>');
    });

    test('« billion laughs » : refusée en moins de 100 ms', () {
      final entites = StringBuffer('<!ENTITY lol "lol">');
      for (var i = 1; i <= 9; i++) {
        entites.write(
          '<!ENTITY lol$i "${'&lol${i == 1 ? '' : i - 1};' * 10}">',
        );
      }
      final texte =
          '<?xml version="1.0"?>\n<!DOCTYPE RECIPES [$entites]>\n'
          '<RECIPES><RECIPE><NAME>&lol9;</NAME></RECIPE></RECIPES>';
      final chrono = Stopwatch()..start();
      expect(_refus(utf8.encode(texte)), RaisonFichier.illisible);
      expect(chrono.elapsedMilliseconds, lessThan(100));
    });

    test('entité externe déclarée : refusée, rien n\'est lu', () {
      const texte =
          '<?xml version="1.0"?>\n'
          '<!DOCTYPE RECIPES SYSTEM "file:///etc/passwd">\n'
          '<RECIPES><RECIPE><NAME>&xxe;</NAME></RECIPE></RECIPES>';
      expect(_refus(utf8.encode(texte)), RaisonFichier.illisible);
      const interne =
          '<!DOCTYPE RECIPES [<!ENTITY xxe SYSTEM "https://exemple.fr/x">]>'
          '<RECIPES><RECIPE><NAME>&xxe;</NAME></RECIPE></RECIPES>';
      expect(_refus(utf8.encode(interne)), RaisonFichier.illisible);
    });

    test(
      'entité inconnue sans DOCTYPE, & seul, référence interdite : refusés',
      () {
        for (final nom in [
          '&xxe;',
          '&nbsp;',
          'Fish & Chips',
          '&#0;',
          '&#xD800;',
          '&#x;',
        ]) {
          expect(
            _refus(utf8.encode(_recette(nom: nom))),
            RaisonFichier.illisible,
            reason: nom,
          );
        }
      },
    );
  });

  group('revue de sécurité de la v0.1.21 : texte en morceaux', () {
    test('notes coupées par 1 300 000 commentaires : lues en moins de 5 s', () {
      final texte =
          '<RECIPES><RECIPE><NAME>A</NAME><NOTES>${'a<!---->' * 1300000}'
          '</NOTES></RECIPE></RECIPES>';
      final octets = utf8.encode(texte);
      expect(octets.length, lessThanOrEqualTo(kMaxOctetsParFichier));
      final chrono = Stopwatch()..start();
      final lu = analyserFichier(octets) as FichierLu;
      expect(chrono.elapsed, lessThan(const Duration(seconds: 5)));
      final lue = lu.recettes.single.resultat as RecetteLue;
      expect([
        for (final m in lue.modifications) decrire(m),
      ], contains('TexteCoupe(notes, 10000)'));
    });

    test(
      '800 000 sections CDATA (10 Mo) sous RECIPES : lues en moins de 5 s',
      () {
        final texte =
            '<RECIPES>${'<![CDATA[a]]>' * 800000}'
            '<RECIPE><NAME>A</NAME></RECIPE></RECIPES>';
        final octets = utf8.encode(texte);
        expect(octets.length, lessThanOrEqualTo(kMaxOctetsParFichier));
        final chrono = Stopwatch()..start();
        final lu = analyserFichier(octets) as FichierLu;
        expect(chrono.elapsed, lessThan(const Duration(seconds: 5)));
        expect(lu.recettes.single.resultat, isA<RecetteLue>());
      },
    );
  });

  group('revue de sécurité de la v0.1.21 : éléments gardés', () {
    test('10 Mo de <X/> dans une recette : illisible, arbre borné', () {
      final debut = '<RECIPES><RECIPE><NAME>A</NAME>';
      const fin = '</RECIPE></RECIPES>';
      final n = (kMaxOctetsParFichier - debut.length - fin.length) ~/ 4;
      final octets = utf8.encode('$debut${'<X/>' * n}$fin');
      expect(octets.length, lessThanOrEqualTo(kMaxOctetsParFichier));
      expect(n, greaterThan(kMaxElementsXml));
      expect(_refus(octets), RaisonFichier.illisible);
    });

    test('enfants de RECIPES autres que RECIPE : ni gardés, ni comptés', () {
      final lu =
          _analyser(
                '<RECIPES>${'<EQUIPMENT/>' * (kMaxElementsXml + 1)}'
                '<RECIPE><NAME>A</NAME><HOPS>$_hop</HOPS></RECIPE></RECIPES>',
              )
              as FichierLu;
      expect(lu.recettes.single.resultat, isA<RecetteLue>());
    });

    test(
      'élément inconnu : ses enfants ne sont pas gardés, il compte pour un',
      () {
        final lu = _lue(
          _recette(plus: '<JUNK>${'<X>1</X>' * (kMaxElementsXml + 1)}</JUNK>'),
        );
        expect(
          [for (final m in lu.modifications) decrire(m)],
          ['ChampsInconnus(1)'],
        );
      },
    );

    test('500 recettes de 50 houblons, champs d\'affichage compris : lues', () {
      const hop =
          '<HOP><NAME>Cascade</NAME><VERSION>1</VERSION><ALPHA>7</ALPHA>'
          '<AMOUNT>0.02</AMOUNT><USE>Boil</USE><TIME>60</TIME>'
          '<TYPE>Both</TYPE><FORM>Pellet</FORM>'
          '<DISPLAY_AMOUNT>0.7 oz</DISPLAY_AMOUNT></HOP>';
      final recette =
          '<RECIPE><NAME>R</NAME><VERSION>1</VERSION><TYPE>All Grain</TYPE>'
          '<BREWER>B</BREWER><BATCH_SIZE>20</BATCH_SIZE>'
          '<BOIL_TIME>60</BOIL_TIME><HOPS>${hop * 50}</HOPS></RECIPE>';
      final octets = utf8.encode(
        '<RECIPES>${List.filled(500, recette).join()}</RECIPES>',
      );
      expect(octets.length, lessThan(kMaxOctetsParFichier));
      final lu = analyserFichier(octets) as FichierLu;
      expect(lu.recettes, hasLength(500));
      expect(lu.recettes.first.resultat, isA<RecetteLue>());
    });
  });

  group('structure et bornes (P9)', () {
    test('XML mal formé ou deux racines : FormatException', () {
      for (final texte in [
        '<RECIPES><RECIPE><NAME>A</NAME></RECIPES>',
        '<RECIPES><RECIPE><NAME>A</NAME></RECIPE>',
        '<RECIPE><NAME>A</NAME></RECIPE><RECIPE><NAME>B</NAME></RECIPE>',
      ]) {
        expect(
          () => _analyser(texte),
          throwsA(isA<FormatException>()),
          reason: texte,
        );
      }
    });

    test('16 niveaux lus, 17 refusés', () {
      String imbrique(int n) => '${'<X>' * n}${'</X>' * n}';
      // RECIPES et RECIPE font les deux premiers niveaux.
      final lu = _analyser(_recette(plus: imbrique(kMaxProfondeurXml - 2)));
      expect(lu, isA<FichierLu>());
      expect(
        _refus(utf8.encode(_recette(plus: imbrique(kMaxProfondeurXml - 1)))),
        RaisonFichier.illisible,
      );
    });

    test('1 000 000 de niveaux : refusé sans dépassement de pile', () {
      final texte = '<RECIPES>${'<X>' * 1000000}${'</X>' * 1000000}</RECIPES>';
      expect(_refus(utf8.encode(texte)), RaisonFichier.illisible);
    });

    test('plus de 500 recettes : les 500 premières, total gardé', () {
      final recettes = [
        for (var i = 0; i < 502; i++)
          '<RECIPE><NAME>R$i</NAME><HOPS>$_hop</HOPS></RECIPE>',
      ];
      final lu =
          _analyser('<RECIPES>${recettes.join()}</RECIPES>') as FichierLu;
      expect(lu.recettes, hasLength(kMaxRecettesParFichier));
      expect(lu.total, 502);
      expect(lu.tronque, isTrue);
      expect(lu.recettes.last.nom, 'R499');
    });

    test('aucune recette : RECIPES vide, bibliothèque d\'ingrédients', () {
      for (final texte in [
        '<RECIPES></RECIPES>',
        '<RECIPES><EQUIPMENT><NAME>E</NAME></EQUIPMENT></RECIPES>',
        '<HOPS>$_hop</HOPS>',
        '<?xml version="1.0"?><STYLES><STYLE><NAME>S</NAME></STYLE></STYLES>',
      ]) {
        expect(
          _refus(utf8.encode(texte)),
          RaisonFichier.aucuneRecette,
          reason: texte,
        );
      }
    });

    test('noms d\'éléments en minuscules : lus', () {
      final lu =
          _analyser(
                '<recipes><recipe><name>Basse</name><hops>${_hop.toLowerCase()}'
                '</hops></recipe></recipes>',
              )
              as FichierLu;
      expect(lu.recettes.single.resultat, isA<RecetteLue>());
    });

    test('formatPresume : xml, json, inconnu, sans rien du contenu', () {
      expect(formatPresume(utf8.encode('  <RECIPES>')), 'xml');
      expect(formatPresume([0xEF, 0xBB, 0xBF, 0x7B]), 'json');
      expect(formatPresume(utf8.encode('Recette')), 'inconnu');
      expect(formatPresume(const []), 'inconnu');
    });
  });

  group('empreinte et doublons', () {
    test(
      'indentation sans effet ; contenu différent, empreinte différente',
      () {
        final a = _analyser(_recette()) as FichierLu;
        final b =
            _analyser(
                  '<RECIPES>\n  <RECIPE>\n    <NAME> Essai </NAME>\n    <HOPS>'
                  '$_hop</HOPS>\n  </RECIPE>\n</RECIPES>\n',
                )
                as FichierLu;
        final c = _analyser(_recette(nom: 'Autre')) as FichierLu;
        expect(a.recettes.single.empreinte, b.recettes.single.empreinte);
        expect(a.recettes.single.empreinte, isNot(c.recettes.single.empreinte));
      },
    );

    test('même recette deux fois : la seconde en double', () {
      final r = '<RECIPE><NAME>A</NAME><HOPS>$_hop</HOPS></RECIPE>';
      final lu = _analyser('<RECIPES>$r$r</RECIPES>') as FichierLu;
      expect([for (final x in lu.recettes) x.enDouble], [false, true]);
    });

    test('imported_from : « BeerXML · sha256:… », 200 caractères au plus', () {
      final lu = _analyser(_recette()) as FichierLu;
      final e = lu.recettes.single.empreinte;
      expect(e, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
      final valeur = importedFrom(lu.format, e);
      expect(valeur, 'BeerXML · $e');
      expect(valeur.length, lessThanOrEqualTo(200));
      expect(estImporteeDe(valeur, e), isTrue);
    });
  });

  group('recette', () {
    test('nom absent : refusée', () {
      expect(_refusRecette(_fichier('<HOPS>$_hop</HOPS>')), 'NomAbsent');
    });

    test('type de recette : sans casse ; inconnu, écarté et listé', () {
      expect(
        _lue(_recette(plus: '<TYPE>all grain</TYPE>')).recipe['type'],
        'all grain',
      );
      final lue = _lue(_recette(plus: '<TYPE>Kit</TYPE>'));
      expect(lue.recipe['type'], isNull);
      expect([
        for (final m in lue.modifications) decrire(m),
      ], contains('ValeurRejetee(type, inconnue)'));
    });

    test('contrôles de direction retirés du nom (P9)', () {
      final lue = _lue(
        _recette(
          nom:
              '${String.fromCharCode(0x202E)}IPA${String.fromCharCode(0x202C)}',
        ),
      );
      expect(lue.recipe['name'], 'IPA');
      expect(decrire(lue.modifications.first), 'CaracteresRetires');
    });

    test('champs inconnus comptés ; DISPLAY_*, INVENTORY, VERSION ignorés', () {
      expect(
        _modifs(
          _recette(
            plus:
                '<VERSION>1</VERSION><DISPLAY_BATCH_SIZE>5 gal</DISPLAY_BATCH_SIZE>'
                '<PRIX>12</PRIX><COUT>3</COUT>',
          ),
        ),
        ['ChampsInconnus(2)'],
      );
    });

    test('style, équipement, eau, fermentation : non importés, listés', () {
      expect(
        _modifs(
          _recette(
            plus:
                '<STYLE><NAME>Saison</NAME><CATEGORY>Belgian Ale</CATEGORY></STYLE>'
                '<EQUIPMENT><NAME>Cuve</NAME></EQUIPMENT>'
                '<WATERS><WATER><NAME>Eau</NAME></WATER></WATERS>'
                '<PRIMARY_AGE>14</PRIMARY_AGE><WATERS/>',
          ),
        ),
        [
          'StyleReduitAuNom(Saison)',
          'PartiesNonImportees(equipement, eau, fermentation)',
        ],
      );
    });

    test('éléments vides : rien n\'est listé', () {
      expect(
        _modifs(
          _recette(
            plus:
                '<WATERS/><EQUIPMENT></EQUIPMENT><TASTE_NOTES> </TASTE_NOTES>',
          ),
        ),
        isEmpty,
      );
    });

    test('nombre illisible ou non fini : recette refusée', () {
      for (final v in ['abc', 'NaN', 'Infinity', '1e400', '20,5']) {
        expect(
          _refusRecette(_recette(plus: '<BATCH_SIZE>$v</BATCH_SIZE>')),
          'ValeurIllisible(volume)',
          reason: v,
        );
      }
    });

    test('durée d\'ébullition décimale : arrondie et listée', () {
      final lue = _lue(_recette(plus: '<BOIL_TIME>59.6</BOIL_TIME>'));
      expect(lue.recipe['boil'], {
        'boil_time': {'value': 60, 'unit': 'min'},
      });
      expect(
        [for (final m in lue.modifications) decrire(m)],
        ['DureeArrondie(dureeEbullition)'],
      );
    });

    test('plus de 50 houblons : refusée, sans troncature', () {
      expect(
        _refusRecette(_fichier('<NAME>R</NAME><HOPS>${_hop * 51}</HOPS>')),
        'TropDeLignes(houblons, 51, 50)',
      );
    });

    test(
      'revue de sécurité de la v0.1.21 : 200 000 houblons, nombre lu cité',
      () {
        // Seules 51 lignes sont converties ; le refus cite le nombre du fichier.
        expect(
          _refusRecette(
            _fichier('<NAME>R</NAME><HOPS>${'<HOP/>' * 200000}</HOPS>'),
          ),
          'TropDeLignes(houblons, 200000, 50)',
        );
        expect(
          _refusRecette(
            _fichier(
              '<NAME>R</NAME><MASH><MASH_STEPS>${'<MASH_STEP/>' * 21}'
              '</MASH_STEPS></MASH>',
            ),
          ),
          'TropDeLignes(paliers, 21, 20)',
        );
      },
    );
  });

  group('houblons', () {
    test('First Wort : ébullition pendant BOIL_TIME, listé', () {
      expect(_timing(_houblon('First Wort', time: '<TIME>60</TIME>')), {
        'use': 'add_to_boil',
        'time': {'value': 70, 'unit': 'min'},
      });
      expect(
        _modifs(
          _fichier(
            '<NAME>R</NAME><BOIL_TIME>70</BOIL_TIME>'
            '<HOPS>${_houblon('First Wort')}</HOPS>',
          ),
        ),
        ['FirstWortEnEbullition(Saaz, 70)'],
      );
    });

    test('First Wort sans BOIL_TIME : durée absente, listé', () {
      final texte = _fichier(
        '<NAME>R</NAME><HOPS>${_houblon('First Wort')}</HOPS>',
      );
      expect(_ligne(texte, 'hop_additions')['timing'], {'use': 'add_to_boil'});
      expect(_modifs(texte), ['FirstWortEnEbullition(Saaz, null)']);
    });

    test(
      'Aroma : avec TIME, ébullition de TIME minutes, listé ; 0, arrêt du feu',
      () {
        expect(_timing(_houblon('Aroma', time: '<TIME>20</TIME>')), {
          'use': 'add_to_boil',
          'time': {'value': 20, 'unit': 'min'},
        });
        expect(
          _modifs(
            _fichier(
              '<NAME>R</NAME><HOPS>${_houblon('Aroma', time: '<TIME>20</TIME>')}</HOPS>',
            ),
          ),
          ['AromaEnEbullition(Saaz, 20)'],
        );
        final zero = _fichier(
          '<NAME>R</NAME><HOPS>${_houblon('Aroma', time: '<TIME>0</TIME>')}</HOPS>',
        );
        expect(_ligne(zero, 'hop_additions')['timing'], {
          'use': 'add_to_boil',
          'time': {'value': 0, 'unit': 'min'},
        });
        expect(_modifs(zero), isEmpty);
      },
    );

    test('Aroma ou Whirlpool sans durée : arrêt du feu, listé', () {
      for (final (use, time) in [
        ('Aroma', ''),
        ('Whirlpool', ''),
        ('Whirlpool', '<TIME>0</TIME>'),
      ]) {
        final texte = _fichier(
          '<NAME>R</NAME><HOPS>${_houblon(use, time: time)}</HOPS>',
        );
        expect(_ligne(texte, 'hop_additions')['timing'], {
          'use': 'add_to_boil',
          'time': {'value': 0, 'unit': 'min'},
        });
        expect(_modifs(texte), ['ArretDuFeuSansDuree(Saaz, $use)']);
      }
    });

    test('Whirlpool avec durée : après l\'arrêt du feu, pour TIME', () {
      expect(_timing(_houblon('Whirlpool', time: '<TIME>15</TIME>')), {
        'use': 'add_to_boil',
        'time': {'value': 0, 'unit': 'min'},
        'duration': {'value': 15, 'unit': 'min'},
      });
    });

    test('Dry Hop, Mash, Secondary', () {
      expect(_timing(_houblon('Dry Hop', time: '<TIME>4320</TIME>')), {
        'use': 'add_to_fermentation',
        'duration': {'value': 4320, 'unit': 'min'},
      });
      expect(_timing(_houblon('Mash', time: '<TIME>60</TIME>')), {
        'use': 'add_to_mash',
        'duration': {'value': 60, 'unit': 'min'},
      });
      expect(
        _modifs(
          _fichier(
            '<NAME>R</NAME><HOPS>${_houblon('Secondary', time: '<TIME>60</TIME>')}</HOPS>',
          ),
        ),
        ['MomentSimplifie(Saaz, add_to_fermentation)'],
      );
    });

    test('moment inconnu : refusée ; forme absente : ligne gardée sans forme, '
        'sans perte', () {
      expect(
        _refusRecette(
          _fichier('<NAME>R</NAME><HOPS>${_houblon('Bouillon')}</HOPS>'),
        ),
        'ValeurInconnue(moment, Saaz, Bouillon)',
      );
      final sansForme = _fichier(
        '<NAME>R</NAME><HOPS><HOP><NAME>Saaz</NAME><AMOUNT>0.01</AMOUNT>'
        '<USE>Boil</USE><TIME>5</TIME></HOP></HOPS>',
      );
      final hop = _ligne(sansForme, 'hop_additions');
      expect(hop.containsKey('form'), isFalse);
      expect(hop['amount'], {'value': 10, 'unit': 'g'});
      expect(_modifs(sansForme), isEmpty);
    });

    test('ALPHA 0 : lu comme absent et listé ; AMOUNT en kg → g', () {
      final texte = _fichier(
        '<NAME>R</NAME><HOPS><HOP><NAME>Saaz</NAME><ALPHA>0</ALPHA>'
        '<AMOUNT>0.0283495</AMOUNT><USE>Boil</USE><TIME>5</TIME>'
        '<FORM>Plug</FORM></HOP></HOPS>',
      );
      final hop = _ligne(texte, 'hop_additions');
      expect(hop['alpha_acid'], isNull);
      expect(hop['form'], 'plug');
      expect(hop['amount'], {'value': 28.3495, 'unit': 'g'});
      expect(_modifs(texte), ['ValeurRejetee(acidesAlpha, Saaz, nulle)']);
    });
  });

  group('malts, ajouts, levures, paliers', () {
    String malt(String type, {String plus = ''}) =>
        '<FERMENTABLE><NAME>M</NAME><TYPE>$type</TYPE><AMOUNT>1</AMOUNT>'
        '<COLOR>10</COLOR>$plus</FERMENTABLE>';
    Map<String, Object?> lireMalt(String f) => _ligne(
      _fichier('<NAME>R</NAME><FERMENTABLES>$f</FERMENTABLES>'),
      'fermentable_additions',
    );

    test('types de malt : Adjunct → grain, extraits, couleur en EBC', () {
      expect(lireMalt(malt('Adjunct'))['type'], 'grain');
      expect(lireMalt(malt('Dry Extract'))['type'], 'dry extract');
      final extrait = lireMalt(malt('Extract'));
      expect(extrait['type'], 'extract');
      // SRM pour un extrait liquide, Lovibond sinon : même facteur, 1,97.
      expect((extrait['color']! as Map)['value'], closeTo(19.7, 1e-9));
      expect(
        (lireMalt(malt('Grain'))['color']! as Map)['value'],
        closeTo(19.7, 1e-9),
      );
      expect(
        _refusRecette(
          _fichier(
            '<NAME>R</NAME><FERMENTABLES>${malt('Mystère')}</FERMENTABLES>',
          ),
        ),
        'ValeurInconnue(type, M, Mystère)',
      );
    });

    test('YIELD 0 : absent, listé ; POTENTIAL lu à défaut de YIELD', () {
      final zero = _fichier(
        '<NAME>R</NAME><FERMENTABLES>${malt('Grain', plus: '<YIELD>0</YIELD>')}</FERMENTABLES>',
      );
      expect(_ligne(zero, 'fermentable_additions')['yield'], isNull);
      expect(_modifs(zero), contains('ValeurRejetee(rendement, M, nulle)'));
      final potentiel = lireMalt(
        malt('Grain', plus: '<POTENTIAL>1.037</POTENTIAL>'),
      );
      expect(
        (((potentiel['yield']! as Map)['fine_grind']) as Map)['value'],
        closeTo(80.062319, 1e-6),
      );
    });

    test(
      'ajout : AMOUNT_IS_WEIGHT absent, litres ; TRUE, grammes ; autre, refusée',
      () {
        String ajout(String poids) => _fichier(
          '<NAME>R</NAME><MISCS><MISC><NAME>Acide</NAME><TYPE>Water Agent</TYPE>'
          '<USE>Mash</USE><TIME>60</TIME><AMOUNT>0.005</AMOUNT>$poids</MISC></MISCS>',
        );
        expect(_ligne(ajout(''), 'miscellaneous_additions'), {
          'name': 'Acide',
          'type': 'water agent',
          'amount': {'value': 0.005, 'unit': 'l'},
          'timing': {
            'use': 'add_to_mash',
            'duration': {'value': 60, 'unit': 'min'},
          },
        });
        expect(
          (_ligne(
                ajout('<AMOUNT_IS_WEIGHT>TRUE</AMOUNT_IS_WEIGHT>'),
                'miscellaneous_additions',
              )['amount']!
              as Map)['unit'],
          'g',
        );
        expect(
          _refusRecette(ajout('<AMOUNT_IS_WEIGHT>oui</AMOUNT_IS_WEIGHT>')),
          'ValeurIllisible(quantite, Acide)',
        );
      },
    );

    test('ajout : moments Boil, Primary, Bottling ; Secondary simplifié', () {
      Object? moment(String use) => _ligne(
        _fichier(
          '<NAME>R</NAME><MISCS><MISC><NAME>X</NAME><TYPE>Spice</TYPE>'
          '<USE>$use</USE><TIME>5</TIME><AMOUNT>0.01</AMOUNT>'
          '<AMOUNT_IS_WEIGHT>TRUE</AMOUNT_IS_WEIGHT></MISC></MISCS>',
        ),
        'miscellaneous_additions',
      )['timing'];
      expect(moment('Boil'), {
        'use': 'add_to_boil',
        'time': {'value': 5, 'unit': 'min'},
      });
      expect((moment('Primary')! as Map)['use'], 'add_to_fermentation');
      expect((moment('Secondary')! as Map)['use'], 'add_to_fermentation');
      expect((moment('Bottling')! as Map)['use'], 'add_to_package');
    });

    test(
      'levure : Wheat → wheat sans perte ; litres par défaut (décision 6)',
      () {
        final texte = _fichier(
          '<NAME>R</NAME><YEASTS><YEAST><NAME>Blé</NAME><TYPE>Wheat</TYPE>'
          '<FORM>Liquid</FORM><AMOUNT>0.125</AMOUNT><ATTENUATION>75</ATTENUATION>'
          '<LABORATORY>Labo</LABORATORY></YEAST></YEASTS>',
        );
        expect(_ligne(texte, 'culture_additions'), {
          'name': 'Blé',
          'type': 'wheat',
          'form': 'liquid',
          'attenuation': {'value': 75.0, 'unit': '%'},
          'amount': {'value': 0.125, 'unit': 'l'},
        });
        expect(_modifs(texte), ['PartiesNonImportees(detailsIngredients)']);
      },
    );

    test(
      'palier : INFUSE_AMOUNT non importé, listé ; nom d\'empâtage remplacé',
      () {
        final lue = _lue(
          _recette(
            plus:
                '<MASH><NAME>Empâtage</NAME><GRAIN_TEMP>20</GRAIN_TEMP><MASH_STEPS>'
                '<MASH_STEP><NAME>Sacch</NAME><TYPE>Infusion</TYPE>'
                '<INFUSE_AMOUNT>15</INFUSE_AMOUNT><STEP_TEMP>66</STEP_TEMP>'
                '<STEP_TIME>60</STEP_TIME></MASH_STEP></MASH_STEPS></MASH>',
          ),
        );
        expect(lue.recipe['mash'], {
          'name': kNomEmpatage,
          'grain_temperature': {'value': 20.0, 'unit': 'C'},
          'mash_steps': [
            {
              'name': 'Sacch',
              'type': 'infusion',
              'step_temperature': {'value': 66.0, 'unit': 'C'},
              'step_time': {'value': 60, 'unit': 'min'},
            },
          ],
        });
        expect(
          [for (final m in lue.modifications) decrire(m)],
          ['PartiesNonImportees(detailsPaliers)'],
        );
      },
    );

    test('palier sans STEP_TIME : refusée', () {
      expect(
        _refusRecette(
          _recette(
            plus:
                '<MASH><MASH_STEPS><MASH_STEP><NAME>P</NAME><STEP_TEMP>66</STEP_TEMP>'
                '</MASH_STEP></MASH_STEPS></MASH>',
          ),
        ),
        'ValeurAbsente(dureePalier, P)',
      );
    });
  });
}
