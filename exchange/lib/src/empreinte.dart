import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'compte_rendu.dart';

/// Profondeur d'imbrication la plus grande lue dans une recette : aucune
/// recette BeerJSON n'en demande plus de 8. Au-delà, la recette est refusée
/// (illisible), sans parcours récursif sans fin.
const int kMaxProfondeur = 32;

/// Empreinte d'une recette du fichier, et vrai si son objet dépasse
/// [kMaxProfondeur] niveaux.
typedef EmpreinteLue = ({String empreinte, bool tropProfond});

/// Empreinte du contenu d'une recette d'un fichier : `sha256:` et 64 chiffres
/// hexadécimaux, calculée sur le JSON canonique de l'objet lu (clés triées,
/// nombre entier écrit sans décimale). Le même fichier donne la même empreinte
/// sur Android et sur le web. Elle ne révèle rien du contenu. Au-delà de
/// [kMaxProfondeur] niveaux, la suite est remplacée par une marque, et
/// [EmpreinteLue.tropProfond] est vrai.
EmpreinteLue lireEmpreinte(Object? recette) {
  final buffer = StringBuffer();
  final complet = _canonique(recette, buffer, 0);
  return (
    empreinte: 'sha256:${sha256.convert(utf8.encode(buffer.toString()))}',
    tropProfond: !complet,
  );
}

/// Écrit [value] en JSON canonique ; faux si la profondeur dépasse la borne.
bool _canonique(Object? value, StringBuffer out, int profondeur) {
  if ((value is List || value is Map) && profondeur >= kMaxProfondeur) {
    out.write('"…"');
    return false;
  }
  var complet = true;
  switch (value) {
    case null:
      out.write('null');
    case bool():
      out.write(value);
    case num():
      // Un entier lu `20` sur la VM et `20.0` sur le web s'écrit pareil ; un
      // grand nombre s'écrit en notation scientifique, la même sur les deux.
      if (!value.isFinite) {
        out.write(jsonEncode('$value'));
      } else if (value.abs() >= 1e15) {
        out.write(value.toDouble().toStringAsExponential());
      } else if (value == value.truncateToDouble()) {
        out.write(value.toInt());
      } else {
        out.write(value);
      }
    case String():
      out.write(jsonEncode(value));
    case List():
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(',');
        complet = _canonique(value[i], out, profondeur + 1) && complet;
      }
      out.write(']');
    case Map():
      final keys = [for (final k in value.keys) '$k']..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out.write(jsonEncode(keys[i]));
        out.write(':');
        complet = _canonique(value[keys[i]], out, profondeur + 1) && complet;
      }
      out.write('}');
    default:
      out.write(jsonEncode('$value'));
  }
  return complet;
}

/// Valeur de `imported_from` d'une recette importée : format et empreinte,
/// 200 caractères au plus (`firestore.rules`). Aucun nom de fichier.
String importedFrom(FormatFichier format, String empreinte) =>
    '${format.nom} · $empreinte';

/// Vrai si [importedFromStocke] désigne une recette importée d'empreinte
/// [empreinte], quel que soit le format.
bool estImporteeDe(String? importedFromStocke, String empreinte) =>
    importedFromStocke != null && importedFromStocke.endsWith(empreinte);
