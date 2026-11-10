import 'package:brewing/brewing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/equipment/data/equipment_repository.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/data/recipes_repository.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/fakes.dart';

Map<String, dynamic> _ingredients(Map<String, dynamic> data) =>
    (data['recipe'] as Map<String, dynamic>)['ingredients']
        as Map<String, dynamic>;

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
  });

  group('FirestoreEquipmentRepository', () {
    late FirestoreEquipmentRepository repository;
    setUp(
      () => repository = FirestoreEquipmentRepository(
        errorReportService: errors,
        firestore: firestore,
      ),
    );

    const content = EquipmentContent(
      name: ' Grainfather ',
      kind: EquipmentKind.allInOne,
      mashEfficiencyPct: 72,
      mashTunVolumeL: 30,
      kettleVolumeL: 40,
    );

    test('création : champs des règles, owner_name du jeton', () async {
      final created = repository.create(
        content: content,
        ownerUid: 'uid-a',
        ownerName: 'Alice',
      );
      await created.written;
      final data =
          (await firestore.collection('equipment').doc(created.id).get())
              .data()!;
      expect(data.keys.toSet(), {
        'owner_uid',
        'owner_name',
        'name',
        'kind',
        'mash_efficiency_pct',
        'mash_tun_volume_l',
        'created_at',
        'updated_at',
      });
      expect(data['owner_uid'], 'uid-a');
      expect(data['owner_name'], 'Alice');
      expect(data['name'], 'Grainfather');
      expect(data['kind'], 'all_in_one');
      // Tout-en-un : pas de cuve d'ébullition.
      expect(data.containsKey('kettle_volume_l'), isFalse);
      expect(data['created_at'], isA<Timestamp>());
    });

    test('création sans nom de jeton : owner_name absent', () async {
      final created = repository.create(
        content: content,
        ownerUid: 'uid-a',
        ownerName: null,
      );
      await created.written;
      final data =
          (await firestore.collection('equipment').doc(created.id).get())
              .data()!;
      expect(data.containsKey('owner_name'), isFalse);
    });

    test(
      'modification : owner_uid et created_at inchangés, champ vidé et nom retirés',
      () async {
        final created = repository.create(
          content: content,
          ownerUid: 'uid-a',
          ownerName: 'Alice',
        );
        await created.written;
        final ref = firestore.collection('equipment').doc(created.id);
        final before = (await ref.get()).data()!;
        await repository.update(
          id: created.id,
          content: const EquipmentContent(
            name: 'Grainfather G30',
            kind: EquipmentKind.multiVessel,
            kettleVolumeL: 40,
          ),
          ownerName: null,
        );
        final after = (await ref.get()).data()!;
        expect(after['owner_uid'], 'uid-a');
        expect(after['created_at'], before['created_at']);
        expect(after['name'], 'Grainfather G30');
        expect(after['kind'], 'multi_vessel');
        expect(after['kettle_volume_l'], 40);
        expect(after.containsKey('mash_efficiency_pct'), isFalse);
        expect(after.containsKey('owner_name'), isFalse);
      },
    );

    test('lecture : document illisible rapporté, jamais complété', () async {
      await firestore.collection('equipment').doc('bon').set({
        'owner_uid': 'uid-a',
        'name': 'Bon',
        'kind': 'multi_vessel',
      });
      await firestore.collection('equipment').doc('mauvais').set({
        'owner_uid': 'uid-a',
        'name': 'Mauvais',
        'kind': 'brewzilla',
      });
      final list = await repository.watchAll().first;
      expect(list.valides.map((e) => e.name), ['Bon']);
      expect(
        list.chercher('mauvais'),
        isA<DocumentIllisibleTrouve<Equipment>>(),
      );
      expect(list.chercher('absent'), isA<DocumentAbsent<Equipment>>());
      expect(errors.reports.single.feature, 'equipment.read');
    });

    test('suppression', () async {
      final created = repository.create(
        content: content,
        ownerUid: 'uid-a',
        ownerName: 'Alice',
      );
      await created.written;
      await repository.delete(created.id);
      expect(
        (await firestore.collection('equipment').doc(created.id).get()).exists,
        isFalse,
      );
    });

    test('refus : rapporté et relancé', () async {
      await expectLater(
        repository.update(id: 'absent', content: content, ownerName: null),
        throwsA(anything),
      );
      expect(errors.reports.single.feature, 'equipment.update');
    });
  });

  group('FirestoreRecipesRepository', () {
    late FirestoreRecipesRepository repository;
    setUp(
      () => repository = FirestoreRecipesRepository(
        errorReportService: errors,
        firestore: firestore,
      ),
    );

    final content = RecipeContent(
      name: 'Blonde',
      batchVolumeL: 20,
      equipmentId: 'eq-1',
      fermentables: const [
        FermentableLine(
          name: 'Pils',
          kind: FermentableKind.malt,
          weightG: 4500,
          yieldPct: 80,
        ),
      ],
    );

    Future<Map<String, dynamic>> read(String id) async =>
        (await firestore.collection('recipes').doc(id).get()).data()!;

    test(
      'création : enveloppe, recipe en BeerJSON, sans clé stockée',
      () async {
        final created = repository.create(
          content: content,
          ownerUid: 'uid-a',
          ownerName: 'Alice',
        );
        await created.written;
        final data = await read(created.id);
        expect(data['owner_uid'], 'uid-a');
        expect(data['owner_name'], 'Alice');
        expect(data.keys.toSet(), {
          'format_version',
          'owner_uid',
          'owner_name',
          'equipment_id',
          'recipe',
          'created_at',
          'updated_at',
        });
        expect(data['format_version'], 1);
        final fermentable =
            (_ingredients(data)['fermentable_additions'] as List).single as Map;
        expect(fermentable.containsKey('key'), isFalse);
        expect(fermentable['amount'], {'value': 4500.0, 'unit': 'g'});
        expect(data['created_at'], isA<Timestamp>());
        expect(data.containsKey('imported_from'), isFalse);
      },
    );

    test(
      'modification : owner_uid et created_at inchangés, nom réécrit',
      () async {
        final created = repository.create(
          content: content,
          ownerUid: 'uid-a',
          ownerName: 'Alice',
        );
        await created.written;
        final before = await read(created.id);
        await repository.update(
          id: created.id,
          content: const RecipeContent(name: 'Blonde 2', style: 'Blonde'),
          ownerName: 'Alice Martin',
        );
        final after = await read(created.id);
        expect(after['owner_uid'], 'uid-a');
        expect(after['created_at'], before['created_at']);
        expect(after['owner_name'], 'Alice Martin');
        final recipe = after['recipe'] as Map<String, dynamic>;
        expect(recipe['style'], {'name': 'Blonde'});
        expect(recipe['name'], 'Blonde 2');
        // `recipe` est écrite d'un bloc. fake_cloud_firestore fusionne une map
        // écrite par update, Firestore la remplace : le remplacement est vérifié
        // contre l'émulateur (rules-tests/test/recipe_format.test.mjs).
        expect(_ingredients(after)['fermentable_additions'], isEmpty);
        expect(after.containsKey('equipment_id'), isFalse);
      },
    );

    test('duplication : copie au nom du lecteur, source inchangée', () async {
      final created = repository.create(
        content: content,
        ownerUid: 'uid-a',
        ownerName: 'Alice',
      );
      await created.written;
      final source = (await repository.watchAll().first).valides.single;
      final copy = repository.duplicate(
        source: source,
        ownerUid: 'uid-b',
        ownerName: 'Bruno',
      );
      await copy.written;
      final data = await read(copy.id);
      expect((data['recipe'] as Map)['name'], 'Copie de Blonde');
      expect(data['owner_uid'], 'uid-b');
      expect(data['owner_name'], 'Bruno');
      expect(data['equipment_id'], 'eq-1');
      expect(
        ((_ingredients(data)['fermentable_additions'] as List).single
            as Map)['name'],
        'Pils',
      );
      final original = await read(created.id);
      expect((original['recipe'] as Map)['name'], 'Blonde');
      expect(original['owner_uid'], 'uid-a');
    });

    test('suppression', () async {
      final created = repository.create(
        content: content,
        ownerUid: 'uid-a',
        ownerName: null,
      );
      await created.written;
      await repository.delete(created.id);
      expect(
        (await firestore.collection('recipes').doc(created.id).get()).exists,
        isFalse,
      );
    });

    test('refus : rapporté et relancé', () async {
      await expectLater(
        repository.update(id: 'absent', content: content, ownerName: null),
        throwsA(anything),
      );
      expect(errors.reports.single.feature, 'recipes.update');
    });

    test(
      'nom d\'ingrédient sans lettre : enregistrement refusé, rapporté',
      () async {
        final created = repository.create(
          content: const RecipeContent(
            name: 'Bizarre',
            hops: [
              HopLine(
                name: '---',
                weightG: 10,
                use: HopUse.boil,
                form: HopForm.pellet,
              ),
            ],
          ),
          ownerUid: 'uid-a',
          ownerName: null,
        );
        await expectLater(
          created.written,
          throwsA(isA<BrewingInputException>()),
        );
        expect(errors.reports.single.feature, 'recipes.create');
      },
    );

    test(
      'document plat de la v0.1.14 : recette illisible, rapportée',
      () async {
        await firestore.collection('recipes').doc('vieille').set({
          'owner_uid': 'uid-a',
          'name': 'Vieille',
          'fermentables': [
            {'name': 'Pils', 'kind': 'grain', 'weight_g': 1000},
          ],
        });
        final list = await repository.watchAll().first;
        expect(
          list.chercher('vieille'),
          isA<DocumentIllisibleTrouve<Recipe>>(),
        );
        final report = errors.reports.single;
        expect(report.feature, 'recipes.read');
        expect(report.error.toString(), contains('format_version'));
      },
    );

    test(
      'valeur que l\'application ne lit pas (extrait sec) : recette illisible, '
      'rapportée sans la valeur',
      () async {
        await firestore.collection('recipes').doc('extrait').set({
          'format_version': 1,
          'owner_uid': 'uid-a',
          'recipe': {
            'name': 'Extrait',
            'ingredients': {
              'fermentable_additions': [
                {
                  'name': 'Extrait sec',
                  'type': 'dry extract',
                  'amount': {'value': 1000, 'unit': 'g'},
                },
              ],
            },
          },
        });
        final list = await repository.watchAll().first;
        expect(
          list.chercher('extrait'),
          isA<DocumentIllisibleTrouve<Recipe>>(),
        );
        final report = errors.reports.single;
        expect(report.feature, 'recipes.read');
        expect(report.error.toString(), isNot(contains('dry extract')));
      },
    );
  });
}
