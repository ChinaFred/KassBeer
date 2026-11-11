import 'package:brewing/brewing.dart';

import 'bornes.dart';
import 'compte_rendu.dart';
import 'schema.dart';
import 'texte.dart';
import 'unites.dart';

/// Lecture d'une recette BeerJSON (`RecipeType`, versions 1, 2 et 3) vers le
/// sous-arbre `recipe` en BeerJSON partiel de Kass'Beer (ADR-005), champ par
/// champ, sans jamais inventer une valeur. Aucun prix ni stock n'est lu : les
/// champs `inventory` et inconnus sont ignorés et comptés. Le paquet ne fait
/// aucun `catch` : une donnée invalide rend un refus ou une modification.

/// Nom écrit dans `recipe.mash.name`, obligatoire dans le schéma : un libellé.
const kNomEmpatage = 'Empâtage';

/// Lit [brut], une recette d'un fichier BeerJSON.
ResultatRecette lireRecetteBeerJson(Object? brut) => lireRecetteConvertie(brut);

/// Lit [brut], une recette en BeerJSON tirée d'un autre format (BeerXML), avec
/// ce que la conversion a déjà relevé : [avant] (modifications propres au
/// format, placées en tête), [parties] non importées, [inconnus] champs
/// inconnus, et [nombres] : nombre de lignes du fichier par liste
/// (`hop_additions`, `mash_steps`…) quand la conversion n'en a gardé que le
/// plafond + 1. Les bornes, les unités et le nettoyage des textes sont ceux du
/// BeerJSON : le compte rendu est le même.
ResultatRecette lireRecetteConvertie(
  Object? brut, {
  List<Modification> avant = const [],
  Set<PartieNonImportee> parties = const {},
  int inconnus = 0,
  Map<String, int> nombres = const {},
}) {
  final lecture = _Lecture()
    .._modifs.addAll(avant)
    .._parties.addAll(parties)
    .._inconnus = inconnus
    .._nombres = nombres;
  final recipe = lecture.recette(brut);
  final refus = lecture.refus;
  if (refus != null || recipe == null) {
    return RecetteRefusee(refus ?? const RecetteIllisible());
  }
  return RecetteLue(recipe, lecture.modifications());
}

/// Nom affiché d'une recette du fichier : nettoyé et coupé, ou `null`.
String? nomAffiche(Object? brut) {
  if (brut is! Map) return null;
  final name = brut['name'];
  if (name is! String) return null;
  final texte = nettoyerLigne(name).texte;
  return texte.isEmpty ? null : couper(texte, kMaxNom);
}

typedef _Json = Map<String, Object?>;

/// Couple `{value, unit}` lu.
typedef _Couple = ({double value, String unit});

/// État d'une lecture : le premier refus l'arrête ; les modifications
/// s'accumulent dans l'ordre de la recette.
class _Lecture {
  Refus? refus;
  final _modifs = <Modification>[];
  final _unites = <String>{};
  final _parties = <PartieNonImportee>{};
  int _inconnus = 0;
  bool _caracteres = false;
  Map<String, int> _nombres = const {};

  bool get _arret => refus != null;

  void _refuser(Refus r) => refus ??= r;

  List<Modification> modifications() => [
    if (_caracteres) const CaracteresRetires(),
    ..._modifs,
    if (_unites.isNotEmpty) UnitesConverties(Set.unmodifiable(_unites)),
    if (_parties.isNotEmpty) PartiesNonImportees(Set.unmodifiable(_parties)),
    if (_inconnus > 0) ChampsInconnus(_inconnus),
  ];

  // --- Structure -------------------------------------------------------------

  /// Map facultative ; présente mais d'un autre type : recette illisible.
  _Json? _objet(Object? value) {
    if (value == null) return null;
    if (value is Map) {
      return {for (final e in value.entries) '${e.key}': e.value};
    }
    _refuser(const RecetteIllisible());
    return null;
  }

