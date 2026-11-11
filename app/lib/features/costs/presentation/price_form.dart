import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/champ_nombre.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/segments.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../../recipes/domain/recipe.dart' show truncateName;
import '../domain/price.dart';
import 'formats_cout.dart';

/// Textes du formulaire de prix et de ses annonces (PR2 à PR10).
abstract final class TextesPrix {
  static const nouveau = 'Nouveau prix';
  static const modifier = 'Modifier le prix';
  static String deManquant(String name) => 'Prix de « $name »';
  static const aideNomVerrouille =
      'Le nom suit celui des recettes. Pour le changer, supprimez ce prix et '
      'ajoutez-en un autre.';
  static String existeDeja(String name) =>
      'Un prix existe déjà pour « $name ». Il sera remplacé.';
  static const nomInvalide = 'Le nom doit contenir une lettre ou un chiffre.';
  static const choisirNature = 'Choisissez une nature.';
  static const inhabituel = 'Prix inhabituel : vérifiez la quantité.';
  static String uniteIncompatible(String unite) =>
      'L\'unité enregistrée ne correspond pas : saisissez la quantité en '
      '$unite.';
  static const abandon = 'Le prix saisi ne sera pas enregistré.';

  /// La saisie remplace un prix d'une autre unité (gramme ↔ litre).
  static const remplaceAuGramme =
      'Ce prix remplacera votre prix au gramme, utilisé par les lignes pesées.';
  static const remplaceAuLitre =
      'Ce prix remplacera votre prix au litre, utilisé par les lignes en '
      'volume.';

  /// Unité choisie qui ne comptera pas la ligne d'où le prix s'ouvre.
  static const ligneEnVolume =
      'Cette ligne est en volume : un prix au gramme ne la comptera pas.';
  static const lignePesee =
      'Cette ligne est pesée : un prix au litre ne la comptera pas.';
  static const reprendre = 'Reprendre un de mes prix';
  static String reprendreTitre(IngredientNature nature) =>
      'Reprendre un prix de ${libelleNatureMinuscule(nature)}';
  static const enregistre = 'Prix enregistré.';
  static const enregistreHorsLigne =
      'Prix enregistré sur l\'appareil. Il partira au retour du réseau.';
  static String refus(String name) =>
      'L\'enregistrement du prix de « $name » a échoué.';
  static String supprime(String name) => 'Prix de « $name » supprimé.';
  static String suppressionRefusee(String name) =>
      'La suppression du prix de « $name » a échoué.';
}

/// Unité de saisie de la quantité achetée : kilogrammes ou grammes (stockés en
/// grammes), litres ou millilitres (stockés en litres, houblon et ajout,
/// v0.1.17), sachets (levure).
enum UniteAchat {
  kg('kg', 'kilogrammes', CostUnit.gram, 1000),
  g('g', 'grammes', CostUnit.gram, 1),
  l('L', 'litres', CostUnit.litre, 1),
  ml('ml', 'millilitres', CostUnit.litre, 0.001),
  sachets('sachets', 'sachets', CostUnit.unit, 1);

  const UniteAchat(this.label, this.parle, this.unit, this.facteur);

  /// Libellé court du segment et du champ.
  final String label;

  /// Libellé lu par un lecteur d'écran.
  final String parle;

  /// Unité stockée.
  final CostUnit unit;

  /// Quantité stockée pour une unité saisie.
  final double facteur;

  /// Unités de saisie de [nature] : celles de ses unités d'achat
  /// ([purchaseUnitsOf]).
  static List<UniteAchat> de(IngredientNature nature) => [
    for (final u in UniteAchat.values)
      if (purchaseUnitsOf(nature).contains(u.unit)) u,
  ];
}

/// Façon d'ouvrir le formulaire de prix.
enum ModePrix {
  /// « Ajouter un prix » : nature et nom à saisir.
  nouveau,

  /// « Saisir le prix » depuis un manquant (LI7) : nature et nom fixés.
  manquant,

  /// Modification d'un prix, ou « Corriger le prix » (LI8, LI9) : nature et nom
  /// verrouillés.
  modification,
}

