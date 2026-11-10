/// Nettoyage des textes d'un fichier importé. Un texte reste une donnée : il
/// n'est ni exécuté, ni interprété, ni affiché autrement qu'en texte simple (P9).
library;

/// Contrôles de la direction du texte (P9) : U+061C, U+200E, U+200F, U+202A à
/// U+202E et U+2066 à U+2069. Ils peuvent inverser l'affichage d'un nom.
final RegExp _bidi = RegExp('[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]');

/// Caractères de contrôle C0 et C1, sauts de ligne et tabulations compris.
final RegExp _controleLigne = RegExp('[\u0000-\u001F\u007F-\u009F]');

/// Caractères de contrôle C0 et C1, sauf saut de ligne et tabulation.
final RegExp _controleNotes = RegExp(
  '[\u0000-\u0008\u000B-\u001F\u007F-\u009F]',
);

/// Texte nettoyé : [texte] et vrai si des caractères ont été retirés.
typedef TexteNettoye = ({String texte, bool retires});

/// Texte d'une ligne (nom, auteur, style) : contrôles de direction retirés,
/// contrôles C0 et C1 remplacés par une espace, espaces de bord retirées.
TexteNettoye nettoyerLigne(String brut) {
  final sansBidi = brut.replaceAll(_bidi, '');
  final texte = sansBidi.replaceAll(_controleLigne, ' ').trim();
  return (
    texte: texte,
    retires: sansBidi.length != brut.length || _controleLigne.hasMatch(brut),
  );
}

/// Texte des notes : contrôles de direction et contrôles C0 et C1 retirés,
/// sauts de ligne et tabulations gardés, espaces de bord retirées.
TexteNettoye nettoyerNotes(String brut) {
  final texte = brut.replaceAll(_bidi, '').replaceAll(_controleNotes, '');
  return (texte: texte.trim(), retires: texte.length != brut.length);
}

/// [texte] coupé à [max] unités UTF-16 sans couper un caractère en deux, comme
/// `truncateName` de l'application : les règles comptent des caractères.
String couper(String texte, int max) {
  if (texte.length <= max) return texte;
  final buffer = StringBuffer();
  for (final rune in texte.runes) {
    final char = String.fromCharCode(rune);
    if (buffer.length + char.length > max) break;
    buffer.write(char);
  }
  return buffer.toString().trimRight();
}
