/// Sources de l'ingestion des référentiels et des recettes publiques (ADR-005,
/// `documentation/DATA_SOURCES.md`) : identifiant, version figée, licence et
/// date du relevé, recopiés dans `provenance[]` de chaque document.
library;

/// Version figée de Brewtarget : tag et commit.
const kVersionBrewtarget = 'v5.2.3 ea10908';

/// Version figée de `alxiw/punkapi` (DIY Dog) : commit.
const kVersionDiyDog = 'e6c12ab';

/// Date du relevé des sources.
const kDateReleve = '2026-11-08';

/// Licences écrites dans `provenance[].licence`.
abstract final class Licence {
  /// Brewtarget 001, 003, 004 et la part non CC BY-SA du 005.
  static const gpl3 = 'GPL-3.0';

  /// Part beer-analytics.com du fichier 005.
  static const ccBySa4 = 'CC BY-SA 4.0';

  /// Styles BJCP 2021 du fichier 002.
  static const bjcp = 'BJCP (noms et plages)';

  /// Recettes DIY Dog.
  static const diyDog = 'DIY Dog (usage privé)';
}

/// Source lue, et son rang de priorité pour un même ingrédient (0 d'abord) :
/// 005, puis 003 et 004, puis 001 (`DATA_SOURCES.md`, décision 4).
enum Source {
  /// `DefaultContent001-OriginalDefaultData.xml`, BeerXML.
  brewtarget001(
    'brewtarget-001',
    2,
    'DefaultContent001-OriginalDefaultData.xml',
  ),

  /// `DefaultContent002-BJCP_2021_Styles.json`, BeerJSON 2.01.
  brewtarget002('brewtarget-002', 1, 'DefaultContent002-BJCP_2021_Styles.json'),

  /// `DefaultContent003-Ingredients-Hops-Yeasts.json`, BeerJSON 2.01.
  brewtarget003(
    'brewtarget-003',
    1,
    'DefaultContent003-Ingredients-Hops-Yeasts.json',
  ),

  /// `DefaultContent004-MoreYeasts.json`, BeerJSON 2.01.
  brewtarget004('brewtarget-004', 1, 'DefaultContent004-MoreYeasts.json'),

  /// `DefaultContent005-Fermentables-Recipes.beer`, DotBeer 1.0.0.
  brewtarget005(
    'brewtarget-005',
    0,
    'DefaultContent005-Fermentables-Recipes.beer',
  ),

  /// `alxiw/punkapi`, `data/NNN.json`.
  diydog('diydog', 3, 'data');

  const Source(this.id, this.rang, this.fichier);

  /// Valeur de `provenance[].source`.
  final String id;

  /// Rang de priorité : le plus petit donne les valeurs d'une fusion.
  final int rang;

  /// Fichier ou dossier de la source, sous son dossier dans `import/sources/`.
  final String fichier;

  /// Version figée de la source.
  String get version => this == diydog ? kVersionDiyDog : kVersionBrewtarget;
}

/// Ligne de `provenance[]`.
Map<String, Object> provenance(
  Source source,
  String sourceId,
  String licence,
) => {
  'source': source.id,
  'source_id': sourceId,
  'version': source.version,
  'licence': licence,
  'retrieved': kDateReleve,
};

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
