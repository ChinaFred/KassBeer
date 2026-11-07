import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/formats.dart';
import '../domain/recipe.dart';

/// Formulaires d'une ligne de recette, ouverts en feuille du bas ou en dialogue
/// (`showFeuilleOuDialogue`). « Ajouter » ajoute la ligne et ferme ; « Ajouter et
/// continuer » l'ajoute, vide le formulaire et remet le curseur sur « Nom » ;
/// « Enregistrer » remplace une ligne existante.

/// Nom refusé par `ingredientKey` (K3).
const kNameWithoutLetter = 'Le nom doit contenir une lettre ou un chiffre.';

/// Erreur du nom d'un ingrédient, ou `null`.
///
/// La règle K3 est celle de `brewing/` (`isValidIngredientName`, la même que
/// `ingredientKey`) : une faute de saisie n'est ni une exception ni un rapport.
String? erreurNomIngredient(String text) {
  if (text.trim().isEmpty) return ErreursNombre.obligatoire;
  return isValidIngredientName(text) ? null : kNameWithoutLetter;
}

/// « Quantité inhabituelle : 22 400 g. Vérifiez la saisie. » (U6).
String quantiteInhabituelle(String quantite) =>
    'Quantité inhabituelle : $quantite. Vérifiez la saisie.';

/// Avertissement d'une masse saisie [text] dans [unitGrams] grammes par unité,
/// au-delà de [thresholdGrams].
String? _warnMass(
  String text,
  double thresholdGrams, {
  required bool kilograms,
}) {
  final value = lireNombre(text).valeur;
  if (value == null) return null;
  final grams = kilograms ? value * 1000 : value;
  if (grams <= thresholdGrams) return null;
  return quantiteInhabituelle(
    kilograms ? formatKilogrammes(grams) : formatGrammes(grams),
  );
}

/// Boutons et cadre communs des formulaires de ligne.
class _Cadre extends StatelessWidget {
  const _Cadre({
    required this.title,
    required this.editing,
    required this.canContinue,
    required this.onSubmit,
    required this.children,
    this.lastAdded,
  });

  final String title;
  final bool editing;
  final bool canContinue;
  final void Function({required bool continuer}) onSubmit;
  final List<Widget> children;

