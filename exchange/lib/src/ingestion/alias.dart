import 'cles.dart';

/// Table d'alias écrite à la main : noms de DIY Dog (`alxiw/punkapi`,
/// `e6c12ab`) sans correspondance exacte dans les référentiels, et l'entrée
/// qu'ils désignent sans doute possible (`DATA_SOURCES.md`, « Résolution des
/// noms DIY Dog »). Une correspondance douteuse n'est pas écrite : le nom
/// reste non résolu et part dans `import_unresolved/`.
///
/// `label_fr` : libellé français facultatif d'un nom générique (« Malt de
/// Munich »), porté par l'entrée désignée. Les noms de variétés restent tels
/// quels.

/// Alias d'un nom de DIY Dog.
class Alias {
  /// Alias vers l'entrée [cible] (`<nature>-<clé>`).
  const Alias(this.nature, this.nom, this.cible, {this.labelFr})
    : producteur = null,
      produit = null;

  /// Alias d'une levure vers sa souche : [producteur] et [produit] (sa
  /// référence chez le producteur), comparés comme dans l'identifiant.
  const Alias.souche(this.nom, String this.producteur, String this.produit)
    : nature = NatureReferentiel.culture,
      cible = null,
      labelFr = null;

  /// Nature de l'entrée désignée.
  final NatureReferentiel nature;

  /// Nom tel que DIY Dog l'écrit (comparé après normalisation).
  final String nom;

  /// Identifiant de l'entrée, ou `null` pour une souche.
  final String? cible;

  /// Producteur d'une souche.
  final String? producteur;

  /// Référence d'une souche chez son producteur.
  final String? produit;

  /// Libellé français de l'entrée désignée, ou `null`.
  final String? labelFr;
}

/// Producteurs de levure écrits de deux façons selon la source : clé
/// normalisée lue → clé retenue dans l'identifiant.
const Map<String, String> kProducteursEquivalents = {
  'wyeast-labs': 'wyeast',
  'omega-yeast-labs': 'omega-yeast',
};

/// Noms de la liste `hops` de DIY Dog qui ne sont pas des houblons : la ligne
/// va dans `miscellaneous_additions[]`, résolue ou non. Un nom de la liste
/// `hops` qui ne se résout pas en houblon et se résout en ajout y va aussi.
const List<String> kAjoutsDansHoublons = [
  'American Oak Chips Heavy Toast Soaked in Bourbon',
  'American Oak Chips Heavy Toast soaked in Speyside Whisky',
  'American Oak Chips Medium Toast Soaked In Speyside Whisky',
  'American Oak Chips Medium Toast Soaked in Bourbon',
  'American Oak Wood- chip medium toast, Ageing soaked in Bourbon',
  'American Oak Wood- chip medium toast, Ageing soaked in Rye Whisky',
  'Apricot Juice',
  'Black Pepper',
  'Blackberry Concentrate',
  'Blackcurrant Concentrate',
  'Blueberries',
  'Blueberry Juice',
  'Cacao Nibs',
  'Cacoa Nibs',
  'Caramalt',
  'Cardamon',
  'Cascara',
  'Cinnamon Powder',
  'Cloudberries',
  'Coconut Extract',
  'Cold Infused Coffee',
  'Coriander seed',
  'Elderflower',
  'Elderflower Concentrate',
  'French Oak Chips Medium Toast',
  'Fresh Strawberries',
  'Ginger Powder',
  'Golden Honey',
  'Ground Coffee',
  'Guarana Powder',
  'Habanero',
  'Habanero powder',
  'Habenero Powder',
  'Heather Honey',
  'Honey',
  'Juniper Berry',
  'Kola Nut Powder',
  'Lactose',
  'Lemon Concentrate',
  'Lemon Juice',
  'Lemon drop chili',
  'Lingonberry Juice',
  'Mandarin Segements',
  'Mango',
  'Mango Concentrate',
  'Mango Puree',
  'Maple Syrup',
  'Milk Sugars',
  'Oat Husks',
  'Peach Concentrate',
  'Peach Juice',
  'Peppercorn',
  'Peppercorns',
  'Pineapple Juice',
  'Pink Peppercorns',
  'Plum Concentrate',
  'Poppy Seed',
  'Raspberry Juice',
  'Rosemary',
  'Seville Orange Juice',
  'Sodium Chloride',
  'Sour Cherry Puree',
  'Star Anis',
  'Tangerine Extract',
  'Vanilla Extract',
];

