import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/champ_nombre.dart';
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
import '../../../core/data/lecture_document.dart';
import '../../auth/presentation/access_providers.dart';
import '../../equipment/domain/equipment.dart';
import '../../equipment/presentation/equipment_providers.dart';
import '../domain/recipe.dart';
import 'ingredient_forms.dart';
import 'recipe_calculations_view.dart';
import 'recipe_detail_screen.dart';
import 'recipes_providers.dart';

/// Nouvelle recette ([id] nul) ou modification d'une recette, en plein écran.
class RecipeEditorScreen extends ConsumerWidget {
  const RecipeEditorScreen({super.key, this.id});

  final String? id;

  static const readOnlyMessage = 'Seul l\'auteur modifie cette recette.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return const _RecipeEditor(initial: null);
    final access = ref.watch(grantedAccessProvider);
    return PageDocument<Recipe>(
      async: ref.watch(recipesListProvider),
      id: id,
      offline: access?.offline ?? false,
      textes: textesRecette,
      onRetry: () => ref.invalidate(recipesListProvider),
      onBack: () => context.go(AppRoutes.recipes),
      frame: (state) => EditeurPleinEcran(
        titre: 'Modifier la recette',
        closePath: AppRoutes.recipes,
        body: state,
      ),
      builder: (context, recipe) {
        if (recipe.ownerUid != access?.user.uid) {
          return EditeurPleinEcran(
            titre: 'Modifier la recette',
            closePath: AppRoutes.recipe(id),
            body: EtatVide(
              icon: Icons.lock_outline,
              message: readOnlyMessage,
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.recipe(id)),
                child: const Text('Voir la recette'),
              ),
            ),
          );
        }
        return _RecipeEditor(key: ValueKey(id), initial: recipe);
      },
    );
  }
}

class _RecipeEditor extends ConsumerStatefulWidget {
  const _RecipeEditor({super.key, required this.initial});

  final Recipe? initial;

  @override
  ConsumerState<_RecipeEditor> createState() => _RecipeEditorState();
}

/// Sections de l'éditeur, dans l'ordre des puces de saut.
enum _Section { general, fermentables, hops, others, yeast, steps, notes }

class _RecipeEditorState extends ConsumerState<_RecipeEditor> {
  final _formKey = GlobalKey<FormState>();
  final _keys = {for (final s in _Section.values) s: GlobalKey()};
  final _nameKey = GlobalKey();
  final _nameFocus = FocusNode();
  late final TextEditingController _name;
  late final TextEditingController _style;
  late final TextEditingController _volume;
  late final TextEditingController _boil;
  late final TextEditingController _notes;
  // Listes modifiées en place, jamais remplacées : « Annuler » après un retrait
  // réinsère la ligne dans la liste que l'écran affiche.
  late final List<FermentableLine> _fermentables;
  late final List<HopLine> _hops;
  late final List<OtherLine> _others;
  late final List<YeastLine> _yeasts;
  late final List<MashStep> _steps;
  String? _equipmentId;
  bool _equipmentTouched = false;
  bool _dirty = false;
  bool _saving = false;
  String? _nameError;

  static const nameMissing = 'Donnez un nom à la recette.';

  @override
  void initState() {
    super.initState();
    final c = widget.initial?.content;
    _name = TextEditingController(text: c?.name ?? '');
    _style = TextEditingController(text: c?.style ?? '');
    _volume = TextEditingController(text: texteSaisi(c?.batchVolumeL));
    _boil = TextEditingController(text: texteSaisi(c?.boilTimeMin));
    _notes = TextEditingController(text: c?.notes ?? '');
    _fermentables = [...?c?.fermentables];
    _hops = [...?c?.hops];
    _others = [...?c?.others];
    _yeasts = [...?c?.yeasts];
    _steps = [...?c?.mashSteps];
    _equipmentId = c?.equipmentId;
  }

