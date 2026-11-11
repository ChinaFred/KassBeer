import 'dart:convert';

import 'package:brewing/brewing.dart';
import 'package:crypto/crypto.dart';

import '../empreinte.dart';

/// Identifiants des documents de l'ingestion et empreintes du contenu
/// (spécification de L3 : « Identifiants »).

/// Longueur maximale de la clé normalisée d'un nom.
const kMaxCle = 100;

/// Nature d'une entrée de référentiel : préfixe de l'identifiant, collection
/// et document de `beer_index/`.
enum NatureReferentiel {
  /// Malt, sucre, extrait, fruit.
  fermentable('fermentable', 'beer_fermentables', 'fermentables'),

  /// Variété de houblon.
  hop('hop', 'beer_hops', 'hops'),

  /// Levure ou autre culture.
  culture('culture', 'beer_cultures', 'cultures'),

  /// Autre ajout : épice, agent de l'eau, clarifiant.
  misc('misc', 'beer_miscs', 'miscs');

  const NatureReferentiel(this.prefixe, this.collection, this.documentIndex);

  /// Préfixe de l'identifiant et valeur de `import_unresolved.nature`.
  final String prefixe;

  /// Collection Firestore des entrées.
  final String collection;

  /// Identifiant du document `beer_index/{index}`.
  final String documentIndex;
}

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

/// Nom de recherche d'une recette publique (`search_name`) : la normalisation
/// de [cleNormalisee], des espaces à la place des tirets (« Punk IPA 2007 -
/// 2010 » donne « punk ipa 2007 2010 »). L'application trie et cherche par
/// préfixe sur ce champ ; elle normalise la saisie de la même façon
/// (`normalizeName` de `brewing/`, tirets remplacés par des espaces). Vide si
/// [nom] n'a ni lettre ni chiffre.
String nomDeRecherche(String nom) => cleNormalisee(nom).replaceAll('-', ' ');

/// Identifiant d'une entrée : `<nature>-<clé>`.
String idEntree(NatureReferentiel nature, String cle) =>
    '${nature.prefixe}-$cle';

/// Identifiant d'un style BJCP 2021 : `bjcp2021-<code en minuscules>`.
String idStyle(String code) => 'bjcp2021-${cleNormalisee(code)}';

/// Identifiant d'une recette DIY Dog : `diydog-<id>`.
String idRecetteDiyDog(int id) => 'diydog-$id';

/// Identifiant de `import_unresolved/` : SHA-256 de `nature|nom normalisé`,
/// 64 chiffres hexadécimaux.
String idNonResolu(NatureReferentiel nature, String nom) => sha256
    .convert(utf8.encode('${nature.prefixe}|${cleNormalisee(nom)}'))
    .toString();

/// `content_sha256` de [contenu] : SHA-256 du JSON canonique (clés triées,
/// entier écrit sans décimale), 64 chiffres hexadécimaux. [contenu] ne porte
/// ni `content_sha256` ni `updated_at`.
String empreinteContenu(Map<String, Object?> contenu) {
  if (contenu.containsKey('content_sha256') ||
      contenu.containsKey('updated_at')) {
    throw ArgumentError('contenu avec content_sha256 ou updated_at');
  }
  final lue = lireEmpreinte(contenu);
  if (lue.tropProfond) throw ArgumentError('contenu trop profond');
  return lue.empreinte.substring('sha256:'.length);
}