  /// Liste facultative ; présente mais d'un autre type : recette illisible.
  List<Object?> _liste(Object? value) {
    if (value == null) return const [];
    if (value is List) return value;
    _refuser(const RecetteIllisible());
    return const [];
  }

  /// Compte les clés de [m] : lues, non importées, ou inconnues.
  void _cles(
    _Json m,
    Set<String> lues, [
    Map<String, PartieNonImportee> nonImportees = const {},
  ]) {
    for (final key in m.keys) {
      if (lues.contains(key)) continue;
      final partie = nonImportees[key];
      if (partie != null) {
        _parties.add(partie);
      } else {
        _inconnus++;
      }
    }
  }

  // --- Valeurs ---------------------------------------------------------------

  /// Texte facultatif nettoyé et coupé à [max] ; vide rend `null`.
  String? _texte(
    Object? value,
    Grandeur grandeur,
    int max, {
    bool notes = false,
  }) {
    if (value == null) return null;
    if (value is! String) {
      _refuser(ValeurIllisible(grandeur));
      return null;
    }
    final propre = notes ? nettoyerNotes(value) : nettoyerLigne(value);
    if (propre.retires) _caracteres = true;
    final texte = propre.texte;
    if (texte.isEmpty) return null;
    if (texte.length <= max) return texte;
    _modifs.add(TexteCoupe(grandeur, max));
    return couper(texte, max);
  }

  /// Valeur facultative de [valeurs] ; hors du schéma, écartée et listée.
  String? _valeur(Object? value, Grandeur grandeur, Set<String> valeurs) {
    if (value == null) return null;
    if (value is! String) {
      _refuser(ValeurIllisible(grandeur));
      return null;
    }
    if (valeurs.contains(value)) return value;
    _modifs.add(ValeurRejetee(grandeur, RaisonRejet.inconnue));
    return null;
  }

  /// Valeur obligatoire de [valeurs] ; absente ou hors du schéma : refus.
  String? _valeurObligatoire(
    Object? value,
    Grandeur grandeur,
    Set<String> valeurs,
  ) {
    if (value == null) {
      _refuser(ValeurAbsente(grandeur));
      return null;
    }
    if (value is! String) {
      _refuser(ValeurIllisible(grandeur));
      return null;
    }
    if (valeurs.contains(value)) return value;
    _refuser(
      ValeurInconnue(grandeur, couper(nettoyerLigne(value).texte, kMaxNom)),
    );
    return null;
  }

  /// Couple `{value, unit}` facultatif.
  _Couple? _couple(Object? value, Grandeur grandeur) {
    final m = _objet(value);
    if (m == null) return null;
    _cles(m, const {'value', 'unit'});
    final unit = m['unit'];
    final number = m['value'];
    if (unit is! String || number is! num || !number.isFinite) {
      _refuser(ValeurIllisible(grandeur));
      return null;
    }
    return (value: number.toDouble(), unit: unit);
  }

  /// Unité lue, pour le compte rendu : nettoyée (contrôles de direction
  /// retirés, P9) et coupée à [kMaxNom].
  String _unite(String unite) => couper(nettoyerLigne(unite).texte, kMaxNom);

  void _converti(String unite, String canonique) {
    if (unite != canonique) _unites.add(unite);
  }

  /// Valeur hors bornes : refus si [obligatoire], sinon écartée et listée.
  void _horsLimites(Grandeur grandeur, {required bool obligatoire}) {
    if (obligatoire) {
      _refuser(ValeurHorsLimites(grandeur));
    } else {
      _modifs.add(ValeurRejetee(grandeur, RaisonRejet.horsLimites));
    }
  }

