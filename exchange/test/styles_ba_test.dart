import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:exchange/ingestion.dart';
import 'package:test/test.dart';

/// Styles de la Brewers Association (ADR-018, lot S1) sur une table et un
/// fichier de plages inventés (`test/fixtures/ingestion/ba/`, P20) : aucun nom
/// ni aucune plage de la BA dans le dépôt hors de la table versionnée.

const _dossier = 'test/fixtures/ingestion';

String _lire(String f) => File('$_dossier/$f').readAsStringSync();

Map<String, Object?> _json(String f) =>
    jsonDecode(_lire(f)) as Map<String, Object?>;

SourcesBrutes _sources({String? table, String? plages, bool ba = true}) {
  String texte(String f) => _lire('brewtarget/$f');
  return SourcesBrutes(
    octets001: File('$_dossier/brewtarget/001.xml').readAsBytesSync(),
    texte002: texte('002.json'),
    texte003: texte('003.json'),
    texte004: texte('004.json'),
    texte005: texte('005.beer'),
    texteFabricants: _lire('fabricants/vide.json'),
    diyDog: [
      for (final f in ['001.json', '002.json'])
        (fichier: f, texte: _lire('diydog/$f')),
    ],
    ba: ba
        ? (
            table: table ?? _lire('ba/table.json'),
            plages: plages ?? _lire('ba/styles.json'),
          )
        : null,
  );
}

Preparation _preparer({String? table, String? plages, bool ba = true}) =>
    preparer(
      _sources(table: table, plages: plages, ba: ba),
      alias: const [],
      ajoutsDansHoublons: const [],
      fusions: const [],
      fusionsCultures: const [],
      correctionsCultures: const [],
    );

Map<String, Object?> _doc(Preparation p, String collection, String id) {
  final d = p.collections[collection]!.where((e) => e['id'] == id);
  expect(d, hasLength(1), reason: '$collection/$id');
  return d.single['data']! as Map<String, Object?>;
}

/// Table de la fixture modifiée par [modifier] (ligne [i]).
String _table(void Function(Map<String, Object?> table) modifier) {
  final t = _json('ba/table.json');
  modifier(t);
  return jsonEncode(t);
}

Map<String, Object?> _ligne(Map<String, Object?> t, int i) =>
    (t['styles']! as List)[i] as Map<String, Object?>;

/// Fichier des plages de la fixture modifié par [modifier].
String _plages(void Function(Map<String, Object?> plages) modifier) {
  final p = _json('ba/styles.json');
  modifier(p);
  return jsonEncode(p);
}

List<Object?> _stylesPlages(Map<String, Object?> p) =>
    (p['beerjson']! as Map)['styles']! as List;

Matcher _refus(String message) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(message)),
);

Matcher _illisible(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(message)),
);

