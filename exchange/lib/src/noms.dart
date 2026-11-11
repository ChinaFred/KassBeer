import 'dart:convert';

import 'package:brewing/brewing.dart';
import 'package:crypto/crypto.dart';

/// Normalisation des noms d'ingrédient, commune à l'ingestion
/// (`package:exchange/ingestion.dart`) et à la résolution d'un import dans
/// l'application (`resolution_import.dart`) : les deux comparent les noms de la
/// même façon, et calculent le même identifiant de `import_unresolved/`.

/// Longueur maximale de la clé normalisée d'un nom.
const kMaxCle = 100;

/// Clé normalisée de [texte] : minuscules, accents retirés, tout caractère
/// hors a-z et 0-9 remplacé par un tiret, tirets répétés réduits, aucun tiret
/// en bord, [kMaxCle] caractères au plus. Même normalisation que les clés
/// d'ingrédient de `brewing/` (`normalizeName`). Vide si [texte] n'a ni lettre
/// ni chiffre.
String cleNormalisee(String texte) {
  final cle = normalizeName(texte);
  if (cle.length <= kMaxCle) return cle;
  return cle.substring(0, kMaxCle).replaceAll(RegExp(r'-+$'), '');
}

/// Producteurs de levure écrits de deux façons selon la source : clé
/// normalisée lue → clé retenue dans l'identifiant.
const Map<String, String> kProducteursEquivalents = {
  'wyeast-labs': 'wyeast',
  'omega-yeast-labs': 'omega-yeast',
};

/// Clé d'un producteur de levure, après [kProducteursEquivalents].
String cleProducteur(String producteur) {
  final cle = cleNormalisee(producteur);
  return kProducteursEquivalents[cle] ?? cle;
}

/// Clé d'une référence de levure chez son producteur : normalisée, sans
/// tiret (`W-34/70` et `W34/70` donnent `w3470`). Wyeast écrit `WY1056` ou
/// `1056` : le `wy` est retiré. White Labs écrit `WLP001` ou `001` : le `wlp`
/// est ajouté.
String cleProduit(String cleDuProducteur, String produit) {
  final cle = cleNormalisee(produit).replaceAll('-', '');
  if (cleDuProducteur == 'wyeast' && RegExp(r'^wy\d+$').hasMatch(cle)) {
    return cle.substring(2);
  }
  if (cleDuProducteur == 'white-labs' && RegExp(r'^\d+$').hasMatch(cle)) {
    return 'wlp$cle';
  }
  return cle;
}

/// Producteur et référence d'une levure lus dans un nom, ou `null` :
/// `Wyeast 1056 - American Ale™` donne Wyeast et `1056`,
/// `WLP099 - Super High Gravity Ale` donne White Labs et `WLP099`.
({String producteur, String produit})? soucheDuNom(String nom) {
  final cle = cleNormalisee(nom);
  final wyeast = RegExp(r'^wyeast-(\d{4})(-|$)').firstMatch(cle);
  if (wyeast != null) return (producteur: 'Wyeast', produit: wyeast[1]!);
  final wlp = RegExp(r'^wlp(\d{3,4})(-|$)').firstMatch(cle);
  if (wlp != null) return (producteur: 'White Labs', produit: 'WLP${wlp[1]}');
  return null;
}

/// Identifiant d'un document `import_unresolved/` écrit par l'ingestion :
/// SHA-256 de `nature|nom normalisé`, 64 chiffres hexadécimaux. [nature] :
/// `fermentable`, `hop`, `culture` ou `misc`.
String empreinteNonResolu(String nature, String nom) =>
    sha256.convert(utf8.encode('$nature|${cleNormalisee(nom)}')).toString();

/// Identifiant d'un document `import_unresolved/` écrit après un import
/// (ADR-005, E6) : SHA-256 de `import|nature|nom normalisé`. Il ne croise
/// jamais celui de l'ingestion ([empreinteNonResolu]) : chaque origine a sa
/// ligne.
String empreinteNonResoluImport(String nature, String nom) => sha256
    .convert(utf8.encode('import|$nature|${cleNormalisee(nom)}'))
    .toString();
