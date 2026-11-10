import 'dart:async';

import 'package:brewing/brewing.dart' show CostUnit;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/brew_cost.dart';
import '../domain/cost_evaluation.dart';
import '../domain/fee.dart';
import '../domain/price.dart';
import 'costs_providers.dart';
import 'formats_cout.dart';
import 'price_form.dart';

/// Textes des blocs Coût (CR, CB, HL4). Aucun n'entre dans une annonce avec un
/// montant (SE7).
abstract final class TextesCout {
  static const titreRecette = 'Coût avec vos prix';
  static const chargementPrix = 'Chargement de vos prix';
  static const lecturePrixImpossible = 'Impossible de lire vos prix.';
  static const horsLigne = 'Prix indisponibles sur cet appareil hors ligne.';
  static const aucunIngredient = 'Aucun ingrédient.';
  static const calculImpossible = 'Calcul du coût impossible.';
  static const volume = 'Volume en fermenteur non renseigné.';
  static const sansNom =
      'Une ligne de cette recette n\'a pas de nom utilisable.';
  static const fraisIllisible =
      'Un de vos frais est illisible : il ne peut pas être compté.';
  static const sucreSansNature = 'Nature du sucre de resucrage non renseignée.';
  static const bouteilles =
      'Nombre de bouteilles non renseigné : les frais par bouteille ne peuvent '
      'pas être comptés.';
  static const aucunFrais =
      'Aucun frais compté (eau, électricité, embouteillage).';
  static const ajouterFrais = 'Ajouter mes frais';
  static const detail = 'Détail du coût';

  /// En-tête des manquants (CR4) : « Coût indisponible : 3 prix manquants. ».
  static String indisponible(int prixManquants) => prixManquants == 0
      ? 'Coût indisponible.'
      : 'Coût indisponible : $prixManquants prix '
            'manquant${prixManquants > 1 ? 's' : ''}.';

  /// Prix d'une unité qui ne chiffre pas la ligne : « Acide lactique · 5 ml :
  /// votre prix est au gramme. Saisissez un prix au litre pour compter cette
  /// ligne. ». L'unité demandée est celle de la ligne ([ligne] : sachet, gramme
  /// ou litre), jamais supposée.
  static String prixIncompatible(
    String ligne, {
    required CostUnit prix,
    required CostUnit attendu,
  }) =>
      '$ligne : votre prix est ${_au(prix)}. Saisissez un prix ${_au(attendu)} '
      'pour compter cette ligne.';

  static String _au(CostUnit unit) => switch (unit) {
    CostUnit.unit => 'au sachet',
    CostUnit.litre => 'au litre',
    CostUnit.gram => 'au gramme',
    CostUnit.brew => 'par brassin',
    CostUnit.bottle => 'par bouteille',
  };

  /// Brassin dont une ligne en volume n'a pas de prix utilisable, sans action
  /// sur place (CB8).
  static String brassinEnVolume(String name) =>
      'Ce brassin compte $name en volume : saisissez un prix au litre dans Mes '
      'prix pour figer son coût.';

  static String deuxUnites(String name) =>
      '$name : quantités en grammes et en volume, qui ne s\'additionnent pas.';
  static String deuxUnitesAuteur(String name) =>
      '${deuxUnites(name)} Mettez les deux lignes dans la même unité.';
  static String deuxUnitesLecteur(String name) =>
      '${deuxUnites(name)} Dupliquez la recette pour la corriger à votre nom.';
  static String deuxUnitesBrassin(String name) =>
      'Ce brassin compte $name en grammes et en volume : ces quantités ne '
      's\'additionnent pas, son coût ne peut pas être figé.';
  static String prixIllisible(String name) => '$name : prix illisible.';
}

/// Ligne du détail du coût, et sa lecture sans le point médian.
typedef LigneDetail = ({String texte, String parle});

