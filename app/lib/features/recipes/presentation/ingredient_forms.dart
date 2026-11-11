import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/segments.dart';
import '../../library/domain/referentiel.dart';
import '../../library/presentation/champ_bibliotheque.dart';
import '../domain/beerjson.dart';
import '../domain/chronologie.dart';
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

/// Unité de saisie de la quantité d'un ajout, d'un houblon extrait ou d'une
/// levure (décision du 2026-11-10) : grammes ou millilitres, enregistrés en
/// grammes ou en litres.
enum UniteSaisie {
  grammes('g', 'grammes'),
  millilitres('ml', 'millilitres');

  const UniteSaisie(this.label, this.parle);

  /// Libellé court du segment et du champ.
  final String label;

  /// Libellé lu par un lecteur d'écran.
  final String parle;
}

/// Mention d'un houblon mesuré en volume, seul terme de la fiche, du calcul et
/// de l'éditeur ; [kHoublonEnVolumePhrase] en début de phrase.
const kHoublonEnVolume = 'non compté dans l\'amertume (mesuré en volume)';

/// [kHoublonEnVolume] avec sa majuscule de début de phrase.
final String kHoublonEnVolumePhrase =
    kHoublonEnVolume[0].toUpperCase() + kHoublonEnVolume.substring(1);

/// Texte du champ de quantité pour [q], dans son unité de saisie.
String texteQuantite(Quantite? q) {
  if (q == null) return '';
  // Arrondi au millième de millilitre : 0,005 L × 1 000 ne donne pas toujours 5.
  return texteSaisi(
    q.enLitres ? (q.valeur * 1000000).round() / 1000 : q.valeur,
  );
}

/// Unité de saisie de [q] : millilitres pour un volume.
UniteSaisie uniteDe(Quantite? q) =>
    q != null && q.enLitres ? UniteSaisie.millilitres : UniteSaisie.grammes;

/// Quantité lue du texte [text] saisi en [unite], ou `null` s'il est vide.
Quantite? lireQuantite(String text, UniteSaisie unite) {
  final value = lireNombre(text).valeur;
  if (value == null) return null;
  return unite == UniteSaisie.millilitres
      ? Quantite.litres(value / 1000)
      : Quantite.grammes(value);
}

/// Avertissement d'une quantité saisie [text] en [unite] : au-delà de
/// [thresholdGrams] grammes, ou de [kUnusualLineLitres] litres.
String? _warnQuantite(String text, UniteSaisie unite, double thresholdGrams) {
  final q = lireQuantite(text, unite);
  if (q == null) return null;
  if (q.enLitres) {
    return q.valeur > kUnusualLineLitres
        ? quantiteInhabituelle(formatVolumeLigne(q.valeur))
        : null;
  }
  return q.valeur > thresholdGrams
      ? quantiteInhabituelle(formatGrammes(q.valeur))
      : null;
}

/// Avertissement d'une masse saisie [text] en kilogrammes, au-delà de
/// [thresholdGrams] grammes.
String? _warnKilograms(String text, double thresholdGrams) {
  final value = lireNombre(text).valeur;
  if (value == null) return null;
  final grams = value * 1000;
  if (grams <= thresholdGrams) return null;
  return quantiteInhabituelle(formatKilogrammes(grams));
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

/// Choix par boutons segmentés, avec son message d'erreur ou son avertissement
/// (non bloquant, couleur `tertiary`). Les segments passent l'un sous l'autre
/// quand leurs libellés ne tiennent pas sur la largeur, à l'échelle de texte
/// courante.
class _Choix<T> extends StatelessWidget {
  const _Choix({
    required this.label,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.semanticsOf,
    this.error,
    this.avertissement,
  });

  final String label;
  final List<T> values;
  final String Function(T) labelOf;

  /// Libellé lu par un lecteur d'écran, s'il diffère du libellé affiché.
  final String Function(T)? semanticsOf;
  final T? selected;
  final ValueChanged<T?> onChanged;
  final String? error;
  final String? avertissement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final err = error;
    final warn = avertissement;
    Widget message(String text, Color color) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        BoutonsSegmentes<T>(
          values: values,
          labelOf: labelOf,
          semanticsOf: semanticsOf,
          emptySelectionAllowed: true,
          selected: {?selected},
          onSelectionChanged: (s) => onChanged(s.isEmpty ? null : s.single),
        ),
        if (err != null)
          message(err, theme.colorScheme.error)
        else if (warn != null)
          message(warn, theme.colorScheme.tertiary),
      ],
    );
  }
}

/// Valeur d'une ligne remplie par une suggestion de la Bibliothèque.
enum ValeurRemplie {
  nature('nature', feminin: true),
  couleur('couleur', feminin: true),
  rendement('rendement d\'extrait'),
  acidesAlpha('acides alpha', pluriel: true),
  forme('forme', feminin: true),
  type('type'),
  attenuation('atténuation', feminin: true);

  const ValeurRemplie(
    this.libelle, {
    this.feminin = false,
    this.pluriel = false,
  });

  final String libelle;
  final bool feminin;
  final bool pluriel;
}

