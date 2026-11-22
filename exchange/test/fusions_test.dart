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
  // Documents à part dans le 003, absorbés par Columbus.
  ('CTZ', 'United States of America (USA)', 30.31),
  ('Tomahawk', 'United States of America (USA)', 30.32),
  ('Zeus', 'United States of America (USA)', 30.33),
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
  // La table et les corrections des cultures du projet désignent des entrées
  // absentes de ces sources : elles sont essayées par les groupes « table de
  // fusion des cultures » et « corrections des cultures de Brewtarget ».
  fusionsCultures: const [],
  correctionsCultures: const [],
);

/// Culture inventée : nom, atténuation minimale (la maximale vaut + 4).
typedef _Culture = (String nom, int attenuation);

/// Fiches inventées du producteur `Labo Fictif`, sans référence.
const List<_Culture> _fiches = [('Souche Courte', 80), ('Autre Fiche', 70)];

/// Cultures inventées du fichier 004, même producteur, sans référence.
const List<_Culture> _c004 = [
  ('Souche Courte Belge', 60),
  ('Souche Seule', 65),
];

String _texteFiches(
  List<_Culture> fiches, {
  String producteur = 'Labo Fictif',
}) => jsonEncode({
  'beerjson': {
    'version': 2.01,
    'cultures': [
      for (final (nom, att) in fiches)
        {
          'id': '${cleProducteur(producteur)}-${cleNormalisee(nom)}',
          'name': nom,
          'type': 'ale',
          'form': 'liquid',
          'producer': producteur,
          'attenuation_range': {
            'minimum': {'unit': '%', 'value': att},
            'maximum': {'unit': '%', 'value': att + 4},
          },
        },
    ],
  },
});

String _texte004(
  List<_Culture> cultures, {
  String? produit,
  String producteur = 'Labo Fictif',
}) => jsonEncode({
  'beerjson': {
    'version': 2.01,
    'cultures': [
      for (final (nom, att) in cultures)
        {
          'name': nom,
          'product_id': ?produit,
          'type': 'ale',
          'form': 'liquid',
          'producer': producteur,
          'attenuation_range': {
            'minimum': {'unit': '%', 'value': att},
            'maximum': {'unit': '%', 'value': att + 4},
          },
        },
    ],
  },
});

/// Référentiel des cultures inventées, avec la table [table].
Referentiel _cultures(
  List<FusionCulture> table, {
  List<_Culture> fiches = _fiches,
  List<_Culture> c004 = _c004,
  String? produit004,
}) {
  final lecture =
      LectureReferentiels(
          datesReleveFabricants: const {'labo-fictif': '2026-11-01'},
        )
        ..lire003ou004(
          _texte004(c004, produit: produit004),
          Source.brewtarget004,
        )
        ..lireFabricants(_texteFiches(fiches));
  return Referentiel.fusionner(lecture.entrees, fusionsCultures: table);
}

/// Cultures du fichier 005 (DotBeer), atténuations inventées.
String _texte005Cultures(List<_Culture> cultures, String producteur) =>
    jsonEncode({
      'DotBeer': {
        'version': '1.0.0',
        'cultures': [
          for (final (nom, att) in cultures)
            {
              'name': nom,
              'folder_path': 'Fictif',
              'culture_type': 'ale',
              'form': 'liquid',
              'producer': producteur,
              'attenuation_range': {
                'minimum': {'unit': '%', 'value': att},
                'maximum': {'unit': '%', 'value': att + 4},
              },
            },
        ],
      },
    });

/// Sources des lignes de [kFusionsCultures] : noms des souches seuls (fiches
/// et cibles Brewtarget de la table), atténuations inventées (P20).
/// Brewtarget écrit la cible de « St. Lucifer » avec et sans point (005,
/// 004) ; celle de « Chaudron Sûr » n'est que dans le 005.
const _escarpment = 'Escarpment Labs';
const List<_Culture> _fichesEscarpment = [
  ('Ardennes Ale', 81),
  ('Classic Wit', 82),
  ('Fruity Wit', 83),
  ('Fruit Bomb Saison Blend', 84),
  ('New World Saison Blend', 85),
  ('St. Lucifer', 86),
  ('Chaudron Sûr', 87),
];
const List<_Culture> _c005Escarpment = [
  ('Ardennes Belgian Ale', 51),
  ('Classic Witbier', 52),
  ('Fruity Witbier', 53),
  ('Fruit Bomb Saison', 54),
  ('New World Saison', 55),
  ('St. Lucifer Belgian Ale', 56),
  ('Lactobacillus Blend', 57),
];
const List<_Culture> _c004Escarpment = [
  ('Ardennes Belgian Ale', 41),
  ('Classic Witbier', 42),
  ('Fruity Witbier', 43),
  ('Fruit Bomb Saison', 44),
  ('New World Saison', 45),
  ('St Lucifer Belgian Ale', 46),
];

