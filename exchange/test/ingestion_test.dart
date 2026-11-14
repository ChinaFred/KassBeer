import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:crypto/crypto.dart';
import 'package:exchange/ingestion.dart';
import 'package:test/test.dart';

/// Préparation de l'ingestion (ADR-005, L3) sur des fixtures écrites à la main
/// (`test/fixtures/ingestion/`) : entrées inventées, dans la forme des
/// fichiers de Brewtarget et de DIY Dog. Aucun extrait de source (P20).

const _dossier = 'test/fixtures/ingestion';

/// Table d'alias des fixtures.
const _alias = [
  Alias(
    NatureReferentiel.fermentable,
    'Pale Fictif',
    'fermentable-malt-moulin-fictif',
    labelFr: 'Malt pâle fictif',
  ),
  Alias(NatureReferentiel.hop, 'H. Test', 'hop-houblon-test'),
  Alias(
    NatureReferentiel.misc,
    'Poudre Test',
    'misc-poudre-fictive',
    labelFr: 'Poudre fictive',
  ),
];

const _ajouts = ['Fruit Inconnu', 'Jus Fictif'];

SourcesBrutes _sources() {
  String texte(String f) => File('$_dossier/brewtarget/$f').readAsStringSync();
  return SourcesBrutes(
    octets001: File('$_dossier/brewtarget/001.xml').readAsBytesSync(),
    texte002: texte('002.json'),
    texte003: texte('003.json'),
    texte004: texte('004.json'),
    texte005: texte('005.beer'),
    texteFabricants: File('$_dossier/fabricants/vide.json').readAsStringSync(),
    diyDog: [
      for (final f in ['001.json', '002.json'])
        (fichier: f, texte: File('$_dossier/diydog/$f').readAsStringSync()),
    ],
  );
}

Preparation _preparer() =>
    preparer(_sources(), alias: _alias, ajoutsDansHoublons: _ajouts);

/// Données du document [id] de [collection].
Map<String, Object?> _doc(Preparation p, String collection, String id) {
  final d = p.collections[collection]!.where((e) => e['id'] == id);
  expect(d, hasLength(1), reason: '$collection/$id');
  return d.single['data']! as Map<String, Object?>;
}

/// Toutes les clés et tous les textes de [valeur], récursivement.
void _parcourir(
  Object? valeur,
  void Function(String cle) surCle,
  void Function(String texte) surTexte,
) {
  switch (valeur) {
    case Map():
      for (final MapEntry(:key, :value) in valeur.entries) {
        surCle('$key');
        _parcourir(value, surCle, surTexte);
      }
    case List():
      for (final v in valeur) {
        _parcourir(v, surCle, surTexte);
      }
    case String():
      surTexte(valeur);
  }
}

