import 'dart:convert';

import 'package:brewing/brewing.dart';

import 'compte_rendu.dart' show Champ, ListeRecette;
import 'schema.dart';

/// Export BeerJSON d'une recette (ADR-005) : le sous-arbre `recipe` stocké,
/// complété de l'auteur, du rendement de l'équipement et des valeurs calculées
/// par `computeRecipe` (P3 étendu). Aucun prix, stock, coût, e-mail,
/// `owner_uid`, `equipment_id` ni nom d'équipement : le fichier ne contient que
/// `recipe` et ce qui est passé ici.

/// Ce qui manque pour exporter une recette.
sealed class ManqueExport {
  const ManqueExport();
}

/// Donnée qui manque aussi au calcul : volume, rendement d'extrait, couleur,
/// acides alpha, rendement d'empâtage. L'application en écrit le libellé comme
/// pour « À compléter ».
class ManqueDeCalcul extends ManqueExport {
  /// Crée le manque.
  const ManqueDeCalcul(this.manque);

  /// Donnée manquante, au sens de `brewing/`.
  final MissingInput manque;
}

/// Champ propre au format.
enum ChampExport {
  /// Type de la recette.
  typeRecette,

  /// Auteur : ni `recipe.author`, ni le nom passé par l'appelant.
  auteur,

  /// Température du grain saisie sans palier : le schéma demande au moins un
  /// palier dans `mash`.
  paliers,

  /// Température du grain.
  temperatureGrain,

  /// Type d'un palier.
  typePalier,

  /// Type d'une levure.
  typeLevure,

  /// Forme d'une levure.
  formeLevure,

  /// Quantité d'une levure.
  quantiteLevure,

  /// Type d'un autre ajout.
  typeAjout,

  // Champs demandés par le BeerXML seul (`ecriture_beerxml.dart`).

  /// Style de la liste BJCP : BeerXML demande sa catégorie et ses plages.
  style,

  /// Durée d'ébullition : `BOIL_TIME`, et le calcul de `BOIL_SIZE`.
  dureeEbullition,

  /// Évaporation de l'équipement, pour `BOIL_SIZE`.
  evaporation,

  /// Pertes au trub de l'équipement, pour `BOIL_SIZE`.
  pertesAuTrub,

  /// Volume mort de la cuve d'ébullition, pour `BOIL_SIZE`.
  volumeMort,

  /// Type de recette sans équivalent BeerXML (`cider`, `mead`…) ; [noms]
  /// porte la valeur.
  typeRecetteBeerXml,

  /// Moment d'un autre ajout : `USE` est obligatoire.
  momentAjout,

  /// Durée ou heure d'un houblon ou d'un autre ajout : `TIME` est obligatoire.
  dureeAjout,

  /// Houblon mesuré en volume : BeerXML le mesure en kilogrammes.
  houblonEnVolume,

  /// Houblon sans forme (recette publique et sa copie, ADR-005, D8) : `FORM`
  /// est attendu par les logiciels qui relisent le BeerXML, et aucune forme
  /// n'est inventée. [noms] : les houblons. Le BeerJSON l'exporte sans forme.
  formeHoublon,
}

/// Donnée qui manque au format seul.
class ManqueDeFormat extends ManqueExport {
  /// Crée le manque.
  const ManqueDeFormat(this.champ, [this.noms = const []]);

  /// Champ manquant.
  final ChampExport champ;

  /// Lignes concernées (paliers, levures, ajouts), dans l'ordre de la recette.
  final List<String> noms;
}

/// Information de la recette que le fichier ne garde pas.
sealed class PerteExport {
  const PerteExport();
}

/// Style non exporté : BeerJSON demande sa catégorie, son guide et son type.
class StyleNonExporte extends PerteExport {
  /// Crée la perte.
  const StyleNonExporte(this.nom);

  /// Nom du style.
  final String nom;
}

/// Chronologie du jour : aucun des deux formats ne la porte.
class ChronologieNonExportee extends PerteExport {
  /// Crée la perte.
  const ChronologieNonExportee();
}

