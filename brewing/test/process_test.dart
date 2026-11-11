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

  test('jour d\'un houblon à cru', () {
    for (final c in objects(fixture['dry_hop_days'])) {
      expect(dryHopDay(c['day_minutes'] as int), c['day'], reason: '$c');
    }
    for (final minutes in fixture['invalid_dry_hop_days'] as List<Object?>) {
      expectInvalid(() => dryHopDay(minutes! as int), '$minutes');
    }
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
}
