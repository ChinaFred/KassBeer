import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../brew_day/presentation/chronologie_jour.dart';
import '../../brew_day/presentation/mesure_form.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/contenu_recette.dart';
import '../../recipes/presentation/recipe_calculations_view.dart';
import '../../recipes/presentation/recipes_providers.dart';
import '../domain/brew.dart';
import 'brews_providers.dart';

/// Fiche d'un brassin : copie figée, calculs, chronologie et saisies.
class BrewDetailScreen extends ConsumerStatefulWidget {
  const BrewDetailScreen({super.key, required this.id});

  final String id;

  static String deleteTitle(String name) => 'Supprimer « $name » ?';
  static const deleteMessage =
      'Le brassin, ses étapes et ses mesures disparaissent pour tout le groupe.';
  static const deleted = 'Brassin supprimé.';
  static const deleteOffline =
      'Suppression impossible hors ligne : ce brassin a des saisies.';
  static String deleteRejected(String name) =>
      'La suppression de « $name » a échoué.';
  static const saved = 'Brassin enregistré.';
  static String recipeChanged(DateTime date) =>
      'La recette a changé depuis la création de ce brassin. Il garde la '
      'version du ${formatDateCourte(date)}.';

  @override
  ConsumerState<BrewDetailScreen> createState() => _BrewDetailScreenState();
}

