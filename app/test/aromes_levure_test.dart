import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/library/data/library_repository.dart';
import 'package:kass_beer/features/library/domain/aromes_houblon.dart';
import 'package:kass_beer/features/library/domain/aromes_levure.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

AromesLevureDecrits decrits(Map<String, dynamic> doc) =>
    AromesLevure.fromFirestore(doc) as AromesLevureDecrits;

Matcher illisible(String field) =>
    throwsA(isA<DocumentIllisible>().having((e) => e.field, 'field', field));

void main() {
  group('AromesLevure.fromFirestore', () {
    test('décrit : descripteurs, textes et styles dans l\'ordre', () {
      final a = decrits(cultureAromaDoc());
      expect(a.confiance, ConfianceArome.haute);
      expect(a.descripteurs.map((d) => d.label), ['poire', 'sec']);
      expect(a.profil, kTexteProfil);
      expect(a.basDePlage, kTexteBas);
      expect(a.hautDePlage, kTexteHaut);
      expect(a.styles.map((s) => (s.code, s.name)), [
        ('bjcp2021-21a', 'American IPA'),
        ('bjcp2021-18b', 'American Pale Ale'),
      ]);
    });

    test('cool et warm absents, clé de texts inconnue ignorée', () {
      final a = decrits(
        cultureAromaDoc(
          texts: {
            'profile': {'text': kTexteProfil},
            'lager': 'valeur d\'une version future',
          },
        ),
      );
      expect(a.basDePlage, isNull);
      expect(a.hautDePlage, isNull);
    });

    test('aucun style', () {
      final a = decrits(cultureAromaDoc(extra: {'styles': null}));
      expect(a.styles, isEmpty);
    });

    test('unknown', () {
      expect(
        AromesLevure.fromFirestore(cultureAromaUnknownDoc()),
        isA<AromesLevureInconnus>(),
      );
    });

    test('reviewed et reviewed_at ignorés, quelle que soit leur valeur', () {
      for (final extra in [
        {'reviewed': false, 'reviewed_at': null},
        {'reviewed': 'oui', 'reviewed_at': 20261121},
      ]) {
        expect(decrits(cultureAromaDoc(extra: extra)).profil, kTexteProfil);
      }
    });

    test('illisible : chaque champ attendu', () {
      expect(
        () =>
            AromesLevure.fromFirestore(cultureAromaDoc(extra: {'status': 'x'})),
        illisible('status'),
      );
      expect(
        () => AromesLevure.fromFirestore(
          cultureAromaDoc(extra: {'confidence': 'certaine'}),
        ),
        illisible('confidence'),
      );
      expect(
        () =>
            AromesLevure.fromFirestore(cultureAromaDoc(extra: {'texts': null})),
        illisible('texts'),
      );
      expect(
        () => AromesLevure.fromFirestore(
          cultureAromaDoc(
            texts: {
              'cool': {'text': kTexteBas},
            },
          ),
        ),
        illisible('texts.profile'),
      );
      expect(
        () => AromesLevure.fromFirestore(
          cultureAromaDoc(
            texts: {
              'profile': {'text': kTexteProfil},
              'warm': {'text': 12},
            },
          ),
        ),
        illisible('texts.warm.text'),
      );
      expect(
        () => AromesLevure.fromFirestore(
          cultureAromaDoc(
            extra: {
              'styles': [
                {'code': 'bjcp2021-21a'},
              ],
            },
          ),
        ),
        illisible('styles[0].name'),
      );
      expect(
        () => AromesLevure.fromFirestore(
          cultureAromaDoc(
            extra: {
              'styles': [
                for (var i = 0; i < 7; i++)
                  {'code': 'bjcp2021-$i', 'name': 'Style $i'},
              ],
            },
          ),
        ),
        illisible('styles'),
      );
      expect(
        () => AromesLevure.fromFirestore(
          cultureAromaDoc(
            extra: {
              'descriptors': [
                {'key': 'pear'},
              ],
            },
          ),
        ),
        illisible('descriptors[0].label'),
      );
    });
  });

  group('lireAromesLevure', () {
    late FakeFirebaseFirestore firestore;
    late RecordingErrorReportService errors;
    late FirestoreLibraryRepository repository;
    const id = 'culture-levure-fictive';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      errors = RecordingErrorReportService();
      repository = FirestoreLibraryRepository(
        errorReportService: errors,
        firestore: firestore,
      );
    });

    test('lu par get() dans beer_culture_aromas/{id}', () async {
      await firestore.doc('beer_culture_aromas/$id').set(cultureAromaDoc());
      final lu = await repository.lireAromesLevure(id);
      expect(lu, isA<DocumentTrouve<AromesLevure>>());
      expect(errors.reports, isEmpty);
    });

    test('absent : aucun rapport', () async {
      expect(
        await repository.lireAromesLevure(id),
        isA<DocumentAbsent<AromesLevure>>(),
      );
      expect(errors.reports, isEmpty);
    });

    test('illisible : rapporté avec l\'identifiant, sans texte', () async {
      await firestore
          .doc('beer_culture_aromas/$id')
          .set(cultureAromaDoc(extra: {'confidence': 'certaine'}));
      final lu = await repository.lireAromesLevure(id);
      expect(lu, isA<DocumentIllisibleTrouve<AromesLevure>>());
      final report = errors.reports.single;
      expect(report.feature, 'library.culture_aroma');
      expect(report.context, 'beer_culture_aromas/$id illisible');
      final rapporte = '${report.error} ${report.context}';
      for (final texte in [
        kTexteProfil,
        kTexteBas,
        kTexteHaut,
        'poire',
        'American IPA',
        'certaine',
      ]) {
        expect(rapporte, isNot(contains(texte)));
      }
    });
  });
}
