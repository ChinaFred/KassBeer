import 'dart:convert';

import 'package:brewing/brewing.dart' show CostUnit, FeeBasis;

import '../analyse.dart';
import '../compte_rendu.dart';
import '../empreinte.dart';
import '../texte.dart';
import 'modele.dart';

/// Lecture du format `kassbeer_fiches` v1 (v0.6, FO1 à FO7) : un fichier JSON
/// dont la racine porte `beerjson` (les recettes, lues par [analyserFichier]
/// comme dans Recettes › Importer) et `kassbeer_fiches` (chronologies,
/// mesures, relevés, embouteillage, prix et écarts des fiches Excel).
///
/// Chaque champ est lu vers un type, dans les bornes de `firestore.rules`. Un
/// champ inconnu, un type faux ou une valeur hors bornes refuse la fiche avec
/// le chemin du premier champ en cause ; les autres fiches restent lisibles.
/// Aucun refus ne porte une valeur du fichier, donc aucun prix. Rien n'est
/// écrit, rien ne part sur le réseau, et aucun `catch` : l'application et la
/// préparation (`bin/verifier_fiches.dart`) lisent avec ce même code.

/// Version du format lue.
const int kVersionFormatFiches = 1;

/// Date la plus ancienne d'une fiche : 1er janvier 2015 (FO4).
final DateTime kDebutDesFiches = DateTime.utc(2015);

final RegExp _ficheId = RegExp(r'^[a-z0-9-]{1,60}$');
final RegExp _docId = RegExp(r'^[a-z0-9-]{1,100}$');
final RegExp _cle = RegExp(r'^[A-Za-z0-9_-]{1,100}$');
final RegExp _clePrix = RegExp(
  r'^(malt|sucre|houblon|levure|ajout)(-[a-z0-9]+)*$',
);
final RegExp _date = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:\d{2})$',
);

/// Montant dans un texte : « € », « EUR », « euro », « euros » (S1 de la revue
/// de sécurité de la v0.6). Les prix ne vont que dans le coût figé (P5, P9).
final RegExp _montant = RegExp(r'€|\bEUR\b|\beuros?\b', caseSensitive: false);

final RegExp _adresseWeb = RegExp(
  r'(?:https?|ftp)://|www\.',
  caseSensitive: false,
);

