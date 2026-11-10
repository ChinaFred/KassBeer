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

  /// Valeur du champ `hop_additions[].form` (BeerJSON) écrite quand le
  /// brasseur choisit cette forme.
  final String storedValue;

  /// Valeurs de `hop_additions[].form` du schéma BeerJSON figé (ADR-005), et
  /// la forme de calcul de chacune. `plug` (cônes pressés) se calcule comme des
  /// cônes (`documentation/DATA_SOURCES.md`). `powder`, `extract` et
  /// `leaf (wet)` n'ont pas de facteur d'utilisation : `null`.
  static const Map<String, HopForm?> ofBeerJsonForm = {
    'leaf': whole,
    'plug': whole,
    'pellet': pellet,
    'leaf (wet)': null,
    'powder': null,
    'extract': null,
  };

  /// Forme de calcul de la forme BeerJSON [form], ou `null` si Tinseth n'a pas
  /// de facteur pour elle (forme non prise en charge par le calcul).
  ///
  /// Lève [BrewingInputException] sur une valeur hors du schéma ; la valeur
  /// n'entre pas dans l'erreur, seule sa longueur.
  static HopForm? ofBeerJson(String form) {
    if (ofBeerJsonForm.containsKey(form)) return ofBeerJsonForm[form];
    throw BrewingInputException(
      'hop_additions[].form',
      form.length,
      'valeur inconnue de ${form.length} caractères',
    );
  }
}

/// Moment d'ajout d'un houblon, dans l'ordre du brassage. Sa valeur stockée se
/// lit dans l'application (`timing` BeerJSON d'une recette, ADR-005).
enum HopUse {
  /// À l'empâtage : Tinseth ne le décrit pas, l'IBU de la recette est
  /// indisponible (`MissingInputKind.hopUse`).
  mash,

  /// Pendant l'ébullition, pour [Hop.boilMinutes] minutes.
  boil,

  /// Après l'ébullition (arrêt du feu, whirlpool) : compté 0 IBU.
  afterBoil,

  /// Houblonnage à cru : compté 0 IBU.
  dryHop,

  /// Au conditionnement : Tinseth ne le décrit pas, l'IBU de la recette est
  /// indisponible (`MissingInputKind.hopUse`).
  package,
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
