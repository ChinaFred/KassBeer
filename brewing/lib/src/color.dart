import 'dart:math' as math;

import 'errors.dart';
import 'fermentables.dart';

/// Facteur EBC / SRM.
const double ebcPerSrm = 1.97;

/// Masse et couleur d'un grain ou d'un sucre : les seules données de la couleur.
typedef ColorContribution = ({double massGrams, double colorEbc});

/// Couleur de la bière (EBC) par la formule de Morey.
///
/// MCU = Σ (couleur °L × masse en livres) / volume en gallons, avec
/// °L ≈ SRM = EBC / 1,97 ; SRM = 1,4922 × MCU^0,6859 ; EBC = SRM × 1,97.
/// [volumeLitres] est le volume du moût fini (volume obtenu pour la fermentation).
double moreyColorEbc({
  required List<Fermentable> fermentables,
  required double volumeLitres,
}) => moreyColorEbcOfGrist(
  grist: [
    for (final f in fermentables)
      (massGrams: f.massGrams, colorEbc: f.colorEbc),
  ],
  volumeLitres: volumeLitres,
);

/// Couleur de Morey (EBC) à partir des seules masses et couleurs.
///
/// Même formule que [moreyColorEbc] : la couleur ne dépend pas du potentiel
/// d'extrait, qui peut manquer quand la couleur est connue.
double moreyColorEbcOfGrist({
  required List<ColorContribution> grist,
  required double volumeLitres,
}) {
  requirePositive('volumeLitres', volumeLitres);
  var lovibondPounds = 0.0;
  for (final g in grist) {
    requireNonNegative('massGrams', g.massGrams);
    requireNonNegative('colorEbc', g.colorEbc);
    lovibondPounds +=
        g.colorEbc / ebcPerSrm * (g.massGrams / 1000 / kilogramsPerPound);
  }
  final mcu = lovibondPounds / (volumeLitres / litresPerUsGallon);
  if (mcu == 0) return 0;
  final srm = 1.4922 * math.pow(mcu, 0.6859);
  return srm * ebcPerSrm;
}
