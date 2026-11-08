import 'package:brewing/brewing.dart' show StepStatus;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/features/brew_day/domain/plan_du_jour.dart';
import 'package:kass_beer/features/brew_day/presentation/mesure_form.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';

void main() {
  group('formats du jour', () {
    test('heure, date, minuteur, durée', () {
      expect(formatHeure(DateTime(2026, 11, 8, 9, 5)), '09:05');
      expect(formatDate(DateTime(2026, 11, 14)), 'sam. 14 nov. 2026');
      expect(formatDateCourte(DateTime(2024, 2, 11)), '11 févr. 2024');
      expect(formatMinuteur(const Duration(minutes: 32, seconds: 15)), '32:15');
      expect(
        formatMinuteur(const Duration(hours: 1, minutes: 5, seconds: 12)),
        '1:05:12',
      );
      expect(
        formatMinuteur(
          const Duration(minutes: 4, seconds: 12),
          depassement: true,
        ),
        '+04:12',
      );
      expect(formatDuree(const Duration(minutes: 45)), '45${nbsp}min');
      expect(
        formatDuree(const Duration(hours: 5, minutes: 40)),
        '5${nbsp}h${nbsp}40',
      );
      expect(formatPh(5.42), '5,42');
      expect(libelleMesure(MeasureType.gravity, 1.0579), '1057,9');
      expect(libelleMesure(MeasureType.volume, 23), '23,0${nbsp}L');
    });
  });

  group('densité saisie', () {
    test('1057,9 et 1.058 acceptées, aperçu sans erreur', () {
      expect(erreurDensite('1057,9'), isNull);
      expect(erreurDensite('1.058'), isNull);
    });

    test('illisible et hors limites : deux messages, sans exception', () {
      expect(erreurDensite('abc'), contains('illisible'));
      expect(erreurDensite('1250'), contains('hors de'));
    });
  });

  group('placerHeure (R2, JB7)', () {
    test('heure passée du jour : gardée', () {
      final now = DateTime(2026, 11, 8, 12, 0);
      expect(
        placerHeure(
          base: now,
          heure: const TimeOfDay(hour: 11, minute: 30),
          now: now,
          plancher: DateTime(2026, 11, 8, 10),
        ).at,
        DateTime(2026, 11, 8, 11, 30),
      );
    });

    test('heure future sans veille possible : refusée', () {
      final now = DateTime(2026, 11, 8, 12, 0);
      final choix = placerHeure(
        base: now,
        heure: const TimeOfDay(hour: 12, minute: 30),
        now: now,
        plancher: DateTime(2026, 11, 8, 10),
      );
      expect(choix.at, isNull);
      expect(choix.erreur, kHeureFutureRefusee);
    });

    test('fin écrite le lendemain à 08:00, corrigée à 18:00 : la veille', () {
      final debutEtape = DateTime(2026, 11, 7, 14);
      expect(
        placerHeure(
          base: DateTime(2026, 11, 8, 8),
          heure: const TimeOfDay(hour: 18, minute: 0),
          now: DateTime(2026, 11, 8, 9),
          apres: debutEtape,
          plancher: DateTime(2026, 11, 7, 12),
        ).at,
        DateTime(2026, 11, 7, 18),
      );
    });

    test('23:55 saisi à 00:05 : la veille', () {
      final now = DateTime(2026, 11, 8, 0, 5);
      expect(
        placerHeure(
          base: now,
          heure: const TimeOfDay(hour: 23, minute: 55),
          now: now,
          plancher: DateTime(2026, 11, 7, 20),
        ).at,
        DateTime(2026, 11, 7, 23, 55),
      );
    });

    test('fin avant le début : refusée', () {
      final now = DateTime(2026, 11, 8, 12, 0);
      final choix = placerHeure(
        base: now,
        heure: const TimeOfDay(hour: 10, minute: 0),
        now: now,
        apres: DateTime(2026, 11, 8, 11),
      );
      expect(choix.at, isNull);
      expect(choix.erreur, kFinAvantDebut);
    });

    test('fin après minuit : le lendemain du début', () {
      expect(
        placerHeure(
          base: DateTime(2026, 11, 7, 23, 30),
          heure: const TimeOfDay(hour: 0, minute: 30),
          now: DateTime(2026, 11, 8, 1),
          apres: DateTime(2026, 11, 7, 23),
        ).at,
        DateTime(2026, 11, 8, 0, 30),
      );
    });

    test('début à 23:50 corrigé à 00:05 le lendemain : au plus proche', () {
      expect(
        placerHeure(
          base: DateTime(2026, 11, 7, 23, 50),
          heure: const TimeOfDay(hour: 0, minute: 5),
          now: DateTime(2026, 11, 8, 0, 10),
          plancher: DateTime(2026, 11, 7, 23, 50),
        ).at,
        DateTime(2026, 11, 8, 0, 5),
      );
    });

    test('fin du jour D à 18:00 corrigée à 13:00 un jour plus tard', () {
      expect(
        placerHeure(
          base: DateTime(2026, 11, 7, 18),
          heure: const TimeOfDay(hour: 13, minute: 0),
          now: DateTime(2026, 11, 8, 20),
          apres: DateTime(2026, 11, 7, 12),
          plancher: DateTime(2026, 11, 7, 10),
        ).at,
        DateTime(2026, 11, 7, 13),
      );
    });

    test('début oublié, corrigé avant le premier début : même jour', () {
      expect(
        placerHeure(
          base: DateTime(2026, 11, 8, 10),
          heure: const TimeOfDay(hour: 8, minute: 0),
          now: DateTime(2026, 11, 8, 12),
          plancher: DateTime(2026, 11, 8, 10),
        ).at,
        DateTime(2026, 11, 8, 8),
      );
    });

    test('correction d\'un jour ancien : garde sa date', () {
      expect(
        placerHeure(
          base: DateTime(2026, 11, 3, 14),
          heure: const TimeOfDay(hour: 15, minute: 0),
          now: DateTime(2026, 11, 8, 9),
        ).at,
        DateTime(2026, 11, 3, 15),
      );
    });
  });

  test(
    'S1 : clé de 101 caractères ou nom trop long, chronologie illisible',
    () {
      final cle = readBrewSteps([
        {'key': 'k' * 101, 'name': 'A', 'duration_min': 5},
      ]);
      expect(cle.problem, isNotNull);
      expect(cle.steps, isEmpty);
      final nom = readBrewSteps([
        {'key': 'k', 'name': 'n' * 121, 'duration_min': 5},
      ]);
      expect(nom.problem, isNotNull);
      expect(
        erreurChronologie([
          BrewStepLine(key: 'k' * 101, name: 'A', durationMin: 1),
        ]),
        isNotNull,
      );
    },
  );

  group('chronologie', () {
    test('lecture : clé en double ou durée hors limites illisibles', () {
      expect(
        readBrewSteps([
          {'key': 'k', 'name': 'A', 'duration_min': 5},
          {'key': 'k', 'name': 'B', 'duration_min': 5},
        ]).problem,
        contains('double'),
      );
      expect(
        readBrewSteps([
          {'key': 'k', 'name': 'A', 'duration_min': -1},
        ]).problem,
        contains('durée'),
      );
      expect(readBrewSteps(null).problem, isNull);
      expect(
        readBrewSteps([
          {'key': 'k1', 'name': 'A', 'duration_min': 60, 'temp_c': 68},
        ]).steps.single.tempC,
        68,
      );
    });

    test('dureeChronologie et decalages, calculés par brewing', () {
      expect(
        dureeChronologie(const [palier, ajout, ebullition]),
        const Duration(minutes: 105),
      );
      expect(
        decalagesChronologie(const [palier, ajout, ebullition]).last,
        const Duration(minutes: 45),
      );
    });

    test('dupliquer une recette garde les clés (CH6)', () {
      const content = RecipeContent(
        name: 'Blonde',
        brewSteps: [palier, ebullition],
      );
      final copy = content.duplicate();
      expect(copy.brewSteps.map((s) => s.key), ['k-palier', 'k-ebullition']);
    });

    test('modifier la recette n\'écrit pas la chronologie', () {
      const content = RecipeContent(name: 'Blonde', brewSteps: [palier]);
      expect(
        content.toFirestore(creation: false).containsKey('brew_steps'),
        isFalse,
      );
      expect(
        content.toFirestore(creation: true).containsKey('brew_steps'),
        isTrue,
      );
    });

    test('erreurChronologie : clés uniques, bornes', () {
      expect(erreurChronologie(const [palier, ebullition]), isNull);
      expect(erreurChronologie(const [palier, palier]), contains('clé'));
      expect(
        erreurChronologie(const [
          BrewStepLine(key: 'k', name: 'x', durationMin: 601),
        ]),
        contains('600'),
      );
    });
  });

  group('conversion du brassin', () {
    test('statut inconnu : DocumentIllisible', () {
      expect(
        () => Brew.fromFirestore('b', {
          'owner_uid': 'u',
          'name': 'B',
          'status': 'autre',
          'recipe_snapshot': <String, dynamic>{'name': 'R'},
          'equipment_snapshot': <String, dynamic>{
            'name': 'E',
            'kind': 'all_in_one',
          },
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('événement : measured_at obligatoire', () {
      expect(
        () => BrewEvent.fromFirestore('e', {
          'owner_uid': 'u',
          'kind': 'step_started',
          'step_key': 'k',
        }),
        throwsA(isA<DocumentIllisible>()),
      );
      final event = BrewEvent.fromFirestore('e', {
        'owner_uid': 'u',
        'kind': 'measurement',
        'measure_type': 'ph',
        'value': 5.4,
        'measured_at': Timestamp.fromDate(DateTime(2026)),
      });
      expect(event.measureType, MeasureType.ph);
      expect(event.toStepEvent(), isNull);
    });
  });

  group('tri et reprise', () {
    Brew b(
      String id,
      BrewStatus status, {
      DateTime? plannedFor,
      DateTime? brewedAt,
      String owner = 'u',
    }) => unBrassin(
      id: id,
      status: status,
      plannedFor: plannedFor,
      brewedAt: brewedAt,
      owner: owner,
    );

    test('en cours, en fermentation, prévus croissants, puis terminés', () {
      final list = [
        b('fini', BrewStatus.done, brewedAt: DateTime(2026, 1, 1)),
        b('p2', BrewStatus.planned, plannedFor: DateTime(2026, 12, 1)),
        b('c', BrewStatus.brewing, brewedAt: DateTime(2026, 11, 8)),
        b('p1', BrewStatus.planned, plannedFor: DateTime(2026, 11, 20)),
        b('recent', BrewStatus.fermenting, brewedAt: DateTime(2026, 11, 1)),
      ]..sort(compareBrews);
      expect(list.map((e) => e.id), ['c', 'recent', 'p1', 'p2', 'fini']);
    });

    test('reprise : un seul brassin en cours de moins de 24 h', () {
      final now = DateTime(2026, 11, 8, 12);
      final recent = b(
        'a',
        BrewStatus.brewing,
        brewedAt: DateTime(2026, 11, 8, 8),
      );
      expect(brassinAReprendre([recent], 'u', now)?.id, 'a');
      expect(
        brassinAReprendre(
          [
            recent,
            b('c', BrewStatus.brewing, brewedAt: DateTime(2026, 11, 8, 9)),
          ],
          'u',
          now,
        ),
        isNull,
      );
      expect(
        brassinAReprendre(
          [b('v', BrewStatus.brewing, brewedAt: DateTime(2026, 11, 6))],
          'u',
          now,
        ),
        isNull,
      );
      expect(brassinAReprendre([recent], 'autre', now), isNull);
    });
  });

  group('PlanDuJour', () {
    final debutAt = DateTime(2026, 11, 8, 11, 45);
    final brew = unBrassin(brewedAt: debutAt);

    test('en cours, à venir, fin prévue et retard', () {
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: [debut('e1', 'k-palier', debutAt)],
        now: DateTime(2026, 11, 8, 12, 45),
      );
      expect(plan.enCours?.step.key, 'k-palier');
      expect(plan.prochaine?.step.key, 'k-ebullition');
      expect(plan.retard, const Duration(minutes: 15));
      expect(plan.finPrevue, DateTime(2026, 11, 8, 13, 45));
    });

    test('heures réelles pour une étape faite', () {
      final fini = debutAt.add(const Duration(minutes: 40));
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: [debut('e1', 'k-palier', debutAt), fin('e2', 'k-palier', fini)],
        now: DateTime(2026, 11, 8, 12),
      );
      expect(plan.lignes.first.record?.endedAt, fini);
      expect(plan.lignes.first.status, StepStatus.done);
    });

    test('deux débuts : le plus ancien, l\'autre en doublon', () {
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: [
          debut('e1', 'k-palier', debutAt),
          debut('e2', 'k-palier', debutAt.add(const Duration(minutes: 2))),
        ],
        now: DateTime(2026, 11, 8, 12),
      );
      expect(plan.lignes.first.record?.startEventId, 'e1');
      expect(plan.lignes.first.doublons.single.id, 'e2');
    });

    test('fin avant le début : incohérence, sans exception', () {
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: [
          debut('e1', 'k-palier', debutAt),
          fin('e2', 'k-palier', debutAt.subtract(const Duration(minutes: 2))),
        ],
        now: DateTime(2026, 11, 8, 12),
      );
      expect(plan.etapeIncoherente, 'Palier 68');
      expect(plan.finPrevue, isNull);
    });

    test('mesure sans étape et sur l\'étape, triées', () {
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: [
          mesure('m2', null, MeasureType.ph, 5.4, DateTime(2026, 11, 8, 12, 5)),
          mesure(
            'm1',
            'k-palier',
            MeasureType.temperature,
            67,
            DateTime(2026, 11, 8, 12),
          ),
        ],
        now: DateTime(2026, 11, 8, 12, 10),
      );
      expect(plan.lignes.first.mesures.single.id, 'm1');
      expect(plan.mesuresSansEtape.single.id, 'm2');
    });
  });
}