  /// Quantité `{value, unit}` en `g`, ou en `l` si [volume] : masse ou volume
  /// converti, jamais négatif. Une unité sans dimension (`each`, `pkg`) refuse
  /// la recette si la quantité est [obligatoire], sinon elle est écartée.
  _Json? _quantite(
    Object? value,
    Grandeur grandeur, {
    required bool obligatoire,
    required bool volume,
  }) {
    final c = _couple(value, grandeur);
    if (c == null) {
      if (value == null && obligatoire) _refuser(ValeurAbsente(grandeur));
      return null;
    }
    final grammes = kGrammesPar[c.unit];
    final litres = volume ? kLitresPar[c.unit] : null;
    if (grammes == null && litres == null) {
      if (!obligatoire && kUnitesSansDimension.contains(c.unit)) {
        _modifs.add(
          ValeurRejetee(grandeur, RaisonRejet.uniteNonPriseEnCharge, c.unit),
        );
      } else {
        _refuser(UniteInconnue(grandeur, _unite(c.unit)));
      }
      return null;
    }
    final valeur = grammes != null ? c.value * grammes : c.value * litres!;
    final max = grammes != null ? kMaxGrammesParLigne : kMaxLitresParLigne;
    if (!valeur.isFinite || valeur < 0 || valeur > max) {
      _horsLimites(grandeur, obligatoire: obligatoire);
      return null;
    }
    final unite = grammes != null ? 'g' : 'l';
    _converti(c.unit, unite);
    return {'value': valeur, 'unit': unite};
  }

  /// Pourcentage facultatif de 0 à 100 ; [zeroAbsent] : 0 se lit comme absent.
  double? _pourcent(
    Object? value,
    Grandeur grandeur, {
    bool zeroAbsent = false,
  }) {
    final c = _couple(value, grandeur);
    if (c == null) return null;
    if (c.unit != '%') {
      _refuser(UniteInconnue(grandeur, _unite(c.unit)));
      return null;
    }
    if (c.value < 0 || c.value > 100) {
      _horsLimites(grandeur, obligatoire: false);
      return null;
    }
    if (zeroAbsent && c.value == 0) {
      _modifs.add(ValeurRejetee(grandeur, RaisonRejet.nulle));
      return null;
    }
    return c.value;
  }

  /// Température en °C, de [min] à [max].
  double? _temperature(
    Object? value,
    Grandeur grandeur, {
    required double min,
    required double max,
    required bool obligatoire,
  }) {
    final c = _couple(value, grandeur);
    if (c == null) {
      if (value == null && obligatoire) _refuser(ValeurAbsente(grandeur));
      return null;
    }
    if (!kUnitesTemperature.contains(c.unit)) {
      _refuser(UniteInconnue(grandeur, _unite(c.unit)));
      return null;
    }
    final celsius = versCelsius(c.value, c.unit);
    if (celsius < min || celsius > max) {
      _horsLimites(grandeur, obligatoire: obligatoire);
      return null;
    }
    _converti(c.unit, 'C');
    return celsius;
  }

  /// Durée en minutes entières, de 0 à [max] (sinon [kMaxDuree]) ; une durée
  /// décimale est arrondie et listée.
  int? _duree(
    Object? value,
    Grandeur grandeur, {
    int? max,
    bool obligatoire = false,
  }) {
    final c = _couple(value, grandeur);
    if (c == null) {
      if (value == null && obligatoire) _refuser(ValeurAbsente(grandeur));
      return null;
    }
    final facteur = kMinutesPar[c.unit];
    if (facteur == null) {
      _refuser(UniteInconnue(grandeur, _unite(c.unit)));
      return null;
    }
    final minutes = c.value * facteur;
    if (!minutes.isFinite || minutes < 0 || minutes > (max ?? kMaxDuree)) {
      _horsLimites(grandeur, obligatoire: obligatoire);
      return null;
    }
    _converti(c.unit, 'min');
    final arrondi = minutes.round();
    if ((arrondi - minutes).abs() > 1e-9) _modifs.add(DureeArrondie(grandeur));
    return arrondi;
  }

