import 'dart:math' as math;

import 'errors.dart';
import 'gravity.dart';

/// Forme du houblon.
enum HopForm {
  /// Cônes entiers : utilisation de Tinseth sans correction. Valeur stockée :
  /// `leaf`.
  whole(1.0, 'leaf'),

  /// Pellets : utilisation majorée de 10 %, convention courante (BeerSmith,
  /// Brewer's Friend) appliquée à la formule de Tinseth. Valeur stockée :
  /// `pellet`.
  pellet(1.1, 'pellet');

  const HopForm(this.utilizationFactor, this.storedValue);

  /// Facteur appliqué à l'utilisation de Tinseth.
  final double utilizationFactor;

  /// Valeur du champ `hops[].form` d'une recette.
  final String storedValue;

  /// Forme correspondant à la valeur stockée [value].
  ///
  /// Lève [BrewingInputException] sur une valeur inconnue.
  static HopForm fromStored(String value) =>
      enumFromStored(values, (f) => f.storedValue, 'hops.form', value);
}

/// Moment d'ajout d'un houblon.
enum HopUse {
  /// Pendant l'ébullition, pour [Hop.boilMinutes] minutes. Valeur stockée :
  /// `boil`.
  boil('boil'),

  /// Après l'ébullition (arrêt du feu, whirlpool) : compté 0 IBU. Valeur
  /// stockée : `whirlpool`.
  afterBoil('whirlpool'),

  /// Houblonnage à cru : compté 0 IBU. Valeur stockée : `dry_hop`.
  dryHop('dry_hop');

  const HopUse(this.storedValue);

  /// Valeur du champ `hops[].use` d'une recette.
  final String storedValue;

  /// Moment correspondant à la valeur stockée [value].
  ///
  /// Lève [BrewingInputException] sur une valeur inconnue.
  static HopUse fromStored(String value) =>
      enumFromStored(values, (u) => u.storedValue, 'hops.use', value);
}

/// Un houblon d'une recette ou d'un brassin.
class Hop {
  /// Crée un houblon. [alphaPercent] en %, [massGrams] en grammes,
  /// [boilMinutes] en minutes (ignoré hors ébullition).
  Hop({
    required this.name,
    required this.alphaPercent,
    required this.massGrams,
    required this.use,
    required this.form,
    this.boilMinutes = 0,
  }) {
    requireRange('alphaPercent', alphaPercent, 0, 100);
    requireNonNegative('massGrams', massGrams);
    requireNonNegative('boilMinutes', boilMinutes);
  }

  /// Nom affiché.
  final String name;

  /// Acides alpha, en %.
  final double alphaPercent;

  /// Masse en grammes.
  final double massGrams;

  /// Moment d'ajout.
  final HopUse use;

  /// Cônes ou pellets.
  final HopForm form;

  /// Durée d'ébullition en minutes.
  final double boilMinutes;
}

/// Utilisation de Tinseth pour une durée d'ébullition et une densité
/// d'ébullition (SG), avant correction de forme.
double tinsethUtilization({
  required double boilMinutes,
  required double boilGravity,
}) {
  requireNonNegative('boilMinutes', boilMinutes);
  requireRange('boilGravity', boilGravity, minGravity, maxGravity);
  final bigness = 1.65 * math.pow(0.000125, boilGravity - 1);
  final boilFactor = (1 - math.exp(-0.04 * boilMinutes)) / 4.15;
  return bigness * boilFactor;
}

/// IBU de Tinseth apportés par un houblon dans [volumeLitres] litres.
///
/// Un houblon ajouté après l'ébullition ou à cru apporte 0 IBU.
double tinsethIbuForHop({
  required Hop hop,
  required double volumeLitres,
  required double boilGravity,
}) {
  requirePositive('volumeLitres', volumeLitres);
  requireRange('boilGravity', boilGravity, minGravity, maxGravity);
  if (hop.use != HopUse.boil) return 0;
  final alphaMgPerLitre =
      hop.alphaPercent / 100 * hop.massGrams * 1000 / volumeLitres;
  final utilization = tinsethUtilization(
    boilMinutes: hop.boilMinutes,
    boilGravity: boilGravity,
  );
  return utilization * hop.form.utilizationFactor * alphaMgPerLitre;
}

/// IBU de Tinseth d'une liste de houblons.
double tinsethIbu({
  required List<Hop> hops,
  required double volumeLitres,
  required double boilGravity,
}) {
  requirePositive('volumeLitres', volumeLitres);
  requireRange('boilGravity', boilGravity, minGravity, maxGravity);
  var total = 0.0;
  for (final hop in hops) {
    total += tinsethIbuForHop(
      hop: hop,
      volumeLitres: volumeLitres,
      boilGravity: boilGravity,
    );
  }
  return total;
}