void main() {
  group('identifiants', () {
    test(
      'clé normalisée : minuscules, sans accents, tirets, 100 caractères',
      () {
        expect(cleNormalisee('Pale Malt (2 Row) UK'), 'pale-malt-2-row-uk');
        expect(cleNormalisee('  Épice — Été  '), 'epice-ete');
        expect(
          cleNormalisee('Wyeast 1056 - American Ale™'),
          'wyeast-1056-american-ale',
        );
        expect(cleNormalisee('™ —'), isEmpty);
        final longue = cleNormalisee('${'a' * 99} bcd');
        expect(longue, 'a' * 99);
      },
    );

    test('style, recette, exécution et non résolu', () {
      expect(idStyle('21A'), 'bjcp2021-21a');
      expect(idRecetteDiyDog(1), 'diydog-1');
      final id = idNonResolu(NatureReferentiel.fermentable, 'Extra Pale');
      expect(id, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        id,
        sha256.convert(utf8.encode('fermentable|extra-pale')).toString(),
      );
      expect(idNonResolu(NatureReferentiel.fermentable, 'EXTRA  pale'), id);
    });

    test('clé de culture : producteur, référence, nom sans répétition', () {
      expect(
        cleCulture('WLP001 - California Ale Yeast', 'White Labs', '001'),
        'white-labs-wlp001-california-ale',
      );
      expect(
        cleCulture('American Ale', 'Wyeast Labs', 'WY1056'),
        'wyeast-1056-american-ale',
      );
      expect(
        cleCulture('Wyeast Bohemian Ale Blend', 'Wyeast', '1087'),
        'wyeast-1087-bohemian-ale-blend',
      );
      expect(cleCulture('Yeast', null, null), 'yeast');
      expect(
        cleProduit('fermentis', 'W-34/70'),
        cleProduit('fermentis', 'W34/70'),
      );
    });

    test('empreinte du contenu : canonique, sans content_sha256', () {
      final a = empreinteContenu({'b': 1, 'a': 2.0});
      expect(a, empreinteContenu({'a': 2, 'b': 1}));
      expect(a, isNot(empreinteContenu({'a': 2, 'b': 2})));
      expect(
        () => empreinteContenu({'content_sha256': 'x'}),
        throwsArgumentError,
      );
    });

    test('souche lue dans un nom de DIY Dog', () {
      expect(soucheDuNom('Wyeast 1272 - American Ale II™'), (
        producteur: 'Wyeast',
        produit: '1272',
      ));
      expect(soucheDuNom('WLP099 - Super High Gravity Ale'), (
        producteur: 'White Labs',
        produit: 'WLP099',
      ));
      expect(soucheDuNom('Champagne'), isNull);
    });
  });

  test('JSON à commentaires : lignes en // retirées, le reste refusé', () {
    expect(
      () => lireJsonCommente('{\n  "a": 1 // fin\n}'),
      throwsFormatException,
    );
    expect(
      lireJsonCommente(
        '// en-tête\n{\n    // bloc\n  "a": "http://exemple.fr"\n}',
      ),
      {'a': 'http://exemple.fr'},
    );
  });

  group('référentiels', () {
    late Preparation p;
    setUpAll(() => p = _preparer());

    test('fusion : 005 donne les valeurs, chaque source sa provenance', () {
      final malt = _doc(p, 'beer_fermentables', 'fermentable-malt-imaginaire');
      expect(malt['name'], 'Malt Imaginaire');
      expect(malt['type'], 'grain');
      expect(malt['yield'], {
        'fine_grind': {'value': 81.0, 'unit': '%'},
      });
      expect(malt['color'], {'value': 4.0, 'unit': 'EBC'});
      expect(malt['origin'], isNull, reason: 'valeurs du seul 005');
      expect(malt['aliases'], isEmpty);
      final provenance = malt['provenance']! as List;
      expect(provenance, [
        {
          'source': 'brewtarget-005',
          'source_id': 'Malt Imaginaire',
          'version': 'v5.2.3 ea10908',
          'licence': 'CC BY-SA 4.0',
          'retrieved': '2026-11-08',
        },
        {
          'source': 'brewtarget-001',
          'source_id': 'Malt Imaginaire',
          'version': 'v5.2.3 ea10908',
          'licence': 'GPL-3.0',
          'retrieved': '2026-11-08',
        },
      ]);
    });

    test('licence du 005 selon folder_path', () {
      final swaen = _doc(
        p,
        'beer_fermentables',
        'fermentable-malt-moulin-fictif',
      );
      expect(
        (swaen['provenance']! as List).single,
        containsPair('licence', 'GPL-3.0'),
      );
      final sel = _doc(p, 'beer_miscs', 'misc-sel-fictif');
      expect(
        (sel['provenance']! as List).single,
        containsPair('licence', 'GPL-3.0'),
      );
      final poudre = _doc(p, 'beer_miscs', 'misc-poudre-fictive');
      expect(
        (poudre['provenance']! as List).single,
        containsPair('licence', 'CC BY-SA 4.0'),
      );
    });

    test('couleurs converties par brewing/, Lovibond, SRM et EBC', () {
      final swaen = _doc(
        p,
        'beer_fermentables',
        'fermentable-malt-moulin-fictif',
      );
      expect(swaen['color'], {
        'value': arrondi(lovibondToEbc(2), 1),
        'unit': 'EBC',
      });
      final extrait = _doc(
        p,
        'beer_fermentables',
        'fermentable-extrait-fictif',
      );
      expect(extrait['type'], 'extract');
      expect(extrait['color'], {
        'value': arrondi(srmToEbc(3), 1),
        'unit': 'EBC',
      });
      final adjuvant = _doc(
        p,
        'beer_fermentables',
        'fermentable-adjuvant-fictif',
      );
      expect(adjuvant['type'], 'grain', reason: 'Adjunct donne grain');
    });

    test('rendement et acide alpha à 0 écartés et notés', () {
      final sucre = _doc(p, 'beer_fermentables', 'fermentable-sucre-nul');
      expect(sucre.containsKey('yield'), isFalse);
      final second = _doc(p, 'beer_hops', 'hop-houblon-second');
      expect(second.containsKey('alpha_acid'), isFalse);
      final ecartees =
          (p.rapport['valeurs_ecartees']! as Map)['lignes']! as List;
      expect(
        ecartees,
        contains(
          equals({
            'source': 'brewtarget-001',
            'nom': 'Sucre Nul',
            'champ': 'YIELD',
            'raison': 'valeur nulle',
          }),
        ),
      );
    });

    test('houblon : 005 prioritaire, alias de la table, usage', () {
      final h = _doc(p, 'beer_hops', 'hop-houblon-test');
      expect(h['alpha_acid'], {'value': 7.0, 'unit': '%'});
      expect(h['purpose'], 'aroma');
      expect(h['aliases'], ['H. Test']);
      expect((h['provenance']! as List).map((l) => (l as Map)['source']), [
        'brewtarget-005',
        'brewtarget-003',
        'brewtarget-001',
      ]);
    });

    test('cultures : même souche fusionnée, °F convertis, unité inconnue', () {
      final s = _doc(p, 'beer_cultures', 'culture-wyeast-9999-souche-fictive');
      expect(s['producer'], 'Wyeast');
      expect(s['product_id'], '9999');
      expect(s['temperature_range'], plage(16, 21, 'C'));
      expect(s['provenance'], hasLength(2));
      final l = _doc(
        p,
        'beer_cultures',
        'culture-labo-fictif-lf1-levure-test-ale',
      );
      expect(l['temperature_range'], plage(15, 22.2, 'C'));
      expect(l['attenuation'], plage(70, 80, '%'));
      expect(l['flocculation'], 'medium');
      expect(l['provenance'], hasLength(2));
      final k = _doc(
        p,
        'beer_cultures',
        'culture-autre-labo-fictif-levure-sans-unite',
      );
      expect(k.containsKey('temperature_range'), isFalse);
      expect(p.collections['beer_cultures'], hasLength(3));
    });

    test('ajouts, recettes et autres listes des sources écartées', () {
      expect(_doc(p, 'beer_miscs', 'misc-epice-test')['type'], 'spice');
      final ids = [
        for (final e in p.collections['beer_fermentables']!) e['id'],
      ];
      expect(ids, isNot(contains('fermentable-malt-de-recette')));
      expect(p.collections['beer_fermentables'], hasLength(5));
      expect(
        p.rapport['listes_ignorees'],
        containsPair('brewtarget-005:recipes', 1),
      );
    });

    test('styles : nom, code, classement et plages seuls', () {
      final s = _doc(p, 'beer_styles', 'bjcp2021-99a');
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
      expect(
        s['color'],
        plage(arrondi(srmToEbc(4), 1), arrondi(srmToEbc(6), 1), 'EBC'),
      );
      expect(s['international_bitterness_units'], plage(20, 30, 'IBUs'));
      expect(
        (s['provenance']! as List).single,
        containsPair('licence', 'BJCP (noms et plages)'),
      );
      final b = _doc(p, 'beer_styles', 'bjcp2021-99b');
      expect(b.containsKey('original_gravity'), isFalse);
    });

    test('beer_index : cinq documents triés, nombres nus', () {
      expect(
        [for (final d in p.collections['beer_index']!) d['id']],
        ['cultures', 'fermentables', 'hops', 'miscs', 'styles'],
      );
      final f = _doc(p, 'beer_index', 'fermentables');
      expect(f['count'], 5);
      final entrees = f['entries']! as List;
      expect(
        [for (final e in entrees) (e as Map)['name']],
        [
          'Adjuvant Fictif',
          'Extrait Fictif',
          'Malt Imaginaire',
          'Malt Moulin Fictif',
          'Sucre Nul',
        ],
      );
      expect(entrees[3], {
        'id': 'fermentable-malt-moulin-fictif',
        'name': 'Malt Moulin Fictif',
        'aliases': ['Pale Fictif'],
        'label_fr': 'Malt pâle fictif',
        'type': 'grain',
        'yield': 80.0,
        'color': arrondi(lovibondToEbc(2), 1),
      });
      final c = _doc(p, 'beer_index', 'cultures')['entries']! as List;
      expect(
        c.firstWhere(
          (e) => (e as Map)['id'] == 'culture-wyeast-9999-souche-fictive',
        ),
        {
          'id': 'culture-wyeast-9999-souche-fictive',
          'name': 'Souche Fictive',
          'producer': 'Wyeast',
          'product_id': '9999',
          'type': 'ale',
          'form': 'liquid',
          'attenuation': 74.0,
        },
      );
      final s = _doc(p, 'beer_index', 'styles')['entries']! as List;
      expect(s.last, {
        'id': 'bjcp2021-99b',
        'name': 'Style Sans Plage',
        'code': '99B',
        'category': 'Catégorie Fictive',
      });
      expect((s.first as Map)['og'], [1.04, 1.05]);
    });
  });

  group('recettes publiques', () {
    late Preparation p;
    late Map<String, Object?> d;
    late Map<String, Object?> recipe;
    late Map<String, Object?> ingredients;
    setUpAll(() {
      p = _preparer();
      d = _doc(p, 'public_recipes', 'diydog-1');
      recipe = d['recipe']! as Map<String, Object?>;
      ingredients = recipe['ingredients']! as Map<String, Object?>;
    });

    test('enveloppe de recipes/ et champs propres aux recettes publiques', () {
      expect(d.keys.toSet(), {
        'format_version',
        'owner_uid',
        'owner_name',
        'imported_from',
        'search_name',
        'recipe',
        'ingredient_refs',
        'source_hop_timing',
        'announced',
        'provenance',
        'content_sha256',
      });
      expect(d['format_version'], 1);
      expect(d['owner_uid'], 'system');
      expect(d['owner_name'], 'DIY Dog');
      expect(d['imported_from'], 'DIY Dog · diydog-1');
      expect(d['search_name'], 'biere inventee');
      expect(nomDeRecherche('Punk IPA 2007 - 2010'), 'punk ipa 2007 2010');
      expect(nomDeRecherche('  Élan   (Été)  '), 'elan ete');
      expect(d['provenance'], [
        {
          'source': 'diydog',
          'source_id': '1',
          'version': 'e6c12ab',
          'licence': 'DIY Dog (usage privé)',
          'retrieved': '2026-11-08',
        },
      ]);
    });

    test('recipe : clés acceptées par isBeerJsonRecipe, sans ébullition', () {
      expect(recipe.keys.toSet(), {
        'name',
        'author',
        'notes',
        'batch_size',
        'mash',
        'ingredients',
      });
      expect(recipe['name'], 'Bière Inventée');
      expect(recipe['author'], 'BrewDog');
      expect(recipe['notes'], 'Ajout inventé pour le test');
      expect(recipe['batch_size'], {'value': 20.0, 'unit': 'l'});
      expect(recipe['mash'], {
        'name': 'Empâtage',
        'mash_steps': [
          {
            'name': 'Palier 1',
            'type': 'infusion',
            'step_temperature': {'value': 65.0, 'unit': 'C'},
            'step_time': {'value': 60, 'unit': 'min'},
          },
        ],
      });
    });

    test('malts : valeurs recopiées de l\'entrée résolue (D4)', () {
      expect(ingredients['fermentable_additions'], [
        {
          'name': 'Malt Imaginaire',
          'type': 'grain',
          'amount': {'value': 4500.0, 'unit': 'g'},
          'yield': {
            'fine_grind': {'value': 81.0, 'unit': '%'},
          },
          'color': {'value': 4.0, 'unit': 'EBC'},
        },
        {
          'name': 'Pale Fictif',
          'type': 'grain',
          'amount': {'value': 500.0, 'unit': 'g'},
          'yield': {
            'fine_grind': {'value': 80.0, 'unit': '%'},
          },
          'color': {'value': arrondi(lovibondToEbc(2), 1), 'unit': 'EBC'},
        },
        {
          'name': 'Nom Inconnu',
          'type': 'grain',
          'amount': {'value': 250.0, 'unit': 'g'},
        },
      ]);
    });

    test('houblons : moments, acide de la source gardé, libellés', () {
      expect(ingredients['hop_additions'], [
        {
          'name': 'Houblon Test',
          'amount': {'value': 20.0, 'unit': 'g'},
          'timing': {'use': 'add_to_boil'},
          'alpha_acid': {'value': 7.0, 'unit': '%'},
        },
        {
          'name': 'Houblon Test',
          'amount': {'value': 10.0, 'unit': 'g'},
          'timing': {
            'use': 'add_to_boil',
            'time': {'value': 60, 'unit': 'min'},
          },
          'alpha_acid': {'value': 10.0, 'unit': '%'},
        },
        {
          'name': 'H. Test',
          'amount': {'value': 15.0, 'unit': 'g'},
          'timing': {
            'use': 'add_to_boil',
            'time': {'value': 0, 'unit': 'min'},
          },
          'alpha_acid': {'value': 7.0, 'unit': '%'},
        },
        {
          'name': 'Houblon Inconnu',
          'amount': {'value': 50.0, 'unit': 'g'},
          'timing': {
            'use': 'add_to_boil',
            'time': {'value': 0, 'unit': 'min'},
          },
        },
        {
          'name': 'Houblon Test',
          'amount': {'value': 30.0, 'unit': 'g'},
          'timing': {
            'use': 'add_to_fermentation',
            'time': {'value': 4320, 'unit': 'min'},
          },
          'alpha_acid': {'value': 7.0, 'unit': '%'},
        },
      ]);
      expect(d['source_hop_timing'], [
        {'hop_index': 0, 'label': 'start'},
        {'hop_index': 3, 'label': 'Whirlpool'},
      ]);
    });

    test('ajouts de la liste des houblons et levures', () {
      expect(ingredients['miscellaneous_additions'], [
        {
          'name': 'Poudre Test',
          'amount': {'value': 8.0, 'unit': 'g'},
          'timing': {'use': 'add_to_boil'},
        },
        {
          'name': 'Fruit Inconnu',
          'amount': {'value': 100.0, 'unit': 'g'},
          'timing': {'use': 'add_to_fermentation'},
        },
      ]);
      expect(ingredients['culture_additions'], [
        {
          'name': 'Wyeast 9999 - Souche Fictive™',
          'type': 'ale',
          'form': 'liquid',
          'attenuation': {'value': 74.0, 'unit': '%'},
        },
        {'name': 'Levure Inconnue'},
      ]);
    });

    test('ingredient_refs : clés de brewing/ des seules lignes résolues', () {
      expect(d['ingredient_refs'], {
        ingredientKey(IngredientNature.malt, 'Malt Imaginaire'):
            'fermentable-malt-imaginaire',
        ingredientKey(IngredientNature.malt, 'Pale Fictif'):
            'fermentable-malt-moulin-fictif',
        ingredientKey(IngredientNature.hop, 'Houblon Test'): 'hop-houblon-test',
        ingredientKey(IngredientNature.hop, 'H. Test'): 'hop-houblon-test',
        ingredientKey(IngredientNature.addition, 'Poudre Test'):
            'misc-poudre-fictive',
        ingredientKey(IngredientNature.yeast, 'Wyeast 9999 - Souche Fictive™'):
            'culture-wyeast-9999-souche-fictive',
      });
    });

    test('valeurs annoncées, jamais dans recipe', () {
      expect(d['announced'], {
        'original_gravity': {'value': 1.05, 'unit': 'sg'},
        'final_gravity': {'value': 1.01, 'unit': 'sg'},
        'alcohol_by_volume': {'value': 5.2, 'unit': '%'},
        'ibu_estimate': {'value': 35.0, 'unit': 'IBUs'},
        'color_estimate': {'value': 20.0, 'unit': 'EBC'},
      });
      final d2 = _doc(p, 'public_recipes', 'diydog-2');
      expect(d2['announced'], {
        'original_gravity': {'value': 1.065, 'unit': 'sg'},
        'alcohol_by_volume': {'value': 7.0, 'unit': '%'},
      });
      final r2 = d2['recipe']! as Map;
      // Type de l'entrée résolue : un sucre reste un sucre, et sa clé
      // d'ingrédient est celle d'un sucre.
      final malts2 =
          (r2['ingredients'] as Map)['fermentable_additions'] as List;
      expect(malts2[1], {
        'name': 'Sucre Nul',
        'type': 'sugar',
        'amount': {'value': 300.0, 'unit': 'g'},
        'color': {'value': 0.0, 'unit': 'EBC'},
      });
      expect(
        d2['ingredient_refs'],
        containsPair(
          ingredientKey(IngredientNature.sugar, 'Sucre Nul'),
          'fermentable-sucre-nul',
        ),
      );
      expect(r2.containsKey('mash'), isFalse);
      expect(r2.containsKey('notes'), isFalse);
      expect(d2['source_hop_timing'], [
        {'hop_index': 0, 'label': 'FWH'},
      ]);
    });

    test('aucun texte libre de source dans un document (P20)', () {
      const interdites = {
        'notes',
        'description',
        'tagline',
        'food_pairing',
        'brewers_tips',
        'contributed_by',
        'substitutes',
        'best_for',
        'overall_impression',
        'examples',
        'tags',
        'url',
        'folder_path',
        'image',
      };
      for (final MapEntry(key: collection, value: docs)
          in p.collections.entries) {
        for (final doc in docs) {
          final data = Map.of(doc['data']! as Map<String, Object?>);
          if (collection == 'public_recipes') {
            (data['recipe'] = Map.of(data['recipe']! as Map)).remove('notes');
          }
          _parcourir(
            data,
            (cle) => expect(
              interdites,
              isNot(contains(cle)),
              reason: '$collection ${doc['id']}',
            ),
            (texte) => expect(texte, isNot(contains('TEXTE LIBRE'))),
          );
        }
      }
    });
  });

  group('fiches des fabricants', () {
    late Preparation p;
    setUpAll(() {
      final s = _sources();
      p = preparer(
        SourcesBrutes(
          octets001: s.octets001,
          texte002: s.texte002,
          texte003: s.texte003,
          texte004: s.texte004,
          texte005: s.texte005,
          texteFabricants: File(
            '$_dossier/fabricants/cultures.json',
          ).readAsStringSync(),
          diyDog: s.diyDog,
        ),
        alias: _alias,
        ajoutsDansHoublons: _ajouts,
      );
    });

    test('la fiche donne les valeurs, l\'identifiant ne change pas', () {
      final l = _doc(
        p,
        'beer_cultures',
        'culture-labo-fictif-lf1-levure-test-ale',
      );
      expect(l['name'], 'Fictiale LF1');
      expect(l['aliases'], ['Levure Test Ale']);
      expect(l['attenuation'], plage(76, 80, '%'));
      expect(l['temperature_range'], plage(18, 26, 'C'));
      // La fiche ne donne pas la floculation : elle n'est pas reprise du 003.
      expect(l.containsKey('flocculation'), isFalse);
      expect(l.containsKey('notes'), isFalse);
      final provenance = l['provenance']! as List;
      expect(provenance.first, {
        'source': 'fabricants',
        'source_id': 'labo-fictif-lf1',
        'version': kDateReleveFabricants,
        'licence': Licence.fabricant,
        'retrieved': kDateReleveFabricants,
      });
      expect(provenance, hasLength(3));
    });

    test('souche connue de la seule fiche ; atténuation hors bornes', () {
      final fiche = p.collections['beer_cultures']!.singleWhere(
        (e) => (e['data']! as Map)['name'] == 'Fictibrew LF2',
      );
      expect(fiche['id'], 'culture-labo-fictif-lf2-fictibrew-lf2');
      final n = fiche['data']! as Map;
      expect(n['temperature_range'], plage(20, 32, 'C'));
      expect(n.containsKey('attenuation'), isFalse);
      expect(p.collections['beer_cultures'], hasLength(4));
      final ecartees = (p.rapport['valeurs_ecartees']! as Map)['lignes']!;
      expect(
        (ecartees as List).where(
          (e) =>
              (e as Map)['source'] == 'fabricants' &&
              '${e['champ']}'.startsWith('attenuation_range'),
        ),
        isNotEmpty,
      );
    });

    test('liste autre que cultures ignorée et comptée', () {
      expect(
        (p.rapport['listes_ignorees']! as Map)['fabricants:hop_varieties'],
        1,
      );
      expect(
        p.collections['beer_hops']!.where(
          (e) => (e['data']! as Map)['name'] == 'Houblon De Fiche',
        ),
        isEmpty,
      );
    });
  });

  group('rapport', () {
    late Preparation p;
    setUpAll(() => p = _preparer());

    test('résolution avant et après alias, par nature', () {
      final r = p.rapport['resolution']! as Map;
      expect(r['fermentable'], {
        'lignes': 5,
        'exactes': 3,
        'souche': 0,
        'alias': 1,
        'non_resolues': 1,
        'taux_avant_alias': 60.0,
        'taux_apres_alias': 80.0,
        'noms_non_resolus': 1,
      });
      expect((r['hop'] as Map)['lignes'], 6);
      expect((r['hop'] as Map)['alias'], 1);
      expect((r['misc'] as Map)['lignes'], 2);
      expect((r['culture'] as Map)['non_resolues'], 1);
    });

    test('valeurs recopiées, non résolus, lignes rejetées', () {
      expect(p.rapport['valeurs_recopiees'], {
        'fermentable.type': 4,
        'fermentable.yield': 3,
        'fermentable.color': 4,
        'hop.alpha_acid': 3,
        'culture.type': 1,
        'culture.form': 1,
        'culture.attenuation': 1,
      });
      expect(p.rapport['non_resolus'], {
        'fermentable': [
          {'name': 'Nom Inconnu', 'lignes': 1},
        ],
        'hop': [
          {'name': 'Houblon Inconnu', 'lignes': 1},
        ],
        'culture': [
          {'name': 'Levure Inconnue', 'lignes': 1},
        ],
        'misc': [
          {'name': 'Fruit Inconnu', 'lignes': 1},
        ],
      });
      expect((p.rapport['lignes_rejetees']! as Map)['lignes'], [
        {
          'recette': 'diydog-1',
          'liste': 'hops',
          'nom': 'Houblon Test',
          'raison': 'moment ambigu',
        },
        {
          'recette': 'diydog-1',
          'liste': 'hops',
          'nom': 'Jus Fictif',
          'raison': 'unité de quantité inconnue',
        },
        {
          'recette': 'diydog-1',
          'liste': 'mash_temp',
          'raison': 'durée absente ou illisible',
        },
        {
          'recette': 'diydog-2',
          'liste': 'mash_temp',
          'raison': 'température absente ou illisible',
        },
      ]);
      expect(p.rapport['libelles_ajouts_perdus'], 1);
      expect(p.rapport['fermentations_non_reprises'], 1);
    });

    test('import_unresolved : empreinte de nature et nom', () {
      final docs = p.collections['import_unresolved']!;
      expect(docs, hasLength(4));
      final id = idNonResolu(NatureReferentiel.hop, 'Houblon Inconnu');
      expect(_doc(p, 'import_unresolved', id), {
        'nature': 'hop',
        'name': 'Houblon Inconnu',
        'source': 'diydog',
        'count': 1,
      });
    });

    test('entrées par source et fusions', () {
      expect(p.rapport['entrees_par_source'], {
        'brewtarget-001': {'fermentable': 4, 'hop': 1, 'misc': 1, 'culture': 1},
        'brewtarget-002': {'style': 2},
        'brewtarget-003': {'hop': 2, 'culture': 1},
        'brewtarget-004': {'culture': 2},
        'brewtarget-005': {'fermentable': 2, 'hop': 1, 'misc': 2, 'culture': 1},
        'diydog': {'recette': 2},
      });
      expect((p.rapport['fusions']! as Map)['culture'], {
        'entrees': 5,
        'documents': 3,
        'fusions': 2,
      });
    });
  });

  test('empreinte de chaque document, et préparation reproductible', () {
    final a = _preparer();
    final b = _preparer();
    expect(jsonEncode(a.collections), jsonEncode(b.collections));
    for (final docs in a.collections.values) {
      for (final doc in docs) {
        final data = Map.of(doc['data']! as Map<String, Object?>);
        final empreinte = data.remove('content_sha256');
        if (empreinte != null) expect(empreinte, empreinteContenu(data));
      }
    }
  });

  test('JSON trop profond et trop de fichiers DIY Dog : refusés', () {
    final profond = '${'[' * 40}1${']' * 40}';
    expect(() => lireJsonBorne(profond), throwsFormatException);
    expect(
      () => lireJsonCommente('// en-tête\n$profond'),
      throwsFormatException,
    );
    expect(lireJsonBorne('[[1]]'), [
      [1],
    ]);
    final s = _sources();
    final trop = SourcesBrutes(
      octets001: s.octets001,
      texte002: s.texte002,
      texte003: s.texte003,
      texte004: s.texte004,
      texte005: s.texte005,
      texteFabricants: s.texteFabricants,
      diyDog: List.filled(kMaxFichiersDiyDog + 1, s.diyDog.first),
    );
    expect(() => preparer(trop), throwsStateError);
  });

  test('alias vers une entrée absente : table refusée', () {
    expect(
      () => preparer(
        _sources(),
        alias: const [
          Alias(NatureReferentiel.hop, 'Nom', 'hop-entree-absente'),
        ],
      ),
      throwsStateError,
    );
    expect(
      () => preparer(
        _sources(),
        alias: const [
          Alias(NatureReferentiel.hop, 'Nom', 'fermentable-malt-imaginaire'),
        ],
      ),
      throwsStateError,
      reason: 'nature différente',
    );
  });

  test('table d\'alias du projet : chaque cible existe dans sa nature', () {
    // Vérifiée sans les sources (absentes du dépôt) : identifiants bien
    // formés, aucun nom en double.
    final vus = <String>{};
    for (final a in kAlias) {
      expect(
        vus.add('${a.nature.prefixe}|${cleNormalisee(a.nom)}'),
        isTrue,
        reason: a.nom,
      );
      final cible = a.cible;
      if (cible != null) {
        expect(cible, startsWith('${a.nature.prefixe}-'));
        expect(
          cible.substring(a.nature.prefixe.length + 1),
          cleNormalisee(cible.substring(a.nature.prefixe.length + 1)),
        );
      }
    }
  });
}