  /// Couleur en EBC, de 0 à [kMaxEbc].
  double? _couleur(Object? value, Grandeur grandeur) {
    final c = _couple(value, grandeur);
    if (c == null) return null;
    if (!kUnitesCouleur.contains(c.unit)) {
      _refuser(UniteInconnue(grandeur, _unite(c.unit)));
      return null;
    }
    if (c.value < 0) {
      _horsLimites(grandeur, obligatoire: false);
      return null;
    }
    final ebc = versEbc(c.value, c.unit);
    if (!ebc.isFinite || ebc > kMaxEbc) {
      _horsLimites(grandeur, obligatoire: false);
      return null;
    }
    _converti(c.unit, 'EBC');
    return ebc;
  }

  /// Rendement d'extrait en % : `fine_grind`, sinon `potential` converti par
  /// `brewing/`. `coarse_grind` seul : écarté et listé.
  double? _rendement(Object? value, Grandeur grandeur) {
    final y = _objet(value);
    if (y == null) return null;
    _cles(
      y,
      const {'fine_grind', 'coarse_grind', 'potential'},
      const {'fine_coarse_difference': PartieNonImportee.detailsIngredients},
    );
    if (y['fine_grind'] != null) {
      return _pourcent(y['fine_grind'], grandeur, zeroAbsent: true);
    }
    if (y['potential'] != null) {
      final c = _couple(y['potential'], grandeur);
      if (c == null) return null;
      if (!kUnitesDensite.contains(c.unit)) {
        _refuser(UniteInconnue(grandeur, _unite(c.unit)));
        return null;
      }
      if (c.unit != 'sg') {
        _modifs.add(
          ValeurRejetee(grandeur, RaisonRejet.uniteNonPriseEnCharge, c.unit),
        );
        return null;
      }
      if (c.value < 1 || c.value > maxPotentialGravity) {
        _horsLimites(grandeur, obligatoire: false);
        return null;
      }
      if (c.value == 1) {
        _modifs.add(ValeurRejetee(grandeur, RaisonRejet.nulle));
        return null;
      }
      _unites.add('potential');
      return potentialToYieldPercent(c.value);
    }
    if (y['coarse_grind'] != null) {
      _modifs.add(ValeurRejetee(grandeur, RaisonRejet.moutureGrossiere));
    }
    return null;
  }

  /// Nom obligatoire d'une ligne ; [nature] : règle K3 d'un ingrédient.
  String? _nomLigne(
    Object? value,
    ListeRecette liste, {
    IngredientNature? nature,
  }) {
    final nom = _texte(value, const Grandeur(Champ.nom), kMaxNom);
    if (_arret) return null;
    if (nom == null || (nature != null && !isValidIngredientName(nom))) {
      _refuser(NomDeLigneIllisible(liste));
      return null;
    }
    return nom;
  }

  /// Vérifie le plafond de la liste [cle] ; le nombre cité est celui du
  /// fichier ([lireRecetteConvertie]), sinon celui de [lignes].
  bool _plafond(
    List<Object?> lignes,
    ListeRecette liste,
    int maximum,
    String cle,
  ) {
    if (lignes.length <= maximum) return true;
    _refuser(TropDeLignes(liste, _nombres[cle] ?? lignes.length, maximum));
    return false;
  }

  // --- Recette ---------------------------------------------------------------

