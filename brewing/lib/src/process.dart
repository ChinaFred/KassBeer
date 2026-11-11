import 'bitterness.dart';
import 'brew_steps.dart';
import 'errors.dart';
import 'recipe_calculation.dart';

/// Nombre de journées d'un modèle de processus et d'un déroulé (ADR-009).
const maxProcessSessions = 5;

/// Écart maximal d'une journée, en jours depuis le début du brassage.
const maxProcessOffsetDays = 365;

/// Minutes par jour : un houblon à cru ajouté à `dayMin` minutes du début de la
/// fermentation tombe au jour `round(dayMin / 1 440)`.
const _minutesPerDay = 1440;

/// Élément d'une journée de modèle : une étape fixe, ou un bloc tiré de la
/// recette figée du brassin.
enum ProcessTemplateItem {
  /// Étape fixe du modèle (désinfection, nettoyage…).
  step,

  /// Chronologie de la recette (`brew_steps`), ou son préremplissage.
  recipeSteps,

  /// Une étape par houblon à cru.
  dryHops,

  /// Une étape par houblon puis par ajout au conditionnement.
  packagingAdditions,
}

/// Journée d'un modèle de processus, vue par la résolution : son écart et la
/// nature de ses éléments. Noms et durées restent dans l'application.
class ProcessTemplateSession {
  /// Crée la journée. [offsetDays] de 0 à [maxProcessOffsetDays].
  ///
  /// Lève [BrewingInputException] si [offsetDays] sort de ces bornes.
  ProcessTemplateSession({
    required this.offsetDays,
    required List<ProcessTemplateItem> items,
    this.requiresRecipeBlock = false,
  }) : items = List.unmodifiable(items) {
    requireRange('offsetDays', offsetDays, 0, maxProcessOffsetDays);
  }

  /// Écart en jours depuis le début du brassage.
  final int offsetDays;

  /// Éléments, dans l'ordre de la journée.
  final List<ProcessTemplateItem> items;

  /// La journée n'est reprise que si son bloc tiré de la recette n'est pas vide.
  final bool requiresRecipeBlock;
}

/// Défaut d'un modèle de processus qui empêche sa résolution.
enum ProcessTemplateIssueKind {
  /// Aucune journée.
  noSession,

  /// Plus de [maxProcessSessions] journées.
  tooManySessions,

  /// La première journée n'a pas un écart de 0 jour.
  firstOffsetNotZero,

  /// La première journée n'a pas de bloc `recipeSteps`.
  recipeStepsMissing,

  /// Un bloc `recipeSteps` hors de la première journée, ou deux.
  recipeStepsTwice,

  /// Un bloc `dryHops` ou `packagingAdditions` dans la première journée.
  blockInFirstSession,

  /// Deux blocs `dryHops` dans le modèle.
  dryHopsTwice,

  /// Deux blocs `packagingAdditions` dans le modèle.
  packagingTwice,

  /// Les blocs `dryHops` et `packagingAdditions` dans la même journée.
  dryHopsWithPackaging,

  /// `requiresRecipeBlock` sur une journée sans bloc `dryHops` ni
  /// `packagingAdditions`.
  requiresRecipeBlockWithoutBlock,

  /// Un écart plus petit que celui de la journée précédente.
  offsetDecreasing,
}

/// Défaut d'un modèle, et la journée qui le porte.
class ProcessTemplateIssue {
  /// Crée le défaut.
  const ProcessTemplateIssue(this.kind, [this.sessionIndex]);

  /// Nature du défaut.
  final ProcessTemplateIssueKind kind;

  /// Place de la journée fautive, ou nulle pour un défaut du modèle entier.
  final int? sessionIndex;
}

