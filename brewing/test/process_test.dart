import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

ProcessTemplateItem _item(String kind) => switch (kind) {
  'step' => ProcessTemplateItem.step,
  'recipe_steps' => ProcessTemplateItem.recipeSteps,
  'dry_hops' => ProcessTemplateItem.dryHops,
  'packaging_additions' => ProcessTemplateItem.packagingAdditions,
  _ => throw ArgumentError(kind),
};

/// Journées d'un modèle de la fixture : éléments en objets (`kind`, nom,
/// durée) ou en simples noms de nature.
List<ProcessTemplateSession> _sessions(Object? raw) => [
  for (final s in objects(raw))
    ProcessTemplateSession(
      offsetDays: s['offset_days'] as int,
      requiresRecipeBlock: s['requires_recipe_block'] as bool? ?? false,
      items: [
        for (final i in s['items'] as List<Object?>)
          _item(
            i is String ? i : (i as Map<String, Object?>)['kind'] as String,
          ),
      ],
    ),
];

ProcessRecipe _recipe(Map<String, Object?> r) {
  final hops = objects(r['hops'] ?? const <Object?>[]);
  return ProcessRecipe(
    brewStepCount: r['brew_step_count'] as int,
    mashSteps: [
      for (final m in objects(r['mash_steps'] ?? const <Object?>[]))
        MashStepInput(
          tempC: optionalNumber(m['temp_c']),
          durationMinutes: optionalNumber(m['duration_minutes']),
        ),
    ],
    boilMinutes: optionalNumber(r['boil_minutes']),
    hops: [
      for (final h in hops)
        HopInput(
          name: h['name'] as String,
          massGrams: number(h['mass_grams']),
          use: HopUse.values.byName(h['use'] as String),
          form: HopForm.pellet,
          minutes: optionalNumber(h['minutes']),
        ),
    ],
    hopDayMinutes: [for (final h in hops) h['day_minutes'] as int?],
    othersAtPackaging: [
      for (final o in r['others_at_packaging'] as List<Object?>? ?? const [])
        o! as bool,
    ],
  );
}

String _step(ProcessStepDraft s) {
  final source = switch (s.source) {
    ProcessStepSource.template => 'template',
    ProcessStepSource.recipeStep => 'recipe_step',
    ProcessStepSource.prefill => 'prefill',
    ProcessStepSource.dryHop => 'dry_hop',
    ProcessStepSource.packagingHop => 'packaging_hop',
    ProcessStepSource.packagingOther => 'packaging_other',
  };
  return '$source:${s.index}';
}

