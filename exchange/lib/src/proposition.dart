import 'package:brewing/brewing.dart';

import 'bornes.dart';
import 'compte_rendu.dart';
import 'lecture_beerjson.dart';
import 'marques_ia.dart';
import 'noms.dart';
import 'resolution_import.dart';
import 'texte.dart';

/// Proposition de l'assistant de recette (ADR-015, section 6, lot A2 ; P61) :
/// lecture bornée, puis application sur une copie de la recette, côté client
/// seul. Le vocabulaire des opérations est celui de
/// `test-fixtures/recipe_assistant_operations.json`, rejoué par
/// `exchange/test/proposition_test.dart` et, pour le format de sortie, par
/// `functions/test/proposition.test.ts`. Aucune formule de brassage : les
/// chiffres de l'aperçu viennent de `computeRecipe` (P3). Le paquet ne fait
/// aucun `catch`.

/// Nombre maximal d'opérations d'une proposition.
const int kMaxOperationsProposition = 30;

/// Longueur maximale du résumé d'une proposition.
const int kMaxResumeProposition = 500;

/// Type d'un champ d'opération.
enum TypeChamp {
  /// Texte.
  texte('string'),

  /// Valeur d'une liste fermée.
  valeurs('enum'),

  /// Nombre fini.
  nombre('number'),

  /// Nombre entier.
  entier('integer');

  const TypeChamp(this.code);

  /// Nom dans la fixture.
  final String code;
}

/// Champ d'une opération : type et bornes.
class SpecChamp {
  /// Texte de [longueurMin] à [longueurMax] caractères.
  const SpecChamp.texte(this.longueurMin, this.longueurMax)
    : type = TypeChamp.texte,
      valeurs = const [],
      minimum = null,
      minimumExclu = null,
      maximum = null;

  /// Valeur de [valeurs].
  const SpecChamp.valeurs(this.valeurs)
    : type = TypeChamp.valeurs,
      longueurMin = null,
      longueurMax = null,
      minimum = null,
      minimumExclu = null,
      maximum = null;

  /// Nombre, au-dessus de [minimumExclu] ou à partir de [minimum], jusqu'à
  /// [maximum].
  const SpecChamp.nombre({this.minimum, this.minimumExclu, this.maximum})
    : type = TypeChamp.nombre,
      valeurs = const [],
      longueurMin = null,
      longueurMax = null;

  /// Entier de [minimum] à [maximum].
  const SpecChamp.entier({this.minimum, this.maximum})
    : type = TypeChamp.entier,
      valeurs = const [],
      minimumExclu = null,
      longueurMin = null,
      longueurMax = null;

  /// Type du champ.
  final TypeChamp type;

  /// Valeurs permises ([TypeChamp.valeurs]).
  final List<String> valeurs;

  /// Bornes d'un texte.
  final int? longueurMin;

  /// Bornes d'un texte.
  final int? longueurMax;

  /// Bornes d'un nombre.
  final num? minimum;

  /// Bornes d'un nombre.
  final num? minimumExclu;

  /// Bornes d'un nombre.
  final num? maximum;

  /// Forme de la fixture.
  Map<String, Object?> versJson() => {
    'type': type.code,
    if (type == TypeChamp.valeurs) 'values': valeurs,
    'min_length': ?longueurMin,
    'max_length': ?longueurMax,
    'minimum': ?minimum,
    'exclusive_minimum': ?minimumExclu,
    'maximum': ?maximum,
  };

  /// Vrai si [valeur] a le type du champ (lecture, comme le serveur).
  bool aLeType(Object? valeur) => switch (type) {
    TypeChamp.texte => valeur is String,
    TypeChamp.valeurs => valeur is String && valeurs.contains(valeur),
    TypeChamp.nombre => valeur is num && valeur.isFinite,
    TypeChamp.entier =>
      valeur is num && valeur.isFinite && valeur == valeur.roundToDouble(),
  };

  /// Vrai si [valeur], du bon type, est dans les bornes (application).
  bool dansLesBornes(Object? valeur) {
    if (valeur is String) {
      final n = valeur.length;
      return (longueurMin == null || n >= longueurMin!) &&
          (longueurMax == null || n <= longueurMax!);
    }
    if (valeur is num) {
      return (minimum == null || valeur >= minimum!) &&
          (minimumExclu == null || valeur > minimumExclu!) &&
          (maximum == null || valeur <= maximum!);
    }
    return true;
  }
}

/// Opération : champs, dans l'ordre, et champs requis.
class SpecOperation {
  /// Crée l'opération.
  const SpecOperation(this.champs, this.requis);