/// Ouvre le formulaire de prix de [uid]. [mesPrix] : prix lisibles du
/// brasseur, pour l'avertissement PR8 et « Reprendre un de mes prix ».
///
/// [initial] : prix à modifier ; nul pour un nouveau prix, ou pour un prix
/// illisible à corriger (champs vides). [nature] et [name] : ingrédient fixé
/// (manquant, modification). [uniteLigne] : unité de la ligne de recette à
/// chiffrer (« Saisir le prix », « Corriger le prix ») ; une ligne en litres
/// ouvre la saisie en litres. Rend vrai si un prix a été enregistré.
Future<bool> ouvrirFormulairePrix(
  BuildContext context, {
  required String uid,
  required List<Price> mesPrix,
  required ModePrix mode,
  Price? initial,
  IngredientNature? nature,
  String? name,
  CostUnit? uniteLigne,
}) async {
  // ticket: /prix/fenetre/prix, /recettes/:id/fenetre/prix, /brassins/:id/fenetre/prix
  final saved = await showFeuilleOuDialogue<bool>(
    context: context,
    fermetureProtegee: true,
    builder: (_) => FormulairePrix(
      uid: uid,
      mesPrix: mesPrix,
      mode: mode,
      initial: initial,
      nature: nature ?? initial?.nature,
      name: name ?? initial?.name,
      uniteLigne: uniteLigne,
    ),
  );
  return saved ?? false;
}

/// Formulaire « Nouveau prix », « Modifier le prix », « Prix de « Pils » ».
class FormulairePrix extends ConsumerStatefulWidget {
  const FormulairePrix({
    super.key,
    required this.uid,
    required this.mesPrix,
    required this.mode,
    this.initial,
    this.nature,
    this.name,
    this.uniteLigne,
  });

  final String uid;
  final List<Price> mesPrix;
  final ModePrix mode;
  final Price? initial;
  final IngredientNature? nature;
  final String? name;

  /// Unité de la ligne de recette à chiffrer, ou `null`.
  final CostUnit? uniteLigne;

  @override
  ConsumerState<FormulairePrix> createState() => _FormulairePrixState();
}

