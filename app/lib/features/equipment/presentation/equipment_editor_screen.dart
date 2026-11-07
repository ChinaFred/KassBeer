import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/equipment.dart';
import 'equipment_detail_screen.dart';
import 'equipment_providers.dart';

/// Nouvel équipement ([id] nul) ou modification d'un équipement, en plein écran.
class EquipmentEditorScreen extends ConsumerWidget {
  const EquipmentEditorScreen({super.key, this.id});

  final String? id;

  static const readOnlyMessage = 'Seul l\'auteur modifie cet équipement.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = this.id;
    if (id == null) return const _EquipmentForm(initial: null);
    final access = ref.watch(grantedAccessProvider);
    final listAsync = ref.watch(equipmentListProvider);
    return PageDocument<Equipment>(
      async: listAsync,
      id: id,
      offline: access?.offline ?? false,
      textes: textesEquipement,
      onRetry: () => ref.invalidate(equipmentListProvider),
      onBack: () => context.go(AppRoutes.equipment),
      frame: (state) => EditeurPleinEcran(
        titre: 'Modifier l\x27équipement',
        closePath: AppRoutes.equipment,
        body: state,
      ),
      builder: (context, equipment) {
        if (equipment.ownerUid != access?.user.uid) {
          return EditeurPleinEcran(
            titre: 'Modifier l\'équipement',
            closePath: AppRoutes.equipmentItem(id),
            body: EtatVide(
              icon: Icons.lock_outline,
              message: readOnlyMessage,
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.equipmentItem(id)),
                child: const Text('Voir l\'équipement'),
              ),
            ),
          );
        }
        return _EquipmentForm(key: ValueKey(id), initial: equipment);
      },
    );
  }
}

class _EquipmentForm extends ConsumerStatefulWidget {
  const _EquipmentForm({super.key, required this.initial});

  final Equipment? initial;

  @override
  ConsumerState<_EquipmentForm> createState() => _EquipmentFormState();
}