  _Json? recette(Object? brut) {
    final r = _objet(brut);
    if (r == null) {
      _refuser(const RecetteIllisible());
      return null;
    }
    _cles(
      r,
      const {
        'name',
        'type',
        'author',
        'batch_size',
        'style',
        'ingredients',
        'mash',
        'notes',
        'boil',
      },
      const {
        'efficiency': PartieNonImportee.rendement,
        'coauthor': PartieNonImportee.coAuteurEtDate,
        'created': PartieNonImportee.coAuteurEtDate,
        'original_gravity': PartieNonImportee.valeursAnnoncees,
        'final_gravity': PartieNonImportee.valeursAnnoncees,
        'alcohol_by_volume': PartieNonImportee.valeursAnnoncees,
        'ibu_estimate': PartieNonImportee.valeursAnnoncees,
        'color_estimate': PartieNonImportee.valeursAnnoncees,
        'beer_pH': PartieNonImportee.valeursAnnoncees,
        'carbonation': PartieNonImportee.valeursAnnoncees,
        'apparent_attenuation': PartieNonImportee.valeursAnnoncees,
        'calories_per_pint': PartieNonImportee.valeursAnnoncees,
        'fermentation': PartieNonImportee.fermentation,
        'packaging': PartieNonImportee.conditionnement,
        'taste': PartieNonImportee.degustation,
      },
    );
    final name = _texte(r['name'], const Grandeur(Champ.nom), kMaxNom);
    if (_arret) return null;
    if (name == null) {
      _refuser(const NomAbsent());
      return null;
    }
    final type = _valeur(r['type'], const Grandeur(Champ.type), kTypesRecette);
    final author = _texte(r['author'], const Grandeur(Champ.auteur), kMaxNom);
    final style = _style(r['style']);
    final notes = _texte(
      r['notes'],
      const Grandeur(Champ.notes),
      kMaxNotes,
      notes: true,
    );
    final batch = _volume(r['batch_size']);
    final boil = _ebullition(r['boil']);
    final mash = _empatage(r['mash']);
    final ingredients = _ingredients(r['ingredients']);
    if (_arret || ingredients == null) return null;
    return {
      'name': name,
      'type': ?type,
      'author': ?author,
      if (style != null) 'style': {'name': style},
      'notes': ?notes,
      'batch_size': ?batch,
      'boil': ?boil,
      'mash': ?mash,
      'ingredients': ingredients,
    };
  }

  String? _style(Object? value) {
    final s = _objet(value);
    if (s == null) return null;
    final name = _texte(s['name'], const Grandeur(Champ.style), kMaxNom);
    if (name == null) {
      if (!_arret) {
        _modifs.add(
          const ValeurRejetee(Grandeur(Champ.style), RaisonRejet.inconnue),
        );
      }
      return null;
    }
    if (s.keys.any((k) => k != 'name')) _modifs.add(StyleReduitAuNom(name));
    return name;
  }

  _Json? _volume(Object? value) {
    const grandeur = Grandeur(Champ.volume);
    final c = _couple(value, grandeur);
    if (c == null) return null;
    final litres = kLitresPar[c.unit];
    if (litres == null) {
      _refuser(UniteInconnue(grandeur, _unite(c.unit)));
      return null;
    }
    final volume = c.value * litres;
    if (!volume.isFinite || volume <= 0 || volume > kMaxVolumeBrassin) {
      _horsLimites(grandeur, obligatoire: false);
      return null;
    }
    _converti(c.unit, 'l');
    return {'value': volume, 'unit': 'l'};
  }

  _Json? _ebullition(Object? value) {
    final b = _objet(value);
    if (b == null) return null;
    _cles(
      b,
      const {'boil_time'},
      const {
        'name': PartieNonImportee.ebullition,
        'description': PartieNonImportee.ebullition,
        'notes': PartieNonImportee.ebullition,
        'pre_boil_size': PartieNonImportee.ebullition,
        'boil_steps': PartieNonImportee.ebullition,
      },
    );
    final minutes = _duree(
      b['boil_time'],
      const Grandeur(Champ.dureeEbullition),
      max: kMaxDureeEbullition,
    );
    if (minutes == null) return null;
    return {
      'boil_time': {'value': minutes, 'unit': 'min'},
    };
  }

