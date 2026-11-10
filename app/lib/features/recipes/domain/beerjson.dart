import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// BeerJSON partiel (ADR-005) : le sous-arbre `recipe` d'un document `recipes/{id}`
/// et d'une copie figée suit `RecipeType` du schéma BeerJSON au commit figé
/// `4370892d44` (`schemas/beerjson-4370892d44/`). Ce fichier porte les unités, les
/// valeurs énumérées du schéma et leur lecture ; `recipe.dart` porte la conversion.

/// Version de l'enveloppe Kass'Beer (`format_version`). Toute autre valeur rend le
/// document illisible.
const kRecipeFormatVersion = 1;

/// Unités canoniques : une seule par grandeur (ADR-005).
abstract final class UniteBeerJson {
  static const gramme = 'g';
  static const litre = 'l';
  static const celsius = 'C';
  static const minute = 'min';
  static const ebc = 'EBC';
  static const pourcent = '%';
}

/// Couple `{value, unit}` à écrire.
Map<String, Object> mesureBeerJson(num value, String unit) => {
  'value': value,
  'unit': unit,
};

/// Lit `format_version` de [data] ; lève [DocumentIllisible] s'il manque ou ne
/// vaut pas [kRecipeFormatVersion]. La valeur n'entre pas dans l'erreur.
void verifierVersionFormat(Map<String, dynamic> data, [String prefix = '']) {
  final value = data['format_version'];
  if (value == kRecipeFormatVersion && value is int) return;
  throw DocumentIllisible(
    '${prefix}format_version',
    value == null
        ? 'version de format absente'
        : 'version de format inconnue (${value.toString().length} caractères)',
  );
}

/// Lecture des grandeurs et des valeurs énumérées de BeerJSON.
extension LectureBeerJson on LecteurChamps {
  /// Valeur du couple [key] exprimé en [unit], ou `null` s'il est absent. Une autre
  /// unité, une unité sans valeur ou une valeur non numérique lève
  /// [DocumentIllisible].
  double? mesure(String key, String unit) =>
      _couple(key, unit)?.nombre('value');

  /// Valeur et unité du couple [key] exprimé dans l'une des unités [units]
  /// (`g` ou `l` pour une quantité), ou `null` s'il est absent. Une autre unité,
  /// une unité sans valeur ou une valeur non numérique lève [DocumentIllisible].
  ({double value, String unit})? mesureParmi(String key, Set<String> units) {
    final couple = objetFacultatif(key);
    if (couple == null) return null;
    final stored = couple.data['unit'];
    if (stored is! String || !units.contains(stored)) {
      throw DocumentIllisible(
        '${couple.prefix}unit',
        stored is String
            ? 'unité inattendue (${stored.length} caractères)'
            : 'unité absente',
      );
    }
    return (value: couple.nombre('value'), unit: stored);
  }

  /// Durée [key] en minutes entières, ou `null` si elle est absente. Une valeur
  /// décimale lève [DocumentIllisible] (`TimeType.value` est un entier).
  int? duree(String key) {
    final couple = _couple(key, UniteBeerJson.minute);
    if (couple == null) return null;
    final value = couple.data['value'];
    if (value is int) return value;
    throw DocumentIllisible('${couple.prefix}value', 'entier attendu');
  }

  LecteurChamps? _couple(String key, String unit) {
    final couple = objetFacultatif(key);
    if (couple == null) return null;
    final stored = couple.data['unit'];
    if (stored != unit) {
      throw DocumentIllisible(
        '${couple.prefix}unit',
        stored is String
            ? 'unité inattendue (${stored.length} caractères)'
            : 'unité absente',
      );
    }
    return couple;
  }

  /// Valeur [key] de l'énumération [values], ou `null` si elle est absente. Une
  /// valeur hors du schéma lève [DocumentIllisible] ; sa longueur seule entre dans
  /// l'erreur.
  String? valeurDe(String key, EnumerationBeerJson values) {
    final value = texteFacultatif(key);
    if (value == null || values.accepte(value)) return value;
    throw DocumentIllisible(
      '$prefix$key',
      'valeur inconnue (${value.length} caractères)',
    );
  }
}

/// Valeurs d'un champ énuméré du schéma. [libelles] : toutes celles du schéma figé,
/// acceptées à la lecture, avec leur libellé court en français (fiche, ligne de
/// l'éditeur, écran du jour) : une valeur importée que l'éditeur ne propose pas
/// s'affiche aussi en français. [proposees] : celles que l'éditeur propose, dans
/// l'ordre du menu. [libellesMenu] : libellé du menu quand il est plus long que le
/// libellé court.
@immutable
class EnumerationBeerJson {
  const EnumerationBeerJson(
    this.libelles, {
    required this.proposees,
    this.libellesMenu = const {},
  });

  final Map<String, String> libelles;
  final List<String> proposees;
  final Map<String, String> libellesMenu;