const _f = NatureReferentiel.fermentable;
const _h = NatureReferentiel.hop;
const _m = NatureReferentiel.misc;

/// Alias de DIY Dog. Écartés faute de correspondance sûre (relevé du
/// 2026-11-11) : niveaux de crystal sans unité (`Crystal 150`, `Crystal 120`,
/// `Dark Crystal 350`, `Light Crystal`, `Pale Crystal`, `Crystal`), malts sans
/// équivalent dans les sources (`Simpsons T50`, `Double Roasted Crystal`,
/// `Special W`, `Propino`, `Tipple`, `Spring Blend`, `Smoked Warminster`),
/// `Maris Otter Extra Pale` (plus clair que `Maris Otter`), `Flaked Oat
/// Malt`, `Dry Malt Extract`, `Lager Malt`, `White Wheat`, extraits de
/// houblon, mélanges (`Bramling Cross/ First Gold`), `German Comet`,
/// `EXP 366`, `Wyeast 2126` (la souche Bohemian Lager est la 2124),
/// `Peppercorns` et `Cardamon` (couleur non dite), levures de maison et
/// ingrédients absents des référentiels.
const List<Alias> kAlias = [
  // Malts et sucres.
  Alias(
    _f,
    'Extra Pale',
    'fermentable-extra-pale-ale-malt',
    labelFr: 'Malt extra-pâle',
  ),
  Alias(_f, 'Pale Ale', 'fermentable-pale-ale-malt', labelFr: 'Malt pale ale'),
  Alias(_f, 'Caramalt', 'fermentable-simpsons-caramalt'),
  Alias(_f, 'Premium English Caramalt', 'fermentable-simpsons-caramalt'),
  Alias(_f, 'Premium English Cara Malt', 'fermentable-simpsons-caramalt'),
  Alias(_f, 'English Cara Malt', 'fermentable-simpsons-caramalt'),
  Alias(_f, 'Organic Caramalt', 'fermentable-simpsons-caramalt'),
  Alias(_f, 'Munich', 'fermentable-munich-malt', labelFr: 'Malt de Munich'),
  Alias(_f, 'Organic Munich', 'fermentable-munich-malt'),
  Alias(_f, 'Munich Type 1 Light', 'fermentable-munich-i'),
  Alias(_f, 'Munich Malt Type 1', 'fermentable-munich-i'),
  Alias(_f, 'Munich Malt Type 2', 'fermentable-munich-ii'),
  Alias(_f, 'Wheat', 'fermentable-pale-wheat-malt', labelFr: 'Malt de blé'),
  Alias(_f, 'Weyernmann Pale Wheat', 'fermentable-weyermann-pale-wheat-malt'),
  Alias(_f, 'Chocolate Wheat', 'fermentable-weyermann-chocolate-wheat'),
  Alias(
    _f,
    'Torrified Wheat',
    'fermentable-torrified-wheat-malt',
    labelFr: 'Blé torréfié',
  ),
  Alias(_f, 'Raw Wheat', 'fermentable-unmalted-wheat', labelFr: 'Blé cru'),
  Alias(
    _f,
    'Torrified Barley',
    'fermentable-barley-torrefied',
    labelFr: 'Orge torréfiée',
  ),
  Alias(_f, 'Dark Crystal', 'fermentable-simpsons-crystal-dark'),
  Alias(_f, 'Simpsons Dark Crystal Malt', 'fermentable-simpsons-crystal-dark'),
  Alias(_f, 'Medium Crystal', 'fermentable-simpsons-crystal-medium'),
  Alias(_f, 'Medium Crystal Malt', 'fermentable-simpsons-crystal-medium'),
  Alias(_f, 'Crystal medium', 'fermentable-simpsons-crystal-medium'),
  Alias(_f, 'Extra Dark Crystal', 'fermentable-simpsons-crystal-extra-dark'),
  Alias(
    _f,
    'Extra Dark Crystal Malt',
    'fermentable-simpsons-crystal-extra-dark',
  ),
  Alias(
    _f,
    'Chocolate',
    'fermentable-chocolate-malt',
    labelFr: 'Malt chocolat',
  ),
  Alias(_f, 'Organic Chocolate', 'fermentable-chocolate-malt'),
  Alias(_f, 'Carafa Special Malt Type 1', 'fermentable-carafa-special-i'),
  Alias(_f, 'Carafa Special Type 1', 'fermentable-carafa-special-i'),
  Alias(_f, 'Weyermann Carafa Special 1', 'fermentable-carafa-special-i'),
  Alias(_f, 'Weyermann Carafa Special Type 1', 'fermentable-carafa-special-i'),
  // Carafa Special : Carafa sans enveloppe, chez Weyermann.
  Alias(
    _f,
    'Carafa Special Malt Type 2',
    'fermentable-weyermann-dehusked-carafa-ii',
  ),
  Alias(
    _f,
    'Carafa Special Malt Type 3',
    'fermentable-carafa-special-iii-weyermann',
  ),
  Alias(
    _f,
    'Carafa Special Type 3',
    'fermentable-carafa-special-iii-weyermann',
  ),
  Alias(_f, 'Carafa type 3', 'fermentable-carafa-iii'),
  Alias(_f, 'Rye', 'fermentable-rye-malt', labelFr: 'Malt de seigle'),
  Alias(_f, 'Crisp Rye', 'fermentable-rye-malt'),
  Alias(_f, 'Simpsons Rye', 'fermentable-rye-malt'),
  Alias(_f, 'Brown', 'fermentable-brown-malt', labelFr: 'Malt brun'),
  Alias(_f, 'Amber', 'fermentable-amber-malt', labelFr: 'Malt ambré'),
  Alias(_f, 'Pilsner', 'fermentable-pilsner-malt', labelFr: 'Malt pils'),
  Alias(_f, 'Weyernmann Pils', 'fermentable-weyermann-pilsner-malt'),
  Alias(_f, 'Vienna', 'fermentable-vienna-malt', labelFr: 'Malt de Vienne'),
  Alias(_f, 'Black Malt', 'fermentable-black-malt-2-row', labelFr: 'Malt noir'),
  Alias(_f, 'Black Patent', 'fermentable-black-patent-malt'),
  Alias(_f, 'Carapils Malt', 'fermentable-carapils'),
  Alias(_f, 'Weyermann Carapils', 'fermentable-carapils-carafoam'),
  Alias(_f, 'Weyermann Carapils Malt', 'fermentable-carapils-carafoam'),
  Alias(_f, 'CaraRed Malt', 'fermentable-carared'),
  Alias(_f, 'Carahell Malt', 'fermentable-carahell'),
  Alias(_f, 'Caramunich', 'fermentable-caramunich-malt'),
  Alias(_f, 'Weyermann Beech Smoked', 'fermentable-weyermann-smoked-malt'),
  Alias(_f, 'Smoked Weyermann', 'fermentable-weyermann-smoked-malt'),
  Alias(_f, 'Weyermann Smoked', 'fermentable-weyermann-smoked-malt'),
  Alias(
    _f,
    'Acidulated Malt for kettle souring',
    'fermentable-acidulated-malt',
    labelFr: 'Malt acide',
  ),
  Alias(
    _f,
    'Weyernmann Acidulated Malt',
    'fermentable-weyermann-acidulated-malt',
  ),
  Alias(_f, 'Pale Ale Malt - M. Otter', 'fermentable-pale-malt-maris-otter'),
  Alias(_f, 'Dextrose', 'fermentable-corn-sugar-dextrose', labelFr: 'Dextrose'),
  Alias(_f, 'Lactose', 'fermentable-lactose-milk-sugar', labelFr: 'Lactose'),
  Alias(
    _f,
    'White Cane Sugar',
    'fermentable-sugar-table-sucrose',
    labelFr: 'Sucre blanc',
  ),
  // Houblons : abréviations, fautes de frappe, anciens noms et codes.
  Alias(_h, 'H. Blanc', 'hop-hallertau-blanc'),
  Alias(_h, 'H. Mittelfruh', 'hop-hallertau-mittelfruh'),
  Alias(_h, 'H. Taurus', 'hop-hallertau-taurus'),
  Alias(_h, 'Goldings', 'hop-golding'),
  Alias(_h, 'German Cascade', 'hop-cascade'),
  Alias(_h, 'Saphire', 'hop-saphir'),
  Alias(_h, 'Select Spalter', 'hop-spalter-select'),
  Alias(_h, 'Hercules', 'hop-herkules'),
  Alias(_h, 'Mt.Hood', 'hop-mount-hood'),
  // Pacific Hallertau : ancien nom de Pacifica.
  Alias(_h, 'Pacific Hallertau', 'hop-pacifica'),
  Alias(_h, 'NZ Nelson Sauvin', 'hop-nelson-sauvin'),
  // Codes de sélection de Hop Breeding Company.
  Alias(_h, 'HBC 366', 'hop-ekuanot'),
  Alias(_h, 'HBC 369', 'hop-mosaic'),
  Alias(_h, 'HBC 438', 'hop-sabro'),
  // Ajouts écrits dans la liste des houblons.
  Alias(_m, 'Ground Coffee', 'misc-coffee', labelFr: 'Café'),
  Alias(_m, 'Cold Infused Coffee', 'misc-coffee'),
  Alias(
    _m,
    'Coriander seed',
    'misc-coriander-seeds',
    labelFr: 'Graines de coriandre',
  ),
  Alias(_m, 'Cinnamon Powder', 'misc-cinnamon', labelFr: 'Cannelle'),
  Alias(_m, 'Ginger Powder', 'misc-ginger', labelFr: 'Gingembre'),
  Alias(_m, 'Vanilla Extract', 'misc-vanilla', labelFr: 'Vanille'),
  Alias(_m, 'Black Pepper', 'misc-peppercorns-black', labelFr: 'Poivre noir'),
  Alias(
    _m,
    'Pink Peppercorns',
    'misc-peppercorns-pink',
    labelFr: 'Baies roses',
  ),
  Alias(_m, 'Cacao Nibs', 'misc-cocoa-nibs', labelFr: 'Grué de cacao'),
  Alias(_m, 'Cacoa Nibs', 'misc-cocoa-nibs'),
  Alias(
    _m,
    'Juniper Berry',
    'misc-juniper-berries',
    labelFr: 'Baies de genièvre',
  ),
  Alias(_m, 'Star Anis', 'misc-star-anise', labelFr: 'Anis étoilé'),
  Alias(_m, 'Sodium Chloride', 'misc-table-salt', labelFr: 'Sel de table'),
  Alias(_m, 'Habanero', 'misc-habanero-chiles', labelFr: 'Piment habanero'),
  Alias(_m, 'Habanero powder', 'misc-habanero-chiles'),
  Alias(_m, 'Habenero Powder', 'misc-habanero-chiles'),
  Alias(
    _m,
    'French Oak Chips Medium Toast',
    'misc-oak-chips',
    labelFr: 'Copeaux de chêne',
  ),
  Alias(
    _m,
    'American Oak Chips Heavy Toast Soaked in Bourbon',
    'misc-oak-chips',
  ),
  Alias(
    _m,
    'American Oak Chips Heavy Toast soaked in Speyside Whisky',
    'misc-oak-chips',
  ),
  Alias(
    _m,
    'American Oak Chips Medium Toast Soaked In Speyside Whisky',
    'misc-oak-chips',
  ),
  Alias(
    _m,
    'American Oak Chips Medium Toast Soaked in Bourbon',
    'misc-oak-chips',
  ),
  Alias(
    _m,
    'American Oak Wood- chip medium toast, Ageing soaked in Bourbon',
    'misc-oak-chips',
  ),
  Alias(
    _m,
    'American Oak Wood- chip medium toast, Ageing soaked in Rye Whisky',
    'misc-oak-chips',
  ),
  // Levures : souche chez son producteur.
  Alias.souche('W34/70', 'Fermentis', 'W-34/70'),
  Alias.souche('Saflager S189', 'Fermentis', 'S-189'),
  Alias.souche('Be-134', 'Fermentis', 'BE-134'),
  Alias.souche('WB-06', 'Fermentis', 'WB-06'),
  // WLP4000 est une souche de The Yeast Bay, vendue par White Labs.
  Alias.souche('WLP4000 - Vermont Ale', 'The Yeast Bay', 'WLP4000'),
];
