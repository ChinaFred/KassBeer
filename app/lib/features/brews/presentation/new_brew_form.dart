import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../equipment/domain/equipment.dart';
import '../../equipment/presentation/equipment_providers.dart';
import '../../recipes/domain/chronologie.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/brew.dart';

/// Ouvre le formulaire « Nouveau brassin » pour [recipe].
Future<void> ouvrirNouveauBrassin(BuildContext context, Recipe recipe) =>
    // ticket: /recettes/:id/fenetre/nouveau-brassin
    showFeuilleOuDialogue<void>(
      context: context,
      builder: (_) => FormulaireNouveauBrassin(recipe: recipe),
    );

/// Crée un brassin depuis une recette, avec une copie de la recette et de
/// l'équipement choisi (BR1, BR2).
class FormulaireNouveauBrassin extends ConsumerStatefulWidget {
  const FormulaireNouveauBrassin({super.key, required this.recipe});

  final Recipe recipe;

  static const created = 'Brassin créé.';
  static const createdOffline =
      'Brassin créé sur l\'appareil. Il partira au retour du réseau.';
  static String rejected(String name) => 'La création de « $name » a échoué.';
  static const chooseEquipment = 'Choisissez un équipement.';
  static const equipmentOffline =
      'Équipement indisponible hors ligne. Reconnectez le téléphone pour créer '
      'le brassin.';

  @override
  ConsumerState<FormulaireNouveauBrassin> createState() =>
      _FormulaireNouveauBrassinState();
}

class _FormulaireNouveauBrassinState
    extends ConsumerState<FormulaireNouveauBrassin> {
  late final TextEditingController _name;
  String? _equipmentId;
  bool _equipmentTouched = false;
  String? _equipmentError;
  DateTime? _plannedFor;
  bool _creating = false;
  String? _nameError;
  final _nameFocus = FocusNode();
  final _nameKey = GlobalKey();
  final _equipmentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.recipe.name);
    final now = ref.read(horlogeProvider)();
    _plannedFor = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Equipment? _selected(List<Equipment> all, String? readerUid) {
    final id = _equipmentId;
    if (_equipmentTouched && id != null) {
      return all.where((e) => e.id == id).firstOrNull;
    }
    final recipeEq = widget.recipe.content.equipmentId;
    final preset = recipeEq == null
        ? null
        : all.where((e) => e.id == recipeEq).firstOrNull;
    if (preset != null) return preset;
    final mine = all.where((e) => e.ownerUid == readerUid).toList();
    return mine.length == 1 ? mine.single : null;
  }

  Future<void> _pickDate() async {
    final now = ref.read(horlogeProvider)();
    // ticket: aucun (sélecteur du système)
    final picked = await showDatePicker(
      context: context,
      initialDate: _plannedFor ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) setState(() => _plannedFor = picked);
  }

  Future<void> _create(Equipment? equipment) async {
    final name = _name.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Donnez un nom au brassin.' : null;
      _equipmentError = equipment == null
          ? FormulaireNouveauBrassin.chooseEquipment
          : null;
    });
    if (name.isEmpty) {
      await montrerChamp(_nameKey.currentContext);
      if (mounted) _nameFocus.requestFocus();
      return;
    }
    if (equipment == null) {
      await montrerChamp(_equipmentKey.currentContext);
      return;
    }
    if (_creating) return;
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    setState(() => _creating = true);
    // Lecture du nom du jeton : 3 s au plus, comme pour les recettes.
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final created = ref
        .read(brewsRepositoryProvider)
        .create(
          recipe: widget.recipe,
          equipment: equipment,
          name: name,
          plannedFor: _plannedFor,
          ownerUid: access.user.uid,
          ownerName: ownerName,
        );
    suivreEcriture(
      messenger: messenger,
      written: created.written,
      succes: access.offline
          ? FormulaireNouveauBrassin.createdOffline
          : FormulaireNouveauBrassin.created,
      refus: FormulaireNouveauBrassin.rejected(name),
    );
    navigator.pop();
    router.go(AppRoutes.brew(created.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final access = ref.watch(grantedAccessProvider);
    final readerUid = access?.user.uid;
    final offline = access?.offline ?? false;
    final equipmentAsync = ref.watch(equipmentListProvider);
    final list = equipmentAsync.value;
    final recipe = widget.recipe;
    final all = [...?list?.valides]..sort(compareEquipment(readerUid));
    final selected = _selected(all, readerUid);
    final mine = recipe.ownerUid == readerUid;
    final unavailable = offline && selected == null && all.isEmpty;
    final emptyFromServer = list != null && all.isEmpty && !offline;
    final loadFailed = list == null && equipmentAsync.hasError;
    final steps = recipe.content.brewSteps;
    final planned = _plannedFor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Nouveau brassin', style: theme.textTheme.titleLarge),
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
        const SizedBox(height: 16),
        KeyedSubtree(
          key: _equipmentKey,
          child: DropdownButtonFormField<String>(
            key: ValueKey('eq-${selected?.id}'),
            initialValue: selected?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Équipement',
              helperText: 'Les calculs du brassin utilisent cet équipement.',
              errorText: _equipmentError,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final e in all)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    e.ownerUid == readerUid
                        ? e.name
                        : '${e.name} (${libelleAuteur(ownerUid: e.ownerUid, ownerName: e.ownerName, readerUid: readerUid)})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => setState(() {
              _equipmentId = id;
              _equipmentTouched = true;
              _equipmentError = null;
            }),
          ),
        ),
        if (loadFailed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Impossible de lire les équipements.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(equipmentListProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        if (list == null && !loadFailed)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: IndicateurBouton(label: 'Lecture des équipements'),
          ),
        if (emptyFromServer)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Aucun équipement. Créez-en un dans Équipements.',
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.go(AppRoutes.equipment);
                  },
                  child: const Text('Ouvrir Équipements'),
                ),
              ],
            ),
          ),
        if (unavailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              FormulaireNouveauBrassin.equipmentOffline,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        Text('Date prévue (facultatif)', style: theme.textTheme.labelLarge),
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
        Text(
          steps.isEmpty
              ? (mine
                    ? 'Cette recette n\'a pas de chronologie : le jour du '
                          'brassage n\'aura aucune étape à suivre.'
                    : 'Seul l\'auteur écrit la chronologie de cette recette. '
                          'Dupliquez-la pour écrire la vôtre.')
              : 'Chronologie : ${formatEtapes(steps.length)} · '
                    '${formatDuree(dureeChronologie(steps))}',
          style: theme.textTheme.bodyMedium,
        ),
        if (steps.isEmpty && mine)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                unawaited(router.push(AppRoutes.editBrewSteps(recipe.id)));
              },
              child: const Text('Écrire la chronologie'),
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: _creating || all.isEmpty
                  ? null
                  : () => unawaited(_create(selected)),
              child: _creating
                  ? const IndicateurBouton(label: 'Création')
                  : const Text('Créer le brassin'),
            ),
          ],
        ),
      ],
    );
  }
}
