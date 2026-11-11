import 'bornes.dart';
import 'compte_rendu.dart';
import 'noms.dart';
import 'schema.dart';

/// Résolution des noms d'une recette importée contre la Bibliothèque
/// (ADR-005, E5) : correspondance exacte après normalisation ([cleNormalisee])
/// du nom ou d'un alias, puis, pour une levure, producteur et référence. Aucune
/// correspondance floue. Une valeur absente du fichier est reprise de l'entrée
/// résolue, comme l'ingestion le fait pour une recette publique (D4) ; une
/// valeur du fichier n'est jamais remplacée. Les index arrivent en paramètre :
/// ce fichier ne lit rien.

/// Valeur de `import_unresolved.nature` pour chaque liste résolue.
const Map<ListeRecette, String> kNaturesNonResolues = {
  ListeRecette.malts: 'fermentable',
  ListeRecette.houblons: 'hop',
  ListeRecette.levures: 'culture',
  ListeRecette.ajouts: 'misc',
};

/// Entrée d'un index de la Bibliothèque (`beer_index/{nature}`), avec les
/// valeurs qu'un import peut reprendre. Nombres en unités canoniques : `%`,
/// `EBC`.
class EntreeBibliotheque {
  /// Crée l'entrée.
  const EntreeBibliotheque({
    required this.id,
    required this.nom,
    this.alias = const [],
    this.producteur,
    this.reference,
    this.type,
    this.rendement,
    this.couleur,
    this.alpha,
    this.forme,
    this.attenuation,
  });

  /// Identifiant de la fiche (`fermentable-pilsner`).
  final String id;

  /// Nom de l'entrée.
  final String nom;

  /// Autres noms de l'entrée.
  final List<String> alias;

  /// Producteur d'une levure.
  final String? producteur;

  /// Référence d'une levure chez son producteur (`product_id`).
  final String? reference;

  /// Type d'un malt, d'une levure ou d'un autre ajout (valeur BeerJSON).
  final String? type;

  /// Rendement d'extrait d'un malt, en %.
  final double? rendement;

  /// Couleur d'un malt, en EBC.
  final double? couleur;

  /// Acides alpha d'un houblon, en %.
  final double? alpha;

  /// Forme d'un houblon ou d'une levure (valeur BeerJSON).
  final String? forme;

  /// Atténuation d'une levure, en % (milieu de la plage de la fiche).
  final double? attenuation;
}

/// Index d'une liste de recette, prêt pour la recherche exacte d'un nom.
class IndexBibliotheque {
  /// Indexe [entrees] pour [liste] (malts, houblons, ajouts ou levures).
  IndexBibliotheque(this.liste, List<EntreeBibliotheque> entrees) {
    final prefixe = kNaturesNonResolues[liste];
    if (prefixe == null) throw ArgumentError.value(liste, 'liste');
    _prefixe = prefixe;
    for (final e in entrees) {
      _parId[e.id] = e;
      for (final n in {e.nom, ...e.alias}) {
        final cle = cleNormalisee(n);
        if (cle.isNotEmpty) _ajouter(_parNom, cle, e);
      }
      final r = e.reference;
      if (liste != ListeRecette.levures || r == null) continue;
      final p = e.producteur;
      final cp = p == null ? '' : cleProducteur(p);
      final cr = cleProduit(cp, r);
      if (cr.isEmpty) continue;
      _ajouter(_parReference, cr, e);
      if (cp.isNotEmpty) _ajouter(_parSouche, '$cp|$cr', e);
    }
  }

  /// Liste résolue.
  final ListeRecette liste;

  late final String _prefixe;
  final Map<String, EntreeBibliotheque> _parId = {};
  final Map<String, Set<EntreeBibliotheque>> _parNom = {};
  final Map<String, Set<EntreeBibliotheque>> _parReference = {};
  final Map<String, Set<EntreeBibliotheque>> _parSouche = {};

  static void _ajouter(
    Map<String, Set<EntreeBibliotheque>> table,
    String cle,
    EntreeBibliotheque e,
  ) => table.putIfAbsent(cle, () => {}).add(e);

  static EntreeBibliotheque? _seule(Set<EntreeBibliotheque>? entrees) =>
      entrees != null && entrees.length == 1 ? entrees.single : null;

