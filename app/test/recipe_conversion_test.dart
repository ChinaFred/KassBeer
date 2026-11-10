import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

Map<String, Object> _g(num value) => {'value': value, 'unit': 'g'};
Map<String, Object> _min(int value) => {'value': value, 'unit': 'min'};
Map<String, Object> _pct(num value) => {'value': value, 'unit': '%'};

/// Document de recette en BeerJSON partiel, tel que Firestore le rend : les durées
/// en entiers, les autres nombres tels qu'ils ont été écrits.
Map<String, dynamic> _doc() => {
  'format_version': 1,
  'owner_uid': 'uid-a',
  'owner_name': 'Brasseuse Fictive',
  'equipment_id': 'eq-1',
  'recipe': {
    'name': 'Twin bottle',
    'type': 'all grain',
    'style': {'name': 'Belgian Blond Ale'},
    'batch_size': {'value': 20, 'unit': 'l'},
    'boil': {'boil_time': _min(60)},
    'mash': {
      'name': 'Empâtage',
      'grain_temperature': {'value': 18, 'unit': 'C'},
      'mash_steps': [
        {
          'name': 'Saccharification',
          'type': 'infusion',
          'step_temperature': {'value': 67, 'unit': 'C'},
          'step_time': _min(60),
        },
      ],
    },
    'ingredients': {
      'fermentable_additions': [
        {
          'name': 'Pils',
          'type': 'grain',
          'amount': _g(4500),
          'color': {'value': 3.5, 'unit': 'EBC'},
          'yield': {'fine_grind': _pct(80)},
        },
        {'name': 'Candi', 'type': 'sugar', 'amount': _g(500)},
      ],
      'hop_additions': [
        {
          'name': 'Citra',
          'form': 'pellet',
          'alpha_acid': _pct(12),
          'amount': _g(22.4),
          'timing': {'use': 'add_to_boil', 'time': _min(60)},
        },
        {
          'name': 'Saaz',
          'form': 'leaf',
          'amount': _g(30),
          'timing': {
            'use': 'add_to_boil',
            'time': _min(0),
            'duration': _min(15),
          },
        },
        {
          'name': 'Mosaic',
          'form': 'pellet',
          'amount': _g(50),
          'timing': {'use': 'add_to_fermentation', 'duration': _min(4320)},
        },
      ],
      'miscellaneous_additions': [
        {
          'name': 'Gypse',
          'type': 'water agent',
          'amount': _g(5),
          'timing': {'use': 'add_to_mash', 'duration': _min(60)},
        },
      ],
      'culture_additions': [
        {
          'name': 'US-05',
          'type': 'ale',
          'form': 'dry',
          'attenuation': _pct(78),
          'amount': _g(11.5),
        },
      ],
    },
  },
};

Map<String, dynamic> _recipe(Map<String, dynamic> doc) =>
    doc['recipe'] as Map<String, dynamic>;

Map<String, dynamic> _ingredients(Map<String, dynamic> doc) =>
    _recipe(doc)['ingredients'] as Map<String, dynamic>;

List<dynamic> _list(Map<String, dynamic> doc, String key) =>
    _ingredients(doc)[key] as List<dynamic>;

/// Recette complète, saisie comme le fait l'éditeur (masses en double).
const _complete = RecipeContent(
  name: 'Blonde de Noël',
  type: 'all grain',
  style: 'Belgian Blond Ale',
  notes: 'Fermentation à 19 °C.',
  batchVolumeL: 20.0,
  boilTimeMin: 60,
  grainTempC: 18.0,
  equipmentId: 'eq-1',
  fermentables: [
    FermentableLine(
      name: 'Pils',
      type: 'grain',
      weightG: 4500.0,
      ebc: 3.5,
      yieldPct: 80.0,
    ),
    FermentableLine(name: 'Candi', type: 'sugar', weightG: 500.0),
  ],
  hops: [
    HopLine(
      name: 'Magnum',
      amount: Quantite.grammes(22.4),
      use: HopUse.boil,
      form: 'pellet',
      alphaPct: 12.0,
      timeMin: 60,
    ),
    HopLine(
      name: 'Saaz',
      amount: Quantite.grammes(30.0),
      use: HopUse.afterBoil,
      form: 'leaf',
      timeMin: 15,
    ),
    HopLine(
      name: 'Citra',
      amount: Quantite.grammes(50.0),
      use: HopUse.dryHop,
      form: 'pellet',
      timeMin: 4320,
    ),
  ],
  others: [
    OtherLine(
      name: 'Gypse',
      amount: Quantite.grammes(5.0),
      type: 'water agent',
      use: OtherUse.mash,
      timeMin: 60,
    ),
    OtherLine(
      name: 'Mousse d\'Irlande',
      amount: Quantite.grammes(4.0),
      type: 'fining',
      use: OtherUse.boil,
      timeMin: 15,
    ),
    OtherLine(
      name: 'Coriandre',
      amount: Quantite.grammes(10.0),
      type: 'spice',
      use: OtherUse.afterBoil,
      timeMin: 10,
    ),
    OtherLine(
      name: 'Écorce d\'orange',
      amount: Quantite.grammes(8.0),
      type: 'flavor',
      use: OtherUse.fermentation,
      timeMin: 2880,
    ),
    OtherLine(
      name: 'Copeaux de chêne',
      amount: Quantite.grammes(20.0),
      type: 'wood',
      use: OtherUse.bottling,
    ),
    OtherLine(name: 'Sel', amount: Quantite.grammes(2.0)),
  ],
  yeasts: [
    YeastLine(
      name: 'US-05',
      type: 'ale',
      form: 'dry',
      attenuationPct: 78.0,
      amount: Quantite.grammes(11.5),
    ),
  ],
  mashSteps: [
    MashStep(
      name: 'Saccharification',
      tempC: 66.0,
      durationMin: 60,
      type: 'infusion',
    ),
    MashStep(
      name: 'Mash-out',
      tempC: 78.0,
      durationMin: 10,
      type: 'temperature',
    ),
  ],
  brewSteps: [
    BrewStepLine(
      key: 'k-palier',
      name: 'Palier 66',
      durationMin: 60,
      tempC: 66,
    ),
    BrewStepLine(key: 'k-ebullition', name: 'Ébullition', durationMin: 60),
  ],
);