void main() {
  final fixture = loadFixture('process');
  final templates = fixture['templates'] as Map<String, Object?>;
  List<ProcessTemplateSession> template(Object? id) =>
      _sessions((templates[id] as Map<String, Object?>)['sessions']);

  test('résolution d\'un modèle avec la recette figée', () {
    for (final c in objects(fixture['cases'])) {
      final result = resolveProcess(
        template: template(c['template']),
        recipe: _recipe(c['recipe'] as Map<String, Object?>),
      );
      final expected = c['expected'] as Map<String, Object?>;
      final sessions = objects(expected['sessions']);
      expect(result.sessions.length, sessions.length, reason: label(c));
      for (final (i, e) in sessions.indexed) {
        final s = result.sessions[i];
        final at = '${label(c)} / journée $i';
        expect(s.templateSessionIndex, e['template_session'], reason: at);
        expect(s.offsetDays, e['offset_days'], reason: at);
        expect(s.offsetSource.name, e['offset_source'], reason: at);
        expect(s.role.name, e['role'], reason: at);
        expect(s.repeat, e['repeat'], reason: at);
        expect(s.steps.map(_step).toList(), e['steps'], reason: at);
      }
      final prefillCount = expected['prefill_count'];
      if (prefillCount != null) {
        expect(result.prefill.length, prefillCount, reason: label(c));
      }
      final warnings = objects(expected['warnings']);
      expect(result.warnings.length, warnings.length, reason: label(c));
      for (final (i, e) in warnings.indexed) {
        final w = result.warnings[i];
        final at = '${label(c)} / avertissement $i';
        expect(w.kind.name, e['kind'], reason: at);
        expect(w.prefillIndex, e['prefill_index'], reason: at);
        expect(w.hopCount, e['hop_count'], reason: at);
        expect(w.day, e['day'], reason: at);
        expect(w.intoDay, e['into_day'], reason: at);
      }
    }
  });

  test('modèles de la fixture sans défaut', () {
    for (final id in templates.keys) {
      expect(processTemplateIssue(template(id)), isNull, reason: id);
    }
  });

  test('modèle invalide : défaut nommé, résolution refusée', () {
    for (final c in objects(fixture['invalid_templates'])) {
      final sessions = _sessions(c['sessions']);
      final issue = processTemplateIssue(sessions);
      expect(issue?.kind.name, c['issue'], reason: label(c));
      expect(issue?.sessionIndex, c['session_index'], reason: label(c));
      expectInvalid(
        () => resolveProcess(
          template: sessions,
          recipe: ProcessRecipe(brewStepCount: 1),
        ),
        label(c),
      );
    }
  });

  test('journée de modèle : écart hors bornes refusé', () {
    for (final c in objects(fixture['invalid_sessions'])) {
      expectInvalid(
        () => ProcessTemplateSession(
          offsetDays: c['offset_days'] as int,
          items: const [ProcessTemplateItem.recipeSteps],
        ),
        label(c),
      );
    }
  });

  test('recette invalide : résolution refusée', () {
    for (final c in objects(fixture['invalid_recipes'])) {
      expectInvalid(
        () => resolveProcess(
          template: template('exemple'),
          recipe: _recipe(c['recipe'] as Map<String, Object?>),
        ),
        label(c),
      );
    }
    expectInvalid(
      () => ProcessRecipe(brewStepCount: -1),
      'nombre d\'étapes négatif',
    );
    expectInvalid(
      () => ProcessRecipe(
        brewStepCount: 1,
        hops: [
          HopInput(
            name: 'Citra',
            massGrams: 50,
            use: HopUse.dryHop,
            form: HopForm.pellet,
          ),
        ],
        hopDayMinutes: const [],
      ),
      'jours d\'ajout sans un élément par houblon',
    );
  });

  test('ordre des journées : brassage en tête, puis par écart', () {
    for (final c in objects(fixture['session_orders'])) {
      final offsets = [for (final o in c['offset_days']! as List) o as int];
      expect(processSessionOrder(offsets), c['expected'], reason: label(c));
    }
    for (final offsets in fixture['invalid_session_orders'] as List<Object?>) {
      expectInvalid(
        () => processSessionOrder([for (final o in offsets! as List) o as int]),
        '$offsets',
      );
    }
  });

  test('jour d\'un houblon à cru', () {
    for (final c in objects(fixture['dry_hop_days'])) {
      expect(dryHopDay(c['day_minutes'] as int), c['day'], reason: '$c');
    }
    for (final minutes in fixture['invalid_dry_hop_days'] as List<Object?>) {
      expectInvalid(() => dryHopDay(minutes! as int), '$minutes');
    }
  });

  group('prévu et réel d\'une journée', () {
    final durations = fixture['actual_durations'] as Map<String, Object?>;
    for (final c in objects(durations['cases'])) {
      test(label(c), () {
        final steps = [
          for (final s in objects(c['steps']))
            PlannedStep(
              id: s['id'] as String,
              duration: Duration(
                seconds: (number(s['planned_minutes']) * 60).round(),
              ),
            ),
        ];
        final events = [
          for (final e in objects(c['events']))
            StepEvent(
              id: e['id'] as String,
              kind: StepEventKind.fromStored(e['kind'] as String),
              stepKey: e['step'] as String,
              measuredAt: DateTime.parse(e['at'] as String),
            ),
        ];
        final now = DateTime.parse(c['now'] as String);
        final records = stepRecordsFromEvents(
          steps: steps,
          events: events,
        ).records;
        DateTime? firstStart;
        for (final r in records) {
          final s = r.startedAt;
          if (s != null && (firstStart == null || s.isBefore(firstStart))) {
            firstStart = s;
          }
        }
        final schedule = recomputeSchedule(
          steps: steps,
          plannedStart: firstStart ?? now,
          records: records,
          now: now,
        );
        final byId = {for (final r in records) r.stepId: r};
        final result = actualDurations(
          steps: [
            for (final (i, s) in steps.indexed)
              StepTiming(
                planned: s.duration,
                status: schedule[i].status,
                record: byId[s.id],
              ),
          ],
          dayClosed: c['day_closed'] as bool? ?? false,
        );

        final expected = c['expected'] as Map<String, Object?>;
        final expectedSteps = objects(expected['steps']);
        expect(result.steps.length, expectedSteps.length);
        for (final (i, e) in expectedSteps.indexed) {
          final s = result.steps[i];
          final at = 'étape ${steps[i].id}';
          expect(s.kind.name, e['kind'], reason: at);
          expect(s.plannedMinutes, e['planned'], reason: at);
          expect(s.actualMinutes, e['actual'], reason: at);
          expect(s.deltaMinutes, e['delta'], reason: at);
        }
        final day = expected['day'] as Map<String, Object?>;
        expect(result.kind.name, day['kind'], reason: 'journée');
        expect(result.plannedMinutes, day['planned'], reason: 'prévu');
        expect(result.actualMinutes, day['actual'], reason: 'réel');
        expect(result.betweenStepsMinutes, day['between'], reason: 'entre');
        expect(result.deltaMinutes, day['delta'], reason: 'écart');
        expect(result.stepsWithoutEnd, day['without_end'], reason: 'sans fin');
      });
    }

    test('étape faite sans début refusée', () {
      expectInvalid(
        () => actualDurations(
          steps: [
            StepTiming(
              planned: const Duration(minutes: 5),
              status: StepStatus.done,
            ),
          ],
        ),
        'faite sans début',
      );
      expectInvalid(
        () => StepTiming(
          planned: const Duration(minutes: -1),
          status: StepStatus.pending,
        ),
        'prévu négatif',
      );
    });
  });

  test('durée réelle proposée pour une étape de modèle', () {
    final updates = fixture['duration_updates'] as Map<String, Object?>;
    for (final c in objects(updates['cases'])) {
      final issue = durationUpdateIssue(
        actual: ActualStepDuration(
          kind: ActualStepKind.values.byName(c['kind'] as String),
          plannedMinutes: 0,
          actualMinutes: c['actual'] as int?,
        ),
        currentMinutes: number(c['current_minutes']),
      );
      expect(issue?.name, c['issue'], reason: label(c));
    }
    for (final c in objects(updates['rounded_step_minutes'])) {
      expect(
        roundedStepMinutes(number(c['minutes'])),
        c['expected'],
        reason: '${c['minutes']}',
      );
    }
    expectInvalid(() => roundedStepMinutes(-1), 'durée négative');
  });

  test('date d\'une journée, inverse du numéro de jour', () {
    for (final c in objects(fixture['session_dates'])) {
      final start = DateTime.parse(c['start'] as String);
      final offset = c['offset_days'] as int;
      final date = processSessionDate(start: start, offsetDays: offset);
      expect(date, DateTime.parse(c['expected'] as String), reason: label(c));
      expect(date.isUtc, start.isUtc, reason: label(c));
      expect(
        fermentationDayNumber(brewedAt: start, at: date),
        offset,
        reason: label(c),
      );
    }
    for (final offset in fixture['invalid_offsets'] as List<Object?>) {
      expectInvalid(
        () => processSessionDate(
          start: DateTime(2026, 11, 22),
          offsetDays: offset! as int,
        ),
        '$offset',
      );
    }
  });

  group('températures visées du jour de brassage', () {
    final section = fixture['brew_day_temperatures'] as Map<String, Object?>;
    List<List<String>> lines(List<List<TargetTemperaturePoint>> raw) => [
      for (final l in raw)
        [
          for (final p in l)
            '${p.at.toUtc().toIso8601String()} ${p.celsius} ${p.stepIndex}',
        ],
    ];
    List<List<String>> expectedLines(Object? raw) => [
      for (final l in raw! as List<Object?>)
        [
          for (final p in objects(l))
            '${DateTime.parse(p['at'] as String).toUtc().toIso8601String()} '
                '${number(p['celsius'])} ${p['step']}',
        ],
    ];
    for (final c in objects(section['cases'])) {
      test(label(c), () {
        final rawSteps = objects(c['steps']);
        final steps = [
          for (final s in rawSteps)
            PlannedStep(
              id: s['id'] as String,
              duration: Duration(minutes: s['planned_minutes'] as int),
            ),
        ];
        final events = [
          for (final e in objects(c['events']))
            StepEvent(
              id: e['id'] as String,
              kind: StepEventKind.fromStored(e['kind'] as String),
              stepKey: e['step'] as String,
              measuredAt: DateTime.parse(e['at'] as String),
            ),
        ];
        final schedule = recomputeSchedule(
          steps: steps,
          plannedStart: DateTime.parse(c['planned_start'] as String),
          records: stepRecordsFromEvents(steps: steps, events: events).records,
          now: DateTime.parse(c['now'] as String),
        );
        final result = brewDayTemperatureSeries(
          steps: steps,
          targetCelsius: [
            for (final s in rawSteps) optionalNumber(s['temp_c']),
          ],
          schedule: schedule,
        );
        final expected = c['expected'] as Map<String, Object?>;
        final origin = expected['origin'] as String?;
        expect(
          result.origin?.toUtc(),
          origin == null ? null : DateTime.parse(origin).toUtc(),
          reason: 'origine',
        );
        final starts = expected['planned_starts'] as List<Object?>?;
        expect(
          result.plannedStarts?.map((d) => d.toUtc()).toList(),
          starts?.map((d) => DateTime.parse(d! as String).toUtc()).toList(),
          reason: 'débuts du plan de départ',
        );
        expect(lines(result.planned), expectedLines(expected['planned']));
        expect(lines(result.recomputed), expectedLines(expected['recomputed']));
        expect(result.delay?.inMinutes, expected['delay_minutes']);
      });
    }

    test('entrées incohérentes refusées', () {
      final at = DateTime.utc(2026, 11, 21, 9);
      for (final c in objects(section['invalid'])) {
        expectInvalid(
          () => brewDayTemperatureSeries(
            steps: [
              for (final id in c['steps']! as List<Object?>)
                PlannedStep(id: id! as String, duration: Duration.zero),
            ],
            targetCelsius: [
              for (final t in c['temps']! as List<Object?>) optionalNumber(t),
            ],
            schedule: [
              for (final id in c['schedule']! as List<Object?>)
                ScheduledStep(
                  stepId: id! as String,
                  expectedStart: at,
                  start: at,
                  end: at,
                  status: StepStatus.pending,
                ),
            ],
          ),
          label(c),
        );
      }
      expectInvalid(
        () => brewDayTemperatureSeries(
          steps: [PlannedStep(id: 'a', duration: Duration.zero)],
          targetCelsius: const [double.nan],
          schedule: [
            ScheduledStep(
              stepId: 'a',
              expectedStart: at,
              start: at,
              end: at,
              status: StepStatus.pending,
            ),
          ],
        ),
        'température non finie',
      );
    });
  });
}