  /// Champs permis (hors `op`).
  final Map<String, SpecChamp> champs;

  /// Champs requis.
  final List<String> requis;

  /// Forme de la fixture.
  Map<String, Object?> versJson() => {
    'fields': {for (final e in champs.entries) e.key: e.value.versJson()},
    'required': requis,
  };
}

const _nom = SpecChamp.texte(1, 120);
const _index = SpecChamp.entier(minimum: 0, maximum: 49);
const _indexPalier = SpecChamp.entier(minimum: 0, maximum: 19);
const _grammes = SpecChamp.nombre(minimumExclu: 0, maximum: 1000000);
const _pourcent = SpecChamp.nombre(minimumExclu: 0, maximum: 100);
const _minutes = SpecChamp.entier(minimum: 0, maximum: 600);
const _typesMalt = SpecChamp.valeurs([
  'grain',
  'sugar',
  'dry extract',
  'extract',
  'fruit',
  'juice',
  'honey',
  'other',
]);
const _formesHoublon = SpecChamp.valeurs([
  'pellet',
  'leaf',
  'leaf (wet)',
  'plug',
  'powder',
  'extract',
]);
const _usagesHoublon = SpecChamp.valeurs(['boil', 'whirlpool', 'dry_hop']);
const _momentsAjout = SpecChamp.valeurs([
  'mash',
  'boil',
  'after_boil',
  'fermentation',
  'bottling',
]);

const _champsMalt = {
  'name': _nom,
  'type': _typesMalt,
  'amount_g': _grammes,
  'color_ebc': SpecChamp.nombre(minimum: 0, maximum: 2000),
  'yield_pct': _pourcent,
};
const _champsHoublon = {
  'name': _nom,
  'form': _formesHoublon,
  'amount_g': _grammes,
  'use': _usagesHoublon,
  'time_min': _minutes,
  'days': SpecChamp.nombre(minimumExclu: 0, maximum: 365),
  'alpha_acid_pct': _pourcent,
};
const _champsAjout = {
  'name': _nom,
  'amount_g': _grammes,
  'amount_l': SpecChamp.nombre(minimumExclu: 0, maximum: 1000),
  'moment': _momentsAjout,
  'time_min': _minutes,
};
const _champsPalier = {
  'name': _nom,
  'temperature_c': SpecChamp.nombre(minimum: 0, maximum: 100),
  'time_min': _minutes,
};
const _retrait = SpecOperation(
  {'index': _index, 'name': _nom},
  ['index', 'name'],
);

/// Liste fermée des opérations d'une proposition, copie de `operations` dans
/// `test-fixtures/recipe_assistant_operations.json`. Aucune opération ne
/// porte `notes`, `author` ni `brew_steps` (ADR-015).
const Map<String, SpecOperation> kOperationsProposition = {
  'set_name': SpecOperation({'value': _nom}, ['value']),
  'set_type': SpecOperation(
    {
      'value': SpecChamp.valeurs([
        'all grain',
        'partial mash',
        'extract',
        'cider',
        'kombucha',
        'soda',
        'mead',
        'wine',
        'other',
      ]),
    },
    ['value'],
  ),
  'set_style_name': SpecOperation({'value': _nom}, ['value']),
  'set_batch_size_l': SpecOperation(
    {'value': SpecChamp.nombre(minimumExclu: 0, maximum: 10000)},
    ['value'],
  ),
  'set_boil_time_min': SpecOperation({'value': _minutes}, ['value']),
  'add_fermentable': SpecOperation(_champsMalt, ['name', 'type', 'amount_g']),
  'update_fermentable': SpecOperation(
    {'index': _index, ..._champsMalt},
    ['index', 'name', 'type', 'amount_g'],
  ),
  'remove_fermentable': _retrait,
  'add_hop': SpecOperation(_champsHoublon, ['name', 'form', 'amount_g', 'use']),
  'update_hop': SpecOperation(
    {'index': _index, ..._champsHoublon},
    ['index', 'name', 'form', 'amount_g', 'use'],
  ),
  'remove_hop': _retrait,
  'add_misc': SpecOperation(_champsAjout, ['name', 'moment']),
  'update_misc': SpecOperation(
    {'index': _index, ..._champsAjout},
    ['index', 'name', 'moment'],
  ),
  'remove_misc': _retrait,
  'set_culture': SpecOperation(
    {
      'name': _nom,
      'type': SpecChamp.valeurs([
        'ale',
        'lager',
        'wheat',
        'wine',
        'champagne',
        'kveik',
        'brett',
        'lacto',
        'pedio',
        'bacteria',
        'malolactic',
        'mixed-culture',
        'spontaneous',
        'other',
      ]),
      'form': SpecChamp.valeurs(['dry', 'liquid', 'slant', 'culture', 'dregs']),
      'attenuation_pct': _pourcent,
    },
    ['name'],
  ),
  'add_mash_step': SpecOperation(_champsPalier, [
    'name',
    'temperature_c',
    'time_min',
  ]),
  'update_mash_step': SpecOperation(
    {'index': _indexPalier, ..._champsPalier},
    ['index', 'name', 'temperature_c', 'time_min'],
  ),
  'remove_mash_step': SpecOperation(
    {'index': _indexPalier, 'name': _nom},
    ['index', 'name'],
  ),
};

