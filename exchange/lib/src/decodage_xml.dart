import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart' show XmlNullEntityMapping;
import 'package:xml/xml_events.dart';

/// Décodage et analyse d'un fichier XML importé (BeerXML 1.0), bornés (P9) :
/// encodage déclaré, aucune DTD ni entité autre que les cinq entités
/// prédéfinies et les références numériques, profondeur bornée, éléments
/// gardés bornés. Le texte d'un élément reste une donnée : rien n'est
/// interprété.

/// Profondeur d'éléments la plus grande d'un fichier : `RECIPES`, `RECIPE`,
/// `MASH`, `MASH_STEPS`, `MASH_STEP`, `NAME` font 6 niveaux en BeerXML. Au-delà
/// de 16, le fichier est refusé sans être lu plus loin.
const int kMaxProfondeurXml = 16;

/// Nombre d'éléments gardés en mémoire pour un fichier. 500 recettes de 50
/// houblons, champs d'affichage non gardés, en gardent 203 501 (mesure du
/// 2026-11-10 ; cas lu dans `lecture_beerxml_test.dart`). Au-delà, le fichier est refusé (illisible)
/// sans que l'analyse continue.
const int kMaxElementsXml = 300000;

/// Élément XML lu : nom en majuscules, texte et enfants gardés.
class ElementXml {
  /// Crée l'élément [nom].
  ElementXml(this.nom);

  /// Nom de l'élément, en majuscules (BeerXML écrit ses noms en majuscules).
  final String nom;

  List<ElementXml>? _enfants;

  /// Vrai si l'élément a des enfants que l'analyse n'a pas gardés.
  bool _enfantsNonGardes = false;

  String _texte = '';

  /// Morceaux de texte après le premier (texte coupé par un commentaire, une
  /// section CDATA, une instruction de traitement), joints une seule fois à la
  /// première lecture de [texte] : aucune recopie de la chaîne par morceau.
  StringBuffer? _suite;

  void _ajouter(String morceau) {
    final suite = _suite;
    if (suite != null) {
      suite.write(morceau);
    } else if (_texte.isEmpty) {
      _texte = morceau;
    } else if (morceau.isNotEmpty) {
      _suite = StringBuffer(_texte)..write(morceau);
    }
  }

  /// Enfants gardés, dans l'ordre du fichier (voir [lireXml]).
  List<ElementXml> get enfants => _enfants ?? const [];

  /// Texte de l'élément, entités décodées, sans les enfants.
  String get texte {
    final suite = _suite;
    if (suite != null) {
      _texte = suite.toString();
      _suite = null;
    }
    return _texte;
  }

  /// Premier enfant nommé [nom], ou `null`.
  ElementXml? enfant(String nom) {
    for (final e in enfants) {
      if (e.nom == nom) return e;
    }
    return null;
  }

  /// Vrai si l'élément porte un texte non blanc ou un enfant, gardé ou non.
  bool get renseigne =>
      enfants.isNotEmpty || _enfantsNonGardes || texte.trim().isNotEmpty;
}

/// Résultat de l'analyse d'un texte XML.
sealed class XmlLu {
  const XmlLu();
}

/// Texte refusé : encodage non pris en charge, `DOCTYPE`, entité inconnue,
/// profondeur ou nombre d'éléments dépassés. Aucun détail : le fichier est
/// illisible.
class XmlRefuse extends XmlLu {
  /// Crée le résultat.
  const XmlRefuse();
}

/// Arbre lu.
class XmlArbre extends XmlLu {
  /// Crée le résultat.
  const XmlArbre(this.racine, this.recettes);

  /// Élément racine et éléments gardés (voir [lireXml]). Sous `RECIPES`, les
  /// `RECIPE` seuls, et les `maxRecettes` premiers.
  final ElementXml racine;

  /// Nombre d'éléments `RECIPE` de la racine `RECIPES`, lus ou non.
  final int recettes;
}