/// Lit [octets], le contenu d'un fichier de fiches. [maintenant] : heure de
/// l'import ; une date postérieure refuse sa fiche.
///
/// Lève [FormatException] pour un JSON mal formé ou un UTF-8 invalide, comme
/// [analyserFichier] : l'appelant la rapporte sans son message, qui cite le
/// contenu du fichier.
LectureFiches lireFichierFiches(
  List<int> octets, {
  required DateTime maintenant,
}) {
  final analyse = analyserFichier(octets);
  final List<RecetteDuFichier> recettes;
  switch (analyse) {
    case FichierRefuse(raison: RaisonFichier.tropGros, :final taille):
      return FichierFichesRefuse(RaisonFichierFiches.tropGros, taille: taille);
    case FichierRefuse(raison: RaisonFichier.aucuneRecette)
        when formatPresume(octets) == 'json':
      recettes = const [];
    case FichierRefuse():
      return const FichierFichesRefuse(
        RaisonFichierFiches.pasUnFichierDeFiches,
      );
    case FichierLu(format: FormatFichier.beerXml):
      return const FichierFichesRefuse(
        RaisonFichierFiches.pasUnFichierDeFiches,
      );
    case FichierLu(recettes: final lues):
      recettes = lues;
  }
  // Fichier JSON déjà borné par analyserFichier (taille, profondeur, nombre de
  // valeurs) : relu ici pour sa partie `kassbeer_fiches`.
  final racine = _decoder(octets);
  if (racine is! Map ||
      !racine.keys.every((k) => k == 'beerjson' || k == 'kassbeer_fiches')) {
    return const FichierFichesRefuse(RaisonFichierFiches.pasUnFichierDeFiches);
  }
  final kf = racine['kassbeer_fiches'];
  if (kf is! Map) {
    return const FichierFichesRefuse(RaisonFichierFiches.pasUnFichierDeFiches);
  }
  final version = kf['format_version'];
  if (version != kVersionFormatFiches) {
    return FichierFichesRefuse(
      version == null
          ? RaisonFichierFiches.pasUnFichierDeFiches
          : RaisonFichierFiches.versionInconnue,
    );
  }
  final brutes = kf['fiches'];
  if (brutes is! List ||
      !kf.keys.every((k) => k == 'format_version' || k == 'fiches')) {
    return const FichierFichesRefuse(RaisonFichierFiches.pasUnFichierDeFiches);
  }
  if (brutes.length > kMaxFiches) {
    return const FichierFichesRefuse(RaisonFichierFiches.tropDeFiches);
  }
  final ids = <String>{};
  for (final brute in brutes) {
    final id = brute is Map ? brute['fiche_id'] : null;
    if (id is String && _ficheId.hasMatch(id) && !ids.add(id)) {
      return FichierFichesRefuse(
        RaisonFichierFiches.identifiantEnDouble,
        ficheId: id,
      );
    }
  }
  final beerjson = racine['beerjson'];
  final recettesBrutes = beerjson is Map ? beerjson['recipes'] : null;
  final fiches = <FicheDuFichier>[];
  final parDocument = <String, ({int index, String etapes})>{};
  for (final (i, brute) in brutes.indexed) {
    final recipeIndex = brute is Map ? brute['recipe_index'] : null;
    final recetteBrute =
        recettesBrutes is List &&
            recipeIndex is int &&
            recipeIndex >= 0 &&
            recipeIndex < recettesBrutes.length
        ? recettesBrutes[recipeIndex]
        : null;
    final id = brute is Map ? brute['fiche_id'] : null;
    var resultat = _Lecteur(maintenant, recettes, recetteBrute).fiche(brute);
    if (resultat case FicheAcceptee(:final fiche)) {
      // CR2 : deux fiches d'un même document de recette ont la même recette et
      // la même chronologie, sinon la seconde est refusée.
      final etapes = lireEmpreinte([
        for (final e in fiche.etapes) [e.key, e.name, e.durationMin, e.tempC],
      ]).empreinte;
      final deja = parDocument[fiche.recipeDocId];
      if (deja == null) {
        parDocument[fiche.recipeDocId] = (
          index: fiche.recipeIndex,
          etapes: etapes,
        );
      } else if (deja.index != fiche.recipeIndex || deja.etapes != etapes) {
        resultat = const FicheRefusee(
          RefusFiche('recipe_doc_id', CodeRefusFiche.recetteIncoherente),
        );
      }
    }
    fiches.add(
      FicheDuFichier(
        numero: i + 1,
        ficheId: id is String && _ficheId.hasMatch(id) ? id : null,
        empreinte: lireEmpreinte({
          'fiche': brute,
          'recipe': recetteBrute,
        }).empreinte,
        resultat: resultat,
      ),
    );
  }
  return FichierFiches(recettes: recettes, fiches: List.unmodifiable(fiches));
}

/// JSON de [octets], après un BOM UTF-8 éventuel.
Object? _decoder(List<int> octets) {
  final debut =
      octets.length >= 3 &&
          octets[0] == 0xEF &&
          octets[1] == 0xBB &&
          octets[2] == 0xBF
      ? 3
      : 0;
  return jsonDecode(const Utf8Decoder().convert(octets, debut));
}

/// Lecture d'une fiche, champ par champ. Le premier champ refusé est retenu
/// ([_refus]) et la lecture rend une valeur neutre à sa place : la fiche
/// construite est alors écartée, sans exception ni `catch`.
class _Lecteur {
  _Lecteur(this.maintenant, this.recettes, this.recetteBrute);

  final DateTime maintenant;
  final List<RecetteDuFichier> recettes;

  /// Objet brut de la recette désignée, pour le contrôle des adresses web.
  final Object? recetteBrute;

