import 'errors.dart';
import 'gravity.dart';

/// Litres dans un gallon américain.
const double litresPerUsGallon = 3.785411784;

/// Kilogrammes dans une livre.
const double kilogramsPerPound = 0.45359237;

/// Points apportés par le saccharose pur : 46,214 points par livre et par gallon
/// (Palmer, *How to Brew*), soit ≈ 385,7 points par kilogramme et par litre.
///
/// C'est la référence d'un rendement d'extrait de 100 %.
const double sucrosePointsPerKgPerLitre =
    46.214 * litresPerUsGallon / kilogramsPerPound;

/// Nature d'un fermentescible : un malt passe par l'empâtage, un sucre non.
enum FermentableKind {
  /// Malt ou céréale empâtée : son extrait est multiplié par le rendement
  /// d'empâtage de l'équipement. Valeur stockée : `grain`.
  malt('grain'),

  /// Sucre (candi, saccharose, dextrose…) : compté à 100 %. Valeur stockée :
  /// `sugar`.
  sugar('sugar');

  const FermentableKind(this.storedValue);

  /// Valeur du champ `fermentable_additions[].type` d'une recette (BeerJSON).
  final String storedValue;

  /// Nature correspondant à la valeur stockée [value].
  ///
  /// Lève [BrewingInputException] sur une valeur inconnue.
  static FermentableKind fromStored(String value) => enumFromStored(
    values,
    (k) => k.storedValue,
    'fermentable_additions[].type',
    value,
  );
}

/// Potentiel d'extrait d'un fermentescible, donné de l'une de deux façons.
class ExtractPotential {
  /// Potentiel donné par le rendement d'extrait du malt, en % du saccharose
  /// (fiche technique du malteur, ex. 80 %).
  ExtractPotential.yieldPercent(double percent)
    : pointsPerKgPerLitre = percent / 100 * sucrosePointsPerKgPerLitre {
    requireRange('yieldPercent', percent, 0, 100);
  }

  /// Potentiel donné en points de densité par kilogramme et par litre
  /// (ex. 300 : 1 kg dans 1 L donne 1.300 à 100 % de rendement).
  ExtractPotential.pointsPerKgPerLitre(this.pointsPerKgPerLitre) {
    requireRange(
      'pointsPerKgPerLitre',
      pointsPerKgPerLitre,
      0,
      sucrosePointsPerKgPerLitre,
    );
  }

  /// Points par kilogramme et par litre.
  final double pointsPerKgPerLitre;
}

/// Un fermentescible d'une recette ou d'un brassin.
class Fermentable {
  /// Crée un fermentescible. [massGrams] en grammes, [colorEbc] en EBC.
  Fermentable({
    required this.name,
    required this.kind,
    required this.massGrams,
    required this.potential,
    required this.colorEbc,
  }) {
    requireNonNegative('massGrams', massGrams);
    requireNonNegative('colorEbc', colorEbc);
  }

  /// Nom affiché.
  final String name;

  /// Malt ou sucre.
  final FermentableKind kind;

  /// Masse en grammes.
  final double massGrams;

  /// Potentiel d'extrait.
  final ExtractPotential potential;

  /// Couleur en EBC.
  final double colorEbc;

  /// Points × litres apportés à 100 % de rendement.
  double get maxPointLitres => massGrams / 1000 * potential.pointsPerKgPerLitre;
}

/// Densité initiale prévue (SG) d'un moût de [volumeLitres] litres.
///
/// Les malts comptent pour [mashEfficiencyPercent] de leur extrait, les sucres
/// pour 100 %. [volumeLitres] est le volume du moût dont on prévoit la densité
/// (en général le volume obtenu pour la fermentation).
double predictedOriginalGravity({
  required List<Fermentable> fermentables,
  required double mashEfficiencyPercent,
  required double volumeLitres,
}) {
  requireRange('mashEfficiencyPercent', mashEfficiencyPercent, 0, 100);
  requirePositive('volumeLitres', volumeLitres);
  if (fermentables.isEmpty) {
    throw BrewingInputException(
      'fermentables',
      fermentables,
      'aucun fermentescible',
    );
  }
  var pointLitres = 0.0;
  for (final f in fermentables) {
    final factor = f.kind == FermentableKind.malt
        ? mashEfficiencyPercent / 100
        : 1.0;
    pointLitres += f.maxPointLitres * factor;
  }
  final points = pointLitres / volumeLitres;
  if (points > (maxGravity - 1) * 1000) {
    throw BrewingInputException(
      'volumeLitres',
      volumeLitres,
      'densité prévue au-delà de $maxGravity',
    );
  }
  return pointsToSg(points);
}

/// Rendement d'empâtage lu sur une mesure, sans exception ([readMashEfficiency]).
sealed class MashEfficiencyReading {
  const MashEfficiencyReading();
}

/// Rendement calculé, en %.
class MashEfficiencyRead extends MashEfficiencyReading {
  /// Crée la lecture.
  const MashEfficiencyRead(this.percent);

  /// Rendement d'empâtage en %, sans plafond.
  final double percent;
}

/// Aucun malt : le rendement d'empâtage n'est pas défini.
class MashEfficiencyWithoutMalt extends MashEfficiencyReading {
  /// Crée la lecture.
  const MashEfficiencyWithoutMalt();
}

/// Les sucres expliquent à eux seuls la densité mesurée.
class MashEfficiencySugarsExplainGravity extends MashEfficiencyReading {
  /// Crée la lecture.
  const MashEfficiencySugarsExplainGravity();
}

/// Rendement d'empâtage réel (%) à partir d'une densité et d'un volume mesurés.
///
/// [sugarsInWort] dit si les sucres de la liste étaient déjà dans le moût au
/// moment de la mesure : leurs points sont alors retirés avant le calcul. Ne
/// lève que sur une densité ou un volume hors limites : l'absence de malt et
/// des sucres qui expliquent toute la densité sont des résultats.
MashEfficiencyReading readMashEfficiency({
  required double measuredGravity,
  required double measuredVolumeLitres,
  required List<Fermentable> fermentables,
  required bool sugarsInWort,
}) {
  requirePositive('measuredVolumeLitres', measuredVolumeLitres);
  final measuredPointLitres =
      sgToPoints(measuredGravity) * measuredVolumeLitres;
  var maltPointLitres = 0.0;
  var sugarPointLitres = 0.0;
  for (final f in fermentables) {
    if (f.kind == FermentableKind.malt) {
      maltPointLitres += f.maxPointLitres;
    } else if (sugarsInWort) {
      sugarPointLitres += f.maxPointLitres;
    }
  }
  if (maltPointLitres <= 0) return const MashEfficiencyWithoutMalt();
  final fromMalts = measuredPointLitres - sugarPointLitres;
  if (fromMalts <= 0) return const MashEfficiencySugarsExplainGravity();
  return MashEfficiencyRead(fromMalts / maltPointLitres * 100);
}
