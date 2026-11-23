import '../resolution_import.dart';
import '../compte_rendu.dart';

/// Ingrédients des recettes du groupe : houblons (ADR-013, décisions 9 à 11),
/// levures (ADR-017) et divers (ADR-018 ; ADR-019). Résolution des noms lus
/// par `ingest/lister-ingredients-recettes.mjs` vers les documents de
/// `beer_hops/`, `beer_cultures/` ou `beer_miscs/`, par
/// [IndexBibliotheque.resoudre] (identifiant, nom et alias ; pour une levure,
/// souche lue dans le nom, référence, producteur et référence), comme
/// Recettes › Importer. Aucune copie de cette résolution en Node.

/// Noms lus au plus dans un fichier de noms.
const int kMaxNomsIngredients = 5000;

/// Longueur maximale d'un nom, en caractères.
const int kMaxLongueurNomIngredient = 120;

/// Raison d'un nom non résolu : aucune entrée, ou plusieurs.
enum RaisonNonResolu {
  /// Aucune entrée n'a ce nom ni cet alias. Les candidats éventuels (levures
  /// seules) viennent d'une correspondance partielle, ou d'une référence dont
  /// le producteur diffère de celui du nom, jamais choisis.
  aucun,

  /// Plusieurs entrées ont ce nom, cet alias ou cette référence.
  plusieurs,
}

/// Format du fichier écrit pour chaque liste : lu par `ingest/` (générateur et
/// écrivain des descriptions aromatiques et des divers).
const Map<ListeRecette, String> kFormatsIngredientsRecettes = {
  ListeRecette.houblons: 'kassbeer_houblons_recettes',
  ListeRecette.levures: 'kassbeer_levures_recettes',
  ListeRecette.ajouts: 'kassbeer_divers_recettes',
};

/// Noms d'un fichier de noms (`{"noms": [...]}`, `noms-houblons.json`,
/// `noms-levures.json` ou `noms-divers.json`) ou d'une liste de noms écrite à la main pour l'essai
/// (`[...]`). Lève [FormatException] pour une autre forme, un nom qui n'est
/// pas un texte de 1 à 120 caractères, ou plus de 5 000 noms.
List<String> lireNomsIngredients(Object? json) {
  final liste = switch (json) {
    {'noms': final List<Object?> noms} => noms,
    final List<Object?> noms => noms,
    _ => throw const FormatException(
      '{"noms": [...]} ou liste de noms attendu',
    ),
  };
  if (liste.length > kMaxNomsIngredients) {
    throw FormatException('$kMaxNomsIngredients noms au plus');
  }
  return [
    for (final (i, n) in liste.indexed)
      if (n is String &&
          n.trim().isNotEmpty &&
          n.trim().runes.length <= kMaxLongueurNomIngredient)
        n.trim()
      else
        throw FormatException('noms[$i] : texte de 1 à 120 caractères attendu'),
  ];
}

/// Cible (`emulator` ou `production`) et date (`generated_at`, ISO 8601) d'un
/// fichier de noms, recopiées dans le fichier résolu : `ingest/ecrire.mjs`
/// refuse en production une liste tirée de l'émulateur ou trop ancienne.
/// `null` pour une liste écrite à la main ou un champ illisible.
({String? cible, String? genereLe}) origineNoms(Object? json) {
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
IndexBibliotheque indexHoublons(Object? json) => IndexBibliotheque(
  ListeRecette.houblons,
  _entrees(json, 'beer_hops.json', levure: false),
);

/// Index des levures tiré de `beer_cultures.json` préparé (liste `{id,
/// data}`), avec producteur et référence (`product_id`). Lève
/// [FormatException] pour une autre forme.
IndexBibliotheque indexLevures(Object? json) => IndexBibliotheque(
  ListeRecette.levures,
  _entrees(json, 'beer_cultures.json', levure: true),
);

/// Index des divers tiré de `beer_miscs.json` préparé (liste `{id, data}`).
/// Lève [FormatException] pour une autre forme.
IndexBibliotheque indexDivers(Object? json) => IndexBibliotheque(
  ListeRecette.ajouts,
  _entrees(json, 'beer_miscs.json', levure: false),
);

List<EntreeBibliotheque> _entrees(
  Object? json,
  String fichier, {
  required bool levure,
}) {
  if (json is! List<Object?>) {
    throw FormatException('$fichier : liste attendue');
  }
  return [
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
            producteur: levure && data['producer'] is String
                ? data['producer'] as String
                : null,
            reference: levure && data['product_id'] is String
                ? data['product_id'] as String
                : null,
          ),
        _ => throw FormatException('$fichier[$i] : {id, data.name} attendu'),
      },
  ];
}

/// Contenu de `houblons-recettes.json`, `levures-recettes.json` ou
/// `divers-recettes.json` (format
/// selon la liste de [index]) : cible et date de la liste des noms ([origine],
/// `null` si inconnues), identifiants résolus, triés, chacun avec les noms qui
/// y mènent, et noms non résolus avec leur raison et leurs candidats
/// ([IndexBibliotheque.candidats]).
Map<String, Object?> ingredientsRecettes(
  List<String> noms,
  IndexBibliotheque index, {
  ({String? cible, String? genereLe}) origine = (cible: null, genereLe: null),
}) {
  final format = kFormatsIngredientsRecettes[index.liste];
  if (format == null) throw ArgumentError.value(index.liste, 'index.liste');
  final resolus = <String, Set<String>>{};
  final nonResolus = <String, ({List<String> ids, bool partiels})>{};
  for (final nom in noms) {
    final entree = index.resoudre(nom);
    if (entree != null) {
      resolus.putIfAbsent(entree.id, () => {}).add(nom);
    } else {
      nonResolus[nom] = index.candidatsAvecOrigine(nom);
    }
  }
  final ids = resolus.keys.toList()..sort();
  final restants = nonResolus.keys.toList()..sort();
  return {
    'format': format,
    'version': 1,
    'target': origine.cible,
    'generated_at': origine.genereLe,
    'resolus': [
      for (final id in ids) {'id': id, 'noms': resolus[id]!.toList()..sort()},
    ],
    'non_resolus': [
      for (final n in restants)
        {
          'nom': n,
          'raison':
              (nonResolus[n]!.ids.length > 1 && !nonResolus[n]!.partiels
                      ? RaisonNonResolu.plusieurs
                      : RaisonNonResolu.aucun)
                  .name,
          'candidats': nonResolus[n]!.ids,
        },
    ],
  };
}
