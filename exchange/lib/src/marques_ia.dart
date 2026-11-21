import 'package:brewing/brewing.dart';

import 'compte_rendu.dart';
import 'schema.dart';

/// Marques « proposée par l'IA » d'une recette (ADR-015, section 6 ; P61) :
/// champ `ai_proposed` de l'enveloppe, jamais dans `recipe` (P21). Une marque
/// s'écrit `<nature>:<ingredientKey>:<champ>`, par exemple
/// `hop:houblon-citra:alpha_acid`. Elle désigne une valeur technique d'un
/// ingrédient que l'assistant a proposée faute de valeur dans la
/// Bibliothèque. La clé vient de `ingredientKey` (`brewing/`) : elle ne change
/// pas quand l'ordre des lignes change.

/// Nombre maximal de marques d'une recette (`firestore.rules`).
const int kMaxMarquesIa = 100;

/// Longueur maximale d'une marque.
const int kMaxLongueurMarqueIa = 200;

/// Champs marquables par nature : `fermentable` (malt ou sucre), `hop`,
/// `culture`.
const Map<String, List<String>> kChampsMarquesIa = {
  'fermentable': ['color', 'yield'],
  'hop': ['alpha_acid'],
  'culture': ['attenuation'],
};

/// Liste de recette de chaque nature marquable.
const Map<String, ListeRecette> kListesMarquesIa = {
  'fermentable': ListeRecette.malts,
  'hop': ListeRecette.houblons,
  'culture': ListeRecette.levures,
};

/// Clé BeerJSON de la liste de chaque nature marquable.
const Map<String, String> kClesListesMarquesIa = {
  'fermentable': 'fermentable_additions',
  'hop': 'hop_additions',
  'culture': 'culture_additions',
};

/// Préfixes de clé permis pour chaque nature (`IngredientNature.prefix`).
final Map<String, Set<String>> _prefixes = {
  'fermentable': {IngredientNature.malt.prefix, IngredientNature.sugar.prefix},
  'hop': {IngredientNature.hop.prefix},
  'culture': {IngredientNature.yeast.prefix},
};

final RegExp _motifCle = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Une marque `ai_proposed`.
class MarqueIa {
  /// Crée la marque ; aucune vérification (voir [MarqueIa.lire]).
  const MarqueIa(this.nature, this.cle, this.champ);

  /// `fermentable`, `hop` ou `culture`.
  final String nature;

  /// Clé d'ingrédient (`ingredientKey`) : `malt-pils`, `houblon-citra`.
  final String cle;

  /// Champ marqué : `color`, `yield`, `alpha_acid` ou `attenuation`.
  final String champ;

  /// Forme stockée : `<nature>:<clé>:<champ>`.
  String get texte => '$nature:$cle:$champ';

  /// Marque lue de [brut], ou `null` si elle est hors forme : autre type
  /// qu'un texte, plus de [kMaxLongueurMarqueIa] caractères, pas trois
  /// parties, nature ou champ hors de [kChampsMarquesIa], clé qui ne suit pas
  /// `ingredientKey` (minuscules, chiffres, tirets, préfixe de la nature).
  static MarqueIa? lire(Object? brut) {
    if (brut is! String || brut.length > kMaxLongueurMarqueIa) return null;
    final parties = brut.split(':');
    if (parties.length != 3) return null;
    final [nature, cle, champ] = parties;
    final champs = kChampsMarquesIa[nature];
    if (champs == null || !champs.contains(champ)) return null;
    if (cle.length > maxIngredientKeyLength || !_motifCle.hasMatch(cle)) {
      return null;
    }
    final prefixe = cle.split('-').first;
    if (!_prefixes[nature]!.contains(prefixe)) return null;
    return MarqueIa(nature, cle, champ);
  }

  @override
  bool operator ==(Object other) =>
      other is MarqueIa &&
      other.nature == nature &&
      other.cle == cle &&
      other.champ == champ;

  @override
  int get hashCode => Object.hash(nature, cle, champ);

  @override
  String toString() => texte;
}

/// Marques lues d'un document.
class MarquesLues {
  /// Crée le résultat.
  const MarquesLues(this.marques, this.illisibles);

  /// Marques valides, sans doublon, dans l'ordre du document,
  /// [kMaxMarquesIa] au plus.
  final List<MarqueIa> marques;

  /// Entrées ignorées : hors forme, ou au-delà de [kMaxMarquesIa]. Un champ
  /// présent qui n'est pas une liste compte pour une. L'appelant le rapporte
  /// (`recipes.ai_proposed`), sans contenu.
  final int illisibles;
}

/// Lecture tolérante de `ai_proposed` : absent ou `null` rend une liste vide ;
/// une entrée hors forme est ignorée et comptée dans [MarquesLues.illisibles].
MarquesLues lireMarques(Object? brut) {
  if (brut == null) return const MarquesLues([], 0);
  if (brut is! List) return const MarquesLues([], 1);
  final marques = <MarqueIa>{};
  var illisibles = 0;
  for (final entree in brut) {
    final marque = MarqueIa.lire(entree);
    if (marque == null || marques.length >= kMaxMarquesIa) {
      illisibles++;
    } else {
      marques.add(marque);
    }
  }
  return MarquesLues(List.unmodifiable(marques), illisibles);
}

/// Forme stockée de [marques] (`ai_proposed`), sans doublon, [kMaxMarquesIa]
/// au plus.
List<String> ecrireMarques(List<MarqueIa> marques) =>
    List.unmodifiable({for (final m in marques) m.texte}.take(kMaxMarquesIa));