/// « Couleur et rendement d'extrait repris de la Bibliothèque. », ou `null`
/// si [valeurs] est vide.
String? valeursReprises(List<ValeurRemplie> valeurs) {
  if (valeurs.isEmpty) return null;
  final noms = [for (final v in valeurs) v.libelle];
  final liste = noms.length == 1
      ? noms.single
      : '${noms.sublist(0, noms.length - 1).join(', ')} et ${noms.last}';
  final pluriel = valeurs.length > 1 || valeurs.single.pluriel;
  final feminin = valeurs.every((v) => v.feminin);
  final accord = feminin ? (pluriel ? 'reprises' : 'reprise') : 'repris';
  return '${liste[0].toUpperCase()}${liste.substring(1)} $accord de la Bibliothèque.';
}

/// Bouton qui remplace les valeurs saisies par celles de la Bibliothèque.
const kReprendreBibliotheque = 'Reprendre les valeurs de la Bibliothèque';

/// [kReprendreBibliotheque] : affiché quand une valeur saisie diffère de
/// l'entrée de la Bibliothèque choisie. Une valeur saisie n'est jamais
/// remplacée sans ce geste (ADR-005, E2).
class _Reprendre extends StatelessWidget {
  const _Reprendre({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.restore),
      label: const Text(kReprendreBibliotheque),
    ),
  );
}

/// Seconde ligne d'une suggestion de malt : « Malt · 3,5 EBC · 81 % ».
String? detailFermentable(EntreeIndex e) {
  if (e is! EntreeFermentable) return null;
  final type = _accepte(e.type, typesFermentable);
  final couleur = e.colorEbc;
  final rendement = e.yieldPct;
  final parties = [
    ?e.labelFr,
    if (type != null) typesFermentable.libelle(type),
    if (couleur != null) '${formatNombre(couleur, decimales: 1)}${nbsp}EBC',
    if (rendement != null) '${formatNombre(rendement, decimales: 1)}$nbsp%',
  ];
  return parties.isEmpty ? null : parties.join(' · ');
}

/// Seconde ligne d'une suggestion de houblon : « Pellets · 6,5 % alpha ».
String? detailHoublon(EntreeIndex e) {
  if (e is! EntreeHoublon) return null;
  final forme = _accepte(e.form, formesHoublon);
  final alpha = e.alphaPct;
  final parties = [
    if (forme != null) formesHoublon.libelle(forme),
    if (alpha != null) '${formatNombre(alpha, decimales: 1)}$nbsp% alpha',
  ];
  return parties.isEmpty ? null : parties.join(' · ');
}

/// Seconde ligne d'une suggestion de levure : « Fermentis US-05 · Sèche ».
String? detailLevure(EntreeIndex e) {
  if (e is! EntreeLevure) return null;
  final souche = [?e.producer, ?e.productId].join(' ');
  final forme = _accepte(e.form, formesLevure);
  final parties = [
    if (souche.isNotEmpty) souche,
    if (forme != null) formesLevure.libelle(forme),
  ];
  return parties.isEmpty ? null : parties.join(' · ');
}

/// Seconde ligne d'une suggestion d'ajout : son libellé français ou son type.
String? detailDivers(EntreeIndex e) {
  if (e is! EntreeDivers) return null;
  final type = _accepte(e.type, typesAjout);
  return e.labelFr ?? (type == null ? null : typesAjout.libelle(type));
}

/// Vrai si le nombre saisi [texte] existe et diffère de [valeur].
bool _differe(String texte, double? valeur) {
  if (valeur == null) return false;
  final saisi = lireNombre(texte).valeur;
  return saisi != null && saisi != valeur;
}

/// [valeur] si elle appartient à [valeurs] du schéma, sinon `null`.
String? _accepte(String? valeur, EnumerationBeerJson valeurs) =>
    valeur != null && valeurs.accepte(valeur) ? valeur : null;

/// Valeurs proposées par un choix : [valeurs] de l'éditeur, puis la valeur de
/// la ligne modifiée et la valeur choisie, si elles sont hors de la liste
/// (import, Bibliothèque).
List<String> _avecHorsListe(
  EnumerationBeerJson valeurs,
  String? initiale,
  String? choisie,
) => [
  ...valeurs.proposees,
  for (final v in {?initiale, ?choisie})
    if (!valeurs.proposees.contains(v)) v,
];

/// « Unité de la quantité » : g ou ml, lus « grammes » et « millilitres ».
class _ChoixUnite extends StatelessWidget {
  const _ChoixUnite({required this.selected, required this.onChanged});

  final UniteSaisie selected;
  final ValueChanged<UniteSaisie> onChanged;

  @override
  Widget build(BuildContext context) => _Choix<UniteSaisie>(
    label: 'Unité de la quantité',
    values: UniteSaisie.values,
    labelOf: (u) => u.label,
    semanticsOf: (u) => u.parle,
    selected: selected,
    onChanged: (u) => onChanged(u ?? selected),
  );
}