/// Champs d'opération qui portent une valeur technique (`technical_fields`
/// de la fixture) : nature et champ de la marque `ai_proposed`.
const Map<String, ({String nature, String champ})> kChampsTechniques = {
  'color_ebc': (nature: 'fermentable', champ: 'color'),
  'yield_pct': (nature: 'fermentable', champ: 'yield'),
  'alpha_acid_pct': (nature: 'hop', champ: 'alpha_acid'),
  'attenuation_pct': (nature: 'culture', champ: 'attenuation'),
};

// --- Lecture ----------------------------------------------------------------

/// Opération lue : son nom et ses champs (sans `op`).
class OperationProposee {
  /// Crée l'opération.
  const OperationProposee(this.op, this.champs);

  /// Nom de l'opération ([kOperationsProposition]).
  final String op;

  /// Champs, du type de leur spécification.
  final Map<String, Object?> champs;
}

/// Proposition lue.
class Proposition {
  /// Crée la proposition.
  const Proposition(this.resume, this.operations);

  /// Résumé écrit par le modèle, texte simple.
  final String resume;

  /// Opérations, dans l'ordre, de 1 à [kMaxOperationsProposition].
  final List<OperationProposee> operations;
}

/// Résultat de [lireProposition].
sealed class LectureProposition {
  const LectureProposition();
}

/// Proposition conforme au format.
class PropositionLue extends LectureProposition {
  /// Crée le résultat.
  const PropositionLue(this.proposition);

  /// La proposition.
  final Proposition proposition;
}

/// Proposition hors format : elle n'est pas proposée.
class PropositionIllisible extends LectureProposition {
  /// Crée le résultat.
  const PropositionIllisible(this.chemin);

  /// Chemin du premier champ en faute (`operations.2.amount_g`), sans valeur.
  final String chemin;
}

/// Lit [brut], la clé `proposition` d'une réponse de l'assistant : objet
/// `{resume, operations}` et rien d'autre ; résumé de 1 à
/// [kMaxResumeProposition] caractères ; de 1 à [kMaxOperationsProposition]
/// opérations, chacune de [kOperationsProposition], avec ses champs requis,
/// aucun autre champ, chaque champ de son type. Les bornes des valeurs ne sont
/// pas vérifiées ici : [appliquerProposition] refuse l'opération seule.
LectureProposition lireProposition(Object? brut) {
  if (brut is! Map) return const PropositionIllisible('');
  for (final cle in brut.keys) {
    if (cle != 'resume' && cle != 'operations') {
      return const PropositionIllisible('');
    }
  }
  final resume = brut['resume'];
  if (resume is! String ||
      resume.isEmpty ||
      resume.length > kMaxResumeProposition) {
    return const PropositionIllisible('resume');
  }
  final operations = brut['operations'];
  if (operations is! List ||
      operations.isEmpty ||
      operations.length > kMaxOperationsProposition) {
    return const PropositionIllisible('operations');
  }
  final lues = <OperationProposee>[];
  for (var i = 0; i < operations.length; i++) {
    final chemin = 'operations.$i';
    final o = operations[i];
    if (o is! Map) return PropositionIllisible(chemin);
    final nom = o['op'];
    final spec = nom is String ? kOperationsProposition[nom] : null;
    if (spec == null) return PropositionIllisible('$chemin.op');
    final champs = <String, Object?>{};
    for (final e in o.entries) {
      final cle = e.key;
      if (cle == 'op') continue;
      final champ = cle is String ? spec.champs[cle] : null;
      // Le chemin ne cite que des noms de la liste fermée, comme le serveur.
      if (champ == null) return PropositionIllisible('$chemin.<champ inconnu>');
      if (!champ.aLeType(e.value)) return PropositionIllisible('$chemin.$cle');
      champs[cle as String] = e.value;
    }
    for (final requis in spec.requis) {
      if (!champs.containsKey(requis)) {
        return PropositionIllisible('$chemin.$requis');
      }
    }
    lues.add(OperationProposee(nom! as String, Map.unmodifiable(champs)));
  }
  return PropositionLue(Proposition(resume, List.unmodifiable(lues)));
}

