import 'package:brewing/brewing.dart' show alcoholByVolume;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/features/brew_day/domain/plan_du_jour.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/mesures_retenues.dart';
import 'package:kass_beer/features/brews/domain/releves.dart';

import 'support/brew_fixtures.dart';

void main() {
  final jour = DateTime(2026, 11, 8, 15, 20);

  group('relevés (FE5, FE6)', () {
    test('couple densité et température de même heure : une ligne', () {
      final at = DateTime(2026, 11, 15, 18, 30);
      final releves = relevesDe([
        releve('t', MeasureType.temperature, 18.5, at),
        releve('g', MeasureType.gravity, 1.02, at),
      ]);
      expect(releves.length, 1);
      expect(releves.single.gravityValue, 1.02);
      expect(releves.single.temperatureValue, 18.5);
    });

    test('deux densités à la même heure : deux lignes', () {
      final at = DateTime(2026, 11, 15, 18, 30);
      final releves = relevesDe([
        releve('g1', MeasureType.gravity, 1.02, at),
        releve('g2', MeasureType.gravity, 1.021, at),
      ]);
      expect(releves.length, 2);
    });

    test(
      'du plus récent au plus ancien ; note seule ; mesures du jour exclues',
      () {
        final releves = relevesDe([
          mesure('jour', null, MeasureType.gravity, 1.05, jour),
          releve('ancien', MeasureType.gravity, 1.04, DateTime(2026, 11, 10)),
          noteDeReleve('note', 'Bonne odeur', DateTime(2026, 11, 12)),
          releve('recent', MeasureType.gravity, 1.02, DateTime(2026, 11, 15)),
        ]);
        expect(releves.map((r) => r.cle), ['recent', 'note', 'ancien']);
        expect(releves[1].note, 'Bonne odeur');
        expect(releves[1].aDesValeurs, isFalse);
      },
    );
  });

  group('FE11 : relevé hors de la chronologie', () {
    test('un relevé ne figure pas dans les mesures du jour', () {
      final plan = PlanDuJour.calculer(
        brew: unBrassin(status: BrewStatus.fermenting, brewedAt: jour),
        events: [
          mesure('jour', null, MeasureType.gravity, 1.05, jour),
          releve('r', MeasureType.gravity, 1.02, DateTime(2026, 11, 15)),
        ],
        now: DateTime(2026, 11, 16),
      );
      expect(plan.mesuresSansEtape.map((e) => e.id), ['jour']);
    });
  });

  group('mesures retenues (VR1, VR2, RR2)', () {
    final og1 = mesure('og1', 'k-palier', MeasureType.gravity, 1.05, jour);
    final og2 = mesure(
      'og2',
      'k-palier',
      MeasureType.gravity,
      1.0579,
      jour.add(const Duration(hours: 1)),
    );
    final v1 = mesure('v1', null, MeasureType.volume, 20, jour);
    final r1 = releve(
      'r1',
      MeasureType.gravity,
      1.02,
      DateTime(2026, 11, 12, 18),
    );
    final r2 = releve(
      'r2',
      MeasureType.gravity,
      1.012,
      DateTime(2026, 11, 20, 18),
    );

    test('automatique : dernière densité du jour, dernière densité de '
        'fermentation, dernier volume', () {
      final retenues = MesuresRetenues.de(
        unBrassin(status: BrewStatus.fermenting, brewedAt: jour),
        [og1, og2, v1, r1, r2],
      );
      expect(retenues.densiteInitiale?.event.id, 'og2');
      expect(retenues.densiteInitiale?.choisie, isFalse);
      expect(retenues.densiteFinale?.event.id, 'r2');
      expect(retenues.volumeFermenteur?.event.id, 'v1');
    });

    test('choisie : l\'identifiant prime sur la règle automatique', () {
      final retenues = MesuresRetenues.de(
        unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: jour,
          ogEventId: 'og1',
          fgEventId: 'r1',
        ),
        [og1, og2, r1, r2],
      );
      expect(retenues.densiteInitiale?.event.id, 'og1');
      expect(retenues.densiteInitiale?.choisie, isTrue);
      expect(retenues.densiteFinale?.event.id, 'r1');
      expect(retenues.densiteFinale?.choisie, isTrue);
    });

    test('VR6 : mesure choisie supprimée : retour à la dernière mesure', () {
      final retenues = MesuresRetenues.de(
        unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: jour,
          fgEventId: 'absent',
        ),
        [og1, r1],
      );
      expect(retenues.densiteFinale?.event.id, 'r1');
      expect(retenues.densiteFinale?.choisie, isFalse);
    });

    test(
      'VR2 : hors fermentation, un relevé postérieur à bottled_at ne compte pas',
      () {
        final retenues = MesuresRetenues.de(
          unBrassin(
            status: BrewStatus.conditioning,
            brewedAt: jour,
            bottledAt: DateTime(2026, 11, 15, 10),
          ),
          [og1, r1, r2],
        );
        expect(retenues.densiteFinale?.event.id, 'r1');
      },
    );

    test(
      'densité finale saisie à l\'embouteillage : même heure que bottled_at, comptée',
      () {
        final bottled = DateTime(2026, 11, 20, 18);
        final retenues = MesuresRetenues.de(
          unBrassin(
            status: BrewStatus.conditioning,
            brewedAt: jour,
            bottledAt: bottled,
          ),
          [og1, releve('fg', MeasureType.gravity, 1.011, bottled)],
        );
        expect(retenues.densiteFinale?.event.id, 'fg');
      },
    );

    test('la densité retenue comme initiale n\'est pas la densité finale', () {
      final retenues = MesuresRetenues.de(
        unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: jour,
          ogEventId: 'r1',
        ),
        [r1],
      );
      expect(retenues.densiteInitiale?.event.id, 'r1');
      expect(retenues.densiteFinale, isNull);
    });

    test('VR5 : la valeur n\'est jamais lue d\'une valeur stockée', () {
      final corrigee = releve(
        'og1',
        MeasureType.gravity,
        1.06,
        DateTime(2026, 11, 8, 15),
      );
      final retenues = MesuresRetenues.de(
        unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: jour,
          ogEventId: 'og1',
        ),
        [corrigee, r2],
      );
      expect(retenues.densiteInitiale?.value, 1.06);
      expect(
        alcoholByVolume(originalGravity: 1.06, finalGravity: 1.012),
        closeTo(6.3, 1e-9),
      );
    });

    test('candidats à « Changer », la plus récente en tête', () {
      final tous = [og1, og2, r1, r2, v1];
      expect(
        candidatsRetenus(
          MesureRetenueChamp.densiteInitiale,
          tous,
        ).map((e) => e.id),
        ['r2', 'r1', 'og2', 'og1'],
      );
      expect(
        candidatsRetenus(
          MesureRetenueChamp.densiteFinale,
          tous,
        ).map((e) => e.id),
        ['r2', 'r1'],
      );
      expect(
        candidatsRetenus(
          MesureRetenueChamp.volumeFermenteur,
          tous,
        ).map((e) => e.id),
        ['v1'],
      );
    });
  });

  group('modèle', () {
    Map<String, dynamic> base() => {
      'owner_uid': 'u',
      'name': 'Blonde',
      'status': 'fermenting',
      'recipe_snapshot': recetteMinimale('Blonde'),
      'equipment_snapshot': {'name': 'Cuve', 'kind': 'all_in_one'},
    };

    test('champs d\'après brassage lus du document', () {
      final brew = Brew.fromFirestore('b', {
        ...base(),
        'bottled_at': Timestamp.fromDate(DateTime(2026, 12, 3)),
        'bottles_count': 60,
        'packaged_volume_l': 19.5,
        'priming_sugar_g': 120,
        'priming_sugar_name': 'Saccharose',
        'og_event_id': 'e1',
        'fg_event_id': 'e2',
        'fermenter_volume_event_id': 'e3',
        'sugars_in_wort': false,
      });
      expect(brew.bottledAt, DateTime(2026, 12, 3));
      expect(brew.bottlesCount, 60);
      expect(brew.packagedVolumeL, 19.5);
      expect(brew.primingSugarG, 120);
      expect(brew.primingSugarName, 'Saccharose');
      expect(brew.ogEventId, 'e1');
      expect(brew.fgEventId, 'e2');
      expect(brew.fermenterVolumeEventId, 'e3');
      expect(brew.sugarsInWort, isFalse);
    });

    test('aucune migration : champs absents, nuls', () {
      final brew = Brew.fromFirestore('b', base());
      expect(brew.bottledAt, isNull);
      expect(brew.sugarsInWort, isNull);
    });

    test('sugars_in_wort non booléen : illisible', () {
      expect(
        () => Brew.fromFirestore('b', {...base(), 'sugars_in_wort': 'oui'}),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('ST5 : reprise déduite de bottled_at', () {
      expect(
        unBrassin(status: BrewStatus.abandoned).statutDeReprise,
        BrewStatus.fermenting,
      );
      expect(
        unBrassin(
          status: BrewStatus.abandoned,
          bottledAt: DateTime(2026, 12, 3),
        ).statutDeReprise,
        BrewStatus.conditioning,
      );
    });

    test('ST10 : ordre de la liste', () {
      final list = [
        unBrassin(id: 'done', status: BrewStatus.done, brewedAt: jour),
        unBrassin(id: 'plan', status: BrewStatus.planned),
        unBrassin(id: 'ferm', status: BrewStatus.fermenting, brewedAt: jour),
        unBrassin(id: 'cond', status: BrewStatus.conditioning, brewedAt: jour),
        unBrassin(id: 'cours', status: BrewStatus.brewing, brewedAt: jour),
      ]..sort(compareBrews);
      expect(list.map((b) => b.id).first, 'cours');
      expect(list.map((b) => b.id).last, 'done');
      expect(list[1].id, anyOf('ferm', 'cond'));
      expect(list[2].id, anyOf('ferm', 'cond'));
      expect(list[3].id, 'plan');
    });

    test('phase lue et réécrite ; phase inconnue illisible', () {
      final event = BrewEvent.fromFirestore('e', {
        'owner_uid': 'u',
        'kind': 'measurement',
        'measure_type': 'gravity',
        'value': 1.02,
        'measured_at': Timestamp.fromDate(jour),
        'phase': 'fermentation',
      });
      expect(event.isFermentation, isTrue);
      expect(event.toFirestore()['phase'], 'fermentation');
      expect(
        () => BrewEvent.fromFirestore('e', {
          'owner_uid': 'u',
          'kind': 'measurement',
          'measure_type': 'gravity',
          'value': 1.02,
          'measured_at': Timestamp.fromDate(jour),
          'phase': 'garde',
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('mesure du jour : aucun champ phase écrit', () {
      final data = mesure(
        'e',
        null,
        MeasureType.gravity,
        1.05,
        jour,
      ).toFirestore();
      expect(data.containsKey('phase'), isFalse);
    });
  });

  group('formats (constat 7)', () {
    test('formatJourHeure et écart à vrai signe moins', () {
      expect(
        formatJourHeure(DateTime(2026, 11, 15, 18, 30)),
        'dim. 15 nov. 18:30',
      );
      expect(formatEcart(-3), '−3,0${nbsp}pts');
      expect(formatEcart(2), '+2,0${nbsp}pts');
      expect(formatEcart(0.01), '0,0${nbsp}pts');
      expect(formatEcart(1.5, unite: 'L'), '+1,5${nbsp}L');
    });

    test('erreurNombre : entier et minimum (constat 6)', () {
      expect(
        erreurNombre('1,5', entier: true, min: 1, max: 9999),
        ErreursNombre.entier,
      );
      expect(
        erreurNombre('0', entier: true, min: 1, max: 9999),
        'Entre 1 et 9${nbsp}999.',
      );
      expect(erreurNombre('60', entier: true, min: 1, max: 9999), isNull);
    });
  });
}
