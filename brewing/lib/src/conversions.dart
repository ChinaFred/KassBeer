import 'color.dart';
import 'errors.dart';
import 'fermentables.dart';
import 'gravity.dart';

/// Conversions d'unités de brassage lues dans un fichier importé (ADR-005,
/// L2) : densité en degrés Plato, couleur en SRM ou en Lovibond, rendement d'un
/// fermentescible donné en densité. Les unités sans formule de brassage
/// (livres, onces, gallons, °F) se convertissent hors de ce paquet.

/// Densité SG décimale d'une densité en degrés Plato :
/// SG = 1 + P / (258,6 − (P / 258,2) × 227,1).
///
/// Lève [BrewingInputException] si la densité obtenue sort de
/// [minGravity]–[maxGravity].
double platoToSg(double plato) {
  if (!plato.isFinite) {
    throw BrewingInputException('plato', plato, 'nombre fini attendu');
  }
  final sg = 1 + plato / (258.6 - (plato / 258.2) * 227.1);
  if (!sg.isFinite || sg < minGravity || sg > maxGravity) {
    throw BrewingInputException(
      'plato',
      plato,
      'densité hors de l\'intervalle $minGravity – $maxGravity',
    );
  }
  return sg;
}

/// Degrés Plato d'une densité SG décimale (polynôme de l'ASBC) :
/// P = −616,868 + 1111,14 × SG − 630,272 × SG² + 135,997 × SG³.
///
/// Ce n'est pas l'inverse exact de [platoToSg] : 12 °P donnent 12,002 °P après
/// un aller-retour. Lève [BrewingInputException] hors de
/// [minGravity]–[maxGravity].
double sgToPlato(double sg) {
  requireRange('sg', sg, minGravity, maxGravity);
  return -616.868 + 1111.14 * sg - 630.272 * sg * sg + 135.997 * sg * sg * sg;
}

/// Couleur en EBC d'une couleur en SRM : EBC = SRM × [ebcPerSrm].
double srmToEbc(double srm) {
  requireNonNegative('srm', srm);
  return srm * ebcPerSrm;
}

/// Couleur en SRM d'une couleur en EBC : SRM = EBC / [ebcPerSrm].
double ebcToSrm(double ebc) {
  requireNonNegative('ebc', ebc);
  return ebc / ebcPerSrm;
}

/// Couleur en EBC d'une couleur de grain en degrés Lovibond.
///
/// Le degré Lovibond est lu comme un SRM, comme dans la couleur de Morey du
/// paquet ([moreyColorEbc]) : une couleur importée donne la même couleur de
/// bière que dans le logiciel d'origine qui applique Morey aux °L.
double lovibondToEbc(double lovibond) {
  requireNonNegative('lovibond', lovibond);
  return lovibond * ebcPerSrm;
}

/// Degrés Lovibond d'une couleur en EBC, réciproque exacte de
/// [lovibondToEbc].
double ebcToLovibond(double ebc) {
  requireNonNegative('ebc', ebc);
  return ebc / ebcPerSrm;
}

/// Rendement d'extrait (% du saccharose) d'un fermentescible dont le
/// rendement est donné en densité (BeerJSON `yield.potential`, densité d'une
/// livre dans un gallon) : (potentiel − 1) × 1000 / 46,214 × 100.
///
/// Lève [BrewingInputException] sous 1,000 ou au-delà du saccharose pur
/// (1 + [sucrosePointsPerPoundPerGallon] / 1000).
double potentialToYieldPercent(double potential) {
  requireRange(
    'potential',
    potential,
    1,
    1 + sucrosePointsPerPoundPerGallon / 1000,
  );
  return (potential - 1) * 1000 / sucrosePointsPerPoundPerGallon * 100;
}
