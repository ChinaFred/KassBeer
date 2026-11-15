import 'dart:convert';
import 'dart:io';

import 'package:exchange/ingestion.dart';
import 'package:test/test.dart';

/// Table de fusion des houblons et liste des pays (ADR-014, P56), sur des
/// sources écrites à la main : noms de variétés des fichiers 001, 003 et 005
/// de Brewtarget (relevé du 2026-11-15), origines dans les graphies relevées,
/// acides inventés. Aucun extrait de source (P20).

typedef _Houblon = (String nom, String origine, double alpha);

/// Houblons du fichier 005 : nom, origine lue, acide alpha inventé.
const List<_Houblon> _h005 = [
  ("Brewer's Gold", 'Germany', 50.1),
  ('Columbus', 'United States', 50.2),
  ('Columbus/Tomahawk/Zeus (CTZ)', 'United States', 50.3),
  ('East Kent Golding', 'Great Britain', 50.4),
  ('East Kent Goldings (EKG)', 'Great Britain', 50.5),
  ('East Kent Goldings (EKG) (1)', 'Great Britain', 50.6),
  ('Hallertau (NZ)', 'New Zealand', 50.7),
  ('Hallertau (US)', 'United States', 50.8),
  ('Hallertauer Bitter', 'Germany', 50.9),
  ('Hallertauer Blanc', 'Germany', 51.0),
  ('Hallertauer Diamant', 'Germany', 51.1),
  ('Hallertauer Gold', 'Germany', 51.2),
  ('Hallertauer Hersbrucker', 'Germany', 51.3),
  ('Hallertauer Mittelfrueh', 'Germany', 51.4),
  ('Hallertauer Mittelfrüh', 'Germany', 51.5),
  ('Hallertauer Rotrebiger', 'Germany', 51.6),
  ('Hallertauer Taurus', 'Germany', 51.7),
  ('Hallertauer Tradition', 'Germany', 51.8),
  ('Magnum', 'United States', 51.9),
  ('Magnum', 'Germany', 52.0),
  ('Northern Brewer', 'Germany', 52.1),
  ('Perle', 'Germany', 52.2),
  ('Saaz', 'United States', 52.3),
  ('Saaz', 'US', 52.4),
  ('Sultana', 'United States', 52.5),
  ('Tettnang', 'Germany', 52.6),
  ('Tettnanger', 'Germany', 52.7),
];

/// Houblons du fichier 003.
const List<_Houblon> _h003 = [
  ("Brewer's Gold (GR)", 'Germany (GER)', 30.1),
  ("Brewer's Gold (US)", 'United States of America (USA)', 30.2),
  ('Columbus', 'United States', 30.3),
  ('East Kent Goldings', 'United Kingdom (UK)', 30.4),
  ('Hallertau (US)', 'United States', 30.5),
  ('Hallertau Blanc', 'Germany (GER)', 30.6),
  ('Hallertau Gold', 'Germany (GER)', 30.7),
  ('Hallertau Mittelfrüh', 'Germany (GER)', 30.8),
  ('Hallertau Taurus', 'United Kingdom (UK)', 30.9),
  ('Hallertau Tradition', 'Germany (GER)', 31.0),
  ('Magnum (GR)', 'Germany (GER)', 31.1),
  ('Magnum (US)', 'United States of America (USA)', 31.2),
  ('Northern Brewer (GR)', 'Germany (GER)', 31.3),
  ('Northern Brewer (US)', 'United States of America (USA)', 31.4),
  ('Perle (GR)', 'Germany (GER)', 31.5),
  ('Perle (US)', 'United States of America (USA)', 31.6),
  ('Saaz (CZ)', 'Czech Replublic (CZH)', 31.7),
  ('Saaz (US)', 'United States of America (USA)', 31.8),
  ('Saaz Late', 'Czech Replublic (CZH)', 31.9),
  ('Sultana (Denali)', 'United States of America (USA)', 32.0),
  ('Tettnang (US)', 'United States of America (USA)', 32.1),
  ('Tettnanger', 'Germany', 32.2),
];

/// Houblons du fichier 001.
const List<_Houblon> _h001 = [
  ('Columbus/Tomahawk/Zeus', 'US', 10.1),
  ('Hallertau', '', 10.2),
  ('Magnum', 'Germany', 10.3),
  ('Northern Brewer', 'Germany', 10.4),
  ('Perle', 'Germany', 10.5),
  ('Saaz (Czech Republic)', 'Czech Republic', 10.6),
  ('Saaz (USA)', 'US', 10.7),
  ('Tettnang', 'Germany', 10.8),
];

