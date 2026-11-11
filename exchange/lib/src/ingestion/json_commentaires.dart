import 'dart:convert';

import '../empreinte.dart';

/// Lecture bornée d'un JSON de source : profondeur d'imbrication bornée à
/// [kMaxProfondeur] niveaux, comme une recette importée (`empreinte.dart`).
/// Au-delà, [FormatException] : la source est refusée.
Object? lireJsonBorne(String texte) => _borne(jsonDecode(texte));

/// Lecture d'un JSON à commentaires de ligne (BeerJSON de Brewtarget, DotBeer).
///
/// Les fichiers 002 à 005 de Brewtarget commencent par un en-tête en `//`, et
/// le 005 garde des blocs commentés. Seules les lignes dont le premier
/// caractère non blanc est `//` sont retirées : une chaîne JSON ne peut pas
/// contenir de saut de ligne, donc une telle ligne n'est jamais dans une
/// chaîne. Un commentaire en fin de ligne ou en `/* */` reste et rend le
/// fichier illisible ([FormatException]). Profondeur bornée comme
/// [lireJsonBorne].
Object? lireJsonCommente(String texte) {
  final lignes = const LineSplitter().convert(texte);
  final sansCommentaires = [
    for (final ligne in lignes)
      if (!ligne.trimLeft().startsWith('//')) ligne,
  ];
  return lireJsonBorne(sansCommentaires.join('\n'));
}

Object? _borne(Object? json) {
  if (lireEmpreinte(json).tropProfond) {
    throw const FormatException(
      'JSON trop profond : $kMaxProfondeur niveaux au plus',
    );
  }
  return json;
}
