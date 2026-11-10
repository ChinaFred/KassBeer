import 'dart:convert';

import 'bornes.dart';
import 'compte_rendu.dart';
import 'decodage_xml.dart';
import 'empreinte.dart';
import 'lecture_beerjson.dart';
import 'lecture_beerxml.dart';
import 'schema.dart';

/// Analyse d'un fichier choisi par l'utilisateur : taille, détection du format
/// par le contenu (jamais par l'extension), décodage, lecture de chaque recette.
/// Rien n'est écrit, rien ne part sur le réseau.

/// Profondeur d'imbrication la plus grande d'un fichier JSON : la racine,
/// `beerjson`, `recipes` et la recette, puis [kMaxProfondeur] niveaux dans la
/// recette. Au-delà, le fichier est refusé avant `jsonDecode`.
const int kMaxProfondeurFichier = kMaxProfondeur + 4;

/// Valeurs d'un fichier JSON comptées avant `jsonDecode` : chaque `{`, `[` et
/// `,` hors des chaînes, soit le nombre de valeurs à une près par objet ou
/// liste. Un fichier BeerJSON de 500 recettes de 50 houblons, écrit sans
/// espace, en compte 354 003 (mesure du 2026-11-10 ; cas lu dans
/// `analyse_test.dart`) ; un fichier de 10 Mo sans espace ne porte guère plus
/// de 1 000 000 de valeurs utiles, à 10 octets par valeur. Au-delà, le fichier
/// est refusé (illisible) sans être décodé.
const int kMaxValeursJson = 1000000;

/// Analyse [octets], le contenu d'un fichier.
///
/// Un fichier JSON plus profond que [kMaxProfondeurFichier] ou de plus de
/// [kMaxValeursJson] valeurs, ou XML plus profond que [kMaxProfondeurXml] ou
/// de plus de [kMaxElementsXml] éléments gardés, est refusé (illisible). Lève
/// [FormatException] pour un JSON ou un XML mal formé, ou un UTF-8 invalide :
/// l'appelant la rapporte et affiche « Fichier illisible ». Toute autre donnée
/// invalide rend un [FichierRefuse] ou une [RecetteRefusee].
AnalyseFichier analyserFichier(List<int> octets) {
  if (octets.length > kMaxOctetsParFichier) {
    return FichierRefuse(RaisonFichier.tropGros, taille: octets.length);
  }
  final debut = _debut(octets);
  if (debut >= octets.length) {
    return const FichierRefuse(RaisonFichier.illisible);
  }
  final premier = octets[debut];
  if (premier == 0x3C) return _xml(octets, debut);
  if (premier != 0x7B && premier != 0x5B) {
    return const FichierRefuse(RaisonFichier.illisible);
  }
  final (:profondeur, :valeurs) = _structureJson(octets, debut);
  if (profondeur > kMaxProfondeurFichier || valeurs > kMaxValeursJson) {
    return const FichierRefuse(RaisonFichier.illisible);
  }
  // JSON : UTF-8 seul (RFC 8259). Un octet invalide lève FormatException.
  final texte = const Utf8Decoder().convert(octets, debut);
  return _beerJson(jsonDecode(texte));
}

/// Format présumé de [octets] d'après leur premier caractère, pour le
/// contexte d'un rapport d'erreur : `xml`, `json` ou `inconnu`. Rien du
/// contenu n'est rendu.
String formatPresume(List<int> octets) {
  final debut = _debut(octets);
  if (debut >= octets.length) return 'inconnu';
  return switch (octets[debut]) {
    0x3C => 'xml',
    0x7B || 0x5B => 'json',
    _ => 'inconnu',
  };
}

/// Position du premier octet après un BOM UTF-8 et des blancs.
int _debut(List<int> octets) {
  var debut = 0;
  if (octets.length >= 3 &&
      octets[0] == 0xEF &&
      octets[1] == 0xBB &&
      octets[2] == 0xBF) {
    debut = 3;
  }
  while (debut < octets.length && _blanc(octets[debut])) {
    debut++;
  }
  return debut;
}

bool _blanc(int octet) =>
    octet == 0x20 || octet == 0x09 || octet == 0x0A || octet == 0x0D;

