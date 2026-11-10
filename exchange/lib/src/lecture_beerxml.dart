import 'bornes.dart';
import 'compte_rendu.dart';
import 'decodage_xml.dart';
import 'lecture_beerjson.dart';
import 'schema.dart';
import 'texte.dart';

/// Lecture d'une recette BeerXML 1.0 (`RECIPE`) vers le sous-arbre `recipe` en
/// BeerJSON partiel de Kass'Beer (ADR-005, `DATA_SOURCES.md`, « Correspondance
/// BeerXML → BeerJSON »). La recette est d'abord récrite en BeerJSON (masses en
/// grammes, couleur en Lovibond ou SRM, moments d'ajout), puis lue par la même
/// lecture que le BeerJSON : bornes, unités, nettoyage des textes et compte
/// rendu sont les mêmes. BeerXML est métrique : kilogrammes, litres, °C,
/// minutes. Les champs `DISPLAY_*`, `INVENTORY` et `VERSION` ne sont pas lus.
/// Aucun prix ni stock n'est lu.

/// Lit [recette], un élément `RECIPE`.
ResultatRecette lireRecetteBeerXml(ElementXml recette) {
  final conversion = _Conversion();
  final brut = conversion.recette(recette);
  final refus = conversion.refus;
  if (refus != null) return RecetteRefusee(refus);
  return lireRecetteConvertie(
    brut,
    avant: conversion.modifications,
    parties: conversion.parties,
    inconnus: conversion.inconnus,
    nombres: conversion.nombres,
  );
}

/// Éléments BeerXML dont la lecture utilise les enfants : [lireXml] ne garde
/// que les enfants de ceux-là (et de la racine). Les enfants d'un autre
/// élément (`WATERS`, `EQUIPMENT`, élément inconnu) ne sont pas gardés : la
/// lecture n'en retient que leur présence.
const Set<String> kConteneursBeerXml = {
  'RECIPE',
  'STYLE',
  'HOPS',
  'HOP',
  'FERMENTABLES',
  'FERMENTABLE',
  'MISCS',
  'MISC',
  'YEASTS',
  'YEAST',
  'MASH',
  'MASH_STEPS',
  'MASH_STEP',
};

/// Nom affiché d'une recette du fichier : nettoyé et coupé, ou `null`.
String? nomAfficheXml(ElementXml recette) => _propre(_texte(recette, 'NAME'));

typedef _Json = Map<String, Object?>;

/// Texte non blanc de l'enfant [nom] de [e], ou `null`.
String? _texte(ElementXml e, String nom) {
  final enfant = e.enfant(nom);
  if (enfant == null) return null;
  final texte = enfant.texte.trim();
  return texte.isEmpty ? null : texte;
}

/// Nom nettoyé et coupé comme le fait la lecture du BeerJSON, ou `null`.
String? _propre(String? brut) {
  if (brut == null) return null;
  final texte = nettoyerLigne(brut).texte;
  return texte.isEmpty ? null : couper(texte, kMaxNom);
}

/// Nombre lu, ou le texte tel quel s'il n'en est pas un : la lecture du
/// BeerJSON le refuse alors (« Valeur illisible »). Un nombre non fini reste
/// tel quel, et il est refusé de même.
Object? _nombre(String? texte) {
  if (texte == null) return null;
  return double.tryParse(texte) ?? texte;
}

/// Couple `{value, unit}`, ou `null` sans valeur.
_Json? _couple(Object? valeur, String unite) =>
    valeur == null ? null : {'value': valeur, 'unit': unite};

/// Masse en kilogrammes du BeerXML, en grammes arrondis au microgramme : le
/// produit par 1 000 d'un décimal (4,5359237 kg) n'en garde pas l'écriture.
_Json? _kilogrammes(String? texte) {
  final n = _nombre(texte);
  return _couple(n is double ? (n * 1e9).roundToDouble() / 1e6 : n, 'g');
}