/// Premier défaut de [sessions] qui empêche la résolution, ou `null`.
///
/// Contraintes d'ADR-009 : de 1 à [maxProcessSessions] journées ; la première
/// est la journée de brassage (écart 0, seul bloc `recipeSteps` du modèle) ;
/// un bloc `dryHops` et un bloc `packagingAdditions` au plus, jamais dans la
/// première journée ni dans la même ; `requiresRecipeBlock` seulement sur une
/// journée qui porte l'un d'eux ; écarts qui ne décroissent pas.
ProcessTemplateIssue? processTemplateIssue(
  List<ProcessTemplateSession> sessions,
) {
  if (sessions.isEmpty) {
    return const ProcessTemplateIssue(ProcessTemplateIssueKind.noSession);
  }
  if (sessions.length > maxProcessSessions) {
    return const ProcessTemplateIssue(ProcessTemplateIssueKind.tooManySessions);
  }
  var dryHops = 0;
  var packaging = 0;
  for (final (i, s) in sessions.indexed) {
    ProcessTemplateIssue issue(ProcessTemplateIssueKind kind) =>
        ProcessTemplateIssue(kind, i);
    final recipe = _count(s, ProcessTemplateItem.recipeSteps);
    final dry = _count(s, ProcessTemplateItem.dryHops);
    final pack = _count(s, ProcessTemplateItem.packagingAdditions);
    if (i == 0) {
      if (s.offsetDays != 0) {
        return issue(ProcessTemplateIssueKind.firstOffsetNotZero);
      }
      if (recipe == 0) {
        return issue(ProcessTemplateIssueKind.recipeStepsMissing);
      }
      if (dry + pack > 0) {
        return issue(ProcessTemplateIssueKind.blockInFirstSession);
      }
    }
    if (recipe > (i == 0 ? 1 : 0)) {
      return issue(ProcessTemplateIssueKind.recipeStepsTwice);
    }
    dryHops += dry;
    packaging += pack;
    if (dryHops > 1) return issue(ProcessTemplateIssueKind.dryHopsTwice);
    if (packaging > 1) return issue(ProcessTemplateIssueKind.packagingTwice);
    if (dry > 0 && pack > 0) {
      return issue(ProcessTemplateIssueKind.dryHopsWithPackaging);
    }
    if (s.requiresRecipeBlock && dry + pack == 0) {
      return issue(ProcessTemplateIssueKind.requiresRecipeBlockWithoutBlock);
    }
    if (i > 0 && s.offsetDays < sessions[i - 1].offsetDays) {
      return issue(ProcessTemplateIssueKind.offsetDecreasing);
    }
  }
  return null;
}

int _count(ProcessTemplateSession s, ProcessTemplateItem item) =>
    s.items.where((i) => i == item).length;

/// Recette figée du brassin, vue par la résolution.
class ProcessRecipe {
  /// Crée la recette.
  ///
  /// [brewStepCount] : nombre d'étapes de `brew_steps` ; à 0, le bloc
  /// `recipeSteps` reçoit le préremplissage [defaultBrewSteps] calculé sur
  /// [mashSteps], [boilMinutes] et [hops]. [hopDayMinutes] : un élément par
  /// houblon de [hops], jour d'ajout à cru en minutes depuis le début de la
  /// fermentation (`timing.time`), ou nul. [othersAtPackaging] : un élément par
  /// ajout de la recette, vrai pour un ajout au conditionnement.
  ///
  /// Lève [BrewingInputException] si [brewStepCount] est négatif ou si
  /// [hopDayMinutes] n'a pas la longueur de [hops].
  ProcessRecipe({
    required this.brewStepCount,
    this.mashSteps = const [],
    this.boilMinutes,
    this.hops = const [],
    List<int?>? hopDayMinutes,
    this.othersAtPackaging = const [],
  }) : hopDayMinutes = hopDayMinutes ?? List.filled(hops.length, null) {
    requireNonNegative('brewStepCount', brewStepCount);
    if (this.hopDayMinutes.length != hops.length) {
      throw BrewingInputException(
        'hopDayMinutes',
        this.hopDayMinutes.length,
        'un élément par houblon attendu (${hops.length})',
      );
    }
  }

  /// Nombre d'étapes de la chronologie de la recette.
  final int brewStepCount;

  /// Paliers d'empâtage, pour le préremplissage.
  final List<MashStepInput> mashSteps;

  /// Durée d'ébullition en minutes, pour le préremplissage.
  final double? boilMinutes;

  /// Houblons, dans l'ordre de la recette.
  final List<HopInput> hops;

  /// Jour d'ajout à cru de chaque houblon, en minutes, ou nul.
  final List<int?> hopDayMinutes;

  /// Pour chaque ajout de la recette : vrai s'il se fait au conditionnement.
  final List<bool> othersAtPackaging;
}

/// Jour d'un houblon à cru ajouté à [dayMinutes] minutes du début de la
/// fermentation : `round(dayMinutes / 1 440)`.
///
/// Lève [BrewingInputException] si [dayMinutes] est négatif ou si le jour
/// dépasse [maxProcessOffsetDays].
int dryHopDay(int dayMinutes) {
  requireNonNegative('dayMinutes', dayMinutes);
  final day = (dayMinutes / _minutesPerDay).round();
  requireRange('dryHopDay', day, 0, maxProcessOffsetDays);
  return day;
}