// --- Application ------------------------------------------------------------

/// Raison du refus d'une opération.
enum RaisonRefusOperation {
  /// L'index ne désigne aucune ligne de la liste.
  indexAbsent('index_absent'),

  /// La ligne de cet index ne porte plus le nom de l'opération (modification
  /// ou retrait) : la recette a changé depuis la proposition (décision de
  /// l'utilisateur du 2026-11-21).
  elementChange('element_changed'),

  /// Une valeur sort de ses bornes, ou un nom d'ingrédient n'a ni lettre ni
  /// chiffre.
  horsBornes('hors_bornes'),

  /// Une valeur nécessaire manque (durée d'un houblon, quantité d'un ajout).
  valeurManquante('valeur_manquante'),

  /// Un champ ne va pas avec un autre (`days` avec `boil`, `amount_g` et
  /// `amount_l`).
  champIncompatible('champ_incompatible'),

  /// La liste a déjà son plafond de lignes (`firestore.rules`).
  listePleine('liste_pleine');

  const RaisonRefusOperation(this.code);

  /// Code de la fixture.
  final String code;
}

/// Opération refusée : les autres s'appliquent.
class RefusOperation {
  /// Crée le refus.
  const RefusOperation(this.index, this.op, this.raison, this.champ);

  /// Rang de l'opération dans la proposition.
  final int index;

  /// Nom de l'opération.
  final String op;

  /// Raison du refus.
  final RaisonRefusOperation raison;

  /// Champ en cause, ou `null`.
  final String? champ;
}

/// Résultat de [appliquerProposition].
sealed class ResultatProposition {
  const ResultatProposition();

  /// Opérations refusées, dans l'ordre.
  List<RefusOperation> get refusOperations;
}

/// Recette relue après la proposition : elle peut remplacer le brouillon.
class PropositionAppliquee extends ResultatProposition {
  /// Crée le résultat.
  const PropositionAppliquee({
    required this.recipe,
    required this.marques,
    required this.refusOperations,
    required this.reprises,
    required this.modifications,
  });

  /// Sous-arbre `recipe` relu par [lireRecettePartielle].
  final Map<String, Object?> recipe;

  /// Marques `ai_proposed` après la proposition : celles d'avant (sauf
  /// ingrédient retiré, ou valeur remplacée par la Bibliothèque), puis
  /// celles des valeurs du modèle.
  final List<MarqueIa> marques;

  @override
  final List<RefusOperation> refusOperations;

  /// Valeurs reprises de la Bibliothèque pour les lignes ajoutées ou
  /// modifiées.
  final List<ValeurReprise> reprises;

  /// Ce que la relecture a changé (texte coupé, caractères retirés…).
  final List<Modification> modifications;
}

/// Recette refusée par la relecture : la proposition n'est pas proposée.
class PropositionRefusee extends ResultatProposition {
  /// Crée le résultat.
  const PropositionRefusee(this.refus, this.refusOperations);

  /// Refus de la relecture.
  final Refus refus;

  @override
  final List<RefusOperation> refusOperations;
}

/// Applique [operations] à une copie de [recipe] (sous-arbre `recipe` en
/// BeerJSON partiel), dans l'ordre ; [recipe] et [marques] ne sont pas
/// modifiés.
///
/// Un `index` désigne la ligne telle que les opérations précédentes ont
/// laissé la liste. Une opération dont l'index n'existe plus, dont le `name`
/// ne correspond pas à la ligne de cet index (modification ou retrait :
/// [RaisonRefusOperation.elementChange]), dont une valeur sort des bornes ou
/// dont une valeur nécessaire manque est refusée et listée ; les autres s'appliquent.
///
/// Valeurs techniques d'une ligne ajoutée ou modifiée (couleur, rendement,
/// acides alpha, atténuation) : le nom se résout dans [bibliotheque]
/// ([IndexBibliotheque.resoudre]) et [completerRecette] reprend ses valeurs,
/// comme Recettes › Importer ; une valeur de la Bibliothèque passe toujours
/// avant celle du modèle. Sans valeur dans la Bibliothèque, la valeur du
/// modèle est gardée et marquée ([MarqueIa]). Une ligne modifiée qui garde sa
/// clé d'ingrédient garde ses valeurs et leurs marques quand l'opération ne
/// les donne pas ; un renommage passe par un retrait puis un ajout. Une
/// liste sans index dans [bibliotheque] n'est pas résolue.
///
/// Le résultat passe par [lireRecettePartielle] : une recette refusée rend
/// [PropositionRefusee].
ResultatProposition appliquerProposition(
  Map<String, Object?> recipe,
  List<MarqueIa> marques,
  List<OperationProposee> operations, {
  required IndexImport bibliotheque,
}) {
  final application = _Application(
    _copie(recipe) as Map<String, Object?>,
    marques,
    bibliotheque,
  );
  for (var i = 0; i < operations.length; i++) {
    application.appliquer(i, operations[i]);
  }
  final refusOperations = List<RefusOperation>.unmodifiable(application.refus);
  final relue = lireRecettePartielle(application.recipe);
  switch (relue) {
    case RecetteRefusee(:final refus):
      return PropositionRefusee(refus, refusOperations);
    case RecetteLue(recipe: final r, :final modifications):
      return PropositionAppliquee(
        recipe: r,
        marques: marquesCoherentes(r, application.marques.toList()),
        refusOperations: refusOperations,
        reprises: List.unmodifiable(application.reprises),
        modifications: modifications,
      );
  }
}

