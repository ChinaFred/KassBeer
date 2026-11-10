import 'dart:convert';

import 'bornes.dart';
import 'compte_rendu.dart';
import 'empreinte.dart';
import 'lecture_beerjson.dart';
import 'schema.dart';

/// Analyse d'un fichier choisi par l'utilisateur : taille, détection du format
/// par le contenu (jamais par l'extension), décodage, lecture de chaque recette.
/// Rien n'est écrit, rien ne part sur le réseau.

/// Profondeur d'imbrication la plus grande d'un fichier JSON : la racine,
/// `beerjson`, `recipes` et la recette, puis [kMaxProfondeur] niveaux dans la
/// recette. Au-delà, le fichier est refusé avant `jsonDecode`.
const int kMaxProfondeurFichier = kMaxProfondeur + 4;

/// Analyse [octets], le contenu d'un fichier.
///
/// Un fichier JSON plus profond que [kMaxProfondeurFichier] est refusé
/// (illisible) avant son décodage. Lève [FormatException] pour un JSON mal
/// formé ou un UTF-8 invalide : l'appelant la rapporte et affiche « Fichier
/// illisible ». Toute autre donnée invalide rend un [FichierRefuse] ou une
/// [RecetteRefusee].
AnalyseFichier analyserFichier(List<int> octets) {
  if (octets.length > kMaxOctetsParFichier) {
    return FichierRefuse(RaisonFichier.tropGros, taille: octets.length);
  }
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
  if (debut >= octets.length) {
    return const FichierRefuse(RaisonFichier.illisible);
  }
  final premier = octets[debut];
  if (premier == 0x3C) return _xml(octets, debut);
  if (premier != 0x7B && premier != 0x5B) {
    return const FichierRefuse(RaisonFichier.illisible);
  }
  if (_profondeurJson(octets, debut) > kMaxProfondeurFichier) {
    return const FichierRefuse(RaisonFichier.illisible);
  }
  // JSON : UTF-8 seul (RFC 8259). Un octet invalide lève FormatException.
  final texte = const Utf8Decoder().convert(octets, debut);
  return _beerJson(jsonDecode(texte));
}

bool _blanc(int octet) =>
    octet == 0x20 || octet == 0x09 || octet == 0x0A || octet == 0x0D;

/// Profondeur d'imbrication de `[` et `{` hors des chaînes, en un seul
/// parcours des octets. Un JSON mal formé donne une valeur quelconque :
/// `jsonDecode` le refuse ensuite.
int _profondeurJson(List<int> octets, int debut) {
  var profondeur = 0;
  var max = 0;
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
      profondeur++;
      if (profondeur > max) max = profondeur;
    } else if (o == 0x5D || o == 0x7D) {
      profondeur--;
    }
  }
  return max;
}

/// Fichier qui commence par `<` : BeerSmith ou BeerXML, reconnus sur leur
/// premier élément. Seul le début est décodé, en ISO-8859-1 : les noms
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
  final nom = _premierElement(tete);
  if (nom == 'RECIPES' || nom == 'RECIPE') {
    return const FichierRefuse(RaisonFichier.beerXml);
  }
  return const FichierRefuse(RaisonFichier.illisible);
}

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