/// Champs propres au BeerXML jamais lus, ni gardés par [lireXml] :
/// présentation et stock.
bool ignoreBeerXml(String nom) => _ignore(nom);

bool _ignore(String nom) =>
    nom == 'VERSION' ||
    nom == 'INVENTORY' ||
    nom.startsWith('DISPLAY_') ||
    nom.startsWith('DISP_');

/// Conversion d'une recette : le premier refus l'arrête ; les modifications,
/// parties non importées et champs inconnus s'accumulent.
class _Conversion {
  Refus? refus;
  final modifications = <Modification>[];
  final parties = <PartieNonImportee>{};
  int inconnus = 0;

  /// Nombre de lignes du fichier, par liste BeerJSON, quand il dépasse le
  /// plafond : seules plafond + 1 lignes sont converties.
  final nombres = <String, int>{};

  /// Compte les enfants de [e] : lus, non importés (s'ils sont renseignés),
  /// ignorés, ou inconnus.
  void _enfants(
    ElementXml e,
    Set<String> lus, [
    Map<String, PartieNonImportee> nonImportes = const {},
  ]) {
    for (final enfant in e.enfants) {
      final nom = enfant.nom;
      if (lus.contains(nom) || _ignore(nom)) continue;
      final partie = nonImportes[nom];
      if (partie != null) {
        if (enfant.renseigne) parties.add(partie);
      } else {
        inconnus++;
      }
    }
  }

  /// Valeur énumérée du BeerXML : [table] (en minuscules), sinon la valeur du
  /// schéma de même nom en minuscules, sinon le texte tel quel, que la lecture
  /// du BeerJSON écarte ou refuse en le citant.
  String? _enumere(
    String? texte,
    Set<String> schema, [
    Map<String, String> table = const {},
  ]) {
    if (texte == null) return null;
    final minuscule = texte.toLowerCase();
    return table[minuscule] ?? (schema.contains(minuscule) ? minuscule : texte);
  }

  /// Enfants [element] de [conteneur], [plafond] + 1 au plus : au-delà, la
  /// recette est refusée (`TropDeLignes`) avec le nombre lu, gardé dans
  /// [nombres] sous [cle] ; aucune ligne de plus n'est convertie. Un autre
  /// enfant est inconnu.
  List<ElementXml> _liste(
    ElementXml? conteneur,
    String element,
    String cle,
    int plafond,
  ) {
    if (conteneur == null) return const [];
    final lignes = <ElementXml>[];
    var nombre = 0;
    for (final e in conteneur.enfants) {
      if (e.nom == element) {
        nombre++;
        if (lignes.length <= plafond) lignes.add(e);
      } else if (!_ignore(e.nom)) {
        inconnus++;
      }
    }
    if (nombre > plafond) nombres[cle] = nombre;
    return lignes;
  }

  /// Quantité en grammes si [AMOUNT_IS_WEIGHT] est vrai, en litres sinon
  /// (valeur par défaut de la norme pour un ajout et une levure).
  _Json? _quantiteMasseOuVolume(ElementXml e, String? nom) {
    final poids = _texte(e, 'AMOUNT_IS_WEIGHT')?.toLowerCase();
    if (poids != null && poids != 'true' && poids != 'false') {
      refus ??= ValeurIllisible(Grandeur(Champ.quantite, nom));
      return null;
    }
    if (poids == 'true') return _kilogrammes(_texte(e, 'AMOUNT'));
    return _couple(_nombre(_texte(e, 'AMOUNT')), 'l');
  }

