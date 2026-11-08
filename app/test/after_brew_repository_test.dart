import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/features/brews/data/brews_repository.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/releves.dart';

import 'support/fakes.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;
  late FirestoreBrewsRepository repository;

  const brewId = 'b1';
  const owner = 'uid-brasseur';
  final at = DateTime(2026, 11, 15, 18, 30);

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
    repository = FirestoreBrewsRepository(
      errorReportService: errors,
      firestore: firestore,
    );
    await firestore.collection('brews').doc(brewId).set({
      'owner_uid': owner,
      'name': 'Blonde',
      'status': 'fermenting',
      'recipe_snapshot': {'name': 'Blonde'},
      'equipment_snapshot': {'name': 'Cuve', 'kind': 'all_in_one'},
    });
  });

  CollectionReference<Map<String, dynamic>> events() =>
      firestore.collection('brews').doc(brewId).collection('events');

  Future<Map<String, Map<String, dynamic>>> relus() async {
    final docs = await events().get();
    return {for (final d in docs.docs) d.id: d.data()};
  }

  Future<Map<String, dynamic>> brassin() async =>
      (await firestore.collection('brews').doc(brewId).get()).data()!;

  group('relevé (FE4, FE5)', () {
    test(
      'densité et température : deux événements, même heure, note sur le premier',
      () async {
        final created = repository.addReleve(
          brewId: brewId,
          ownerUid: owner,
          releve: ReleveSaisi(
            gravity: 1.02,
            temperature: 18.5,
            note: ' Fermentation active ',
            measuredAt: at,
          ),
        );
        await created.written;
        final data = await relus();
        expect(data.length, 2);
        final byType = {for (final d in data.values) d['measure_type']: d};
        expect(byType['gravity']!['value'], 1.02);
        expect(byType['gravity']!['note'], 'Fermentation active');
        expect(byType['gravity']!['phase'], 'fermentation');
        expect(byType['gravity']!['step_key'], isNull);
        expect(byType['temperature']!['value'], 18.5);
        expect(byType['temperature']!.containsKey('note'), isFalse);
        expect(
          byType['gravity']!['measured_at'],
          byType['temperature']!['measured_at'],
        );
        expect(created.ids.length, 2);
      },
    );

    test('note seule : événement note, phase fermentation', () async {
      await repository
          .addReleve(
            brewId: brewId,
            ownerUid: owner,
            releve: ReleveSaisi(note: 'Bulles', measuredAt: at),
          )
          .written;
      final data = (await relus()).values.single;
      expect(data['kind'], 'note');
      expect(data['note'], 'Bulles');
      expect(data['phase'], 'fermentation');
    });
  });

  group('correction (FE9)', () {
    Future<Releve> releveExistant({
      double? gravity,
      double? temperature,
      String? note,
    }) async {
      final created = repository.addReleve(
        brewId: brewId,
        ownerUid: owner,
        releve: ReleveSaisi(
          gravity: gravity,
          temperature: temperature,
          note: note,
          measuredAt: at,
        ),
      );
      await created.written;
      final docs = await events().get();
      return relevesDe([
        for (final d in docs.docs) BrewEvent.fromFirestore(d.id, d.data()),
      ]).single;
    }

    test('valeurs et heure corrigées', () async {
      final avant = await releveExistant(gravity: 1.02, temperature: 18);
      final nouvelleHeure = at.add(const Duration(hours: 1));
      await repository.correctReleve(
        brewId: brewId,
        ownerUid: owner,
        avant: avant,
        releve: ReleveSaisi(
          gravity: 1.019,
          temperature: 17.5,
          measuredAt: nouvelleHeure,
        ),
      );
      final data = await relus();
      expect(data.length, 2);
      final byType = {for (final d in data.values) d['measure_type']: d};
      expect(byType['gravity']!['value'], 1.019);
      expect(byType['temperature']!['value'], 17.5);
      expect(
        byType['temperature']!['measured_at'],
        Timestamp.fromDate(nouvelleHeure),
      );
    });

    test('température vidée : son événement est supprimé', () async {
      final avant = await releveExistant(gravity: 1.02, temperature: 18);
      await repository.correctReleve(
        brewId: brewId,
        ownerUid: owner,
        avant: avant,
        releve: ReleveSaisi(gravity: 1.02, measuredAt: at),
      );
      final data = await relus();
      expect(data.length, 1);
      expect(data.values.single['measure_type'], 'gravity');
    });

    test(
      'température ajoutée : créée à la même heure, phase fermentation',
      () async {
        final avant = await releveExistant(gravity: 1.02);
        await repository.correctReleve(
          brewId: brewId,
          ownerUid: owner,
          avant: avant,
          releve: ReleveSaisi(gravity: 1.02, temperature: 18, measuredAt: at),
        );
        final data = await relus();
        expect(data.length, 2);
        final t = data.values.firstWhere(
          (d) => d['measure_type'] == 'temperature',
        );
        expect(t['phase'], 'fermentation');
        expect(t['measured_at'], Timestamp.fromDate(at));
      },
    );

    test(
      'note seule remplacée par des valeurs : note portée par la mesure',
      () async {
        final avant = await releveExistant(note: 'Bulles');
        await repository.correctReleve(
          brewId: brewId,
          ownerUid: owner,
          avant: avant,
          releve: ReleveSaisi(gravity: 1.02, note: 'Bulles', measuredAt: at),
        );
        final data = (await relus()).values.single;
        expect(data['kind'], 'measurement');
        expect(data['note'], 'Bulles');
      },
    );

    test(
      'densité vidée, note gardée : la note passe sur la température',
      () async {
        final avant = await releveExistant(
          gravity: 1.02,
          temperature: 18,
          note: 'Bulles',
        );
        await repository.correctReleve(
          brewId: brewId,
          ownerUid: owner,
          avant: avant,
          releve: ReleveSaisi(temperature: 18, note: 'Bulles', measuredAt: at),
        );
        final data = (await relus()).values.single;
        expect(data['measure_type'], 'temperature');
        expect(data['note'], 'Bulles');
      },
    );
  });

  test(
    'FE10 : suppression puis Annuler : mêmes identifiants, heure et phase',
    () async {
      final created = repository.addReleve(
        brewId: brewId,
        ownerUid: owner,
        releve: ReleveSaisi(gravity: 1.02, temperature: 18, measuredAt: at),
      );
      await created.written;
      final docs = await events().get();
      final saved = [
        for (final d in docs.docs) BrewEvent.fromFirestore(d.id, d.data()),
      ];
      await repository.deleteEvents(brewId: brewId, eventIds: created.ids);
      expect(await relus(), isEmpty);
      await repository.restoreEvents(brewId: brewId, events: saved);
      final data = await relus();
      expect(data.keys.toSet(), created.ids.toSet());
      for (final d in data.values) {
        expect(d['phase'], 'fermentation');
        expect(d['measured_at'], Timestamp.fromDate(at));
      }
    },
  );

  test('ST8 : statut, owner_name et updated_at', () async {
    await repository.setStatus(
      brewId: brewId,
      status: BrewStatus.abandoned,
      ownerName: 'Bruno',
    );
    final data = await brassin();
    expect(data['status'], 'abandoned');
    expect(data['owner_name'], 'Bruno');
    expect(data['updated_at'], isA<Timestamp>());
  });

  group('embouteillage (EM1)', () {
    final bottled = DateTime(2026, 11, 20, 18, 30);

    test('densité finale : relevé à bottled_at dans le même lot', () async {
      await repository.saveBottling(
        brewId: brewId,
        ownerUid: owner,
        embouteillage: Embouteillage(
          bottledAt: bottled,
          bottlesCount: 60,
          packagedVolumeL: 19.5,
          primingSugarG: 120,
          primingSugarName: 'Saccharose',
        ),
        nouveauStatut: BrewStatus.conditioning,
        finalGravity: 1.012,
        ownerName: null,
      );
      final data = await brassin();
      expect(data['status'], 'conditioning');
      expect(data['bottled_at'], Timestamp.fromDate(bottled));
      expect(data['bottles_count'], 60);
      expect(data['priming_sugar_name'], 'Saccharose');
      final releve = (await relus()).values.single;
      expect(releve['measure_type'], 'gravity');
      expect(releve['value'], 1.012);
      expect(releve['phase'], 'fermentation');
      expect(releve['measured_at'], Timestamp.fromDate(bottled));
    });

    test(
      'champs vides : retirés ; modification : statut inchangé, aucun relevé',
      () async {
        await repository.saveBottling(
          brewId: brewId,
          ownerUid: owner,
          embouteillage: Embouteillage(bottledAt: bottled, bottlesCount: 60),
          nouveauStatut: BrewStatus.conditioning,
          ownerName: null,
        );
        await repository.saveBottling(
          brewId: brewId,
          ownerUid: owner,
          embouteillage: Embouteillage(bottledAt: bottled),
          nouveauStatut: null,
          ownerName: null,
        );
        final data = await brassin();
        expect(data['status'], 'conditioning');
        expect(data.containsKey('bottles_count'), isFalse);
        expect(await relus(), isEmpty);
      },
    );
  });

  group('mesure retenue (VR4, VR5)', () {
    test('le choix écrit l\'identifiant, jamais la valeur', () async {
      await repository.setMesureRetenue(
        brewId: brewId,
        champ: MesureRetenueChamp.densiteInitiale,
        eventId: 'e7',
        ownerName: null,
      );
      final data = await brassin();
      expect(data['og_event_id'], 'e7');
      expect(data.containsKey('value'), isFalse);
    });

    test('« Dernière mesure » retire le champ', () async {
      await repository.setMesureRetenue(
        brewId: brewId,
        champ: MesureRetenueChamp.volumeFermenteur,
        eventId: 'e7',
        ownerName: null,
      );
      await repository.setMesureRetenue(
        brewId: brewId,
        champ: MesureRetenueChamp.volumeFermenteur,
        eventId: null,
        ownerName: null,
      );
      expect(
        (await brassin()).containsKey('fermenter_volume_event_id'),
        isFalse,
      );
    });

    test('sucres dans le moût : booléen écrit', () async {
      await repository.setSugarsInWort(
        brewId: brewId,
        value: true,
        ownerName: 'Bruno',
      );
      final data = await brassin();
      expect(data['sugars_in_wort'], isTrue);
      expect(data['owner_name'], 'Bruno');
    });
  });
}