/// Liste déroulante d'une valeur énumérée de BeerJSON, facultative : « Non
/// précisé » en tête (champ absent), puis les valeurs de l'éditeur, sous leur
/// libellé de menu. Une valeur du schéma hors de cette liste, venue d'un import,
/// reste choisie et s'affiche sous son libellé français : l'enregistrement la
/// conserve. Le champ affiche le libellé court. Une entrée tient sur deux lignes
/// à grande taille de texte.
class ListeBeerJson extends StatelessWidget {
  const ListeBeerJson({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final EnumerationBeerJson values;
  final String? selected;
  final ValueChanged<String?> onChanged;

  static const nonPrecise = 'Non précisé';

  @override
  Widget build(BuildContext context) {
    final current = selected;
    final entries = <String?>[
      null,
      ...values.proposees,
      if (current != null && !values.proposees.contains(current)) current,
    ];
    Text texte(String text) =>
        Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    return DropdownButtonFormField<String?>(
      initialValue: current,
      isExpanded: true,
      itemHeight: null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final v in entries)
          DropdownMenuItem(
            value: v,
            child: texte(v == null ? nonPrecise : values.libelleMenu(v)),
          ),
      ],
      selectedItemBuilder: (context) => [
        for (final v in entries)
          texte(v == null ? nonPrecise : values.libelle(v)),
      ],
      onChanged: onChanged,
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

  /// Reconstruit le formulaire après une saisie : le bouton « Reprendre les
  /// valeurs de la Bibliothèque » suit les valeurs saisies.
  void _suiviSuggestion(String _) => setState(() {});

  /// Champ « Nom » ; [ingredient] faux pour un palier (aucune clé d'ingrédient).
  /// Avec [nature], le champ propose les entrées de la Bibliothèque
  /// (ADR-005, E2) ; [onSuggestion] reçoit l'entrée choisie, [detail] donne
  /// la seconde ligne d'une suggestion. La saisie libre reste possible.
  Widget nameField({
    bool ingredient = true,
    NatureReferentiel? nature,
    List<ValeurRemplie> Function(EntreeIndex)? onSuggestion,
    String? Function(EntreeIndex)? detail,
  }) {
    Widget champ(String? aide, [VoidCallback? onSubmitted]) => TextFormField(
      controller: name,
      focusNode: nameFocus,
      autofocus: true,
      // Entrée choisit la suggestion surlignée après ↑ ou ↓ (ChampBibliotheque).
      onFieldSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      maxLength: kIngredientNameMaxLength,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Nom',
        helperText: aide,
        helperMaxLines: 8,
        border: const OutlineInputBorder(),
      ),
      // Le bouton « Reprendre les valeurs de la Bibliothèque » suit le nom.
      onChanged: nature == null ? null : (_) => setState(() {}),
      validator: (v) => ingredient
          ? erreurNomIngredient(v ?? '')
          : ((v ?? '').trim().isEmpty ? ErreursNombre.obligatoire : null),
    );
    if (nature == null) return champ(null);
    final repris = _reprisPour == name.text.trim() ? _repris : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChampBibliotheque(
          nature: nature,
          controller: name,
          focusNode: nameFocus,
          detail: detail,
          onSelected: (e) => setState(() {
            _repris = valeursReprises(onSuggestion?.call(e) ?? const []);
            _reprisPour = e.name;
          }),
          fieldBuilder: (context, aide, onSubmitted) =>
              champ(aide, onSubmitted),
        ),
        // Ce que la suggestion a rempli, annoncé au lecteur d'écran.
        Semantics(
          liveRegion: true,
          child: repris == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    repris,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
        ),
      ],
    );
  }

  /// Valeurs remplies par la dernière suggestion, et le nom choisi : la ligne
  /// disparaît quand le nom change.
  String? _repris;
  String? _reprisPour;

  /// Après « Reprendre les valeurs de la Bibliothèque » : la ligne sous « Nom »
  /// liste les valeurs reprises, et le focus va au premier champ de saisie
  /// repris ([focus], dans l'ordre du formulaire ; un choix par segments n'a
  /// pas de champ de saisie).
  void montrerReprises(List<ValeurRemplie> valeurs, FocusNode? focus) {
    _repris = valeursReprises(valeurs);
    _reprisPour = name.text.trim();
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    }
  }

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
  final _ebcFocus = FocusNode();
  final _yieldFocus = FocusNode();

  /// Valeur de [typesFermentable] : `grain`, `sugar`, ou la valeur importée de
  /// la ligne modifiée ou de la Bibliothèque, gardée tant que le brasseur n'en
  /// choisit pas une autre.
  String _type = FermentableKind.malt.storedValue;

  /// Vrai quand le type vient du brasseur ou de la ligne modifiée : une
  /// suggestion ne le remplace pas sans « Reprendre ».
  late bool _typeChoisi = widget.initial != null;

  /// Entrée de la Bibliothèque choisie pour le nom, ou `null`.
  EntreeFermentable? _suggestion;

  static const natureAPreciser =
      'Nature à préciser pour le calcul : choisissez Malt ou Sucre.';

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
      _type = i.type;
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
    _ebcFocus.dispose();
    _yieldFocus.dispose();
    super.dispose();
  }

  @override
  FermentableLine readLine() => FermentableLine(
    name: name.text.trim(),
    type: _type,
    weightG: lireNombre(_mass.text).valeur! * 1000,
    ebc: lireNombre(_ebc.text).valeur,
    yieldPct: lireNombre(_yield.text).valeur,
  );

  @override
  void clearFields() {
    _mass.clear();
    _ebc.clear();
    _yield.clear();
    _typeChoisi = false;
    _suggestion = null;
  }

  /// Suggestion choisie : remplit le type, la couleur et le rendement vides.
  List<ValeurRemplie> _choisir(EntreeIndex e) {
    if (e is! EntreeFermentable) return const [];
    _suggestion = e;
    final remplies = <ValeurRemplie>[];
    final type = _accepte(e.type, typesFermentable);
    if (!_typeChoisi && type != null && type != _type) {
      _type = type;
      remplies.add(ValeurRemplie.nature);
    }
    if (_ebc.text.trim().isEmpty && e.colorEbc != null) {
      _ebc.text = texteSaisi(e.colorEbc);
      remplies.add(ValeurRemplie.couleur);
    }
    if (_yield.text.trim().isEmpty && e.yieldPct != null) {
      _yield.text = texteSaisi(e.yieldPct);
      remplies.add(ValeurRemplie.rendement);
    }
    return remplies;
  }

  /// Nature de la suggestion à comparer et à reprendre : celle de l'index,
  /// sauf une nature hors de Malt et Sucre (extrait, miel, fruit) quand le
  /// brasseur a choisi Malt ou Sucre.
  String? get _typeSuggestion {
    final type = _accepte(_suggestion?.type, typesFermentable);
    if (type == null) return null;
    final proposees = typesFermentable.proposees;
    if (_typeChoisi && proposees.contains(_type) && !proposees.contains(type)) {
      return null;
    }
    return type;
  }

  /// Vrai si une valeur saisie diffère de la suggestion, toujours choisie.
  bool get _valeursDifferentes {
    final s = _suggestion;
    if (s == null || name.text.trim() != s.name) return false;
    final type = _typeSuggestion;
    return (type != null && type != _type) ||
        _differe(_ebc.text, s.colorEbc) ||
        _differe(_yield.text, s.yieldPct);
  }

  void _reprendre() => setState(() {
    final s = _suggestion!;
    final reprises = <ValeurRemplie>[];
    FocusNode? focus;
    final type = _typeSuggestion;
    if (type != null && type != _type) {
      _type = type;
      reprises.add(ValeurRemplie.nature);
    }
    if (_differe(_ebc.text, s.colorEbc)) {
      _ebc.text = texteSaisi(s.colorEbc);
      reprises.add(ValeurRemplie.couleur);
      focus ??= _ebcFocus;
    }
    if (_differe(_yield.text, s.yieldPct)) {
      _yield.text = texteSaisi(s.yieldPct);
      reprises.add(ValeurRemplie.rendement);
      focus ??= _yieldFocus;
    }
    montrerReprises(reprises, focus);
  });

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
          nameField(
            nature: NatureReferentiel.fermentables,
            onSuggestion: _choisir,
            detail: detailFermentable,
          ),
          _Choix<String>(
            label: 'Nature',
            values: _avecHorsListe(typesFermentable, initial?.type, _type),
            labelOf: typesFermentable.libelle,
            selected: _type,
            avertissement: FermentableKind.ofType(_type) == null
                ? natureAPreciser
                : null,
            onChanged: (t) => setState(() {
              _type = t ?? _type;
              _typeChoisi = true;
            }),
          ),
          ChampNombre(
            controller: _mass,
            label: 'Quantité (kg)',
            obligatoire: true,
            minExclu: true,
            avertissement: _warnKilograms(_mass.text, kUnusualFermentableGrams),
            onChanged: (_) => setState(() {}),
          ),
          ChampNombre(
            controller: _ebc,
            focusNode: _ebcFocus,
            label: 'Couleur (EBC)',
            aide: 'Sert au calcul de la couleur.',
            onChanged: _suiviSuggestion,
          ),
          ChampNombre(
            controller: _yield,
            focusNode: _yieldFocus,
            label: 'Rendement d\'extrait (%)',
            aide: 'Sert au calcul de la densité initiale.',
            max: 100,
            onChanged: _suiviSuggestion,
            textInputAction: TextInputAction.done,
            onSubmitted: kIsWeb ? (_) => submit(continuer: false) : null,
          ),
          // Après le dernier champ concerné : le champ en cours de frappe ne
          // bouge pas quand le bouton apparaît.
          if (_valeursDifferentes) _Reprendre(onPressed: _reprendre),
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
  final int? recipeBoilMin;
  final ValueChanged<HopLine> onSubmit;

  @override
  ConsumerState<FormulaireHoublon> createState() => _FormulaireHoublonState();
}

