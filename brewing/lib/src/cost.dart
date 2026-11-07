import 'errors.dart';

/// Volume d'une bouteille de référence, en litres (33 cl).
const double referenceBottleLitres = 0.33;

/// Une ligne de coût : une quantité et son prix unitaire.
///
/// [quantity] s'exprime dans l'unité du prix (g pour un prix au gramme, L pour
/// un prix au litre, 1 pour un forfait). Le prix vient du lecteur
/// (`users/{uid}/…`) : le paquet ne stocke aucun prix. [unitPrice] nul veut dire
/// « prix inconnu ».
class CostLine {
  /// Crée une ligne de coût.
  CostLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  }) {
    requireNonNegative('quantity', quantity);
    final price = unitPrice;
    if (price != null) requireNonNegative('unitPrice', price);
  }

  /// Nom de l'ingrédient ou du poste.
  final String name;

  /// Quantité, dans l'unité du prix.
  final double quantity;

  /// Prix unitaire en euros, ou nul s'il est inconnu.
  final double? unitPrice;
}

/// Résultat d'un calcul de coût.
sealed class CostResult {
  const CostResult();
}

/// Coût calculé : tous les prix sont connus.
class CostComputed extends CostResult {
  /// Crée le résultat.
  const CostComputed({
    required this.total,
    required this.perLitre,
    required this.perBottle33cl,
  });

  /// Coût total en euros.
  final double total;

  /// Coût par litre de bière obtenue.
  final double perLitre;

  /// Coût d'une bouteille de 33 cl.
  final double perBottle33cl;
}

/// Coût absent : au moins un prix manque.
class CostUnavailable extends CostResult {
  /// Crée le résultat.
  const CostUnavailable(this.linesWithoutPrice);

  /// Noms des lignes sans prix, dans l'ordre reçu.
  final List<String> linesWithoutPrice;
}

/// Coût d'un brassin ou d'une recette pour [volumeLitres] litres de bière.
///
/// Un seul prix manquant rend le coût absent ([CostUnavailable]) : aucun prix
/// n'est remplacé par zéro ni par une valeur par défaut.
CostResult computeCost({
  required List<CostLine> lines,
  required double volumeLitres,
}) {
  requirePositive('volumeLitres', volumeLitres);
  final missing = <String>[];
  var total = 0.0;
  for (final line in lines) {
    final price = line.unitPrice;
    if (price == null) {
      missing.add(line.name);
    } else {
      total += line.quantity * price;
    }
  }
  if (missing.isNotEmpty) return CostUnavailable(List.unmodifiable(missing));
  final perLitre = total / volumeLitres;
  return CostComputed(
    total: total,
    perLitre: perLitre,
    perBottle33cl: perLitre * referenceBottleLitres,
  );
}
