/// Affichage des montants, quantités et prix unitaires de « Mes prix » et des
/// blocs Coût : virgule décimale, espace insécable avant l'unité.
///
/// Conversion d'affichage seulement (grammes en kilogrammes, euros par gramme en
/// euros par kilogramme) : les calculs de coût vivent dans `brewing/` (P3).
library;

import 'package:brewing/brewing.dart';

import '../../../core/presentation/formats.dart';
import '../domain/price.dart';

/// Grammes dans un kilogramme : conversion d'affichage.
const double _grammesParKg = 1000;

/// Montant calculé, au centime : « 40,84 € » (CR10).
String formatEuros(double eur) =>
    '${formatNombre(eur, decimales: 2, fixe: true)}$nbsp€';

/// Montant saisi, tel que saisi jusqu'à 4 décimales, au moins 2 : « 47,50 € »,
/// « 0,0525 € ».
String formatEurosSaisis(double eur) {
  var text = formatNombre(eur, decimales: 4);
  final comma = text.indexOf(',');
  if (comma < 0) {
    text = '$text,00';
  } else if (text.length - comma - 1 < 2) {
    text = '${text}0';
  }
  return '$text$nbsp€';
}

/// Coût par litre : « 2,15 €/L ».
String formatEurosParLitre(double eur) =>
    '${formatNombre(eur, decimales: 2, fixe: true)}$nbsp€/L';

/// Nature au singulier : « Malt ».
String libelleNature(IngredientNature nature) => switch (nature) {
  IngredientNature.malt => 'Malt',
  IngredientNature.sugar => 'Sucre',
  IngredientNature.hop => 'Houblon',
  IngredientNature.yeast => 'Levure',
  IngredientNature.addition => 'Ajout',
};

/// Nature au pluriel, titre d'une section de « Mes prix » : « Malts ».
String libelleNaturePluriel(IngredientNature nature) => switch (nature) {
  IngredientNature.malt => 'Malts',
  IngredientNature.sugar => 'Sucres',
  IngredientNature.hop => 'Houblons',
  IngredientNature.yeast => 'Levures',
  IngredientNature.addition => 'Ajouts',
};

/// Nature en minuscules, après « de » : « Reprendre un prix de malt ».
String libelleNatureMinuscule(IngredientNature nature) =>
    libelleNature(nature).toLowerCase();

/// Sachets accordés : « 1 sachet », « 5 sachets ».
String formatSachets(double sachets) =>
    '${formatNombre(sachets, decimales: 0)}$nbsp'
    'sachet${sachets > 1 ? 's' : ''}';

/// Masse en grammes : en kilogrammes à partir de 1 000 g (« 25 kg »), sinon en
/// grammes (« 500 g »).
String formatMasse(double grams) => grams >= _grammesParKg
    ? '${formatNombre(grams / _grammesParKg, decimales: 3)}${nbsp}kg'
    : '${formatNombre(grams, decimales: 1)}${nbsp}g';

/// Masse lue par un lecteur d'écran : « 5 kilogrammes », « 500 grammes ».
String masseParlee(double grams) => grams >= _grammesParKg
    ? '${formatNombre(grams / _grammesParKg, decimales: 3)} kilogrammes'
    : '${formatNombre(grams, decimales: 1)} grammes';

/// Quantité d'un ingrédient ou d'un achat dans [unit] : « 5 kg », « 1 sachet ».
String formatQuantite(double quantity, CostUnit unit) => switch (unit) {
  CostUnit.unit => formatSachets(quantity),
  CostUnit.litre => formatVolumeLigne(quantity),
  _ => formatMasse(quantity),
};

/// [formatQuantite] pour un lecteur d'écran.
String quantiteParlee(double quantity, CostUnit unit) => switch (unit) {
  CostUnit.unit => formatSachets(quantity),
  CostUnit.litre => volumeParle(quantity),
  _ => masseParlee(quantity),
};

/// Volume lu par un lecteur d'écran, au singulier sous 2 : « 1 millilitre »,
/// « 5 millilitres », « 1 litre », « 1,5 litre », « 2 litres ».
String volumeParle(double litres) {
  final (valeur, unite) = litres < 1
      ? (litres * 1000, 'millilitre')
      : (litres, 'litre');
  final texte = formatNombre(valeur, decimales: litres < 1 ? 1 : 2);
  return '$texte $unite${valeur < 2 ? '' : 's'}';
}

/// Achat lu par un lecteur d'écran : « 47,50 € les 25 kilogrammes »,
/// « 6,50 € les 100 millilitres », « 3,99 € le sachet ».
String achatParle(Price price) {
  final texte = formatAchat(price);
  final montant = formatEurosSaisis(price.priceEur);
  if (!texte.startsWith('$montant les ')) return texte;
  return '$montant les ${quantiteParlee(price.quantity, price.unit)}';
}

/// Prix unitaire lu par un lecteur d'écran : « 1,90 € le kilogramme »,
/// « 65,00 € le litre », « 0,80 € le sachet ».
String prixUnitaireParle(Price price) {
  final texte = formatPrixUnitaire(price);
  final valeur = texte.substring(0, texte.indexOf('€') + 1);
  return '$valeur ${switch (price.unit) {
    CostUnit.unit => 'le sachet',
    CostUnit.litre => 'le litre',
    _ => 'le kilogramme',
  }}';
}

/// Prix unitaire de [price] : « 1,90 €/kg », « 0,80 €/sachet » (PR7).
String formatPrixUnitaire(Price price) =>
    formatPrixUnitaireDe(price.unitPriceEur, price.unit);

/// Prix unitaire [eurParUnite] (euros par gramme, par sachet ou par litre)
/// affiché par kilogramme, par sachet ou par litre.
String formatPrixUnitaireDe(double eurParUnite, CostUnit unit) =>
    switch (unit) {
      CostUnit.unit =>
        '${formatNombre(eurParUnite, decimales: 2, fixe: true)}$nbsp€/sachet',
      CostUnit.litre =>
        '${formatNombre(eurParUnite, decimales: 2, fixe: true)}$nbsp€/L',
      _ =>
        '${formatNombre(eurParUnite * _grammesParKg, decimales: 2, fixe: true)}'
            '$nbsp€/kg',
    };

/// Achat : « 47,50 € les 25 kg », « 3,99 € le sachet ».
String formatAchat(Price price) {
  final quantity = price.quantity;
  final unit = price.unit;
  final un = switch (unit) {
    CostUnit.unit || CostUnit.litre => quantity == 1,
    _ => quantity == _grammesParKg,
  };
  final quantite = un
      ? switch (unit) {
          CostUnit.unit => 'le sachet',
          CostUnit.litre => 'le litre',
          _ => 'le kg',
        }
      : 'les ${formatQuantite(quantity, unit)}';
  return '${formatEurosSaisis(price.priceEur)} $quantite';
}

/// Base d'un frais : « par brassin », « par bouteille ».
String libelleBase(FeeBasis basis) => switch (basis) {
  FeeBasis.perBrew => 'par brassin',
  FeeBasis.perBottle => 'par bouteille',
};

/// Bouteilles accordées : « 1 bouteille », « 50 bouteilles ».
String formatBouteilles(num bouteilles) =>
    '${formatNombre(bouteilles.toDouble(), decimales: 0)}$nbsp'
    'bouteille${bouteilles > 1 ? 's' : ''}';

/// Texte de plusieurs parties séparées par « · », et sa lecture sans le point
/// médian (accessibilité : « · » n'est pas lu).
({String texte, String parle}) parties(List<String> items) =>
    (texte: items.join(' · '), parle: items.join(', '));
