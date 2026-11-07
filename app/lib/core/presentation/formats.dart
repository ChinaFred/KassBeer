/// Affichage et lecture des nombres à la française : virgule décimale, espace
/// insécable avant l'unité et entre les milliers.
///
/// Conversion d'affichage seulement (CLAUDE.md, « Unités du système international en
/// base ») : aucune formule de brassage ici, elles vivent dans `brewing/` (P3).
library;

/// Espace insécable, avant une unité et entre les milliers.
const String nbsp = ' ';

/// Minutes dans un jour : la durée d'un houblon à cru se saisit en jours et se
/// stocke en minutes.
const int minutesParJour = 1440;

/// [value] avec au plus [decimales] chiffres après la virgule.
///
/// Les zéros finaux sont retirés, sauf si [fixe] est vrai. Les milliers sont séparés
/// par une espace insécable si [grouper] est vrai (« 22 400 »).
String formatNombre(
  double value, {
  int decimales = 2,
  bool fixe = false,
  bool grouper = true,
}) {
  var text = value.abs().toStringAsFixed(decimales);
  if (!fixe && text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  final parts = text.split('.');
  var integer = parts.first;
  if (grouper && integer.length > 3) {
    final buffer = StringBuffer();
    for (var i = 0; i < integer.length; i++) {
      if (i > 0 && (integer.length - i) % 3 == 0) buffer.write(nbsp);
      buffer.write(integer[i]);
    }
    integer = buffer.toString();
  }
  final negative = value < 0 && RegExp('[1-9]').hasMatch(text);
  final sign = negative ? '-' : '';
  return parts.length == 1 ? '$sign$integer' : '$sign$integer,${parts[1]}';
}

/// Densité en SG décimal (1.0579) affichée en « 1057,9 ».
String formatDensite(double sg) =>
    formatNombre(sg * 1000, decimales: 1, fixe: true, grouper: false);

/// Degré : « 6,6 % vol ».
String formatDegre(double abv) =>
    '${formatNombre(abv, decimales: 1, fixe: true)}$nbsp%${nbsp}vol';

/// Amertume, entière : « 32 IBU ».
String formatIbu(double ibu) => '${formatNombre(ibu, decimales: 0)}${nbsp}IBU';

/// Couleur, entière : « 18 EBC ».
String formatEbc(double ebc) => '${formatNombre(ebc, decimales: 0)}${nbsp}EBC';

/// Volume : « 20 L ».
String formatLitres(double litres) => '${formatNombre(litres)}${nbsp}L';

/// Masse d'un houblon ou d'un ajout, stockée en grammes : « 22,4 g ».
String formatGrammes(double grams) =>
    '${formatNombre(grams, decimales: 1)}${nbsp}g';

/// Masse d'un fermentescible, stockée en grammes, affichée en kilogrammes :
/// « 4,5 kg » (arbitrage A9).
String formatKilogrammes(double grams) =>
    '${formatNombre(grams / 1000, decimales: 3)}${nbsp}kg';

/// Pourcentage : « 72 % ».
String formatPourcent(double percent) =>
    '${formatNombre(percent, decimales: 1)}$nbsp%';

/// Température : « 67 °C ».
String formatCelsius(double celsius) =>
    '${formatNombre(celsius, decimales: 1)}$nbsp°C';

/// Durée : « 60 min ».
String formatMinutes(double minutes) =>
    '${formatNombre(minutes, decimales: 1)}${nbsp}min';

/// Durée stockée en minutes, affichée en jours : « 3 jours ».
String formatJours(double minutes) {
  final days = minutes / minutesParJour;
  final text = formatNombre(days, decimales: 1);
  // Singulier sous 2 : « 1,5 jour ».
  return '$text$nbsp${days < 2 ? 'jour' : 'jours'}';
}

/// Évaporation : « 3,5 L/h ».
String formatLitresParHeure(double value) => '${formatNombre(value)}${nbsp}L/h';

/// Absorption du grain : « 0,8 L/kg ».
String formatLitresParKg(double value) => '${formatNombre(value)}${nbsp}L/kg';

/// Texte d'un nombre dans un champ de saisie : virgule décimale, sans espace ni
/// unité (« 4,5 »). Vide pour `null`.
String texteSaisi(double? value, {int decimales = 3}) => value == null
    ? ''
    : formatNombre(value, decimales: decimales, grouper: false);

/// Lecture d'un nombre saisi : [valeur] nulle pour un champ vide ; [illisible] vrai
/// quand le texte n'est pas un nombre.
typedef NombreLu = ({double? valeur, bool illisible});

final RegExp _blancs = RegExp(r'[\s  ]');
final RegExp _forme = RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)$');

/// Lit un nombre saisi (règle U1) : virgule ou point décimal, espaces ignorés.
///
/// Plus d'un séparateur (« 1.234,5 », « 1,2,3 ») rend le nombre illisible : le
/// point n'est jamais lu comme un séparateur de milliers. Un nombre trop long pour
/// un double (plus de 309 chiffres, lu comme l'infini) est illisible.
NombreLu lireNombre(String texte) {
  final compact = texte.replaceAll(_blancs, '');
  if (compact.isEmpty) return (valeur: null, illisible: false);
  final separators = RegExp('[.,]').allMatches(compact).length;
  final normalized = compact.replaceAll(',', '.');
  if (separators > 1 || !_forme.hasMatch(normalized)) {
    return (valeur: null, illisible: true);
  }
  final value = double.parse(normalized);
  if (!value.isFinite) return (valeur: null, illisible: true);
  return (valeur: value, illisible: false);
}

/// Plus grand nombre accepté à la saisie : les règles bornent chaque nombre de
/// premier niveau à ±1e9 (`optNumber` de `firestore.rules`).
const double kNombreMaximum = 1e9;

/// Messages d'erreur d'un champ numérique.
abstract final class ErreursNombre {
  static const obligatoire = 'Champ obligatoire.';
  static const illisible = 'Nombre illisible.';
  static const positif = 'Nombre positif attendu.';
  static const tropGrand = 'Nombre trop grand.';
  static String entre(double max) => 'Entre 0 et ${formatNombre(max)}.';
}

/// Erreur du texte [texte] d'un champ numérique, ou `null` s'il est accepté.
///
/// Le minimum est 0, inclus, sauf si [minExclu] est vrai (volume strictement
/// positif) ; [max] est inclus ; à partir de [kNombreMaximum], le nombre est refusé,
/// comme dans `firestore.rules` (`optNumber`, borne exclue).
String? erreurNombre(
  String texte, {
  bool obligatoire = false,
  double? max,
  bool minExclu = false,
}) {
  final lu = lireNombre(texte);
  if (lu.illisible) return ErreursNombre.illisible;
  final value = lu.valeur;
  if (value == null) return obligatoire ? ErreursNombre.obligatoire : null;
  final tooLow = minExclu ? value <= 0 : value < 0;
  if (tooLow || (max != null && value > max)) {
    return max == null ? ErreursNombre.positif : ErreursNombre.entre(max);
  }
  if (value >= kNombreMaximum) return ErreursNombre.tropGrand;
  return null;
}