  _Json? _empatage(Object? value) {
    final m = _objet(value);
    if (m == null) return null;
    _cles(
      m,
      const {'name', 'grain_temperature', 'mash_steps'},
      const {'notes': PartieNonImportee.detailsPaliers},
    );
    final grain = _temperature(
      m['grain_temperature'],
      const Grandeur(Champ.temperatureGrain),
      min: kMinTemperatureGrain,
      max: kMaxTemperatureGrain,
      obligatoire: false,
    );
    final lignes = _liste(m['mash_steps']);
    if (!_plafond(lignes, ListeRecette.paliers, kMaxPaliers, 'mash_steps')) {
      return null;
    }
    final steps = <_Json>[];
    for (final brut in lignes) {
      final step = _palier(brut);
      if (_arret) return null;
      steps.add(step!);
    }
    if (grain == null && steps.isEmpty) return null;
    return {
      'name': kNomEmpatage,
      if (grain != null) 'grain_temperature': {'value': grain, 'unit': 'C'},
      // Absent sans palier, jamais une liste vide (ADR-005).
      if (steps.isNotEmpty) 'mash_steps': steps,
    };
  }

  _Json? _palier(Object? brut) {
    final s = _objet(brut);
    if (s == null) {
      _refuser(const RecetteIllisible());
      return null;
    }
    _cles(
      s,
      const {'name', 'type', 'step_temperature', 'step_time'},
      const {
        'amount': PartieNonImportee.detailsPaliers,
        'ramp_time': PartieNonImportee.detailsPaliers,
        'end_temperature': PartieNonImportee.detailsPaliers,
        'description': PartieNonImportee.detailsPaliers,
        'water_grain_ratio': PartieNonImportee.detailsPaliers,
        'infuse_temperature': PartieNonImportee.detailsPaliers,
        'start_ph': PartieNonImportee.detailsPaliers,
        'end_ph': PartieNonImportee.detailsPaliers,
      },
    );
    final name = _nomLigne(s['name'], ListeRecette.paliers);
    if (name == null) return null;
    final type = _valeur(s['type'], Grandeur(Champ.type, name), kTypesPalier);
    final temp = _temperature(
      s['step_temperature'],
      Grandeur(Champ.temperaturePalier, name),
      min: kMinTemperaturePalier,
      max: kMaxTemperaturePalier,
      obligatoire: true,
    );
    final time = _duree(
      s['step_time'],
      Grandeur(Champ.dureePalier, name),
      max: kMaxDureePalier,
      obligatoire: true,
    );
    if (_arret || temp == null || time == null) return null;
    return {
      'name': name,
      'type': ?type,
      'step_temperature': {'value': temp, 'unit': 'C'},
      'step_time': {'value': time, 'unit': 'min'},
    };
  }

  _Json? _ingredients(Object? value) {
    final i = _objet(value) ?? const <String, Object?>{};
    if (_arret) return null;
    _cles(
      i,
      const {
        'fermentable_additions',
        'hop_additions',
        'miscellaneous_additions',
        'culture_additions',
      },
      const {'water_additions': PartieNonImportee.eau},
    );
    final listes = <String, List<_Json>>{};
    for (final (key, liste, lire)
        in <(String, ListeRecette, _Json? Function(Object?))>[
          ('fermentable_additions', ListeRecette.malts, _malt),
          ('hop_additions', ListeRecette.houblons, _houblon),
          ('miscellaneous_additions', ListeRecette.ajouts, _ajout),
          ('culture_additions', ListeRecette.levures, _levure),
        ]) {
      final lignes = _liste(i[key]);
      if (!_plafond(lignes, liste, kPlafondsListes[key]!, key)) return null;
      final lues = <_Json>[];
      for (final brut in lignes) {
        final ligne = lire(brut);
        if (_arret) return null;
        lues.add(ligne!);
      }
      listes[key] = lues;
    }
    if (_arret) return null;
    return listes;
  }

  _Json? _ligne(Object? brut) {
    final m = _objet(brut);
    if (m == null) _refuser(const RecetteIllisible());
    return m;
  }

