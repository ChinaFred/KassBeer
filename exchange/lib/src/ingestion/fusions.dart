import 'cles.dart';
import 'lecture_sources.dart';
import 'referentiel.dart';
import 'sources.dart';

/// Table de fusion écrite à la main (ADR-014, « Table de fusion »), distincte
/// de la table d'alias de DIY Dog (`alias.dart`). Règle : une variété et un
/// pays de culture font un document. Le nom court désigne la variété dans son
/// pays d'origine (`Saaz` tchèque) ; une culture ailleurs garde son document,
/// nommé avec le pays (`Saaz (US)`). Deux noms d'une même variété fusionnent
/// (`Sultana` et `Denali`). Valeurs de l'entrée la plus prioritaire du groupe
/// (005, puis 003 et 004, puis 001) ; origine imposée quand cette entrée la
/// porte fausse. Table validée par l'utilisateur le 2026-11-15.
///
/// Chaque ligne a son cas de test (`exchange/test/fusions_test.dart`). Une
/// ligne qui ne désigne aucune entrée lue arrête la préparation
/// ([StateError]).

/// Entrée d'une source désignée par une ligne de fusion.
class EntreeDesignee {
  /// Entrée de [source] nommée [nom] (comparé après normalisation), et
  /// d'origine [origine] si elle est donnée (graphie canonique, après la table
  /// des graphies) : deux entrées de même nom se distinguent ainsi (`Saaz`
  /// américain du fichier 005).
  const EntreeDesignee(this.source, this.nom, {this.origine});

  /// Source de l'entrée.
  final Source source;

  /// Nom lu.
  final String nom;

  /// Origine lue, ou `null` pour toute origine.
  final String? origine;

  /// Vrai si [e] est désignée.
  bool designe(EntreeBrute e) =>
      e.nature == NatureReferentiel.hop &&
      e.source == source &&
      cleNormalisee(e.nom) == cleNormalisee(nom) &&
      (origine == null || e.origine == origine);

  @override
  String toString() =>
      '${source.id} « $nom »${origine == null ? '' : ' ($origine)'}';
}

/// Ligne de la table : un document de houblon.
class Fusion {
  /// Crée la ligne.
  const Fusion(
    this.nom, {
    required this.entrees,
    this.origine,
    this.alias = const [],
    this.ecartes = const [],
  });

  /// Nom du document ; son identifiant est `hop-<cleNormalisee(nom)>`.
  final String nom;

  /// Origine imposée au document, ou `null` pour celle de l'entrée qui donne
  /// les valeurs.
  final String? origine;

  /// Entrées rattachées au document, en plus de celles dont le nom donne déjà
  /// son identifiant.
  final List<EntreeDesignee> entrees;

  /// Noms ajoutés aux `aliases` (nom commercial, abréviation).
  final List<String> alias;

  /// Noms écartés des `aliases` : un nom faux d'une source (`Saaz` pour une
  /// culture américaine) ne désigne pas ce document.
  final List<String> ecartes;

  /// Identifiant du document.
  String get id => idEntree(NatureReferentiel.hop, cleNormalisee(nom));
}

const _s005 = Source.brewtarget005;
const _s003 = Source.brewtarget003;
const _s001 = Source.brewtarget001;

/// Table de fusion des houblons.
const List<Fusion> kFusions = [
  // Saaz : le nom court désigne le Saaz tchèque.
  Fusion(
    'Saaz',
    origine: 'Czech Republic',
    entrees: [
      EntreeDesignee(_s003, 'Saaz (CZ)'),
      EntreeDesignee(_s001, 'Saaz (Czech Republic)'),
    ],
  ),
  Fusion(
    'Saaz (US)',
    entrees: [
      EntreeDesignee(_s005, 'Saaz', origine: 'United States'),
      EntreeDesignee(_s001, 'Saaz (USA)'),
    ],
    ecartes: ['Saaz'],
  ),
  // Magnum : variété allemande.
  Fusion(
    'Magnum',
    origine: 'Germany',
    entrees: [EntreeDesignee(_s003, 'Magnum (GR)')],
  ),
  Fusion(
    'Magnum (US)',
    entrees: [EntreeDesignee(_s005, 'Magnum', origine: 'United States')],
    ecartes: ['Magnum'],
  ),
  Fusion(
    'Northern Brewer',
    entrees: [EntreeDesignee(_s003, 'Northern Brewer (GR)')],
  ),
  Fusion('Perle', entrees: [EntreeDesignee(_s003, 'Perle (GR)')]),
  Fusion(
    "Brewer's Gold",
    entrees: [EntreeDesignee(_s003, "Brewer's Gold (GR)")],
  ),
  Fusion(
    'East Kent Goldings',
    entrees: [
      EntreeDesignee(_s005, 'East Kent Golding'),
      EntreeDesignee(_s005, 'East Kent Goldings (EKG)'),
      EntreeDesignee(_s005, 'East Kent Goldings (EKG) (1)'),
    ],
  ),
  // Hallertau : noms du fichier 005 (« Hallertauer … ») gardés, noms du 003
  // (« Hallertau … ») en alias.
  Fusion(
    'Hallertauer Blanc',
    entrees: [EntreeDesignee(_s003, 'Hallertau Blanc')],
  ),
  Fusion(
    'Hallertauer Gold',
    entrees: [EntreeDesignee(_s003, 'Hallertau Gold')],
  ),
  Fusion(
    'Hallertauer Taurus',
    origine: 'Germany',
    entrees: [EntreeDesignee(_s003, 'Hallertau Taurus')],
  ),
  Fusion(
    'Hallertauer Tradition',
    entrees: [EntreeDesignee(_s003, 'Hallertau Tradition')],
  ),
  Fusion(
    'Hallertauer Mittelfrüh',
    entrees: [
      EntreeDesignee(_s003, 'Hallertau Mittelfrüh'),
      EntreeDesignee(_s005, 'Hallertauer Mittelfrueh'),
      EntreeDesignee(_s001, 'Hallertau'),
    ],
  ),
  Fusion(
    'Tettnang',
    entrees: [
      EntreeDesignee(_s005, 'Tettnanger'),
      EntreeDesignee(_s003, 'Tettnanger'),
    ],
  ),
  // Denali : ancien nom commercial de Sultana (décision 3).
  Fusion(
    'Sultana',
    entrees: [EntreeDesignee(_s003, 'Sultana (Denali)')],
    alias: ['Denali'],
  ),
  Fusion(
    'Columbus',
    entrees: [
      EntreeDesignee(_s001, 'Columbus/Tomahawk/Zeus'),
      EntreeDesignee(_s005, 'Columbus/Tomahawk/Zeus (CTZ)'),
      // Documents à part dans le fichier 003 (relevé du 2026-11-15) : même
      // variété, leurs noms deviennent des alias.
      EntreeDesignee(_s003, 'CTZ'),
      EntreeDesignee(_s003, 'Tomahawk'),
      EntreeDesignee(_s003, 'Zeus'),
    ],
  ),
];

