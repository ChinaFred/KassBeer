import 'package:brewing/brewing.dart' show StepEventKind;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/brews/data/brews_repository.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/data/recipes_repository.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;
  late FirestoreBrewsRepository repository;

  final at = DateTime(2026, 11, 8, 11, 45);

  setUp(() {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
    repository = FirestoreBrewsRepository(
      errorReportService: errors,
      firestore: firestore,
    );
  });

  final recette = Recipe(
    id: 'r1',
    ownerUid: 'uid-auteur',
    ownerName: 'Auteur',
    updatedAt: DateTime(2026, 1, 2),
    content: const RecipeContent(
      name: ' Blonde ',
      brewSteps: [palier, ebullition],
    ),
  );
  const equipement = Equipment(
    id: 'e1',
    ownerUid: 'uid-auteur',
    ownerName: 'Auteur',
    content: equipementTest,
  );

  Future<CreationEnCours> creer({String? ownerName = 'Bruno'}) async {
    final created = repository.create(
      recipe: recette,
      equipment: equipement,
      name: 'Blonde 1',
      plannedFor: DateTime(2026, 11, 15),
      ownerUid: 'uid-brasseur',
      ownerName: ownerName,
    );
    await created.written;
    return created;
  }

  Future<Map<String, dynamic>> docBrassin(String id) async =>
      (await firestore.collection('brews').doc(id).get()).data()!;

  group('création', () {
    test('notes recopiées à la recréation', () async {
      final created = repository.create(
        recipe: recette,
        equipment: equipement,
        name: 'Blonde',
        plannedFor: null,
        ownerUid: 'u',
        ownerName: null,
        notes: ' levure fraîche ',
      );
      await created.written;
      expect((await docBrassin(created.id))['notes'], 'levure fraîche');
    });

    test('copie figée, owner_name du jeton, statut prévu', () async {
      final created = await creer();
      final data = await docBrassin(created.id);
      expect(data['status'], 'planned');
      expect(data['owner_uid'], 'uid-brasseur');
      expect(data['owner_name'], 'Bruno');
      expect(data['recipe_id'], 'r1');
      final snapshot = data['recipe_snapshot'] as Map<String, dynamic>;
      expect(snapshot['name'], 'Blonde');
      expect(snapshot['owner_uid'], 'uid-auteur');
      expect((snapshot['brew_steps'] as List<dynamic>).length, 2);
      final equipment = data['equipment_snapshot'] as Map<String, dynamic>;
      expect(equipment['name'], 'Grainfather');
      expect(data.containsKey('brewed_at'), isFalse);
    });

    test('nom du jeton absent : owner_name absent', () async {
      final created = await creer(ownerName: null);
      expect((await docBrassin(created.id)).containsKey('owner_name'), isFalse);
    });

    test('éléments de brew_steps : liste blanche des champs', () async {
      final created = await creer();
      final data = await docBrassin(created.id);
      final step =
          ((data['recipe_snapshot'] as Map<String, dynamic>)['brew_steps']
                      as List<dynamic>)
                  .first
              as Map<String, dynamic>;
      expect(step.keys.toSet(), {'key', 'name', 'duration_min', 'temp_c'});
    });

    test('aucun champ brew_steps écrit pour une recette sans chronologie', () {
      final content = const RecipeContent(
        name: 'Sans',
      ).toFirestore(creation: true);
      expect(content.containsKey('brew_steps'), isFalse);
    });
  });

  group('owner_name réécrit à chaque écriture du brassin', () {
    test('commencer : statut, heure, premier début, nom du jeton', () async {
      final created = await creer();
      await repository.start(
        brewId: created.id,
        ownerUid: 'uid-brasseur',
        at: at,
        firstStepKey: 'k-palier',
        ownerName: 'Nouveau Nom',
      );
      final data = await docBrassin(created.id);
      expect(data['status'], 'brewing');
      expect(data['brewed_at'], Timestamp.fromDate(at));
      expect(data['owner_name'], 'Nouveau Nom');
      final events = await firestore
          .collection('brews/${created.id}/events')
          .get();
      final event = events.docs.single.data();
      expect(event['kind'], 'step_started');
      expect(event['measured_at'], Timestamp.fromDate(at));
    });

    test(
      'commencer sans nom lisible : champ retiré, pas de valeur périmée',
      () async {
        final created = await creer();
        await repository.start(
          brewId: created.id,
          ownerUid: 'uid-brasseur',
          at: at,
          firstStepKey: null,
          ownerName: null,
        );
        final data = await docBrassin(created.id);
        expect(data.containsKey('owner_name'), isFalse);
      },
    );

    test('terminer : fermenting, owner_name réécrit ou retiré', () async {
      final created = await creer();
      await repository.finish(brewId: created.id, ownerName: 'Bruno');
      expect((await docBrassin(created.id))['status'], 'fermenting');
      await repository.finish(brewId: created.id, ownerName: null);
      expect((await docBrassin(created.id)).containsKey('owner_name'), isFalse);
    });

    test('modifier : nom et notes, owner_name réécrit', () async {
      final created = await creer();
      await repository.update(
        id: created.id,
        name: ' Blonde 2 ',
        plannedFor: null,
        notes: ' note ',
        ownerName: 'Bruno',
      );
      final data = await docBrassin(created.id);
      expect(data['name'], 'Blonde 2');
      expect(data['notes'], 'note');
      expect(data.containsKey('planned_for'), isFalse);
      expect(data['owner_name'], 'Bruno');
    });
  });

  group('événements', () {
    test(
      'identifiant de l\'appareil et measured_at ; aucune heure prévue',
      () async {
        await firestore.collection('brews').doc('b1').set({'owner_uid': 'u'});
        await repository.writeSteps(
          brewId: 'b1',
          ownerUid: 'u',
          writes: const [(kind: StepEventKind.started, stepKey: 'k1')],
          at: at,
        );
        final snap = await firestore.collection('brews/b1/events').get();
        final data = snap.docs.single.data();
        expect(snap.docs.single.id, isNotEmpty);
        expect(data['measured_at'], Timestamp.fromDate(at));
        expect(data['step_key'], 'k1');
        expect(data.keys.toSet(), {
          'owner_uid',
          'kind',
          'step_key',
          'measure_type',
          'value',
          'measured_at',
          'created_at',
        });
      },
    );

    test('plusieurs écritures : un seul lot, même instant', () async {
      await repository.writeSteps(
        brewId: 'b1',
        ownerUid: 'u',
        writes: const [
          (kind: StepEventKind.ended, stepKey: 'k1'),
          (kind: StepEventKind.started, stepKey: 'k2'),
        ],
        at: at,
      );
      final snap = await firestore.collection('brews/b1/events').get();
      expect(snap.docs.length, 2);
      expect(
        {for (final d in snap.docs) d['kind']},
        {'step_ended', 'step_started'},
      );
    });

    test('mesure : type et valeur stockés en SI', () async {
      final created = repository.addEvent(
        brewId: 'b1',
        input: BrewEventInput(
          ownerUid: 'u',
          kind: BrewEventKind.measurement,
          measureType: MeasureType.gravity,
          value: 1.0579,
          measuredAt: at,
        ),
      );
      await created.written;
      final data =
          (await firestore.collection('brews/b1/events').doc(created.id).get())
              .data()!;
      expect(data['value'], 1.0579);
      expect(data['measure_type'], 'gravity');
    });

    test('correction : valeur, note et heure seulement', () async {
      final doc = firestore.collection('brews/b1/events').doc('e1');
      await doc.set({
        'owner_uid': 'u',
        'kind': 'measurement',
        'measure_type': 'temperature',
        'value': 66.0,
        'measured_at': Timestamp.fromDate(at),
        'created_at': Timestamp.fromDate(at),
      });
      await repository.correct(
        brewId: 'b1',
        eventId: 'e1',
        value: 67.5,
        note: 'corrigé',
        measuredAt: at.add(const Duration(minutes: 1)),
      );
      final data = (await doc.get()).data()!;
      expect(data['value'], 67.5);
      expect(data['note'], 'corrigé');
      expect(data['kind'], 'measurement');
    });

    test('restaurer : même identifiant, même heure', () async {
      final event = debut('e9', 'k1', at);
      await repository.restoreEvent(brewId: 'b1', event: event);
      final data =
          (await firestore.collection('brews/b1/events').doc('e9').get())
              .data()!;
      expect(data['measured_at'], Timestamp.fromDate(at));
      expect(data['kind'], 'step_started');
    });

    test('event illisible : rapporté, document rendu comme tel', () async {
      await firestore.collection('brews/b1/events').doc('bad').set({
        'owner_uid': 'u',
        'kind': 'nature_inconnue',
        'measured_at': Timestamp.fromDate(at),
      });
      final list = await repository.watchEvents('b1').first;
      expect(list.documents.single, isA<DocumentInvalide<BrewEvent>>());
      expect(errors.reports.single.feature, 'brews.event_read');
    });
  });

  group('HS7 : saisie refusée', () {
    final refus = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    test(
      'événement déjà sur le serveur : refus ignoré, rien d\'annoncé',
      () async {
        final ref = firestore.collection('brews/b1/events').doc('e1');
        await ref.set({'kind': 'step_started'});
        await repository.creationSuivie(
          refs: [ref],
          kinds: const ['step_started'],
          write: () async => throw refus,
        );
        expect(errors.reports.single.feature, 'brews.event_replayed');
      },
    );

    test('événement absent du serveur : rapporté et relancé', () async {
      final ref = firestore.collection('brews/b1/events').doc('absent');
      await expectLater(
        repository.creationSuivie(
          refs: [ref],
          kinds: const ['measurement:gravity'],
          write: () async => throw refus,
        ),
        throwsA(same(refus)),
      );
      expect(errors.reports.single.feature, 'brews.event_rejected');
    });
  });

  group('suppression', () {
    test('avec saisies : les événements puis le brassin', () async {
      final brew = firestore.collection('brews').doc('b1');
      await brew.set({'owner_uid': 'u'});
      for (final id in ['e1', 'e2', 'e3']) {
        await brew.collection('events').doc(id).set({'kind': 'note'});
      }
      await repository.deleteWithEvents('b1', ownerUid: 'u');
      expect((await brew.get()).exists, isFalse);
      expect((await brew.collection('events').get()).docs, isEmpty);
    });

    test('sans saisie : brassin supprimé', () async {
      final brew = firestore.collection('brews').doc('b1');
      await brew.set({'owner_uid': 'u'});
      await repository.delete('b1', ownerUid: 'u');
      expect((await brew.get()).exists, isFalse);
    });
  });

  test('Préparer : réponse du serveur, n\'écrit rien (PR4)', () async {
    await firestore.collection('brews').doc('b1').set({'owner_uid': 'u'});
    final ok = await repository.attendreServeur(
      'b1',
      limite: const Duration(seconds: 1),
    );
    expect(ok, isTrue);
    final data = (await firestore.collection('brews').doc('b1').get()).data();
    expect(data, {'owner_uid': 'u'});
    expect((await firestore.collection('brews/b1/events').get()).docs, isEmpty);
  });

  test('lecture : brassin illisible rapporté, copie relue', () async {
    await firestore.collection('brews').doc('mauvais').set({'owner_uid': 'u'});
    await firestore.collection('brews').doc('b1').set({
      'owner_uid': 'u',
      'name': 'Blonde',
      'status': 'brewing',
      'recipe_snapshot': {
        'name': 'Blonde',
        'brew_steps': [
          {'key': 'k1', 'name': 'Palier', 'duration_min': 45},
        ],
      },
      'equipment_snapshot': {'name': 'Cuve', 'kind': 'multi_vessel'},
      'brewed_at': Timestamp.fromDate(at),
    });
    final list = await repository.watchAll().first;
    final brew = list.valides.single;
    expect(brew.status, BrewStatus.brewing);
    expect(brew.recipe.brewSteps.single.key, 'k1');
    expect(brew.equipment.name, 'Cuve');
    expect(list.documents.whereType<DocumentInvalide<Brew>>(), hasLength(1));
    expect(errors.reports.single.feature, 'brews.read');
  });

  group('recettes : chronologie', () {
    late FirestoreRecipesRepository recipes;
    setUp(
      () => recipes = FirestoreRecipesRepository(
        errorReportService: errors,
        firestore: firestore,
      ),
    );

    test(
      'updateBrewSteps : n\'écrit que brew_steps, owner_name, updated_at',
      () async {
        final doc = firestore.collection('recipes').doc('r1');
        await doc.set({
          'owner_uid': 'u',
          'name': 'Blonde',
          'created_at': Timestamp.fromDate(at),
          'updated_at': Timestamp.fromDate(at),
        });
        await recipes.updateBrewSteps(
          id: 'r1',
          steps: const [palier, ebullition],
          ownerName: 'Bruno',
        );
        final data = (await doc.get()).data()!;
        expect(data['name'], 'Blonde');
        expect(data['owner_name'], 'Bruno');
        expect(
          ((data['brew_steps'] as List<dynamic>).first as Map<String, dynamic>)
              .keys
              .toSet(),
          {'key', 'name', 'duration_min', 'temp_c'},
        );
      },
    );

    test('chronologie hors limites refusée et rapportée', () async {
      await expectLater(
        recipes.updateBrewSteps(
          id: 'r1',
          steps: const [
            BrewStepLine(key: 'k1', name: 'Long', durationMin: 700),
          ],
          ownerName: null,
        ),
        throwsA(anything),
      );
      expect(errors.reports.single.feature, 'recipes.brew_steps_update');
    });

    test(
      'chronologie illisible : recette lisible, problème rapporté',
      () async {
        await firestore.collection('recipes').doc('r1').set({
          'owner_uid': 'u',
          'name': 'Blonde',
          'brew_steps': [
            {'key': 'k', 'name': 'A', 'duration_min': 1},
            {'key': 'k', 'name': 'B', 'duration_min': 1},
          ],
        });
        final list = await recipes.watchAll().first;
        expect(list.valides.single.content.brewStepsProblem, isNotNull);
        expect(errors.reports.single.feature, 'recipes.brew_steps');
      },
    );
  });
}