  _Json? _malt(Object? brut) {
    final f = _ligne(brut);
    if (f == null) return null;
    _cles(
      f,
      const {'name', 'type', 'yield', 'color', 'amount'},
      const {
        'origin': PartieNonImportee.detailsIngredients,
        'producer': PartieNonImportee.detailsIngredients,
        'product_id': PartieNonImportee.detailsIngredients,
        'grain_group': PartieNonImportee.detailsIngredients,
        'timing': PartieNonImportee.detailsIngredients,
      },
    );
    final name = _nomLigne(
      f['name'],
      ListeRecette.malts,
      nature: IngredientNature.malt,
    );
    if (name == null) return null;
    final type = _valeurObligatoire(
      f['type'],
      Grandeur(Champ.type, name),
      kTypesFermentable,
    );
    final amount = _quantite(
      f['amount'],
      Grandeur(Champ.quantite, name),
      obligatoire: true,
      volume: false,
    );
    final color = _couleur(f['color'], Grandeur(Champ.couleur, name));
    final yieldPct = _rendement(f['yield'], Grandeur(Champ.rendement, name));
    if (_arret || type == null || amount == null) return null;
    return {
      'name': name,
      'type': type,
      'amount': amount,
      if (color != null) 'color': {'value': color, 'unit': 'EBC'},
      if (yieldPct != null)
        'yield': {
          'fine_grind': {'value': yieldPct, 'unit': '%'},
        },
    };
  }

  _Json? _houblon(Object? brut) {
    final h = _ligne(brut);
    if (h == null) return null;
    _cles(
      h,
      const {'name', 'form', 'alpha_acid', 'amount', 'timing'},
      const {
        'producer': PartieNonImportee.detailsIngredients,
        'product_id': PartieNonImportee.detailsIngredients,
        'origin': PartieNonImportee.detailsIngredients,
        'year': PartieNonImportee.detailsIngredients,
        'beta_acid': PartieNonImportee.detailsIngredients,
      },
    );
    final name = _nomLigne(
      h['name'],
      ListeRecette.houblons,
      nature: IngredientNature.hop,
    );
    if (name == null) return null;
    // Forme facultative (ADR-005, D8) : une ligne sans forme est gardée sans
    // `form`, sans perte ; aucune forme n'est inventée. Une forme hors du
    // schéma reste refusée.
    final form = h['form'] == null
        ? null
        : _valeurObligatoire(
            h['form'],
            Grandeur(Champ.forme, name),
            kFormesHoublon,
          );
    final alpha = _pourcent(
      h['alpha_acid'],
      Grandeur(Champ.acidesAlpha, name),
      zeroAbsent: true,
    );
    final amount = _quantite(
      h['amount'],
      Grandeur(Champ.quantite, name),
      obligatoire: true,
      volume: true,
    );
    final timing = _moment(h['timing'], name, houblon: true);
    if (_arret || amount == null || timing == null) return null;
    return {
      'name': name,
      'form': ?form,
      if (alpha != null) 'alpha_acid': {'value': alpha, 'unit': '%'},
      'amount': amount,
      'timing': timing,
    };
  }

  _Json? _ajout(Object? brut) {
    final o = _ligne(brut);
    if (o == null) return null;
    _cles(
      o,
      const {'name', 'type', 'amount', 'timing'},
      const {
        'producer': PartieNonImportee.detailsIngredients,
        'product_id': PartieNonImportee.detailsIngredients,
      },
    );
    final name = _nomLigne(
      o['name'],
      ListeRecette.ajouts,
      nature: IngredientNature.addition,
    );
    if (name == null) return null;
    final type = _valeur(o['type'], Grandeur(Champ.type, name), kTypesAjout);
    final amount = _quantite(
      o['amount'],
      Grandeur(Champ.quantite, name),
      obligatoire: true,
      volume: true,
    );
    final timing = _moment(o['timing'], name, houblon: false);
    if (_arret || amount == null) return null;
    return {'name': name, 'type': ?type, 'amount': amount, 'timing': ?timing};
  }