  _Json recette(ElementXml r) {
    _enfants(
      r,
      const {
        'NAME',
        'TYPE',
        'BREWER',
        'STYLE',
        'NOTES',
        'BATCH_SIZE',
        'BOIL_TIME',
        'MASH',
        'HOPS',
        'FERMENTABLES',
        'MISCS',
        'YEASTS',
      },
      const {
        'EQUIPMENT': PartieNonImportee.equipement,
        'WATERS': PartieNonImportee.eau,
        'EFFICIENCY': PartieNonImportee.rendement,
        'ACTUAL_EFFICIENCY': PartieNonImportee.rendement,
        'BOIL_SIZE': PartieNonImportee.ebullition,
        'ASST_BREWER': PartieNonImportee.coAuteurEtDate,
        'DATE': PartieNonImportee.coAuteurEtDate,
        'OG': PartieNonImportee.valeursAnnoncees,
        'FG': PartieNonImportee.valeursAnnoncees,
        'EST_OG': PartieNonImportee.valeursAnnoncees,
        'EST_FG': PartieNonImportee.valeursAnnoncees,
        'EST_COLOR': PartieNonImportee.valeursAnnoncees,
        'IBU': PartieNonImportee.valeursAnnoncees,
        'IBU_METHOD': PartieNonImportee.valeursAnnoncees,
        'EST_ABV': PartieNonImportee.valeursAnnoncees,
        'ABV': PartieNonImportee.valeursAnnoncees,
        'CALORIES': PartieNonImportee.valeursAnnoncees,
        'FERMENTATION_STAGES': PartieNonImportee.fermentation,
        'PRIMARY_AGE': PartieNonImportee.fermentation,
        'PRIMARY_TEMP': PartieNonImportee.fermentation,
        'SECONDARY_AGE': PartieNonImportee.fermentation,
        'SECONDARY_TEMP': PartieNonImportee.fermentation,
        'TERTIARY_AGE': PartieNonImportee.fermentation,
        'TERTIARY_TEMP': PartieNonImportee.fermentation,
        'AGE': PartieNonImportee.fermentation,
        'AGE_TEMP': PartieNonImportee.fermentation,
        'CARBONATION': PartieNonImportee.conditionnement,
        'FORCED_CARBONATION': PartieNonImportee.conditionnement,
        'PRIMING_SUGAR_NAME': PartieNonImportee.conditionnement,
        'CARBONATION_TEMP': PartieNonImportee.conditionnement,
        'PRIMING_SUGAR_EQUIV': PartieNonImportee.conditionnement,
        'KEG_PRIMING_FACTOR': PartieNonImportee.conditionnement,
        'TASTE_NOTES': PartieNonImportee.degustation,
        'TASTE_RATING': PartieNonImportee.degustation,
      },
    );
    final boilTime = _texte(r, 'BOIL_TIME');
    final style = r.enfant('STYLE');
    final mash = r.enfant('MASH');
    return {
      'name': _texte(r, 'NAME'),
      'type': _enumere(_texte(r, 'TYPE'), kTypesRecette),
      'author': _texte(r, 'BREWER'),
      if (style != null && style.renseigne) 'style': _style(style),
      'notes': r.enfant('NOTES')?.texte,
      'batch_size': _couple(_nombre(_texte(r, 'BATCH_SIZE')), 'l'),
      if (boilTime != null)
        'boil': {'boil_time': _couple(_nombre(boilTime), 'min')},
      if (mash != null) 'mash': _empatage(mash),
      'ingredients': {
        'fermentable_additions': [
          for (final f in _liste(
            r.enfant('FERMENTABLES'),
            'FERMENTABLE',
            'fermentable_additions',
            kPlafondsListes['fermentable_additions']!,
          ))
            _malt(f),
        ],
        'hop_additions': [
          for (final h in _liste(
            r.enfant('HOPS'),
            'HOP',
            'hop_additions',
            kPlafondsListes['hop_additions']!,
          ))
            _houblon(h, _nombre(boilTime)),
        ],
        'miscellaneous_additions': [
          for (final m in _liste(
            r.enfant('MISCS'),
            'MISC',
            'miscellaneous_additions',
            kPlafondsListes['miscellaneous_additions']!,
          ))
            _ajout(m),
        ],
        'culture_additions': [
          for (final y in _liste(
            r.enfant('YEASTS'),
            'YEAST',
            'culture_additions',
            kPlafondsListes['culture_additions']!,
          ))
            _levure(y),
        ],
      },
    };
  }

