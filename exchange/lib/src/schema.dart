/// Valeurs énumérées et champs de `RecipeType` au commit figé `4370892d44` du
/// schéma BeerJSON (`schemas/beerjson-4370892d44/`). Les tests du paquet les
/// comparent aux fichiers du schéma.
library;

/// `RecipeType.type`.
const Set<String> kTypesRecette = {
  'cider',
  'kombucha',
  'soda',
  'other',
  'mead',
  'wine',
  'extract',
  'partial mash',
  'all grain',
};

/// `FermentableBase.type`.
const Set<String> kTypesFermentable = {
  'dry extract',
  'extract',
  'grain',
  'sugar',
  'fruit',
  'juice',
  'honey',
  'other',
};

/// `HopVarietyBase.form`.
const Set<String> kFormesHoublon = {
  'extract',
  'leaf',
  'leaf (wet)',
  'pellet',
  'powder',
  'plug',
};

/// `CultureBase.type`.
const Set<String> kTypesLevure = {
  'ale',
  'bacteria',
  'brett',
  'champagne',
  'kveik',
  'lacto',
  'lager',
  'malolactic',
  'mixed-culture',
  'other',
  'pedio',
  'spontaneous',
  'wheat',
  'wine',
};

/// `CultureBase.form`.
const Set<String> kFormesLevure = {
  'liquid',
  'dry',
  'slant',
  'culture',
  'dregs',
};

/// `MiscellaneousBase.type`.
const Set<String> kTypesAjout = {
  'spice',
  'fining',
  'water agent',
  'herb',
  'flavor',
  'wood',
  'other',
};

/// `MashStepType.type`.
const Set<String> kTypesPalier = {
  'infusion',
  'temperature',
  'decoction',
  'souring mash',
  'souring wort',
  'drain mash tun',
  'sparge',
};

/// `TimingType.use`.
const Set<String> kUsages = {
  'add_to_mash',
  'add_to_boil',
  'add_to_fermentation',
  'add_to_package',
};

/// Versions de BeerJSON lues : 1.x, 2.x et 3 (ADR-005).
const Set<int> kVersionsLues = {1, 2, 3};

/// Version écrite par l'export : 2.01, candidate d'ADR-005, à confirmer par un
/// essai d'import dans Brewtarget.
const double kVersionEcrite = 2.01;