/// Profondeur d'imbrication de `[` et `{` hors des chaînes, et nombre de
/// `{`, `[` et `,` hors des chaînes, en un seul parcours des octets. Un JSON
/// mal formé donne des valeurs quelconques : `jsonDecode` le refuse ensuite.
({int profondeur, int valeurs}) _structureJson(List<int> octets, int debut) {
  var profondeur = 0;
  var max = 0;
  var valeurs = 0;
  var dansChaine = false;
  for (var i = debut; i < octets.length; i++) {
    final o = octets[i];
    if (dansChaine) {
      if (o == 0x5C) {
        i++; // caractère échappé, guillemet compris
      } else if (o == 0x22) {
        dansChaine = false;
      }
    } else if (o == 0x22) {
      dansChaine = true;
    } else if (o == 0x5B || o == 0x7B) {
      valeurs++;
      profondeur++;
      if (profondeur > max) max = profondeur;
    } else if (o == 0x5D || o == 0x7D) {
      profondeur--;
    } else if (o == 0x2C) {
      valeurs++;
    }
  }
  return (profondeur: max, valeurs: valeurs);
}

/// Racines d'un fichier BeerXML sans recette : bibliothèques d'ingrédients,
/// de styles, d'équipements ou d'empâtages.
const Set<String> _racinesSansRecette = {
  'HOPS',
  'FERMENTABLES',
  'YEASTS',
  'MISCS',
  'WATERS',
  'STYLES',
  'EQUIPMENTS',
  'MASHS',
  'HOP',
  'FERMENTABLE',
  'YEAST',
  'MISC',
  'WATER',
  'STYLE',
  'EQUIPMENT',
  'MASH',
};

/// Fichier qui commence par `<` : BeerSmith ou BeerXML, reconnus sur leur
/// premier élément. Le début est d'abord lu en ISO-8859-1 : les noms
/// d'éléments sont en ASCII, quel que soit l'encodage déclaré.
AnalyseFichier _xml(List<int> octets, int debut) {
  final fin = octets.length < debut + 4096 ? octets.length : debut + 4096;
  final tete = const Latin1Decoder().convert(octets, debut, fin);
  if (tete.contains('<F_R_') ||
      tete.contains('<_PERMID_>') ||
      tete.contains('<Selections>') ||
      tete.contains('<Selections ')) {
    return const FichierRefuse(RaisonFichier.bsmx);
  }
  final nom = _premierElement(tete)?.toUpperCase();
  if (_racinesSansRecette.contains(nom)) {
    return const FichierRefuse(RaisonFichier.aucuneRecette);
  }
  if (nom != 'RECIPES' && nom != 'RECIPE') {
    return const FichierRefuse(RaisonFichier.illisible);
  }
  final texte = decoderXml(octets, debut);
  if (texte == null) return const FichierRefuse(RaisonFichier.illisible);
  final lu = lireXml(
    texte,
    maxRecettes: kMaxRecettesParFichier,
    conteneurs: kConteneursBeerXml,
    ignore: ignoreBeerXml,
  );
  final XmlArbre arbre;
  switch (lu) {
    case XmlRefuse():
      return const FichierRefuse(RaisonFichier.illisible);
    case XmlArbre():
      arbre = lu;
  }
  final racine = arbre.racine;
  final List<ElementXml> recettes;
  final int total;
  if (racine.nom == 'RECIPE') {
    recettes = [racine];
    total = 1;
  } else {
    recettes = [
      for (final e in racine.enfants)
        if (e.nom == 'RECIPE') e,
    ];
    total = arbre.recettes;
  }
  if (recettes.isEmpty) return const FichierRefuse(RaisonFichier.aucuneRecette);
  final lues = <RecetteDuFichier>[];
  final vues = <String>{};
  for (final (i, recette) in recettes.indexed) {
    final empreinte = lireEmpreinte(_canonique(recette)).empreinte;
    lues.add(
      RecetteDuFichier(
        numero: i + 1,
        nom: nomAfficheXml(recette),
        empreinte: empreinte,
        resultat: lireRecetteBeerXml(recette),
        enDouble: !vues.add(empreinte),
      ),
    );
  }
  return FichierLu(
    format: FormatFichier.beerXml,
    recettes: List.unmodifiable(lues),
    total: total,
  );
}

