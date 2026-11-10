import 'errors.dart';

// Aucune erreur levée ici ne porte la valeur reçue : un prix, un montant ou une
// quantité saisis par le brasseur finiraient dans error_reports/, que l'admin lit
// (P13). Les vérifications passent par requirePositiveHidden et
// requireNonNegativeHidden.

/// Volume d'une bouteille de référence, en litres (33 cl).
const double referenceBottleLitres = 0.33;

/// Sachets comptés pour une ligne de levure : une recette ne donne pas de
/// quantité de levure, et chaque fiche Excel en compte un (hypothèse H1).
const double yeastSachetsPerLine = 1;

/// Unité d'une quantité chiffrée.
enum CostUnit {
  /// Gramme : malt, sucre, houblon, ajout.
  gram('g'),

  /// Unité : sachet de levure.
  unit('unit'),

  /// Litre : ajout ou houblon mesuré en volume, et son prix au litre
  /// (décision du 2026-11-10). Une ligne en litres ne se chiffre qu'avec un prix
  /// au litre ([unitPriceFor]) : aucune densité n'est supposée.
  litre('l'),

  /// Forfait par brassin (frais).
  brew('brew'),

  /// Par bouteille (frais).
  bottle('bottle');

  const CostUnit(this.storedValue);

  /// Valeur stockée (`g`, `unit`, `l`, `brew`, `bottle`).
  final String storedValue;

  /// Unités d'un prix d'achat : grammes, sachets ou litres.
  static const List<CostUnit> purchaseUnits = [gram, unit, litre];

  /// Unité de la valeur stockée [value] ; lève [BrewingInputException] sans le
  /// texte reçu si elle est inconnue.
  static CostUnit fromStored(String value, [String field = 'unit']) =>
      enumFromStored(values, (u) => u.storedValue, field, value);
}

/// Base d'un frais hors ingrédients.
enum FeeBasis {
  /// Une fois par brassin.
  perBrew('per_brew'),

  /// Une fois par bouteille.
  perBottle('per_bottle');

  const FeeBasis(this.storedValue);

  /// Valeur stockée (`per_brew`, `per_bottle`).
  final String storedValue;

  /// Unité de la ligne de coût d'un frais de cette base.
  CostUnit get unit => switch (this) {
    FeeBasis.perBrew => CostUnit.brew,
    FeeBasis.perBottle => CostUnit.bottle,
  };

  /// Base de la valeur stockée [value] ; lève [BrewingInputException] sans le
  /// texte reçu si elle est inconnue.
  static FeeBasis fromStored(String value, [String field = 'basis']) =>
      enumFromStored(values, (b) => b.storedValue, field, value);
}

/// Prix unitaire d'un achat : [priceEur] payés pour [quantity] grammes,
/// sachets ou litres. Un prix nul est un prix connu (eau de pluie, ingrédient offert).
///
/// Lève [BrewingInputException], sans la valeur reçue, pour un prix négatif ou
/// non fini et pour une quantité nulle, négative ou non finie.
double unitPrice({required double priceEur, required double quantity}) {
  requireNonNegativeHidden('priceEur', priceEur);
  requirePositiveHidden('quantity', quantity);
  return priceEur / quantity;
}

/// Prix unitaire d'un achat en [purchaseUnit] pour une ligne en [lineUnit], ou
/// `null` si les deux unités diffèrent : un prix au sachet ne chiffre pas des
/// grammes, un prix au gramme ne chiffre pas des litres (et l'inverse).
///
/// Lève [BrewingInputException] comme [unitPrice].
double? unitPriceFor({
  required double priceEur,
  required double quantity,
  required CostUnit purchaseUnit,
  required CostUnit lineUnit,
}) {
  final price = unitPrice(priceEur: priceEur, quantity: quantity);
  return purchaseUnit == lineUnit ? price : null;
}

/// Ingrédient à chiffrer, avant regroupement : sa clé, son nom affiché, sa
/// quantité dans [unit].
class CostItem {
  /// Crée l'ingrédient ; lève [BrewingInputException], sans la valeur reçue,
  /// pour une quantité négative ou non finie.
  CostItem({
    required this.key,
    required this.name,
    required this.quantity,
    required this.unit,
  }) {
    requireNonNegativeHidden('quantity', quantity);
  }

  /// Clé d'ingrédient (`ingredientKey`).
  final String key;

  /// Nom affiché.
  final String name;

  /// Quantité, dans [unit].
  final double quantity;

  /// Unité de la quantité.
  final CostUnit unit;
}

/// Regroupe les ingrédients de même clé : quantités additionnées, nom et place
/// du premier. Cascade 20 g et Cascade 30 g donnent Cascade 50 g ; sans prix,
/// « Cascade » n'est nommé qu'une fois.
///
/// Lève [BrewingInputException] si deux ingrédients de même clé n'ont pas la
/// même unité.
List<CostItem> groupCostItems(List<CostItem> items) {
  final grouped = <String, CostItem>{};
  for (final item in items) {
    final previous = grouped[item.key];
    if (previous == null) {
      grouped[item.key] = item;
      continue;
    }
    if (previous.unit != item.unit) {
      throw const BrewingInputException(
        'items',
        null,
        'unités différentes pour une même clé',
      );
    }
    grouped[item.key] = CostItem(
      key: previous.key,
      name: previous.name,
      quantity: previous.quantity + item.quantity,
      unit: previous.unit,
    );
  }
  return List.unmodifiable(grouped.values);
}

