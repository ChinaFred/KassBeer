import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/library/data/library_repository.dart';
import 'package:kass_beer/features/library/domain/description_divers.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

DiversDecrit decrit(Map<String, dynamic> doc) =>
    DescriptionDivers.fromFirestore(doc) as DiversDecrit;

Matcher illisible(String field) =>
    throwsA(isA<DocumentIllisible>().having((e) => e.field, 'field', field));

void main() {
  group('DescriptionDivers.fromFirestore', () {
    test('décrit : résumé, rôles dans l\'ordre, moments, relu', () {
      final d = decrit(miscDescriptionDoc());
      expect(d.resume, kTexteResume);
      expect(d.roles.map((r) => r.label), ['Clarifier', 'Autre usage']);
      expect(d.moments, {
        OtherUse.boil: kTexteEbullition,
        OtherUse.fermentation: kTexteFermentation,
      });
      expect(d.gout, isNull);
      expect(d.confianceFaible, isFalse);
      expect(d.relu, isTrue);
      expect(d.reluLe, DateTime(2026, 11, 21));
    });

    test('clés des moments : celles de l\'éditeur, dans son ordre', () {
      expect(kClesMoments.keys, OtherUse.values);
      expect(kClesMoments.values, [
        'mash',
        'boil',
        'after_boil',
        'fermentation',
        'bottling',
      ]);
    });

    test('goût et confiance faible', () {
      final d = decrit(
        miscDescriptionDoc(
          extra: {
            'changes_taste': true,
            'taste': {'text': kTexteGout},
            'confidence': 'low',
          },
        ),
      );
      expect(d.gout, kTexteGout);
      expect(d.confianceFaible, isTrue);
    });

    test('clé de moment inconnue ignorée, sans lecture de sa valeur', () {
      final d = decrit(
        miscDescriptionDoc(
          moments: {
            'mash': {'text': kTexteEbullition},
            'whirlpool': 'valeur d\'une version future',
          },
        ),
      );
      expect(d.moments, {OtherUse.mash: kTexteEbullition});
    });

    test('aucune clé de moment connue : décrit, sans moment', () {
      final d = decrit(
        miscDescriptionDoc(
          moments: {
            'whirlpool': {'text': kTexteEbullition},
          },
        ),
      );
      expect(d.moments, isEmpty);
    });

    test('unknown, non relu', () {
      final d = DescriptionDivers.fromFirestore(miscDescriptionUnknownDoc());
      expect(d, isA<DiversInconnu>());
      expect(d.relu, isFalse);
      expect(d.reluLe, isNull);
    });

    test('illisible : chaque champ attendu', () {
      Object? lire(Map<String, Object?> extra) =>
          DescriptionDivers.fromFirestore(miscDescriptionDoc(extra: extra));
      expect(() => lire({'status': 'x'}), illisible('status'));
      expect(() => lire({'confidence': 'certaine'}), illisible('confidence'));
      expect(() => lire({'confidence': null}), illisible('confidence'));
      expect(() => lire({'reviewed': null}), illisible('reviewed'));
      expect(
        () => lire({'reviewed_at': '2026-02-30'}),
        illisible('reviewed_at'),
      );
      expect(() => lire({'summary': null}), illisible('summary'));
      expect(() => lire({'summary': 12}), illisible('summary'));
      expect(() => lire({'roles': null}), illisible('roles'));
      expect(
        () => lire({
          'roles': [
            {'key': 'clarify'},
          ],
        }),
        illisible('roles[0].label'),
      );
      expect(() => lire({'moments': null}), illisible('moments'));
      expect(
        () => DescriptionDivers.fromFirestore(
          miscDescriptionDoc(
            moments: {
              'boil': {'text': 12},
            },
          ),
        ),
        illisible('moments.boil.text'),
      );
      expect(() => lire({'changes_taste': null}), illisible('changes_taste'));
      expect(() => lire({'changes_taste': 'oui'}), illisible('changes_taste'));
      // `taste` sans `changes_taste`, et `changes_taste` sans `taste`.
      expect(
        () => lire({
          'taste': {'text': kTexteGout},
        }),
        illisible('taste'),
      );
      expect(() => lire({'changes_taste': true}), illisible('taste'));
      expect(
        () => lire({
          'changes_taste': true,
          'taste': {'texte': kTexteGout},
        }),
        illisible('taste.text'),
      );
    });
  });

  group('lireDescriptionDivers', () {
    late FakeFirebaseFirestore firestore;
    late RecordingErrorReportService errors;
    late FirestoreLibraryRepository repository;
    const id = 'misc-mousse-irlandaise';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      errors = RecordingErrorReportService();
      repository = FirestoreLibraryRepository(
        errorReportService: errors,
        firestore: firestore,
      );
    });

    test('lu par get() dans beer_misc_descriptions/{id}', () async {
      await firestore
          .doc('beer_misc_descriptions/$id')
          .set(miscDescriptionDoc());
      final lu = await repository.lireDescriptionDivers(id);
      expect(lu, isA<DocumentTrouve<DescriptionDivers>>());
      expect(errors.reports, isEmpty);
    });

    test('absent : aucun rapport', () async {
      expect(
        await repository.lireDescriptionDivers(id),
        isA<DocumentAbsent<DescriptionDivers>>(),
      );
      expect(errors.reports, isEmpty);
    });

    test('illisible : rapporté avec l\'identifiant, sans texte', () async {
      await firestore
          .doc('beer_misc_descriptions/$id')
          .set(
            miscDescriptionDoc(
              extra: {
                'taste': {'text': kTexteGout},
              },
            ),
          );
      final lu = await repository.lireDescriptionDivers(id);
      expect(lu, isA<DocumentIllisibleTrouve<DescriptionDivers>>());
      final report = errors.reports.single;
      expect(report.feature, 'library.misc_description');
      expect(report.context, 'beer_misc_descriptions/$id illisible');
      final rapporte = '${report.error} ${report.context}';
      for (final texte in [
        kTexteGout,
        kTexteResume,
        kTexteEbullition,
        'Clarifier',
        'Mousse irlandaise',
      ]) {
        expect(rapporte, isNot(contains(texte)));
      }
    });
  });
}