class _BrewDetailScreenState extends ConsumerState<BrewDetailScreen> {
  void _suivre(Future<void> written, String libelle) => unawaited(
    written.catchError((Object _) {
      // Déjà rapportée par le dépôt de données.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$libelle : refusée.')));
      }
    }),
  );

  Future<void> _delete(Brew brew, bool hasEvents) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmerSuppression(
      context,
      titre: BrewDetailScreen.deleteTitle(brew.name),
      paragraphes: const [BrewDetailScreen.deleteMessage],
    );
    if (!confirmed || !mounted) return;
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    final repo = ref.read(brewsRepositoryProvider);
    if (offline && hasEvents) {
      messenger.showSnackBar(
        const SnackBar(content: Text(BrewDetailScreen.deleteOffline)),
      );
      return;
    }
    // BR7 : sans saisie, immédiat, même hors ligne ; avec saisies, réseau exigé.
    final written = hasEvents
        ? repo.deleteWithEvents(brew.id)
        : repo.delete(brew.id);
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: BrewDetailScreen.deleted,
      refus: BrewDetailScreen.deleteRejected(brew.name),
    );
    context.go(AppRoutes.brews);
  }

  void _edit(Brew brew) {
    unawaited(
      showFeuilleOuDialogue<void>(
        context: context,
        builder: (_) => _FormulaireBrassin(brew: brew),
      ),
    );
  }

  Future<void> _recreate(Brew brew, Recipe recipe) async {
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recréer depuis la recette ?'),
        content: const Text(
          'Ce brassin est remplacé par un nouveau, à partir de la recette '
          'actuelle. Sa version figée de la recette est perdue ; ses notes sont '
          'recopiées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Recréer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final repo = ref.read(brewsRepositoryProvider);
    final created = repo.create(
      recipe: recipe,
      equipment: brew.equipmentRead,
      name: brew.name,
      plannedFor: brew.plannedFor,
      ownerUid: access.user.uid,
      ownerName: ownerName,
      notes: brew.notes,
    );
    final removal = repo.delete(brew.id);
    suivreEcriture(
      messenger: messenger,
      written: Future.wait([created.written, removal]),
      succes: 'Brassin recréé depuis la recette.',
      refus: 'La recréation de « ${brew.name} » a échoué.',
    );
    router.go(AppRoutes.brew(created.id));
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Brew>(
      async: ref.watch(brewsListProvider),
      id: widget.id,
      offline: access?.offline ?? false,
      textes: textesBrassin,
      onRetry: () => ref.invalidate(brewsListProvider),
      onBack: () => context.go(AppRoutes.brews),
      builder: (context, brew) => _fiche(context, brew, access?.user.uid),
    );
  }

  Widget _fiche(BuildContext context, Brew brew, String? readerUid) {
    final theme = Theme.of(context);
    final eventsAsync = ref.watch(brewEventsProvider(brew.id));
    final events = eventsAsync.value;
    final prepared = ref.watch(preparedBrewsProvider).contains(brew.id);
    final mine = brew.ownerUid == readerUid;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final content = brew.recipe;
    final equipement = EquipementConnu(brew.equipmentRead);
    final calculs = evaluerRecette(
      content,
      equipement,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(calculationReportsProvider),
      recipeKey: 'brew-${brew.id}',
    );
    final hopIbu = <int, double>{
      if (calculs case CalculsObtenus(:final calculation))
        for (final h in calculation.hopBitterness) h.hop.index: h.ibu,
    };
    final plan = evaluerPlan(
      brew: brew,
      events: [...?events?.valides],
      now: ref.read(horlogeProvider)(),
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(planReportsProvider),
    );

    final recipesList = ref.watch(recipesListProvider).value;
    final source = brew.recipeId == null
        ? null
        : switch (recipesList?.chercher(brew.recipeId!)) {
            DocumentTrouve<Recipe>(:final value) => value,
            _ => null,
          };
    final recipeChanged =
        brew.status == BrewStatus.planned &&
        source != null &&
        source.updatedAt != null &&
        brew.recipeUpdatedAt != null &&
        source.updatedAt != brew.recipeUpdatedAt;
    final noEvents = events != null && events.documents.isEmpty;

    final primaryStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
    );
    final Widget? principal = !mine
        ? null
        : switch (brew.status) {
            BrewStatus.planned => FilledButton(
              style: primaryStyle,
              onPressed: () => context.go(AppRoutes.prepareBrew(brew.id)),
              child: const Text('Préparer le brassage'),
            ),
            BrewStatus.brewing => FilledButton(
              style: primaryStyle,
              onPressed: () => context.go(AppRoutes.brewDay(brew.id)),
              child: const Text('Reprendre le brassage'),
            ),
            _ => null,
          };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Semantics(
          header: true,
          child: Text(brew.name, style: theme.textTheme.headlineSmall),
        ),
        Text(brew.status.label, style: muted),
        if (brew.recipeId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go(AppRoutes.recipe(brew.recipeId!)),
              child: Text('Recette : ${content.name} ›'),
            ),
          ),
        if (!mine)
          Text(
            'Brassin de ${libelleAuteur(ownerUid: brew.ownerUid, ownerName: brew.ownerName, readerUid: readerUid)}',
            style: muted,
          ),
        if (brew.hasPendingWrites) ...[
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Etiquette(label: 'En attente du réseau'),
          ),
        ],
        if (recipeChanged) ...[
          const SizedBox(height: 8),
          Text(
            BrewDetailScreen.recipeChanged(
              brew.recipeUpdatedAt ?? brew.createdAt!,
            ),
          ),
          if (mine && noEvents)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => unawaited(_recreate(brew, source)),
                child: const Text('Recréer depuis la recette'),
              ),
            ),
        ],
        const SizedBox(height: 16),
        ?principal,
        if (mine) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _edit(brew),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => _delete(
                  brew,
                  events == null || events.documents.isNotEmpty,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
            ],
          ),
        ],
        // Connu seulement dans la session : rien à dire quand l'information manque.
        if (mine && brew.status == BrewStatus.planned && prepared)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Préparé sur cet appareil', style: muted),
          ),
        const TitreSection('Calculs'),
        BlocCalculs(calculs: calculs, content: content, equipement: equipement),
        const TitreSection('Chronologie'),
        if (events == null && eventsAsync.hasError)
          Row(
            children: [
              const Expanded(
                child: TexteAbsent('Impossible de lire les saisies.'),
              ),
              TextButton(
                onPressed: () => ref.invalidate(brewEventsProvider(brew.id)),
                child: const Text('Réessayer'),
              ),
            ],
          )
        else if (events == null)
          const TexteAbsent('Chargement des saisies')
        else
          switch (plan) {
            PlanImpossible() => const TexteAbsent(kCalculChronologieImpossible),
            PlanObtenu(:final plan) =>
              content.brewStepsProblem != null
                  ? TexteAbsent(
                      messageChronologieIllisible(content.brewStepsProblem!),
                    )
                  : plan.lignes.isEmpty && plan.mesuresSansEtape.isEmpty
                  ? const TexteAbsent('Aucune étape.')
                  : ChronologieJour(
                      plan: plan,
                      onTapSaisie: mine
                          ? (e) => ouvrirCorrection(
                              context: context,
                              ref: ref,
                              brew: brew,
                              event: e,
                              suivre: _suivre,
                            )
                          : null,
                    ),
          },
        const TitreSection('Recette'),
        ContenuRecette(content: content, hopIbu: hopIbu),
        const TitreSection('Général'),
        LigneFiche(
          label: 'Date prévue',
          value: brew.plannedFor == null ? null : formatDate(brew.plannedFor!),
        ),
        LigneFiche(
          label: 'Brassé le',
          value: brew.brewedAt == null
              ? null
              : formatDateCourte(brew.brewedAt!),
        ),
        LigneFiche(label: 'Équipement', value: brew.equipment.name),
        if (brew.notes != null) ...[
          const TitreSection('Notes'),
          Text(brew.notes!, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}

/// « Modifier » : nom, date prévue, notes. Réécrit `owner_name` (règle `ownerNameOk`).
class _FormulaireBrassin extends ConsumerStatefulWidget {
  const _FormulaireBrassin({required this.brew});

  final Brew brew;

  @override
  ConsumerState<_FormulaireBrassin> createState() => _FormulaireBrassinState();
}

class _FormulaireBrassinState extends ConsumerState<_FormulaireBrassin> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late DateTime? _plannedFor;
  bool _saving = false;
  String? _nameError;
  final _nameFocus = FocusNode();
  final _nameKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.brew.name);
    _notes = TextEditingController(text: widget.brew.notes ?? '');
    _plannedFor = widget.brew.plannedFor;
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = ref.read(horlogeProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedFor ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) setState(() => _plannedFor = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Donnez un nom au brassin.');
      await montrerChamp(_nameKey.currentContext);
      if (mounted) _nameFocus.requestFocus();
      return;
    }
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final written = ref
        .read(brewsRepositoryProvider)
        .update(
          id: widget.brew.id,
          name: name,
          plannedFor: _plannedFor,
          notes: _notes.text,
          ownerName: ownerName,
        );
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: BrewDetailScreen.saved,
      refus: 'L\'enregistrement de « $name » a échoué.',
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final planned = _plannedFor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Modifier le brassin',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: _nameKey,
          controller: _name,
          focusNode: _nameFocus,
          maxLength: kBrewNameMaxLength,
          decoration: InputDecoration(
            labelText: 'Nom du brassin',
            errorText: _nameError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(planned == null ? 'Aucune' : formatDate(planned)),
              ),
            ),
            if (planned != null)
              IconButton(
                tooltip: 'Effacer la date',
                onPressed: () => setState(() => _plannedFor = null),
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notes,
          maxLength: kBrewNotesMaxLength,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Notes (facultatif)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const IndicateurBouton(label: 'Enregistrement')
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ],
    );
  }
}