/// Empâtage omis : la recette n'a ni palier ni température du grain (recette à
/// l'extrait). `mash` est facultatif dans `RecipeType`.
class EmpatageNonExporte extends PerteExport {
  /// Crée la perte.
  const EmpatageNonExporte();
}

/// Ébullition omise : sa durée n'est pas renseignée, et `boil` est facultatif
/// dans `RecipeType` (sa durée y est obligatoire).
class EbullitionNonExportee extends PerteExport {
  /// Crée la perte.
  const EbullitionNonExportee();
}

// Pertes propres au BeerXML (`ecriture_beerxml.dart`).

/// Valeur écrite autrement : BeerXML n'a pas la valeur de Kass'Beer.
class ValeurEcriteAutrement extends PerteExport {
  /// Crée la perte.
  const ValeurEcriteAutrement(
    this.ligne,
    this.liste,
    this.champ,
    this.source,
    this.ecrite,
  );

  /// Nom de la ligne (ingrédient, palier).
  final String ligne;

  /// Liste de la ligne.
  final ListeRecette liste;

  /// Champ écrit autrement : [Champ.type], [Champ.forme] ou [Champ.moment].
  final Champ champ;

  /// Valeur BeerJSON de la recette (`honey`, `powder`…) ; pour un moment,
  /// `whirlpool` ou `add_to_package`.
  final String source;

  /// Valeur BeerXML écrite (`Sugar`, `Aroma`, `Pellet`…).
  final String ecrite;
}

/// Volume d'infusion d'un palier d'infusion (`INFUSE_AMOUNT`) : Kass'Beer ne
/// le stocke pas.
class VolumeInfusionNonExporte extends PerteExport {
  /// Crée la perte.
  const VolumeInfusionNonExporte(this.paliers);

  /// Paliers concernés.
  final List<String> paliers;
}

/// Jour d'ajout d'un houblon à cru : BeerXML n'en garde que la durée.
class JourAjoutNonExporte extends PerteExport {
  /// Crée la perte.
  const JourAjoutNonExporte(this.lignes);

  /// Houblons concernés.
  final List<String> lignes;
}

/// Durée après l'arrêt du feu d'un autre ajout : BeerXML n'a pas ce moment ;
/// l'ajout est écrit à l'ébullition, 0 minute.
class DureeApresArretNonExportee extends PerteExport {
  /// Crée la perte.
  const DureeApresArretNonExportee(this.lignes);

  /// Ajouts concernés.
  final List<String> lignes;
}

/// Résultat d'un export.
sealed class ResultatExport {
  const ResultatExport();
}

/// Export impossible : la liste de ce qui manque.
class ExportBloque extends ResultatExport {
  /// Crée le résultat.
  const ExportBloque(this.manques);

  /// Valeurs à compléter, jamais vide.
  final List<ManqueExport> manques;
}

/// Fichier prêt.
class ExportPret extends ResultatExport {
  /// Crée le résultat.
  const ExportPret(this.contenu, this.pertes, this.auteur);

  /// Contenu du fichier, en JSON indenté ou en XML : deux exports de la même
  /// recette donnent le même texte (E7).
  final String contenu;

  /// Informations non exportées.
  final List<PerteExport> pertes;

  /// Auteur écrit dans le fichier (`author`), montré avant l'envoi.
  final String auteur;
}

