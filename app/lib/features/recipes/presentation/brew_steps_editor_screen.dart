import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_editeur.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/chronologie.dart';
import '../domain/recipe.dart';
import 'ingredient_forms.dart';
import 'recipe_detail_screen.dart';
import 'recipes_providers.dart';

/// Éditeur de la chronologie d'une recette (CH), plein écran. N'écrit que
/// `brew_steps`.
class BrewStepsEditorScreen extends ConsumerWidget {
  const BrewStepsEditorScreen({super.key, required this.id});

  final String id;

  static const titre = 'Chronologie du jour';
  static const readOnly = 'Seul l\'auteur modifie cette chronologie.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Recipe>(
      async: ref.watch(recipesListProvider),
      id: id,
      offline: access?.offline ?? false,
      textes: textesRecette,
      onRetry: () => ref.invalidate(recipesListProvider),
      onBack: () => context.go(AppRoutes.recipes),
      frame: (state) => EditeurPleinEcran(
        titre: titre,
        closePath: AppRoutes.recipes,
        body: state,
      ),
      builder: (context, recipe) {
        if (recipe.ownerUid != access?.user.uid) {
          return EditeurPleinEcran(
            titre: titre,
            closePath: AppRoutes.recipe(id),
            body: EtatVide(
              icon: Icons.lock_outline,
              message: readOnly,
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.recipe(id)),
                child: const Text('Voir la recette'),
              ),
            ),
          );
        }
        return _Editeur(key: ValueKey(id), recipe: recipe);
      },
    );
  }
}

/// Nom d'une étape préremplie : nom du palier, « Ébullition », « Whirlpool »,
/// « Ajouter Cascade 20 g ».
String nomEtapePreremplie(BrewStepDraft draft, RecipeContent content) {
  final index = draft.sourceIndex;
  return switch (draft.kind) {
    BrewStepKind.mashStep => content.mashSteps[index!].name,
    BrewStepKind.boil => 'Ébullition',
    BrewStepKind.whirlpool => 'Whirlpool',
    BrewStepKind.hopAddition => truncateName(
      'Ajouter ${content.hops[index!].name} '
      '${formatGrammes(content.hops[index].weightG)}',
      kBrewStepNameMaxLength,
    ),
  };
}

class _Editeur extends ConsumerStatefulWidget {
  const _Editeur({super.key, required this.recipe});

  final Recipe recipe;

  @override
  ConsumerState<_Editeur> createState() => _EditeurState();
}

class _EditeurState extends ConsumerState<_Editeur> {
  late final List<BrewStepLine> _steps = [...widget.recipe.content.brewSteps];
  bool _dirty = false;
  bool _saving = false;
  final _warnings = <String>[];

  void _mutate(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  void _prefill() {
    final c = widget.recipe.content;
    final drafts = defaultBrewSteps(
      mashSteps: [
        for (final m in c.mashSteps)
          MashStepInput(
            tempC: m.tempC,
            durationMinutes: m.durationMin.toDouble(),
          ),
      ],
      boilMinutes: c.boilTimeMin?.toDouble(),
      hops: [for (final h in c.hops) h.toInput()],
    );
    final repo = ref.read(recipesRepositoryProvider);
    final warnings = <String>[];
    final steps = <BrewStepLine>[];
    for (final draft in drafts) {
      final name = nomEtapePreremplie(draft, c);
      final minutes = draft.durationMinutes;
      if (minutes == null) {
        warnings.add('« $name » : durée non renseignée, étape non ajoutée.');
        continue;
      }
      if (draft.problem == BrewStepProblem.missingHopTime) {
        warnings.add('« $name » : houblon sans durée, placé en tête.');
      } else if (draft.problem == BrewStepProblem.hopLongerThanBoil) {
        warnings.add('« $name » : plus long que l\'ébullition, placé en tête.');
      }
      steps.add(
        BrewStepLine(
          key: repo.newStepKey(),
          name: name,
          durationMin: minutes,
          tempC: draft.tempC,
        ),
      );
    }
    _mutate(() {
      _steps
        ..clear()
        ..addAll(steps);
      _warnings
        ..clear()
        ..addAll(warnings);
    });
  }

  Future<void> _replaceFromRecipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _steps.length == 1
              ? 'Remplacer l\'étape ?'
              : 'Remplacer les ${_steps.length} étapes ?',
        ),
        content: const Text(
          'La chronologie sera remplacée par les paliers et l\'ébullition de la '
          'recette.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _prefill();
  }

  bool get _atMax => _steps.length >= kMaxBrewSteps;

