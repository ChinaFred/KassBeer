import 'dart:async';

import 'package:brewing/brewing.dart'
    show GravityOutOfRange, GravityRead, GravityUnreadable, readGravity;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/editeur_plein_ecran.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../brews/data/brews_repository.dart';
import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../../recipes/domain/chronologie.dart';

/// Heure future refusée (JB7).
const kHeureFutureRefusee = 'L\'heure ne peut pas être dans le futur.';

/// Fin placée avant le début de l'étape.
const kFinAvantDebut = 'La fin doit suivre le début.';

/// Instant choisi, ou raison du refus.
typedef ChoixHeure = ({DateTime? at, String? erreur});

/// Place l'heure [heure], choisie sans date, au candidat non futur le plus proche
/// de [base], parmi le jour de [base], son lendemain et sa veille (R2).
///
/// La veille n'est candidate que si elle reste après [plancher] (début du
/// brassin) : sans cela, une heure future reculerait d'un jour sans message (JB7).
/// Aucun candidat : heure refusée comme future. [apres] (début d'une étape, pour une
/// fin) : un candidat retenu avant le début est refusé.
ChoixHeure placerHeure({
  required DateTime base,
  required TimeOfDay heure,
  required DateTime now,
  DateTime? apres,
  DateTime? plancher,
}) {
  DateTime jour(int decalage) => DateTime(
    base.year,
    base.month,
    base.day + decalage,
    heure.hour,
    heure.minute,
  );
  final veille = jour(-1);
  final candidats = [
    jour(0),
    jour(1),
    if (plancher != null && !veille.isBefore(plancher)) veille,
  ].where((c) => !c.isAfter(now));
  DateTime? choisi;
  for (final c in candidats) {
    if (choisi == null ||
        c.difference(base).abs() < choisi.difference(base).abs()) {
      choisi = c;
    }
  }
  if (choisi == null) return (at: null, erreur: kHeureFutureRefusee);
  if (apres != null && choisi.isBefore(apres)) {
    return (at: null, erreur: kFinAvantDebut);
  }
  return (at: choisi, erreur: null);
}

