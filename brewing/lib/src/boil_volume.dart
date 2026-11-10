import 'errors.dart';

/// Volume avant ébullition d'une recette sur un équipement (`BOIL_SIZE` d'un
/// export BeerXML, ADR-005, L2c), en litres :
/// V = [batchLitres] + [trubLossLitres] + [kettleDeadSpaceLitres]
///   + [boilOffLitresPerHour] × [boilMinutes] / 60.
///
/// [batchLitres] est le volume en fermenteur de la recette ; [trubLossLitres]
/// et [kettleDeadSpaceLitres] restent dans la cuve d'ébullition. Le retrait du
/// moût au refroidissement n'est pas compté : aucun profil d'équipement ne le
/// porte. Aucune valeur par défaut : l'appelant ne calcule rien quand l'une
/// manque.
///
/// Lève [BrewingInputException] pour un volume en fermenteur nul ou négatif,
/// une autre valeur négative, ou un nombre non fini.
double preBoilVolumeLitres({
  required double batchLitres,
  required double boilMinutes,
  required double boilOffLitresPerHour,
  required double trubLossLitres,
  required double kettleDeadSpaceLitres,
}) {
  requirePositive('batchLitres', batchLitres);
  requireNonNegative('boilMinutes', boilMinutes);
  requireNonNegative('boilOffLitresPerHour', boilOffLitresPerHour);
  requireNonNegative('trubLossLitres', trubLossLitres);
  requireNonNegative('kettleDeadSpaceLitres', kettleDeadSpaceLitres);
  return batchLitres +
      trubLossLitres +
      kettleDeadSpaceLitres +
      boilOffLitresPerHour * boilMinutes / 60;
}