/// Recette importée qui porte les valeurs lues depuis la v0.1.17 (L2a
/// d'ADR-005) : auteur, malts extrait, miel, fruit, jus et `other`, houblons à
/// l'empâtage et au conditionnement, formes `plug`, `powder`, `extract` et
/// `leaf (wet)`, jour d'ajout à cru, quantités en litres, levure `wheat`.
const _imported = RecipeContent(
  name: 'Import de test',
  type: 'extract',
  author: 'Brasseuse Fictive',
  batchVolumeL: 20.0,
  boilTimeMin: 60,
  fermentables: [
    FermentableLine(
      name: 'Extrait liquide clair',
      type: 'extract',
      weightG: 3000.0,
      ebc: 8.0,
      yieldPct: 78.0,
    ),
    FermentableLine(
      name: 'Extrait sec',
      type: 'dry extract',
      weightG: 500.0,
      ebc: 6.0,
      yieldPct: 95.0,
    ),
    FermentableLine(
      name: 'Miel de fleurs',
      type: 'honey',
      weightG: 250.0,
      ebc: 2.0,
      yieldPct: 75.0,
    ),
    FermentableLine(name: 'Framboises', type: 'fruit', weightG: 1000.0),
    FermentableLine(name: 'Jus de pomme', type: 'juice', weightG: 300.0),
    FermentableLine(name: 'Sirop maison', type: 'other', weightG: 200.0),
  ],
  hops: [
    HopLine(
      name: 'Saaz',
      amount: Quantite.grammes(20.0),
      use: HopUse.mash,
      form: 'leaf',
      alphaPct: 3.5,
      timeMin: 60,
    ),
    HopLine(
      name: 'Fuggles',
      amount: Quantite.grammes(15.0),
      use: HopUse.boil,
      form: 'plug',
      alphaPct: 4.5,
      timeMin: 30,
    ),
    HopLine(
      name: 'Cascade',
      amount: Quantite.grammes(10.0),
      use: HopUse.boil,
      form: 'powder',
      alphaPct: 6.0,
      timeMin: 10,
    ),
    HopLine(
      name: 'Extrait de houblon',
      amount: Quantite.litres(0.005),
      use: HopUse.boil,
      form: 'extract',
      alphaPct: 50.0,
      timeMin: 60,
    ),
    HopLine(
      name: 'Houblon frais',
      amount: Quantite.grammes(100.0),
      use: HopUse.afterBoil,
      form: 'leaf (wet)',
      timeMin: 20,
    ),
    HopLine(
      name: 'Citra',
      amount: Quantite.grammes(50.0),
      use: HopUse.dryHop,
      form: 'pellet',
      alphaPct: 12.0,
      timeMin: 4320,
      dayMin: 4320,
    ),
    HopLine(
      name: 'Mosaic',
      amount: Quantite.grammes(5.0),
      use: HopUse.package,
      form: 'pellet',
    ),
  ],
  others: [
    OtherLine(
      name: 'Acide lactique',
      amount: Quantite.litres(0.005),
      type: 'water agent',
      use: OtherUse.mash,
      timeMin: 60,
    ),
  ],
  yeasts: [
    YeastLine(
      name: 'Levure de blanche liquide',
      type: 'wheat',
      form: 'liquid',
      attenuationPct: 75.0,
      amount: Quantite.litres(0.1),
    ),
  ],
);