  /// Vrai si [value] est une valeur du schéma.
  bool accepte(String value) => libelles.containsKey(value);

  /// Libellé court de [value].
  String libelle(String value) => libelles[value] ?? value;

  /// Libellé de [value] dans le menu de l'éditeur.
  String libelleMenu(String value) => libellesMenu[value] ?? libelle(value);
}

/// `RecipeType.type`.
const typesRecette = EnumerationBeerJson(
  {
    'cider': 'Cidre',
    'kombucha': 'Kombucha',
    'soda': 'Soda',
    'other': 'Autre',
    'mead': 'Hydromel',
    'wine': 'Vin',
    'extract': 'Extrait',
    'partial mash': 'Empâtage partiel',
    'all grain': 'Tout grain',
  },
  proposees: ['all grain', 'partial mash', 'extract'],
);

/// `FermentableBase.type`. Le calcul lit la nature par
/// `FermentableKind.ofType` de `brewing/` : extrait, miel, fruit et jus comme un
/// sucre, `other` à préciser. L'éditeur propose Malt et Sucre.
const typesFermentable = EnumerationBeerJson(
  {
    'grain': 'Malt',
    'sugar': 'Sucre',
    'extract': 'Extrait liquide',
    'dry extract': 'Extrait sec',
    'honey': 'Miel',
    'fruit': 'Fruit',
    'juice': 'Jus',
    'other': 'Autre',
  },
  proposees: ['grain', 'sugar'],
);

/// `HopVarietyBase.form`. Le calcul lit la forme par `HopForm.ofBeerJson` de
/// `brewing/` : `plug` comme des cônes ; poudre, extrait et cônes frais sans
/// facteur d'utilisation. L'éditeur propose Pellets et Cônes.
const formesHoublon = EnumerationBeerJson(
  {
    'pellet': 'Pellets',
    'leaf': 'Cônes',
    'plug': 'Cônes pressés',
    'leaf (wet)': 'Cônes frais',
    'powder': 'Poudre',
    'extract': 'Extrait',
  },
  proposees: ['pellet', 'leaf'],
);

/// `CultureBase.type`.
const typesLevure = EnumerationBeerJson(
  {
    'ale': 'Haute fermentation (ale)',
    'bacteria': 'Autres bactéries',
    'brett': 'Brettanomyces',
    'champagne': 'Champagne',
    'kveik': 'Kveik',
    'lacto': 'Lactobacilles',
    'lager': 'Basse fermentation (lager)',
    'malolactic': 'Bactéries malolactiques',
    'mixed-culture': 'Culture mixte',
    'other': 'Autre',
    'pedio': 'Pédiocoques',
    'spontaneous': 'Fermentation spontanée',
    'wheat': 'Levure de blanche',
    'wine': 'Vin',
  },
  proposees: [
    'ale',
    'lager',
    'kveik',
    'brett',
    'lacto',
    'pedio',
    'mixed-culture',
    'champagne',
    'wine',
    'spontaneous',
    'malolactic',
    'bacteria',
    'other',
  ],
);

/// `CultureBase.form`.
const formesLevure = EnumerationBeerJson(
  {
    'liquid': 'Liquide',
    'dry': 'Sèche',
    'slant': 'Gélose',
    'culture': 'Culture',
    'dregs': 'Lie',
  },
  proposees: ['dry', 'liquid'],
);

/// `MiscellaneousBase.type`.
const typesAjout = EnumerationBeerJson(
  {
    'spice': 'Épice',
    'fining': 'Clarifiant',
    'water agent': "Correction de l'eau",
    'herb': 'Herbe',
    'flavor': 'Arôme',
    'wood': 'Bois',
    'other': 'Autre',
  },
  proposees: [
    'water agent',
    'fining',
    'spice',
    'herb',
    'flavor',
    'wood',
    'other',
  ],
);

/// `MashStepType.type`.
const typesPalier = EnumerationBeerJson(
  {
    'infusion': 'Infusion',
    'temperature': "Chauffe de la cuve d'empâtage",
    'decoction': 'Décoction',
    'souring mash': "Acidification à l'empâtage",
    'souring wort': 'Acidification du moût',
    'drain mash tun': "Vidange de la cuve d'empâtage",
    'sparge': 'Rinçage',
  },
  proposees: [
    'infusion',
    'temperature',
    'decoction',
    'sparge',
    'drain mash tun',
    'souring mash',
    'souring wort',
  ],
  libellesMenu: {'infusion': 'Infusion (eau chaude ajoutée)'},
);

/// `TimingType.use`.
abstract final class UsageBeerJson {
  static const mash = 'add_to_mash';
  static const boil = 'add_to_boil';
  static const fermentation = 'add_to_fermentation';
  static const package = 'add_to_package';
}

/// Nom écrit dans `recipe.mash.name`, obligatoire dans le schéma : un libellé.
const kNomEmpatage = 'Empâtage';
