import 'bornes.dart';
import 'compte_rendu.dart';
import 'noms.dart';
import 'schema.dart';

/// Résolution des noms d'une recette importée contre la Bibliothèque
/// (ADR-005, E5) : correspondance exacte après normalisation ([cleNormalisee])
/// du nom ou d'un alias, puis, pour une levure, producteur et référence, et en
/// dernier une référence lue dans le nom (lettres et chiffres). Aucune
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
      if (liste != ListeRecette.levures) continue;
      final p = e.producteur;
      final cp = p == null ? '' : cleProducteur(p);
      if (cp.isNotEmpty) _producteurs.add(cp);
      final r = e.reference;
      if (r == null) continue;
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
  final Set<String> _producteurs = {};

  static void _ajouter(
    Map<String, Set<EntreeBibliotheque>> table,
    String cle,
    EntreeBibliotheque e,
  ) => table.putIfAbsent(cle, () => {}).add(e);

  static EntreeBibliotheque? _seule(Set<EntreeBibliotheque>? entrees) =>
      entrees != null && entrees.length == 1 ? entrees.single : null;

  /// Poids écrit dans un nom (`10g`, `11-5-g` joint en `115g`, `500-ml`) :
  /// jamais lu comme une référence.
  static final RegExp _poids = RegExp(r'^\d+(?:g|gr|kg|mg|l|ml|cl)$');

  /// Candidats au plus d'une correspondance partielle : levures dont le nom,
  /// un alias ou le producteur portent tous les mots de [cle]
  /// (`belle-saison-lallemand` désigne LalBrew Belle Saison de Lallemand).
  /// Jamais une résolution : ces entrées ne servent qu'à lister des candidats.
  static const int _maxCandidatsPartiels = 10;

  Set<EntreeBibliotheque> _parMotsDuNom(String cle) {
    final mots = cle.split('-').toSet();
    final trouves = <EntreeBibliotheque>{};
    for (final e in _parId.values) {
      final motsEntree = <String>{
        for (final n in [e.nom, ...e.alias, ?e.producteur])
          ...cleNormalisee(n).split('-'),
      };
      if (motsEntree.containsAll(mots)) trouves.add(e);
      if (trouves.length > _maxCandidatsPartiels) return const {};
    }
    return trouves;
  }

  /// Entrées d'une levure désignées par une référence lue dans [cle] (clé
  /// normalisée du nom), quand aucune autre voie n'aboutit : chaque suite
  /// d'un à trois segments consécutifs, jointe sans tiret (`s23`, `be-256`
  /// donne `be256`, `w-34-70` donne `w3470`), qui porte au moins une lettre et
  /// un chiffre et n'est pas un poids, est cherchée parmi les références
  /// (`product_id`) de la Bibliothèque. Une référence faite de chiffres seuls
  /// n'est pas lue ainsi : Wyeast passe par [soucheDuNom]. White Labs, indexé
  /// en `wlpNNN`, est lu ainsi aussi.
  Set<EntreeBibliotheque> _parJetonsReference(String cle) {
    final segments = cle.split('-');
    final trouves = <EntreeBibliotheque>{};
    for (var debut = 0; debut < segments.length; debut++) {
      for (var n = 1; n <= 3 && debut + n <= segments.length; n++) {
        final jeton = segments.sublist(debut, debut + n).join();
        if (!jeton.contains(RegExp(r'[a-z]')) ||
            !jeton.contains(RegExp(r'\d')) ||
            _poids.hasMatch(jeton)) {
          continue;
        }
        trouves.addAll(_parReference[jeton] ?? const {});
      }
    }
    return trouves;
  }

  /// Clés des producteurs de la Bibliothèque écrits dans [cle] (suites d'un à
  /// trois segments, après [kProducteursEquivalents]).
  Set<String> _producteursDuNom(String cle) {
    final segments = cle.split('-');
    return {
      for (var debut = 0; debut < segments.length; debut++)
        for (var n = 1; n <= 3 && debut + n <= segments.length; n++)
          if (_producteurs.contains(
            cleProducteur(segments.sublist(debut, debut + n).join('-')),
          ))
            cleProducteur(segments.sublist(debut, debut + n).join('-')),
    };
  }

  /// Identifiants, triés, des entrées que [nom] désigne par l'une des voies de
  /// [resoudre] : identifiant (`<nature>-<clé du nom>`), nom ou alias ; pour
  /// une levure, aussi souche lue dans le nom, référence, producteur et
  /// référence, puis référence lue dans le nom ; si aucune de ces voies ne
  /// donne rien, les levures qui portent tous les mots du nom
  /// ([_parMotsDuNom], dix au plus). Pour les voies de [resoudre], vide ou d'au
  /// moins 2 entrées quand [resoudre] rend `null`, sauf une référence lue
  /// dans un nom qui cite un autre producteur (une entrée, refusée) ; une
  /// correspondance partielle peut n'en donner qu'une, jamais choisie. Sert
  /// à dire pourquoi un nom n'est pas résolu et à lister ses candidats
  /// (`exchange/bin/lister_ingredients_recettes.dart`, ADR-013 et ADR-017).
  List<String> candidats(String nom) => candidatsAvecOrigine(nom).ids;

  /// [candidats], et `partiels` vrai s'ils viennent de la seule
  /// correspondance partielle ([_parMotsDuNom]) : ils ne disent pas qu'un nom
  /// désigne plusieurs entrées.
  ({List<String> ids, bool partiels}) candidatsAvecOrigine(String nom) {
    final cle = cleNormalisee(nom);
    if (cle.isEmpty) return (ids: const [], partiels: false);
    var partiels = false;
    final trouves = <EntreeBibliotheque>{
      ?_parId['$_prefixe-$cle'],
      ...?_parNom[cle],
    };
    if (liste == ListeRecette.levures) {
      final souche = soucheDuNom(nom);
      if (souche != null) {
        final cp = cleProducteur(souche.producteur);
        trouves.addAll(
          _parSouche['$cp|${cleProduit(cp, souche.produit)}'] ?? const {},
        );
      }
      trouves.addAll(_parReference[cle.replaceAll('-', '')] ?? const {});
      final segments = cle.split('-');
      for (var i = 1; i < segments.length; i++) {
        final cp = cleProducteur(segments.take(i).join('-'));
        final cr = cleProduit(cp, segments.skip(i).join('-'));
        trouves.addAll(_parSouche['$cp|$cr'] ?? const {});
      }
      if (trouves.isEmpty) trouves.addAll(_parJetonsReference(cle));
      if (trouves.isEmpty) {
        trouves.addAll(_parMotsDuNom(cle));
        partiels = trouves.isNotEmpty;
      }
    }
    return (ids: [for (final e in trouves) e.id]..sort(), partiels: partiels);
  }

  /// Entrée de [nom], ou `null` si aucune ou plusieurs correspondent.
  ///
  /// Dans l'ordre : l'entrée d'identifiant `<nature>-<clé du nom>` ; la seule
  /// entrée dont le nom ou un alias a la clé de [nom] ; pour une levure, la
  /// seule souche lue dans le nom (`Wyeast 1056`, `WLP001`, [soucheDuNom]),
  /// puis la seule entrée de cette référence (`US-05`), puis la seule de ce
  /// producteur et de cette référence (`Fermentis US-05`), puis la seule
  /// désignée par une référence lue dans le nom ([_parJetonsReference]), si
  /// le nom ne nomme pas un autre producteur de la Bibliothèque.
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
    // En dernier, une référence lue dans le nom écrit à la main
    // (`BOHEMIAN LAGER M84 MANGROVE JACK`, `SafeLager S23`), seulement si une
    // seule souche la porte et si le nom ne nomme pas un autre producteur
    // (`Labo Fictif Z23` pour un Z23 de Sèche Fictive) ; sinon, ses candidats
    // sont listés.
    final e = _seule(_parJetonsReference(cle));
    if (e == null) return null;
    final nommes = _producteursDuNom(cle);
    final p = e.producteur;
    if (nommes.isNotEmpty &&
        (p == null || !nommes.contains(cleProducteur(p)))) {
      return null;
    }
    return e;
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