/// Lignes du détail d'un coût calculé (CR8) : « Pils · 5 kg · 9,50 € »,
/// « Électricité · par brassin · 2,00 € ».
List<LigneDetail> lignesDetail(CoutObtenu cout) => [
  for (final l in cout.lignes)
    _ligne(
      l.name,
      l.quantity,
      l.unit,
      l.costEur,
      parBouteille: cout.bouteillesEstimees,
    ),
];

/// Lignes d'un coût figé (CB12) : quantités du jour du figeage.
List<LigneDetail> lignesFigees(BrewCost cout) => [
  for (final l in cout.lines)
    _ligne(l.name, l.quantity, l.unit, l.costEur, parBouteille: false),
];

LigneDetail _ligne(
  String name,
  double quantity,
  CostUnit unit,
  double costEur, {
  required bool parBouteille,
}) {
  final cost = formatEuros(costEur);
  final (String texte, String parle) = switch (unit) {
    CostUnit.gram || CostUnit.unit || CostUnit.litre => (
      formatQuantite(quantity, unit),
      quantiteParlee(quantity, unit),
    ),
    CostUnit.brew => ('par brassin', 'par brassin'),
    CostUnit.bottle =>
      parBouteille
          ? ('par bouteille', 'par bouteille')
          : (formatBouteilles(quantity), formatBouteilles(quantity)),
  };
  return (
    texte: parties([name, texte, cost]).texte,
    parle: parties([name, parle, cost]).parle,
  );
}

/// « Détail du coût », repliable et fermé, résumé « 14 lignes ».
class DetailCout extends StatelessWidget {
  const DetailCout({super.key, required this.lignes, required this.storageKey});

  final List<LigneDetail> lignes;
  final String storageKey;

  @override
  Widget build(BuildContext context) {
    final n = lignes.length;
    return SectionRepliable(
      titre: TextesCout.detail,
      storageKey: storageKey,
      resume: '$n ligne${n > 1 ? 's' : ''}',
      children: [
        for (final l in lignes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l.texte, semanticsLabel: l.parle),
          ),
      ],
    );
  }
}

/// Texte d'hypothèse, en couleur atténuée.
class TexteHypothese extends StatelessWidget {
  const TexteHypothese(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        // « · » n'est pas lu.
        semanticsLabel: text.replaceAll(' · ', ', '),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Cadre « Calcul du coût impossible. » (CR9), comme `CalculsImpossibles`.
class CadreCalculImpossible extends StatelessWidget {
  const CadreCalculImpossible({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  TextesCout.calculImpossible,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une raison et son action, sur deux niveaux si la largeur manque. La ligne
/// entière fait au moins 48 dp et répond à l'appui ; seul le bouton est lu comme
/// une action.
class LigneRaison extends StatelessWidget {
  const LigneRaison({
    super.key,
    required this.texte,
    this.parle,
    this.action,
    this.actionParlee,
    this.onAction,
  });

  final String texte;
  final String? parle;
  final String? action;
  final String? actionParlee;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = action;
    final tap = onAction;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(texte, semanticsLabel: parle),
          if (label != null && tap != null)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: tap,
              child: Text(label, semanticsLabel: actionParlee),
            ),
        ],
      ),
    );
    if (label == null || tap == null) {
      return Align(alignment: Alignment.centerLeft, child: content);
    }
    return InkWell(
      onTap: tap,
      excludeFromSemantics: true,
      child: Align(alignment: Alignment.centerLeft, child: content),
    );
  }
}

/// Actions offertes à la liste des raisons ; une action nulle n'est pas proposée.
@immutable
class ActionsRaisons {
  const ActionsRaisons({
    this.onPrix,
    this.onCompleterRecette,
    this.onModifierEmbouteillage,
    this.onMesPrix,
    this.brassin = false,
  });

  /// « Saisir le prix » (manquant) ou « Corriger le prix » (incompatible,
  /// illisible).
  final ValueChanged<RaisonPrix>? onPrix;
  final VoidCallback? onCompleterRecette;
  final VoidCallback? onModifierEmbouteillage;
  final VoidCallback? onMesPrix;