class _EquipmentFormState extends ConsumerState<_EquipmentForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameField = GlobalKey<FormFieldState<String>>();
  final _kindKey = GlobalKey();
  final _nameFocus = FocusNode();
  late final TextEditingController _name;
  late final TextEditingController _efficiency;
  late final TextEditingController _boilOff;
  late final TextEditingController _absorption;
  late final TextEditingController _mashTun;
  late final TextEditingController _kettle;
  late final TextEditingController _mashTunDead;
  late final TextEditingController _kettleDead;
  late final TextEditingController _trub;
  late final TextEditingController _fermenter;
  late final TextEditingController _notes;
  EquipmentKind? _kind;
  bool _kindError = false;
  bool _dirty = false;
  bool _saving = false;

  static const nameMissing = 'Donnez un nom à l\'équipement.';
  static const kindMissing = 'Choisissez un type.';

  @override
  void initState() {
    super.initState();
    final c = widget.initial?.content;
    TextEditingController number(double? v) =>
        TextEditingController(text: texteSaisi(v));
    _name = TextEditingController(text: c?.name ?? '');
    _efficiency = number(c?.mashEfficiencyPct);
    _boilOff = number(c?.boilOffLPerH);
    _absorption = number(c?.grainAbsorptionLPerKg);
    _mashTun = number(c?.mashTunVolumeL);
    _kettle = number(c?.kettleVolumeL);
    _mashTunDead = number(c?.mashTunDeadSpaceL);
    _kettleDead = number(c?.kettleDeadSpaceL);
    _trub = number(c?.trubLossL);
    _fermenter = number(c?.fermenterLossL);
    _notes = TextEditingController(text: c?.notes ?? '');
    _kind = c?.kind;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _efficiency,
      _boilOff,
      _absorption,
      _mashTun,
      _kettle,
      _mashTunDead,
      _kettleDead,
      _trub,
      _fermenter,
      _notes,
    ]) {
      c.dispose();
    }
    _nameFocus.dispose();
    super.dispose();
  }

  void _changed([Object? _]) {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    // Tous les champs sont construits (colonne défilante, pas de ListView) : un
    // champ hors écran est validé aussi.
    final invalid = _formKey.currentState!.validateGranularly();
    final kind = _kind;
    setState(() => _kindError = kind == null);
    if (invalid.isNotEmpty) {
      final first = invalid.first;
      await montrerChamp(first.context);
      if (first == _nameField.currentState) _nameFocus.requestFocus();
      return;
    }
    if (kind == null) {
      await montrerChamp(_kindKey.currentContext);
      return;
    }
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    double? n(TextEditingController c) => lireNombre(c.text).valeur;
    final allInOne = kind == EquipmentKind.allInOne;
    final content = EquipmentContent(
      name: _name.text.trim(),
      kind: kind,
      mashEfficiencyPct: n(_efficiency),
      boilOffLPerH: n(_boilOff),
      grainAbsorptionLPerKg: n(_absorption),
      mashTunVolumeL: n(_mashTun),
      kettleVolumeL: allInOne ? null : n(_kettle),
      mashTunDeadSpaceL: n(_mashTunDead),
      kettleDeadSpaceL: allInOne ? null : n(_kettleDead),
      trubLossL: n(_trub),
      fermenterLossL: n(_fermenter),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    // Nom du jeton, celui que comparent les règles ; nul s'il n'y en a pas ou si
    // le jeton ne peut pas être lu (déjà rapporté).
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    if (!mounted) return;
    final repository = ref.read(equipmentRepositoryProvider);
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
          ? 'Équipement enregistré sur l\'appareil. Il partira au retour du '
                'réseau.'
          : 'Équipement enregistré.',
      refus: 'L\'enregistrement de « ${content.name} » a échoué.',
    );
    setState(() {
      _saving = false;
      _dirty = false;
    });
    context.go(AppRoutes.equipmentItem(id));
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    final allInOne = _kind == EquipmentKind.allInOne;
    final theme = Theme.of(context);
    const gap = SizedBox(height: 16);
    Widget number(
      TextEditingController c,
      String label, {
      String? help,
      double? max,
      bool positive = false,
    }) => ChampNombre(
      controller: c,
      label: label,
      aide: help,
      max: max,
      minExclu: positive,
      onChanged: _changed,
    );
    return EditeurPleinEcran(
      titre: initial == null ? 'Nouvel équipement' : 'Modifier l\'équipement',
      closePath: initial == null
          ? AppRoutes.equipment
          : AppRoutes.equipmentItem(initial.id),
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      abandonMessage:
          'Les changements de cet équipement ne seront pas enregistrés.',
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kDialogMaxWidth),
            // Colonne défilante et non ListView : chaque champ reste construit,
            // donc validé, même hors écran.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: _nameField,
                    controller: _name,
                    focusNode: _nameFocus,
                    autofocus: initial == null,
                    maxLength: kEquipmentNameMaxLength,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nom de l\'équipement',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? nameMissing : null,
                    onChanged: _changed,
                  ),
                  gap,
                  Text(
                    'Type',
                    key: _kindKey,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<EquipmentKind>(
                    emptySelectionAllowed: true,
                    segments: [
                      for (final k in EquipmentKind.values)
                        ButtonSegment(value: k, label: Text(k.label)),
                    ],
                    selected: {?_kind},
                    onSelectionChanged: (s) => setState(() {
                      _kind = s.isEmpty ? _kind : s.single;
                      _kindError = false;
                      _dirty = true;
                    }),
                  ),
                  if (_kindError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        kindMissing,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  gap,
                  number(
                    _efficiency,
                    'Rendement d\'empâtage (%)',
                    help: 'Sert au calcul de la densité initiale des recettes.',
                    max: 100,
                  ),
                  gap,
                  number(_boilOff, 'Évaporation (L/h)'),
                  gap,
                  number(_absorption, 'Absorption du grain (L/kg)'),
                  gap,
                  number(
                    _mashTun,
                    allInOne
                        ? 'Volume de la cuve (L)'
                        : 'Volume de la cuve d\'empâtage (L)',
                    positive: true,
                  ),
                  if (!allInOne) ...[
                    gap,
                    number(
                      _kettle,
                      'Volume de la cuve d\'ébullition (L)',
                      positive: true,
                    ),
                  ],
                  gap,
                  number(
                    _mashTunDead,
                    allInOne
                        ? 'Volume mort de la cuve (L)'
                        : 'Volume mort de la cuve d\'empâtage (L)',
                  ),
                  if (!allInOne) ...[
                    gap,
                    number(
                      _kettleDead,
                      'Volume mort de la cuve d\'ébullition (L)',
                    ),
                  ],
                  gap,
                  number(_trub, 'Pertes au trub (L)'),
                  gap,
                  number(_fermenter, 'Pertes au fermenteur (L)'),
                  gap,
                  TextFormField(
                    controller: _notes,
                    maxLength: kEquipmentNotesMaxLength,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Notes (facultatif)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _changed,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