class _FormulaireHoublonState extends ConsumerState<FormulaireHoublon>
    with _FormulaireLigne<FormulaireHoublon, HopLine> {
  final _mass = TextEditingController();
  final _alpha = TextEditingController();
  final _alphaFocus = FocusNode();
  final _time = TextEditingController();
  HopUse _use = HopUse.boil;

  /// Valeur de [formesHoublon], ou `null` tant qu'aucune n'est choisie.
  String? _form;
  bool _formError = false;
  UniteSaisie _unite = UniteSaisie.grammes;

  /// Entrée de la Bibliothèque choisie pour le nom, ou `null`.
  EntreeHoublon? _suggestion;

  /// Suggestion choisie : remplit l'acide alpha et la forme vides.
  List<ValeurRemplie> _choisir(EntreeIndex e) {
    if (e is! EntreeHoublon) return const [];
    _suggestion = e;
    final remplies = <ValeurRemplie>[];
    if (_alpha.text.trim().isEmpty && e.alphaPct != null) {
      _alpha.text = texteSaisi(e.alphaPct);
      remplies.add(ValeurRemplie.acidesAlpha);
    }
    final forme = _accepte(e.form, formesHoublon);
    if (_form == null && forme != null) {
      _form = forme;
      _formError = false;
      remplies.add(ValeurRemplie.forme);
    }
    return remplies;
  }

  /// Vrai si une valeur saisie diffère de la suggestion, toujours choisie.
  bool get _valeursDifferentes {
    final s = _suggestion;
    if (s == null || name.text.trim() != s.name) return false;
    final forme = _accepte(s.form, formesHoublon);
    return (forme != null && forme != _form) ||
        _differe(_alpha.text, s.alphaPct);
  }

  void _reprendre() => setState(() {
    final s = _suggestion!;
    final reprises = <ValeurRemplie>[];
    FocusNode? focus;
    if (_differe(_alpha.text, s.alphaPct)) {
      _alpha.text = texteSaisi(s.alphaPct);
      reprises.add(ValeurRemplie.acidesAlpha);
      focus = _alphaFocus;
    }
    final forme = _accepte(s.form, formesHoublon);
    if (forme != null && forme != _form) {
      _form = forme;
      _formError = false;
      reprises.add(ValeurRemplie.forme);
    }
    montrerReprises(reprises, focus);
  });

  /// Moment enregistré que l'éditeur ne propose pas (empâtage,
  /// conditionnement, import), montré pendant toute la modification.
  HopUse? get _momentImporte {
    final u = widget.initial?.use;
    return u == HopUse.mash || u == HopUse.package ? u : null;
  }

  /// Un extrait se mesure en grammes ou en millilitres ; une ligne déjà en
  /// volume garde ce choix, et il reste visible tant que l'unité est ml.
  bool get _uniteAuChoix =>
      _form == 'extract' ||
      (widget.initial?.amount.enLitres ?? false) ||
      _unite == UniteSaisie.millilitres;

  static const formeHorsCalcul =
      'Forme non prise en charge par le calcul de l\'amertume : choisissez '
      'Pellets ou Cônes.';

  /// Extrait pesé : la quantité en volume l'écarte du calcul sans changer sa
  /// forme.
  static const extraitPese =
      'Forme non prise en charge par le calcul de l\'amertume. Pour un extrait, '
      'indiquez la quantité en ml.';

  /// Avertissement sous « Forme » : houblon d'ébullition pesé, d'une forme sans
  /// facteur d'utilisation (poudre, extrait, cônes frais).
  String? get _formeAvertissement {
    final form = _form;
    if (form == null || _use != HopUse.boil) return null;
    if (_uniteAuChoix && _unite == UniteSaisie.millilitres) return null;
    if (HopForm.ofBeerJson(form) != null) return null;
    return form == 'extract' ? extraitPese : formeHorsCalcul;
  }

  /// Texte saisi dans la durée pour chaque moment : revenir à un moment remet
  /// son texte, un moment jamais saisi a un champ vide.
  final _timeTexts = <HopUse, String>{};

  static const formMissing = 'Choisissez une forme.';
  static const momentHorsCalcul =
      'Moment conservé du fichier importé ; le calcul de l\'amertume ne le '
      'prend pas en charge.';
  static const whirlpoolHelp =
      'Temps entre l\'arrêt du feu et le refroidissement. Pour un ajout à '
      'l\'arrêt du feu sans infusion, choisissez Ébullition et 0 min.';

  /// Erreur d'un whirlpool à 0 min, qui se lirait comme un ajout à l'arrêt du
  /// feu.
  static const whirlpoolZero =
      'Au moins 1 min. Pour un ajout à l\'arrêt du feu, choisissez '
      'Ébullition et 0 min.';

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
      _mass.text = texteQuantite(i.amount);
      _unite = uniteDe(i.amount);
      _alpha.text = texteSaisi(i.alphaPct);
      _use = i.use;
      _form = i.form;
      final t = i.timeMin;
      _time.text = texteSaisi(
        t == null || i.use != HopUse.dryHop ? t : t / minutesParJour,
      );
    }
  }

  /// Durée lue en minutes entières : à cru, jours saisis × 1 440 arrondis à la
  /// minute ; sinon, minutes saisies (entier vérifié par le champ).
  int? get _minutes {
    final value = lireNombre(_time.text).valeur;
    if (value == null) return null;
    return (_use == HopUse.dryHop ? value * minutesParJour : value).round();
  }

  @override
  void dispose() {
    _mass.dispose();
    _alpha.dispose();
    _alphaFocus.dispose();
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
    final initial = widget.initial;
    return HopLine(
      name: name.text.trim(),
      amount: lireQuantite(
        _mass.text,
        _uniteAuChoix ? _unite : UniteSaisie.grammes,
      )!,
      alphaPct: lireNombre(_alpha.text).valeur,
      use: _use,
      form: form,
      timeMin: _minutes,
      // Jour d'ajout d'un import : gardé tant que le houblon reste à cru.
      dayMin: _use == HopUse.dryHop && initial?.use == HopUse.dryHop
          ? initial?.dayMin
          : null,
    );
  }

  @override
  void clearFields() {
    _mass.clear();
    _alpha.clear();
    _time.clear();
    _timeTexts.clear();
    _form = null;
    _formError = false;
    _unite = UniteSaisie.grammes;
    _suggestion = null;
  }

  String? get _boilWarning {
    final boil = widget.recipeBoilMin;
    final time = _minutes;
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
          nameField(
            nature: NatureReferentiel.hops,
            onSuggestion: _choisir,
            detail: detailHoublon,
          ),
          if (_uniteAuChoix)
            _ChoixUnite(
              selected: _unite,
              onChanged: (u) => setState(() => _unite = u),
            ),
          ChampNombre(
            key: ValueKey(_uniteAuChoix ? _unite : UniteSaisie.grammes),
            controller: _mass,
            label:
                'Quantité (${(_uniteAuChoix ? _unite : UniteSaisie.grammes).label})',
            aide: _uniteAuChoix && _unite == UniteSaisie.millilitres
                ? '$kHoublonEnVolumePhrase.'
                : null,
            obligatoire: true,
            minExclu: true,
            avertissement: _warnQuantite(
              _mass.text,
              _uniteAuChoix ? _unite : UniteSaisie.grammes,
              kUnusualHopGrams,
            ),
            onChanged: (_) => setState(() {}),
          ),
          ChampNombre(
            controller: _alpha,
            focusNode: _alphaFocus,
            label: 'Acides alpha (%)',
            max: 100,
            onChanged: _suiviSuggestion,
          ),
          _Choix<HopUse>(
            label: 'Utilisation',
            values: [
              HopUse.boil,
              HopUse.afterBoil,
              HopUse.dryHop,
              // Moment importé que l'éditeur ne propose pas : il reste visible
              // et choisi, l'enregistrement le conserve.
              ?_momentImporte,
            ],
            labelOf: libelleUtilisationHoublon,
            selected: _use,
            onChanged: (u) => setState(() {
              final next = u ?? _use;
              // Chaque moment a sa durée : minutes d'ébullition, minutes
              // d'infusion, jours à cru. Changer de moment garde le texte du
              // moment quitté et remet celui du moment choisi.
              if (next != _use) {
                _timeTexts[_use] = _time.text;
                _time.text = _timeTexts[next] ?? '';
              }
              _use = next;
            }),
          ),
          ChampNombre(
            key: ValueKey(_use),
            controller: _time,
            label: switch (_use) {
              HopUse.boil => 'Durée d\'ébullition (min)',
              HopUse.afterBoil => 'Durée d\'infusion (min)',
              HopUse.dryHop => 'Durée à cru (jours)',
              HopUse.mash || HopUse.package => 'Durée (min)',
            },
            aide: switch (_use) {
              HopUse.afterBoil => whirlpoolHelp,
              HopUse.dryHop when widget.initial?.dayMin != null =>
                'Jour d\'ajout du fichier importé conservé : jour '
                    '${formatNombre(widget.initial!.dayMin! / minutesParJour, decimales: 1)}.',
              HopUse.mash || HopUse.package => momentHorsCalcul,
              _ => null,
            },
            obligatoire: _use == HopUse.boil || _use == HopUse.afterBoil,
            entier: _use != HopUse.dryHop,
            min: _use == HopUse.afterBoil ? 1 : 0,
            max: _use == HopUse.boil || _use == HopUse.afterBoil ? 600 : null,
            erreurPropre: _use == HopUse.afterBoil
                ? (t) => lireNombre(t).valeur == 0 ? whirlpoolZero : null
                : null,
            avertissement: _boilWarning,
            onChanged: (_) => setState(() {}),
          ),
          _Choix<String>(
            label: 'Forme',
            values: _avecHorsListe(formesHoublon, widget.initial?.form, _form),
            labelOf: formesHoublon.libelle,
            selected: _form,
            error: _formError ? formMissing : null,
            avertissement: _formeAvertissement,
            onChanged: (f) => setState(() {
              _form = f;
              _formError = false;
            }),
          ),
          // Après le dernier champ concerné : le champ en cours de frappe ne
          // bouge pas quand le bouton apparaît.
          if (_valeursDifferentes) _Reprendre(onPressed: _reprendre),
        ],
      ),
    );
  }
}