  /// Entrée de [nom], ou `null` si aucune ou plusieurs correspondent.
  ///
  /// Dans l'ordre : l'entrée d'identifiant `<nature>-<clé du nom>` ; la seule
  /// entrée dont le nom ou un alias a la clé de [nom] ; pour une levure, la
  /// seule souche lue dans le nom (`Wyeast 1056`, `WLP001`, [soucheDuNom]),
  /// puis la seule entrée de cette référence (`US-05`), puis la seule de ce
  /// producteur et de cette référence (`Fermentis US-05`).
  EntreeBibliotheque? resoudre(String nom) {
    final cle = cleNormalisee(nom);
    if (cle.isEmpty) return null;
    final direct = _parId['$_prefixe-$cle'];
    if (direct != null) return direct;
    final exact = _seule(_parNom[cle]);
    if (exact != null || liste != ListeRecette.levures) return exact;
    final souche = soucheDuNom(nom);
    if (souche != null) {
      final cp = cleProducteur(souche.producteur);
      final e = _seule(_parSouche['$cp|${cleProduit(cp, souche.produit)}']);
      if (e != null) return e;
    }
    final parReference = _seule(_parReference[cle.replaceAll('-', '')]);
    if (parReference != null) return parReference;
    final segments = cle.split('-');
    for (var i = 1; i < segments.length; i++) {
      final cp = cleProducteur(segments.take(i).join('-'));
      final cr = cleProduit(cp, segments.skip(i).join('-'));
      final e = _seule(_parSouche['$cp|$cr']);
      if (e != null) return e;
    }
    return null;
  }
}

/// Index lus pour un import. Une liste sans index n'est ni résolue ni
/// signalée : aucun nom n'y est compté comme non résolu.
class IndexImport {
  /// Crée l'ensemble.
  const IndexImport({this.malts, this.houblons, this.ajouts, this.levures});

  /// Index des malts et sucres.
  final IndexBibliotheque? malts;

  /// Index des houblons.
  final IndexBibliotheque? houblons;

  /// Index des autres ajouts.
  final IndexBibliotheque? ajouts;

  /// Index des levures.
  final IndexBibliotheque? levures;

  /// Vrai si les quatre index sont là.
  bool get complet =>
      malts != null && houblons != null && ajouts != null && levures != null;
}

/// Nom d'une ligne qu'aucune entrée de la Bibliothèque ne résout.
class NomNonResolu {
  /// Crée le nom.
  const NomNonResolu(this.nature, this.nom);

  /// `fermentable`, `hop`, `culture` ou `misc` ([kNaturesNonResolues]).
  final String nature;

  /// Nom de la ligne, tel que la recette lue le porte.
  final String nom;

  /// Nom normalisé ([cleNormalisee]), 100 caractères au plus : `key` du
  /// document, que les règles hachent pour vérifier l'identifiant.
  String get cle => cleNormalisee(nom);

  /// Identifiant de `import_unresolved/` ([empreinteNonResoluImport]), distinct
  /// de celui de l'ingestion pour le même nom.
  String get empreinte => empreinteNonResoluImport(nature, nom);
}

/// Recette complétée par la Bibliothèque.
class RecetteCompletee {
  /// Crée le résultat.
  const RecetteCompletee(this.recipe, this.reprises, this.nonResolus);

  /// Sous-arbre `recipe`, avec les valeurs reprises.
  final Map<String, Object?> recipe;

  /// Valeurs reprises, dans l'ordre de la recette.
  final List<ValeurReprise> reprises;

  /// Noms non résolus, une fois chacun, dans l'ordre de la recette.
  final List<NomNonResolu> nonResolus;
}