/// Sélecteur d'heure sur 24 h, en saisie au clavier.
Future<TimeOfDay?> demanderHeure24(BuildContext context, TimeOfDay initiale) =>
    showTimePicker(
      context: context,
      initialTime: initiale,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

/// Sélecteur d'heure sur 24 h ; rend l'instant choisi au plus proche de [base] ou la
/// raison du refus, `null` si l'utilisateur annule.
Future<ChoixHeure?> demanderHeure(
  BuildContext context, {
  required DateTime base,
  required DateTime now,
  DateTime? apres,
  DateTime? plancher,
}) async {
  final picked = await demanderHeure24(context, TimeOfDay.fromDateTime(base));
  if (picked == null || !context.mounted) return null;
  return placerHeure(
    base: base,
    heure: picked,
    now: now,
    apres: apres,
    plancher: plancher,
  );
}

/// Erreur d'une densité saisie, ou `null` : une faute de frappe n'est pas une erreur
/// à journaliser (D-Q13).
String? erreurDensite(String text) => switch (readGravity(text)) {
  GravityRead() => null,
  GravityUnreadable() => 'Densité illisible. Écrivez 1057,9 ou 1.058.',
  GravityOutOfRange() => 'Densité hors de 980 à 1200.',
};

/// Résultat d'une saisie : mesure ou note.
@immutable
class SaisieMesure {
  const SaisieMesure({
    required this.kind,
    this.type,
    this.value,
    this.stepKey,
    this.note,
    required this.at,
  });

  final BrewEventKind kind;
  final MeasureType? type;
  final double? value;
  final String? stepKey;
  final String? note;
  final DateTime at;
}

/// Bornes de saisie : température 0..110 °C, volume ]0..1000] L, pH 0..14 (ME2).
const _maxTemp = 110.0;
const _maxVolume = 1000.0;
const _maxPh = 14.0;
const _seuilVolume = 200.0;

/// Formulaire de mesure, en feuille : type, valeur, heure, note. Aussi utilisé
/// pour corriger ([correction]) : valeur, note et heure seulement (ME5).
class FormulaireMesure extends StatefulWidget {
  const FormulaireMesure({
    super.key,
    required this.steps,
    required this.initialStepKey,
    required this.initialType,
    required this.now,
    required this.onSubmit,
    this.note = false,
    this.correction,
    this.onDelete,
    this.initialValue,
    this.initialAt,
    this.initialNote,
    this.plancher,
  });

  final List<BrewStepLine> steps;
  final String? initialStepKey;

  /// Type présélectionné ; nul pour une note.
  final MeasureType? initialType;
  final DateTime Function() now;
  final ValueChanged<SaisieMesure> onSubmit;

  /// Ouvre directement la saisie d'une note.
  final bool note;
  final BrewEvent? correction;
  final VoidCallback? onDelete;

  /// Valeur, heure et note reprises d'une saisie refusée (« Saisir à nouveau »).
  final double? initialValue;
  final DateTime? initialAt;
  final String? initialNote;

  /// Début du brassin : une heure saisie peut reculer d'un jour jusque-là.
  final DateTime? plancher;

  @override
  State<FormulaireMesure> createState() => _FormulaireMesureState();
}

class _FormulaireMesureState extends State<FormulaireMesure> {
  final _formKey = GlobalKey<FormState>();
  final _value = TextEditingController();
  final _note = TextEditingController();
  late MeasureType? _type;
  late bool _isNote;
  late String? _stepKey;
  DateTime? _at;
  String? _heureErreur;
  final _valueFocus = FocusNode();
  final _noteFocus = FocusNode();

  BrewEvent? get _edit => widget.correction;

  @override
  void initState() {
    super.initState();
    final edit = _edit;
    _isNote = edit?.kind == BrewEventKind.note || widget.note;
    _type = edit?.measureType ?? widget.initialType;
    _stepKey = edit?.stepKey ?? widget.initialStepKey;
    _at = edit?.measuredAt ?? widget.initialAt;
    final value = edit?.value ?? widget.initialValue;
    if (value != null) {
      _value.text = _type == MeasureType.gravity
          ? formatDensite(value)
          : texteSaisi(value);
    }
    _note.text = edit?.note ?? widget.initialNote ?? '';
  }

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    _valueFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      // Une seule erreur possible selon le mode : la valeur ou la note.
      unawaited(montrerChamp(invalid.first.context));
      (_isNote ? _noteFocus : _valueFocus).requestFocus();
      return;
    }
    final note = _note.text.trim();
    final at = _at ?? widget.now();
    final SaisieMesure result;
    if (_isNote) {
      result = SaisieMesure(
        kind: BrewEventKind.note,
        stepKey: _stepKey,
        note: note,
        at: at,
      );
    } else {
      final type = _type!;
      final double value = switch (readGravity(_value.text)) {
        GravityRead(:final sg) when type == MeasureType.gravity => sg,
        _ => lireNombre(_value.text).valeur!,
      };
      result = SaisieMesure(
        kind: BrewEventKind.measurement,
        type: type,
        value: value,
        stepKey: _stepKey,
        note: note.isEmpty ? null : note,
        at: at,
      );
    }
    Navigator.of(context).pop();
    widget.onSubmit(result);
  }

  Future<void> _changerHeure() async {
    final choix = await demanderHeure(
      context,
      base: _at ?? widget.now(),
      now: widget.now(),
      plancher: widget.plancher,
    );
    if (choix == null || !mounted) return;
    setState(() {
      _heureErreur = choix.erreur;
      if (choix.at != null) _at = choix.at;
    });
  }

  Widget _champValeur() {
    final type = _type!;
    const grand = TextStyle(fontSize: 28);
    final autofocus = _edit == null;
    switch (type) {
      case MeasureType.gravity:
        return ChampDensite(
          controller: _value,
          onSubmit: _submit,
          focusNode: _valueFocus,
          autofocus: autofocus,
        );
      case MeasureType.temperature:
        return ChampNombre(
          controller: _value,
          label: 'Température (°C)',
          obligatoire: true,
          max: _maxTemp,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.done,
          style: grand,
          autofocus: autofocus,
          focusNode: _valueFocus,
        );
      case MeasureType.volume:
        final volume = lireNombre(_value.text).valeur;
        return ChampNombre(
          controller: _value,
          label: 'Volume (L)',
          obligatoire: true,
          minExclu: true,
          max: _maxVolume,
          avertissement: volume != null && volume > _seuilVolume
              ? 'Volume inhabituel : ${formatLitres(volume)}. Vérifiez la saisie.'
              : null,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.done,
          style: grand,
          autofocus: autofocus,
          focusNode: _valueFocus,
        );
      case MeasureType.ph:
        return ChampNombre(
          controller: _value,
          label: 'pH',
          obligatoire: true,
          max: _maxPh,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.done,
          style: grand,
          autofocus: autofocus,
          focusNode: _valueFocus,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final edit = _edit;
    final at = _at;
    final correcting = edit != null;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              correcting
                  ? (_isNote ? 'Corriger la note' : 'Corriger la mesure')
                  : (_isNote ? 'Note' : 'Mesure'),
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          if (!correcting) ...[
            DropdownButtonFormField<String?>(
              initialValue: _stepKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Étape',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sans étape')),
                for (final s in widget.steps)
                  DropdownMenuItem(
                    value: s.key,
                    child: Text(s.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (key) => setState(() => _stepKey = key),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in MeasureType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: !_isNote && _type == type,
                    onSelected: (_) => setState(() {
                      _isNote = false;
                      _type = type;
                      _value.clear();
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Note'),
                  selected: _isNote,
                  onSelected: (_) => setState(() {
                    _isNote = true;
                    _value.clear();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (correcting && !_isNote)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Pour changer de type, supprimez la mesure et saisissez-la '
                'à nouveau.',
              ),
            ),
          if (!_isNote && _type != null) _champValeur(),
          if (!_isNote && _type != null) const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            focusNode: _noteFocus,
            autofocus: _isNote && !correcting,
            maxLength: kEventNoteMaxLength,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _isNote ? 'Note' : 'Note (facultatif)',
              border: const OutlineInputBorder(),
            ),
            validator: (v) => _isNote && (v ?? '').trim().isEmpty
                ? 'Écrivez une note.'
                : null,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  at == null
                      ? 'Heure : maintenant'
                      : 'Heure : ${formatHeure(at)}',
                ),
              ),
              TextButton(
                onPressed: () => unawaited(_changerHeure()),
                child: const Text('Changer l\'heure'),
              ),
            ],
          ),
          if (_heureErreur != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _heureErreur!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
            ),
            onPressed: _submit,
            child: Text(
              correcting
                  ? 'Enregistrer'
                  : (_isNote ? 'Enregistrer la note' : 'Enregistrer la mesure'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onDelete!();
              },
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(
                _isNote ? 'Supprimer la note' : 'Supprimer la mesure',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Champ de saisie d'une densité, avec son aperçu : « = 1057,9 ».
class ChampDensite extends StatefulWidget {
  const ChampDensite({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.focusNode,
    required this.autofocus,
    this.label = 'Densité',
    this.textInputAction = TextInputAction.done,
    this.obligatoire = true,
    this.grand = true,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final FocusNode focusNode;
  final bool autofocus;
  final String label;
  final TextInputAction textInputAction;

  /// Faux : un champ vide est accepté (densité finale de l'embouteillage).
  final bool obligatoire;

  /// Chiffres en grand (28 sp), pour une saisie à côté de la cuve.
  final bool grand;

  @override
  State<ChampDensite> createState() => _ChampDensiteState();
}

class _ChampDensiteState extends State<ChampDensite> {
  @override
  Widget build(BuildContext context) {
    final preview = switch (readGravity(widget.controller.text)) {
      GravityRead(:final sg) => '= ${formatDensite(sg)}',
      _ => null,
    };
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: widget.textInputAction,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: widget.grand ? const TextStyle(fontSize: 28) : null,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: preview ?? '1057,9 ou 1.058',
        border: const OutlineInputBorder(),
      ),
      validator: (text) {
        final value = text ?? '';
        if (!widget.obligatoire && value.trim().isEmpty) return null;
        return erreurDensite(value);
      },
      onChanged: (_) => setState(() {}),
      onFieldSubmitted: (_) => widget.onSubmit(),
    );
  }
}

/// Correction d'une saisie depuis la feuille : le résultat est écrit par le dépôt.
/// Une suppression propose « Annuler » : réécrit le même identifiant (ME6).
void ouvrirCorrection({
  required BuildContext context,
  required WidgetRef ref,
  required Brew brew,
  required BrewEvent event,
  required void Function(Future<void> written, String libelle) suivre,
}) {
  final repo = ref.read(brewsRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  unawaited(
    showFeuilleOuDialogue<void>(
      context: context,
      fermetureProtegee: true,
      builder: (_) => FormulaireMesure(
        steps: const [],
        plancher: brew.brewedAt,
        initialStepKey: null,
        initialType: event.measureType,
        now: ref.read(horlogeProvider),
        correction: event,
        onSubmit: (saisie) => suivre(
          repo.correct(
            brewId: brew.id,
            eventId: event.id,
            value: saisie.value,
            note: saisie.note,
            measuredAt: saisie.at,
          ),
          'Correction',
        ),
        onDelete: () {
          suivre(
            repo.deleteEvent(brewId: brew.id, eventId: event.id),
            'Suppression',
          );
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 10),
              persist: false,
              content: const Text('Saisie supprimée.'),
              action: SnackBarAction(
                label: 'Annuler',
                onPressed: () => suivre(
                  repo.restoreEvent(brewId: brew.id, event: event),
                  'Annulation',
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Ajoute une mesure, feuille fermée aussitôt, avec « Annuler » pendant 10 s.
void enregistrerSaisie({
  required WidgetRef ref,
  required ScaffoldMessengerState messenger,
  required Brew brew,
  required SaisieMesure saisie,
  required void Function(Future<void> written, String libelle) suivre,
}) {
  final repo = ref.read(brewsRepositoryProvider);
  final created = repo.addEvent(
    brewId: brew.id,
    input: BrewEventInput(
      ownerUid: brew.ownerUid,
      kind: saisie.kind,
      stepKey: saisie.stepKey,
      measureType: saisie.type,
      value: saisie.value,
      note: saisie.note,
      measuredAt: saisie.at,
    ),
  );
  final type = saisie.type;
  final value = saisie.value;
  suivre(
    created.written,
    saisie.kind == BrewEventKind.note
        ? 'Note à ${formatHeure(saisie.at)}'
        : '${type!.label} ${libelleMesure(type, value!)} à ${formatHeure(saisie.at)}',
  );
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 10),
      persist: false,
      content: Text(
        saisie.kind == BrewEventKind.note
            ? 'Note enregistrée.'
            : 'Mesure enregistrée.',
      ),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => suivre(
          repo.deleteEvent(brewId: brew.id, eventId: created.id),
          'Annulation',
        ),
      ),
    ),
  );
}