/// « Ébullition », « Whirlpool », « À cru », et, pour un import, « Empâtage » et
/// « Conditionnement ».
String libelleUtilisationHoublon(HopUse use) => switch (use) {
  HopUse.mash => 'Empâtage',
  HopUse.boil => 'Ébullition',
  HopUse.afterBoil => 'Whirlpool',
  HopUse.dryHop => 'À cru',
  HopUse.package => 'Conditionnement',
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
  String? _type;
  OtherUse? _use;
  UniteSaisie _unite = UniteSaisie.grammes;

  /// Champ « Utilisation », revalidé quand la durée change.
  final _useField = GlobalKey<FormFieldState<OtherUse?>>();

  /// Suggestion choisie : remplit le type vide (ADR-005, E2).
  List<ValeurRemplie> _choisir(EntreeIndex e) {
    if (e is! EntreeDivers || _type != null) return const [];
    final type = _accepte(e.type, typesAjout);
    if (type == null) return const [];
    _type = type;
    return const [ValeurRemplie.type];
  }

  static const useMissing = 'Choisissez une utilisation.';
  static const afterBoilWithoutTime =
      'Sans durée, l\'ajout est enregistré à l\'arrêt du feu (Ébullition, '
      '0 min).';

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
      _mass.text = texteQuantite(i.amount);
      _unite = uniteDe(i.amount);
      _time.text = texteSaisi(i.timeMin);
      _type = i.type;
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
    amount: lireQuantite(_mass.text, _unite)!,
    type: _type,
    use: _use,
    timeMin: lireNombre(_time.text).valeur?.round(),
  );

  @override
  void clearFields() {
    _mass.clear();
    _time.clear();
    _type = null;
    _use = null;
    _unite = UniteSaisie.grammes;
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
          // La suggestion donne le nom, et le type s'il est vide.
          nameField(
            nature: NatureReferentiel.miscs,
            onSuggestion: _choisir,
            detail: detailDivers,
          ),
          _ChoixUnite(
            selected: _unite,
            onChanged: (u) => setState(() => _unite = u),
          ),
          ChampNombre(
            key: ValueKey(_unite),
            controller: _mass,
            label: 'Quantité (${_unite.label})',
            obligatoire: true,
            minExclu: true,
            avertissement: _warnQuantite(
              _mass.text,
              _unite,
              kUnusualOtherGrams,
            ),
            onChanged: (_) => setState(() {}),
          ),
          ListeBeerJson(
            label: 'Type d\'ajout',
            values: typesAjout,
            selected: _type,
            onChanged: (t) => setState(() => _type = t),
          ),
          DropdownButtonFormField<OtherUse?>(
            key: _useField,
            initialValue: _use,
            isExpanded: true,
            // L'erreur s'efface dès qu'une utilisation est choisie.
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Utilisation',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Non précisée')),
              for (final u in OtherUse.values)
                DropdownMenuItem(value: u, child: Text(u.label)),
            ],
            // Une durée sans moment ne s'écrit pas (`timing` absent).
            validator: (u) => u == null && lireNombre(_time.text).valeur != null
                ? useMissing
                : null,
            onChanged: (u) => setState(() => _use = u),
          ),
          ChampNombre(
            controller: _time,
            label: 'Durée (min)',
            entier: true,
            aide: _use == OtherUse.afterBoil && _time.text.trim().isEmpty
                ? afterBoilWithoutTime
                : null,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              // Durée vidée : l'erreur « Choisissez une utilisation. » s'efface.
              final use = _useField.currentState;
              if (use != null && use.hasError) use.validate();
              setState(() {});
            },
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
  final _amount = TextEditingController();
  final _attenuation = TextEditingController();
  final _attenuationFocus = FocusNode();
  String? _type;
  UniteSaisie _unite = UniteSaisie.grammes;

  /// Valeur de `formesLevure` ; une valeur hors des deux segments (import) est
  /// gardée tant que le brasseur n'en choisit pas une autre.
  String? _form;

  /// Entrée de la Bibliothèque choisie pour le nom, ou `null`.
  EntreeLevure? _suggestion;

  /// Suggestion choisie : remplit le type, la forme et l'atténuation vides.
  List<ValeurRemplie> _choisir(EntreeIndex e) {
    if (e is! EntreeLevure) return const [];
    _suggestion = e;
    final remplies = <ValeurRemplie>[];
    final type = _accepte(e.type, typesLevure);
    if (_type == null && type != null) {
      _type = type;
      remplies.add(ValeurRemplie.type);
    }
    final forme = _accepte(e.form, formesLevure);
    if (_form == null && forme != null) {
      _form = forme;
      remplies.add(ValeurRemplie.forme);
    }
    if (_attenuation.text.trim().isEmpty && e.attenuationPct != null) {
      _attenuation.text = texteSaisi(e.attenuationPct);
      remplies.add(ValeurRemplie.attenuation);
    }
    return remplies;
  }

  /// Vrai si une valeur saisie diffère de la suggestion, toujours choisie.
  bool get _valeursDifferentes {
    final s = _suggestion;
    if (s == null || name.text.trim() != s.name) return false;
    final type = _accepte(s.type, typesLevure);
    final forme = _accepte(s.form, formesLevure);
    return (type != null && type != _type) ||
        (forme != null && forme != _form) ||
        _differe(_attenuation.text, s.attenuationPct);
  }

  void _reprendre() => setState(() {
    final s = _suggestion!;
    final reprises = <ValeurRemplie>[];
    FocusNode? focus;
    final type = _accepte(s.type, typesLevure);
    if (type != null && type != _type) {
      _type = type;
      reprises.add(ValeurRemplie.type);
    }
    final forme = _accepte(s.form, formesLevure);
    if (forme != null && forme != _form) {
      _form = forme;
      reprises.add(ValeurRemplie.forme);
    }
    if (_differe(_attenuation.text, s.attenuationPct)) {
      _attenuation.text = texteSaisi(s.attenuationPct);
      reprises.add(ValeurRemplie.attenuation);
      focus = _attenuationFocus;
    }
    montrerReprises(reprises, focus);
  });

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
      _amount.text = texteQuantite(i.amount);
      _unite = uniteDe(i.amount);
      _attenuation.text = texteSaisi(i.attenuationPct);
      _type = i.type;
      _form = i.form;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _attenuation.dispose();
    _attenuationFocus.dispose();
    super.dispose();
  }

  @override
  YeastLine readLine() => YeastLine(
    name: name.text.trim(),
    type: _type,
    form: _form,
    attenuationPct: lireNombre(_attenuation.text).valeur,
    amount: lireQuantite(_amount.text, _unite),
  );

  @override
  void clearFields() {
    _amount.clear();
    _attenuation.clear();
    _type = null;
    _form = null;
    _suggestion = null;
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
          nameField(
            nature: NatureReferentiel.cultures,
            onSuggestion: _choisir,
            detail: detailLevure,
          ),
          _ChoixUnite(
            selected: _unite,
            onChanged: (u) => setState(() => _unite = u),
          ),
          ChampNombre(
            key: ValueKey(_unite),
            controller: _amount,
            label: 'Quantité (${_unite.label})',
            aide:
                'Le coût compte un sachet par levure, quelle que soit la '
                'quantité.',
            minExclu: true,
          ),
          ChampNombre(
            controller: _attenuation,
            focusNode: _attenuationFocus,
            label: 'Atténuation (%)',
            aide: 'Sert au calcul de la densité finale.',
            max: 100,
            onChanged: _suiviSuggestion,
          ),
          ListeBeerJson(
            label: 'Type de levure',
            values: typesLevure,
            selected: _type,
            onChanged: (t) => setState(() => _type = t),
          ),
          _Choix<String>(
            label: 'Forme',
            // Forme hors des deux segments, venue d'un import ou de la
            // Bibliothèque : elle reste visible et choisie, sous son libellé
            // français.
            values: _avecHorsListe(formesLevure, initial?.form, _form),
            labelOf: formesLevure.libelle,
            selected: _form,
            onChanged: (f) => setState(() => _form = f),
          ),
          // Après le dernier champ concerné : le champ en cours de frappe ne
          // bouge pas quand le bouton apparaît.
          if (_valeursDifferentes) _Reprendre(onPressed: _reprendre),
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
  String? _type;

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
      _type = i.type;
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
    durationMin: lireNombre(_duration.text).valeur!.round(),
    type: _type,
  );

  @override
  void clearFields() {
    _temp.clear();
    _duration.clear();
    _type = null;
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
            entier: true,
            max: 600,
            // « Type de palier » suit la durée.
            textInputAction: TextInputAction.next,
          ),
          ListeBeerJson(
            label: 'Type de palier',
            values: typesPalier,
            selected: _type,
            onChanged: (t) => setState(() => _type = t),
          ),
        ],
      ),
    );
  }
}

