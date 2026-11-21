import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/library/data/library_repository.dart';
import 'package:kass_beer/features/library/domain/aromes_houblon.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

AromesDecrits decrits(Map<String, dynamic> doc) =>
    AromesHoublon.fromFirestore(doc) as AromesDecrits;

Matcher illisible(String field) =>
    throwsA(isA<DocumentIllisible>().having((e) => e.field, 'field', field));

void main() {
  group('AromesHoublon.fromFirestore', () {
    test('décrit : descripteurs dans l\'ordre, usages', () {
      final a = decrits(hopAromaDoc());
      expect(a.confiance, ConfianceArome.haute);
      expect(a.descripteurs.map((d) => d.label), ['Pamplemousse', 'Floral']);
      expect(a.usages, {
        UsageArome.dryHop: kTexteCru,
        UsageArome.bittering: kTexteAmertume,
      });
    });

    test('confiance faible', () {
      final a = decrits(hopAromaDoc(extra: {'confidence': 'low'}));
      expect(a.confiance, ConfianceArome.faible);
    });

    test('clé d\'usage inconnue ignorée, sans lecture de sa valeur', () {
      final a = decrits(
        hopAromaDoc(
          uses: {
            'whirlpool': {'text': kTexteWhirlpool},
            'hop_stand': 'valeur d\'une version future',
          },
        ),
      );
      expect(a.usages, {UsageArome.whirlpool: kTexteWhirlpool});
    });

    test('aucune clé d\'usage connue : décrit, sans usage', () {
      final a = decrits(
        hopAromaDoc(
          uses: {
            'hop_stand': {'text': kTexteCru},
          },
        ),
      );
      expect(a.usages, isEmpty);
    });

    test('unknown', () {
      final a = AromesHoublon.fromFirestore(hopAromaUnknownDoc());
      expect(a, isA<AromesInconnus>());
    });

    test('reviewed et reviewed_at ignorés, quelle que soit leur valeur', () {
      for (final extra in [
        {'reviewed': false, 'reviewed_at': null},
        {'reviewed': null, 'reviewed_at': '14/11/2026'},
        {'reviewed': 'oui', 'reviewed_at': 20261114},
      ]) {
        expect(decrits(hopAromaDoc(extra: extra)).usages, hasLength(2));
      }
    });

    test('illisible : chaque champ attendu', () {
      expect(
        () => AromesHoublon.fromFirestore(hopAromaDoc(extra: {'status': 'x'})),
        illisible('status'),
      );
      expect(
        () => AromesHoublon.fromFirestore(
          hopAromaDoc(extra: {'confidence': null}),
        ),
        illisible('confidence'),
      );
      expect(
        () => AromesHoublon.fromFirestore(hopAromaDoc(extra: {'uses': null})),
        illisible('uses'),
      );
      expect(
        () => AromesHoublon.fromFirestore(
          hopAromaDoc(
            uses: {
              'dry_hop': {'text': 12},
            },
          ),
        ),
        illisible('uses.dry_hop.text'),
      );
      expect(
        () => AromesHoublon.fromFirestore(
          hopAromaDoc(
            extra: {
              'descriptors': [
                {'key': 'floral'},
              ],
            },
          ),
        ),
        illisible('descriptors[0].label'),
      );
    });
  });

  group('lireAromesHoublon', () {
    late FakeFirebaseFirestore firestore;
    late RecordingErrorReportService errors;
    late FirestoreLibraryRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      errors = RecordingErrorReportService();
      repository = FirestoreLibraryRepository(
        errorReportService: errors,
        firestore: firestore,
      );
    });

    test('lu par get() dans beer_hop_aromas/{id}', () async {
      await firestore.doc('beer_hop_aromas/hop-cascade').set(hopAromaDoc());
      final lu = await repository.lireAromesHoublon('hop-cascade');
      expect(lu, isA<DocumentTrouve<AromesHoublon>>());
      expect(errors.reports, isEmpty);
    });

    test('absent : aucun rapport', () async {
      expect(
        await repository.lireAromesHoublon('hop-cascade'),
        isA<DocumentAbsent<AromesHoublon>>(),
      );
      expect(errors.reports, isEmpty);
    });

    test('illisible : rapporté avec l\'identifiant, sans texte', () async {
      await firestore
          .doc('beer_hop_aromas/hop-cascade')
          .set(hopAromaDoc(extra: {'confidence': 'certaine'}));
      final lu = await repository.lireAromesHoublon('hop-cascade');
      expect(lu, isA<DocumentIllisibleTrouve<AromesHoublon>>());
      final report = errors.reports.single;
      expect(report.feature, 'library.hop_aroma');
      expect(report.context, 'beer_hop_aromas/hop-cascade illisible');
      final rapporte = '${report.error} ${report.context}';
      for (final texte in [kTexteCru, kTexteAmertume, 'Pamplemousse']) {
        expect(rapporte, isNot(contains(texte)));
      }
      expect(rapporte, isNot(contains('certaine')));
    });
  });
}
