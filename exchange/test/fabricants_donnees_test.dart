import 'dart:io';

import 'package:exchange/ingestion.dart';
import 'package:test/test.dart';

/// Fichier versionné des fiches des fabricants (ADR-005, amendement du
/// 2026-11-15), lu par défaut par `bin/preparer_referentiels.dart`.
void main() {
  late LectureReferentiels lecture;
  setUpAll(() {
    lecture = LectureReferentiels()
      ..lireFabricants(
        File(
          'donnees/fabricants/${Source.fabricants.fichier}',
        ).readAsStringSync(),
      );
  });

  test('25 cultures Fermentis, aucun rejet', () {
    expect(lecture.entrees, hasLength(25));
    expect(lecture.rejets, isEmpty);
    expect(lecture.listesIgnorees, isEmpty);
    expect(lecture.entrees.map((e) => e.source).toSet(), {Source.fabricants});
    expect(lecture.entrees.map((e) => e.nature).toSet(), {
      NatureReferentiel.culture,
    });
    expect(lecture.entrees.map((e) => e.sourceId).toSet(), hasLength(25));
  });

  test('atténuations de 98 à 102 % écartées, et elles seules', () {
    final ecartees = lecture.journal.ecartees;
    expect(ecartees.every((e) => e.source == 'fabricants'), isTrue);
    expect(
      ecartees.every((e) => e.champ.startsWith('attenuation_range')),
      isTrue,
    );
    expect(ecartees.map((e) => e.nom).toSet(), {
      'SafBrew HA-18',
      'SafBrew DA-16',
      'SafBrew DW-17',
      'SafBrew LD-20',
    });
  });
}