/// Forme canonique d'un élément pour son empreinte : `[nom, texte]` pour une
/// feuille (texte sans blancs de bord), `[nom, [enfants…]]` sinon. L'ordre des
/// enfants compte ; l'indentation du fichier, non. Profondeur : deux niveaux
/// par élément, et [kMaxProfondeurXml] borne les éléments sous [kMaxProfondeur].
List<Object?> _canonique(ElementXml e) => e.enfants.isEmpty
    ? [e.nom, e.texte.trim()]
    : [
        e.nom,
        [for (final enfant in e.enfants) _canonique(enfant)],
      ];

/// Nom du premier élément de [tete], après les déclarations `<?…?>`, les
/// commentaires `<!--…-->` et un `<!DOCTYPE …>` ; `null` s'il n'y en a pas.
/// Parcours linéaire par `indexOf` : aucune expression régulière à retour
/// arrière sur un texte du fichier.
String? _premierElement(String tete) {
  var i = 0;
  while (true) {
    while (i < tete.length && ' \t\r\n'.contains(tete[i])) {
      i++;
    }
    if (tete.startsWith('<?', i)) {
      final fin = tete.indexOf('?>', i + 2);
      if (fin < 0) return null;
      i = fin + 2;
    } else if (tete.startsWith('<!--', i)) {
      final fin = tete.indexOf('-->', i + 4);
      if (fin < 0) return null;
      i = fin + 3;
    } else if (tete.startsWith('<!DOCTYPE', i)) {
      final fin = tete.indexOf('>', i);
      if (fin < 0) return null;
      i = fin + 1;
    } else if (tete.startsWith('<', i)) {
      var j = i + 1;
      while (j < tete.length &&
          _caractereNom(tete.codeUnitAt(j), premier: j == i + 1)) {
        j++;
      }
      return j == i + 1 ? null : tete.substring(i + 1, j);
    } else {
      return null;
    }
  }
}

/// Lettre ou `_` ; pour la suite, aussi chiffre, `.` ou `-`.
bool _caractereNom(int c, {required bool premier}) {
  final lettre = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  if (lettre || c == 0x5F) return true;
  if (premier) return false;
  return (c >= 0x30 && c <= 0x39) || c == 0x2E || c == 0x2D;
}

AnalyseFichier _beerJson(Object? racine) {
  if (racine is! Map) return const FichierRefuse(RaisonFichier.jsonNonBeerJson);
  final beerjson = racine['beerjson'];
  if (beerjson is! Map) {
    return const FichierRefuse(RaisonFichier.jsonNonBeerJson);
  }
  final version = beerjson['version'];
  final numero = switch (version) {
    num() => version.toDouble(),
    String() => double.tryParse(version.trim()),
    _ => null,
  };
  if (numero == null ||
      !numero.isFinite ||
      !kVersionsLues.contains(numero.floor())) {
    return FichierRefuse(
      RaisonFichier.versionInconnue,
      version: _versionAffichee(version),
    );
  }
  final recipes = beerjson['recipes'];
  if (recipes == null || (recipes is List && recipes.isEmpty)) {
    return const FichierRefuse(RaisonFichier.aucuneRecette);
  }
  if (recipes is! List) return const FichierRefuse(RaisonFichier.illisible);
  final lues = <RecetteDuFichier>[];
  final vues = <String>{};
  for (var i = 0; i < recipes.length && i < kMaxRecettesParFichier; i++) {
    final brut = recipes[i];
    final (:empreinte, :tropProfond) = lireEmpreinte(brut);
    lues.add(
      RecetteDuFichier(
        numero: i + 1,
        nom: nomAffiche(brut),
        empreinte: empreinte,
        // Imbrication anormale : refusée sans être lue.
        resultat: tropProfond
            ? const RecetteRefusee(RecetteIllisible())
            : lireRecetteBeerJson(brut),
        enDouble: !vues.add(empreinte),
      ),
    );
  }
  return FichierLu(
    format: FormatFichier.beerJson,
    recettes: List.unmodifiable(lues),
    total: recipes.length,
  );
}

/// Version lue, pour le message « Version non prise en charge » : un nombre,
/// ou une chaîne courte, nettoyée et de 20 caractères au plus ; `null` sinon
/// (liste, objet, chaîne longue), sans convertir la valeur en texte.
String? _versionAffichee(Object? version) {
  final String brut;
  if (version is num) {
    brut = '$version';
  } else if (version is String && version.length <= 40) {
    brut = version;
  } else {
    return null;
  }
  final texte = brut.replaceAll(RegExp(r'[^\w.,+-]'), '');
  return texte.isEmpty || texte.length > 20 ? null : texte;
}