  /// Style : son nom seul. Le reste (catégorie, plages) demande le
  /// référentiel des styles (ADR-005).
  _Json _style(ElementXml s) {
    final nom = _texte(s, 'NAME');
    final propre = _propre(nom);
    final autres = s.enfants.any(
      (e) => e.nom != 'NAME' && !_ignore(e.nom) && e.renseigne,
    );
    if (propre != null && autres) modifications.add(StyleReduitAuNom(propre));
    return {'name': nom};
  }

  _Json _empatage(ElementXml m) {
    _enfants(
      m,
      const {'NAME', 'GRAIN_TEMP', 'MASH_STEPS'},
      const {
        'NOTES': PartieNonImportee.detailsPaliers,
        'TUN_TEMP': PartieNonImportee.detailsPaliers,
        'SPARGE_TEMP': PartieNonImportee.detailsPaliers,
        'PH': PartieNonImportee.detailsPaliers,
        'TUN_WEIGHT': PartieNonImportee.detailsPaliers,
        'TUN_SPECIFIC_HEAT': PartieNonImportee.detailsPaliers,
        'EQUIP_ADJUST': PartieNonImportee.detailsPaliers,
      },
    );
    // Le nom de l'empâtage est remplacé par un libellé (`kNomEmpatage`).
    final nom = _texte(m, 'NAME');
    if (nom != null && nom != kNomEmpatage) {
      parties.add(PartieNonImportee.nomEmpatage);
    }
    final paliers = _liste(
      m.enfant('MASH_STEPS'),
      'MASH_STEP',
      'mash_steps',
      kMaxPaliers,
    );
    return {
      'grain_temperature': _couple(_nombre(_texte(m, 'GRAIN_TEMP')), 'C'),
      if (paliers.isNotEmpty)
        'mash_steps': [for (final p in paliers) _palier(p)],
    };
  }

  _Json _palier(ElementXml p) {
    _enfants(
      p,
      const {'NAME', 'TYPE', 'STEP_TEMP', 'STEP_TIME'},
      const {
        'INFUSE_AMOUNT': PartieNonImportee.detailsPaliers,
        'RAMP_TIME': PartieNonImportee.detailsPaliers,
        'END_TEMP': PartieNonImportee.detailsPaliers,
        'DESCRIPTION': PartieNonImportee.detailsPaliers,
        'WATER_GRAIN_RATIO': PartieNonImportee.detailsPaliers,
        'DECOCTION_AMT': PartieNonImportee.detailsPaliers,
        'INFUSE_TEMP': PartieNonImportee.detailsPaliers,
      },
    );
    return {
      'name': _texte(p, 'NAME'),
      'type': _enumere(_texte(p, 'TYPE'), kTypesPalier),
      'step_temperature': _couple(_nombre(_texte(p, 'STEP_TEMP')), 'C'),
      'step_time': _couple(_nombre(_texte(p, 'STEP_TIME')), 'min'),
    };
  }

  _Json _malt(ElementXml f) {
    _enfants(
      f,
      const {'NAME', 'TYPE', 'AMOUNT', 'YIELD', 'COLOR', 'POTENTIAL'},
      const {
        'ADD_AFTER_BOIL': PartieNonImportee.detailsIngredients,
        'ORIGIN': PartieNonImportee.detailsIngredients,
        'SUPPLIER': PartieNonImportee.detailsIngredients,
        'NOTES': PartieNonImportee.detailsIngredients,
        'COARSE_FINE_DIFF': PartieNonImportee.detailsIngredients,
        'MOISTURE': PartieNonImportee.detailsIngredients,
        'DIASTATIC_POWER': PartieNonImportee.detailsIngredients,
        'PROTEIN': PartieNonImportee.detailsIngredients,
        'MAX_IN_BATCH': PartieNonImportee.detailsIngredients,
        'RECOMMEND_MASH': PartieNonImportee.detailsIngredients,
        'IBU_GAL_PER_LB': PartieNonImportee.detailsIngredients,
      },
    );
    final type = _enumere(_texte(f, 'TYPE'), kTypesFermentable, const {
      'adjunct': 'grain',
    });
    final rendement = _texte(f, 'YIELD');
    final potentiel = _texte(f, 'POTENTIAL');
    return {
      'name': _texte(f, 'NAME'),
      'type': type,
      'amount': _kilogrammes(_texte(f, 'AMOUNT')),
      // La norme donne la couleur en Lovibond, en SRM pour un extrait
      // liquide ; les deux se convertissent en EBC dans brewing/ (P3).
      'color': _couple(
        _nombre(_texte(f, 'COLOR')),
        type == 'extract' ? 'SRM' : 'Lovi',
      ),
      if (rendement != null)
        'yield': {'fine_grind': _couple(_nombre(rendement), '%')}
      else if (potentiel != null)
        'yield': {'potential': _couple(_nombre(potentiel), 'sg')},
    };
  }