  /// Vrai pour le coût d'un brassin : sa copie figée ne se corrige pas.
  final bool brassin;
}

/// Une ligne par raison (LI7 à LI10, CR4 à CR6, CB8), aucune avec un montant.
List<Widget> lignesRaisons(List<RaisonCout> raisons, ActionsRaisons actions) =>
    [for (final r in raisons) ?_ligneRaison(r, actions)];

Widget? _ligneRaison(RaisonCout raison, ActionsRaisons actions) {
  final onPrix = actions.onPrix;
  String ligne(IngredientCout i) =>
      parties([i.name, formatQuantite(i.quantity, i.unit)]).texte;
  switch (raison) {
    // Brassin, ligne en volume, aucune action sur place : Mes prix seul.
    case RaisonPrix(:final ingredient)
        when actions.brassin &&
            onPrix == null &&
            ingredient.unit == CostUnit.litre &&
            raison is! PrixIllisible:
      return LigneRaison(
        texte: TextesCout.brassinEnVolume(ingredient.name),
        action: 'Ouvrir Mes prix',
        onAction: actions.onMesPrix,
      );
    case PrixManquant(:final ingredient):
      final litres = ingredient.unit == CostUnit.litre;
      return LigneRaison(
        texte: ligne(ingredient),
        parle:
            '${ingredient.name}, '
            '${quantiteParlee(ingredient.quantity, ingredient.unit)}, '
            'prix manquant',
        action: litres ? 'Saisir le prix au litre' : 'Saisir le prix',
        actionParlee: litres
            ? 'Saisir le prix au litre de ${ingredient.name}'
            : 'Saisir le prix de ${ingredient.name}',
        onAction: onPrix == null ? null : () => onPrix(raison),
      );
    case QuantitesDeDeuxUnites(:final name):
      if (actions.brassin) {
        return LigneRaison(texte: TextesCout.deuxUnitesBrassin(name));
      }
      final completer = actions.onCompleterRecette;
      return completer == null
          ? LigneRaison(texte: TextesCout.deuxUnitesLecteur(name))
          : LigneRaison(
              texte: TextesCout.deuxUnitesAuteur(name),
              action: 'Compléter la recette',
              onAction: completer,
            );
    case PrixUniteIncompatible(:final ingredient, :final price):
      final parle = parties([
        ingredient.name,
        quantiteParlee(ingredient.quantity, ingredient.unit),
      ]).parle;
      return LigneRaison(
        texte: TextesCout.prixIncompatible(
          ligne(ingredient),
          prix: price.unit,
          attendu: ingredient.unit,
        ),
        parle: TextesCout.prixIncompatible(
          parle,
          prix: price.unit,
          attendu: ingredient.unit,
        ),
        action: 'Corriger le prix',
        actionParlee: 'Corriger le prix de ${ingredient.name}',
        onAction: onPrix == null ? null : () => onPrix(raison),
      );
    case PrixIllisible(:final ingredient):
      return LigneRaison(
        texte: TextesCout.prixIllisible(ingredient.name),
        action: 'Corriger le prix',
        actionParlee: 'Corriger le prix de ${ingredient.name}',
        onAction: onPrix == null ? null : () => onPrix(raison),
      );
    case LigneSansNom():
      return const LigneRaison(texte: TextesCout.sansNom);
    case VolumeNonRenseigne():
      return LigneRaison(
        texte: TextesCout.volume,
        action: 'Compléter la recette',
        onAction: actions.onCompleterRecette,
      );
    case AucunIngredient():
      return const LigneRaison(texte: TextesCout.aucunIngredient);
    case PrixIndisponiblesHorsLigne():
      return const LigneRaison(texte: TextesCout.horsLigne);
    case FraisIllisible():
      return LigneRaison(
        texte: TextesCout.fraisIllisible,
        action: 'Ouvrir Mes prix',
        onAction: actions.onMesPrix,
      );
    case SucreResucrageSansNature():
      return LigneRaison(
        texte: TextesCout.sucreSansNature,
        action: 'Modifier l\'embouteillage',
        onAction: actions.onModifierEmbouteillage,
      );
    case BouteillesNonRenseignees():
      return LigneRaison(
        texte: TextesCout.bouteilles,
        action: 'Renseigner les bouteilles',
        onAction: actions.onModifierEmbouteillage,
      );
    case CalculImpossible():
      // Affiché à part, dans son cadre (CR9).
      return null;
  }
}