  /// Annonce de la dernière ligne ajoutée par « Ajouter et continuer ».
  final String? lastAdded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final added = lastAdded;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        if (added != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(added, style: theme.textTheme.bodyMedium),
            ),
          ),
        const SizedBox(height: 16),
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          child,
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            if (!editing && canContinue)
              OutlinedButton(
                onPressed: () => onSubmit(continuer: true),
                child: const Text('Ajouter et continuer'),
              ),
            FilledButton(
              onPressed: () => onSubmit(continuer: false),
              child: Text(editing ? 'Enregistrer' : 'Ajouter'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Choix obligatoire par boutons segmentés, avec son message d'erreur.
class _Choix<T> extends StatelessWidget {
  const _Choix({
    required this.label,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.error,
  });

  final String label;
  final List<T> values;
  final String Function(T) labelOf;
  final T? selected;
  final ValueChanged<T?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final err = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<T>(
          emptySelectionAllowed: true,
          segments: [
            for (final v in values)
              ButtonSegment(value: v, label: Text(labelOf(v))),
          ],
          selected: {?selected},
          onSelectionChanged: (s) => onChanged(s.isEmpty ? null : s.single),
        ),
        if (err != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              err,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// Logique commune : formulaire, champ « Nom », ajout et continuation.
mixin _FormulaireLigne<W extends ConsumerStatefulWidget, T>
    on ConsumerState<W> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final nameFocus = FocusNode();
  String? lastAdded;

  /// Lignes encore possibles avant le plafond (I7), celle-ci comprise.
  int get remaining;
  bool get editing;
  void submitLine(T line);

  /// Vérifie les choix obligatoires hors des champs de texte (forme d'un
  /// houblon) et affiche leur erreur ; vrai s'ils sont faits.
  bool validateChoices() => true;

  /// Ligne lue des champs, appelée une fois le formulaire validé.
  T readLine();
  void clearFields();

  int _added = 0;

  bool get canContinue => remaining - _added > 1;

  void submit({required bool continuer}) {
    final fieldsValid = formKey.currentState!.validate();
    final choicesValid = validateChoices();
    if (!fieldsValid || !choicesValid) return;
    final line = readLine();
    submitLine(line);
    if (!continuer) {
      Navigator.of(context).pop();
      return;
    }
    _added++;
    setState(() {
      lastAdded = '« ${name.text.trim()} » ajouté.';
      formKey.currentState!.reset();
      name.clear();
      clearFields();
    });
    nameFocus.requestFocus();
  }

  /// Champ « Nom » ; [ingredient] faux pour un palier (aucune clé d'ingrédient).
  Widget nameField({bool ingredient = true}) => TextFormField(
    controller: name,
    focusNode: nameFocus,
    autofocus: true,
    maxLength: kIngredientNameMaxLength,
    textCapitalization: TextCapitalization.sentences,
    textInputAction: TextInputAction.next,
    decoration: const InputDecoration(
      labelText: 'Nom',
      border: OutlineInputBorder(),
    ),
    validator: (v) => ingredient
        ? erreurNomIngredient(v ?? '')
        : ((v ?? '').trim().isEmpty ? ErreursNombre.obligatoire : null),
  );

  @override
  void dispose() {
    name.dispose();
    nameFocus.dispose();
    super.dispose();
  }
}

/// Formulaire d'un malt ou d'un sucre (I1). Quantité saisie en kilogrammes.
class FormulaireFermentescible extends ConsumerStatefulWidget {
  const FormulaireFermentescible({
    super.key,
    this.initial,
    required this.remaining,
    required this.onSubmit,
  });

  final FermentableLine? initial;
  final int remaining;
  final ValueChanged<FermentableLine> onSubmit;

  @override
  ConsumerState<FormulaireFermentescible> createState() =>
      _FormulaireFermentescibleState();
}

class _FormulaireFermentescibleState
    extends ConsumerState<FormulaireFermentescible>
    with _FormulaireLigne<FormulaireFermentescible, FermentableLine> {
  final _mass = TextEditingController();
  final _ebc = TextEditingController();
  final _yield = TextEditingController();
  FermentableKind _kind = FermentableKind.malt;

  @override
  int get remaining => widget.remaining;
  @override
  bool get editing => widget.initial != null;
  @override
  void submitLine(FermentableLine line) => widget.onSubmit(line);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      name.text = i.name;
      _kind = i.kind;
      _mass.text = texteSaisi(i.weightG / 1000);
      _ebc.text = texteSaisi(i.ebc);
      _yield.text = texteSaisi(i.yieldPct);
    }
  }

  @override
  void dispose() {
    _mass.dispose();
    _ebc.dispose();
    _yield.dispose();
    super.dispose();
  }

  @override
  FermentableLine readLine() => FermentableLine(
    name: name.text.trim(),
    kind: _kind,
    weightG: lireNombre(_mass.text).valeur! * 1000,
    ebc: lireNombre(_ebc.text).valeur,
    yieldPct: lireNombre(_yield.text).valeur,
  );

  @override
  void clearFields() {
    _mass.clear();
    _ebc.clear();
    _yield.clear();
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return Form(
      key: formKey,
      child: _Cadre(
        title: initial == null
            ? 'Ajouter un malt ou un sucre'
            : 'Modifier « ${initial.name} »',
        editing: editing,
        canContinue: canContinue,
        onSubmit: submit,
        lastAdded: lastAdded,
        children: [
          nameField(),
          _Choix<FermentableKind>(
            label: 'Nature',
            values: FermentableKind.values,
            labelOf: (k) => switch (k) {
              FermentableKind.malt => 'Malt',
              FermentableKind.sugar => 'Sucre',
            },
            selected: _kind,
            onChanged: (k) => setState(() => _kind = k ?? _kind),
          ),
          ChampNombre(
            controller: _mass,
            label: 'Quantité (kg)',
            obligatoire: true,
            minExclu: true,
            avertissement: _warnMass(
              _mass.text,
              kUnusualFermentableGrams,
              kilograms: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          ChampNombre(
            controller: _ebc,
            label: 'Couleur (EBC)',
            aide: 'Sert au calcul de la couleur.',
          ),
          ChampNombre(
            controller: _yield,
            label: 'Rendement d\'extrait (%)',
            aide: 'Sert au calcul de la densité initiale.',
            max: 100,
            textInputAction: TextInputAction.done,
            onSubmitted: kIsWeb ? (_) => submit(continuer: false) : null,
          ),
        ],
      ),
    );
  }
}

/// Formulaire d'un houblon (I2). Quantité en grammes ; à cru, durée en jours.
class FormulaireHoublon extends ConsumerStatefulWidget {
  const FormulaireHoublon({
    super.key,
    this.initial,
    required this.remaining,
    required this.recipeBoilMin,
    required this.onSubmit,
  });

  final HopLine? initial;
  final int remaining;

  /// Durée d'ébullition de la recette, pour l'avertissement U6.
  final double? recipeBoilMin;
  final ValueChanged<HopLine> onSubmit;

  @override
  ConsumerState<FormulaireHoublon> createState() => _FormulaireHoublonState();
}

class _FormulaireHoublonState extends ConsumerState<FormulaireHoublon>
    with _FormulaireLigne<FormulaireHoublon, HopLine> {
  final _mass = TextEditingController();
  final _alpha = TextEditingController();
  final _time = TextEditingController();
  HopUse _use = HopUse.boil;
  HopForm? _form;
  bool _formError = false;

  static const formMissing = 'Choisissez une forme.';

  @override
  int get remaining => widget.remaining;
  @override
  bool get editing => widget.initial != null;
  @override
  void submitLine(HopLine line) => widget.onSubmit(line);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      name.text = i.name;
      _mass.text = texteSaisi(i.weightG);
      _alpha.text = texteSaisi(i.alphaPct);
      _use = i.use;
      _form = i.form;
      final t = i.timeMin;
      _time.text = texteSaisi(
        t == null || i.use != HopUse.dryHop ? t : t / minutesParJour,
      );
    }
  }

  @override
  void dispose() {
    _mass.dispose();
    _alpha.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  bool validateChoices() {
    setState(() => _formError = _form == null);
    return _form != null;
  }

  @override
  HopLine readLine() {
    final form = _form!;
    final time = lireNombre(_time.text).valeur;
    return HopLine(
      name: name.text.trim(),
      weightG: lireNombre(_mass.text).valeur!,
      alphaPct: lireNombre(_alpha.text).valeur,
      use: _use,
      form: form,
      timeMin: time == null || _use != HopUse.dryHop
          ? time
          : time * minutesParJour,
    );
  }

  @override
  void clearFields() {
    _mass.clear();
    _alpha.clear();
    _time.clear();
    _form = null;
    _formError = false;
  }

  String? get _boilWarning {
    final boil = widget.recipeBoilMin;
    final time = lireNombre(_time.text).valeur;
    if (_use != HopUse.boil || boil == null || time == null || time <= boil) {
      return null;
    }
    return 'Plus long que l\'ébullition de la recette '
        '(${formatMinutes(boil)}).';
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return Form(
      key: formKey,
      child: _Cadre(
        title: initial == null
            ? 'Ajouter un houblon'
            : 'Modifier « ${initial.name} »',
        editing: editing,
        canContinue: canContinue,
        onSubmit: submit,
        lastAdded: lastAdded,
        children: [
          nameField(),
          ChampNombre(
            controller: _mass,
            label: 'Quantité (g)',
            obligatoire: true,
            minExclu: true,
            avertissement: _warnMass(
              _mass.text,
              kUnusualHopGrams,
              kilograms: false,
            ),
            onChanged: (_) => setState(() {}),
          ),
          ChampNombre(controller: _alpha, label: 'Acides alpha (%)', max: 100),
          _Choix<HopUse>(
            label: 'Utilisation',
            values: HopUse.values,
            labelOf: libelleUtilisationHoublon,
            selected: _use,
            onChanged: (u) => setState(() {
              final next = u ?? _use;
              // Une durée à cru se saisit en jours, les autres en minutes : 60 min
              // ne deviennent pas 60 jours.
              if ((next == HopUse.dryHop) != (_use == HopUse.dryHop)) {
                _time.clear();
              }
              _use = next;
            }),
          ),
          ChampNombre(
            key: ValueKey(_use),
            controller: _time,
            label: switch (_use) {
              HopUse.boil => 'Durée d\'ébullition (min)',
              HopUse.afterBoil => 'Durée (min)',
              HopUse.dryHop => 'Durée à cru (jours)',
            },
            obligatoire: _use == HopUse.boil,
            max: _use == HopUse.dryHop ? null : 600,
            avertissement: _boilWarning,
            onChanged: (_) => setState(() {}),
          ),
          _Choix<HopForm>(
            label: 'Forme',
            values: const [HopForm.pellet, HopForm.whole],
            labelOf: libelleFormeHoublon,
            selected: _form,
            error: _formError ? formMissing : null,
            onChanged: (f) => setState(() {
              _form = f;
              _formError = false;
            }),
          ),
        ],
      ),
    );
  }
}

/// « Ébullition », « Whirlpool », « À cru ».
String libelleUtilisationHoublon(HopUse use) => switch (use) {
  HopUse.boil => 'Ébullition',
  HopUse.afterBoil => 'Whirlpool',
  HopUse.dryHop => 'À cru',
};

/// « Pellets », « Cônes ».
String libelleFormeHoublon(HopForm form) => switch (form) {
  HopForm.pellet => 'Pellets',
  HopForm.whole => 'Cônes',
};

/// Formulaire d'un autre ajout (I3) : aucun calcul.
class FormulaireAjout extends ConsumerStatefulWidget {
  const FormulaireAjout({
    super.key,
    this.initial,
    required this.remaining,
    required this.onSubmit,
  });

  final OtherLine? initial;
  final int remaining;
  final ValueChanged<OtherLine> onSubmit;

  @override
  ConsumerState<FormulaireAjout> createState() => _FormulaireAjoutState();
}

class _FormulaireAjoutState extends ConsumerState<FormulaireAjout>
    with _FormulaireLigne<FormulaireAjout, OtherLine> {
  final _mass = TextEditingController();
  final _time = TextEditingController();
  OtherUse? _use;

  @override
  int get remaining => widget.remaining;
  @override
  bool get editing => widget.initial != null;
  @override
  void submitLine(OtherLine line) => widget.onSubmit(line);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      name.text = i.name;
      _mass.text = texteSaisi(i.weightG);
      _time.text = texteSaisi(i.timeMin);
      _use = i.use;
    }
  }

  @override
  void dispose() {
    _mass.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  OtherLine readLine() => OtherLine(
    name: name.text.trim(),
    weightG: lireNombre(_mass.text).valeur!,
    use: _use,
    timeMin: lireNombre(_time.text).valeur,
  );

  @override
  void clearFields() {
    _mass.clear();
    _time.clear();
    _use = null;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return Form(
      key: formKey,
      child: _Cadre(
        title: initial == null
            ? 'Ajouter un ajout'
            : 'Modifier « ${initial.name} »',
        editing: editing,
        canContinue: canContinue,
        onSubmit: submit,
        lastAdded: lastAdded,
        children: [
          nameField(),
          ChampNombre(
            controller: _mass,
            label: 'Quantité (g)',
            obligatoire: true,
            minExclu: true,
            avertissement: _warnMass(
              _mass.text,
              kUnusualOtherGrams,
              kilograms: false,
            ),
            onChanged: (_) => setState(() {}),
          ),
          DropdownButtonFormField<OtherUse?>(
            initialValue: _use,
            decoration: const InputDecoration(
              labelText: 'Utilisation',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Non précisée')),
              for (final u in OtherUse.values)
                DropdownMenuItem(value: u, child: Text(u.label)),
            ],
            onChanged: (u) => setState(() => _use = u),
          ),
          ChampNombre(
            controller: _time,
            label: 'Durée (min)',
            textInputAction: TextInputAction.done,
            onSubmitted: kIsWeb ? (_) => submit(continuer: false) : null,
          ),
        ],
      ),
    );
  }
}

/// Formulaire de la levure (I4) : une seule par recette, pas de continuation.
class FormulaireLevure extends ConsumerStatefulWidget {
  const FormulaireLevure({super.key, this.initial, required this.onSubmit});

  final YeastLine? initial;
  final ValueChanged<YeastLine> onSubmit;

  @override
  ConsumerState<FormulaireLevure> createState() => _FormulaireLevureState();
}

class _FormulaireLevureState extends ConsumerState<FormulaireLevure>
    with _FormulaireLigne<FormulaireLevure, YeastLine> {
  final _attenuation = TextEditingController();
  YeastForm? _form;

  @override
  int get remaining => 1;
  @override
  bool get editing => widget.initial != null;
  @override
  void submitLine(YeastLine line) => widget.onSubmit(line);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      name.text = i.name;
      _attenuation.text = texteSaisi(i.attenuationPct);
      _form = i.form;
    }
  }

  @override
  void dispose() {
    _attenuation.dispose();
    super.dispose();
  }

  @override
  YeastLine readLine() => YeastLine(
    name: name.text.trim(),
    attenuationPct: lireNombre(_attenuation.text).valeur,
    form: _form,
  );

  @override
  void clearFields() {
    _attenuation.clear();
    _form = null;
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return Form(
      key: formKey,
      child: _Cadre(
        title: initial == null
            ? 'Ajouter une levure'
            : 'Modifier « ${initial.name} »',
        editing: editing,
        canContinue: false,
        onSubmit: submit,
        children: [
          nameField(),
          ChampNombre(
            controller: _attenuation,
            label: 'Atténuation (%)',
            aide: 'Sert au calcul de la densité finale.',
            max: 100,
          ),
          _Choix<YeastForm>(
            label: 'Forme',
            values: YeastForm.values,
            labelOf: (f) => f.label,
            selected: _form,
            onChanged: (f) => setState(() => _form = f),
          ),
        ],
      ),
    );
  }
}