/// Exporte [recipe] (sous-arbre `recipe` en BeerJSON partiel) en BeerJSON
/// [kVersionEcrite].
///
/// L'auteur écrit est `recipe.author`, sinon [ownerName]. L'appelant passe
/// `owner_name` quand le propriétaire exporte sa recette, `null` sinon : la
/// recette d'un autre membre sans `recipe.author` est bloquée (décision du
/// 2026-11-10 : elle se duplique pour sortir au nom de qui exporte).
/// `efficiency.brewhouse` vaut
/// [rendementEmpatage], le rendement d'empâtage de l'équipement de la recette
/// (amendements de L2). [calcul] : résultat de `computeRecipe` ; seules les
/// valeurs calculées sont écrites. [chronologie] : la recette a une
/// chronologie du jour, qui n'est pas exportée.
ResultatExport exporterBeerJson({
  required Map<String, Object?> recipe,
  required String? ownerName,
  required double? rendementEmpatage,
  required RecipeCalculation? calcul,
  required bool chronologie,
}) {
  final author = _texte(recipe['author']) ?? _texte(ownerName);
  final manques = manquesExportBeerJson(
    recipe: recipe,
    auteur: author,
    rendementEmpatage: rendementEmpatage,
  );
  if (manques.isNotEmpty) return ExportBloque(List.unmodifiable(manques));
  final copie = _copie(recipe) as Map<String, Object?>;
  final pertes = <PerteExport>[];
  final style = copie.remove('style');
  if (style is Map && style['name'] is String) {
    pertes.add(StyleNonExporte(style['name'] as String));
  }
  final mash = _map(copie['mash']);
  if (_maps(mash['mash_steps']).isEmpty && mash['grain_temperature'] == null) {
    copie.remove('mash');
    pertes.add(const EmpatageNonExporte());
  }
  if (_map(copie['boil'])['boil_time'] == null) {
    copie.remove('boil');
    pertes.add(const EbullitionNonExportee());
  }
  if (chronologie) pertes.add(const ChronologieNonExportee());
  final sortie = <String, Object?>{
    ...copie,
    'author': author,
    'efficiency': {
      'brewhouse': {'value': rendementEmpatage, 'unit': '%'},
    },
    if (calcul != null) ..._estimations(calcul),
  };
  final document = {
    'beerjson': {
      'version': kVersionEcrite,
      'recipes': [sortie],
    },
  };
  return ExportPret(
    '${const JsonEncoder.withIndent('  ').convert(document)}\n',
    List.unmodifiable(pertes),
    // Non nul : sans auteur, l'export est bloqué plus haut.
    author!,
  );
}

/// Ce qui manque à [recipe] pour un export BeerJSON, dans l'ordre de la
/// recette ; vide si l'export est possible. [auteur] : auteur retenu (voir
/// [exporterBeerJson]).
List<ManqueExport> manquesExportBeerJson({
  required Map<String, Object?> recipe,
  required String? auteur,
  required double? rendementEmpatage,
}) {
  final manques = <ManqueExport>[];
  void format(ChampExport champ, [List<String> noms = const []]) =>
      manques.add(ManqueDeFormat(champ, List.unmodifiable(noms)));
  void calcul(MissingInputKind kind, [List<IngredientRef> refs = const []]) =>
      manques.add(ManqueDeCalcul(MissingInput(kind, List.unmodifiable(refs))));

  final ingredients = _map(recipe['ingredients']);
  final fermentables = _maps(ingredients['fermentable_additions']);
  final hops = _maps(ingredients['hop_additions']);
  final miscs = _maps(ingredients['miscellaneous_additions']);
  final cultures = _maps(ingredients['culture_additions']);
  final mash = _map(recipe['mash']);
  final steps = _maps(mash['mash_steps']);

  if (recipe['type'] == null) format(ChampExport.typeRecette);
  if (auteur == null) format(ChampExport.auteur);
  if (recipe['batch_size'] == null) calcul(MissingInputKind.batchVolume);
  if (rendementEmpatage == null) calcul(MissingInputKind.mashEfficiency);
  // Sans palier ni température du grain, `mash` est omis (perte) ; l'un sans
  // l'autre bloque : le schéma demande les deux dans `mash`.
  final grain = mash['grain_temperature'] != null;
  if (steps.isEmpty && grain) format(ChampExport.paliers);
  if (steps.isNotEmpty && !grain) format(ChampExport.temperatureGrain);
  final sansType = _noms(steps, (s) => s['type'] == null);
  if (sansType.isNotEmpty) format(ChampExport.typePalier, sansType);
  final sansRendement = _refs(
    fermentables,
    (f) => _map(f['yield'])['fine_grind'] == null,
  );
  if (sansRendement.isNotEmpty) {
    calcul(MissingInputKind.extractYield, sansRendement);
  }
  final sansCouleur = _refs(fermentables, (f) => f['color'] == null);
  if (sansCouleur.isNotEmpty) calcul(MissingInputKind.color, sansCouleur);
  final sansAlpha = _refs(hops, (h) => h['alpha_acid'] == null);
  if (sansAlpha.isNotEmpty) calcul(MissingInputKind.hopAlpha, sansAlpha);
  for (final (champ, cle) in const [
    (ChampExport.typeLevure, 'type'),
    (ChampExport.formeLevure, 'form'),
    (ChampExport.quantiteLevure, 'amount'),
  ]) {
    final noms = _noms(cultures, (c) => c[cle] == null);
    if (noms.isNotEmpty) format(champ, noms);
  }
  final ajoutsSansType = _noms(miscs, (o) => o['type'] == null);
  if (ajoutsSansType.isNotEmpty) format(ChampExport.typeAjout, ajoutsSansType);
  return manques;
}

