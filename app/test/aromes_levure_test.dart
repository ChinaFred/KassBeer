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

  group('AromesLevure.fromFirestore : bornes de l\'écrivain', () {
    test('texte de 400 caractères lu, de 401 illisible', () {
      final t400 = 'a' * 400;
      for (final cle in ['profile', 'cool', 'warm']) {
        final textes = <String, Object?>{
          'profile': {'text': kTexteProfil},
          cle: {'text': t400},
        };
        expect(decrits(cultureAromaDoc(texts: textes)), isNotNull);
        textes[cle] = {'text': '$t400.'};
        expect(
          () => AromesLevure.fromFirestore(cultureAromaDoc(texts: textes)),
          illisible('texts.$cle.text'),
        );
      }
    });

    test('texte compté en points de code, comme l\'écrivain', () {
      // 399 « a » et un emoji : 400 points de code, 401 unités UTF-16.
      final t = '${'a' * 399}\u{1F37A}';
      final textes = <String, Object?>{
        'profile': {'text': t},
      };
      expect(decrits(cultureAromaDoc(texts: textes)), isNotNull);
    });

    test('8 descripteurs lus, 9 illisible', () {
      List<Map<String, String>> descripteurs(int n) => [
        for (var i = 0; i < n; i++) {'key': 'k$i', 'label': 'd$i'},
      ];
      expect(
        decrits(
          cultureAromaDoc(extra: {'descriptors': descripteurs(8)}),
        ).descripteurs,
        hasLength(8),
      );
      expect(
        () => AromesLevure.fromFirestore(
          cultureAromaDoc(extra: {'descriptors': descripteurs(9)}),
        ),
        illisible('descriptors'),
      );
    });

    test('nom de style de 120 caractères lu, de 121 illisible', () {
      Map<String, dynamic> doc(String name) => cultureAromaDoc(
        extra: {
          'styles': [
            {'code': 'bjcp2021-21a', 'name': name},
          ],
        },
      );
      expect(decrits(doc('n' * 120)).styles.single.name, hasLength(120));
      expect(
        () => AromesLevure.fromFirestore(doc('n' * 121)),
        illisible('styles[0].name'),
      );
    });

    test('codes de style : forme d\'idStyle seule', () {
      for (final code in ['bjcp2021-21a', 'bjcp2021-27-historical-beer']) {
        final doc = cultureAromaDoc(
          extra: {
            'styles': [
              {'code': code, 'name': 'Style'},
            ],
          },
        );
        expect(decrits(doc).styles.single.code, code);
      }
      for (final code in [
        '..',
        'a/b',
        'bjcp2021-21A',
        'bjcp2021-',
        'bjcp2021-21a/../x',
        'bjcp2015-21a',
      ]) {
        final doc = cultureAromaDoc(
          extra: {
            'styles': [
              {'code': 'bjcp2021-21a', 'name': 'Style'},
              {'code': code, 'name': 'Style'},
            ],
          },
        );
        expect(
          () => AromesLevure.fromFirestore(doc),
          illisible('styles[1].code'),
          reason: code,
        );
      }
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

    test('code de style refusé : rapport sans la valeur', () async {
      for (final code in ['..', 'a/b']) {
        errors.reports.clear();
        await firestore
            .doc('beer_culture_aromas/$id')
            .set(
              cultureAromaDoc(
                extra: {
                  'styles': [
                    {'code': code, 'name': 'Style'},
                  ],
                },
              ),
            );
        final lu = await repository.lireAromesLevure(id);
        expect(lu, isA<DocumentIllisibleTrouve<AromesLevure>>());
        final report = errors.reports.single;
        final rapporte = '${report.error} ${report.context}';
        expect(rapporte, contains('styles[0].code'));
        expect(rapporte, isNot(contains('..')), reason: code);
        expect(rapporte, isNot(contains('a/b')), reason: code);
      }
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
      expect(rapporte, isNot(contains('..')));
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
