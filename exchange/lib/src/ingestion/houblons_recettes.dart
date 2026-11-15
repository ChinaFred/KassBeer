import '../resolution_import.dart';
import '../compte_rendu.dart';

/// Houblons des recettes du groupe (ADR-013, décisions 9 à 11) : résolution
/// des noms lus par `ingest/lister-houblons-recettes.mjs` vers les documents de
/// `beer_hops/`, par [IndexBibliotheque.resoudre] (identifiant, nom et alias),
/// comme Recettes › Importer. Aucune copie de cette résolution en Node.

/// Noms lus au plus dans un fichier de noms.
const int kMaxNomsHoublons = 5000;

/// Longueur maximale d'un nom, en caractères.
const int kMaxLongueurNomHoublon = 120;

/// Raison d'un nom non résolu : aucune entrée, ou plusieurs.
enum RaisonNonResolu {
  /// Aucune entrée n'a ce nom ni cet alias.
  aucun,

  /// Plusieurs entrées ont ce nom ou cet alias.
  plusieurs,
}

/// Noms d'un fichier `noms-houblons.json` (`{"noms": [...]}`) ou d'une liste
/// de noms écrite à la main pour l'essai (`[...]`). Lève [FormatException]
/// pour une autre forme, un nom qui n'est pas un texte de 1 à 120 caractères,
/// ou plus de 5 000 noms.
List<String> lireNomsHoublons(Object? json) {
  final liste = switch (json) {
    {'noms': final List<Object?> noms} => noms,
    final List<Object?> noms => noms,
    _ => throw const FormatException(
      '{"noms": [...]} ou liste de noms attendu',
    ),
  };
  if (liste.length > kMaxNomsHoublons) {
    throw FormatException('$kMaxNomsHoublons noms au plus');
  }
  return [
    for (final (i, n) in liste.indexed)
      if (n is String &&
          n.trim().isNotEmpty &&
          n.trim().runes.length <= kMaxLongueurNomHoublon)
        n.trim()
      else
        throw FormatException('noms[$i] : texte de 1 à 120 caractères attendu'),
  ];
}

/// Cible (`emulator` ou `production`) et date (`generated_at`, ISO 8601) d'un
/// fichier `noms-houblons.json`, recopiées dans `houblons-recettes.json` :
/// `ingest/ecrire.mjs` refuse en production une liste tirée de l'émulateur ou
/// trop ancienne. `null` pour une liste écrite à la main ou un champ illisible.
({String? cible, String? genereLe}) origineNomsHoublons(Object? json) {
  if (json is! Map<String, Object?>) return (cible: null, genereLe: null);
  final cible = json['target'];
  final date = json['generated_at'];
  return (
    cible: cible == 'emulator' || cible == 'production'
        ? cible as String
        : null,
    genereLe: date is String && DateTime.tryParse(date) != null ? date : null,
  );
}

/// Index des houblons tiré de `beer_hops.json` préparé (liste `{id, data}`).
/// Lève [FormatException] pour une autre forme.
IndexBibliotheque indexHoublons(Object? json) {
  if (json is! List<Object?>) {
    throw const FormatException('beer_hops.json : liste attendue');
  }
  return IndexBibliotheque(ListeRecette.houblons, [
    for (final (i, d) in json.indexed)
      switch (d) {
        {
          'id': final String id,
          'data': {'name': final String nom} && final Map<String, Object?> data,
        } =>
          EntreeBibliotheque(
            id: id,
            nom: nom,
            alias: [
              for (final a in (data['aliases'] as List<Object?>? ?? const []))
                if (a is String) a,
            ],
          ),
        _ => throw FormatException(
          'beer_hops.json[$i] : {id, data.name} attendu',
        ),
      },
  ]);
}

/// Contenu de `houblons-recettes.json` : cible et date de la liste des noms
/// ([origine], `null` si inconnues), identifiants résolus, triés, chacun avec
/// les noms qui y mènent, et noms non résolus avec leur raison.
Map<String, Object?> houblonsRecettes(
  List<String> noms,
  IndexBibliotheque index, {
  ({String? cible, String? genereLe}) origine = (cible: null, genereLe: null),
}) {
  final resolus = <String, Set<String>>{};
  final nonResolus = <String, RaisonNonResolu>{};
  for (final nom in noms) {
    final entree = index.resoudre(nom);
    if (entree != null) {
      resolus.putIfAbsent(entree.id, () => {}).add(nom);
    } else {
      nonResolus[nom] = index.correspondances(nom) > 1
          ? RaisonNonResolu.plusieurs
          : RaisonNonResolu.aucun;
    }
  }
  final ids = resolus.keys.toList()..sort();
  final restants = nonResolus.keys.toList()..sort();
  return {
    'format': 'kassbeer_houblons_recettes',
    'version': 1,
    'target': origine.cible,
    'generated_at': origine.genereLe,
    'resolus': [
      for (final id in ids) {'id': id, 'noms': resolus[id]!.toList()..sort()},
    ],
    'non_resolus': [
      for (final n in restants) {'nom': n, 'raison': nonResolus[n]!.name},
    ],
  };
}
