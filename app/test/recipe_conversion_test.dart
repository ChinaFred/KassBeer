import 'package:brewing/brewing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

/// Document de recette tel que Firestore le rend (valeurs stockées A5).
Map<String, dynamic> _doc() => {
  'owner_uid': 'uid-a',
  'owner_name': 'Alice',
  'name': 'Twin bottle',
  'batch_volume_l': 20,
  'boil_time_min': 60,
  'equipment_id': 'eq-1',
  'fermentables': [
    {
      'key': 'malt-pils',
      'name': 'Pils',
      'kind': 'grain',
      'weight_g': 4500,
      'ebc': 3.5,
      'yield_pct': 80,
    },
    {'key': 'sucre-candi', 'name': 'Candi', 'kind': 'sugar', 'weight_g': 500},
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
    {'name': 'Saaz', 'weight_g': 30, 'use': 'whirlpool', 'form': 'leaf'},
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
  'mash_steps': [
    {'name': 'Saccharification', 'temp_c': 67, 'duration_min': 60},
  ],
};

void main() {
  group('document → domaine', () {
    test('valeurs stockées lues par fromStored de brewing/', () {
      final c = RecipeContent.fromFirestore(_doc());
      expect(c.fermentables.map((f) => f.kind), [
        FermentableKind.malt,
        FermentableKind.sugar,
      ]);
      expect(c.hops.map((h) => h.use), [
        HopUse.boil,
        HopUse.afterBoil,
        HopUse.dryHop,
      ]);
      expect(c.hops.map((h) => h.form), [
        HopForm.pellet,
        HopForm.whole,
        HopForm.pellet,
      ]);
      expect(c.yeasts.single.form, YeastForm.dry);
      expect(c.batchVolumeL, 20);
      expect(c.hops.first.weightG, 22.4);
    });

    test('valeur stockée inconnue : BrewingInputException', () {
      final doc = _doc();
      (doc['fermentables'] as List).first['kind'] = 'extract';
      expect(
        () => RecipeContent.fromFirestore(doc),
        throwsA(isA<BrewingInputException>()),
      );
      final hops = _doc();
      (hops['hops'] as List).first['use'] = 'first_wort';
      expect(
        () => RecipeContent.fromFirestore(hops),
        throwsA(isA<BrewingInputException>()),
      );
    });

    test(
      'champ obligatoire absent : DocumentIllisible, aucune valeur par défaut',
      () {
        final doc = _doc();
        (doc['fermentables'] as List).first.remove('weight_g');
        expect(
          () => RecipeContent.fromFirestore(doc),
          throwsA(
            isA<DocumentIllisible>().having(
              (e) => e.field,
              'field',
              'fermentables[0].weight_g',
            ),
          ),
        );
        final noForm = _doc();
        (noForm['hops'] as List).first.remove('form');
        expect(
          () => RecipeContent.fromFirestore(noForm),
          throwsA(isA<DocumentIllisible>()),
        );
        expect(
          () => Recipe.fromFirestore('r', {'name': 'Sans auteur'}),
          throwsA(isA<DocumentIllisible>()),
        );
      },
    );
  });

  group('domaine → document', () {
    test('clé recalculée par ingredientKey, valeurs stockées, grammes', () {
      final data = RecipeContent.fromFirestore(
        _doc(),
      ).toFirestore(creation: true);
      final fermentables = data['fermentables'] as List<Map<String, Object?>>;
      expect(fermentables.first, {
        'key': 'malt-pils',
        'name': 'Pils',
        'kind': 'grain',
        'weight_g': 4500.0,
        'ebc': 3.5,
        'yield_pct': 80.0,
      });
      expect(fermentables.last['key'], 'sucre-candi');
      final hops = data['hops'] as List<Map<String, Object?>>;
      expect(hops.map((h) => h['key']), [
        'houblon-citra',
        'houblon-saaz',
        'houblon-mosaic',
      ]);
      expect(hops.map((h) => h['use']), ['boil', 'whirlpool', 'dry_hop']);
      expect(hops[1]['form'], 'leaf');
      expect(hops[2]['time_min'], 4320.0);
      expect((data['yeasts'] as List).single, {
        'key': 'levure-us-05',
        'name': 'US-05',
        'attenuation_pct': 78.0,
        'form': 'dry',
      });
      expect(data.containsKey('style'), isFalse);
      expect(data.containsKey('others'), isFalse);
    });

    test('modification : champ vidé retiré par FieldValue.delete()', () {
      const content = RecipeContent(name: 'Vide');
      final data = content.toFirestore(creation: false);
      expect(data['style'].toString(), contains('FieldValue'));
      expect(data['fermentables'].toString(), contains('FieldValue'));
      expect(const RecipeContent(name: 'Vide').toFirestore(creation: true), {
        'name': 'Vide',
      });
    });

    test('aucun prix ni stock dans le document (P5)', () {
      final data = RecipeContent.fromFirestore(
        _doc(),
      ).toFirestore(creation: true);
      final text = data.toString();
      for (final word in ['price', 'prix', 'stock', 'cost']) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });
  });

  group('calculs', () {
    test('toInput : masses en grammes, durées en minutes', () {
      final input = RecipeContent.fromFirestore(_doc()).toInput();
      expect(input.fermentables.first.massGrams, 4500);
      expect(input.hops.last.minutes, 4320);
      expect(input.batchVolumeLitres, 20);
      final calc = computeRecipe(recipe: input, mashEfficiencyPercent: 72);
      // Le candi n'a pas de rendement d'extrait : aucune valeur par défaut.
      final og = calc.originalGravity as CalculationUnavailable;
      expect(og.missing.single.kind, MissingInputKind.extractYield);
      expect(og.missing.single.items.single.name, 'Candi');
      expect(calc.colorEbc, isA<CalculationUnavailable>());
    });
  });

  group('duplication et tri', () {
    test('« Copie de {nom} » coupé à 120, sans fiche d\'origine', () {
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
    });

    test('malts par masse décroissante, houblons par moment', () {
      const a = FermentableLine(
        name: 'A',
        kind: FermentableKind.malt,
        weightG: 500,
      );
      const b = FermentableLine(
        name: 'B',
        kind: FermentableKind.malt,
        weightG: 4500,
      );
      expect(sortFermentables([a, b]).map((f) => f.name), ['B', 'A']);
      HopLine hop(String name, HopUse use, [double? t]) => HopLine(
        name: name,
        weightG: 10,
        use: use,
        form: HopForm.pellet,
        timeMin: t,
      );
      final sorted = sortHops([
        hop('cru', HopUse.dryHop),
        hop('10', HopUse.boil, 10),
        hop('wp', HopUse.afterBoil),
        hop('60', HopUse.boil, 60),
      ]);
      expect(sorted.map((h) => h.name), ['60', '10', 'wp', 'cru']);
    });
  });

  test(
    'valeur stockée inconnue : l\x27erreur ne contient pas le texte stocké',
    () {
      const secret = 'texte écrit par un autre membre';
      final others = _doc()
        ..['others'] = [
          {'name': 'Coriandre', 'weight_g': 10, 'use': secret},
        ];
      final yeasts = _doc()
        ..['yeasts'] = [
          {'name': 'US-05', 'form': secret},
        ];
      final kinds = _doc();
      (kinds['fermentables'] as List).first['kind'] = secret;
      for (final doc in [others, yeasts, kinds]) {
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
    },
  );
}