/// Décode [octets] à partir de [debut] selon l'encodage déclaré dans
/// `<?xml … encoding="…"?>` : UTF-8 sans déclaration ; `ISO-8859-1`,
/// `windows-1252` et `US-ASCII` décodés en windows-1252, comme le fait le
/// standard Encoding du WHATWG pour ces trois noms. Un fichier BeerSmith qui
/// annonce ISO-8859-1 et contient une apostrophe typographique (0x92) se lit
/// donc juste. Rend `null` pour un autre encodage déclaré. Lève
/// [FormatException] pour un UTF-8 invalide.
String? decoderXml(List<int> octets, int debut) {
  final fin = octets.length < debut + 1024 ? octets.length : debut + 1024;
  final encodage = encodageDeclare(
    const Latin1Decoder().convert(octets, debut, fin),
  );
  if (encodage == null || _utf8.contains(encodage)) {
    return const Utf8Decoder().convert(octets, debut);
  }
  if (_windows1252.contains(encodage)) {
    return _decoderWindows1252(octets, debut);
  }
  return null;
}

const Set<String> _utf8 = {'utf-8', 'utf8'};

const Set<String> _windows1252 = {
  'iso-8859-1',
  'iso8859-1',
  'iso_8859-1',
  'latin1',
  'l1',
  'windows-1252',
  'cp1252',
  'x-cp1252',
  'us-ascii',
  'ascii',
};

/// Encodage déclaré en tête de [tete], en minuscules, ou `null` sans
/// déclaration. Une déclaration dont l'encodage est illisible rend une chaîne
/// vide, refusée ensuite.
String? encodageDeclare(String tete) {
  if (!tete.startsWith('<?xml')) return null;
  final fin = tete.indexOf('?>');
  if (fin < 0) return '';
  final declaration = tete.substring(0, fin);
  final i = declaration.indexOf('encoding');
  if (i < 0) return null;
  var j = i + 'encoding'.length;
  while (j < declaration.length && ' \t\r\n'.contains(declaration[j])) {
    j++;
  }
  if (j >= declaration.length || declaration[j] != '=') return '';
  j++;
  while (j < declaration.length && ' \t\r\n'.contains(declaration[j])) {
    j++;
  }
  if (j >= declaration.length) return '';
  final guillemet = declaration[j];
  if (guillemet != '"' && guillemet != "'") return '';
  final k = declaration.indexOf(guillemet, j + 1);
  if (k < 0 || k - j > 41) return '';
  return declaration.substring(j + 1, k).trim().toLowerCase();
}

/// Caractères de windows-1252 pour les octets 0x80 à 0x9F ; les cinq octets
/// sans caractère (0x81, 0x8D, 0x8F, 0x90, 0x9D) gardent leur valeur, comme
/// dans le standard du WHATWG. Les autres octets valent leur point de code.
const List<int> _c1Windows1252 = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, //
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, //
];

String _decoderWindows1252(List<int> octets, int debut) {
  // Deux octets par caractère : tous les points de code de windows-1252
  // tiennent sur 16 bits.
  final codes = Uint16List(octets.length - debut);
  for (var i = debut; i < octets.length; i++) {
    final o = octets[i] & 0xFF;
    codes[i - debut] = o >= 0x80 && o <= 0x9F ? _c1Windows1252[o - 0x80] : o;
  }
  return String.fromCharCodes(codes);
}

