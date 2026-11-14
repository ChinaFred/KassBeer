import 'package:brewing/brewing.dart' show StepStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/features/brew_day/domain/plan_du_jour.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/deroule.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';

/// Déroulé de deux journées : brassage (palier, ébullition de la recette, encadrés
/// par deux étapes du modèle) et houblonnage à cru au J+4.
Deroule deuxJournees() => const Deroule(
  templateId: 't1',
  templateName: 'Brassage et cru',
  journees: [
    JourneeDeroulee(
      key: 'j-brassage',
      name: 'Brassage',
      offsetDays: 0,
      sourceEcart: SourceEcart.modele,
      role: RoleJournee.brassage,
      cleJourneeModele: 'm-brassage',
      etapes: [
        EtapeDeroulee(
          ligne: BrewStepLine(
            key: 'k-mise-en-place',
            name: 'Mise en place',
            durationMin: 30,
          ),
          origine: OrigineEtape.modele,
          cleEtapeModele: 'm-mise-en-place',
        ),
        EtapeDeroulee(ligne: palier, origine: OrigineEtape.chronologieRecette),
        EtapeDeroulee(
          ligne: ebullition,
          origine: OrigineEtape.chronologieRecette,
        ),
      ],
    ),
    JourneeDeroulee(
      key: 'j-cru',
      name: 'Houblonnage à cru',
      offsetDays: 4,
      sourceEcart: SourceEcart.recette,
      role: RoleJournee.autre,
      cleJourneeModele: 'm-cru',
      etapes: [
        EtapeDeroulee(
          ligne: BrewStepLine(
            key: 'k-desinfection',
            name: 'Désinfection',
            durationMin: 10,
          ),
          origine: OrigineEtape.modele,
          cleEtapeModele: 'm-desinfection',
        ),
        EtapeDeroulee(
          ligne: BrewStepLine(
            key: 'k-citra',
            name: 'Ajouter Citra 50 g',
            durationMin: 0,
          ),
          origine: OrigineEtape.houblonsACru,
        ),
      ],
    ),
  ],
);

Map<String, Object?> _copie(Map<String, Object?> process) =>
    lireDeroule(process).toFirestore();

Map<String, Object?> _avecJournee(
  Map<String, Object?> process,
  int index,
  Map<String, Object?> Function(Map<String, Object?>) change,
) {
  final sessions = [
    for (final s in process['sessions']! as List<Object?>)
      Map<String, Object?>.from(s! as Map),
  ];
  sessions[index] = change(sessions[index]);
  return {...process, 'sessions': sessions};
}