/// Valeur JSON canonique : clés triées, Timestamp en `{"__timestamp__": iso}`. Un
/// entier et un double ne s'écrivent pas de la même façon (60 et 60.0).
Object? _canonical(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys.map((k) => k as String).toList()..sort())
      key: _canonical(value[key]),
  },
  List() => [for (final item in value) _canonical(item)],
  Timestamp() => {'__timestamp__': value.toDate().toUtc().toIso8601String()},
  _ => value,
};

String _json(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(_canonical(value));

/// Fixture partagée avec `rules-tests/test/beerjson_schema.test.mjs` (ajv).
String _fixture(String name) =>
    File('test/fixtures/recipe_documents/$name.json').readAsStringSync();

/// Entrée de `computeRecipe` construite comme la v0.1.14 la construisait depuis un
/// document plat. Sert seulement à vérifier que le passage en BeerJSON ne change
/// aucun chiffre.
RecipeInput _inputFromFlat(Map<String, dynamic> doc) {
  const uses = {
    'boil': HopUse.boil,
    'whirlpool': HopUse.afterBoil,
    'dry_hop': HopUse.dryHop,
  };
  double? n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble();
  List<Map<String, dynamic>> rows(String k) => [
    for (final e in (doc[k] as List? ?? const [])) e as Map<String, dynamic>,
  ];
  return RecipeInput(
    fermentables: [
      for (final f in rows('fermentables'))
        FermentableInput(
          name: f['name'] as String,
          kind: FermentableKind.ofType(f['kind'] as String),
          massGrams: n(f, 'weight_g')!,
          colorEbc: n(f, 'ebc'),
          yieldPercent: n(f, 'yield_pct'),
        ),
    ],
    hops: [
      for (final h in rows('hops'))
        HopInput(
          name: h['name'] as String,
          massGrams: n(h, 'weight_g')!,
          use: uses[h['use']]!,
          form: HopForm.ofBeerJson(h['form'] as String),
          alphaPercent: n(h, 'alpha_pct'),
          minutes: n(h, 'time_min'),
        ),
    ],
    yeasts: [
      for (final y in rows('yeasts'))
        YeastInput(
          name: y['name'] as String,
          attenuationPercent: n(y, 'attenuation_pct'),
        ),
    ],
    batchVolumeLitres: n(doc, 'batch_volume_l'),
    boilMinutes: n(doc, 'boil_time_min'),
  );
}

/// Description complète d'une entrée de calcul, pour comparer deux entrées.
/// Valeur calculée, ou natures et lignes des données manquantes.
Object? _result(CalculationResult result) => switch (result) {
  CalculationComputed(:final value) => value,
  CalculationUnavailable(:final missing) => [
    for (final m in missing)
      '${m.kind.name} : ${m.items.map((i) => i.name).join(", ")}',
  ],
};

List<Object?> _describe(RecipeInput input) => [
  for (final f in input.fermentables)
    (f.name, f.kind, f.massGrams, f.colorEbc, f.yieldPercent),
  for (final h in input.hops)
    (h.name, h.massGrams, h.use, h.form, h.alphaPercent, h.minutes),
  for (final y in input.yeasts) (y.name, y.attenuationPercent),
  input.batchVolumeLitres,
  input.boilMinutes,
];

void main() {
  group('document → domaine', () {
    test('BeerJSON lu vers les types de travail', () {
      final c = RecipeContent.fromFirestore(_doc());
      expect(c.name, 'Twin bottle');
      expect(c.type, 'all grain');
      expect(c.style, 'Belgian Blond Ale');
      expect(c.batchVolumeL, 20);
      expect(c.boilTimeMin, 60);
      expect(c.grainTempC, 18);
      expect(c.equipmentId, 'eq-1');
      expect(c.fermentables.map((f) => f.kind), [
        FermentableKind.malt,
        FermentableKind.sugar,
      ]);
      expect(c.fermentables.first.yieldPct, 80);
      expect(c.fermentables.first.ebc, 3.5);
      expect(c.hops.map((h) => (h.use, h.timeMin)), [
        (HopUse.boil, 60),
        (HopUse.afterBoil, 15),
        (HopUse.dryHop, 4320),
      ]);
      expect(c.hops.map((h) => h.form), ['pellet', 'leaf', 'pellet']);
      expect(c.hops.map((h) => h.calcForm), [
        HopForm.pellet,
        HopForm.whole,
        HopForm.pellet,
      ]);
      expect(c.hops.first.amount, const Quantite.grammes(22.4));
      final gypse = c.others.single;
      expect(
        (gypse.type, gypse.use, gypse.timeMin),
        ('water agent', OtherUse.mash, 60),
      );
      final yeast = c.yeasts.single;
      expect(
        (yeast.type, yeast.form, yeast.attenuationPct, yeast.amount),
        ('ale', 'dry', 78, const Quantite.grammes(11.5)),
      );
      final step = c.mashSteps.single;
      expect((step.type, step.tempC, step.durationMin), ('infusion', 67, 60));
    });

    test('durées lues en int', () {
      final c = RecipeContent.fromFirestore(_doc());
      expect(c.boilTimeMin, isA<int>());
      expect(c.mashSteps.single.durationMin, isA<int>());
      for (final h in c.hops) {
        expect(h.timeMin, isA<int>());
      }
      expect(c.others.single.timeMin, isA<int>());
    });

    test('moments d\x27un ajout lus depuis timing', () {
      final doc = _doc();
      _ingredients(doc)['miscellaneous_additions'] = [
        for (final timing in <Map<String, Object>?>[
          {'use': 'add_to_mash', 'duration': _min(60)},
          {'use': 'add_to_boil', 'time': _min(15)},
          {'use': 'add_to_boil', 'time': _min(0), 'duration': _min(10)},
          {'use': 'add_to_boil', 'time': _min(0)},
          {'use': 'add_to_fermentation', 'duration': _min(2880)},
          {'use': 'add_to_package'},
          null,
        ])
          {'name': 'Ajout', 'amount': _g(1), 'timing': ?timing},
      ];
      final others = RecipeContent.fromFirestore(doc).others;
      expect(others.map((o) => (o.use, o.timeMin)), [
        (OtherUse.mash, 60),
        (OtherUse.boil, 15),
        (OtherUse.afterBoil, 10),
        // « Après ébullition » sans durée s'écrit à 0 min d'ébullition.
        (OtherUse.boil, 0),
        (OtherUse.fermentation, 2880),
        (OtherUse.bottling, null),
        (null, null),
      ]);
    });

    test('valeur du schéma hors des listes de l\x27éditeur : conservée', () {
      final doc = _doc();
      _recipe(doc)['type'] = 'cider';
      (_list(doc, 'culture_additions').single as Map)['form'] = 'slant';
      (_list(doc, 'culture_additions').single as Map)['type'] = 'wheat';
      final c = RecipeContent.fromFirestore(doc);
      expect(c.type, 'cider');
      expect(c.yeasts.single.form, 'slant');
      expect(c.yeasts.single.type, 'wheat');
      final written = c.toFirestore(creation: true);
      final recipe = written['recipe'] as Map<String, Object?>;
      expect(recipe['type'], 'cider');
      final culture =
          ((recipe['ingredients'] as Map)['culture_additions'] as List).single
              as Map;
      expect(culture['form'], 'slant');
      expect(culture['type'], 'wheat');
    });

    test('température du grain sans palier', () {
      final doc = _doc();
      _recipe(doc)['mash'] = {
        'name': 'Empâtage',
        'grain_temperature': {'value': 20, 'unit': 'C'},
      };
      final c = RecipeContent.fromFirestore(doc);
      expect(c.grainTempC, 20);
      expect(c.mashSteps, isEmpty);
    });
  });

  group('documents illisibles', () {
    void illisible(Map<String, dynamic> doc, String field) => expect(
      () => RecipeContent.fromFirestore(doc),
      throwsA(isA<DocumentIllisible>().having((e) => e.field, 'field', field)),
    );

    test('format_version absent, 2, ou en texte', () {
      illisible(_doc()..remove('format_version'), 'format_version');
      illisible(_doc()..['format_version'] = 2, 'format_version');
      illisible(_doc()..['format_version'] = '1', 'format_version');
    });

    test('document plat de la v0.1.14', () {
      illisible({
        'owner_uid': 'uid-a',
        'name': 'Ancienne',
        'batch_volume_l': 20,
        'fermentables': const [],
      }, 'format_version');
      illisible({'format_version': 1, 'name': 'Sans recipe'}, 'recipe');
    });

    test('unité hors liste, unité sans valeur, couple incomplet', () {
      illisible(
        _doc()..['recipe']['batch_size'] = {'value': 20, 'unit': 'gal'},
        'recipe.batch_size.unit',
      );
      illisible(
        _doc()..['recipe']['batch_size'] = {'unit': 'l'},
        'recipe.batch_size.value',
      );
      illisible(
        _doc()..['recipe']['batch_size'] = {'value': 20},
        'recipe.batch_size.unit',
      );
      final kg = _doc();
      (_list(kg, 'fermentable_additions').first as Map)['amount'] = {
        'value': 4.5,
        'unit': 'kg',
      };
      illisible(kg, 'recipe.ingredients.fermentable_additions[0].amount.unit');
      final f = _doc();
      (_recipe(f)['mash'] as Map)['grain_temperature'] = {
        'value': 64,
        'unit': 'F',
      };
      illisible(f, 'recipe.mash.grain_temperature.unit');
    });

    test('durée décimale', () {
      illisible(
        _doc()
          ..['recipe']['boil'] = {
            'boil_time': {'value': 60.5, 'unit': 'min'},
          },
        'recipe.boil.boil_time.value',
      );
      final step = _doc();
      ((_recipe(step)['mash'] as Map)['mash_steps'] as List)
          .single['step_time'] = {
        'value': 60.0,
        'unit': 'min',
      };
      // Une durée est un entier Firestore : 60.0 écrit en double est refusé (les
      // tests tournent sur la VM Dart, où 60.0 est un double).
      illisible(step, 'recipe.mash.mash_steps[0].step_time.value');
    });

    test('valeur énumérée hors schéma', () {
      illisible(_doc()..['recipe']['type'] = 'bière', 'recipe.type');
      final culture = _doc();
      (_list(culture, 'culture_additions').single as Map)['form'] = 'poudre';
      illisible(culture, 'recipe.ingredients.culture_additions[0].form');
      final misc = _doc();
      (_list(misc, 'miscellaneous_additions').single as Map)['type'] = 'épice';
      illisible(misc, 'recipe.ingredients.miscellaneous_additions[0].type');
      final step = _doc();
      ((_recipe(step)['mash'] as Map)['mash_steps'] as List).single['type'] =
          'step';
      illisible(step, 'recipe.mash.mash_steps[0].type');
    });

    test('moment d\x27un houblon hors du schéma, absent, ou durée perdue', () {
      final water = _doc();
      (_list(water, 'hop_additions').first as Map)['timing'] = {
        'use': 'add_to_water',
      };
      illisible(water, 'recipe.ingredients.hop_additions[0].timing.use');
      // L'empâtage et le conditionnement n'écrivent que `duration`.
      final mashTime = _doc();
      (_list(mashTime, 'hop_additions').first as Map)['timing'] = {
        'use': 'add_to_mash',
        'time': _min(10),
      };
      illisible(mashTime, 'recipe.ingredients.hop_additions[0].timing.time');
      final absent = _doc();
      (_list(absent, 'hop_additions').first as Map).remove('timing');
      illisible(absent, 'recipe.ingredients.hop_additions[0].timing');
      // Une infusion après un ajout à 60 min serait perdue à l'enregistrement.
      final duration = _doc();
      (_list(duration, 'hop_additions').first as Map)['timing'] = {
        'use': 'add_to_boil',
        'time': _min(60),
        'duration': _min(10),
      };
      illisible(
        duration,
        'recipe.ingredients.hop_additions[0].timing.duration',
      );
    });

    test(
      'type d\x27un malt ou forme d\x27un houblon hors du schéma, ou absent',
      () {
        final malt = _doc();
        (_list(malt, 'fermentable_additions').first as Map)['type'] = 'malt';
        illisible(malt, 'recipe.ingredients.fermentable_additions[0].type');
        final noType = _doc();
        (_list(noType, 'fermentable_additions').first as Map).remove('type');
        illisible(noType, 'recipe.ingredients.fermentable_additions[0].type');
        final whole = _doc();
        (_list(whole, 'hop_additions').first as Map)['form'] = 'whole';
        illisible(whole, 'recipe.ingredients.hop_additions[0].form');
      },
    );

    test(
      'quantité d\x27un houblon, d\x27un ajout ou d\x27une levure : g ou l',
      () {
        for (final (list, unit) in [
          ('hop_additions', 'ml'),
          ('hop_additions', 'kg'),
          ('miscellaneous_additions', 'ml'),
          ('miscellaneous_additions', 'each'),
          ('culture_additions', 'pkg'),
        ]) {
          final doc = _doc();
          (_list(doc, list).first as Map)['amount'] = {
            'value': 5,
            'unit': unit,
          };
          illisible(doc, 'recipe.ingredients.$list[0].amount.unit');
        }
        // Un malt reste en grammes (décision du 2026-11-10).
        final malt = _doc();
        (_list(malt, 'fermentable_additions').first as Map)['amount'] = {
          'value': 1,
          'unit': 'l',
        };
        illisible(
          malt,
          'recipe.ingredients.fermentable_additions[0].amount.unit',
        );
      },
    );

    test('champ obligatoire absent : aucune valeur par défaut', () {
      final doc = _doc();
      (_list(doc, 'fermentable_additions').first as Map).remove('amount');
      illisible(doc, 'recipe.ingredients.fermentable_additions[0].amount');
      illisible(_doc()..['recipe'].remove('ingredients'), 'recipe.ingredients');
      expect(
        () => Recipe.fromFirestore('r', {
          'format_version': 1,
          'recipe': {'name': 'Sans auteur', 'ingredients': <String, Object>{}},
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('l\x27erreur ne contient pas le texte stocké', () {
      const secret = 'texte écrit par un autre membre';
      final docs = <Map<String, dynamic>>[
        _doc()..['format_version'] = secret,
        _doc()..['recipe']['batch_size'] = {'value': 1, 'unit': secret},
        _doc()..['recipe']['type'] = secret,
      ];
      final culture = _doc();
      (_list(culture, 'culture_additions').single as Map)['type'] = secret;
      final hop = _doc();
      (_list(hop, 'hop_additions').first as Map)['timing'] = {'use': secret};
      final kind = _doc();
      (_list(kind, 'fermentable_additions').first as Map)['type'] = secret;
      for (final doc in [...docs, culture, hop, kind]) {
        try {
          RecipeContent.fromFirestore(doc);
          fail('document accepté');
        } on Object catch (error) {
          expect(error.toString(), isNot(contains(secret)));
        }
      }
      expect(
        () => EquipmentContent.fromFirestore({'name': 'Cuve', 'kind': secret}),
        throwsA(
          isA<DocumentIllisible>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains(secret)),
          ),
        ),
      );
    });
  });

  group('domaine → document', () {
    test('aller-retour : la recette relue est la même', () {
      final written = _complete.toFirestore(creation: true);
      final read = RecipeContent.fromFirestore({
        ...written,
        'owner_uid': 'uid-a',
      });
      expect(_json(read.toFirestore(creation: true)), _json(written));
      expect(read.others[2].use, OtherUse.afterBoil);
      expect(read.hops[1].use, HopUse.afterBoil);
      expect(read.mashSteps.map((s) => s.type), ['infusion', 'temperature']);
      expect(read.brewSteps.map((s) => s.key), ['k-palier', 'k-ebullition']);
    });

    test('durées écrites en int, jamais en double', () {
      final data = _complete.toFirestore(creation: true);
      final recipe = data['recipe'] as Map<String, Object?>;
      Object? valueOf(Object? measure) => (measure as Map)['value'];
      expect(valueOf((recipe['boil'] as Map)['boil_time']), isA<int>());
      final mash = recipe['mash'] as Map;
      for (final s in mash['mash_steps'] as List) {
        expect(valueOf((s as Map)['step_time']), isA<int>());
      }
      final ingredients = recipe['ingredients'] as Map;
      for (final list in ['hop_additions', 'miscellaneous_additions']) {
        for (final line in ingredients[list] as List) {
          final timing = (line as Map)['timing'] as Map?;
          for (final key in ['time', 'duration']) {
            if (timing?[key] != null) expect(valueOf(timing![key]), isA<int>());
          }
        }
      }
    });

    test(
      'ajout « Après ébullition » sans durée : relu à 0 min d\x27ébullition',
      () {
        const content = RecipeContent(
          name: 'R',
          others: [
            OtherLine(
              name: 'Coriandre',
              amount: Quantite.grammes(10),
              use: OtherUse.afterBoil,
            ),
          ],
        );
        final written = content.toFirestore(creation: true);
        final misc =
            (((written['recipe'] as Map)['ingredients']
                            as Map)['miscellaneous_additions']
                        as List)
                    .single
                as Map;
        expect(misc['timing'], {
          'use': 'add_to_boil',
          'time': {'value': 0, 'unit': 'min'},
        });
        final read = RecipeContent.fromFirestore(written).others.single;
        expect((read.use, read.timeMin), (OtherUse.boil, 0));
      },
    );

    test('lignes que l\x27éditeur refuse : ArgumentError', () {
      expect(
        () => const HopLine(
          name: 'Saaz',
          amount: Quantite.grammes(10),
          use: HopUse.afterBoil,
          form: 'pellet',
        ).toFirestore(),
        throwsArgumentError,
      );
      expect(
        () => const OtherLine(
          name: 'Sel',
          amount: Quantite.grammes(1),
          timeMin: 5,
        ).toFirestore(),
        throwsArgumentError,
      );
    });

    test('mash : absent sans palier ni température, jamais une liste vide', () {
      const none = RecipeContent(name: 'R');
      expect(
        (none.toFirestore(creation: true)['recipe'] as Map).containsKey('mash'),
        isFalse,
      );
      const grainOnly = RecipeContent(name: 'R', grainTempC: 18);
      final mash =
          (grainOnly.toFirestore(creation: true)['recipe'] as Map)['mash']
              as Map;
      expect(mash, {
        'name': 'Empâtage',
        'grain_temperature': {'value': 18.0, 'unit': 'C'},
      });
    });

    test(
      'modification : enveloppe vidée retirée, recipe écrite d\x27un bloc',
      () {
        const content = RecipeContent(name: 'Vide');
        final data = content.toFirestore(creation: false);
        expect(data['equipment_id'], isA<FieldValue>());
        expect(data['imported_from'], isA<FieldValue>());
        expect(data.containsKey('brew_steps'), isFalse);
        expect(data['format_version'], 1);
        expect(data['recipe'].toString(), isNot(contains('FieldValue')));
      },
    );

    test('aucune clé d\x27ingrédient stockée, aucun prix ni stock (P5)', () {
      final text = jsonEncode(
        _canonical(_complete.toFirestore(creation: true)),
      );
      for (final word in [
        '"key":"malt',
        '"key":"houblon',
        'price',
        'prix',
        'stock',
        'cost',
      ]) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });
  });

  group('fixtures partagées avec ajv (rules-tests)', () {
    test('recette complète', () {
      expect(
        _json(_complete.toFirestore(creation: true)),
        _json(jsonDecode(_fixture('complete'))),
      );
    });

    test('recette importée : valeurs lues depuis la v0.1.17', () {
      expect(
        _json(_imported.toFirestore(creation: true)),
        _json(jsonDecode(_fixture('imported'))),
      );
    });

    test('recette minimale : un nom seul', () {
      expect(
        _json(
          const RecipeContent(name: 'Minimale').toFirestore(creation: true),
        ),
        _json(jsonDecode(_fixture('minimal'))),
      );
    });

    test('copie figée d\x27un brassin', () {
      final snapshot = recipeSnapshot(
        Recipe(
          id: 'r-1',
          ownerUid: 'uid-a',
          ownerName: 'Brasseuse Fictive',
          content: _complete,
          updatedAt: DateTime.utc(2026, 11, 2, 8),
        ),
      );
      expect(_json(snapshot), _json(jsonDecode(_fixture('snapshot'))));
    });
  });

  group('calculs', () {
    test('même recette en plat et en BeerJSON : même RecipeInput', () {
      final flat = <String, dynamic>{
        'name': 'Twin bottle',
        'batch_volume_l': 20,
        'boil_time_min': 60,
        'fermentables': [
          {
            'key': 'malt-pils',
            'name': 'Pils',
            'kind': 'grain',
            'weight_g': 4500,
            'ebc': 3.5,
            'yield_pct': 80,
          },
          {
            'key': 'sucre-candi',
            'name': 'Candi',
            'kind': 'sugar',
            'weight_g': 500,
          },
        ],
        'hops': [
          {
            'name': 'Citra',
            'weight_g': 22.4,
            'alpha_pct': 12,
            'use': 'boil',
            'time_min': 60,
            'form': 'pellet',
          },
          {
            'name': 'Saaz',
            'weight_g': 30,
            'use': 'whirlpool',
            'time_min': 15,
            'form': 'leaf',
          },
          {
            'name': 'Mosaic',
            'weight_g': 50,
            'use': 'dry_hop',
            'time_min': 4320,
            'form': 'pellet',
          },
        ],
        'yeasts': [
          {'name': 'US-05', 'attenuation_pct': 78, 'form': 'dry'},
        ],
      };
      final before = _inputFromFlat(flat);
      final after = RecipeContent.fromFirestore(_doc()).toInput();
      expect(_describe(after), _describe(before));
      for (final efficiency in [65.0, 72.0]) {
        final a = computeRecipe(
          recipe: before,
          mashEfficiencyPercent: efficiency,
        );
        final b = computeRecipe(
          recipe: after,
          mashEfficiencyPercent: efficiency,
        );
        for (final (x, y) in [
          (a.originalGravity, b.originalGravity),
          (a.finalGravity, b.finalGravity),
          (a.alcoholByVolume, b.alcoholByVolume),
          (a.bitternessIbu, b.bitternessIbu),
          (a.colorEbc, b.colorEbc),
        ]) {
          expect(_result(y), _result(x));
        }
      }
    });

    test('toInput : masses en grammes, durées en minutes', () {
      final input = RecipeContent.fromFirestore(_doc()).toInput();
      expect(input.fermentables.first.massGrams, 4500);
      expect(input.hops.last.minutes, 4320);
      expect(input.batchVolumeLitres, 20);
      expect(input.boilMinutes, 60);
      final calc = computeRecipe(recipe: input, mashEfficiencyPercent: 72);
      // Le candi n'a pas de rendement d'extrait : aucune valeur par défaut.
      final og = calc.originalGravity as CalculationUnavailable;
      expect(og.missing.single.kind, MissingInputKind.extractYield);
      expect(og.missing.single.items.single.name, 'Candi');
      expect(calc.colorEbc, isA<CalculationUnavailable>());
    });
  });

  group('duplication et tri', () {
    test('« Copie de {nom} » coupé à 120, sans fiche d\x27origine', () {
      final long = RecipeContent(name: 'x' * 120, importedFrom: 'fiche.xlsx');
      final copy = long.duplicate();
      expect(copy.name.length, 120);
      expect(copy.name, startsWith('Copie de x'));
      expect(copy.importedFrom, isNull);
      final source = RecipeContent.fromFirestore(_doc());
      final dup = source.duplicate();
      expect(dup.name, 'Copie de Twin bottle');
      expect(dup.fermentables, same(source.fermentables));
      expect(dup.equipmentId, 'eq-1');
      expect(dup.type, 'all grain');
      expect(dup.grainTempC, 18);
    });

    test('malts par masse décroissante, houblons par moment', () {
      const a = FermentableLine(name: 'A', type: 'grain', weightG: 500);
      const b = FermentableLine(name: 'B', type: 'grain', weightG: 4500);
      expect(sortFermentables([a, b]).map((f) => f.name), ['B', 'A']);
      HopLine hop(String name, HopUse use, [int? t]) => HopLine(
        name: name,
        amount: Quantite.grammes(10),
        use: use,
        form: 'pellet',
        timeMin: t,
      );
      final sorted = sortHops([
        hop('cru', HopUse.dryHop),
        hop('10', HopUse.boil, 10),
        hop('wp', HopUse.afterBoil, 15),
        hop('60', HopUse.boil, 60),
      ]);
      expect(sorted.map((h) => h.name), ['60', '10', 'wp', 'cru']);
      // Ordre du brassage : empâtage d'abord, conditionnement en dernier.
      expect(
        sortHops([
          hop('cond', HopUse.package),
          hop('60', HopUse.boil, 60),
          hop('emp', HopUse.mash, 60),
        ]).map((h) => h.name),
        ['emp', '60', 'cond'],
      );
    });
  });

  group('v0.1.17 — valeurs importées lues (L2a d\x27ADR-005)', () {
    Map<String, dynamic> imported() =>
        jsonDecode(_fixture('imported')) as Map<String, dynamic>;

    test('fixture lue vers les types de travail', () {
      final c = RecipeContent.fromFirestore(imported());
      expect(c.author, 'Brasseuse Fictive');
      expect(c.fermentables.map((f) => (f.type, f.kind)), [
        ('extract', FermentableKind.sugar),
        ('dry extract', FermentableKind.sugar),
        ('honey', FermentableKind.sugar),
        ('fruit', FermentableKind.sugar),
        ('juice', FermentableKind.sugar),
        ('other', null),
      ]);
      expect(c.hops.map((h) => (h.use, h.form, h.calcForm)), [
        (HopUse.mash, 'leaf', HopForm.whole),
        (HopUse.boil, 'plug', HopForm.whole),
        (HopUse.boil, 'powder', null),
        (HopUse.boil, 'extract', null),
        (HopUse.afterBoil, 'leaf (wet)', null),
        (HopUse.dryHop, 'pellet', HopForm.pellet),
        (HopUse.package, 'pellet', HopForm.pellet),
      ]);
      expect(c.hops[3].amount, const Quantite.litres(0.005));
      expect(c.hops[5].dayMin, 4320);
      expect(c.others.single.amount, const Quantite.litres(0.005));
      expect(c.yeasts.single.amount, const Quantite.litres(0.1));
      expect(c.yeasts.single.type, 'wheat');
    });

    test('I9 : relue puis enregistrée sans changement, recipe identique', () {
      final doc = imported();
      final read = RecipeContent.fromFirestore(doc);
      final written = read.toFirestore(creation: false);
      expect(_json(written['recipe']), _json(doc['recipe']));
      // L'auteur et la quantité en litres passent aussi par la copie figée.
      final snapshot = recipeSnapshot(
        Recipe(id: 'r-i', ownerUid: 'uid-a', content: read),
      );
      expect(_json(snapshot['recipe']), _json(doc['recipe']));
      expect(
        _json(
          RecipeContent.fromFirestore(
            snapshot,
          ).toFirestore(creation: true)['recipe'],
        ),
        _json(doc['recipe']),
      );
    });

    test('Dupliquer garde l\x27auteur de la recette d\x27origine', () {
      expect(_imported.duplicate().author, 'Brasseuse Fictive');
    });

    test('auteur vide ou blanc : absent', () {
      const blank = RecipeContent(name: 'Sans auteur', author: '  ');
      final recipe =
          blank.toFirestore(creation: true)['recipe'] as Map<String, Object?>;
      expect(recipe.containsKey('author'), isFalse);
    });

    test('toInput : nature, forme, masse de chaque ligne', () {
      final input = _imported.toInput();
      expect(input.fermentables.map((f) => f.kind), [
        FermentableKind.sugar,
        FermentableKind.sugar,
        FermentableKind.sugar,
        FermentableKind.sugar,
        FermentableKind.sugar,
        null,
      ]);
      expect(input.hops.map((h) => (h.use, h.form, h.massGrams)), [
        (HopUse.mash, HopForm.whole, 20.0),
        (HopUse.boil, HopForm.whole, 15.0),
        (HopUse.boil, null, 10.0),
        (HopUse.boil, null, null),
        (HopUse.afterBoil, null, 100.0),
        (HopUse.dryHop, HopForm.pellet, 50.0),
        (HopUse.package, HopForm.pellet, 5.0),
      ]);
    });

    test('calculs : nature à préciser, moment et forme non pris en charge, '
        'houblon en volume', () {
      final c = computeRecipe(recipe: _imported.toInput());
      final kinds = {
        for (final m in c.missingInputs)
          m.kind: [for (final i in m.items) i.name],
      };
      expect(kinds[MissingInputKind.fermentableKind], ['Sirop maison']);
      expect(kinds[MissingInputKind.hopUse], ['Saaz', 'Mosaic']);
      expect(kinds[MissingInputKind.hopForm], ['Cascade']);
      expect(c.hopsWithoutMass.map((h) => h.name), ['Extrait de houblon']);
    });
  });
}