/// Analyse [texte] en un arbre d'éléments.
///
/// Refuse ([XmlRefuse]) un `DOCTYPE`, une entité autre que `&lt;`, `&gt;`,
/// `&amp;`, `&quot;`, `&apos;` et les références numériques, un élément plus
/// profond que [kMaxProfondeurXml] et plus de [kMaxElementsXml] éléments
/// gardés. Aucune entité n'est donc étendue, ni interne ni externe.
///
/// Éléments gardés : la racine ; sous une racine `RECIPES`, les [maxRecettes]
/// premiers `RECIPE` seuls (les suivants sont comptés) ; ailleurs, les enfants
/// d'un élément de [conteneurs] que [ignore] ne rejette pas. Un autre élément
/// garde son texte, et note qu'il a des enfants sans les garder. Les fins de
/// ligne sont normalisées en `\n`. Lève [FormatException] pour un XML mal formé
/// (balise non fermée, deux racines…).
XmlLu lireXml(
  String texte, {
  required int maxRecettes,
  Set<String> conteneurs = const {},
  bool Function(String nom)? ignore,
}) {
  // Fins de ligne normalisées avant l'analyse (XML 1.0, § 2.11) : un fichier
  // en CRLF et le même en LF donnent le même texte et la même empreinte.
  texte = texte.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final pile = <ElementXml?>[];
  ElementXml? racine;
  var recettes = 0;
  var gardes = 0;
  for (final event in parseEvents(
    texte,
    // Aucune entité décodée par le paquet : [_decoder] les lit, et refuse
    // toute entité inconnue.
    entityMapping: const XmlNullEntityMapping(),
    validateNesting: true,
    validateDocument: true,
  )) {
    switch (event) {
      case XmlDoctypeEvent():
        return const XmlRefuse();
      case XmlStartElementEvent(:final name, :final isSelfClosing):
        if (pile.length >= kMaxProfondeurXml) return const XmlRefuse();
        final nom = name.toUpperCase();
        ElementXml? garde;
        if (pile.isEmpty) {
          garde = racine = ElementXml(nom);
        } else {
          final parent = pile.last;
          if (parent == null) {
            garde = null;
          } else if (pile.length == 1 && parent.nom == 'RECIPES') {
            // Sous RECIPES : les recettes seules, et 500 au plus.
            if (nom == 'RECIPE' && ++recettes <= maxRecettes) {
              garde = ElementXml(nom);
            }
          } else if (parent == racine || conteneurs.contains(parent.nom)) {
            if (ignore == null || !ignore(nom)) garde = ElementXml(nom);
          } else {
            parent._enfantsNonGardes = true;
          }
          if (garde != null) (parent!._enfants ??= []).add(garde);
        }
        if (garde != null && ++gardes > kMaxElementsXml) {
          return const XmlRefuse();
        }
        if (!isSelfClosing) pile.add(garde);
      case XmlEndElementEvent():
        pile.removeLast();
      case XmlTextEvent(:final value):
        // Une entité est vérifiée même dans un texte qui n'est pas gardé.
        final decode = _decoder(value);
        if (decode == null) return const XmlRefuse();
        final element = pile.isEmpty ? null : pile.last;
        if (element != null) element._ajouter(decode);
      case XmlCDATAEvent(:final value):
        final element = pile.isEmpty ? null : pile.last;
        if (element != null) element._ajouter(value);
      default:
      // Déclaration, commentaire, instruction de traitement : ignorés.
    }
  }
  if (racine == null) throw const FormatException('aucun élément racine');
  return XmlArbre(racine, recettes);
}

const Map<String, String> _predefinies = {
  'lt': '<',
  'gt': '>',
  'amp': '&',
  'quot': '"',
  'apos': "'",
};

/// Texte [brut] dont les entités prédéfinies et numériques sont décodées ;
/// `null` si une autre entité, ou un `&` hors d'une entité, s'y trouve.
String? _decoder(String brut) {
  var debut = brut.indexOf('&');
  if (debut < 0) return brut;
  final buffer = StringBuffer(brut.substring(0, debut));
  while (debut >= 0) {
    final fin = brut.indexOf(';', debut + 1);
    // 10 caractères suffisent à toute entité permise (`&#x10FFFF;`).
    if (fin < 0 || fin - debut > 10) return null;
    final nom = brut.substring(debut + 1, fin);
    final String? valeur;
    if (nom.startsWith('#x') || nom.startsWith('#X')) {
      valeur = _numerique(nom.substring(2), 16);
    } else if (nom.startsWith('#')) {
      valeur = _numerique(nom.substring(1), 10);
    } else {
      valeur = _predefinies[nom];
    }
    if (valeur == null) return null;
    buffer.write(valeur);
    final suivant = brut.indexOf('&', fin + 1);
    buffer.write(brut.substring(fin + 1, suivant < 0 ? brut.length : suivant));
    debut = suivant;
  }
  return buffer.toString();
}

/// Caractère de la référence numérique [chiffres], ou `null` hors des
/// caractères permis par XML 1.0 (sauts de ligne et tabulations compris).
String? _numerique(String chiffres, int base) {
  if (chiffres.isEmpty) return null;
  for (final c in chiffres.codeUnits) {
    final chiffre =
        (c >= 0x30 && c <= 0x39) ||
        (base == 16 && ((c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)));
    if (!chiffre) return null;
  }
  final code = int.parse(chiffres, radix: base);
  final permis =
      code == 0x9 ||
      code == 0xA ||
      code == 0xD ||
      (code >= 0x20 && code <= 0xD7FF) ||
      (code >= 0xE000 && code <= 0xFFFD) ||
      (code >= 0x10000 && code <= 0x10FFFF);
  return permis ? String.fromCharCode(code) : null;
}