class _FormulairePrixState extends ConsumerState<FormulairePrix> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  IngredientNature? _nature;

  /// Unité de saisie de la quantité, parmi [UniteAchat.de] de la nature.
  late UniteAchat _saisie;
  String? _natureError;
  bool _modifie = false;

  /// Prix lu dans une unité qui ne convient pas à sa nature ou à la ligne à
  /// chiffrer (LI8) : la quantité est à saisir de nouveau.
  bool _uniteIncompatible = false;

  bool get _fixe => widget.mode != ModePrix.nouveau;

  @override
  void initState() {
    super.initState();
    _nature = widget.nature;
    _name = TextEditingController(text: widget.name ?? '');
    _price = TextEditingController();
    _quantity = TextEditingController();
    _saisie = _uniteParDefaut(_nature, widget.uniteLigne);
    final initial = widget.initial;
    final nature = _nature;
    if (initial != null) {
      _price.text = texteSaisi(initial.priceEur, decimales: 4);
      // Unité incompatible (LI8) : la quantité achetée ne se relit pas dans
      // l'unité attendue, elle est à saisir de nouveau, dans l'unité de la ligne.
      final ligne = widget.uniteLigne;
      _uniteIncompatible =
          nature != null &&
          (!purchaseUnitsOf(nature).contains(initial.unit) ||
              (ligne != null && ligne != initial.unit));
      if (nature != null && !_uniteIncompatible) {
        _remplirQuantite(initial.quantity, initial.unit);
      }
    }
    for (final c in [_name, _price, _quantity]) {
      c.addListener(_changement);
    }
  }

  void _changement() => setState(() => _modifie = true);

  /// Unité de saisie à l'ouverture : celle de la ligne à chiffrer (litres pour
  /// une ligne en volume), sinon grammes pour un houblon ou un ajout,
  /// kilogrammes pour un malt ou un sucre, sachets pour une levure.
  static UniteAchat _uniteParDefaut(
    IngredientNature? nature,
    CostUnit? ligne,
  ) => switch (nature) {
    IngredientNature.yeast => UniteAchat.sachets,
    IngredientNature.hop || IngredientNature.addition =>
      ligne == CostUnit.litre ? UniteAchat.l : UniteAchat.g,
    _ => UniteAchat.kg,
  };

  /// Remplit la quantité de [quantity] stockée en [unit], dans l'unité de
  /// saisie la plus lisible : kilogrammes dès 1 000 g, millilitres sous 1 L.
  void _remplirQuantite(double quantity, CostUnit unit) {
    _saisie = switch (unit) {
      CostUnit.unit => UniteAchat.sachets,
      CostUnit.litre => quantity >= 1 ? UniteAchat.l : UniteAchat.ml,
      _ => quantity >= 1000 ? UniteAchat.kg : UniteAchat.g,
    };
    // Arrondi au millième : 0,1 L ÷ 0,001 ne donne pas toujours 100.
    final saisi = (quantity / _saisie.facteur * 1000).round() / 1000;
    _quantity.text = texteSaisi(saisi, decimales: _levure ? 0 : 3);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  bool get _levure => _nature == IngredientNature.yeast;

  /// Quantité saisie convertie dans l'unité stockée (grammes, sachets ou
  /// litres), ou `null` si elle est illisible ou hors bornes.
  double? get _quantiteStockee {
    final text = _quantity.text;
    if (_erreurQuantite(text) != null) return null;
    final value = lireNombre(text).valeur;
    if (value == null) return null;
    return value * _saisie.facteur;
  }

  double? get _prixSaisi {
    final text = _price.text;
    if (erreurNombre(text, obligatoire: true, max: kPriceMaxEur) != null) {
      return null;
    }
    return lireNombre(text).valeur;
  }

  String? _erreurQuantite(String text) => erreurNombre(
    text,
    obligatoire: true,
    minExclu: true,
    entier: _levure,
    max: _maxQuantite,
  );

  /// Borne de la quantité saisie : 1e9 grammes, sachets ou litres stockés, soit
  /// 1e6 kg ; 1e9 ml, borne de la saisie des nombres.
  double get _maxQuantite => _saisie.facteur > 1
      ? kPurchaseQuantityMax / _saisie.facteur
      : kPurchaseQuantityMax;

  /// Prix unitaire de la saisie (PR7, `brewing/`), ou `null` si un champ est
  /// illisible.
  double? get _prixUnitaire {
    final price = _prixSaisi;
    final quantity = _quantiteStockee;
    if (price == null || quantity == null || quantity <= 0) return null;
    return unitPrice(priceEur: price, quantity: quantity);
  }

  /// Avertissements sous l'unité : prix d'une autre unité remplacé, et unité
  /// qui ne comptera pas la ligne d'où le prix s'ouvre (gramme ↔ litre).
  List<String> get _avertissementsUnite {
    final saisie = _saisie.unit;
    const grammeOuLitre = {CostUnit.gram, CostUnit.litre};
    if (!grammeOuLitre.contains(saisie)) return const [];
    final remplace = widget.initial ?? _existant;
    final ligne = widget.uniteLigne;
    return [
      if (remplace != null &&
          remplace.unit != saisie &&
          grammeOuLitre.contains(remplace.unit))
        remplace.unit == CostUnit.gram
            ? TextesPrix.remplaceAuGramme
            : TextesPrix.remplaceAuLitre,
      if (ligne != null && ligne != saisie && grammeOuLitre.contains(ligne))
        ligne == CostUnit.litre
            ? TextesPrix.ligneEnVolume
            : TextesPrix.lignePesee,
    ];
  }

  /// Prix existant pour la clé de la saisie (PR8), hors du prix modifié.
  Price? get _existant {
    final nature = _nature;
    final name = _name.text;
    if (widget.mode != ModePrix.nouveau ||
        nature == null ||
        !isValidIngredientName(name)) {
      return null;
    }
    final key = ingredientKey(nature, name);
    for (final p in widget.mesPrix) {
      if (p.key == key) return p;
    }
    return null;
  }

  List<Price> get _reprenables {
    final nature = _nature;
    if (nature == null) return const [];
    final key = widget.initial?.key;
    return [
      for (final p in widget.mesPrix)
        if (p.nature == nature && p.key != key) p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> _reprendre() async {
    final nature = _nature;
    if (nature == null) return;
    // ticket: /prix/fenetre/reprendre, /recettes/:id/fenetre/reprendre, /brassins/:id/fenetre/reprendre
    final choisi = await showFeuilleOuDialogue<Price>(
      context: context,
      builder: (context) => _ListeReprise(
        titre: TextesPrix.reprendreTitre(nature),
        prix: _reprenables,
      ),
    );
    if (choisi == null || !mounted) return;
    setState(() {
      _price.text = texteSaisi(choisi.priceEur, decimales: 4);
      _remplirQuantite(choisi.quantity, choisi.unit);
      _modifie = true;
    });
  }

  Future<void> _quitter() async {
    final navigator = Navigator.of(context);
    if (!_modifie) {
      navigator.pop(false);
      return;
    }
    // ticket: aucun (confirmation)
    final abandon = await confirmerAbandon(context, TextesPrix.abandon);
    if (abandon && mounted) navigator.pop(false);
  }

  void _save() {
    final nature = _nature;
    setState(
      () => _natureError = nature == null ? TextesPrix.choisirNature : null,
    );
    final valid = _form.currentState?.validate() ?? false;
    final price = _prixSaisi;
    final quantity = _quantiteStockee;
    if (!valid || nature == null || price == null || quantity == null) return;
    final nom = _name.text.trim();
    // La clé suit le nom de la recette en entier ; le nom stocké est coupé à la
    // borne des règles, qu'un nom importé peut dépasser.
    final key = widget.initial?.key ?? ingredientKey(nature, nom);
    final name = truncateName(nom, kPriceNameMaxLength);
    final saisi = Price(
      key: key,
      name: name,
      priceEur: price,
      quantity: quantity,
      unit: _saisie.unit,
    );
    final offline = ref.read(grantedAccessProvider)?.offline ?? false;
    final messenger = ScaffoldMessenger.of(context);
    suivreEcriture(
      messenger: messenger,
      written: ref
          .read(costsRepositoryProvider)
          .savePrice(uid: widget.uid, price: saisi),
      succes: offline ? TextesPrix.enregistreHorsLigne : TextesPrix.enregistre,
      refus: TextesPrix.refus(name),
    );
    Navigator.of(context).pop(true);
  }

  void _delete(Price initial) {
    final repo = ref.read(costsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final uid = widget.uid;
    unawaited(
      repo.deletePrice(uid: uid, key: initial.key).catchError((Object _) {
        // Déjà rapportée par le dépôt de données.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(TextesPrix.suppressionRefusee(initial.name))),
        );
      }),
    );
    annoncerAvecAnnulation(
      messenger,
      TextesPrix.supprime(initial.name),
      onAnnuler: () => suivreEcriture(
        messenger: messenger,
        written: repo.savePrice(uid: uid, price: initial),
        succes: TextesPrix.enregistre,
        refus: TextesPrix.refus(initial.name),
      ),
    );
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nature = _nature;
    final initial = widget.initial;
    final titre = switch (widget.mode) {
      ModePrix.nouveau => TextesPrix.nouveau,
      ModePrix.manquant => TextesPrix.deManquant(_name.text),
      ModePrix.modification => TextesPrix.modifier,
    };
    final unitaire = _prixUnitaire;
    final existant = _existant;
    final reprenables = widget.mode == ModePrix.nouveau
        ? const <Price>[]
        : _reprenables;
    final quantiteLabel = 'Quantité achetée (${_saisie.label})';
    final unites = nature == null
        ? const <UniteAchat>[]
        : UniteAchat.de(nature);
    return PopScope(
      canPop: !_modifie,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_quitter());
      },
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titre, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_fixe && nature != null) ...[
              Text(
                parties([libelleNature(nature), _name.text]).texte,
                semanticsLabel: parties([
                  libelleNature(nature),
                  _name.text,
                ]).parle,
                style: theme.textTheme.titleMedium,
              ),
              if (widget.mode == ModePrix.modification)
                Text(
                  TextesPrix.aideNomVerrouille,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (reprenables.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _reprendre,
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text(TextesPrix.reprendre),
                  ),
                ),
              const SizedBox(height: 16),
            ] else ...[
              DropdownButtonFormField<IngredientNature>(
                initialValue: nature,
                decoration: InputDecoration(
                  labelText: 'Nature',
                  errorText: _natureError,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final n in IngredientNature.values)
                    DropdownMenuItem(value: n, child: Text(libelleNature(n))),
                ],
                onChanged: (n) => setState(() {
                  _nature = n;
                  _saisie = _uniteParDefaut(n, widget.uniteLigne);
                  _natureError = null;
                  _modifie = true;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                maxLength: kPriceNameMaxLength,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Nom',
                  border: const OutlineInputBorder(),
                  helperText: existant == null
                      ? null
                      : TextesPrix.existeDeja(existant.name),
                  helperMaxLines: 3,
                  helperStyle: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                validator: (text) {
                  if (text == null || text.trim().isEmpty) {
                    return ErreursNombre.obligatoire;
                  }
                  if (!isValidIngredientName(text)) {
                    return TextesPrix.nomInvalide;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
            ],
            ChampNombre(
              controller: _price,
              label: 'Prix payé (€)',
              obligatoire: true,
              max: kPriceMaxEur,
            ),
            const SizedBox(height: 16),
            ChampNombre(
              key: ValueKey(_saisie),
              controller: _quantity,
              label: quantiteLabel,
              obligatoire: true,
              minExclu: true,
              entier: _levure,
              max: _maxQuantite,
              aide: _uniteIncompatible && _quantity.text.trim().isEmpty
                  ? TextesPrix.uniteIncompatible(_saisie.label)
                  : null,
              avertissement:
                  nature != null &&
                      unitaire != null &&
                      isUnusualPrice(nature, unitaire, unit: _saisie.unit)
                  ? TextesPrix.inhabituel
                  : null,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            if (unites.length > 1) ...[
              const SizedBox(height: 8),
              Text('Unité', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: BoutonsSegmentes<UniteAchat>(
                  values: unites,
                  labelOf: (u) => u.label,
                  semanticsOf: (u) => u.parle,
                  selected: {_saisie},
                  onSelectionChanged: (s) => setState(() {
                    _saisie = s.first;
                    _modifie = true;
                  }),
                ),
              ),
              for (final texte in _avertissementsUnite)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    texte,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              unitaire == null || nature == null
                  ? ''
                  : 'Soit ${formatPrixUnitaireDe(unitaire, _saisie.unit)}',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (initial != null && widget.mode == ModePrix.modification)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => _delete(initial),
                    child: const Text('Supprimer'),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => unawaited(_quitter()),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('Enregistrer'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Seconde feuille de « Reprendre un de mes prix » : un appui rend le prix
/// choisi, sans rien enregistrer (LI6).
class _ListeReprise extends StatelessWidget {
  const _ListeReprise({required this.titre, required this.prix});

  final String titre;
  final List<Price> prix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titre, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final p in prix)
          LignePrix(price: p, onTap: () => Navigator.of(context).pop(p)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
        ),
      ],
    );
  }
}

/// Ligne d'un prix : nom, puis « 47,50 € les 25 kg · 1,90 €/kg », lue d'un bloc
/// sans le point médian.
class LignePrix extends StatelessWidget {
  const LignePrix({
    super.key,
    required this.price,
    required this.onTap,
    this.trailing,
  });

  final Price price;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = parties([formatAchat(price), formatPrixUnitaire(price)]);
    final parle = parties([achatParle(price), prixUnitaireParle(price)]).parle;
    final extra = trailing;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(price.name, style: theme.textTheme.titleMedium),
                Text(
                  detail.texte,
                  semanticsLabel: parle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (extra != null) ...[const SizedBox(height: 8), extra],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