/// Vrai si [a] et [b] disent la même chose (même raison, même ingrédient).
bool memeRaison(RaisonCout a, RaisonCout b) {
  if (a.runtimeType != b.runtimeType) return false;
  if (a is RaisonPrix && b is RaisonPrix) {
    return a.ingredient.key == b.ingredient.key;
  }
  if (a is QuantitesDeDeuxUnites && b is QuantitesDeDeuxUnites) {
    return a.name == b.name;
  }
  return true;
}

/// Coût indisponible : cadre du calcul impossible, ou en-tête annoncé et liste
/// des raisons, sans aucun montant (CR4).
List<Widget> vueIndisponible(
  BuildContext context,
  CoutIndisponible cout,
  ActionsRaisons actions,
) {
  final raisons = cout.raisons;
  if (raisons.any((r) => r is CalculImpossible)) {
    return const [CadreCalculImpossible()];
  }
  if (raisons.length == 1 &&
      (raisons.single is AucunIngredient ||
          raisons.single is PrixIndisponiblesHorsLigne)) {
    return [
      TexteAbsent(
        raisons.single is AucunIngredient
            ? TextesCout.aucunIngredient
            : TextesCout.horsLigne,
      ),
    ];
  }
  final theme = Theme.of(context);
  return [
    Semantics(
      liveRegion: true,
      child: Text(
        TextesCout.indisponible(cout.prixManquants),
        style: theme.textTheme.titleSmall,
      ),
    ),
    const SizedBox(height: 4),
    ...lignesRaisons(raisons, actions),
  ];
}

/// Mention FR5 et accès à « Mes prix ».
class MentionAucunFrais extends StatelessWidget {
  const MentionAucunFrais({super.key});

  @override
  Widget build(BuildContext context) => LigneRaison(
    texte: TextesCout.aucunFrais,
    action: TextesCout.ajouterFrais,
    onAction: () => unawaited(context.push(AppRoutes.prices)),
  );
}