  @override
  void dispose() {
    for (final c in [_name, _style, _volume, _boil, _notes]) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void _changed([Object? _]) => setState(() => _dirty = true);

  /// Équipement retenu : celui de la recette, ou, pour une nouvelle recette, le
  /// seul équipement du brasseur tant qu'il n'a rien choisi.
  String? _effectiveEquipmentId(List<Equipment> mine) {
    if (_equipmentTouched || widget.initial != null) return _equipmentId;
    return _equipmentId ?? (mine.length == 1 ? mine.single.id : null);
  }

  RecipeContent _content(String? equipmentId) {
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final initial = widget.initial?.content;
    return RecipeContent(
      name: _name.text.trim(),
      style: text(_style),
      notes: text(_notes),
      batchVolumeL: _positive(_volume.text),
      boilTimeMin: _withinBoil(_boil.text),
      equipmentId: equipmentId,
      fermentables: List.unmodifiable(_fermentables),
      hops: List.unmodifiable(_hops),
      others: List.unmodifiable(_others),
      yeasts: List.unmodifiable(_yeasts),
      mashSteps: List.unmodifiable(_steps),
      importedFrom: initial?.importedFrom,
    );
  }

  /// Volume lisible et accepté par le formulaire, sinon absent du calcul.
  double? _positive(String text) => erreurNombre(text, minExclu: true) == null
      ? lireNombre(text).valeur
      : null;

  double? _withinBoil(String text) =>
      erreurNombre(text, max: 600) == null ? lireNombre(text).valeur : null;

  Future<void> _scrollTo(GlobalKey key) => montrerChamp(key.currentContext);

  Future<void> _save(String? equipmentId) async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = nameMissing);
      await _scrollTo(_nameKey);
      if (mounted) _nameFocus.requestFocus();
      return;
    }
    // Tous les champs sont construits (colonne défilante) : un champ hors écran
    // est validé aussi. L'écran défile jusqu'au premier en erreur.
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await montrerChamp(invalid.first.context);
      return;
    }
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final content = _content(equipmentId);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    // Nom du jeton, celui que comparent les règles ; nul s'il n'y en a pas ou si
    // le jeton ne peut pas être lu (déjà rapporté).
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final repository = ref.read(recipesRepositoryProvider);
    final initial = widget.initial;
    final String id;
    final Future<void> written;
    if (initial == null) {
      final created = repository.create(
        content: content,
        ownerUid: access.user.uid,
        ownerName: ownerName,
      );
      id = created.id;
      written = created.written;
    } else {
      id = initial.id;
      written = repository.update(
        id: id,
        content: content,
        ownerName: ownerName,
      );
    }
    suivreEcriture(
      messenger: messenger,
      written: written,
      succes: access.offline
          ? RecipeDetailScreen.savedOffline
          : RecipeDetailScreen.saved,
      refus: RecipeDetailScreen.saveRejected(content.name),
    );
    setState(() {
      _saving = false;
      _dirty = false;
    });
    context.go(AppRoutes.recipe(id));
  }

  // ------------------------------------------------------------ lignes

  Future<void> _openFermentable([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireFermentescible(
      initial: index == null ? null : _fermentables[index],
      remaining: kMaxFermentables - _fermentables.length,
      onSubmit: (line) => setState(() {
        final list = [..._fermentables];
        index == null ? list.add(line) : list[index] = line;
        _replace(_fermentables, sortFermentables(list));
        _dirty = true;
      }),
    ),
  );

  Future<void> _openHop([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireHoublon(
      initial: index == null ? null : _hops[index],
      remaining: kMaxHops - _hops.length,
      recipeBoilMin: _withinBoil(_boil.text),
      onSubmit: (line) => setState(() {
        final list = [..._hops];
        index == null ? list.add(line) : list[index] = line;
        _replace(_hops, sortHops(list));
        _dirty = true;
      }),
    ),
  );

  Future<void> _openOther([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireAjout(
      initial: index == null ? null : _others[index],
      remaining: kMaxOthers - _others.length,
      onSubmit: (line) => setState(() {
        index == null ? _others.add(line) : _others[index] = line;
        _dirty = true;
      }),
    ),
  );

  Future<void> _openYeast() => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulaireLevure(
      initial: _yeasts.isEmpty ? null : _yeasts.first,
      // Une seule levure (A3) : la saisie remplace la première.
      onSubmit: (line) => setState(() {
        _replace(_yeasts, [line, ..._yeasts.skip(1)]);
        _dirty = true;
      }),
    ),
  );

  Future<void> _openStep([int? index]) => showFeuilleOuDialogue<void>(
    context: context,
    builder: (_) => FormulairePalier(
      initial: index == null ? null : _steps[index],
      remaining: kMaxMashSteps - _steps.length,
      onSubmit: (line) => setState(() {
        index == null ? _steps.add(line) : _steps[index] = line;
        _dirty = true;
      }),
    ),
  );

  /// Retire une ligne sans confirmation ; la SnackBar propose « Annuler ».
  void _remove<T>(
    List<T> list,
    int index,
    String name, {
    List<T> Function(List<T>)? sort,
  }) {
    final removed = list[index];
    setState(() {
      list.removeAt(index);
      _dirty = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: Text('« $name » retiré.'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              list.insert(index.clamp(0, list.length), removed);
              if (sort != null) {
                _replace(list, sort(list));
              }
            });
          },
        ),
      ),
    );
  }

  void _duplicateLine<T>(
    List<T> list,
    int index,
    int max, {
    List<T> Function(List<T>)? sort,
  }) {
    if (list.length >= max) return;
    setState(() {
      list.insert(index + 1, list[index]);
      if (sort != null) {
        _replace(list, sort(list));
      }
      _dirty = true;
    });
  }

  /// Remplace le contenu de [target] par [items], en place.
  static void _replace<T>(List<T> target, Iterable<T> items) {
    final copy = items.toList();
    target
      ..clear()
      ..addAll(copy);
  }

  void _moveStep(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _steps.length) return;
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(target, step);
      _dirty = true;
    });
  }

  // ------------------------------------------------------------ affichage

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    final equipmentAsync = ref.watch(equipmentListProvider);
    final readerUid = access?.user.uid;
    final allEquipment = (equipmentAsync.value?.valides ?? <Equipment>[])
      ..sort(compareEquipment(readerUid));
    final mine = [
      for (final e in allEquipment)
        if (e.ownerUid == readerUid) e,
    ];
    final equipmentId = _effectiveEquipmentId(mine);
    final equipement = equipementDe(
      equipmentId,
      equipmentAsync,
      offline: access?.offline ?? false,
    );
    final content = _content(equipmentId);
    final calculs = evaluerRecette(
      content,
      equipement,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(calculationReportsProvider),
      recipeKey: widget.initial?.id ?? 'nouvelle',
    );
    final initial = widget.initial;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= kExpandedMinWidth;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _JumpChips(
            counts: {
              _Section.fermentables: _fermentables.length,
              _Section.hops: _hops.length,
              _Section.others: _others.length,
              _Section.yeast: _yeasts.length,
              _Section.steps: _steps.length,
            },
            onJump: (s) => _scrollTo(_keys[s]!),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _sections(
                  calculs: calculs,
                  equipment: allEquipment,
                  readerUid: readerUid,
                  equipmentId: equipmentId,
                  equipement: equipement,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return EditeurPleinEcran(
      titre: initial == null ? 'Nouvelle recette' : 'Modifier la recette',
      closePath: initial == null
          ? AppRoutes.recipes
          : AppRoutes.recipe(initial.id),
      dirty: _dirty,
      saving: _saving,
      onSave: () => _save(equipmentId),
      abandonMessage:
          'Les changements de cette recette ne seront pas '
          'enregistrés.',
      bottomBar: wide || keyboardOpen
          ? null
          : BarreCalculs(
              calculs: calculs,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                showDragHandle: true,
                builder: (_) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: BlocCalculs(
                    calculs: calculs,
                    content: content,
                    equipement: equipement,
                  ),
                ),
              ),
            ),
      body: wide
          ? Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kEditorMaxWidth),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: form),
                    SizedBox(
                      width: kCalculationPanelWidth,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(8, 16, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                'Calculs',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 8),
                            BlocCalculs(
                              calculs: calculs,
                              content: content,
                              equipement: equipement,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : form,
    );
  }

  List<Widget> _sections({
    required CalculsRecette calculs,
    required List<Equipment> equipment,
    required String? readerUid,
    required String? equipmentId,
    required EquipementRecette equipement,
  }) {
    final theme = Theme.of(context);
    final volume = lireNombre(_volume.text).valeur;
    final hopIbu = <int, double>{
      if (calculs is CalculsObtenus)
        for (final h in calculs.calculation.hopBitterness) h.hop.index: h.ibu,
    };
    final longer = <int>{
      if (calculs is CalculsObtenus)
        for (final h in calculs.calculation.hopsLongerThanBoil) h.index,
    };
    final fermentableTotal = _fermentables.fold(0.0, (s, f) => s + f.weightG);
    final hopTotal = _hops.fold(0.0, (s, h) => s + h.weightG);
    final ids = {for (final e in equipment) e.id};
    Widget section(_Section s, String title, {String? trailing}) =>
        KeyedSubtree(
          key: _keys[s],
          child: TitreSection(title, trailing: trailing),
        );
    Widget add(String label, VoidCallback onPressed, {String? capMessage}) =>
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: capMessage == null ? onPressed : null,
                icon: const Icon(Icons.add),
                label: Text(label),
              ),
              if (capMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(capMessage, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        );

    return [
      section(_Section.general, 'Général'),
      KeyedSubtree(
        key: _nameKey,
        child: TextFormField(
          controller: _name,
          focusNode: _nameFocus,
          autofocus: widget.initial == null,
          maxLength: kRecipeNameMaxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Nom',
            errorText: _nameError,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() {
            _dirty = true;
            if (v.trim().isNotEmpty) _nameError = null;
          }),
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _style,
        maxLength: kRecipeNameMaxLength,
        decoration: const InputDecoration(
          labelText: 'Style (facultatif)',
          border: OutlineInputBorder(),
        ),
        onChanged: _changed,
      ),
      const SizedBox(height: 8),
      ChampNombre(
        controller: _volume,
        label: 'Volume en fermenteur (L)',
        minExclu: true,
        avertissement: volume != null && volume > kUnusualVolumeLitres
            ? 'Volume inhabituel : ${formatLitres(volume)}. Vérifiez la saisie.'
            : null,
        onChanged: _changed,
      ),
      const SizedBox(height: 16),
      ChampNombre(
        controller: _boil,
        label: 'Durée d\'ébullition (min)',
        max: 600,
        onChanged: _changed,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String?>(
        key: ValueKey('equipement-$equipmentId'),
        initialValue: equipmentId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Équipement',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('Aucun équipement')),
          for (final e in equipment)
            DropdownMenuItem(
              value: e.id,
              child: Text(
                e.ownerUid == readerUid
                    ? e.name
                    : '${e.name} (${libelleAuteur(ownerUid: e.ownerUid, ownerName: e.ownerName, readerUid: readerUid)})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (equipmentId != null && !ids.contains(equipmentId))
            DropdownMenuItem(
              value: equipmentId,
              child: Text(libelleEquipement(equipement)),
            ),
        ],
        onChanged: (id) => setState(() {
          _equipmentId = id;
          _equipmentTouched = true;
          _dirty = true;
        }),
      ),
      section(
        _Section.fermentables,
        'Malts et sucres',
        trailing: _fermentables.isEmpty
            ? null
            : '${_fermentables.length} · ${formatKilogrammes(fermentableTotal)}',
      ),
      for (final (i, f) in _fermentables.indexed)
        LigneEditeur(
          title: f.name,
          details: [
            f.kind == FermentableKind.malt ? 'Malt' : 'Sucre',
            formatKilogrammes(f.weightG),
            if (f.ebc != null) formatEbc(f.ebc!),
            if (f.yieldPct != null) 'rendement ${formatPourcent(f.yieldPct!)}',
          ],
          warning: f.weightG > kUnusualFermentableGrams
              ? quantiteInhabituelle(formatKilogrammes(f.weightG))
              : null,
          onTap: () => _openFermentable(i),
          onDuplicate: () => _duplicateLine(
            _fermentables,
            i,
            kMaxFermentables,
            sort: sortFermentables,
          ),
          onRemove: () =>
              _remove(_fermentables, i, f.name, sort: sortFermentables),
        ),
      add(
        'Ajouter un malt ou un sucre',
        _openFermentable,
        capMessage: _fermentables.length >= kMaxFermentables
            ? '$kMaxFermentables malts et sucres au plus.'
            : null,
      ),
      section(
        _Section.hops,
        'Houblons',
        trailing: _hops.isEmpty
            ? null
            : '${_hops.length} · ${formatGrammes(hopTotal)}',
      ),
      for (final (i, h) in _hops.indexed)
        LigneEditeur(
          title: h.name,
          details: [
            _hopMoment(h),
            formatGrammes(h.weightG),
            if (h.alphaPct != null) '${formatPourcent(h.alphaPct!)} alpha',
            libelleFormeHoublon(h.form),
            if (hopIbu[i] != null) formatIbu(hopIbu[i]!),
          ],
          warning: [
            if (h.weightG > kUnusualHopGrams)
              quantiteInhabituelle(formatGrammes(h.weightG)),
            if (longer.contains(i))
              'Plus long que l\'ébullition de la recette.',
          ].join(' ').nullIfEmpty,
          onTap: () => _openHop(i),
          onDuplicate: () => _duplicateLine(_hops, i, kMaxHops, sort: sortHops),
          onRemove: () => _remove(_hops, i, h.name, sort: sortHops),
        ),
      add(
        'Ajouter un houblon',
        _openHop,
        capMessage: _hops.length >= kMaxHops
            ? '$kMaxHops houblons au plus.'
            : null,
      ),
      section(
        _Section.others,
        'Autres ajouts',
        trailing: _others.isEmpty ? null : '${_others.length}',
      ),
      for (final (i, o) in _others.indexed)
        LigneEditeur(
          title: o.name,
          details: [
            formatGrammes(o.weightG),
            if (o.use != null) o.use!.label,
            if (o.timeMin != null) formatMinutes(o.timeMin!),
          ],
          warning: o.weightG > kUnusualOtherGrams
              ? quantiteInhabituelle(formatGrammes(o.weightG))
              : null,
          onTap: () => _openOther(i),
          onDuplicate: () => _duplicateLine(_others, i, kMaxOthers),
          onRemove: () => _remove(_others, i, o.name),
        ),
      add(
        'Ajouter un ajout',
        _openOther,
        capMessage: _others.length >= kMaxOthers
            ? '$kMaxOthers ajouts au plus.'
            : null,
      ),
      section(_Section.yeast, 'Levure'),
      if (_yeasts.isEmpty)
        add('Ajouter une levure', _openYeast)
      else
        LigneEditeur(
          title: _yeasts.first.name,
          details: [
            if (_yeasts.first.attenuationPct != null)
              'atténuation ${formatPourcent(_yeasts.first.attenuationPct!)}',
            if (_yeasts.first.form != null) _yeasts.first.form!.label,
          ],
          onTap: _openYeast,
          onRemove: () => _remove(_yeasts, 0, _yeasts.first.name),
        ),
      section(
        _Section.steps,
        'Paliers d\'empâtage',
        trailing: _steps.isEmpty ? null : '${_steps.length}',
      ),
      for (final (i, s) in _steps.indexed)
        LigneEditeur(
          title: s.name,
          details: [formatCelsius(s.tempC), formatMinutes(s.durationMin)],
          onTap: () => _openStep(i),
          onMoveUp: i == 0 ? null : () => _moveStep(i, -1),
          onMoveDown: i == _steps.length - 1 ? null : () => _moveStep(i, 1),
          onDuplicate: () => _duplicateLine(_steps, i, kMaxMashSteps),
          onRemove: () => _remove(_steps, i, s.name),
        ),
      add(
        'Ajouter un palier',
        _openStep,
        capMessage: _steps.length >= kMaxMashSteps
            ? '$kMaxMashSteps paliers au plus.'
            : null,
      ),
      section(_Section.notes, 'Notes'),
      TextFormField(
        controller: _notes,
        maxLength: kRecipeNotesMaxLength,
        minLines: 3,
        maxLines: 10,
        decoration: const InputDecoration(
          labelText: 'Notes (facultatif)',
          border: OutlineInputBorder(),
        ),
        onChanged: _changed,
      ),
    ];
  }

  String _hopMoment(HopLine h) {
    final t = h.timeMin;
    return switch (h.use) {
      HopUse.boil =>
        t == null ? 'Ébullition' : 'Ébullition ${formatMinutes(t)}',
      HopUse.afterBoil =>
        t == null ? 'Whirlpool' : 'Whirlpool ${formatMinutes(t)}',
      HopUse.dryHop => t == null ? 'À cru' : 'À cru ${formatJours(t)}',
    };
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// Puces de saut vers chaque section, avec le nombre de lignes.
class _JumpChips extends StatelessWidget {
  const _JumpChips({required this.counts, required this.onJump});

  final Map<_Section, int> counts;
  final ValueChanged<_Section> onJump;

  @override
  Widget build(BuildContext context) {
    String label(_Section s) => switch (s) {
      _Section.general => 'Général',
      _Section.fermentables => 'Malts et sucres (${counts[s]})',
      _Section.hops => 'Houblons (${counts[s]})',
      _Section.others => 'Autres ajouts (${counts[s]})',
      _Section.yeast => 'Levure (${counts[s]})',
      _Section.steps => 'Paliers (${counts[s]})',
      _Section.notes => 'Notes',
    };
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            for (final s in _Section.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ActionChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  label: Text(label(s)),
                  onPressed: () => onJump(s),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