typedef _Json = Map<String, Object?>;

Object? _copie(Object? value) => switch (value) {
  Map() => <String, Object?>{
    for (final e in value.entries) '${e.key}': _copie(e.value),
  },
  List() => [for (final v in value) _copie(v)],
  _ => value,
};

/// Refus d'une étape d'application, rendu par un retour (aucune exception).
typedef _Echec = ({RaisonRefusOperation raison, String champ});

_Json _mesure(num value, String unit) => {'value': value, 'unit': unit};

class _Application {
  _Application(this.recipe, List<MarqueIa> marques, this.bibliotheque)
    : marques = {...marques};

  final _Json recipe;
  final Set<MarqueIa> marques;
  final IndexImport bibliotheque;
  final refus = <RefusOperation>[];
  final reprises = <ValeurReprise>[];

  _Json get _ingredients {
    final i = recipe['ingredients'];
    if (i is Map<String, Object?>) return i;
    final cree = <String, Object?>{};
    recipe['ingredients'] = cree;
    return cree;
  }

  List<Object?> _liste(String cle) {
    final i = _ingredients;
    final l = i[cle];
    if (l is List<Object?>) return l;
    final cree = <Object?>[];
    i[cle] = cree;
    return cree;
  }

  List<Object?> get _paliers {
    var mash = recipe['mash'];
    if (mash is! Map<String, Object?>) {
      mash = <String, Object?>{'name': kNomEmpatage};
      recipe['mash'] = mash;
    }
    final l = mash['mash_steps'];
    if (l is List<Object?>) return l;
    final cree = <Object?>[];
    mash['mash_steps'] = cree;
    return cree;
  }

  void appliquer(int rang, OperationProposee o) {
    final spec = kOperationsProposition[o.op]!;
    for (final e in spec.champs.entries) {
      final valeur = o.champs[e.key];
      if (valeur != null && !e.value.dansLesBornes(valeur)) {
        refus.add(
          RefusOperation(rang, o.op, RaisonRefusOperation.horsBornes, e.key),
        );
        return;
      }
    }
    final echec = _executer(o);
    if (echec != null) {
      refus.add(RefusOperation(rang, o.op, echec.raison, echec.champ));
    }
  }

  _Echec? _executer(OperationProposee o) {
    final c = o.champs;
    switch (o.op) {
      case 'set_name':
        recipe['name'] = c['value'];
      case 'set_type':
        recipe['type'] = c['value'];
      case 'set_style_name':
        recipe['style'] = {'name': c['value']};
      case 'set_batch_size_l':
        recipe['batch_size'] = _mesure(_double(c['value']), 'l');
      case 'set_boil_time_min':
        recipe['boil'] = {'boil_time': _mesure(_int(c['value']), 'min')};
      case 'add_fermentable':
        return _ajouter('fermentable_additions', () => _malt(c, null));
      case 'update_fermentable':
        return _modifier('fermentable_additions', c, (a) => _malt(c, a));
      case 'remove_fermentable':
        return _retirer(_liste('fermentable_additions'), c);
      case 'add_hop':
        return _ajouter('hop_additions', () => _houblon(c, null));
      case 'update_hop':
        return _modifier('hop_additions', c, (a) => _houblon(c, a));
      case 'remove_hop':
        return _retirer(_liste('hop_additions'), c);
      case 'add_misc':
        return _ajouter('miscellaneous_additions', () => _ajout(c, null));
      case 'update_misc':
        return _modifier('miscellaneous_additions', c, (a) => _ajout(c, a));
      case 'remove_misc':
        return _retirer(_liste('miscellaneous_additions'), c);
      case 'set_culture':
        final lignes = _liste('culture_additions');
        final ancienne = lignes.isEmpty ? null : _map(lignes.first);
        _rangCourant = lignes.isEmpty ? null : 0;
        final (ligne, echec) = _levure(c, ancienne);
        if (echec != null) return echec;
        if (lignes.isEmpty) {
          lignes.add(ligne);
        } else {
          lignes[0] = ligne;
        }
      case 'add_mash_step':
        final paliers = _paliers;
        if (paliers.length >= kMaxPaliers) {
          return (raison: RaisonRefusOperation.listePleine, champ: 'index');
        }
        paliers.add(_palier(c, null));
      case 'update_mash_step':
        final paliers = _paliers;
        final i = _int(c['index']);
        if (i >= paliers.length) return _indexAbsent;
        if (_change(paliers[i], c)) return _elementChange;
        paliers[i] = _palier(c, _map(paliers[i]));
      case 'remove_mash_step':
        return _retirer(_paliers, c);
    }
    return null;
  }