  RefusFiche? _refus;

  bool get _refusee => _refus != null;

  void _refuser(String chemin, CodeRefusFiche code, {Refus? recette}) {
    _refus ??= RefusFiche(chemin, code, refusRecette: recette);
  }

  ResultatFiche fiche(Object? brute) {
    final fiche = _fiche(brute);
    final refus = _refus;
    return refus != null || fiche == null
        ? FicheRefusee(
            refus ?? const RefusFiche('', CodeRefusFiche.champAbsent),
          )
        : FicheAcceptee(fiche);
  }

  // ---------------------------------------------------------------- Outils

  /// Objet [valeur] dont les clés appartiennent à [permises] et contiennent
  /// [obligatoires] ; `null` après un refus.
  Map<Object?, Object?>? _objet(
    Object? valeur,
    String chemin, {
    required Set<String> permises,
    Set<String> obligatoires = const {},
  }) {
    if (valeur is! Map) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return null;
    }
    for (final cle in valeur.keys) {
      if (!permises.contains(cle)) {
        _refuser(_sous(chemin, '$cle'), CodeRefusFiche.champInconnu);
        return null;
      }
    }
    for (final cle in obligatoires) {
      if (valeur[cle] == null) {
        _refuser(_sous(chemin, cle), CodeRefusFiche.champAbsent);
        return null;
      }
    }
    return valeur;
  }

  String _sous(String chemin, String cle) =>
      chemin.isEmpty ? cle : '$chemin.$cle';

  /// Liste de [max] éléments au plus ; `null` absente ; vide après un refus.
  List<Object?> _liste(Object? valeur, String chemin, int max) {
    if (valeur == null) return const [];
    if (valeur is! List) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return const [];
    }
    if (valeur.length > max) {
      _refuser(chemin, CodeRefusFiche.horsBornes);
      return const [];
    }
    return valeur;
  }

  /// Texte d'une ligne, nettoyé (P9), de 1 à [max] caractères, sans adresse
  /// web si [sansAdresse], sans montant si [groupe] (texte lu par le groupe).
  String _ligne(
    Object? valeur,
    String chemin,
    int max, {
    bool sansAdresse = true,
    bool groupe = false,
  }) {
    if (valeur is! String) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return '';
    }
    final texte = nettoyerLigne(valeur).texte;
    if (texte.isEmpty || texte.length > max) {
      _refuser(chemin, CodeRefusFiche.horsBornes);
      return '';
    }
    _controler(texte, chemin, sansAdresse: sansAdresse, groupe: groupe);
    return texte;
  }

  /// FO5 et S1 : adresse web refusée si [sansAdresse], montant refusé si
  /// [groupe]. Le refus porte le chemin, jamais le texte.
  void _controler(
    String texte,
    String chemin, {
    required bool sansAdresse,
    required bool groupe,
  }) {
    if (sansAdresse && _adresseWeb.hasMatch(texte)) {
      _refuser(chemin, CodeRefusFiche.adresseWeb);
    }
    if (groupe && _montant.hasMatch(texte)) {
      _refuser(chemin, CodeRefusFiche.montant);
    }
  }

  /// Texte de notes facultatif, nettoyé (P9), [max] caractères au plus ;
  /// absent ou vide rend `null`. [groupe] : texte lu par le groupe.
  String? _notes(
    Object? valeur,
    String chemin,
    int max, {
    bool sansAdresse = true,
    bool groupe = false,
  }) {
    if (valeur == null) return null;
    if (valeur is! String) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return null;
    }
    final texte = nettoyerNotes(valeur).texte;
    if (texte.length > max) {
      _refuser(chemin, CodeRefusFiche.horsBornes);
      return null;
    }
    _controler(texte, chemin, sansAdresse: sansAdresse, groupe: groupe);
    return texte.isEmpty ? null : texte;
  }

  /// Identifiant conforme à [forme].
  String _id(Object? valeur, String chemin, RegExp forme) {
    if (valeur is! String) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return '';
    }
    if (!forme.hasMatch(valeur)) {
      _refuser(chemin, CodeRefusFiche.formatInvalide);
      return '';
    }
    return valeur;
  }

  /// Nombre fini de [min] à [max] ; [minExclu] exclut [min].
  double _nombre(
    Object? valeur,
    String chemin, {
    required double min,
    required double max,
    bool minExclu = false,
  }) {
    if (valeur is! num || !valeur.isFinite) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return 0;
    }
    final v = valeur.toDouble();
    if ((minExclu ? v <= min : v < min) || v > max) {
      _refuser(chemin, CodeRefusFiche.horsBornes);
      return 0;
    }
    return v;
  }

  double? _nombreFacultatif(
    Object? valeur,
    String chemin, {
    required double min,
    required double max,
    bool minExclu = false,
  }) => valeur == null
      ? null
      : _nombre(valeur, chemin, min: min, max: max, minExclu: minExclu);

  /// Entier de [min] à [max].
  int _entier(Object? valeur, String chemin, {required int min, int? max}) {
    if (valeur is! num || !valeur.isFinite || valeur != valeur.truncate()) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return 0;
    }
    final v = valeur.toInt();
    if (v < min || (max != null && v > max)) {
      _refuser(chemin, CodeRefusFiche.horsBornes);
      return 0;
    }
    return v;
  }

  /// Date ISO 8601 avec son décalage (PR8), du 1er janvier 2015 à
  /// [maintenant].
  DateTime _dateHeure(Object? valeur, String chemin) {
    if (valeur is! String) {
      _refuser(chemin, CodeRefusFiche.typeInattendu);
      return kDebutDesFiches;
    }
    final m = _date.firstMatch(valeur);
    final date = m == null ? null : DateTime.tryParse(valeur);
    if (m == null ||
        date == null ||
        !_dansLesBornes(int.parse(m[2]!), 1, 12) ||
        !_dansLesBornes(int.parse(m[3]!), 1, 31) ||
        !_dansLesBornes(int.parse(m[4]!), 0, 23) ||
        !_dansLesBornes(int.parse(m[5]!), 0, 59) ||
        !_dansLesBornes(int.parse(m[6] ?? '0'), 0, 59)) {
      _refuser(chemin, CodeRefusFiche.formatInvalide);
      return kDebutDesFiches;
    }
    if (date.isBefore(kDebutDesFiches) || date.isAfter(maintenant)) {
      _refuser(chemin, CodeRefusFiche.horsBornes);
      return kDebutDesFiches;
    }
    return date;
  }

  static bool _dansLesBornes(int v, int min, int max) => v >= min && v <= max;

  /// Valeur de [valeurs] dont la valeur du fichier est [valeur].
  T _parmi<T>(
    Object? valeur,
    String chemin,
    List<T> valeurs,
    String Function(T) lu,
  ) {
    for (final v in valeurs) {
      if (lu(v) == valeur) return v;
    }
    _refuser(
      chemin,
      valeur is String
          ? CodeRefusFiche.horsBornes
          : CodeRefusFiche.typeInattendu,
    );
    return valeurs.first;
  }

  /// Liste de textes (déductions, divergences, non importé), 2 000
  /// caractères chacun. Ces textes ne sont lus que par l'administrateur.
  List<String> _textes(Object? valeur, String chemin) => [
    for (final (i, t) in _liste(valeur, chemin, kMaxElementsListeFiche).indexed)
      _ligneLongue(t, '$chemin[$i]'),
  ];

  String _ligneLongue(Object? valeur, String chemin) {
    final texte = _notes(valeur, chemin, 2000, sansAdresse: false);
    if (texte == null && !_refusee) {
      _refuser(chemin, CodeRefusFiche.champAbsent);
    }
    return texte ?? '';
  }

  // ---------------------------------------------------------------- Fiche

  static const _champsFiche = {
    'fiche_id',
    'recipe_index',
    'recipe_doc_id',
    'brew_steps',
    'brew',
    'events',
    'retained',
    'cost',
    'corrections',
    'deductions',
    'divergences',
    'not_imported',
  };

  FicheLue? _fiche(Object? brute) {
    final f = _objet(
      brute,
      '',
      permises: _champsFiche,
      obligatoires: const {
        'fiche_id',
        'recipe_index',
        'recipe_doc_id',
        'brew_steps',
        'brew',
        'events',
      },
    );
    if (f == null) return null;
    final ficheId = _id(f['fiche_id'], 'fiche_id', _ficheId);
    final recipeDocId = _id(f['recipe_doc_id'], 'recipe_doc_id', _docId);
    final recipeIndex = _entier(f['recipe_index'], 'recipe_index', min: 0);
    if (_refusee) return null;
    if (recipeIndex >= recettes.length) {
      _refuser('recipe_index', CodeRefusFiche.recetteAbsente);
      return null;
    }
    final source = recettes[recipeIndex];
    final RecetteLue recette;
    switch (source.resultat) {
      case RecetteRefusee(:final refus):
        _refuser('recipe_index', CodeRefusFiche.recetteRefusee, recette: refus);
        return null;
      case final RecetteLue lue:
        recette = lue;
    }
    _controlerRecette();
    final etapes = _etapes(f['brew_steps']);
    final cles = {for (final e in etapes) e.key};
    final brassin = _brassin(f['brew']);
    final evenements = _evenements(f['events'], cles);
    final retenues = _retenues(f['retained'], evenements);
    final cout = _cout(f['cost']);
    final corrections = _corrections(f['corrections']);
    final deductions = _textes(f['deductions'], 'deductions');
    final divergences = _textes(f['divergences'], 'divergences');
    final nonImporte = _textes(f['not_imported'], 'not_imported');
    if (_refusee) return null;
    return FicheLue(
      ficheId: ficheId,
      recipeIndex: recipeIndex,
      recipeDocId: recipeDocId,
      recette: recette,
      etapes: etapes,
      brassin: brassin,
      evenements: evenements,
      ogEventId: retenues.og,
      fgEventId: retenues.fg,
      fermenterVolumeEventId: retenues.volume,
      cout: cout,
      corrections: corrections,
      deductions: deductions,
      divergences: divergences,
      nonImporte: nonImporte,
    );
  }

  /// Recette lue par le groupe : aucune adresse web (FO5, S4) ni aucun montant
  /// (S1, S6) dans aucune de ses chaînes, noms et notes des lignes compris.
  void _controlerRecette() {
    final r = recetteBrute;
    if (r is! Map) return;
    if (_dans(r, _adresseWeb)) {
      _refuser('recipe_index', CodeRefusFiche.adresseWeb);
    }
    if (_dans(r, _montant)) _refuser('recipe_index', CodeRefusFiche.montant);
  }

  /// Vrai si une chaîne de [valeur], clés comprises, correspond à [motif]. La
  /// profondeur est bornée par `analyserFichier`.
  static bool _dans(Object? valeur, RegExp motif) => switch (valeur) {
    final String t => motif.hasMatch(t),
    final List<Object?> l => l.any((v) => _dans(v, motif)),
    final Map<Object?, Object?> m => m.entries.any(
      (e) => _dans(e.key, motif) || _dans(e.value, motif),
    ),
    _ => false,
  };

  List<EtapeFiche> _etapes(Object? valeur) {
    final etapes = <EtapeFiche>[];
    final vues = <String>{};
    for (final (i, brute) in _liste(valeur, 'brew_steps', 60).indexed) {
      final chemin = 'brew_steps[$i]';
      final e = _objet(
        brute,
        chemin,
        permises: const {'key', 'name', 'duration_min', 'temp_c'},
        obligatoires: const {'key', 'name', 'duration_min'},
      );
      if (e == null) return const [];
      final key = _id(e['key'], '$chemin.key', _cle);
      if (!_refusee && !vues.add(key)) {
        _refuser('$chemin.key', CodeRefusFiche.enDouble);
      }
      etapes.add(
        EtapeFiche(
          key: key,
          name: _ligne(e['name'], '$chemin.name', 120, groupe: true),
          durationMin: _nombre(
            e['duration_min'],
            '$chemin.duration_min',
            min: 0,
            max: 600,
          ),
          tempC: _nombreFacultatif(
            e['temp_c'],
            '$chemin.temp_c',
            min: 0,
            max: 100,
          ),
        ),
      );
    }
    return List.unmodifiable(etapes);
  }

  BrassinFiche _brassin(Object? valeur) {
    final b = _objet(
      valeur,
      'brew',
      permises: const {
        'name',
        'planned_for',
        'start_at',
        'notes',
        'bottles_count',
        'packaged_volume_l',
        'priming_sugar_name',
        'equipment',
      },
      obligatoires: const {'name', 'planned_for', 'start_at', 'equipment'},
    );
    final eq = b == null
        ? null
        : _objet(
            b['equipment'],
            'brew.equipment',
            permises: const {'name', 'kind'},
            obligatoires: const {'name', 'kind'},
          );
    if (b == null || eq == null) {
      return BrassinFiche(
        name: '',
        plannedFor: kDebutDesFiches,
        startAt: kDebutDesFiches,
        equipementNom: '',
        equipementType: TypeEquipementFiche.cuves,
      );
    }
    final bouteilles = b['bottles_count'];
    final sucre = b['priming_sugar_name'];
    return BrassinFiche(
      name: _ligne(b['name'], 'brew.name', 120, groupe: true),
      plannedFor: _dateHeure(b['planned_for'], 'brew.planned_for'),
      startAt: _dateHeure(b['start_at'], 'brew.start_at'),
      notes: _notes(b['notes'], 'brew.notes', 10000, groupe: true),
      bottlesCount: bouteilles == null
          ? null
          : _entier(bouteilles, 'brew.bottles_count', min: 1, max: 9999),
      packagedVolumeL: _nombreFacultatif(
        b['packaged_volume_l'],
        'brew.packaged_volume_l',
        min: 0,
        max: 1000,
        minExclu: true,
      ),
      primingSugarName: sucre == null
          ? null
          : _ligne(sucre, 'brew.priming_sugar_name', 80, groupe: true),
      equipementNom: _ligne(
        eq['name'],
        'brew.equipment.name',
        120,
        groupe: true,
      ),
      equipementType: _parmi(
        eq['kind'],
        'brew.equipment.kind',
        TypeEquipementFiche.values,
        (t) => t.valeur,
      ),
    );
  }

  List<EvenementFiche> _evenements(Object? valeur, Set<String> cles) {
    final evenements = <EvenementFiche>[];
    final vus = <String>{};
    for (final (i, brute) in _liste(
      valeur,
      'events',
      kMaxEvenementsParFiche,
    ).indexed) {
      final chemin = 'events[$i]';
      final e = _objet(
        brute,
        chemin,
        permises: const {
          'id',
          'kind',
          'step_key',
          'measure_type',
          'value',
          'note',
          'measured_at',
          'phase',
          'time_source',
        },
        obligatoires: const {'id', 'kind', 'measured_at', 'time_source'},
      );
      if (e == null) return const [];
      final id = _id(e['id'], '$chemin.id', _cle);
      if (!_refusee && !vus.add(id)) {
        _refuser('$chemin.id', CodeRefusFiche.enDouble);
      }
      final nature = _parmi(
        e['kind'],
        '$chemin.kind',
        NatureEvenementFiche.values,
        (n) => n.valeur,
      );
      final stepKey = e['step_key'] == null
          ? null
          : _id(e['step_key'], '$chemin.step_key', _cle);
      if (stepKey != null && !_refusee && !cles.contains(stepKey)) {
        _refuser('$chemin.step_key', CodeRefusFiche.etapeInconnue);
      }
      final phase = e['phase'];
      if (phase != null && phase != 'fermentation') {
        _refuser('$chemin.phase', CodeRefusFiche.horsBornes);
      }
      final fermentation = phase == 'fermentation';
      final note = _notes(e['note'], '$chemin.note', 2000, groupe: true);
      TypeMesureFiche? type;
      double? mesure;
      switch (nature) {
        case NatureEvenementFiche.debutEtape:
          if (stepKey == null) {
            _refuser('$chemin.step_key', CodeRefusFiche.champAbsent);
          }
          _sansMesure(e, chemin);
          if (fermentation) {
            _refuser('$chemin.phase', CodeRefusFiche.horsBornes);
          }
        case NatureEvenementFiche.mesure:
          if (e['measure_type'] == null) {
            _refuser('$chemin.measure_type', CodeRefusFiche.champAbsent);
          } else if (e['value'] == null) {
            _refuser('$chemin.value', CodeRefusFiche.champAbsent);
          } else {
            final lu = _parmi<TypeMesureFiche>(
              e['measure_type'],
              '$chemin.measure_type',
              TypeMesureFiche.values,
              (t) => t.valeur,
            );
            type = lu;
            mesure = _mesure(lu, e['value'], '$chemin.value');
          }
        case NatureEvenementFiche.note:
          if (note == null) {
            _refuser('$chemin.note', CodeRefusFiche.champAbsent);
          }
          _sansMesure(e, chemin);
      }
      evenements.add(
        EvenementFiche(
          id: id,
          nature: nature,
          stepKey: stepKey,
          typeMesure: type,
          valeur: mesure,
          note: note,
          measuredAt: _dateHeure(e['measured_at'], '$chemin.measured_at'),
          fermentation: fermentation,
          origineHeure: _parmi(
            e['time_source'],
            '$chemin.time_source',
            OrigineHeure.values,
            (o) => o.valeur,
          ),
        ),
      );
    }
    return List.unmodifiable(evenements);
  }

  void _sansMesure(Map<Object?, Object?> e, String chemin) {
    for (final cle in const ['measure_type', 'value']) {
      if (e[cle] != null) _refuser('$chemin.$cle', CodeRefusFiche.horsBornes);
    }
  }

  /// Valeur d'une mesure, aux bornes de `measureInRange` (`firestore.rules`).
  double _mesure(TypeMesureFiche type, Object? valeur, String chemin) =>
      switch (type) {
        TypeMesureFiche.temperature => _nombre(
          valeur,
          chemin,
          min: 0,
          max: 110,
        ),
        TypeMesureFiche.densite => _nombre(valeur, chemin, min: 0.98, max: 1.2),
        TypeMesureFiche.volume => _nombre(
          valeur,
          chemin,
          min: 0,
          max: 1000,
          minExclu: true,
        ),
        TypeMesureFiche.ph => _nombre(valeur, chemin, min: 0, max: 14),
      };

  ({String? og, String? fg, String? volume}) _retenues(
    Object? valeur,
    List<EvenementFiche> evenements,
  ) {
    if (valeur == null) return (og: null, fg: null, volume: null);
    final r = _objet(
      valeur,
      'retained',
      permises: const {
        'og_event_id',
        'fg_event_id',
        'fermenter_volume_event_id',
      },
    );
    if (r == null) return (og: null, fg: null, volume: null);
    String? designe(String cle, bool Function(EvenementFiche) valide) {
      final id = r[cle];
      if (id == null) return null;
      for (final e in evenements) {
        if (e.id == id && valide(e)) return e.id;
      }
      _refuser('retained.$cle', CodeRefusFiche.evenementInconnu);
      return null;
    }

    bool densite(EvenementFiche e) => e.typeMesure == TypeMesureFiche.densite;
    return (
      og: designe('og_event_id', densite),
      fg: designe('fg_event_id', (e) => densite(e) && e.fermentation),
      volume: designe(
        'fermenter_volume_event_id',
        (e) => e.typeMesure == TypeMesureFiche.volume && !e.fermentation,
      ),
    );
  }

  CoutFiche? _cout(Object? valeur) {
    if (valeur == null) return null;
    final c = _objet(
      valeur,
      'cost',
      permises: const {'prices', 'fees', 'fiche_total_eur'},
    );
    if (c == null) return null;
    final prixBruts = _liste(c['prices'], 'cost.prices', kMaxLignesCoutFiche);
    final fraisBruts = _liste(c['fees'], 'cost.fees', kMaxLignesCoutFiche);
    if (prixBruts.length + fraisBruts.length > kMaxLignesCoutFiche) {
      _refuser('cost', CodeRefusFiche.horsBornes);
      return null;
    }
    final cles = <String>{};
    final prix = <PrixFiche>[];
    for (final (i, brut) in prixBruts.indexed) {
      final chemin = 'cost.prices[$i]';
      final p = _objet(
        brut,
        chemin,
        permises: const {'key', 'name', 'price_eur', 'quantity', 'unit'},
        obligatoires: const {'key', 'name', 'price_eur', 'quantity', 'unit'},
      );
      if (p == null) return null;
      final key = _id(p['key'], '$chemin.key', _clePrix);
      if (key.length > 100) _refuser('$chemin.key', CodeRefusFiche.horsBornes);
      if (!_refusee && !cles.add(key)) {
        _refuser('$chemin.key', CodeRefusFiche.enDouble);
      }
      // Bornes de `isPriceShape` (`firestore.rules`).
      prix.add(
        PrixFiche(
          key: key,
          name: _ligne(p['name'], '$chemin.name', 120),
          priceEur: _nombre(
            p['price_eur'],
            '$chemin.price_eur',
            min: 0,
            max: 100000,
          ),
          quantity: _nombre(
            p['quantity'],
            '$chemin.quantity',
            min: 0,
            max: 1e9,
            minExclu: true,
          ),
          unit: _parmi(
            p['unit'],
            '$chemin.unit',
            CostUnit.purchaseUnits,
            (u) => u.storedValue,
          ),
        ),
      );
    }
    final frais = <FraisFiche>[];
    for (final (i, brut) in fraisBruts.indexed) {
      final chemin = 'cost.fees[$i]';
      final f = _objet(
        brut,
        chemin,
        permises: const {'name', 'amount_eur', 'basis'},
        obligatoires: const {'name', 'amount_eur', 'basis'},
      );
      if (f == null) return null;
      // Bornes de `isFeeShape` (`firestore.rules`).
      frais.add(
        FraisFiche(
          name: _ligne(f['name'], '$chemin.name', 60),
          amountEur: _nombre(
            f['amount_eur'],
            '$chemin.amount_eur',
            min: 0,
            max: 10000,
          ),
          basis: _parmi(
            f['basis'],
            '$chemin.basis',
            FeeBasis.values,
            (b) => b.storedValue,
          ),
        ),
      );
    }
    final total = c['fiche_total_eur'];
    return CoutFiche(
      prix: List.unmodifiable(prix),
      frais: List.unmodifiable(frais),
      totalFicheEur: total == null
          ? null
          : _nombre(total, 'cost.fiche_total_eur', min: 0, max: 999999999),
    );
  }

  List<CorrectionFiche> _corrections(Object? valeur) {
    final corrections = <CorrectionFiche>[];
    for (final (i, brute) in _liste(
      valeur,
      'corrections',
      kMaxElementsListeFiche,
    ).indexed) {
      final chemin = 'corrections[$i]';
      const champs = {'subject', 'fiche_value', 'imported_value', 'reason'};
      final c = _objet(brute, chemin, permises: champs, obligatoires: champs);
      if (c == null) return const [];
      corrections.add(
        CorrectionFiche(
          sujet: _ligneLongue(c['subject'], '$chemin.subject'),
          valeurFiche: _ligneLongue(c['fiche_value'], '$chemin.fiche_value'),
          valeurImportee: _ligneLongue(
            c['imported_value'],
            '$chemin.imported_value',
          ),
          raison: _ligneLongue(c['reason'], '$chemin.reason'),
        ),
      );
    }
    return List.unmodifiable(corrections);
  }
}
