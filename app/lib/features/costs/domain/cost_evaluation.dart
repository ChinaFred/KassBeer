import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../brews/domain/brew.dart';
import '../../recipes/domain/recipe.dart';
import 'brew_cost.dart';
import 'fee.dart';
import 'price.dart';

/// Coût d'une recette, estimation et figeage du coût d'un brassin, et ce qui les
/// empêche. Aucun widget : les écrans affichent ce que rendent ces fonctions.
///
/// Les formules (prix unitaire, regroupement, frais, totaux) sont celles de
/// `brewing/` (P3). La clé d'un ingrédient se dérive de son nom à la lecture
/// (`ingredientKey`) : aucun champ `key` d'une ligne de recette n'est lu (LI1).

/// Ingrédient à chiffrer : clé dérivée de sa nature et de son nom.
@immutable
class IngredientCout {
  const IngredientCout({
    required this.key,
    required this.nature,
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String key;
  final IngredientNature nature;

  /// Nom de la première ligne de cette clé.
  final String name;

  /// Grammes, ou sachets pour une levure ; lignes de même clé additionnées.
  final double quantity;
  final CostUnit unit;
}

/// Ingrédients de [content] dans l'ordre de la fiche : malts et sucres, houblons,
/// ajouts, levures (une ligne de levure vaut un sachet, H1). Une ligne sans
/// lettre ni chiffre n'a pas de clé : elle est écartée et [sansNom] est vrai
/// (LI10).
({List<IngredientCout> ingredients, bool sansNom}) ingredientsDeRecette(
  RecipeContent content,
) {
  final ingredients = <IngredientCout>[];
  var sansNom = false;
  void add(IngredientNature nature, String name, double quantity) {
    if (!isValidIngredientName(name)) {
      sansNom = true;
      return;
    }
    ingredients.add(
      IngredientCout(
        key: ingredientKey(nature, name),
        nature: nature,
        name: name.trim(),
        quantity: quantity,
        unit: purchaseUnitOf(nature),
      ),
    );
  }

  for (final f in content.fermentables) {
    add(IngredientNature.ofFermentable(f.kind), f.name, f.weightG);
  }
  for (final h in content.hops) {
    add(IngredientNature.hop, h.name, h.weightG);
  }
  for (final o in content.others) {
    add(IngredientNature.addition, o.name, o.weightG);
  }
  for (final y in content.yeasts) {
    add(IngredientNature.yeast, y.name, yeastSachetsPerLine);
  }
  return (ingredients: ingredients, sansNom: sansNom);
}

// ---------------------------------------------------------------- Raisons

/// Ce qui empêche d'afficher un montant, ou de figer un coût (CB8). Aucune n'est
/// stockée : elles se recalculent à l'affichage (CB10).
@immutable
sealed class RaisonCout {
  const RaisonCout();
}

/// Prix d'un ingrédient à saisir ou à corriger (LI7 à LI9).
sealed class RaisonPrix extends RaisonCout {
  const RaisonPrix(this.ingredient);

  final IngredientCout ingredient;
}

/// Aucun prix pour cette clé (LI7) : « Saisir le prix ».
class PrixManquant extends RaisonPrix {
  const PrixManquant(super.ingredient);
}

/// Prix dont l'unité ne convient pas à la ligne (LI8) : « Corriger le prix ».
class PrixUniteIncompatible extends RaisonPrix {
  const PrixUniteIncompatible(super.ingredient, this.price);

  final Price price;
}

/// Document de prix illisible, déjà rapporté (LI9) : « Corriger le prix ».
class PrixIllisible extends RaisonPrix {
  const PrixIllisible(super.ingredient);
}

/// Une ligne n'a pas de nom utilisable (LI10). Donnée attendue : aucun rapport.
class LigneSansNom extends RaisonCout {
  const LigneSansNom();
}

/// Volume en fermenteur de la recette non renseigné (CR5).
class VolumeNonRenseigne extends RaisonCout {
  const VolumeNonRenseigne();
}

/// Aucune ligne d'ingrédient (CR6) : jamais « 0,00 € ».
class AucunIngredient extends RaisonCout {
  const AucunIngredient();
}

/// Valeur refusée par `brewing/`, rapportée sans montant (CR9, SE4).
class CalculImpossible extends RaisonCout {
  const CalculImpossible();
}

/// Prix ou frais non chargés, ou absents du cache hors ligne (HL4) : jamais
/// « manquant ».
class PrixIndisponiblesHorsLigne extends RaisonCout {
  const PrixIndisponiblesHorsLigne();
}

/// Un document de frais est illisible (déjà rapporté) : il ne peut pas être
/// compté, et l'ignorer donnerait un total faux.
class FraisIllisible extends RaisonCout {
  const FraisIllisible();
}

/// Masse de resucrage saisie sans sa nature (CB8).
class SucreResucrageSansNature extends RaisonCout {
  const SucreResucrageSansNature();
}

/// Nombre de bouteilles absent avec au moins un frais par bouteille (CB8). Au
/// rattrapage, le brasseur peut figer sans ces frais (CB11).
class BouteillesNonRenseignees extends RaisonCout {
  const BouteillesNonRenseignees();
}

// ---------------------------------------------------------------- Résultats

/// Ligne du détail du coût (CR8) : un ingrédient regroupé ou un frais.
@immutable
class LigneCout {
  const LigneCout({
    required this.key,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.costEur,
  });

  /// Clé d'ingrédient, ou `frais-{id}`.
  final String key;
  final String name;
  final double quantity;
  final CostUnit unit;
  final double costEur;
}

/// Coût d'une recette ou estimation d'un brassin.
sealed class EvaluationCout {
  const EvaluationCout();
}

/// Tous les prix sont connus.
class CoutObtenu extends EvaluationCout {
  const CoutObtenu({
    required this.totalEur,
    required this.lignes,
    required this.volumeL,
    required this.perLitreEur,
    required this.perBottle33clEur,
    required this.bouteilles,
    required this.bouteillesEstimees,
    required this.perBottleEur,
    required this.aucunFrais,
  });

  /// Somme exacte des lignes (CR10 : l'écran arrondit ce total).
  final double totalEur;
  final List<LigneCout> lignes;

  /// Volume du prix par litre, ou `null`.
  final double? volumeL;
  final double? perLitreEur;

  /// Bouteille de 33 cl (recette, CR3), ou `null` sans volume.
  final double? perBottle33clEur;

  /// Bouteilles comptées pour les frais par bouteille : nombre réel, ou
  /// estimation de 33 cl ([bouteillesEstimees]) ; `null` sans l'un ni l'autre.
  final double? bouteilles;
  final bool bouteillesEstimees;

  /// Coût d'une bouteille réelle (CB13), ou `null` sans nombre réel.
  final double? perBottleEur;

  /// Aucun frais saisi (FR5) : le coût s'affiche avec sa mention.
  final bool aucunFrais;
}

/// Au moins une raison empêche le montant : aucun total, aucun sous-total (CR4).
class CoutIndisponible extends EvaluationCout {
  const CoutIndisponible(this.raisons);

  final List<RaisonCout> raisons;

  /// Nombre de prix à saisir ou à corriger (« 3 prix manquants »).
  int get prixManquants => raisons.whereType<RaisonPrix>().length;
}

/// Erreur d'un calcul de coût, rapportée à la place de l'erreur d'origine : seul
/// son type, aucun prix, quantité, total ni nom de poste (SE4, P13).
class CalculCoutRefuse implements Exception {
  const CalculCoutRefuse(this.type);

  final String type;

  @override
  String toString() => 'CalculCoutRefuse($type)';
}

// ---------------------------------------------------------------- Calcul

/// Calcul commun. Toute erreur levée est rapportée par [onRefus] et rend
/// [CalculImpossible] : l'embouteillage n'est jamais bloqué (CB8).
EvaluationCout _evaluer({
  required List<IngredientCout> ingredients,
  required bool sansNom,
  required ListeLue<Price>? prices,
  required ListeLue<Fee>? fees,
  required List<RaisonCout> raisonsAmont,
  required double? volumeParLitre,
  required int? bouteillesReelles,
  required double? volumeEstimation,
  required bool exigerBouteilles,
  required bool sansFraisParBouteille,
  required void Function(Object error, StackTrace stackTrace) onRefus,
}) {
  try {
    final raisons = <RaisonCout>[];
    final natures = {for (final i in ingredients) i.key: i.nature};
    final grouped = groupCostItems([
      for (final i in ingredients)
        CostItem(key: i.key, name: i.name, quantity: i.quantity, unit: i.unit),
    ]);
    final unitPrices = <String, double>{};
    var horsLigne = prices == null || fees == null;
    for (final g in grouped) {
      final ingredient = IngredientCout(
        key: g.key,
        nature: natures[g.key]!,
        name: g.name,
        quantity: g.quantity,
        unit: g.unit,
      );
      switch (prices?.chercher(g.key)) {
        case null:
          break;
        case DocumentTrouve<Price>(:final value):
          final price = unitPriceFor(
            priceEur: value.priceEur,
            quantity: value.quantity,
            purchaseUnit: value.unit,
            lineUnit: g.unit,
          );
          if (price == null) {
            raisons.add(PrixUniteIncompatible(ingredient, value));
          } else {
            unitPrices[g.key] = price;
          }
        case DocumentIllisibleTrouve<Price>():
          raisons.add(PrixIllisible(ingredient));
        case DocumentAbsent<Price>():
          raisons.add(PrixManquant(ingredient));
        case DocumentAbsentDuCache<Price>():
          horsLigne = true;
      }
    }
    if (sansNom) raisons.add(const LigneSansNom());
    if (ingredients.isEmpty && !sansNom) raisons.add(const AucunIngredient());
    raisons.addAll(raisonsAmont);

    final bouteilles =
        bouteillesReelles?.toDouble() ??
        (volumeEstimation == null ? null : bottles33clIn(volumeEstimation));
    final comptes = <Fee>[];
    if (fees != null) {
      if (fees.fromCache && fees.documents.isEmpty) horsLigne = true;
      if (fees.documents.any((d) => d is DocumentInvalide<Fee>)) {
        raisons.add(const FraisIllisible());
      }
      for (final fee in fees.valides) {
        if (fee.basis == FeeBasis.perBottle && bouteilles == null) {
          if (sansFraisParBouteille) continue;
          if (exigerBouteilles &&
              !raisons.any((r) => r is BouteillesNonRenseignees)) {
            raisons.add(const BouteillesNonRenseignees());
          }
          continue;
        }
        comptes.add(fee);
      }
    }
    if (horsLigne) raisons.add(const PrixIndisponiblesHorsLigne());
    if (raisons.isNotEmpty) return CoutIndisponible(List.unmodifiable(raisons));

    final feeQuantities = [
      for (final fee in comptes) feeQuantity(fee.basis, bottles: bouteilles),
    ];
    final result = computeCost(
      lines: [
        for (final g in grouped)
          CostLine(
            name: g.name,
            quantity: g.quantity,
            unitPrice: unitPrices[g.key],
          ),
        for (final (i, fee) in comptes.indexed)
          CostLine(
            name: fee.name,
            quantity: feeQuantities[i],
            unitPrice: fee.amountEur,
          ),
      ],
      volumeLitres: volumeParLitre,
    );
    if (result is! CostComputed) {
      // Chaque ligne a un prix : brewing/ ne peut pas rendre de manquant ici.
      throw StateError('prix manquant après vérification');
    }
    final lineCosts = result.lineCosts;
    final lignes = [
      for (final (i, g) in grouped.indexed)
        LigneCout(
          key: g.key,
          name: g.name,
          quantity: g.quantity,
          unit: g.unit,
          costEur: lineCosts[i],
        ),
      for (final (i, fee) in comptes.indexed)
        LigneCout(
          key: fee.lineKey,
          name: fee.name,
          quantity: feeQuantities[i],
          unit: fee.basis.unit,
          costEur: lineCosts[grouped.length + i],
        ),
    ];
    return CoutObtenu(
      totalEur: result.total,
      lignes: List.unmodifiable(lignes),
      volumeL: volumeParLitre,
      perLitreEur: result.perLitre,
      perBottle33clEur: result.perBottle33cl,
      bouteilles: bouteilles,
      bouteillesEstimees: bouteillesReelles == null && bouteilles != null,
      perBottleEur: bouteillesReelles == null
          ? null
          : costPerBottle(total: result.total, bottles: bouteillesReelles),
      aucunFrais: fees != null && fees.documents.isEmpty,
    );
  } catch (error, stackTrace) {
    onRefus(error, stackTrace);
    return const CoutIndisponible([CalculImpossible()]);
  }
}

/// Rapporteur d'un calcul refusé : une fois par [cle] dans [reported], avec une
/// erreur qui ne porte que le type de l'erreur d'origine (SE4).
void Function(Object, StackTrace) _rapporteur({
  required ErrorReportService errors,
  required Set<String> reported,
  required String feature,
  required String cle,
}) => (error, stackTrace) {
  if (!reported.add('$feature|$cle')) return;
  errors.reportError(
    feature: feature,
    error: CalculCoutRefuse('${error.runtimeType}'),
    stackTrace: stackTrace,
    context: 'type=${error.runtimeType}',
  );
};

/// Sucre de resucrage du brassin, à ajouter aux ingrédients (CB4) : aucun sans
/// masse ; `sansNature` quand la masse est saisie sans sa nature.
({IngredientCout? sucre, bool sansNature, bool sansNom}) _sucreDeResucrage(
  double? grams,
  String? name,
) {
  if (grams == null || grams <= 0) {
    return (sucre: null, sansNature: false, sansNom: false);
  }
  if (name == null || name.trim().isEmpty) {
    return (sucre: null, sansNature: true, sansNom: false);
  }
  if (!isValidIngredientName(name)) {
    return (sucre: null, sansNature: false, sansNom: true);
  }
  return (
    sucre: IngredientCout(
      key: ingredientKey(IngredientNature.sugar, name),
      nature: IngredientNature.sugar,
      name: name.trim(),
      quantity: grams,
      unit: CostUnit.gram,
    ),
    sansNature: false,
    sansNom: false,
  );
}

/// Coût d'une recette avec les prix et les frais du lecteur (CR1 à CR10) :
/// volume visé en fermenteur, bouteilles de 33 cl estimées sur ce volume (Q3).
/// N'écrit rien. [prices] ou [fees] nul : pas encore lus.
///
/// Un calcul refusé par `brewing/` est rapporté une fois par [reportKey]
/// (`costs.calculation`).
EvaluationCout evaluerCoutRecette(
  RecipeContent content, {
  required ListeLue<Price>? prices,
  required ListeLue<Fee>? fees,
  required ErrorReportService errors,
  required Set<String> reported,
  required String reportKey,
}) {
  final (:ingredients, :sansNom) = ingredientsDeRecette(content);
  final volume = content.batchVolumeL;
  return _evaluer(
    ingredients: ingredients,
    sansNom: sansNom,
    prices: prices,
    fees: fees,
    raisonsAmont: [if (volume == null) const VolumeNonRenseigne()],
    volumeParLitre: volume,
    bouteillesReelles: null,
    volumeEstimation: volume,
    exigerBouteilles: false,
    sansFraisParBouteille: false,
    onRefus: _rapporteur(
      errors: errors,
      reported: reported,
      feature: 'costs.calculation',
      cle: reportKey,
    ),
  );
}

/// Ingrédients d'un brassin : copie figée de la recette, puis sucre de
/// resucrage.
({List<IngredientCout> ingredients, bool sansNom, List<RaisonCout> raisons})
_ingredientsDuBrassin(
  RecipeContent recipe,
  double? primingSugarG,
  String? primingSugarName,
) {
  final (:ingredients, :sansNom) = ingredientsDeRecette(recipe);
  final sucre = _sucreDeResucrage(primingSugarG, primingSugarName);
  return (
    ingredients: [...ingredients, ?sucre.sucre],
    sansNom: sansNom || sucre.sansNom,
    raisons: [if (sucre.sansNature) const SucreResucrageSansNature()],
  );
}

/// Estimation du coût d'un brassin non figé avec les prix actuels du lecteur
/// (CB2) : copie figée de la recette et sucre de resucrage ; `bottles_count`,
/// sinon bouteilles de 33 cl estimées sur le volume de la copie. N'écrit rien.
EvaluationCout evaluerEstimationBrassin(
  Brew brew, {
  required ListeLue<Price>? prices,
  required ListeLue<Fee>? fees,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  final (:ingredients, :sansNom, :raisons) = _ingredientsDuBrassin(
    brew.recipe,
    brew.primingSugarG,
    brew.primingSugarName,
  );
  final volume = brew.recipe.batchVolumeL;
  return _evaluer(
    ingredients: ingredients,
    sansNom: sansNom,
    prices: prices,
    fees: fees,
    raisonsAmont: [
      ...raisons,
      if (volume == null && brew.bottlesCount == null)
        const VolumeNonRenseigne(),
    ],
    volumeParLitre: volume,
    bouteillesReelles: brew.bottlesCount,
    volumeEstimation: volume,
    exigerBouteilles: false,
    sansFraisParBouteille: false,
    onRefus: _rapporteur(
      errors: errors,
      reported: reported,
      feature: 'costs.calculation',
      cle: 'brew-${brew.id}',
    ),
  );
}

// ---------------------------------------------------------------- Figeage

/// Coût à figer, ou ce qui l'empêche.
sealed class EvaluationFigeage {
  const EvaluationFigeage();
}

/// Tout est connu : [cout] est le document à écrire.
class FigeagePossible extends EvaluationFigeage {
  const FigeagePossible(this.cout);

  final BrewCost cout;
}

/// Au moins une raison de CB8 empêche le figeage.
class FigeageImpossible extends EvaluationFigeage {
  const FigeageImpossible(this.raisons);

  final List<RaisonCout> raisons;

  /// Vrai si seul le nombre de bouteilles manque : « Figer le coût » ouvre
  /// « Figer sans les frais par bouteille ? » (CB11).
  bool get seulementBouteilles =>
      raisons.isNotEmpty && raisons.every((r) => r is BouteillesNonRenseignees);
}

/// Coût réel d'un brassin à figer avec les prix et les frais du lecteur (CB4) :
/// ingrédients de la copie figée regroupés par clé, une levure pour un sachet,
/// sucre de resucrage quand sa masse dépasse 0, frais avec [bottlesCount]. Le
/// volume du prix par litre est [packagedVolumeL] seul (CB14). `adjustments`
/// n'entre pas dans le calcul.
///
/// [sansFraisParBouteille] : le brasseur a confirmé « Figer sans les frais par
/// bouteille » (CB11). [now] est l'heure de l'appareil (HL3). N'écrit rien ; un
/// calcul refusé est rapporté (`costs.freeze_failed`) et rend
/// [FigeageImpossible] avec [CalculImpossible].
EvaluationFigeage evaluerFigeage({
  required String brewId,
  required RecipeContent recipe,
  required int? bottlesCount,
  required double? packagedVolumeL,
  required double? primingSugarG,
  required String? primingSugarName,
  required ListeLue<Price>? prices,
  required ListeLue<Fee>? fees,
  required FreezeKind kind,
  required DateTime now,
  bool sansFraisParBouteille = false,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  final onRefus = _rapporteur(
    errors: errors,
    reported: reported,
    feature: 'costs.freeze_failed',
    cle: brewId,
  );
  final (:ingredients, :sansNom, :raisons) = _ingredientsDuBrassin(
    recipe,
    primingSugarG,
    primingSugarName,
  );
  final evaluation = _evaluer(
    ingredients: ingredients,
    sansNom: sansNom,
    prices: prices,
    fees: fees,
    raisonsAmont: raisons,
    volumeParLitre: packagedVolumeL,
    bouteillesReelles: bottlesCount,
    volumeEstimation: null,
    exigerBouteilles: true,
    sansFraisParBouteille: sansFraisParBouteille,
    onRefus: onRefus,
  );
  switch (evaluation) {
    case CoutIndisponible(:final raisons):
      return FigeageImpossible(raisons);
    case final CoutObtenu detail:
      if (detail.lignes.length > kMaxBrewCostLines) {
        onRefus(
          StateError('plus de $kMaxBrewCostLines lignes'),
          StackTrace.current,
        );
        return const FigeageImpossible([CalculImpossible()]);
      }
      return FigeagePossible(
        BrewCost(
          brewId: brewId,
          totalEur: detail.totalEur,
          lines: [
            for (final l in detail.lignes)
              BrewCostLine(
                key: l.key,
                name: l.name,
                quantity: l.quantity,
                unit: l.unit,
                costEur: l.costEur,
              ),
          ],
          computedAt: now,
          freezeKind: kind,
          bottlesCount: bottlesCount,
          packagedVolumeL: packagedVolumeL,
          primingSugarG: primingSugarG,
          primingSugarName: primingSugarName,
        ),
      );
  }
}

/// [evaluerFigeage] sur les valeurs d'embouteillage enregistrées de [brew] :
/// rattrapage (« Figer le coût », CB10) et « Recalculer » (CB16).
EvaluationFigeage evaluerFigeageDuBrassin(
  Brew brew, {
  required ListeLue<Price>? prices,
  required ListeLue<Fee>? fees,
  required FreezeKind kind,
  required DateTime now,
  bool sansFraisParBouteille = false,
  required ErrorReportService errors,
  required Set<String> reported,
}) => evaluerFigeage(
  brewId: brew.id,
  recipe: brew.recipe,
  bottlesCount: brew.bottlesCount,
  packagedVolumeL: brew.packagedVolumeL,
  primingSugarG: brew.primingSugarG,
  primingSugarName: brew.primingSugarName,
  prices: prices,
  fees: fees,
  kind: kind,
  now: now,
  sansFraisParBouteille: sansFraisParBouteille,
  errors: errors,
  reported: reported,
);

/// Vrai si un coût figé a été lu pour ce brassin, lisible ou non.
bool coutFigeLu(RechercheDocument<BrewCost>? cout) =>
    cout is DocumentTrouve<BrewCost> ||
    cout is DocumentIllisibleTrouve<BrewCost>;

/// Déclencheur unique du figeage automatique (CB3) : premier enregistrement de
/// l'embouteillage ([modification] faux), aucune date d'embouteillage avant
/// l'écriture ([bottledAtAvant] : `bottled_at` survit à un retour en arrière,
/// CB15), et aucun coût figé déjà lu ([coutLu]).
bool doitFigerAuPremierEmbouteillage({
  required bool modification,
  required DateTime? bottledAtAvant,
  required RechercheDocument<BrewCost>? coutLu,
}) => !modification && bottledAtAvant == null && !coutFigeLu(coutLu);

/// Statuts où « Figer le coût » sert au rattrapage (CB10).
const kStatutsDeRattrapage = {
  BrewStatus.conditioning,
  BrewStatus.done,
  BrewStatus.abandoned,
};

/// Vrai si « Figer le coût » s'affiche (CB10) : propriétaire, statut de
/// rattrapage, aucun coût figé. Le bouton reste désactivé tant que
/// [evaluerFigeageDuBrassin] rend des raisons, sauf [FigeageImpossible.seulementBouteilles].
bool figerLeCoutPropose({
  required Brew brew,
  required String? readerUid,
  required RechercheDocument<BrewCost>? coutLu,
}) =>
    brew.ownerUid == readerUid &&
    kStatutsDeRattrapage.contains(brew.status) &&
    (coutLu is DocumentAbsent<BrewCost> ||
        coutLu is DocumentAbsentDuCache<BrewCost>);

/// Vrai si « Recalculer avec mes prix actuels » s'affiche (CB16, CB20) :
/// propriétaire et coût figé lu, lisible ou non.
bool recalculerPropose({
  required Brew brew,
  required String? readerUid,
  required RechercheDocument<BrewCost>? coutLu,
}) => brew.ownerUid == readerUid && coutFigeLu(coutLu);

// ---------------------------------------------------------------- Écart

/// Valeur d'embouteillage gardée par un coût figé (CB15).
enum ChampEmbouteillage { bouteilles, volume, sucreResucrage, natureSucre }

/// Valeur d'embouteillage changée depuis le figeage : [figee] dans le coût,
/// [actuelle] dans `brews/{id}`.
@immutable
class EcartEmbouteillage {
  const EcartEmbouteillage(this.champ, this.figee, this.actuelle);

  final ChampEmbouteillage champ;
  final Object? figee;
  final Object? actuelle;
}

/// Écarts entre les valeurs d'embouteillage de [cout] et celles de [brew]
/// (CB15) ; vide si rien n'a changé. Un changement de date seul ne compte pas.
List<EcartEmbouteillage> ecartsDepuisFigeage(BrewCost cout, Brew brew) => [
  if (cout.bottlesCount != brew.bottlesCount)
    EcartEmbouteillage(
      ChampEmbouteillage.bouteilles,
      cout.bottlesCount,
      brew.bottlesCount,
    ),
  if (cout.packagedVolumeL != brew.packagedVolumeL)
    EcartEmbouteillage(
      ChampEmbouteillage.volume,
      cout.packagedVolumeL,
      brew.packagedVolumeL,
    ),
  if (cout.primingSugarG != brew.primingSugarG)
    EcartEmbouteillage(
      ChampEmbouteillage.sucreResucrage,
      cout.primingSugarG,
      brew.primingSugarG,
    ),
  if (cout.primingSugarName != brew.primingSugarName)
    EcartEmbouteillage(
      ChampEmbouteillage.natureSucre,
      cout.primingSugarName,
      brew.primingSugarName,
    ),
];