/// Date d'une journée : le jour calendaire local de [start] plus [offsetDays],
/// à minuit. Inverse de `fermentationDayNumber` : un changement d'heure ne
/// décale pas la date.
///
/// [start] : `brewed_at`, sinon `planned_for`. Une heure UTC rend une date UTC.
/// Lève [BrewingInputException] si [offsetDays] sort de 0 à
/// [maxProcessOffsetDays].
DateTime processSessionDate({
  required DateTime start,
  required int offsetDays,
}) {
  requireRange('offsetDays', offsetDays, 0, maxProcessOffsetDays);
  return start.isUtc
      ? DateTime.utc(start.year, start.month, start.day + offsetDays)
      : DateTime(start.year, start.month, start.day + offsetDays);
}

/// Origine d'une étape résolue.
enum ProcessStepSource {
  /// Étape fixe du modèle : [ProcessStepDraft.index] est sa place dans
  /// [ProcessTemplateSession.items].
  template,

  /// Étape de `brew_steps` de la recette : [ProcessStepDraft.index] est sa
  /// place, la clé est gardée.
  recipeStep,

  /// Étape du préremplissage : [ProcessStepDraft.index] est sa place dans
  /// [ProcessResolution.prefill].
  prefill,

  /// Houblon à cru `hops[index]`, 0 min.
  dryHop,

  /// Houblon au conditionnement `hops[index]`, 0 min.
  packagingHop,

  /// Ajout au conditionnement `others[index]`, 0 min.
  packagingOther,
}

/// Étape résolue, sans clé ni libellé : l'application les crée.
class ProcessStepDraft {
  /// Crée l'étape.
  const ProcessStepDraft(this.source, this.index);

  /// Origine.
  final ProcessStepSource source;

  /// Place dans la liste d'origine (voir [ProcessStepSource]).
  final int index;
}

/// Rôle d'une journée résolue.
enum ProcessSessionRole {
  /// Journée de brassage, la première.
  brew,

  /// Journée qui portait le bloc `packagingAdditions` dans le modèle.
  packaging,

  /// Autre journée.
  other,
}

/// Source de l'écart d'une journée résolue.
enum ProcessOffsetSource {
  /// Écart du modèle.
  template,

  /// Jour d'ajout à cru donné par la recette.
  recipe,
}

/// Journée résolue, sans clé ni libellé.
class ProcessSessionDraft {
  /// Crée la journée.
  const ProcessSessionDraft({
    required this.templateSessionIndex,
    required this.offsetDays,
    required this.offsetSource,
    required this.role,
    required this.repeat,
    required this.steps,
  });

  /// Place de la journée du modèle dont elle vient.
  final int templateSessionIndex;

  /// Écart en jours depuis le début du brassage.
  final int offsetDays;

  /// Source de l'écart.
  final ProcessOffsetSource offsetSource;

  /// Rôle.
  final ProcessSessionRole role;

  /// Rang 1, 2… quand la journée de houblonnage du modèle donne plusieurs
  /// journées (« {nom} 1 », « {nom} 2 ») ; nul sinon.
  final int? repeat;

  /// Étapes, dans l'ordre.
  final List<ProcessStepDraft> steps;
}

/// Nature d'un avertissement de la résolution.
enum ProcessWarningKind {
  /// Étape préremplie sans durée, non ajoutée.
  prefillMissingDuration,

  /// Houblon prérempli sans durée, placé en tête de sa section.
  prefillMissingHopTime,

  /// Houblon d'ébullition plus long que l'ébullition, placé en tête.
  prefillHopLongerThanBoil,

  /// La recette a des houblons à cru et le modèle n'a pas de bloc `dryHops`.
  dryHopsWithoutSession,

  /// Houblons à cru d'un jour regroupés dans une journée antérieure : plus de
  /// [maxProcessSessions] journées sinon.
  dryHopDayMerged,
}

/// Avertissement à montrer au brasseur avant d'écrire le déroulé.
class ProcessWarning {
  /// Crée l'avertissement.
  const ProcessWarning(
    this.kind, {
    this.prefillIndex,
    this.hopCount,
    this.day,
    this.intoDay,
  });

  /// Nature.
  final ProcessWarningKind kind;

  /// Étape concernée dans [ProcessResolution.prefill], pour les avertissements
  /// du préremplissage.
  final int? prefillIndex;