/// Bouteilles de 33 cl contenues dans [volumeLitres] litres, sans arrondi.
///
/// Lève [BrewingInputException], sans la valeur reçue, pour un volume nul,
/// négatif ou non fini.
double bottles33clIn(double volumeLitres) {
  requirePositiveHidden('volumeLitres', volumeLitres);
  return volumeLitres / referenceBottleLitres;
}

/// Quantité de la ligne d'un frais : 1 pour un frais par brassin, [bottles] pour
/// un frais par bouteille.
///
/// Lève [BrewingInputException] pour un frais par bouteille sans nombre de
/// bouteilles, ou avec un nombre nul, négatif ou non fini.
double feeQuantity(FeeBasis basis, {required double? bottles}) {
  switch (basis) {
    case FeeBasis.perBrew:
      return 1;
    case FeeBasis.perBottle:
      if (bottles == null) {
        throw const BrewingInputException(
          'bottles',
          null,
          'nombre de bouteilles requis pour un frais par bouteille',
        );
      }
      requirePositiveHidden('bottles', bottles);
      return bottles;
  }
}

/// Une ligne de coût : une quantité et son prix unitaire.
///
/// [quantity] s'exprime dans l'unité du prix (g pour un prix au gramme, sachets
/// pour une levure, 1 pour un frais par brassin, bouteilles pour un frais par
/// bouteille). Le prix vient du lecteur (`users/{uid}/…`) : le paquet ne stocke
/// aucun prix. [unitPrice] nul veut dire « prix inconnu ».
class CostLine {
  /// Crée une ligne de coût ; lève [BrewingInputException], sans la valeur
  /// reçue, pour une quantité ou un prix négatif ou non fini.
  CostLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  }) {
    requireNonNegativeHidden('quantity', quantity);
    final price = unitPrice;
    if (price != null) requireNonNegativeHidden('unitPrice', price);
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
    required this.lineCosts,
    required this.perLitre,
    required this.perBottle33cl,
  });

  /// Coût total en euros : somme exacte des lignes, sans arrondi.
  final double total;

  /// Coût de chaque ligne (quantité × prix unitaire), dans l'ordre reçu.
  final List<double> lineCosts;

  /// Coût par litre de bière, ou `null` sans volume.
  final double? perLitre;

  /// Coût d'une bouteille de 33 cl, ou `null` sans volume.
  final double? perBottle33cl;
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
/// n'est remplacé par zéro ni par une valeur par défaut. Sans volume
/// ([volumeLitres] nul), le total est calculé, sans prix par litre ni par
/// bouteille de 33 cl.
///
/// Lève [BrewingInputException], sans la valeur reçue, pour un volume nul,
/// négatif ou non fini.
CostResult computeCost({
  required List<CostLine> lines,
  required double? volumeLitres,
}) {
  final volume = volumeLitres;
  if (volume != null) requirePositiveHidden('volumeLitres', volume);
  final missing = <String>[];
  final lineCosts = <double>[];
  var total = 0.0;
  for (final line in lines) {
    final price = line.unitPrice;
    if (price == null) {
      missing.add(line.name);
    } else {
      final cost = line.quantity * price;
      lineCosts.add(cost);
      total += cost;
    }
  }
  if (missing.isNotEmpty) return CostUnavailable(List.unmodifiable(missing));
  final perLitre = volume == null
      ? null
      : costPerLitre(total: total, volumeLitres: volume);
  return CostComputed(
    total: total,
    lineCosts: List.unmodifiable(lineCosts),
    perLitre: perLitre,
    perBottle33cl: perLitre == null ? null : perLitre * referenceBottleLitres,
  );
}

/// Coût d'une bouteille réelle : [total] divisé par le nombre de bouteilles
/// remplies ([bottles]). 40,84 € pour 50 bouteilles donnent 0,8168 €.
///
/// Lève [BrewingInputException], sans la valeur reçue, pour un total négatif ou
/// non fini, ou un nombre de bouteilles nul ou négatif.
double costPerBottle({required double total, required int bottles}) {
  requireNonNegativeHidden('total', total);
  requirePositiveHidden('bottles', bottles);
  return total / bottles;
}

/// Coût par litre : [total] divisé par [volumeLitres]. 40,84 € pour 17 L
/// donnent 2,4024 €/L.
///
/// Lève [BrewingInputException], sans la valeur reçue, pour un total négatif ou
/// non fini, ou un volume nul, négatif ou non fini.
double costPerLitre({required double total, required double volumeLitres}) {
  requireNonNegativeHidden('total', total);
  requirePositiveHidden('volumeLitres', volumeLitres);
  return total / volumeLitres;
}