  _Json _houblon(ElementXml h, Object? ebullition) {
    _enfants(
      h,
      const {'NAME', 'ALPHA', 'AMOUNT', 'USE', 'TIME', 'FORM'},
      const {
        'NOTES': PartieNonImportee.detailsIngredients,
        'TYPE': PartieNonImportee.detailsIngredients,
        'BETA': PartieNonImportee.detailsIngredients,
        'HSI': PartieNonImportee.detailsIngredients,
        'ORIGIN': PartieNonImportee.detailsIngredients,
        'SUBSTITUTES': PartieNonImportee.detailsIngredients,
        'HUMULENE': PartieNonImportee.detailsIngredients,
        'CARYOPHYLLENE': PartieNonImportee.detailsIngredients,
        'COHUMULONE': PartieNonImportee.detailsIngredients,
        'MYRCENE': PartieNonImportee.detailsIngredients,
      },
    );
    final nom = _texte(h, 'NAME');
    return {
      'name': nom,
      'form': _enumere(_texte(h, 'FORM'), kFormesHoublon),
      'alpha_acid': _couple(_nombre(_texte(h, 'ALPHA')), '%'),
      'amount': _kilogrammes(_texte(h, 'AMOUNT')),
      'timing': _momentHoublon(
        _texte(h, 'USE'),
        _nombre(_texte(h, 'TIME')),
        _propre(nom),
        ebullition,
      ),
    };
  }

  /// Moment d'un houblon (`DATA_SOURCES.md`) : `Boil`, `Aroma`, `First Wort`,
  /// `Dry Hop`, `Mash`, et `Whirlpool`, `Secondary` hors norme.
  _Json? _momentHoublon(
    String? use,
    Object? time,
    String? nom,
    Object? ebullition,
  ) {
    if (use == null) return null;
    _Json minutes(Object? v) => {'value': v, 'unit': 'min'};
    final sansDuree = time == null || time == 0;
    switch (use.toLowerCase()) {
      case 'boil':
        return {'use': 'add_to_boil', 'time': ?_couple(time, 'min')};
      case 'first wort':
        if (nom != null) {
          modifications.add(FirstWortEnEbullition(nom, _minutes(ebullition)));
        }
        return {'use': 'add_to_boil', 'time': ?_couple(ebullition, 'min')};
      case 'aroma' || 'whirlpool' when sansDuree:
        if (nom != null && (time == null || use.toLowerCase() == 'whirlpool')) {
          modifications.add(
            ArretDuFeuSansDuree(
              nom,
              use.toLowerCase() == 'aroma' ? 'Aroma' : 'Whirlpool',
            ),
          );
        }
        return {'use': 'add_to_boil', 'time': minutes(0)};
      case 'aroma':
        final n = _minutes(time);
        if (nom != null && n != null) {
          modifications.add(AromaEnEbullition(nom, n));
        }
        return {'use': 'add_to_boil', 'time': minutes(time)};
      case 'whirlpool':
        return {
          'use': 'add_to_boil',
          'time': minutes(0),
          'duration': minutes(time),
        };
      case 'dry hop':
        return {
          'use': 'add_to_fermentation',
          'duration': ?_couple(time, 'min'),
        };
      case 'secondary':
        if (nom != null) {
          modifications.add(MomentSimplifie(nom, 'add_to_fermentation'));
        }
        return {
          'use': 'add_to_fermentation',
          'duration': ?_couple(time, 'min'),
        };
      case 'mash':
        return {'use': 'add_to_mash', 'duration': ?_couple(time, 'min')};
      default:
        return {'use': use};
    }
  }