void main() {
  group('sans --ba', () {
    final p = _preparer(ba: false);

    test('styles BJCP seuls, index sans ba_mention, guide par entrée', () {
      expect(
        [for (final d in p.collections['beer_styles']!) d['id']],
        ['bjcp2021-99a', 'bjcp2021-99b'],
      );
      final index = _doc(p, 'beer_index', 'styles');
      expect(index.containsKey('ba_mention'), isFalse);
      for (final e
          in (index['entries']! as List).cast<Map<Object?, Object?>>()) {
        expect(e['guide'], 'BJCP2021', reason: '${e['id']}');
      }
      expect(p.rapport.containsKey('styles_ba'), isFalse);
      expect([
        for (final s in p.rapport['sources']! as List) (s as Map)['source'],
      ], isNot(contains(kSourceBa)));
      expect(
        (p.rapport['entrees_par_source']! as Map).containsKey(kSourceBa),
        isFalse,
      );
    });
  });

  group('avec --ba', () {
    final p = _preparer();

    test('seuls les nouveaux de l\'édition courante sont écrits', () {
      expect(
        [for (final d in p.collections['beer_styles']!) d['id']],
        [
          'ba-ambree-inventee',
          'ba-blonde-imaginaire',
          'bjcp2021-99a',
          'bjcp2021-99b',
        ],
      );
    });

    test('document : code et guide de la table, plages converties', () {
      final s = _doc(p, 'beer_styles', 'ba-ambree-inventee');
      expect(s.keys.toSet(), {
        'name',
        'category',
        'category_id',
        'style_id',
        'type',
        'style_guide',
        'original_gravity',
        'final_gravity',
        'international_bitterness_units',
        'color',
        'alcohol_by_volume',
        'provenance',
        'content_sha256',
      });
      expect(s['name'], 'Ambrée Inventée');
      expect(s['category'], 'Catégorie Inventée Une');
      expect(s['style_id'], 'BA1A');
      expect(s['category_id'], 'BA1');
      expect(s['style_guide'], 'BA2026');
      expect(s['type'], 'beer');
      expect(
        s['color'],
        plage(arrondi(srmToEbc(5), 1), arrondi(srmToEbc(9), 1), 'EBC'),
      );
      expect(s['original_gravity'], plage(1.045, 1.055, 'sg'));
      expect((s['provenance']! as List).single, {
        'source': 'brewers-association',
        'source_id': 'Ambrée Inventée',
        'version': '2026',
        'licence': 'BA (usage gratuit, mention de la BA)',
        'retrieved': '2026-11-22',
      });
      final b = _doc(p, 'beer_styles', 'ba-blonde-imaginaire');
      expect(b['style_id'], 'BA1B');
      expect(b.containsKey('final_gravity'), isFalse);
    });

    test('aucun texte libre du fichier des plages (P20)', () {
      final texte = jsonEncode(p.collections);
      expect(texte, isNot(contains('TEXTE LIBRE BA')));
      expect(texte, isNot(contains('IGNORE')));
      expect(texte, isNot(contains('Motif inventé')));
    });

    test('index : guide par entrée, ba_mention de la table', () {
      final index = _doc(p, 'beer_index', 'styles');
      expect(index['count'], 4);
      expect(index['ba_mention'], {
        'edition': 2026,
        'mention': 'Mention inventée pour la fixture, édition 2026.',
      });
      final entrees = (index['entries']! as List).cast<Map<Object?, Object?>>();
      expect(entrees.first, {
        'id': 'ba-ambree-inventee',
        'name': 'Ambrée Inventée',
        'code': 'BA1A',
        'category': 'Catégorie Inventée Une',
        'guide': 'BA2026',
        'og': [1.045, 1.055],
        'fg': [1.01, 1.014],
        'ibu': [25, 35],
        'ebc': [arrondi(srmToEbc(5), 1), arrondi(srmToEbc(9), 1)],
        'abv': [4.5, 5.5],
      });
      expect(
        [for (final e in entrees) e['guide']],
        ['BA2026', 'BA2026', 'BJCP2021', 'BJCP2021'],
      );
    });

    test('rapport : chevauchements, équivalents, retirées, source', () {
      final r = p.rapport['styles_ba']! as Map;
      expect(r['edition'], 2026);
      expect(r['lignes'], 4);
      expect(r['lus'], 3);
      expect(r['nouveaux'], 2);
      expect(r['retirees'], 1);
      expect(r['equivalents'], [
        {
          'name': 'Style Fictif Bis',
          'equivalent': ['99A'],
        },
      ]);
      expect(r['chevauchements'], [
        {
          'id': 'ba-ambree-inventee',
          'name': 'Ambrée Inventée',
          'code': 'BA1A',
          'bjcp': ['99A'],
        },
        {
          'id': 'ba-blonde-imaginaire',
          'name': 'Blonde Imaginaire',
          'code': 'BA1B',
          'contenu_dans': '99A',
          'bjcp': <String>[],
        },
      ]);
      expect(
        p.rapport['sources'],
        contains(equals({'source': kSourceBa, 'version': '2026'})),
      );
      expect((p.rapport['entrees_par_source']! as Map)[kSourceBa], {
        'style': 3,
      });
    });

    test('préparation reproductible, empreintes du contenu', () {
      final autre = _preparer();
      expect(jsonEncode(autre.collections), jsonEncode(p.collections));
      for (final d in p.collections['beer_styles']!) {
        final data = Map.of(d['data']! as Map<String, Object?>);
        final empreinte = data.remove('content_sha256');
        expect(empreinte, empreinteContenu(data));
      }
    });
  });

  group('contrôles', () {
    test('édition du fichier des plages différente : refusée', () {
      expect(
        () => _preparer(plages: _plages((p) => p['edition'] = 2027)),
        _refus('édition 2027'),
      );
    });

    test('style sans ligne, et style d\'une ligne retirée : refusés', () {
      expect(
        () => _preparer(
          plages: _plages(
            (p) => _stylesPlages(p).addAll([
              {
                'name': 'Inconnue Inventée',
                'category': 'Catégorie Inventée Une',
              },
              {'name': 'Brune Disparue', 'category': 'Catégorie Inventée Deux'},
            ]),
          ),
        ),
        _refus(
          'styles sans ligne de la table : « Inconnue Inventée » '
          '(Catégorie Inventée Une), « Brune Disparue » '
          '(Catégorie Inventée Deux, ligne retirée)',
        ),
      );
    });

    test('même nom dans une autre catégorie : sans ligne', () {
      expect(
        () => _preparer(
          plages: _plages(
            (p) => (_stylesPlages(p)[1] as Map)['category'] = 'Autre Catégorie',
          ),
        ),
        _refus('« Blonde Imaginaire » (Autre Catégorie)'),
      );
    });

    test('ligne non retirée sans style : refusée', () {
      expect(
        () => _preparer(plages: _plages((p) => _stylesPlages(p).removeAt(2))),
        _refus('lignes sans style dans styles.json : « Style Fictif Bis »'),
      );
    });

    test('ligne non retirée sans l\'édition courante : refusée', () {
      expect(
        () =>
            _preparer(table: _table((t) => _ligne(t, 1)['editions'] = [2025])),
        _refus(
          '« Blonde Imaginaire » : ligne non retirée sans l\'édition 2026',
        ),
      );
    });

    test('code hors motif : refusé', () {
      for (final code in ['BA0A', 'BA1', 'BA100A', 'ba1a', 'BA1ABC', 'X1A']) {
        expect(
          () => _preparer(table: _table((t) => _ligne(t, 0)['code'] = code)),
          _illisible('code hors du motif'),
          reason: code,
        );
      }
      expect(
        lireTableBa(_table((t) => _ligne(t, 0)['code'] = 'BA12AB')),
        isNotNull,
      );
    });

    test('code en double, même sur une ligne retirée : refusé', () {
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 1)['code'] = 'BA2A')),
        _refus(
          'code BA2A porté par « Blonde Imaginaire » et « Brune Disparue »',
        ),
      );
    });

    test('nouveau sans code, équivalent avec un code : refusés', () {
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 0).remove('code'))),
        _illisible('styles[0].code'),
      );
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 2)['code'] = 'BA2B')),
        _illisible('refusé sur un « equivalent »'),
      );
    });

    test('équivalent vers un code absent du BJCP préparé : refusé', () {
      expect(
        () => _preparer(
          table: _table((t) => _ligne(t, 2)['equivalent'] = ['99A', '21B']),
        ),
        _refus('équivalent 21B absent du BJCP 2021 préparé'),
      );
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 2)['equivalent'] = [])),
        _illisible('liste de 1 à 10 codes BJCP'),
      );
    });

    test('contenu_dans : refusé sur un équivalent, code du 002 exigé', () {
      expect(
        () => _preparer(
          table: _table((t) => _ligne(t, 2)['contenu_dans'] = '99A'),
        ),
        _illisible('styles[2].contenu_dans : refusé sur un « equivalent »'),
      );
      expect(
        () => _preparer(
          table: _table((t) => _ligne(t, 1)['contenu_dans'] = '21B'),
        ),
        _refus('contenu_dans 21B absent du BJCP 2021 préparé'),
      );
    });

    test('nom égal après cleNormalisee à un style BJCP : refusé', () {
      expect(
        () => _preparer(
          table: _table((t) => _ligne(t, 0)['name'] = 'STYLE fictif'),
          plages: _plages(
            (p) => (_stylesPlages(p)[0] as Map)['name'] = 'STYLE fictif',
          ),
        ),
        _refus('« STYLE fictif » : même nom normalisé que bjcp2021-99a'),
      );
    });

    test('nom égal après cleNormalisee à un autre style BA : refusé', () {
      expect(
        () => _preparer(
          table: _table((t) {
            _ligne(t, 1)
              ..['name'] = 'Ambree inventée'
              ..['category'] = 'Catégorie Inventée Une';
          }),
          plages: _plages(
            (p) => (_stylesPlages(p)[1] as Map)['name'] = 'Ambree inventée',
          ),
        ),
        _refus(
          '« Ambree inventée » : même nom normalisé que « Ambrée Inventée »',
        ),
      );
    });

    test('style en double dans le fichier des plages : refusé', () {
      expect(
        () => _preparer(
          plages: _plages(
            (p) => _stylesPlages(p).add(Map.of(_stylesPlages(p)[0] as Map)),
          ),
        ),
        _refus('« Ambrée Inventée » (Catégorie Inventée Une) : deux fois'),
      );
    });

    test('decision et motif obligatoires', () {
      expect(
        () => _preparer(
          table: _table((t) => _ligne(t, 0)['decision'] = 'peut-être'),
        ),
        _illisible('« nouveau » ou « equivalent »'),
      );
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 0).remove('motif'))),
        _illisible('styles[0].motif'),
      );
    });

    test('plage ou description dans la table : refusée (P20)', () {
      for (final cle in ['original_gravity', 'description', 'examples']) {
        expect(
          () => _preparer(table: _table((t) => _ligne(t, 0)[cle] = 'x')),
          _illisible('clé non permise « $cle »'),
          reason: cle,
        );
      }
    });

    test('clé hors des champs de P20 à la racine de la table : refusée', () {
      for (final cle in ['regle_code', 'description', 'plages']) {
        expect(
          () => lireTableBa(_table((t) => t[cle] = 'x')),
          _illisible('racine : clé non permise « $cle »'),
          reason: cle,
        );
      }
    });

    test('nom hors NFC ou avec une espace de bord : refusé', () {
      // « e » suivi de l'accent combinant U+0301.
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 0)['name'] = 'Ambrée')),
        _illisible('hors de la forme NFC'),
      );
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 0)['name'] = 'Ambrée ')),
        _illisible('espace de bord'),
      );
    });

    test('mention qui ne cite pas l\'édition, retire_en avant une édition', () {
      expect(
        () => _preparer(
          table: _table((t) => t['mention'] = 'Mention sans année.'),
        ),
        _illisible('ne cite pas l\'édition 2026'),
      );
      expect(
        () => _preparer(table: _table((t) => _ligne(t, 3)['retire_en'] = 2025)),
        _illisible('styles[3].retire_en'),
      );
    });

    test('en-tête du fichier des plages contrôlé', () {
      expect(
        () => _preparer(plages: _plages((p) => p['pdf_sha256'] = 'abc')),
        _illisible('pdf_sha256'),
      );
      expect(
        () => _preparer(plages: _plages((p) => p['retrieved'] = 'hier')),
        _illisible('retrieved'),
      );
      expect(
        () => _preparer(plages: _plages((p) => p['notes'] = 'x')),
        _illisible('clé non permise « notes »'),
      );
    });
  });

  group('controlerTableBa', () {
    test('table de la fixture : aucune anomalie, avec ou sans le 002', () {
      final t = lireTableBa(_lire('ba/table.json'));
      expect(controlerTableBa(t), isEmpty);
      expect(
        controlerTableBa(
          t,
          codesBjcp: {'99A', '99B'},
          nomsBjcp: {'style-fictif': 'bjcp2021-99a'},
        ),
        isEmpty,
      );
      expect(
        [for (final l in t.lignesActives) l.nom],
        ['Ambrée Inventée', 'Blonde Imaginaire', 'Style Fictif Bis'],
      );
    });

    test('anomalies de la table seule, sans le 002', () {
      final t = lireTableBa(
        _table((t) {
          _ligne(t, 1)['code'] = 'BA2A';
          _ligne(t, 2)
            ..['name'] = 'Ambrée Inventée'
            ..['category'] = 'Catégorie Inventée Une'
            ..['editions'] = [2025];
          _ligne(t, 0)['name'] = 'AMBREE inventee';
        }),
      );
      expect(controlerTableBa(t), [
        '« Ambrée Inventée » : ligne non retirée sans l\'édition 2026',
        'code BA2A porté par « Blonde Imaginaire » et « Brune Disparue »',
      ]);
      final doublon = lireTableBa(
        _table((t) {
          final l = Map.of(_ligne(t, 0))..['code'] = 'BA1C';
          (t['styles']! as List).add(l);
        }),
      );
      expect(controlerTableBa(doublon), [
        '« Ambrée Inventée » (Catégorie Inventée Une) : deux lignes non retirées',
        '« Ambrée Inventée » : même nom normalisé que « Ambrée Inventée »',
      ]);
    });

    test('avec le 002 : codes et noms BJCP contrôlés', () {
      final t = lireTableBa(
        _table((t) {
          _ligne(t, 0)['name'] = 'Style Fictif';
          _ligne(t, 2)['equivalent'] = ['21B'];
        }),
      );
      expect(
        controlerTableBa(
          t,
          codesBjcp: {'99A'},
          nomsBjcp: {'style-fictif': 'bjcp2021-99a'},
        ),
        [
          '« Style Fictif » : même nom normalisé que bjcp2021-99a',
          '« Style Fictif Bis » : équivalent 21B absent du BJCP 2021 préparé',
        ],
      );
      expect(controlerTableBa(t), isEmpty);
    });
  });

  group('table versionnée', () {
    final texte = File('donnees/styles/ba.json').readAsStringSync();

    test('lisible, édition 2026, mention exacte de la BA', () {
      final t = lireTableBa(texte);
      expect(t.editionCourante, 2026);
      expect(
        t.mention,
        'Based on Brewers Association 2026 Beer Style Guidelines with '
        'changes. Used with permission of Brewers Association.',
      );
    });

    // Tant que la table n'a aucune ligne (avant la relecture du lot S0), un
    // fichier de plages vide se joint sans style BA.
    test(
      'vide, jointe à un fichier de plages vide : aucun style BA',
      () {
        final plages = _plages(
          (p) => (p['beerjson']! as Map)['styles'] = <Object?>[],
        );
        final p = _preparer(table: texte, plages: plages);
        expect(
          [for (final d in p.collections['beer_styles']!) d['id']],
          ['bjcp2021-99a', 'bjcp2021-99b'],
        );
        expect(
          (_doc(p, 'beer_index', 'styles')['ba_mention']! as Map)['edition'],
          2026,
        );
      },
      skip: lireTableBa(texte).lignes.isNotEmpty
          ? 'table remplie : jointure rejouée sur le poste de l\'admin'
          : false,
    );

    test('contrôles de la table seule : aucune anomalie', () {
      // Noms BJCP : ceux du 002 de la fixture ; les codes de la vraie table
      // visent le 002 réel, rejoué par --ba sur le poste de l'admin.
      final lecture = LectureReferentiels()
        ..lire002(_lire('brewtarget/002.json'));
      expect(
        controlerTableBa(
          lireTableBa(texte),
          nomsBjcp: {
            for (final s in lecture.styles)
              cleNormalisee(s.document['name']! as String): s.id,
          },
        ),
        isEmpty,
      );
    });

    test('codes uniques et au motif (ADR-018, section 4)', () {
      final codes = [for (final l in lireTableBa(texte).lignes) ?l.code];
      expect(codes.toSet(), hasLength(codes.length));
      expect(codes.where((c) => !kMotifCodeBa.hasMatch(c)), isEmpty);
    });
  });
}