/// Malts du fichier 005 : nom et origine lue.
const List<(String, String)> _m005 = [
  ('Malt Fictif US', 'US'),
  ('Malt Fictif UK', 'UK'),
  ('Malt Fictif NZ', 'New Zealand, Canterbury'),
  ('Malt Fictif Double', 'Austria/Slovenia'),
  ('Malt Fictif Vide', ''),
  ('Malt Fictif Inconnu', 'Pays fictif'),
];

String _texte005(List<_Houblon> houblons, List<(String, String)> malts) =>
    jsonEncode({
      'DotBeer': {
        'version': '1.0.0',
        'fermentables': [
          for (final (nom, origine) in malts)
            {
              'name': nom,
              'folder_path': 'Grain',
              'fermentable_type': 'grain',
              'origin': origine,
              'color': {'unit': 'EBC', 'value': 5},
            },
        ],
        'hops': [
          for (final (nom, origine, alpha) in houblons)
            {
              'name': nom,
              'folder_path': 'Fictif',
              'origin': origine,
              'alpha_acid': {'unit': '%', 'value': alpha},
              'hop_type': 'aroma',
            },
        ],
      },
    });

String _texte003(List<_Houblon> houblons) => jsonEncode({
  'beerjson': {
    'version': 2.01,
    'hop_varieties': [
      for (final (i, (nom, origine, alpha)) in houblons.indexed)
        {
          'id': '${i + 1}',
          'name': nom,
          'origin': origine,
          'alpha_acid': {'unit': '%', 'value': alpha},
          'type': 'aroma',
        },
    ],
  },
});

List<int> _octets001(List<_Houblon> houblons) => latin1.encode(
  '<?xml version="1.0" encoding="ISO-8859-1"?>\n<HOPS>\n'
  '${[for (final (nom, origine, alpha) in houblons) '  <HOP><NAME>$nom</NAME><ALPHA>$alpha</ALPHA><TYPE>Aroma</TYPE><ORIGIN>$origine</ORIGIN></HOP>\n'].join()}'
  '</HOPS>\n',
);

SourcesBrutes _sources({
  List<_Houblon> h005 = _h005,
  List<_Houblon> h003 = _h003,
  List<_Houblon> h001 = _h001,
}) => SourcesBrutes(
  octets001: _octets001(h001),
  texte002: File(
    'test/fixtures/ingestion/brewtarget/002.json',
  ).readAsStringSync(),
  texte003: _texte003(h003),
  texte004: '{"beerjson": {"version": 2.01, "cultures": []}}',
  texte005: _texte005(h005, _m005),
  texteFabricants: File(
    'test/fixtures/ingestion/fabricants/vide.json',
  ).readAsStringSync(),
  diyDog: const [],
);

Preparation _preparer({
  List<_Houblon> h005 = _h005,
  List<_Houblon> h003 = _h003,
  List<_Houblon> h001 = _h001,
  List<Fusion> fusions = kFusions,
}) => preparer(
  _sources(h005: h005, h003: h003, h001: h001),
  alias: const [],
  ajoutsDansHoublons: const [],
  fusions: fusions,
);

Map<String, Map<String, Object?>> _houblons(Preparation p) => {
  for (final d in p.collections['beer_hops']!)
    d['id']! as String: d['data']! as Map<String, Object?>,
};

/// Noms des entrées fusionnées dans [doc], par source : `<source>|<nom>`.
Set<String> _sourcesDe(Map<String, Object?> doc) => {
  for (final l in doc['provenance']! as List)
    '${(l as Map)['source']}|${l['source_id']}',
};