/// Complète [recipe] (sous-arbre `recipe` lu par `exchange/`) avec [index].
///
/// Pour chaque ligne dont le nom se résout ([IndexBibliotheque.resoudre]), une
/// valeur absente est reprise de l'entrée si elle est valide pour le schéma :
/// malt `type`, `yield.fine_grind` et `color` ; houblon `alpha_acid` et
/// `form` ; levure `type`, `form` et `attenuation` ; autre ajout `type`.
/// [recipe] n'est pas modifiée.
RecetteCompletee completerRecette(
  Map<String, Object?> recipe,
  IndexImport index,
) {
  final reprises = <ValeurReprise>[];
  final nonResolus = <String, NomNonResolu>{};
  final ingredients = recipe['ingredients'];
  if (ingredients is! Map) return RecetteCompletee(recipe, const [], const []);
  final nouveaux = Map<String, Object?>.of(ingredients.cast<String, Object?>());

  for (final (cle, liste, idx) in [
    ('fermentable_additions', ListeRecette.malts, index.malts),
    ('hop_additions', ListeRecette.houblons, index.houblons),
    ('miscellaneous_additions', ListeRecette.ajouts, index.ajouts),
    ('culture_additions', ListeRecette.levures, index.levures),
  ]) {
    final lignes = ingredients[cle];
    if (idx == null || lignes is! List) continue;
    nouveaux[cle] = [
      for (final ligne in lignes)
        if (ligne is Map)
          _completerLigne(
            liste,
            idx,
            Map<String, Object?>.of(ligne.cast<String, Object?>()),
            reprises,
            nonResolus,
          )
        else
          ligne,
    ];
  }
  return RecetteCompletee(
    {...recipe, 'ingredients': nouveaux},
    List.unmodifiable(reprises),
    List.unmodifiable(nonResolus.values),
  );
}

Map<String, Object?> _completerLigne(
  ListeRecette liste,
  IndexBibliotheque index,
  Map<String, Object?> ligne,
  List<ValeurReprise> reprises,
  Map<String, NomNonResolu> nonResolus,
) {
  final nom = ligne['name'];
  if (nom is! String) return ligne;
  final e = index.resoudre(nom);
  if (e == null) {
    final n = NomNonResolu(kNaturesNonResolues[liste]!, nom);
    nonResolus.putIfAbsent(n.empreinte, () => n);
    return ligne;
  }
  void reprendre(String cle, Object? valeur, Champ champ) {
    if (ligne[cle] != null || valeur == null) return;
    ligne[cle] = valeur;
    reprises.add(ValeurReprise(Grandeur(champ, nom), liste));
  }

  switch (liste) {
    case ListeRecette.malts:
      reprendre('type', _parmi(e.type, kTypesFermentable), Champ.type);
      final rendement = ligne['yield'];
      final fin = rendement is Map ? rendement['fine_grind'] : null;
      final r = _pourcent(e.rendement);
      if (fin == null && r != null) {
        ligne['yield'] = {
          if (rendement is Map) ...rendement.cast<String, Object?>(),
          'fine_grind': {'value': r, 'unit': '%'},
        };
        reprises.add(ValeurReprise(Grandeur(Champ.rendement, nom), liste));
      }
      final c = e.couleur;
      reprendre(
        'color',
        c != null && c >= 0 && c <= kMaxEbc
            ? {'value': c, 'unit': 'EBC'}
            : null,
        Champ.couleur,
      );
    case ListeRecette.houblons:
      final a = _pourcent(e.alpha);
      reprendre(
        'alpha_acid',
        a == null ? null : {'value': a, 'unit': '%'},
        Champ.acidesAlpha,
      );
      reprendre('form', _parmi(e.forme, kFormesHoublon), Champ.forme);
    case ListeRecette.levures:
      reprendre('type', _parmi(e.type, kTypesLevure), Champ.type);
      reprendre('form', _parmi(e.forme, kFormesLevure), Champ.forme);
      final a = _pourcent(e.attenuation);
      reprendre(
        'attenuation',
        a == null ? null : {'value': a, 'unit': '%'},
        Champ.attenuation,
      );
    case ListeRecette.ajouts:
      reprendre('type', _parmi(e.type, kTypesAjout), Champ.type);
    case ListeRecette.paliers:
      break;
  }
  return ligne;
}

/// [valeur] si elle appartient à [valeurs] du schéma, sinon `null`.
String? _parmi(String? valeur, Set<String> valeurs) =>
    valeur != null && valeurs.contains(valeur) ? valeur : null;

/// [valeur] si elle est un pourcentage strictement positif, 100 au plus.
double? _pourcent(double? valeur) =>
    valeur != null && valeur > 0 && valeur <= 100 ? valeur : null;