void main() {
  group('lecture tolérante (Brew.deroule)', () {
    test('sans process : une journée tirée de brew_steps', () {
      final brew = unBrassin();
      final deroule = brew.deroule;
      expect(deroule.resolu, isFalse);
      expect(deroule.probleme, isNull);
      expect(deroule.journees, hasLength(1));
      expect(deroule.brassage?.role, RoleJournee.brassage);
      expect(deroule.brassage?.offsetDays, 0);
      expect(deroule.lignes.map((s) => s.key), ['k-palier', 'k-ebullition']);
    });

    test('sans process, chronologie illisible : déroulé illisible', () {
      final brew = unBrassin(
        recipe: const RecipeContent(
          name: 'Blonde',
          brewStepsProblem: 'clé en double (1)',
        ),
      );
      expect(brew.deroule.probleme, 'clé en double (1)');
      expect(brew.deroule.resolu, isFalse);
      expect(brew.deroule.journees, isEmpty);
    });

    test('process lu par Brew.fromFirestore, prioritaire sur brew_steps', () {
      final brew = Brew.fromFirestore('b1', {
        'owner_uid': 'u',
        'name': 'Blonde',
        'status': 'planned',
        'recipe_snapshot': recetteMinimale(
          'Blonde',
          extra: {
            'brew_steps': [
              {'key': 'k-palier', 'name': 'Palier 68', 'duration_min': 45},
            ],
          },
        ),
        'equipment_snapshot': {'name': 'Cuve', 'kind': 'multi_vessel'},
        'process': deuxJournees().toFirestore(),
      });
      expect(brew.deroule.resolu, isTrue);
      expect(brew.deroule.journees.map((j) => j.key), ['j-brassage', 'j-cru']);
      expect(brew.deroule.lignes, hasLength(5));
    });

    test('process nul : une journée tirée de brew_steps', () {
      final brew = Brew.fromFirestore('b1', {
        'owner_uid': 'u',
        'name': 'Blonde',
        'status': 'planned',
        'recipe_snapshot': recetteMinimale('Blonde'),
        'equipment_snapshot': {'name': 'Cuve', 'kind': 'multi_vessel'},
        'process': null,
      });
      expect(brew.process, isNull);
      expect(brew.deroule.resolu, isFalse);
    });

    test('process illisible : panne, sans repli sur brew_steps', () {
      final brew = unBrassin().copieAvecProcess(
        lireDeroule({'format_version': 2, 'sessions': <Object?>[]}),
      );
      expect(brew.recipe.brewSteps, isNotEmpty);
      expect(brew.deroule.probleme, 'déroulé, format inconnu');
      expect(brew.deroule.resolu, isTrue);
      expect(brew.deroule.lignes, isEmpty);
    });
  });

  group('lireDeroule', () {
    final valide = deuxJournees().toFirestore();

    test('écriture puis lecture : mêmes champs', () {
      expect(_copie(valide), valide);
      final deroule = lireDeroule(valide);
      final cru = deroule.journees[1];
      expect(cru.sourceEcart, SourceEcart.recette);
      expect(cru.cleJourneeModele, 'm-cru');
      expect(cru.etapes.last.origine, OrigineEtape.houblonsACru);
      expect(
        deroule.journees.first.etapes.first.cleEtapeModele,
        'm-mise-en-place',
      );
    });

    test('liste blanche des champs écrits', () {
      final sessions = valide['sessions']! as List<Object?>;
      final journee = sessions.first! as Map<String, Object?>;
      final etape =
          (journee['steps']! as List<Object?>).first! as Map<String, Object?>;
      expect(valide.keys.toSet(), {
        'format_version',
        'template_id',
        'template_name',
        'sessions',
      });
      expect(journee.keys.toSet(), {
        'key',
        'name',
        'offset_days',
        'offset_source',
        'role',
        'template_session_key',
        'steps',
      });
      expect(etape.keys.toSet(), {
        'key',
        'name',
        'duration_min',
        'origin',
        'template_step_key',
      });
    });

    test('champ inconnu ignoré', () {
      expect(lireDeroule({...valide, 'futur': 1}).probleme, isNull);
    });

    for (final (label, raw) in <(String, Object?)>[
      ('texte', 'brassage'),
      ('format inconnu', {...valide, 'format_version': 2}),
      ('aucune journée', {...valide, 'sessions': <Object?>[]}),
      (
        'six journées',
        {
          ...valide,
          'sessions': List.filled(6, (valide['sessions']! as List).first),
        },
      ),
      (
        'clé d\'étape en double sur deux journées',
        _avecJournee(valide, 1, (s) {
          final steps = [...s['steps']! as List<Object?>];
          steps[0] = {...steps[0]! as Map<String, Object?>, 'key': 'k-palier'};
          return {...s, 'steps': steps};
        }),
      ),
      (
        'clé de journée en double',
        _avecJournee(valide, 1, (s) => {...s, 'key': 'j-brassage'}),
      ),
      (
        'durée de 700 min',
        _avecJournee(valide, 1, (s) {
          final steps = [...s['steps']! as List<Object?>];
          steps[0] = {
            ...steps[0]! as Map<String, Object?>,
            'duration_min': 700,
          };
          return {...s, 'steps': steps};
        }),
      ),
      (
        'origine inconnue',
        _avecJournee(valide, 1, (s) {
          final steps = [...s['steps']! as List<Object?>];
          steps[0] = {...steps[0]! as Map<String, Object?>, 'origin': 'autre'};
          return {...s, 'steps': steps};
        }),
      ),
      (
        'journée de brassage hors de la première place',
        _avecJournee(valide, 1, (s) => {...s, 'role': 'brew'}),
      ),
      (
        'écart de 400 jours',
        _avecJournee(valide, 1, (s) => {...s, 'offset_days': 400}),
      ),
      (
        '121 étapes',
        _avecJournee(
          valide,
          1,
          (s) => {
            ...s,
            'steps': [
              for (var i = 0; i < 121; i++)
                {
                  'key': 'k$i',
                  'name': 'Étape $i',
                  'duration_min': 1,
                  'origin': 'template',
                },
            ],
          },
        ),
      ),
    ]) {
      test('illisible : $label', () {
        final deroule = lireDeroule(raw);
        expect(deroule.probleme, isNotNull, reason: label);
        expect(deroule.probleme, startsWith('déroulé, '));
        expect(deroule.journees, isEmpty);
        expect(deroule.resolu, isTrue);
      });
    }
  });

  group('erreurDeroule', () {
    test('déroulé valide', () {
      expect(erreurDeroule(deuxJournees()), isNull);
    });

    test('clé d\'étape en double sur deux journées', () {
      final d = deuxJournees();
      final cru = d.journees[1];
      final doublon = Deroule(
        journees: [
          d.journees[0],
          JourneeDeroulee(
            key: cru.key,
            name: cru.name,
            offsetDays: cru.offsetDays,
            sourceEcart: cru.sourceEcart,
            role: cru.role,
            etapes: [
              const EtapeDeroulee(ligne: palier, origine: OrigineEtape.modele),
            ],
          ),
        ],
      );
      expect(erreurDeroule(doublon), 'Journée 2 : clé d\'étape en double.');
    });

    test('déroulé illisible : refusé', () {
      expect(
        erreurDeroule(const Deroule.illisible('x', resolu: true)),
        'Déroulé illisible.',
      );
      expect(
        () => const Deroule.illisible('x', resolu: true).toFirestore(),
        throwsStateError,
      );
    });

    test('étape hors bornes : rang de la journée et de l\'étape', () {
      final d = deuxJournees();
      final longue = Deroule(
        journees: [
          d.journees[0],
          const JourneeDeroulee(
            key: 'j-cru',
            name: 'Cru',
            offsetDays: 4,
            sourceEcart: SourceEcart.modele,
            role: RoleJournee.autre,
            etapes: [
              EtapeDeroulee(
                ligne: BrewStepLine(key: 'k1', name: 'Long', durationMin: 700),
                origine: OrigineEtape.modele,
              ),
            ],
          ),
        ],
      );
      expect(
        erreurDeroule(longue),
        'Journée 2, étape 1 : durée hors de 0 à 600 minutes.',
      );
    });

    test('deux journées d\'embouteillage refusées', () {
      final d = deuxJournees();
      JourneeDeroulee embouteillage(String key) => JourneeDeroulee(
        key: key,
        name: 'Embouteillage',
        offsetDays: 14,
        sourceEcart: SourceEcart.modele,
        role: RoleJournee.embouteillage,
        etapes: const [],
      );
      expect(
        erreurDeroule(
          Deroule(
            journees: [d.journees[0], embouteillage('a'), embouteillage('b')],
          ),
        ),
        'Une seule journée d\'embouteillage.',
      );
    });
  });

  group('PlanDuJour : calcul journée par journée', () {
    final debutAt = DateTime(2026, 11, 8, 8);
    final brew = unBrassin(brewedAt: debutAt).copieAvecProcess(deuxJournees());

    test('étapes de la journée de brassage seules', () {
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: const [],
        now: debutAt,
      );
      expect(plan.lignes.map((l) => l.step.key), [
        'k-mise-en-place',
        'k-palier',
        'k-ebullition',
      ]);
      expect(plan.finPrevue, DateTime(2026, 11, 8, 10, 15));
    });

    test('un début d\'une autre journée ne rend rien « Non faite »', () {
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: [
          debut('e1', 'k-mise-en-place', debutAt),
          debut('e2', 'k-desinfection', DateTime(2026, 11, 12, 9)),
          debut('e3', 'k-desinfection', DateTime(2026, 11, 12, 9, 5)),
        ],
        now: DateTime(2026, 11, 8, 8, 10),
      );
      expect(plan.lignes.map((l) => l.status), [
        StepStatus.running,
        StepStatus.pending,
        StepStatus.pending,
      ]);
      expect(plan.anomalies, isEmpty);
      expect(plan.lignes.expand((l) => l.doublons), isEmpty);
    });

    test('étape inconnue de toutes les journées : anomalie', () {
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: [debut('e1', 'k-inconnue', debutAt)],
        now: debutAt,
      );
      expect(plan.anomalies.single.event.id, 'e1');
    });

    test(
      'mesure d\'une étape d\'une autre journée : ni ici, ni sans étape',
      () {
        final plan = PlanDuJour.calculer(
          brew: brew,
          events: [
            mesure(
              'm1',
              'k-desinfection',
              MeasureType.temperature,
              20,
              debutAt,
            ),
            mesure('m2', null, MeasureType.ph, 5.4, debutAt),
          ],
          now: debutAt,
        );
        expect(plan.lignes.expand((l) => l.mesures), isEmpty);
        expect(plan.mesuresSansEtape.single.id, 'm2');
      },
    );
  });
}

extension on Brew {
  /// Copie du brassin avec [process], pour les tests.
  Brew copieAvecProcess(Deroule process) => Brew(
    id: id,
    ownerUid: ownerUid,
    ownerName: ownerName,
    name: name,
    status: status,
    recipeId: recipeId,
    recipe: recipe,
    equipment: equipment,
    plannedFor: plannedFor,
    brewedAt: brewedAt,
    process: process,
  );
}