  static const _Echec _indexAbsent = (
    raison: RaisonRefusOperation.indexAbsent,
    champ: 'index',
  );

  static const _Echec _elementChange = (
    raison: RaisonRefusOperation.elementChange,
    champ: 'name',
  );

  /// Vrai si [ligne] ne porte pas le nom de l'opération, comparé par nom
  /// normalisé ([cleNormalisee], comme `ingredientKey`).
  static bool _change(Object? ligne, Map<String, Object?> c) {
    final nom = _map(ligne)?['name'];
    return nom is! String ||
        cleNormalisee(nom) != cleNormalisee(c['name']! as String);
  }

  _Echec? _ajouter(String cle, (_Json?, _Echec?) Function() construire) {
    final lignes = _liste(cle);
    if (lignes.length >= kPlafondsListes[cle]!) {
      return (raison: RaisonRefusOperation.listePleine, champ: 'index');
    }
    _rangCourant = null;
    final (ligne, echec) = construire();
    if (echec != null) return echec;
    lignes.add(ligne);
    return null;
  }

  _Echec? _modifier(
    String cle,
    Map<String, Object?> c,
    (_Json?, _Echec?) Function(_Json? ancienne) construire,
  ) {
    final lignes = _liste(cle);
    final i = _int(c['index']);
    if (i >= lignes.length) return _indexAbsent;
    if (_change(lignes[i], c)) return _elementChange;
    _rangCourant = i;
    final (ligne, echec) = construire(_map(lignes[i]));
    if (echec != null) return echec;
    lignes[i] = ligne;
    return null;
  }

  _Echec? _retirer(List<Object?> lignes, Map<String, Object?> c) {
    final i = _int(c['index']);
    if (i >= lignes.length) return _indexAbsent;
    if (_change(lignes[i], c)) return _elementChange;
    lignes.removeAt(i);
    return null;
  }

  /// Nom d'ingrédient nettoyé comme à la relecture, ou `null` s'il n'a ni
  /// lettre ni chiffre.
  static String? _nomIngredient(Map<String, Object?> c) {
    final nom = nettoyerLigne(c['name']! as String).texte;
    return isValidIngredientName(nom) ? nom : null;
  }

  static const _Echec _nomInvalide = (
    raison: RaisonRefusOperation.horsBornes,
    champ: 'name',
  );

  /// Champs de [ancienne] gardés quand la ligne garde sa clé [cle] et que
  /// l'opération ne les donne pas.
  static void _garder(
    _Json ligne,
    _Json? ancienne,
    String nature,
    String? cle,
    List<String> champs,
  ) {
    if (ancienne == null ||
        cle == null ||
        cleIngredientDeLigne(nature, ancienne) != cle) {
      return;
    }
    for (final champ in champs) {
      if (!ligne.containsKey(champ) && ancienne[champ] != null) {
        ligne[champ] = _copie(ancienne[champ]);
      }
    }
  }