  /// Nombre de houblons à cru sans journée ([ProcessWarningKind.dryHopsWithoutSession]).
  final int? hopCount;

  /// Jour regroupé ([ProcessWarningKind.dryHopDayMerged]).
  final int? day;

  /// Jour de la journée qui le reçoit ([ProcessWarningKind.dryHopDayMerged]).
  final int? intoDay;
}

/// Résultat de [resolveProcess].
class ProcessResolution {
  /// Crée le résultat.
  const ProcessResolution({
    required this.sessions,
    required this.prefill,
    required this.warnings,
  });

  /// Journées triées par écart, la journée de brassage en tête.
  final List<ProcessSessionDraft> sessions;

  /// Préremplissage complet, étapes sans durée comprises ; vide si la recette a
  /// une chronologie.
  final List<BrewStepDraft> prefill;

  /// Avertissements, dans l'ordre : préremplissage, puis houblons à cru.
  final List<ProcessWarning> warnings;
}

/// Résout le modèle [template] avec la recette figée [recipe] (ADR-009).
///
/// Chaque journée garde ses étapes fixes et remplace ses blocs : `recipeSteps`
/// par la chronologie de la recette, ou à défaut par son préremplissage, sans
/// les étapes sans durée ; `dryHops` par un houblon à cru par étape ;
/// `packagingAdditions` par les houblons puis les ajouts au conditionnement.
/// Un bloc vide disparaît, et sa journée aussi si elle porte
/// `requiresRecipeBlock`. Un houblon à cru qui a un jour d'ajout tombe à
/// [dryHopDay] ; sans jour, à l'écart du modèle. La journée de houblonnage se
/// répète une fois par jour distinct ; au-delà de [maxProcessSessions]
/// journées, les jours les plus tardifs se regroupent dans le premier jour
/// regroupé. Les journées se trient par écart, à égalité dans l'ordre du
/// modèle.
///
/// Lève [BrewingInputException] si le modèle a un défaut
/// ([processTemplateIssue]) ou si un jour d'ajout est invalide.
ProcessResolution resolveProcess({
  required List<ProcessTemplateSession> template,
  required ProcessRecipe recipe,
}) {
  final issue = processTemplateIssue(template);
  if (issue != null) {
    throw BrewingInputException(
      'template',
      issue.sessionIndex,
      'modèle invalide : ${issue.kind.name}',
    );
  }

  final prefill = recipe.brewStepCount > 0
      ? const <BrewStepDraft>[]
      : defaultBrewSteps(
          mashSteps: recipe.mashSteps,
          boilMinutes: recipe.boilMinutes,
          hops: recipe.hops,
        );
  final warnings = <ProcessWarning>[
    for (final (i, d) in prefill.indexed)
      if (d.durationMinutes == null)
        ProcessWarning(
          ProcessWarningKind.prefillMissingDuration,
          prefillIndex: i,
        )
      else if (d.problem == BrewStepProblem.missingHopTime)
        ProcessWarning(
          ProcessWarningKind.prefillMissingHopTime,
          prefillIndex: i,
        )
      else if (d.problem == BrewStepProblem.hopLongerThanBoil)
        ProcessWarning(
          ProcessWarningKind.prefillHopLongerThanBoil,
          prefillIndex: i,
        ),
  ];

  final dryHops = <int>[];
  final dryDays = <int, int?>{};
  for (final (i, hop) in recipe.hops.indexed) {
    if (hop.use != HopUse.dryHop) continue;
    dryHops.add(i);
    final minutes = recipe.hopDayMinutes[i];
    dryDays[i] = minutes == null ? null : dryHopDay(minutes);
  }
  final packaging = [
    for (final (i, hop) in recipe.hops.indexed)
      if (hop.use == HopUse.package)
        ProcessStepDraft(ProcessStepSource.packagingHop, i),
    for (final (i, atPackaging) in recipe.othersAtPackaging.indexed)
      if (atPackaging) ProcessStepDraft(ProcessStepSource.packagingOther, i),
  ];

  List<ProcessStepDraft> stepsOf(
    ProcessTemplateSession session,
    List<int> hops,
  ) => [
    for (final (j, item) in session.items.indexed)
      ...switch (item) {
        ProcessTemplateItem.step => [
          ProcessStepDraft(ProcessStepSource.template, j),
        ],
        ProcessTemplateItem.recipeSteps =>
          recipe.brewStepCount > 0
              ? [
                  for (var k = 0; k < recipe.brewStepCount; k++)
                    ProcessStepDraft(ProcessStepSource.recipeStep, k),
                ]
              : [
                  for (final (k, d) in prefill.indexed)
                    if (d.durationMinutes != null)
                      ProcessStepDraft(ProcessStepSource.prefill, k),
                ],
        ProcessTemplateItem.dryHops => [
          for (final i in hops) ProcessStepDraft(ProcessStepSource.dryHop, i),
        ],
        ProcessTemplateItem.packagingAdditions => packaging,
      },
  ];

  final sessions = <_Session>[];
  var dryBlock = false;
  for (final (t, session) in template.indexed) {
    final role = t == 0
        ? ProcessSessionRole.brew
        : session.items.contains(ProcessTemplateItem.packagingAdditions)
        ? ProcessSessionRole.packaging
        : ProcessSessionRole.other;
    if (session.items.contains(ProcessTemplateItem.dryHops)) {
      dryBlock = true;
      if (dryHops.isEmpty) {
        if (!session.requiresRecipeBlock) {
          sessions.add(_Session(t, session, role, session.offsetDays, []));
        }
        continue;
      }
      final byDay = <int, List<int>>{};
      for (final i in dryHops) {
        (byDay[dryDays[i] ?? session.offsetDays] ??= []).add(i);
      }
      for (final day in byDay.keys.toList()..sort()) {
        sessions.add(
          _Session(t, session, role, day, byDay[day]!, split: true)
            ..fromTemplate = byDay[day]!.any((i) => dryDays[i] == null),
        );
      }
      continue;
    }
    if (packaging.isEmpty &&
        session.requiresRecipeBlock &&
        session.items.contains(ProcessTemplateItem.packagingAdditions)) {
      continue;
    }
    sessions.add(_Session(t, session, role, session.offsetDays, []));
  }
  if (dryHops.isNotEmpty && !dryBlock) {
    warnings.add(
      ProcessWarning(
        ProcessWarningKind.dryHopsWithoutSession,
        hopCount: dryHops.length,
      ),
    );
  }

  final split = sessions.where((s) => s.split).toList();
  final excess = sessions.length - maxProcessSessions;
  if (excess > 0) {
    // Le modèle a 5 journées au plus, dont une seule de houblonnage : l'excès
    // est plus petit que le nombre de jours de houblonnage.
    final merged = split.sublist(split.length - excess - 1);
    final into = merged.first;
    for (final s in merged.skip(1)) {
      into.hops.addAll(s.hops);
      sessions.remove(s);
      split.remove(s);
      warnings.add(
        ProcessWarning(
          ProcessWarningKind.dryHopDayMerged,
          day: s.offsetDays,
          intoDay: into.offsetDays,
        ),
      );
    }
  }

  final ordered = [...sessions.indexed]
    ..sort((a, b) {
      final byOffset = a.$2.offsetDays.compareTo(b.$2.offsetDays);
      if (byOffset != 0) return byOffset;
      final byTemplate = a.$2.templateIndex.compareTo(b.$2.templateIndex);
      return byTemplate != 0 ? byTemplate : a.$1.compareTo(b.$1);
    });
  return ProcessResolution(
    sessions: List.unmodifiable([
      for (final (_, s) in ordered)
        ProcessSessionDraft(
          templateSessionIndex: s.templateIndex,
          offsetDays: s.offsetDays,
          offsetSource: s.split && !s.fromTemplate
              ? ProcessOffsetSource.recipe
              : ProcessOffsetSource.template,
          role: s.role,
          repeat: s.split && split.length > 1 ? split.indexOf(s) + 1 : null,
          steps: List.unmodifiable(stepsOf(s.template, s.hops)),
        ),
    ]),
    prefill: List.unmodifiable(prefill),
    warnings: List.unmodifiable(warnings),
  );
}

/// Journée en cours de résolution.
class _Session {
  _Session(
    this.templateIndex,
    this.template,
    this.role,
    this.offsetDays,
    this.hops, {
    this.split = false,
  });

  final int templateIndex;
  final ProcessTemplateSession template;
  final ProcessSessionRole role;
  final int offsetDays;

  /// Houblons à cru de la journée, dans l'ordre des jours puis de la recette.
  final List<int> hops;

  /// Journée tirée du bloc `dryHops`, une par jour distinct.
  final bool split;

  /// Au moins un de ses houblons n'a pas de jour : l'écart vient du modèle.
  bool fromTemplate = false;
}
