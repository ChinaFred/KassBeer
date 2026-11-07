import 'dart:math' as math;

import 'errors.dart';
import 'fermentables.dart';

/// Facteur EBC / SRM.
const double ebcPerSrm = 1.97;

/// Couleur de la bière (EBC) par la formule de Morey.
///
/// MCU = Σ (couleur °L × masse en livres) / volume en gallons, avec
/// °L ≈ SRM = EBC / 1,97 ; SRM = 1,4922 × MCU^0,6859 ; EBC = SRM × 1,97.
/// [volumeLitres] est le volume du moût fini (volume obtenu pour la fermentation).
double moreyColorEbc({
  required List<Fermentable> fermentables,
  required double volumeLitres,
}) {
  requirePositive('volumeLitres', volumeLitres);
  var lovibondPounds = 0.0;
  for (final f in fermentables) {
    lovibondPounds +=
        f.colorEbc / ebcPerSrm * (f.massGrams / 1000 / kilogramsPerPound);
  }
  final mcu = lovibondPounds / (volumeLitres / litresPerUsGallon);
  if (mcu == 0) return 0;
  final srm = 1.4922 * math.pow(mcu, 0.6859);
  return srm * ebcPerSrm;
}
