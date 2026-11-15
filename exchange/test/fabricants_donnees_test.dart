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

  test('200 cultures (25 Fermentis, 16 Mangrove Jack\'s, 55 Imperial, '
      '104 Omega), aucun rejet', () {
    expect(lecture.entrees, hasLength(200));
    final parProducteur = <String, int>{};
    for (final e in lecture.entrees) {
      parProducteur[e.producteur!] = (parProducteur[e.producteur!] ?? 0) + 1;
    }
    expect(parProducteur, {
      'Fermentis': 25,
      "Mangrove Jack's": 16,
      'Imperial Yeast': 55,
      'Omega Yeast': 104,
    });
    expect(lecture.rejets, isEmpty);
    expect(lecture.listesIgnorees, isEmpty);
    expect(lecture.entrees.map((e) => e.source).toSet(), {Source.fabricants});
    expect(lecture.entrees.map((e) => e.nature).toSet(), {
      NatureReferentiel.culture,
    });
    expect(lecture.entrees.map((e) => e.sourceId).toSet(), hasLength(200));
  });

  test('chaque fiche porte la date du relevé de son producteur', () {
    for (final e in lecture.entrees) {
      expect(e.releveFabricant, switch (e.producteur) {
        'Fermentis' => '2026-11-14',
        _ => '2026-11-15',
      }, reason: e.nom);
    }
  });

  test('Omega : variantes « Plus », noms normalisés distincts', () {
    final noms = [
      for (final e in lecture.entrees)
        if (e.producteur == 'Omega Yeast') e.nom,
    ];
    expect(noms.where((n) => n.contains('+')), isEmpty);
    expect(noms, contains('Kolsch II Plus'));
    final cles = noms.map(cleNormalisee).toList();
    expect(cles.toSet(), hasLength(cles.length));
  });

  test('Omega : types tirés de la fiche, champs absents attendus', () {
    final om = {
      for (final e in lecture.entrees.where(
        (e) => e.producteur == 'Omega Yeast',
      ))
        e.sourceId: e,
    };
    expect(om['omega-yeast-oyl-061']!.valeurs['type'], 'kveik');
    expect(om['omega-yeast-oyl-605']!.valeurs['type'], 'lacto');
    expect(om['omega-yeast-oyl-606']!.valeurs['type'], 'pedio');
    expect(om['omega-yeast-oyl-217']!.valeurs['type'], 'mixed-culture');
    expect(om['omega-yeast-pinnacle-crisp-sour']!.valeurs['type'], 'other');
    expect(om['omega-yeast-pinnacle-crisp-sour']!.valeurs['form'], 'dry');
    expect(
      om.values.where((e) => e.produit == null).map((e) => e.sourceId),
      hasLength(5),
    );
    expect(
      om.values
          .where((e) => !e.valeurs.containsKey('attenuation'))
          .map((e) => e.sourceId)
          .toSet(),
      {
        'omega-yeast-oyl-410',
        'omega-yeast-oyl-605',
        'omega-yeast-oyl-606',
        'omega-yeast-pinnacle-low-alcohol',
      },
    );
  });

  test(
    'Imperial : liquide, °F convertis, floculation et atténuation partout',
    () {
      final imp = lecture.entrees.where(
        (e) => e.producteur == 'Imperial Yeast',
      );
      expect(imp.every((e) => e.valeurs['form'] == 'liquid'), isTrue);
      expect(
        imp.every(
          (e) =>
              e.valeurs.containsKey('flocculation') &&
              e.valeurs.containsKey('attenuation') &&
              e.valeurs.containsKey('temperature_range'),
        ),
        isTrue,
      );
      final house = imp.singleWhere((e) => e.produit == 'A01');
      // 62-70 °F de la fiche.
      expect(house.valeurs['temperature_range'], {
        'minimum': {'value': 16.7, 'unit': 'C'},
        'maximum': {'value': 21.1, 'unit': 'C'},
      });
      expect(house.valeurs['flocculation'], 'high');
      expect(
        imp.singleWhere((e) => e.produit == 'A07').valeurs['flocculation'],
        'medium low',
      );
    },
  );

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