void main() {
  group('liste des pays', () {
    test('graphies relevées ramenées au pays, casse et espaces ignorées', () {
      const attendu = {
        'US': 'United States',
        'United States': 'United States',
        'United States of America (USA)': 'United States',
        'Germany (GER)': 'Germany',
        'United Kingdom (UK)': 'Great Britain',
        'UK': 'Great Britain',
        'United Kingdom': 'Great Britain',
        'England': 'Great Britain',
        'Czech Replublic (CZH)': 'Czech Republic',
        'New Zealand (NZ)': 'New Zealand',
        'New Zealand, Canterbury': 'New Zealand',
        'Australia (AUS)': 'Australia',
        'Poland (POL)': 'Poland',
        'Slovenia (SLO)': 'Slovenia',
        'France (FR)': 'France',
        'Canada (CAN)': 'Canada',
        'China (CN)': 'China',
        '  czech   republic ': 'Czech Republic',
        'NETHERLANDS': 'Netherlands',
      };
      for (final MapEntry(:key, :value) in attendu.entries) {
        expect(paysDeGraphie(key), value, reason: key);
      }
    });

    test('origine double, inconnue ou vide : aucun pays', () {
      expect(paysDeGraphie('Austria/Slovenia'), isNull);
      expect(paysDeGraphie('Pays fictif'), isNull);
      expect(paysDeGraphie(''), isNull);
    });

    test('table : clés normalisées, chaque cible dans la liste', () {
      for (final MapEntry(:key, :value) in kGraphiesOrigine.entries) {
        expect(key, cleOrigine(key));
        expect(kPays, contains(value), reason: key);
      }
    });
  });

  group('préparation', () {
    late Preparation p;
    late Map<String, Map<String, Object?>> h;
    setUpAll(() {
      p = _preparer();
      h = _houblons(p);
    });

    test('origines des malts ramenées au pays ; inconnue et double absentes, '
        'listées au rapport ; vide absente, non listée', () {
      final malts = {
        for (final d in p.collections['beer_fermentables']!)
          d['id']! as String: d['data']! as Map<String, Object?>,
      };
      expect(malts['fermentable-malt-fictif-us']!['origin'], 'United States');
      expect(malts['fermentable-malt-fictif-uk']!['origin'], 'Great Britain');
      expect(malts['fermentable-malt-fictif-nz']!['origin'], 'New Zealand');
      for (final id in [
        'fermentable-malt-fictif-double',
        'fermentable-malt-fictif-vide',
        'fermentable-malt-fictif-inconnu',
      ]) {
        expect(malts[id]!.containsKey('origin'), isFalse, reason: id);
      }
      expect(p.rapport['origines_inconnues'], [
        {
          'id': 'fermentable-malt-fictif-double',
          'source': 'brewtarget-005',
          'name': 'Malt Fictif Double',
          'graphie': 'Austria/Slovenia',
        },
        {
          'id': 'fermentable-malt-fictif-inconnu',
          'source': 'brewtarget-005',
          'name': 'Malt Fictif Inconnu',
          'graphie': 'Pays fictif',
        },
      ]);
    });

    test('origines des houblons : une seule graphie par pays', () {
      final origines = {
        for (final d in h.values)
          if (d['origin'] case final String o) o,
      };
      expect(origines, {
        'Czech Republic',
        'Germany',
        'Great Britain',
        'New Zealand',
        'United States',
      });
      expect(kPays.containsAll(origines), isTrue);
    });

    test('documents restants : une variété et un pays par document', () {
      expect(h.keys.toSet(), {
        'hop-brewer-s-gold',
        'hop-brewer-s-gold-us',
        'hop-columbus',
        'hop-east-kent-goldings',
        'hop-hallertau-nz',
        'hop-hallertau-us',
        'hop-hallertauer-bitter',
        'hop-hallertauer-blanc',
        'hop-hallertauer-diamant',
        'hop-hallertauer-gold',
        'hop-hallertauer-hersbrucker',
        'hop-hallertauer-mittelfruh',
        'hop-hallertauer-rotrebiger',
        'hop-hallertauer-taurus',
        'hop-hallertauer-tradition',
        'hop-magnum',
        'hop-magnum-us',
        'hop-northern-brewer',
        'hop-northern-brewer-us',
        'hop-perle',
        'hop-perle-us',
        'hop-saaz',
        'hop-saaz-late',
        'hop-saaz-us',
        'hop-sultana',
        'hop-tettnang',
        'hop-tettnang-us',
      });
      for (final MapEntry(:key, :value) in h.entries) {
        expect(
          key,
          idEntree(NatureReferentiel.hop, cleNormalisee('${value['name']}')),
        );
      }
    });

    test('aucun nom normalisé ne désigne deux houblons', () {
      expect(p.rapport['noms_partages'], isNot(contains('hop')));
      final parNom = <String, Set<String>>{};
      for (final MapEntry(:key, :value) in h.entries) {
        for (final n in [value['name'], ...(value['aliases']! as List)]) {
          parNom.putIfAbsent(cleNormalisee('$n'), () => {}).add(key);
        }
      }
      expect(parNom.values.where((ids) => ids.length > 1), isEmpty);
    });

    test('chaque ligne de la table : document nommé, entrées désignées', () {
      final lecture = LectureReferentiels()
        ..lire001(_octets001(_h001))
        ..lire003ou004(_texte003(_h003), Source.brewtarget003)
        ..lire005(_texte005(_h005, _m005));
      final referentiel = Referentiel.fusionner(
        lecture.entrees,
        fusions: kFusions,
      );
      for (final f in kFusions) {
        final doc = referentiel.entree(f.id);
        expect(doc, isNotNull, reason: f.id);
        expect(doc!.nom, f.nom);
        expect(h[f.id]!['name'], f.nom);
        for (final d in f.entrees) {
          expect(doc.entrees.where(d.designe), isNotEmpty, reason: '$d');
        }
        if (f.origine case final o?) expect(h[f.id]!['origin'], o);
        for (final a in f.alias) {
          expect(h[f.id]!['aliases'], contains(a), reason: f.id);
        }
      }
    });

    test('Saaz : nom court tchèque, culture américaine à part', () {
      final saaz = h['hop-saaz']!;
      expect(saaz['name'], 'Saaz');
      expect(saaz['origin'], 'Czech Republic');
      expect(saaz['alpha_acid'], {'value': 31.7, 'unit': '%'}, reason: '003');
      expect(saaz['aliases'], ['Saaz (CZ)', 'Saaz (Czech Republic)']);
      final us = h['hop-saaz-us']!;
      expect(us['origin'], 'United States');
      expect(us['alpha_acid'], {'value': 52.3, 'unit': '%'}, reason: '005');
      expect(us['aliases'], ['Saaz (USA)'], reason: '« Saaz » écarté');
      expect(_sourcesDe(us), {
        'brewtarget-005|Saaz',
        'brewtarget-003|18',
        'brewtarget-001|Saaz (USA)',
      });
      expect(h['hop-saaz-late']!['aliases'], isEmpty);
    });

    test('Magnum : allemand, entrée 005 américaine vers Magnum (US)', () {
      final magnum = h['hop-magnum']!;
      expect(magnum['origin'], 'Germany');
      expect(magnum['alpha_acid'], {'value': 52.0, 'unit': '%'});
      expect(magnum['aliases'], ['Magnum (GR)']);
      final us = h['hop-magnum-us']!;
      expect(us['alpha_acid'], {'value': 51.9, 'unit': '%'});
      expect(us['aliases'], isEmpty, reason: '« Magnum » écarté');
    });

    test(
      'Northern Brewer, Perle, Brewer\'s Gold : (GR) fusionné, (US) seul',
      () {
        for (final nom in ['Northern Brewer', 'Perle', "Brewer's Gold"]) {
          final id = idEntree(NatureReferentiel.hop, cleNormalisee(nom));
          expect(h[id]!['aliases'], ['$nom (GR)'], reason: nom);
          expect(h[id]!['origin'], 'Germany');
          expect(h['$id-us']!['origin'], 'United States');
        }
      },
    );

    test('East Kent Goldings : quatre noms, Grande-Bretagne', () {
      final ekg = h['hop-east-kent-goldings']!;
      expect(ekg['name'], 'East Kent Goldings');
      expect(ekg['origin'], 'Great Britain');
      expect(ekg['alpha_acid'], {'value': 50.4, 'unit': '%'}, reason: '005');
      expect(ekg['aliases'], [
        'East Kent Golding',
        'East Kent Goldings (EKG)',
        'East Kent Goldings (EKG) (1)',
      ]);
    });

    test('Hallertau : noms du 005 gardés, noms du 003 en alias', () {
      expect(h['hop-hallertauer-blanc']!['aliases'], ['Hallertau Blanc']);
      expect(h['hop-hallertauer-gold']!['aliases'], ['Hallertau Gold']);
      expect(h['hop-hallertauer-tradition']!['aliases'], [
        'Hallertau Tradition',
      ]);
      final taurus = h['hop-hallertauer-taurus']!;
      expect(taurus['origin'], 'Germany');
      expect(taurus['aliases'], ['Hallertau Taurus']);
      final mittelfruh = h['hop-hallertauer-mittelfruh']!;
      expect(mittelfruh['name'], 'Hallertauer Mittelfrüh');
      expect(mittelfruh['aliases'], [
        'Hallertau',
        'Hallertau Mittelfrüh',
        'Hallertauer Mittelfrueh',
      ]);
      expect(h['hop-hallertau-nz']!['aliases'], isEmpty);
      expect(h['hop-hallertau-us']!['aliases'], isEmpty);
    });

    test('Tettnang, Sultana, Columbus', () {
      expect(h['hop-tettnang']!['aliases'], ['Tettnanger']);
      expect(h['hop-tettnang-us']!['aliases'], isEmpty);
      expect(h['hop-sultana']!['aliases'], ['Denali', 'Sultana (Denali)']);
      expect(h['hop-columbus']!['aliases'], [
        'CTZ',
        'Columbus/Tomahawk/Zeus',
        'Columbus/Tomahawk/Zeus (CTZ)',
        'Tomahawk',
        'Zeus',
      ]);
    });

    test('résolution d\'un nom à l\'import (IndexBibliotheque)', () {
      final index = indexHoublons(p.collections['beer_hops']);
      const attendu = {
        'Saaz': 'hop-saaz',
        'saaz (cz)': 'hop-saaz',
        'Saaz (USA)': 'hop-saaz-us',
        'Hallertau': 'hop-hallertauer-mittelfruh',
        'Hallertau Mittelfrüh': 'hop-hallertauer-mittelfruh',
        'Tettnanger': 'hop-tettnang',
        'CTZ': 'hop-columbus',
        'Zeus': 'hop-columbus',
        'Denali': 'hop-sultana',
        'Magnum': 'hop-magnum',
        'East Kent Golding': 'hop-east-kent-goldings',
      };
      for (final MapEntry(:key, :value) in attendu.entries) {
        expect(index.resoudre(key)?.id, value, reason: key);
        expect(index.correspondances(key), 1, reason: key);
      }
    });

    test('groupes de même nom sans parenthèse, pour la revue suivante', () {
      final groupes = {
        for (final g in p.rapport['groupes_sans_parenthese']! as List)
          (g as Map)['name']: g['ids'],
      };
      expect(groupes['saaz'], ['hop-saaz', 'hop-saaz-us']);
      expect(groupes['hallertau'], ['hop-hallertau-nz', 'hop-hallertau-us']);
    });

    test('table de fusion au rapport : document et entrées', () {
      final table = p.rapport['table_de_fusion']! as List;
      expect(table, hasLength(kFusions.length));
      final saaz = table.first as Map;
      expect(saaz['id'], 'hop-saaz');
      expect(saaz['origin'], 'Czech Republic');
      expect(saaz['entrees'], [
        {
          'source': 'brewtarget-003',
          'name': 'Saaz (CZ)',
          'origin': 'Czech Republic',
        },
        {
          'source': 'brewtarget-001',
          'name': 'Saaz (Czech Republic)',
          'origin': 'Czech Republic',
        },
      ]);
    });
  });

  group('table fausse : préparation arrêtée', () {
    test('ligne qui ne désigne aucune entrée', () {
      expect(
        () => _preparer(
          h003: [
            for (final e in _h003)
              if (e.$1 != 'Sultana (Denali)') e,
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Sultana'),
          ),
        ),
      );
    });

    test('entrée désignée par deux lignes, ligne en double', () {
      const perle = EntreeDesignee(Source.brewtarget003, 'Perle (GR)');
      expect(
        () => _preparer(
          fusions: const [
            Fusion('Perle', entrees: [perle]),
            Fusion('Perle (US)', entrees: [perle]),
          ],
        ),
        throwsStateError,
      );
      expect(
        () => _preparer(
          fusions: const [
            Fusion('Perle', entrees: [perle]),
            Fusion('perle', entrees: [perle]),
          ],
        ),
        throwsStateError,
      );
    });

    test('nom porté par deux houblons', () {
      expect(
        () => _preparer(
          fusions: const [
            Fusion(
              'Sultana',
              entrees: [
                EntreeDesignee(Source.brewtarget003, 'Sultana (Denali)'),
              ],
              alias: ['Perle'],
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('perle'),
          ),
        ),
      );
    });

    test('sans la table : hop-saaz se dit américain', () {
      // Sans fusion, les deux entrées 005 « Saaz » américaines donnent leurs
      // valeurs à hop-saaz (cause d'ADR-014).
      final h = _houblons(_preparer(fusions: const []));
      expect(h['hop-saaz']!['origin'], 'United States');
    });
  });
}