/// Formulaire d'une étape de la chronologie (CH1). La clé est créée à l'ajout et
/// reste celle de l'étape à la modification (CH6).
class FormulaireEtape extends ConsumerStatefulWidget {
  const FormulaireEtape({
    super.key,
    this.initial,
    required this.remaining,
    required this.newKey,
    required this.onSubmit,
  });

  final BrewStepLine? initial;
  final int remaining;
  final String Function() newKey;
  final ValueChanged<BrewStepLine> onSubmit;

  @override
  ConsumerState<FormulaireEtape> createState() => _FormulaireEtapeState();
}

class _FormulaireEtapeState extends ConsumerState<FormulaireEtape>
    with _FormulaireLigne<FormulaireEtape, BrewStepLine> {
  final _duration = TextEditingController();
  final _temp = TextEditingController();

  @override
  int get remaining => widget.remaining;
  @override
  bool get editing => widget.initial != null;
  @override
  void submitLine(BrewStepLine line) => widget.onSubmit(line);

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      name.text = i.name;
      _duration.text = texteSaisi(i.durationMin);
      _temp.text = texteSaisi(i.tempC);
    }
  }

  @override
  void dispose() {
    _duration.dispose();
    _temp.dispose();
    super.dispose();
  }

  @override
  BrewStepLine readLine() => BrewStepLine(
    key: widget.initial?.key ?? widget.newKey(),
    name: name.text.trim(),
    durationMin: lireNombre(_duration.text).valeur!,
    tempC: lireNombre(_temp.text).valeur,
  );

  @override
  void clearFields() {
    _duration.clear();
    _temp.clear();
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initial;
    return Form(
      key: formKey,
      child: _Cadre(
        title: initial == null ? 'Étape' : 'Modifier « ${initial.name} »',
        editing: editing,
        canContinue: canContinue,
        onSubmit: submit,
        lastAdded: lastAdded,
        children: [
          TextFormField(
            controller: name,
            focusNode: nameFocus,
            autofocus: true,
            maxLength: kBrewStepNameMaxLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nom de l\'étape',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Donnez un nom à l\'étape.' : null,
          ),
          ChampNombre(
            controller: _duration,
            label: 'Durée (min)',
            aide: '0 pour une action sans minuteur (ajout, mesure).',
            obligatoire: true,
            max: kBrewStepMaxMinutes,
          ),
          ChampNombre(
            controller: _temp,
            label: 'Température visée (°C) (facultatif)',
            max: kBrewStepMaxTemp,
            textInputAction: TextInputAction.done,
            onSubmitted: kIsWeb ? (_) => submit(continuer: false) : null,
          ),
        ],
      ),
    );
  }
}