  /// Valeurs techniques de [ligne] : valeurs du modèle ([proposees], champ
  /// d'opération → valeur BeerJSON) retirées, valeurs absentes reprises de la
  /// Bibliothèque, puis valeurs du modèle posées et marquées là où la
  /// Bibliothèque n'en a pas.
  (_Json?, _Echec?) _completer(
    ListeRecette liste,
    String cleListe,
    _Json ligne,
    String? nature,
    Map<String, Object?> c, [
    Map<String, Object?> Function(String champOp, num valeur)? valeurBeerJson,
  ]) {
    final proposees = <String, Object?>{};
    for (final e in kChampsTechniques.entries) {
      final v = c[e.key];
      if (v is num && e.value.nature == nature && valeurBeerJson != null) {
        final champ = e.value.champ;
        ligne.remove(champ);
        proposees[champ] = valeurBeerJson(e.key, v);
      }
    }
    final avant = {...ligne.keys};
    final index = switch (liste) {
      ListeRecette.malts => IndexImport(malts: bibliotheque.malts),
      ListeRecette.houblons => IndexImport(houblons: bibliotheque.houblons),
      ListeRecette.ajouts => IndexImport(ajouts: bibliotheque.ajouts),
      ListeRecette.levures => IndexImport(levures: bibliotheque.levures),
      ListeRecette.paliers => const IndexImport(),
    };
    final completee = completerRecette({
      'ingredients': {
        cleListe: [ligne],
      },
    }, index);
    reprises.addAll(completee.reprises);
    final resultat = Map<String, Object?>.of(
      ((completee.recipe['ingredients']! as Map)[cleListe]! as List).single
          as Map<String, Object?>,
    );
    if (nature == null) return (resultat, null);
    final cle = cleIngredientDeLigne(nature, resultat);
    final ajouts = <MarqueIa>[];
    final retraits = <MarqueIa>[];
    for (final champ in kChampsMarquesIa[nature]!) {
      if (cle == null) break;
      final marque = MarqueIa(nature, cle, champ);
      final reprise = !avant.contains(champ) && resultat[champ] != null;
      if (reprise) {
        // Valeur de la Bibliothèque : elle passe avant celle du modèle.
        retraits.add(marque);
      } else if (proposees.containsKey(champ)) {
        resultat[champ] = proposees[champ];
        final valeur = valeurMarquee(resultat, champ);
        // Une autre ligne du même ingrédient porte une valeur qui n'est pas
        // celle-ci, marquée : la marque serait ambiguë, et une valeur saisie à
        // la main se lirait « proposée par l'IA ». Opération refusée.
        for (final (i, autre) in _liste(cleListe).indexed) {
          if (i == _rangCourant || autre is! Map) continue;
          if (cleIngredientDeLigne(nature, autre) != cle) continue;
          final w = valeurMarquee(autre, champ);
          if (w != null && (w != valeur || !marques.contains(marque))) {
            return (
              null,
              (
                raison: RaisonRefusOperation.champIncompatible,
                champ: kChampsTechniques.entries
                    .firstWhere((e) => e.value.champ == champ)
                    .key,
              ),
            );
          }
        }
        ajouts.add(marque);
      }
    }
    marques
      ..removeAll(retraits)
      ..addAll(ajouts);
    return (resultat, null);
  }

  /// Rang de la ligne remplacée par l'opération en cours, ou `null` pour un
  /// ajout : elle n'entre pas dans le contrôle des autres lignes de la clé.
  int? _rangCourant;

  (_Json?, _Echec?) _malt(Map<String, Object?> c, _Json? ancienne) {
    final nom = _nomIngredient(c);
    if (nom == null) return (null, _nomInvalide);
    final ligne = <String, Object?>{
      'name': nom,
      'type': c['type'],
      'amount': _mesure(_double(c['amount_g']), 'g'),
    };
    _garder(
      ligne,
      ancienne,
      'fermentable',
      cleIngredientDeLigne('fermentable', ligne),
      const ['color', 'yield'],
    );
    return _completer(
      ListeRecette.malts,
      'fermentable_additions',
      ligne,
      'fermentable',
      c,
      (champ, v) => champ == 'yield_pct'
          ? {'fine_grind': _mesure(v.toDouble(), '%')}
          : _mesure(v.toDouble(), 'EBC'),
    );
  }

