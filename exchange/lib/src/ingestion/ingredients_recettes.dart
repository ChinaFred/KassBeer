import '../resolution_import.dart';
import '../compte_rendu.dart';

/// Ingrédients des recettes du groupe, pour une nature rédigée par l'API
/// Claude : houblons (ADR-013, décisions 9 à 11) ou divers (ADR-017).
/// Résolution des noms lus par `ingest/lister-houblons-recettes.mjs` ou
/// `ingest/lister-divers-recettes.mjs` vers les documents de `beer_hops/` ou
/// `beer_miscs/`, par [IndexBibliotheque.resoudre] (identifiant, nom et alias),
/// comme Recettes › Importer. Aucune copie de cette résolution en Node.

/// Noms lus au plus dans un fichier de noms.
const int kMaxNomsIngredients = 5000;

/// Longueur maximale d'un nom, en caractères.
const int kMaxLongueurNomIngredient = 120;

/// Nature d'une liste du groupe : liste de recette résolue, référentiel
/// préparé lu, format du fichier écrit.
enum NatureRecettes {
  /// Houblons (`hop_additions`, `beer_hops.json`, `houblons-recettes.json`).
  houblons(
    ListeRecette.houblons,
    'beer_hops.json',
    'kassbeer_houblons_recettes',
  ),

  /// Divers (`miscellaneous_additions`, `beer_miscs.json`,
  /// `divers-recettes.json`).
  divers(ListeRecette.ajouts, 'beer_miscs.json', 'kassbeer_divers_recettes');

  const NatureRecettes(this.liste, this.referentiel, this.format);

  /// Liste de recette résolue par [IndexBibliotheque].
  final ListeRecette liste;

  /// Nom du référentiel préparé (`import/ingest/prepare/`).
  final String referentiel;

  /// Valeur de `format` du fichier écrit, lue par `ingest/`.
  final String format;
}

/// Raison d'un nom non résolu : aucune entrée, ou plusieurs.
enum RaisonNonResolu {
  /// Aucune entrée n'a ce nom ni cet alias.
  aucun,

  /// Plusieurs entrées ont ce nom ou cet alias.
  plusieurs,
}

/// Noms d'un fichier de noms (`{"noms": [...]}`, écrit par `ingest/`) ou
/// d'une liste de noms écrite à la main pour l'essai (`[...]`). Lève
/// [FormatException] pour une autre forme, un nom qui n'est pas un texte de 1
/// à 120 caractères, ou plus de 5 000 noms.
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
/// fichier de noms, recopiées dans la liste du groupe : `ingest/ecrire.mjs`
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

/// Index de [nature] tiré de son référentiel préparé (liste `{id, data}`).
/// Lève [FormatException] pour une autre forme.
IndexBibliotheque indexIngredients(NatureRecettes nature, Object? json) {
  if (json is! List<Object?>) {
    throw FormatException('${nature.referentiel} : liste attendue');
  }
  return IndexBibliotheque(nature.liste, [
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
          '${nature.referentiel}[$i] : {id, data.name} attendu',
        ),
      },
  ]);
}

/// Contenu de la liste du groupe de [nature] (`houblons-recettes.json`,
/// `divers-recettes.json`) : cible et date de la liste des noms ([origine],
/// `null` si inconnues), identifiants résolus, triés, chacun avec les noms qui
/// y mènent, et noms non résolus avec leur raison.
Map<String, Object?> ingredientsRecettes(
  NatureRecettes nature,
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
    'format': nature.format,
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
