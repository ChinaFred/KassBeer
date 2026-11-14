import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/processes/data/preferences_processus_repository.dart';
import 'package:kass_beer/features/processes/data/processes_repository.dart';
import 'package:kass_beer/features/processes/domain/modele_exemple.dart';
import 'package:kass_beer/features/processes/domain/modele_processus.dart';
import 'package:kass_beer/features/processes/domain/preference_processus.dart';

import 'support/fakes.dart';

/// Toutes les clés de journées et d'éléments de [modele].
List<String> cles(ContenuModele modele) => [
  for (final j in modele.journees) ...[
    j.key,
    for (final e in j.elements) e.key,
  ],
];

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;
  late FirestoreProcessesRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
    repository = FirestoreProcessesRepository(
      errorReportService: errors,
      firestore: firestore,
    );
  });

  Future<Map<String, dynamic>> lire(String id) async =>
      (await firestore.collection('process_templates').doc(id).get()).data()!;

  group('FirestoreProcessesRepository', () {
    test('création : champs des règles, owner_name du jeton', () async {
      final created = repository.create(
        content: modeleExemple(repository.newKey),
        ownerUid: 'uid-a',
        ownerName: 'Alice',
      );
      await created.written;
      final data = await lire(created.id);
      expect(data.keys.toSet(), {
        'format_version',
        'owner_uid',
        'owner_name',
        'name',
        'notes',
        'sessions',
        'created_at',
        'updated_at',
      });
      expect(data['format_version'], 1);
      expect(data['owner_uid'], 'uid-a');
      expect(data['name'], kNomModeleExemple);
      expect(data['sessions'], hasLength(3));
      expect(data['created_at'], isA<Timestamp>());
    });

    test(
      'modèle refusé par erreurModele : rien n\'est écrit, rapporté',
      () async {
        final ok = modeleExemple(repository.newKey);
        final invalide = ContenuModele(
          name: ok.name,
          journees: [
            for (final (i, j) in ok.journees.indexed)
              JourneeModele(
                key: j.key,
                name: j.name,
                // La première journée n'est plus à J+0.
                offsetDays: i == 0 ? 1 : j.offsetDays,
                requiresRecipeBlock: j.requiresRecipeBlock,
                elements: j.elements,
              ),
          ],
        );
        final created = repository.create(
          content: invalide,
          ownerUid: 'uid-a',
          ownerName: null,
        );
        await expectLater(created.written, throwsA(isA<ModeleInvalide>()));
        final doc = await firestore
            .collection('process_templates')
            .doc(created.id)
            .get();
        expect(doc.exists, isFalse);
        expect(errors.reports.single.feature, 'processes.create');
      },
    );

    test('un document illisible est isolé, la liste reste lue', () async {
      final created = repository.create(
        content: modeleExemple(repository.newKey),
        ownerUid: 'uid-a',
        ownerName: null,
      );
      await created.written;
      await firestore.collection('process_templates').doc('casse').set({
        'format_version': 2,
        'owner_uid': 'uid-b',
        'name': 'Futur',
        'sessions': <Object>[],
      });
      final list = await repository.watchAll().first;
      expect(list.valides.single.id, created.id);
      expect(
        list.documents.whereType<DocumentInvalide<ModeleProcessus>>().single.id,
        'casse',
      );
      expect(errors.reports.single.feature, 'processes.read');
      expect(
        errors.reports.single.context,
        'process_templates/casse illisible',
      );
    });

    test('modification : owner_uid et created_at gardés, nom retiré', () async {
      final created = repository.create(
        content: modeleExemple(repository.newKey),
        ownerUid: 'uid-a',
        ownerName: 'Alice',
      );
      await created.written;
      final avant = await lire(created.id);
      final source = ModeleProcessus.fromFirestore(created.id, avant);
      await repository.update(
        id: created.id,
        content: ContenuModele(
          name: 'Mon déroulé',
          journees: source.content.journees,
        ),
        ownerName: null,
      );
      final apres = await lire(created.id);
      expect(apres['name'], 'Mon déroulé');
      expect(apres['owner_uid'], 'uid-a');
      expect(apres['created_at'], avant['created_at']);
      expect(apres.containsKey('owner_name'), isFalse);
      expect(apres['notes'], isNull);
    });

    test('copie : nouveau document au nom du lecteur, clés neuves', () async {
      final created = repository.create(
        content: modeleExemple(repository.newKey),
        ownerUid: 'uid-zoe',
        ownerName: 'Zoé',
      );
      await created.written;
      final source = ModeleProcessus.fromFirestore(
        created.id,
        await lire(created.id),
      );
      final copie = repository.copy(
        source: source,
        ownerUid: 'uid-a',
        ownerName: 'Alice',
      );
      await copie.written;
      expect(copie.id, isNot(created.id));
      final lu = ModeleProcessus.fromFirestore(copie.id, await lire(copie.id));
      expect(lu.ownerUid, 'uid-a');
      expect(lu.ownerName, 'Alice');
      expect(lu.content.name, source.content.name);
      expect(
        cles(lu.content).toSet().intersection(cles(source.content).toSet()),
        isEmpty,
      );
      // La source n'est pas écrite.
      expect((await lire(created.id))['owner_uid'], 'uid-zoe');
    });

    test('duplication : « {nom} (copie) »', () async {
      final created = repository.create(
        content: modeleExemple(repository.newKey),
        ownerUid: 'uid-a',
        ownerName: null,
      );
      await created.written;
      final source = ModeleProcessus.fromFirestore(
        created.id,
        await lire(created.id),
      );
      final copie = repository.duplicate(
        source: source,
        ownerUid: 'uid-a',
        ownerName: null,
      );
      await copie.written;
      expect((await lire(copie.id))['name'], '$kNomModeleExemple (copie)');
    });

    test('suppression', () async {
      final created = repository.create(
        content: modeleExemple(repository.newKey),
        ownerUid: 'uid-a',
        ownerName: null,
      );
      await created.written;
      await repository.delete(created.id);
      final doc = await firestore
          .collection('process_templates')
          .doc(created.id)
          .get();
      expect(doc.exists, isFalse);
    });
  });

  group('FirestorePreferencesProcessusRepository', () {
    late FirestorePreferencesProcessusRepository preferences;
    setUp(
      () => preferences = FirestorePreferencesProcessusRepository(
        errorReportService: errors,
        firestore: firestore,
      ),
    );

    test('absent : aucun défaut', () async {
      final lu = await preferences.watch('uid-a').first;
      expect(lu, isA<DocumentAbsent<PreferenceProcessus>>());
      expect(idModeleParDefaut(lu), isNull);
    });

    test('écriture du défaut, puis retour à la chronologie seule', () async {
      await preferences.saveDefault(uid: 'uid-a', templateId: 'p1');
      final ref = firestore
          .collection('users')
          .doc('uid-a')
          .collection('preferences')
          .doc('processes');
      final data = (await ref.get()).data()!;
      expect(data.keys.toSet(), {'default_template_id', 'updated_at'});
      expect(data['default_template_id'], 'p1');
      expect(idModeleParDefaut(await preferences.watch('uid-a').first), 'p1');

      await preferences.saveDefault(uid: 'uid-a', templateId: null);
      expect((await ref.get()).data()!['default_template_id'], isNull);
      expect(idModeleParDefaut(await preferences.watch('uid-a').first), isNull);
    });

    test('illisible : rapporté, aucun défaut', () async {
      await firestore
          .collection('users')
          .doc('uid-a')
          .collection('preferences')
          .doc('processes')
          .set({'default_template_id': 12});
      final lu = await preferences.watch('uid-a').first;
      expect(lu, isA<DocumentIllisibleTrouve<PreferenceProcessus>>());
      expect(idModeleParDefaut(lu), isNull);
      expect(errors.reports.single.feature, 'processes.preference_read');
    });
  });
}