  _Json? _levure(Object? brut) {
    final y = _ligne(brut);
    if (y == null) return null;
    _cles(
      y,
      const {'name', 'type', 'form', 'attenuation', 'amount'},
      const {
        'producer': PartieNonImportee.detailsIngredients,
        'product_id': PartieNonImportee.detailsIngredients,
        'times_cultured': PartieNonImportee.detailsIngredients,
        'timing': PartieNonImportee.detailsIngredients,
        'cell_count_billions': PartieNonImportee.detailsIngredients,
      },
    );
    final name = _nomLigne(
      y['name'],
      ListeRecette.levures,
      nature: IngredientNature.yeast,
    );
    if (name == null) return null;
    final type = _valeur(y['type'], Grandeur(Champ.type, name), kTypesLevure);
    final form = _valeur(y['form'], Grandeur(Champ.forme, name), kFormesLevure);
    final attenuation = _pourcent(
      y['attenuation'],
      Grandeur(Champ.attenuation, name),
    );
    final amount = _quantite(
      y['amount'],
      Grandeur(Champ.quantite, name),
      obligatoire: false,
      volume: true,
    );
    if (_arret) return null;
    return {
      'name': name,
      'type': ?type,
      'form': ?form,
      if (attenuation != null)
        'attenuation': {'value': attenuation, 'unit': '%'},
      'amount': ?amount,
    };
  }

  /// `timing` d'un [houblon] (obligatoire) ou d'un ajout, dans la forme que
  /// lit l'application : à l'ébullition, `time` (sinon `duration`, ADR-005),
  /// ou `time` à 0 avec `duration` après l'arrêt du feu ; houblon à cru,
  /// `time` (jour d'ajout) et `duration` ; autres moments, `duration` seule.
  _Json? _moment(Object? value, String name, {required bool houblon}) {
    final obligatoire = houblon;
    final t = _objet(value);
    if (t == null) {
      if (value == null && obligatoire) {
        _refuser(ValeurAbsente(Grandeur(Champ.moment, name)));
      }
      return null;
    }
    _cles(t, const {
      'use',
      'time',
      'duration',
      'continuous',
      'specific_gravity',
      'pH',
      'step',
    });
    var simplifie =
        t['continuous'] != null ||
        t['specific_gravity'] != null ||
        t['pH'] != null ||
        t['step'] != null;
    final Object? useBrut = t['use'];
    if (useBrut == null && !obligatoire) {
      // Ajout sans moment : la recette le garde sans moment.
      if (t.isNotEmpty) _modifs.add(MomentSimplifie(name, null));
      return null;
    }
    final use = _valeurObligatoire(
      useBrut,
      Grandeur(Champ.moment, name),
      kUsages,
    );
    if (use == null) return null;
    final grandeur = Grandeur(Champ.duree, name);
    final boil = use == 'add_to_boil';
    final max = boil ? kMaxDureeEbullition : null;
    final aTime = t['time'] != null;
    final time = _duree(t['time'], grandeur, max: max);
    final duration = _duree(t['duration'], grandeur, max: max);
    if (_arret) return null;
    final _Json result;
    switch (use) {
      case 'add_to_boil':
        if (aTime) {
          if (time == 0 && duration != null && duration > 0) {
            result = _timing(use, time: 0, duration: duration);
          } else {
            if (duration != null) simplifie = true;
            result = _timing(use, time: time);
          }
        } else {
          result = _timing(use, time: duration);
        }
      case 'add_to_fermentation' when houblon:
        result = _timing(use, time: time, duration: duration);
      default:
        if (time != null) simplifie = true;
        result = _timing(use, duration: duration);
    }
    if (simplifie) _modifs.add(MomentSimplifie(name, use));
    return result;
  }

  _Json _timing(String use, {int? time, int? duration}) => {
    'use': use,
    if (time != null) 'time': {'value': time, 'unit': 'min'},
    if (duration != null) 'duration': {'value': duration, 'unit': 'min'},
  };
}
