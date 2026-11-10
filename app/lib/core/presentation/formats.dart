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
String formatMinutes(num minutes) =>
    '${formatNombre(minutes.toDouble(), decimales: 1)}${nbsp}min';

/// Durée stockée en minutes, affichée en jours : « 3 jours ».
String formatJours(num minutes) {
  final days = minutes / minutesParJour;
  final text = formatNombre(days, decimales: 1);
  // Singulier sous 2 : « 1,5 jour ».
  return '$text$nbsp${days < 2 ? 'jour' : 'jours'}';
}

String _deuxChiffres(int value) => value.toString().padLeft(2, '0');

/// Heure sur 24 h : « 12:42 ».
String formatHeure(DateTime when) =>
    '${_deuxChiffres(when.hour)}:${_deuxChiffres(when.minute)}';

/// Durée en heures et minutes : « 45 min », « 5 h 40 ».
String formatDuree(Duration duree) {
  final minutes = duree.inMinutes;
  if (minutes < 60) return '$minutes${nbsp}min';
  return '${minutes ~/ 60}${nbsp}h$nbsp${_deuxChiffres(minutes % 60)}';
}

const _joursCourts = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _moisCourts = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Date avec le jour : « sam. 15 nov. 2026 ».
String formatDate(DateTime date) =>
    '${_joursCourts[date.weekday - 1]} ${formatDateCourte(date)}';

/// Date sans le jour : « 11 févr. 2024 ».
String formatDateCourte(DateTime date) =>
    '${date.day} ${_moisCourts[date.month - 1]} ${date.year}';

/// Date et heure sans l'année : « sam. 15 nov. 18:30 ».
String formatJourHeure(DateTime when) =>
    '${_joursCourts[when.weekday - 1]} ${formatJourCourtHeure(when)}';

/// Date courte et heure sans l'année : « 15 nov. 18:30 ».
String formatJourCourtHeure(DateTime when) =>
    '${when.day} ${_moisCourts[when.month - 1]} ${formatHeure(when)}';

const _joursComplets = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];
const _moisComplets = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Lecture d'une date et d'une heure pour un lecteur d'écran :
/// « Samedi 15 novembre 18 heures 30 ».
String jourHeureParle(DateTime when) =>
    '${_joursComplets[when.weekday - 1]} ${when.day} '
    '${_moisComplets[when.month - 1]} ${when.hour} heures '
    '${_deuxChiffres(when.minute)}';

/// Date en chiffres : « 08/11/26 ».
String formatDateChiffres(DateTime date) =>
    '${_deuxChiffres(date.day)}/${_deuxChiffres(date.month)}/'
    '${_deuxChiffres(date.year % 100)}';

/// Date longue : « 8 novembre 2026 », « 1er novembre 2026 ».
String formatDateLongue(DateTime when) =>
    '${when.day == 1 ? '1er' : when.day} ${_moisComplets[when.month - 1]} '
    '${when.year}';

/// Écart signé, sans couleur : « +2,0 pts », « −3,0 pts », « 0,0 pts ».
String formatEcart(double ecart, {String unite = 'pts'}) {
  final texte = formatNombre(ecart.abs(), decimales: 1, fixe: true);
  final signe = texte == '0,0' ? '' : (ecart < 0 ? '−' : '+');
  return '$signe$texte$nbsp$unite';
}

/// Nombre d'étapes, accordé : « 1 étape », « 11 étapes ».
String formatEtapes(int nombre) => '$nombre étape${nombre > 1 ? 's' : ''}';

/// pH : « 5,42 ».
String formatPh(double ph) => formatNombre(ph, fixe: true);

/// Minuteur : « 32:15 », « 1:05:12 », et « +04:12 » pour un dépassement.
String formatMinuteur(Duration duree, {bool depassement = false}) {
  final secondes = duree.inSeconds;
  final heures = secondes ~/ 3600;
  final minutes = (secondes % 3600) ~/ 60;
  final reste = _deuxChiffres(secondes % 60);
  final text = heures > 0
      ? '$heures:${_deuxChiffres(minutes)}:$reste'
      : '${_deuxChiffres(minutes)}:$reste';
  return depassement ? '+$text' : text;
}

/// Lecture du minuteur pour un lecteur d'écran : « 32 minutes 15 secondes ».
String minuteurParle(Duration duree) {
  final secondes = duree.inSeconds;
  final minutes = secondes ~/ 60;
  return [
    if (minutes > 0) '$minutes minute${minutes > 1 ? 's' : ''}',
    '${secondes % 60} seconde${secondes % 60 > 1 ? 's' : ''}',
  ].join(' ');
}

/// Évaporation : « 3,5 L/h ».
String formatLitresParHeure(double value) => '${formatNombre(value)}${nbsp}L/h';

/// Absorption du grain : « 0,8 L/kg ».
String formatLitresParKg(double value) => '${formatNombre(value)}${nbsp}L/kg';

/// Texte d'un nombre dans un champ de saisie : virgule décimale, sans espace ni
/// unité (« 4,5 »). Vide pour `null`.
String texteSaisi(num? value, {int decimales = 3}) => value == null
    ? ''
    : formatNombre(value.toDouble(), decimales: decimales, grouper: false);

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
  static const entier = 'Nombre entier attendu.';
  static String entre(double max, {double min = 0}) =>
      'Entre ${formatNombre(min)} et ${formatNombre(max)}.';
}

/// Erreur du texte [texte] d'un champ numérique, ou `null` s'il est accepté.
///
/// Le minimum est [min], inclus, sauf si [minExclu] est vrai (volume strictement
/// positif) ; [max] est inclus ; à partir de [kNombreMaximum], le nombre est refusé,
/// comme dans `firestore.rules` (`optNumber`, borne exclue). [entier] refuse un nombre
/// décimal.
String? erreurNombre(
  String texte, {
  bool obligatoire = false,
  double? max,
  double min = 0,
  bool minExclu = false,
  bool entier = false,
}) {
  final lu = lireNombre(texte);
  if (lu.illisible) return ErreursNombre.illisible;
  final value = lu.valeur;
  if (value == null) return obligatoire ? ErreursNombre.obligatoire : null;
  if (entier && value != value.truncateToDouble()) return ErreursNombre.entier;
  final tooLow = minExclu ? value <= min : value < min;
  if (tooLow || (max != null && value > max)) {
    return max == null
        ? ErreursNombre.positif
        : ErreursNombre.entre(max, min: min);
  }
  if (value >= kNombreMaximum) return ErreursNombre.tropGrand;
  return null;
}
