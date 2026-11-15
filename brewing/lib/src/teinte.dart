import 'color.dart';
import 'conversions.dart';
import 'errors.dart';
import 'teintes_srm.dart';

/// Couleur EBC la plus haute de la table des teintes ([teintesSrm] s'arrête
/// à 40 SRM, soit 78,8 EBC) : au-delà, [teinteEbc] rend la teinte de cette
/// limite. Affichée arrondie : « 79 EBC et plus ».
const double teinteEbcLimite = 40 * ebcPerSrm;

/// Teinte indicative d'une bière de couleur [ebc], en entier `0xRRGGBB`.
///
/// La table est indexée par dixième de SRM : l'indice vaut
/// `floor(ebcToSrm(ebc) × 10)`. 0 EBC donne la première teinte ; à partir de
/// [teinteEbcLimite], la dernière. Lève [BrewingInputException] pour une
/// valeur négative ou non finie, comme [ebcToSrm].
int teinteEbc(double ebc) {
  final srm = ebcToSrm(ebc);
  final indice = srm >= 40 ? teintesSrm.length - 1 : (srm * 10).floor();
  final (rouge, vert, bleu) = teintesSrm[indice];
  return rouge << 16 | vert << 8 | bleu;
}

/// Teintes de [points] couleurs régulièrement réparties de [debut] à [fin]
/// EBC inclus, dans l'ordre croissant même si [debut] dépasse [fin] : les
/// arrêts d'un dégradé qui illustre une plage de couleur. La partie au-delà de
/// [teinteEbcLimite] est d'une teinte unie.
///
/// Lève [BrewingInputException] pour une borne négative ou non finie, ou si
/// [points] est inférieur à 2.
List<int> degradeEbc(double debut, double fin, {int points = 24}) {
  requireNonNegative('debut', debut);
  requireNonNegative('fin', fin);
  if (points < 2) {
    throw BrewingInputException('points', points, 'au moins 2 attendus');
  }
  final bas = debut <= fin ? debut : fin;
  final haut = debut <= fin ? fin : debut;
  return [
    for (var i = 0; i < points; i++)
      teinteEbc(i == points - 1 ? haut : bas + (haut - bas) * i / (points - 1)),
  ];
}