  (_Json?, _Echec?) _houblon(Map<String, Object?> c, _Json? ancienne) {
    final nom = _nomIngredient(c);
    if (nom == null) return (null, _nomInvalide);
    final minutes = c['time_min'];
    final jours = c['days'];
    final _Json timing;
    switch (c['use']) {
      case 'dry_hop':
        if (minutes != null) {
          return (
            null,
            (raison: RaisonRefusOperation.champIncompatible, champ: 'time_min'),
          );
        }
        if (jours == null) {
          return (
            null,
            (raison: RaisonRefusOperation.valeurManquante, champ: 'days'),
          );
        }
        timing = {
          'use': 'add_to_fermentation',
          'duration': _mesure(((jours as num) * 1440).round(), 'min'),
        };
      case final use:
        if (jours != null) {
          return (
            null,
            (raison: RaisonRefusOperation.champIncompatible, champ: 'days'),
          );
        }
        if (minutes == null) {
          return (
            null,
            (raison: RaisonRefusOperation.valeurManquante, champ: 'time_min'),
          );
        }
        final m = _int(minutes);
        if (use == 'whirlpool') {
          // Relu, un whirlpool de 0 minute deviendrait un ajout à 0 minute
          // d'ébullition.
          if (m < 1) {
            return (
              null,
              (raison: RaisonRefusOperation.horsBornes, champ: 'time_min'),
            );
          }
          timing = {
            'use': 'add_to_boil',
            'time': _mesure(0, 'min'),
            'duration': _mesure(m, 'min'),
          };
        } else {
          timing = {'use': 'add_to_boil', 'time': _mesure(m, 'min')};
        }
    }
    final ligne = <String, Object?>{
      'name': nom,
      'form': c['form'],
      'amount': _mesure(_double(c['amount_g']), 'g'),
      'timing': timing,
    };
    _garder(ligne, ancienne, 'hop', cleIngredientDeLigne('hop', ligne), const [
      'alpha_acid',
    ]);
    return _completer(
      ListeRecette.houblons,
      'hop_additions',
      ligne,
      'hop',
      c,
      (_, v) => _mesure(v.toDouble(), '%'),
    );
  }

  (_Json?, _Echec?) _ajout(Map<String, Object?> c, _Json? ancienne) {
    final nom = _nomIngredient(c);
    if (nom == null) return (null, _nomInvalide);
    final grammes = c['amount_g'];
    final litres = c['amount_l'];
    if (grammes != null && litres != null) {
      return (
        null,
        (raison: RaisonRefusOperation.champIncompatible, champ: 'amount_l'),
      );
    }
    if (grammes == null && litres == null) {
      return (
        null,
        (raison: RaisonRefusOperation.valeurManquante, champ: 'amount_g'),
      );
    }
    final m = c['time_min'] == null ? null : _int(c['time_min']);
    _Json duree(String use) => {
      'use': use,
      if (m != null) 'duration': _mesure(m, 'min'),
    };
    final timing = switch (c['moment']) {
      'mash' => duree('add_to_mash'),
      'boil' => {
        'use': 'add_to_boil',
        if (m != null) 'time': _mesure(m, 'min'),
      },
      'after_boil' => {
        'use': 'add_to_boil',
        'time': _mesure(0, 'min'),
        if (m != null) 'duration': _mesure(m, 'min'),
      },
      'fermentation' => duree('add_to_fermentation'),
      _ => duree('add_to_package'),
    };
    final ligne = <String, Object?>{
      'name': nom,
      'amount': grammes != null
          ? _mesure(_double(grammes), 'g')
          : _mesure(_double(litres), 'l'),
      'timing': timing,
    };
    // Même ajout : son type est gardé (aucune valeur technique marquée).
    final ancienNom = ancienne?['name'];
    if (ancienNom is String &&
        ancienne!['type'] != null &&
        cleNormalisee(ancienNom) == cleNormalisee(nom)) {
      ligne['type'] = ancienne['type'];
    }
    return _completer(
      ListeRecette.ajouts,
      'miscellaneous_additions',
      ligne,
      null,
      c,
    );
  }

  (_Json?, _Echec?) _levure(Map<String, Object?> c, _Json? ancienne) {
    final nom = _nomIngredient(c);
    if (nom == null) return (null, _nomInvalide);
    final ligne = <String, Object?>{
      'name': nom,
      'type': ?c['type'],
      'form': ?c['form'],
    };
    _garder(
      ligne,
      ancienne,
      'culture',
      cleIngredientDeLigne('culture', ligne),
      const ['type', 'form', 'attenuation', 'amount'],
    );
    return _completer(
      ListeRecette.levures,
      'culture_additions',
      ligne,
      'culture',
      c,
      (_, v) => _mesure(v.toDouble(), '%'),
    );
  }

  static _Json _palier(Map<String, Object?> c, _Json? ancien) => {
    'name': c['name'],
    if (ancien?['type'] != null) 'type': ancien!['type'],
    'step_temperature': _mesure(_double(c['temperature_c']), 'C'),
    'step_time': _mesure(_int(c['time_min']), 'min'),
  };

  static _Json? _map(Object? value) => value is Map<String, Object?>
      ? value
      : value is Map
      ? value.cast<String, Object?>()
      : null;

  static double _double(Object? value) => (value! as num).toDouble();

  static int _int(Object? value) => (value! as num).round();
}