  _Json _ajout(ElementXml m) {
    _enfants(
      m,
      const {'NAME', 'TYPE', 'USE', 'TIME', 'AMOUNT', 'AMOUNT_IS_WEIGHT'},
      const {
        'USE_FOR': PartieNonImportee.detailsIngredients,
        'NOTES': PartieNonImportee.detailsIngredients,
      },
    );
    final nom = _texte(m, 'NAME');
    final time = _couple(_nombre(_texte(m, 'TIME')), 'min');
    final use = _texte(m, 'USE');
    final _Json? timing;
    switch (use?.toLowerCase()) {
      case null:
        timing = time == null ? null : {'duration': time};
      case 'boil':
        timing = {'use': 'add_to_boil', 'time': ?time};
      case 'mash':
        timing = {'use': 'add_to_mash', 'duration': ?time};
      case 'primary':
        timing = {'use': 'add_to_fermentation', 'duration': ?time};
      case 'secondary':
        final propre = _propre(nom);
        if (propre != null) {
          modifications.add(MomentSimplifie(propre, 'add_to_fermentation'));
        }
        timing = {'use': 'add_to_fermentation', 'duration': ?time};
      case 'bottling':
        timing = {'use': 'add_to_package', 'duration': ?time};
      default:
        timing = {'use': use};
    }
    return {
      'name': nom,
      'type': _enumere(_texte(m, 'TYPE'), kTypesAjout),
      'amount': _quantiteMasseOuVolume(m, _propre(nom)),
      'timing': ?timing,
    };
  }

  _Json _levure(ElementXml y) {
    _enfants(
      y,
      const {
        'NAME',
        'TYPE',
        'FORM',
        'AMOUNT',
        'AMOUNT_IS_WEIGHT',
        'ATTENUATION',
      },
      const {
        'LABORATORY': PartieNonImportee.detailsIngredients,
        'PRODUCT_ID': PartieNonImportee.detailsIngredients,
        'MIN_TEMPERATURE': PartieNonImportee.detailsIngredients,
        'MAX_TEMPERATURE': PartieNonImportee.detailsIngredients,
        'FLOCCULATION': PartieNonImportee.detailsIngredients,
        'NOTES': PartieNonImportee.detailsIngredients,
        'BEST_FOR': PartieNonImportee.detailsIngredients,
        'TIMES_CULTURED': PartieNonImportee.detailsIngredients,
        'MAX_REUSE': PartieNonImportee.detailsIngredients,
        'ADD_TO_SECONDARY': PartieNonImportee.detailsIngredients,
        'CULTURE_DATE': PartieNonImportee.detailsIngredients,
      },
    );
    final nom = _texte(y, 'NAME');
    return {
      'name': nom,
      // `Wheat` donne `wheat`, valeur du schéma (ADR-005, amendements de L2).
      'type': _enumere(_texte(y, 'TYPE'), kTypesLevure),
      'form': _enumere(_texte(y, 'FORM'), kFormesLevure),
      'attenuation': _couple(_nombre(_texte(y, 'ATTENUATION')), '%'),
      'amount': _quantiteMasseOuVolume(y, _propre(nom)),
    };
  }
}

/// Minutes entières d'une durée lue, pour un libellé ; `null` si elle n'est
/// pas un nombre fini de 0 à [kMaxDureeEbullition].
int? _minutes(Object? valeur) {
  if (valeur is! double || !valeur.isFinite) return null;
  if (valeur < 0 || valeur > kMaxDureeEbullition) return null;
  return valeur.round();
}
