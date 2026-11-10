import 'package:brewing/brewing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Bornes d'un prix d'achat (`firestore.rules`, PR2, PR5).
const kPriceNameMaxLength = 120;
const kPriceMaxEur = 100000.0;
const kPurchaseQuantityMax = 1e9;

/// Seuils de « Prix inhabituel : vérifiez la quantité. » (PR6), en euros par
/// gramme, par sachet ou par litre. Avertissement seul, sans blocage ; à ajuster
/// à l'usage (hypothèse H4).
const kUnusualMaltOrSugarEurPerGram = 0.05;
const kUnusualHopOrAdditionEurPerGram = 0.5;
const kUnusualYeastEurPerSachet = 50.0;

/// Seuil d'un prix au litre (houblon extrait, ajout liquide) : 1 000 €/L
/// (hypothèse H4, v0.1.17).
const kUnusualEurPerLitre = 1000.0;

/// Forme d'un identifiant de prix, celle des règles : préfixe d'une nature puis
/// segments en minuscules et chiffres, 100 caractères au plus (`ingredientKey`).
final _priceKeyFormat = RegExp(
  r'^(malt|sucre|houblon|levure|ajout)(-[a-z0-9]+)*$',
);

/// Document `users/{uid}/prices/{key}` : ce que le brasseur a payé pour une
/// quantité d'un ingrédient. Privé à son propriétaire (P5).
@immutable
class Price {
  const Price({
    required this.key,
    required this.name,
    required this.priceEur,
    required this.quantity,
    required this.unit,
    this.updatedAt,
    this.hasPendingWrites = false,
  });

  /// Clé d'ingrédient, identifiant du document (`ingredientKey`).
  final String key;

  /// Nom saisi.
  final String name;

  /// Prix payé, en euros.
  final double priceEur;

  /// Quantité achetée : grammes, sachets pour une levure, ou litres pour un
  /// houblon ou un ajout acheté au volume (v0.1.17).
  final double quantity;

  /// [CostUnit.gram], [CostUnit.unit] ou [CostUnit.litre].
  final CostUnit unit;

  /// `null` tant qu'une écriture locale attend le serveur.
  final DateTime? updatedAt;
  final bool hasPendingWrites;

  /// Nature lue sur le préfixe de la clé. Une clé lue de Firestore suit le
  /// format des règles ([Price.fromFirestore]) et une clé saisie vient
  /// d'`ingredientKey` : toutes deux portent le préfixe d'une nature.
  IngredientNature get nature => natureOfKey(key)!;

  /// Prix unitaire en euros par gramme, par sachet ou par litre (PR7,
  /// `brewing/`).
  double get unitPriceEur => unitPrice(priceEur: priceEur, quantity: quantity);

  /// Lit le document ; lève [DocumentIllisible] si un champ manque, sort des
  /// bornes des règles, ou si l'unité n'est pas `g`, `unit` ni `l`. Aucune valeur
  /// reçue n'entre dans l'erreur.
  factory Price.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    if (id.length > maxIngredientKeyLength || !_priceKeyFormat.hasMatch(id)) {
      // L'identifiant dérive du nom : il n'entre pas dans l'erreur.
      throw const DocumentIllisible('id', 'clé hors format');
    }
    final read = LecteurChamps(data);
    final priceEur = read.nombre('price_eur');
    if (priceEur < 0 || priceEur > kPriceMaxEur) {
      throw const DocumentIllisible('price_eur', 'prix hors limites');
    }
    final quantity = read.nombre('quantity');
    if (quantity <= 0 || quantity > kPurchaseQuantityMax) {
      throw const DocumentIllisible('quantity', 'quantité hors limites');
    }
    return Price(
      key: id,
      name: read.texte('name'),
      priceEur: priceEur,
      quantity: quantity,
      unit: _purchaseUnit(data['unit']),
      updatedAt: read.date('updated_at'),
      hasPendingWrites: hasPendingWrites,
    );
  }

  /// Champs à écrire ; `updated_at` est posée par le serveur.
  Map<String, Object?> toFirestore() => {
    'name': name.trim(),
    'price_eur': priceEur,
    'quantity': quantity,
    'unit': unit.storedValue,
    'updated_at': FieldValue.serverTimestamp(),
  };
}

CostUnit _purchaseUnit(Object? value) {
  for (final unit in CostUnit.purchaseUnits) {
    if (unit.storedValue == value) return unit;
  }
  // `kwh`, prévu avant la v0.5, ne chiffre aucune ligne de recette.
  throw const DocumentIllisible('unit', 'unité d\'achat inconnue');
}

/// Unité d'achat par défaut d'un ingrédient de nature [nature] : sachets pour
/// une levure, grammes sinon (PR3).
CostUnit purchaseUnitOf(IngredientNature nature) =>
    nature == IngredientNature.yeast ? CostUnit.unit : CostUnit.gram;

/// Unités d'achat proposées pour [nature] : sachets pour une levure ; grammes
/// ou litres pour un houblon ou un ajout, qu'une recette peut compter en volume
/// (décision du 2026-11-10) ; grammes pour un malt ou un sucre.
List<CostUnit> purchaseUnitsOf(IngredientNature nature) => switch (nature) {
  IngredientNature.yeast => const [CostUnit.unit],
  IngredientNature.hop ||
  IngredientNature.addition => const [CostUnit.gram, CostUnit.litre],
  IngredientNature.malt || IngredientNature.sugar => const [CostUnit.gram],
};

/// Vrai si [unitPriceEur] (euros par gramme, par sachet pour une levure, ou par
/// litre si [unit] vaut [CostUnit.litre]) dépasse le seuil de PR6 pour [nature].
bool isUnusualPrice(
  IngredientNature nature,
  double unitPriceEur, {
  CostUnit unit = CostUnit.gram,
}) =>
    unitPriceEur >
    switch (nature) {
      _ when unit == CostUnit.litre => kUnusualEurPerLitre,
      IngredientNature.malt ||
      IngredientNature.sugar => kUnusualMaltOrSugarEurPerGram,
      IngredientNature.hop ||
      IngredientNature.addition => kUnusualHopOrAdditionEurPerGram,
      IngredientNature.yeast => kUnusualYeastEurPerSachet,
    };