const _ligneCourte = FusionCulture(
  'Labo Fictif',
  'Souche Courte',
  nomBrewtarget: 'Souche Courte Belge',
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
        expect(index.candidats(key), [value], reason: key);
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

  test('Private Collection de Wyeast : la fiche et les entrées « -PC » '
      'font un seul document', () {
    String culture(String nom, String producteur, String produit, int att) =>
        jsonEncode({
          'name': nom,
          'product_id': produit,
          'type': 'ale',
          'form': 'liquid',
          'producer': producteur,
          'attenuation_range': {
            'minimum': {'unit': '%', 'value': att},
            'maximum': {'unit': '%', 'value': att + 4},
          },
        });
    String fichier(List<String> cultures) =>
        '{"beerjson": {"version": 2.01, "cultures": [${cultures.join(',')}]}}';
    final lecture =
        LectureReferentiels(
            datesReleveFabricants: const {'wyeast': '2026-11-01'},
          )
          ..lire003ou004(
            fichier([
              culture('Souche Fictive', 'Wyeast Labs', 'WY9999-PC', 60),
              culture('Autre Fictive', 'Wyeast Labs', 'WY9998-PC', 61),
            ]),
            Source.brewtarget003,
          )
          ..lire003ou004(
            fichier([culture('Souche Fictive', 'Wyeast', '9999-PC', 62)]),
            Source.brewtarget004,
          )
          ..lireFabricants(
            jsonEncode({
              'beerjson': {
                'version': 2.01,
                'cultures': [
                  {
                    ...jsonDecode(
                          culture('Souche Fictive', 'Wyeast', '9999', 80),
                        )
                        as Map<String, Object?>,
                    'id': 'wyeast-9999',
                  },
                ],
              },
            }),
          );
    final r = Referentiel.fusionner(lecture.entrees);
    final c = r.parNature[NatureReferentiel.culture]!;
    expect(c.keys, {
      'culture-wyeast-9999-souche-fictive',
      'culture-wyeast-9998-autre-fictive',
    });
    final doc = c['culture-wyeast-9999-souche-fictive']!;
    expect(doc.entrees, hasLength(3));
    expect(doc.principale.source, Source.fabricants);
    expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
  });

  group('corrections des cultures de Brewtarget', () {
    /// Culture inventée d'un fichier 004 : nom, producteur, référence.
    String culture(String nom, String producteur, String? produit) =>
        jsonEncode({
          'name': nom,
          'product_id': ?produit,
          'type': 'ale',
          'form': 'liquid',
          'producer': producteur,
          'attenuation_range': {
            'minimum': {'unit': '%', 'value': 70},
            'maximum': {'unit': '%', 'value': 74},
          },
        });
    Referentiel fusionner(
      List<String> c004,
      List<String> c005,
      List<CorrectionCulture> corrections,
    ) {
      String fichier(List<String> c) =>
          '{"beerjson": {"version": 2.01, "cultures": [${c.join(',')}]}}';
      final lecture = LectureReferentiels(datesReleveFabricants: const {})
        ..lire003ou004(fichier(c004), Source.brewtarget004)
        ..lire003ou004(fichier(c005), Source.brewtarget003);
      return Referentiel.fusionner(
        lecture.entrees,
        correctionsCultures: corrections,
      );
    }

    Set<String> ids(Referentiel r) =>
        r.parNature[NatureReferentiel.culture]!.keys.toSet();

    test('référence lue : l\'entrée rejoint la souche retenue', () {
      final r = fusionner(
        [culture('Souche Courte', 'Labo Fictif', 'LF-7-SC')],
        [culture('Souche Courte', 'Labo Fictif', 'LF-7')],
        const [
          ReferenceCulture('Labo Fictif', lue: 'LF-7-SC', retenue: 'LF-7'),
        ],
      );
      expect(ids(r), {'culture-labo-fictif-lf7-souche-courte'});
      expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
    });

    test('entrée sans référence : elle prend la référence retenue', () {
      final r = fusionner(
        [culture('Souche Courte', 'Labo Fictif', null)],
        [culture('LF-7 Souche Courte Longue', 'Labo Fictif', 'LF-7')],
        const [
          ReferenceCulture(
            'Labo Fictif',
            nom: 'Souche Courte',
            retenue: 'LF-7',
          ),
        ],
      );
      expect(ids(r), hasLength(1));
      expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
    });

    test('nom de gamme : « <gamme> <référence> », une entrée sans référence '
        'garde son nom', () {
      final r = fusionner(
        [
          culture('Gamme', 'Labo Fictif', 'A-1'),
          culture('Gamme', 'Labo Fictif', 'B2'),
          culture('Gamme', 'Labo Fictif', null),
        ],
        const [],
        const [GammeCulture('Labo Fictif', 'Gamme')],
      );
      final c = r.parNature[NatureReferentiel.culture]!;
      expect(
        {for (final f in c.values) f.nom},
        {'Gamme A-1', 'Gamme B2', 'Gamme'},
      );
      expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
    });

    test('alias écarté : le nom sort des alias de la seule souche visée', () {
      final r = fusionner(
        [
          culture('Souche Longue', 'Labo Fictif', 'LF-1'),
          culture('Souche Courte', 'Labo Fictif', 'LF-2'),
        ],
        [culture('Souche Courte', 'Labo Fictif', 'LF-1')],
        const [
          AliasEcarteCulture(
            'Labo Fictif',
            reference: 'LF-1',
            alias: 'Souche Courte',
          ),
        ],
      );
      expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
      expect(
        r.parNature[NatureReferentiel.culture]!.values
            .firstWhere((f) => f.nom == 'Souche Longue')
            .aliases,
        isEmpty,
      );
    });

    test('même souche sans référence sous deux noms : un document, '
        'identifiant et valeurs de la source la plus prioritaire', () {
      // 004 (rang 2) porte « Nom Long Fictif », 003 lu ici comme second
      // fichier (rang 2 aussi) : l'ordre de lecture départage.
      final r = fusionner(
        [culture('Nom Long Fictif', 'Labo Fictif', null)],
        [culture('Nom Court Fictif', 'Labo Fictif', null)],
        const [
          MemeSoucheCulture(
            'Labo Fictif',
            nom: 'Nom Court Fictif',
            rejoint: 'Nom Long Fictif',
          ),
        ],
      );
      final c = r.parNature[NatureReferentiel.culture]!;
      expect(c.keys, {'culture-labo-fictif-nom-long-fictif'});
      expect(c.values.single.nom, 'Nom Long Fictif');
      expect(c.values.single.aliases, ['Nom Court Fictif']);
      expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
      // Une entrée avec référence n'est pas désignée.
      expect(
        () => fusionner(
          [culture('Nom Long Fictif', 'Labo Fictif', 'LF-1')],
          [culture('Nom Court Fictif', 'Labo Fictif', null)],
          const [
            MemeSoucheCulture(
              'Labo Fictif',
              nom: 'Nom Court Fictif',
              rejoint: 'Nom Long Fictif',
            ),
          ],
        ),
        throwsStateError,
      );
    });

    test('doublons d\'un même producteur : seuls les noms partagés chez un '
        'même producteur, « Labs » rapproché', () {
      final r = fusionner(
        [
          culture('Souche Courte', 'Wyeast', '1001'),
          culture('Souche Courte', 'Wyeast Labs', '1002'),
          culture('Autre Souche', 'Labo Fictif', 'LF-1'),
          culture('Autre Souche', 'Autre Labo', 'AL-1'),
        ],
        const [],
        const [],
      );
      expect(r.nomsPartages(NatureReferentiel.culture).keys, {
        'souche-courte',
        'autre-souche',
      });
      expect(r.doublonsMemeProducteur().keys, {'souche-courte'});
    });

    test('nom de gamme : le nom construit est coupé à 120 caractères', () {
      final longue = 'R${'1' * 119}';
      final r = fusionner(
        [culture('Gamme', 'Labo Fictif', longue)],
        const [],
        const [GammeCulture('Labo Fictif', 'Gamme')],
      );
      final nom = r.parNature[NatureReferentiel.culture]!.values.single.nom;
      expect(nom, hasLength(120));
      expect(nom, startsWith('Gamme R1'));
    });

    test(
      'ligne qui ne désigne rien, entrée corrigée deux fois : StateError',
      () {
        final c = [culture('Souche Courte', 'Labo Fictif', 'LF-7')];
        expect(
          () => fusionner(c, const [], const [
            ReferenceCulture('Labo Fictif', lue: 'LF-9', retenue: 'LF-7'),
          ]),
          throwsStateError,
        );
        expect(
          () =>
              fusionner(c, const [], const [GammeCulture('Labo Fictif', 'X')]),
          throwsStateError,
        );
        expect(
          () => fusionner(c, const [], const [
            AliasEcarteCulture('Labo Fictif', reference: 'LF-7', alias: 'X'),
          ]),
          throwsStateError,
        );
        expect(
          () => fusionner(
            [culture('Gamme', 'Labo Fictif', 'LF-7')],
            const [],
            const [
              GammeCulture('Labo Fictif', 'Gamme'),
              ReferenceCulture('Labo Fictif', lue: 'LF-7', retenue: 'LF-8'),
            ],
          ),
          throwsStateError,
        );
      },
    );

    test('chaque ligne de kCorrectionsCultures, sur ses noms et références', () {
      // Noms et références des souches visées seuls, valeurs inventées (P20).
      final r = fusionner(
        [
          culture('C2C American Farmhouse', 'Omega Yeast', 'OYL-217-C2C'),
          culture('Saison #1', 'GigaYeast', 'GY018-SAISON-1'),
          culture('Saison #2', 'GigaYeast', 'GY027-SAISON-2'),
          culture('Sweet Flemish Brett', 'GigaYeast', 'GY144'),
          culture('Saison Blend', 'The Yeast Bay', null),
          culture('Prise de Mousse Wine', 'Lallemand', 'LALVIN-EC-1118'),
          culture('Lalvin', 'Lallemand', '71B'),
          culture('SafSpirit', 'Fermentis', 'HG-1'),
          culture('Fermoale', 'AEB', 'AY3'),
          culture('Bavarian Wheat Blend', 'Wyeast', '3056'),
          culture('British Ale II', 'Wyeast', '1335'),
          culture('Lactobacillus buchneri', 'Wyeast', '5335'),
          culture('LalBrew Belle Saison', 'Lallemand', null),
        ],
        [
          culture('C2C American Farmhouse', 'Omega Yeast', 'OYL-217'),
          culture('Saison #1', 'GigaYeast', 'GY018'),
          culture('Saison #2', 'GigaYeast', 'GY027'),
          culture('Sweet Flemish Brett', 'GigaYeast', 'GB144'),
          culture('Saison Blend', 'The Yeast Bay', 'WLP4007'),
          culture('Lalvin', 'Lallemand', 'EC-1118'),
          culture('Bavarian Wheat', 'Wyeast', '3056'),
          culture('British Ale', 'Wyeast', '1335'),
          culture('Lactobacillus', 'Wyeast', '5335'),
          culture('Belle Saison Belgian Saison-Style', 'Lallemand', null),
        ],
        kCorrectionsCultures,
      );
      final c = r.parNature[NatureReferentiel.culture]!;
      expect(c, hasLength(13));
      // Les deux Belle Saison de Lallemand : un document, à l'identifiant de
      // l'entrée lue la première (004 ici ; 005 en production).
      expect(c['culture-lallemand-lalbrew-belle-saison']?.aliases, [
        'Belle Saison Belgian Saison-Style',
      ]);
      expect({
        for (final f in c.values) f.nom,
      }, containsAll(['Lalvin 71B', 'SafSpirit HG-1', 'Fermoale AY3']));
      // « Prise de Mousse Wine » (`LALVIN-EC-1118`) rejoint la souche EC-1118 :
      // un seul document porte les deux noms.
      expect(
        c.values.where(
          (f) => {
            f.nom,
            ...f.aliases,
          }.containsAll(['Lalvin EC-1118', 'Prise de Mousse Wine']),
        ),
        hasLength(1),
      );
      for (final f in c.values) {
        expect(f.aliases, isNot(contains('Bavarian Wheat')), reason: f.id);
        expect(f.aliases, isNot(contains('British Ale')), reason: f.id);
        expect(f.aliases, isNot(contains('Lactobacillus')), reason: f.id);
      }
      expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
    });
  });

  group('table de fusion des cultures', () {
    test('sans la table : la fiche crée un second document', () {
      final c = _cultures(const []).parNature[NatureReferentiel.culture]!;
      expect(c.keys, {
        'culture-labo-fictif-souche-courte',
        'culture-labo-fictif-souche-courte-belge',
        'culture-labo-fictif-autre-fiche',
        'culture-labo-fictif-souche-seule',
      });
    });

    test('la fiche rejoint le document Brewtarget : même identifiant, '
        'valeurs et nom de la fiche, nom Brewtarget en alias', () {
      expect(_ligneCourte.id, 'culture-labo-fictif-souche-courte-belge');
      final r = _cultures(const [_ligneCourte]);
      final c = r.parNature[NatureReferentiel.culture]!;
      expect(c.keys, {
        'culture-labo-fictif-souche-courte-belge',
        'culture-labo-fictif-autre-fiche',
        'culture-labo-fictif-souche-seule',
      });
      final doc = c['culture-labo-fictif-souche-courte-belge']!.document();
      expect(doc['name'], 'Souche Courte');
      expect(doc['aliases'], ['Souche Courte Belge']);
      expect(doc['attenuation'], {
        'minimum': {'unit': '%', 'value': 80},
        'maximum': {'unit': '%', 'value': 84},
      });
      expect(
        [for (final l in doc['provenance']! as List) (l as Map)['source']],
        ['fabricants', 'brewtarget-004'],
      );
      expect(
        r.parNomExact(NatureReferentiel.culture, 'Souche Courte'),
        'culture-labo-fictif-souche-courte-belge',
      );
      expect(
        r.parNomExact(NatureReferentiel.culture, 'Souche Courte Belge'),
        'culture-labo-fictif-souche-courte-belge',
      );
    });

    test('ligne sans fiche ou sans entrée Brewtarget : StateError', () {
      expect(
        () => _cultures(const [_ligneCourte], fiches: [_fiches.last]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('aucune fiche'),
          ),
        ),
      );
      expect(
        () => _cultures(const [_ligneCourte], c004: [_c004.last]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('aucune entrée Brewtarget'),
          ),
        ),
      );
    });

    test('nom partagé par deux producteurs : deux documents, nom compté '
        'dans nomsPartages', () {
      final lecture =
          LectureReferentiels(
              datesReleveFabricants: const {
                'labo-fictif': '2026-11-01',
                'autre-labo': '2026-11-01',
              },
            )
            ..lireFabricants(_texteFiches(const [('Souche Courte', 80)]))
            ..lireFabricants(
              _texteFiches(const [
                ('Souche Courte', 70),
              ], producteur: 'Autre Labo'),
            );
      final r = Referentiel.fusionner(lecture.entrees);
      expect(r.parNature[NatureReferentiel.culture]!.keys, {
        'culture-labo-fictif-souche-courte',
        'culture-autre-labo-souche-courte',
      });
      expect(r.nomsPartages(NatureReferentiel.culture), {
        'souche-courte': [
          'culture-autre-labo-souche-courte',
          'culture-labo-fictif-souche-courte',
        ],
      });
    });

    test('cible Brewtarget qui porte une référence : StateError', () {
      // Avec la référence, l'identifiant de la cible est celui de sa souche
      // (`culture-labo-fictif-lf9-souche-courte-belge`) : la ligne créerait
      // un document à côté de l'ancien.
      expect(
        () => _cultures(
          const [_ligneCourte],
          c004: [_c004.first],
          produit004: 'LF9',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('a pour identifiant'),
          ),
        ),
      );
    });

    test('ligne en double, entrée désignée par deux lignes : StateError', () {
      expect(
        () => _cultures(const [
          _ligneCourte,
          FusionCulture(
            'Labo Fictif',
            'Autre Fiche',
            nomBrewtarget: 'Souche Courte Belge',
          ),
        ]),
        throwsStateError,
      );
      expect(
        () => _cultures(const [
          _ligneCourte,
          FusionCulture(
            'Labo Fictif',
            'Souche Courte',
            nomBrewtarget: 'Souche Seule',
          ),
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('désignée par'),
          ),
        ),
      );
    });

    test(
      'chaque ligne de kFusionsCultures : document, entrées, nom, alias',
      () {
        final lecture =
            LectureReferentiels(
                datesReleveFabricants: const {'escarpment-labs': '2026-11-01'},
              )
              ..lire003ou004(
                _texte004(_c004Escarpment, producteur: _escarpment),
                Source.brewtarget004,
              )
              ..lire005(_texte005Cultures(_c005Escarpment, _escarpment))
              ..lireFabricants(
                _texteFiches(_fichesEscarpment, producteur: _escarpment),
              );
        final r = Referentiel.fusionner(
          lecture.entrees,
          fusionsCultures: kFusionsCultures,
        );
        const tous = {'fabricants', 'brewtarget-005', 'brewtarget-004'};
        const attendu = {
          'Ardennes Ale': (
            'culture-escarpment-labs-ardennes-belgian-ale',
            tous,
            ['Ardennes Belgian Ale'],
          ),
          'Classic Wit': (
            'culture-escarpment-labs-classic-witbier',
            tous,
            ['Classic Witbier'],
          ),
          'Fruity Wit': (
            'culture-escarpment-labs-fruity-witbier',
            tous,
            ['Fruity Witbier'],
          ),
          'Fruit Bomb Saison Blend': (
            'culture-escarpment-labs-fruit-bomb-saison',
            tous,
            ['Fruit Bomb Saison'],
          ),
          'New World Saison Blend': (
            'culture-escarpment-labs-new-world-saison',
            tous,
            ['New World Saison'],
          ),
          'St. Lucifer': (
            'culture-escarpment-labs-st-lucifer-belgian-ale',
            tous,
            ['St Lucifer Belgian Ale', 'St. Lucifer Belgian Ale'],
          ),
          'Chaudron Sûr': (
            'culture-escarpment-labs-lactobacillus-blend',
            {'fabricants', 'brewtarget-005'},
            ['Lactobacillus Blend'],
          ),
        };
        expect(kFusionsCultures.map((f) => f.nom), attendu.keys);
        expect(
          r.parNature[NatureReferentiel.culture],
          hasLength(kFusionsCultures.length),
        );
        for (final f in kFusionsCultures) {
          final (id, sources, alias) = attendu[f.nom]!;
          expect(f.id, id, reason: f.nom);
          final doc = r.entree(id);
          expect(doc, isNotNull, reason: f.nom);
          expect(doc!.entrees.where(f.designeFiche), hasLength(1));
          expect(doc.principale.source, Source.fabricants, reason: f.nom);
          expect(
            doc.entrees.where(f.designeBrewtarget),
            hasLength(sources.length - 1),
            reason: f.nom,
          );
          expect(doc.entrees.map((e) => e.source.id).toSet(), sources);
          final data = doc.document();
          expect(data['name'], f.nom);
          expect(data['aliases'], alias, reason: f.nom);
          expect(data['aliases'], contains(f.nomBrewtarget));
          final fiche = _fichesEscarpment.firstWhere((c) => c.$1 == f.nom);
          expect(
            ((data['attenuation']! as Map)['minimum'] as Map)['value'],
            fiche.$2,
            reason: f.nom,
          );
        }
        // P56, nature `culture` : la table ne laisse aucun nom normalisé
        // partagé entre deux documents de ce référentiel.
        expect(r.nomsPartages(NatureReferentiel.culture), isEmpty);
      },
    );

    test(
      'table du projet : une ligne par identifiant, une fiche par ligne',
      () {
        expect(
          kFusionsCultures.map((f) => f.id).toSet(),
          hasLength(kFusionsCultures.length),
        );
        expect(
          kFusionsCultures.map((f) => cleNormalisee(f.nom)).toSet(),
          hasLength(kFusionsCultures.length),
        );
      },
    );
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