/// Formulaire d'un palier d'empâtage (I5).
class FormulairePalier extends ConsumerStatefulWidget {
  const FormulairePalier({
    super.key,
    this.initial,
    required this.remaining,
    required this.onSubmit,
  });

  final MashStep? initial;
  final int remaining;
  final ValueChanged<MashStep> onSubmit;

  @override
  ConsumerState<FormulairePalier> createState() => _FormulairePalierState();
}

class _FormulairePalierState extends ConsumerState<FormulairePalier>
    with _FormulaireLigne<FormulairePalier, MashStep> {
  final _temp = TextEditingController();
  final _duration = TextEditingController();

  @override
  int get remaining => widget.remaining;
  @override
  bool get editing => widget.initial != null;
  @override
  void submitLine(MashStep line) => widget.onSubmit(line);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      name.text = i.name;
      _temp.text = texteSaisi(i.tempC);
      _duration.text = texteSaisi(i.durationMin);
    }
  }

  @override
  void dispose() {
    _temp.dispose();
    _duration.dispose();
    super.dispose();
  }

  @override
  MashStep readLine() => MashStep(
    name: name.text.trim(),
    tempC: lireNombre(_temp.text).valeur!,
    durationMin: lireNombre(_duration.text).valeur!,
  );

  @override
  void clearFields() {
    _temp.clear();
    _duration.clear();
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return Form(
      key: formKey,
      child: _Cadre(
        title: initial == null
            ? 'Ajouter un palier'
            : 'Modifier « ${initial.name} »',
        editing: editing,
        canContinue: canContinue,
        onSubmit: submit,
        lastAdded: lastAdded,
        children: [
          nameField(ingredient: false),
          ChampNombre(
            controller: _temp,
            label: 'Température (°C)',
            obligatoire: true,
            max: 100,
          ),
          ChampNombre(
            controller: _duration,
            label: 'Durée (min)',
            obligatoire: true,
            max: 600,
            textInputAction: TextInputAction.done,
            onSubmitted: kIsWeb ? (_) => submit(continuer: false) : null,
          ),
        ],
      ),
    );
  }
}
