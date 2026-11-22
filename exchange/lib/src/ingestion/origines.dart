/// Origines des houblons et des malts (ADR-014, « Origines ») : liste fermée
/// des pays, en graphie anglaise la plus fréquente dans les sources, et table
/// des graphies lues. Une graphie absente de la table laisse `origin` absent et
/// part au rapport de préparation : aucune origine n'est devinée. Le champ
/// reste un texte (`HopVarietyType.origin`, `FermentableType.origin`).
library;

/// Pays connus, en graphie canonique. Seule copie de cette liste (P56).
const Set<String> kPays = {
  'Argentina',
  'Australia',
  'Austria',
  'Belgium',
  'Canada',
  'China',
  'Czech Republic',
  'France',
  'Germany',
  'Great Britain',
  'Japan',
  'Netherlands',
  'New Zealand',
  'Poland',
  'Russia',
  'Serbia',
  'Slovenia',
  'South Africa',
  'Sweden',
  'Ukraine',
  'United States',
};

/// Nom français de chaque pays de [kPays], écrit par la préparation à côté de
/// `origin` (`origin_fr`), que l'application affiche. `origin` reste la
/// graphie canonique anglaise, lue par l'export, la génération des arômes et
/// la table de fusion. Seule copie de ces noms (P56) : une entrée par pays.
const Map<String, String> kPaysFr = {
  'Argentina': 'Argentine',
  'Australia': 'Australie',
  'Austria': 'Autriche',
  'Belgium': 'Belgique',
  'Canada': 'Canada',
  'China': 'Chine',
  'Czech Republic': 'République tchèque',
  'France': 'France',
  'Germany': 'Allemagne',
  'Great Britain': 'Royaume-Uni',
  'Japan': 'Japon',
  'Netherlands': 'Pays-Bas',
  'New Zealand': 'Nouvelle-Zélande',
  'Poland': 'Pologne',
  'Russia': 'Russie',
  'Serbia': 'Serbie',
  'Slovenia': 'Slovénie',
  'South Africa': 'Afrique du Sud',
  'Sweden': 'Suède',
  'Ukraine': 'Ukraine',
  'United States': 'États-Unis',
};

/// Nom français du pays canonique [pays]. Un pays sans nom français lève
/// [StateError] : la table est fausse, aucun nom n'est deviné.
String paysEnFrancais(String pays) =>
    kPaysFr[pays] ?? (throw StateError('pays sans nom français : $pays'));

/// Graphies relevées dans les sources (mesure du 2026-11-15) et leur pays.
/// Les clés sont comparées sans casse, espaces réduites ([cleOrigine]).
const Map<String, String> kGraphiesOrigine = {
  'us': 'United States',
  'usa': 'United States',
  'united states of america (usa)': 'United States',
  'germany (ger)': 'Germany',
  'united kingdom': 'Great Britain',
  'united kingdom (uk)': 'Great Britain',
  'uk': 'Great Britain',
  'england': 'Great Britain',
  'czech replublic (czh)': 'Czech Republic',
  'new zealand (nz)': 'New Zealand',
  'new zealand, canterbury': 'New Zealand',
  'australia (aus)': 'Australia',
  'poland (pol)': 'Poland',
  'slovenia (slo)': 'Slovenia',
  'france (fr)': 'France',
  'canada (can)': 'Canada',
  'china (cn)': 'China',
};

/// Clé de comparaison d'une graphie : minuscules, espaces de tête et de fin
/// retirées, suites d'espaces réduites à une.
String cleOrigine(String graphie) =>
    graphie.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

final Map<String, String> _parCle = {
  for (final pays in kPays) cleOrigine(pays): pays,
  ...kGraphiesOrigine,
};

/// Pays canonique de [graphie], ou `null` si la graphie est inconnue ou
/// désigne plusieurs pays (`Austria/Slovenia`).
String? paysDeGraphie(String graphie) => _parCle[cleOrigine(graphie)];
