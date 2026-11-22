/// Sources de l'ingestion des référentiels et des recettes publiques (ADR-005,
/// `documentation/DATA_SOURCES.md`) : identifiant, version figée, licence et
/// date du relevé, recopiés dans `provenance[]` de chaque document.
library;

/// Version figée de Brewtarget : tag et commit.
const kVersionBrewtarget = 'v5.2.3 ea10908';

/// Version figée de `alxiw/punkapi` (DIY Dog) : commit.
const kVersionDiyDog = 'e6c12ab';

/// Date du relevé des sources de Brewtarget et de DIY Dog.
const kDateReleve = '2026-11-08';

/// Valeur de `provenance[].source` d'un style de la Brewers Association
/// (ADR-018). Elle n'est pas dans [Source] : sa version est l'édition du
/// guide, lue dans la table de décisions, et une préparation sans `--ba` ne
/// la cite pas.
const kSourceBa = 'brewers-association';

/// Date du relevé des fiches techniques de chaque fabricant
/// (`exchange/donnees/fabricants/cultures.json`), par clé de producteur
/// (`cleProducteur`). Elle tient lieu de version dans `provenance[]`. Une
/// entrée d'un producteur absent de cette table est refusée.
const Map<String, String> kDatesReleveFabricants = {
  'fermentis': '2026-11-14',
  'mangrove-jack-s': '2026-11-15',
  'imperial-yeast': '2026-11-15',
  'omega-yeast': '2026-11-15',
  'white-labs': '2026-11-15',
  'the-yeast-bay': '2026-11-15',
  'wyeast': '2026-11-15',
  'escarpment-labs': '2026-11-15',
};

/// Date du relevé le plus récent de [dates] : version de la source
/// `fabricants` au rapport ; `null` si [dates] est vide.
String? dernierReleve(Map<String, String> dates) {
  String? dernier;
  for (final d in dates.values) {
    if (dernier == null || d.compareTo(dernier) > 0) dernier = d;
  }
  return dernier;
}

/// Licences écrites dans `provenance[].licence`.
abstract final class Licence {
  /// Brewtarget 001, 003, 004 et la part non CC BY-SA du 005.
  static const gpl3 = 'GPL-3.0';

  /// Part beer-analytics.com du fichier 005.
  static const ccBySa4 = 'CC BY-SA 4.0';

  /// Styles BJCP 2021 du fichier 002.
  static const bjcp = 'BJCP (noms et plages)';

  /// Styles de la Brewers Association (ADR-018, décision 1).
  static const ba = 'BA (usage gratuit, mention de la BA)';

  /// Recettes DIY Dog.
  static const diyDog = 'DIY Dog (usage privé)';

  /// Valeurs recopiées à la main des fiches techniques publiées par les
  /// fabricants (décision de l'utilisateur du 2026-11-14).
  static const fabricant = 'Données publiées par le fabricant';
}

/// Source lue, et son rang de priorité pour un même ingrédient (0 d'abord) :
/// fiches des fabricants, puis 005, puis 003 et 004, puis 001
/// (`DATA_SOURCES.md`, décision 4).
enum Source {
  /// `fabricants/cultures.json`, BeerJSON 2.01 écrit à la main depuis les
  /// fiches techniques des fabricants.
  fabricants('fabricants', 0, 'cultures.json'),

  /// `DefaultContent001-OriginalDefaultData.xml`, BeerXML.
  brewtarget001(
    'brewtarget-001',
    3,
    'DefaultContent001-OriginalDefaultData.xml',
  ),

  /// `DefaultContent002-BJCP_2021_Styles.json`, BeerJSON 2.01.
  brewtarget002('brewtarget-002', 2, 'DefaultContent002-BJCP_2021_Styles.json'),

  /// `DefaultContent003-Ingredients-Hops-Yeasts.json`, BeerJSON 2.01.
  brewtarget003(
    'brewtarget-003',
    2,
    'DefaultContent003-Ingredients-Hops-Yeasts.json',
  ),

  /// `DefaultContent004-MoreYeasts.json`, BeerJSON 2.01.
  brewtarget004('brewtarget-004', 2, 'DefaultContent004-MoreYeasts.json'),

  /// `DefaultContent005-Fermentables-Recipes.beer`, DotBeer 1.0.0.
  brewtarget005(
    'brewtarget-005',
    1,
    'DefaultContent005-Fermentables-Recipes.beer',
  ),

  /// `alxiw/punkapi`, `data/NNN.json`.
  diydog('diydog', 4, 'data');

  const Source(this.id, this.rang, this.fichier);

  /// Valeur de `provenance[].source`.
  final String id;

  /// Rang de priorité : le plus petit donne les valeurs d'une fusion.
  final int rang;

  /// Fichier ou dossier de la source, sous son dossier dans `import/sources/`.
  final String fichier;

  /// Version figée de la source ; pour les fiches des fabricants, date du
  /// relevé le plus récent de [datesFabricants], et [StateError] si la table
  /// est vide.
  String version([
    Map<String, String> datesFabricants = kDatesReleveFabricants,
  ]) => switch (this) {
    diydog => kVersionDiyDog,
    fabricants =>
      dernierReleve(datesFabricants) ??
          (throw StateError('aucune date de relevé des fabricants')),
    _ => kVersionBrewtarget,
  };
}

/// Ligne de `provenance[]`. [releveFabricant] : date du relevé de la fiche,
/// obligatoire pour [Source.fabricants], qui la prend pour version.
Map<String, Object> provenance(
  Source source,
  String sourceId,
  String licence, {
  String? releveFabricant,
}) {
  if (source == Source.fabricants && releveFabricant == null) {
    throw ArgumentError.notNull('releveFabricant');
  }
  return {
    'source': source.id,
    'source_id': sourceId,
    'version': releveFabricant ?? source.version(),
    'licence': licence,
    'retrieved': releveFabricant ?? kDateReleve,
  };
}

/// Licence d'une entrée du fichier 005 selon son `folder_path` : The Swaen,
/// la Canadian Homebrewers Association et les exemples dotBeer (agents de
/// l'eau) restent sous la GPL-3 générale ; le reste vient de
/// beer-analytics.com, sous CC BY-SA 4.0 (en-tête du fichier, ADR-005).
String licence005(String? folderPath) {
  if (folderPath == 'The Swaen' ||
      folderPath == 'Canadian Homebrewers Association' ||
      (folderPath != null && folderPath.startsWith('Water Agents'))) {
    return Licence.gpl3;
  }
  return Licence.ccBySa4;
}