/// État des lectures de prix et de frais : `null` quand les deux sont lus, sinon
/// le texte de chargement ou la panne avec « Réessayer ».
Widget? etatLecturePrix({
  required AsyncValue<ListeLue<Price>> prices,
  required AsyncValue<ListeLue<Fee>> fees,
  required VoidCallback onRetry,
}) {
  if ((prices.value == null && prices.hasError) ||
      (fees.value == null && fees.hasError)) {
    return Row(
      children: [
        const Expanded(child: TexteAbsent(TextesCout.lecturePrixImpossible)),
        TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    );
  }
  if (prices.value == null || fees.value == null) {
    return const TexteAbsent(TextesCout.chargementPrix);
  }
  return null;
}

/// Ouvre le formulaire de prix d'une raison : « Saisir le prix » pour un
/// manquant, « Corriger le prix » sinon (LI7 à LI9). Rend vrai si un prix a été
/// enregistré.
Future<bool> ouvrirPrixDeRaison(
  BuildContext context, {
  required String uid,
  required List<Price> mesPrix,
  required RaisonPrix raison,
}) {
  final ingredient = raison.ingredient;
  return ouvrirFormulairePrix(
    context,
    uid: uid,
    mesPrix: mesPrix,
    mode: raison is PrixManquant ? ModePrix.manquant : ModePrix.modification,
    initial: raison is PrixUniteIncompatible ? raison.price : null,
    nature: ingredient.nature,
    name: ingredient.name,
    uniteLigne: ingredient.unit,
  );
}

/// Bloc « Coût avec vos prix » d'une fiche recette (CR1 à CR10) : calculé à
/// l'affichage avec les prix et les frais du lecteur, auteur ou non (CR7). Rien
/// n'est écrit sous `recipes/`.
class BlocCoutRecette extends ConsumerStatefulWidget {
  const BlocCoutRecette({super.key, required this.recipe, this.onCompleter});

  final Recipe recipe;

  /// « Compléter la recette », pour l'auteur seul.
  final VoidCallback? onCompleter;

  @override
  ConsumerState<BlocCoutRecette> createState() => _BlocCoutRecetteState();
}

class _BlocCoutRecetteState extends ConsumerState<BlocCoutRecette> {
  /// Titre « Coût avec vos prix », présent dans tous les états : le focus y
  /// revient après « Saisir le prix ». Hors du parcours de tabulation.
  final _titre = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _titre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(grantedAccessProvider)?.user.uid;
    if (uid == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          focusNode: _titre,
          child: const TitreSection(TextesCout.titreRecette),
        ),
        _contenu(context, uid),
      ],
    );
  }

  Widget _contenu(BuildContext context, String uid) {
    final pricesAsync = ref.watch(pricesProvider(uid));
    final feesAsync = ref.watch(feesProvider(uid));
    final etat = etatLecturePrix(
      prices: pricesAsync,
      fees: feesAsync,
      onRetry: () {
        ref.invalidate(pricesProvider(uid));
        ref.invalidate(feesProvider(uid));
      },
    );
    if (etat != null) return etat;
    final prices = pricesAsync.requireValue;
    final fees = feesAsync.requireValue;
    final content = widget.recipe.content;
    final evaluation = evaluerCoutRecette(
      content,
      prices: prices,
      fees: fees,
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(costReportsProvider),
      reportKey: widget.recipe.id,
    );
    final actions = ActionsRaisons(
      onPrix: (raison) => unawaited(_saisir(uid, prices, raison)),
      onCompleterRecette: widget.onCompleter,
      onMesPrix: () => unawaited(context.push(AppRoutes.prices)),
    );
    final aucunFrais = fees.documents.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch (evaluation) {
        CoutIndisponible() => [
          ...vueIndisponible(context, evaluation, actions),
          if (aucunFrais &&
              !evaluation.raisons.any((r) => r is CalculImpossible))
            const MentionAucunFrais(),
        ],
        CoutObtenu() => [
          LigneFiche(label: 'Total', value: formatEuros(evaluation.totalEur)),
          if (evaluation.perLitreEur case final perLitre?)
            LigneFiche(
              label: 'Par litre',
              value: formatEurosParLitre(perLitre),
            ),
          if (evaluation.perBottle33clEur case final perBottle?)
            LigneFiche(
              label: 'Bouteille de 33 cl',
              value: formatEuros(perBottle),
            ),
          TexteHypothese(hypotheseRecette(evaluation)),
          if (evaluation.aucunFrais) const MentionAucunFrais(),
          DetailCout(
            lignes: lignesDetail(evaluation),
            storageKey: 'cout-recette-${widget.recipe.id}',
          ),
        ],
      },
    );
  }

  Future<void> _saisir(
    String uid,
    ListeLue<Price> prices,
    RaisonPrix raison,
  ) async {
    final saved = await ouvrirPrixDeRaison(
      context,
      uid: uid,
      mesPrix: prices.valides,
      raison: raison,
    );
    // L'en-tête des manquants disparaît au dernier prix : le focus revient sur
    // le titre du bloc.
    if (saved && mounted) _titre.requestFocus();
  }
}

/// Hypothèse d'un coût de recette : « Pour 20 L · environ 61 bouteilles de
/// 33 cl » (CR2).
String hypotheseRecette(CoutObtenu cout) {
  final volume = cout.volumeL;
  final bouteilles = cout.bouteilles;
  return [
    if (volume != null) 'Pour ${formatLitres(volume)}',
    if (bouteilles != null) 'environ ${bouteilles.round()} bouteilles de 33 cl',
  ].join(' · ');
}
