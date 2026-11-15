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

  test('41 cultures (25 Fermentis, 16 Mangrove Jack\'s), aucun rejet', () {
    expect(lecture.entrees, hasLength(41));
    final parProducteur = <String, int>{};
    for (final e in lecture.entrees) {
      parProducteur[e.producteur!] = (parProducteur[e.producteur!] ?? 0) + 1;
    }
    expect(parProducteur, {'Fermentis': 25, "Mangrove Jack's": 16});
    expect(lecture.rejets, isEmpty);
    expect(lecture.listesIgnorees, isEmpty);
    expect(lecture.entrees.map((e) => e.source).toSet(), {Source.fabricants});
    expect(lecture.entrees.map((e) => e.nature).toSet(), {
      NatureReferentiel.culture,
    });
    expect(lecture.entrees.map((e) => e.sourceId).toSet(), hasLength(41));
  });

  test('chaque fiche porte la date du relevé de son producteur', () {
    for (final e in lecture.entrees) {
      expect(e.releveFabricant, switch (e.producteur) {
        'Fermentis' => '2026-11-14',
        _ => '2026-11-15',
      }, reason: e.nom);
    }
  });

  test(
    'Mangrove Jack\'s : floculation sur chaque fiche, M76 sans atténuation',
    () {
      final mj = lecture.entrees.where(
        (e) => e.producteur == "Mangrove Jack's",
      );
      expect(mj.every((e) => e.valeurs.containsKey('flocculation')), isTrue);
      expect(
        mj
            .where((e) => !e.valeurs.containsKey('attenuation'))
            .map((e) => e.nom),
        ['M76 Bavarian Lager'],
      );
    },
  );

  test('atténuations de 98 à 102 % de Fermentis écartées, et elles seules', () {
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