/// Clé d'ingrédient d'une [ligne] de la liste de [nature], ou `null` si son
/// nom ou son type ne permet pas de la dériver.
String? cleIngredientDeLigne(String nature, Map<Object?, Object?> ligne) {
  final nom = ligne['name'];
  if (nom is! String || !isValidIngredientName(nom)) return null;
  switch (nature) {
    case 'fermentable':
      final type = ligne['type'];
      if (type is! String ||
          !kTypesFermentable.contains(type) ||
          !FermentableKind.ofBeerJsonType.containsKey(type)) {
        return null;
      }
      return ingredientKey(
        IngredientNature.ofFermentable(FermentableKind.ofType(type)),
        nom,
      );
    case 'hop':
      return ingredientKey(IngredientNature.hop, nom);
    case 'culture':
      return ingredientKey(IngredientNature.yeast, nom);
  }
  return null;
}

List<Map<Object?, Object?>> _lignes(
  Map<String, Object?> recipe,
  String nature,
) {
  final ingredients = recipe['ingredients'];
  if (ingredients is! Map) return const [];
  final lignes = ingredients[kClesListesMarquesIa[nature]];
  if (lignes is! List) return const [];
  return [
    for (final l in lignes)
      if (l is Map) l,
  ];
}

/// Lignes de [recipe] (sous-arbre `recipe`) que désigne [marque] : toutes les
/// lignes de sa liste dont la clé d'ingrédient est celle de la marque.
List<Map<Object?, Object?>> lignesMarquees(
  Map<String, Object?> recipe,
  MarqueIa marque,
) => [
  for (final ligne in _lignes(recipe, marque.nature))
    if (cleIngredientDeLigne(marque.nature, ligne) == marque.cle) ligne,
];

/// Première ligne de [recipe] que désigne [marque], ou `null`.
Map<Object?, Object?>? ligneMarquee(
  Map<String, Object?> recipe,
  MarqueIa marque,
) {
  final lignes = lignesMarquees(recipe, marque);
  return lignes.isEmpty ? null : lignes.first;
}

/// Valeur du champ [champ] d'une [ligne] (`color` en EBC, `yield` en %,
/// `alpha_acid` en %, `attenuation` en %), ou `null`.
double? valeurMarquee(Map<Object?, Object?> ligne, String champ) {
  Object? couple = ligne[champ];
  if (champ == 'yield') couple = couple is Map ? couple['fine_grind'] : null;
  if (couple is! Map) return null;
  final value = couple['value'];
  return value is num ? value.toDouble() : null;
}

/// Valeur unique que porte [marque] dans [recipe] : toutes les lignes de sa
/// clé qui ont une valeur pour le champ ont la même, et au moins une en a
/// une ; sinon `null` (marque ambiguë ou sans valeur).
double? valeurUnique(Map<String, Object?> recipe, MarqueIa marque) {
  double? unique;
  for (final ligne in lignesMarquees(recipe, marque)) {
    final v = valeurMarquee(ligne, marque.champ);
    if (v == null) continue;
    if (unique != null && unique != v) return null;
    unique = v;
  }
  return unique;
}

/// [marques] réduites à celles que [recipe] porte sans ambiguïté : leur
/// ingrédient est présent (un ingrédient retiré perd ses marques), et toutes
/// les lignes de leur clé qui ont une valeur pour le champ ont la même
/// ([valeurUnique]). Une ligne de la même clé saisie avec une autre valeur
/// efface donc la marque : aucune ligne n'est montrée « proposée par l'IA »
/// pour une valeur saisie à la main.
List<MarqueIa> marquesCoherentes(
  Map<String, Object?> recipe,
  List<MarqueIa> marques,
) => List.unmodifiable(marques.where((m) => valeurUnique(recipe, m) != null));

/// Marques de [edite] après une édition à la main de [reference] (même
/// recette, sous-arbre `recipe`) : une marque reste seulement si toutes les
/// lignes de sa clé dans [edite] ont la valeur marquée de [reference],
/// inchangée ([valeurUnique]). Elle sort si l'ingrédient est retiré, si la
/// valeur est corrigée à la main ou reprise de la Bibliothèque, ou si une
/// ligne de la même clé porte une autre valeur. Une marque dont la clé
/// n'est pas dans [reference] (ligne ajoutée depuis) suit [marquesCoherentes].
List<MarqueIa> marquesApresEdition({
  required Map<String, Object?> reference,
  required Map<String, Object?> edite,
  required List<MarqueIa> marques,
}) => List.unmodifiable(
  marques.where((m) {
    final apres = valeurUnique(edite, m);
    if (apres == null) return false;
    if (lignesMarquees(reference, m).isEmpty) return true;
    return valeurUnique(reference, m) == apres;
  }),
);

/// Valeur proposée par l'IA, pour l'affichage et le compte rendu d'un export
/// (« Valeurs proposées par l'IA : … »).
class ValeurProposee {
  /// Crée la valeur.
  const ValeurProposee(this.marque, this.liste, this.nom, this.valeur);

  /// Marque d'origine.
  final MarqueIa marque;

  /// Liste de la ligne.
  final ListeRecette liste;

  /// Nom de la ligne, tel que la recette le porte.
  final String nom;

  /// Valeur marquée (EBC ou %), ou `null` si la ligne ne la porte plus.
  final double? valeur;
}

/// Valeurs de [recipe] que désigne une marque de [marques], dans l'ordre des
/// marques ; une marque sans ligne est omise.
List<ValeurProposee> valeursProposees(
  Map<String, Object?> recipe,
  List<MarqueIa> marques,
) => List.unmodifiable([
  for (final m in marques)
    if (ligneMarquee(recipe, m) case final ligne?)
      ValeurProposee(
        m,
        kListesMarquesIa[m.nature]!,
        ligne['name']! as String,
        valeurMarquee(ligne, m.champ),
      ),
]);