  Future<void> _open([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireEtape(
      initial: index == null ? null : _steps[index],
      remaining: kMaxBrewSteps - _steps.length,
      newKey: ref.read(recipesRepositoryProvider).newStepKey,
      onSubmit: (line) => _mutate(() {
        if (index == null) {
          _steps.add(line);
        } else {
          _steps[index] = line;
        }
      }),
    ),
  );

  void _move(int from, int to) => _mutate(() {
    final line = _steps.removeAt(from);
    _steps.insert(to, line);
  });

  void _duplicate(int index) {
    if (_atMax) return;
    final s = _steps[index];
    _mutate(
      () => _steps.insert(
        index + 1,
        BrewStepLine(
          key: ref.read(recipesRepositoryProvider).newStepKey(),
          name: s.name,
          durationMin: s.durationMin,
          tempC: s.tempC,
        ),
      ),
    );
  }

  void _remove(int index) {
    final removed = _steps[index];
    _mutate(() => _steps.removeAt(index));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: Text('« ${removed.name} » retiré.'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            if (!mounted) return;
            _mutate(() => _steps.insert(index, removed));
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    final problem = erreurChronologie(_steps);
    final messenger = ScaffoldMessenger.of(context);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    setState(() => _saving = true);
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final written = ref
        .read(recipesRepositoryProvider)
        .updateBrewSteps(
          id: widget.recipe.id,
          steps: List.unmodifiable(_steps),
          ownerName: ownerName,
        );
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: access.offline
          ? 'Chronologie enregistrée sur l\'appareil. Elle partira au retour '
                'du réseau.'
          : 'Chronologie enregistrée.',
      refus: 'L\'enregistrement de la chronologie a échoué.',
    );
    setState(() {
      _saving = false;
      _dirty = false;
    });
    context.go(AppRoutes.recipe(widget.recipe.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decalages = decalagesChronologie(_steps);
    final hasRecipeContent =
        widget.recipe.content.mashSteps.isNotEmpty ||
        widget.recipe.content.boilTimeMin != null;
    // Dans la liste : tout défile, même avec un écran bas ou un grand texte.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _steps.isEmpty
                        ? 'Total : 0 min'
                        : 'Total : ${formatDuree(dureeChronologie(_steps))} · ${formatEtapes(_steps.length)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              if (_steps.isNotEmpty && hasRecipeContent)
                PopupMenuButton<void>(
                  tooltip: 'Plus d\'actions',
                  onSelected: (_) {},
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: _replaceFromRecipe,
                      child: const Text(
                        'Repartir des paliers et de l\'ébullition',
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        for (final w in _warnings)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              w,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
      ],
    );
    final footer = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_atMax) const TexteAbsent('60 étapes au plus.'),
          OutlinedButton.icon(
            onPressed: _atMax ? null : _open,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter une étape'),
          ),
        ],
      ),
    );
    return EditeurPleinEcran(
      titre: BrewStepsEditorScreen.titre,
      closePath: AppRoutes.recipe(widget.recipe.id),
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      abandonMessage:
          'Les changements de cette chronologie ne seront pas '
          'enregistrés.',
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kEditorMaxWidth),
          child: _steps.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: EtatVide(
                        icon: Icons.schedule,
                        message:
                            'Aucune étape. Préremplissez depuis les paliers et '
                            'l\'ébullition, ou ajoutez une étape.',
                        action: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            if (hasRecipeContent)
                              FilledButton(
                                onPressed: _prefill,
                                child: const Text(
                                  'Préremplir depuis la recette',
                                ),
                              ),
                            OutlinedButton(
                              onPressed: _open,
                              child: const Text('Ajouter une étape'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ReorderableListView.builder(
                  header: header,
                  footer: footer,
                  buildDefaultDragHandles: false,
                  itemCount: _steps.length,
                  onReorderItem: _move,
                  itemBuilder: (context, i) {
                    final s = _steps[i];
                    return Padding(
                      key: ValueKey(s.key),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: const SizedBox.square(
                              dimension: 48,
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                          Expanded(
                            child: LigneEditeur(
                              title: '${i + 1}. ${s.name}',
                              details: [
                                '+${formatDuree(decalages[i])}',
                                if (s.durationMin == 0)
                                  'action'
                                else
                                  '${formatNombre(s.durationMin, decimales: 1)}${nbsp}min',
                                if (s.tempC != null) formatCelsius(s.tempC!),
                              ],
                              onTap: () => _open(i),
                              onDuplicate: _atMax ? null : () => _duplicate(i),
                              onMoveUp: i == 0 ? null : () => _move(i, i - 1),
                              onMoveDown: i == _steps.length - 1
                                  ? null
                                  : () => _move(i, i + 1),
                              onRemove: () => _remove(i),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