/// Sources de Brewtarget qui portent des cultures.
const Set<Source> _sourcesBrewtarget = {
  Source.brewtarget001,
  Source.brewtarget003,
  Source.brewtarget004,
  Source.brewtarget005,
};

/// Ligne de la table de fusion des cultures : la fiche d'un fabricant qui ne
/// publie aucune référence (`product_id`) et le document Brewtarget de la
/// même souche, sous un autre nom (décision de l'utilisateur du 2026-11-15).
///
/// La ligne désigne l'entrée de la source `fabricants` de [producteur] et de
/// nom [nom], et les entrées de Brewtarget de [producteur] et de nom
/// [nomBrewtarget] (noms comparés après normalisation). Toutes rejoignent un
/// seul document, d'identifiant [id] : celui que Brewtarget donne déjà, pour
/// ne laisser aucun ancien document à côté du nouveau. La fiche, prioritaire,
/// donne les valeurs et le nom ; le nom Brewtarget passe en alias.
class FusionCulture {
  /// Crée la ligne.
  const FusionCulture(this.producteur, this.nom, {required this.nomBrewtarget});

  /// Producteur, tel que les sources l'écrivent.
  final String producteur;

  /// Nom de la fiche du fabricant.
  final String nom;

  /// Nom du document Brewtarget de la même souche.
  final String nomBrewtarget;

  /// Identifiant du document : celui des entrées Brewtarget, sans référence.
  String get id => idEntree(
    NatureReferentiel.culture,
    cleCulture(nomBrewtarget, producteur, null),
  );

  bool _culture(EntreeBrute e, String n) =>
      e.nature == NatureReferentiel.culture &&
      e.producteur != null &&
      cleProducteur(e.producteur!) == cleProducteur(producteur) &&
      cleNormalisee(e.nom) == cleNormalisee(n);

  /// Vrai si [e] est la fiche désignée.
  bool designeFiche(EntreeBrute e) =>
      e.source == Source.fabricants && _culture(e, nom);

  /// Vrai si [e] est une entrée Brewtarget désignée.
  bool designeBrewtarget(EntreeBrute e) =>
      _sourcesBrewtarget.contains(e.source) && _culture(e, nomBrewtarget);

  @override
  String toString() => '$producteur « $nom » → « $nomBrewtarget »';
}

/// Table de fusion des cultures. Chaque ligne a son cas dans
/// `exchange/test/fabricants_donnees_test.dart` (fiche présente dans
/// `donnees/fabricants/cultures.json`) ; la règle est essayée par
/// `exchange/test/fusions_test.dart` sur des fixtures inventées.
const List<FusionCulture> kFusionsCultures = [
  FusionCulture(
    'Escarpment Labs',
    'Ardennes Ale',
    nomBrewtarget: 'Ardennes Belgian Ale',
  ),
  FusionCulture(
    'Escarpment Labs',
    'Classic Wit',
    nomBrewtarget: 'Classic Witbier',
  ),
  FusionCulture(
    'Escarpment Labs',
    'Fruity Wit',
    nomBrewtarget: 'Fruity Witbier',
  ),
  FusionCulture(
    'Escarpment Labs',
    'Fruit Bomb Saison Blend',
    nomBrewtarget: 'Fruit Bomb Saison',
  ),
  FusionCulture(
    'Escarpment Labs',
    'New World Saison Blend',
    nomBrewtarget: 'New World Saison',
  ),
  // 005 écrit « St. Lucifer Belgian Ale », 004 « St Lucifer Belgian Ale » :
  // même clé normalisée.
  FusionCulture(
    'Escarpment Labs',
    'St. Lucifer',
    nomBrewtarget: 'St. Lucifer Belgian Ale',
  ),
  FusionCulture(
    'Escarpment Labs',
    'Chaudron Sûr',
    nomBrewtarget: 'Lactobacillus Blend',
  ),
];