/// Nom du fichier exporté : nom de la recette sans accents, en minuscules, avec
/// des tirets (`ipa-maison.json`), coupé à 100 caractères ; `recette` si le nom
/// n'a ni lettre ni chiffre. [extension] sans point.
String nomFichierExport(String nomRecette, String extension) {
  var base = normalizeName(nomRecette);
  if (base.length > 100) {
    base = base.substring(0, 100).replaceAll(RegExp(r'-+$'), '');
  }
  return '${base.isEmpty ? 'recette' : base}.$extension';
}

Map<String, Object?> _estimations(RecipeCalculation c) {
  double? v(CalculationResult r) => switch (r) {
    CalculationComputed(:final value) => value,
    CalculationUnavailable() => null,
  };
  final og = v(c.originalGravity);
  final fg = v(c.finalGravity);
  final abv = v(c.alcoholByVolume);
  final ibu = v(c.bitternessIbu);
  final ebc = v(c.colorEbc);
  return {
    if (og != null)
      'original_gravity': {'value': _arrondi(og, 4), 'unit': 'sg'},
    if (fg != null) 'final_gravity': {'value': _arrondi(fg, 4), 'unit': 'sg'},
    if (abv != null)
      'alcohol_by_volume': {'value': _arrondi(abv, 2), 'unit': '%'},
    if (ibu != null)
      'ibu_estimate': {
        'method': 'Tinseth',
        'value': {'value': _arrondi(ibu, 1), 'unit': 'IBUs'},
      },
    if (ebc != null)
      'color_estimate': {'value': _arrondi(ebc, 1), 'unit': 'EBC'},
  };
}

double _arrondi(double value, int decimales) {
  var facteur = 1.0;
  for (var i = 0; i < decimales; i++) {
    facteur *= 10;
  }
  return (value * facteur).round() / facteur;
}

String? _texte(Object? value) => texteExport(value);

/// Texte non blanc, sans blancs de bord, ou `null` (auteur d'un export).
String? texteExport(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

Map<String, Object?> _map(Object? value) => mapExport(value);

/// [value] en map à clés textuelles ; vide si ce n'en est pas une.
Map<String, Object?> mapExport(Object? value) => value is Map
    ? {for (final e in value.entries) '${e.key}': e.value}
    : const {};

List<Map<String, Object?>> _maps(Object? value) => mapsExport(value);

/// [value] en liste de maps ; vide si ce n'en est pas une.
List<Map<String, Object?>> mapsExport(Object? value) =>
    value is List ? [for (final v in value) mapExport(v)] : const [];

List<String> _noms(
  List<Map<String, Object?>> lignes,
  bool Function(Map<String, Object?>) manque,
) => [
  for (final l in lignes)
    if (manque(l)) '${l['name']}',
];

List<IngredientRef> _refs(
  List<Map<String, Object?>> lignes,
  bool Function(Map<String, Object?>) manque,
) => [
  for (final (i, l) in lignes.indexed)
    if (manque(l)) IngredientRef(i, '${l['name']}'),
];

Object? _copie(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final e in value.entries) '${e.key}': _copie(e.value),
  },
  List() => [for (final v in value) _copie(v)],
  _ => value,
};
