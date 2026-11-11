import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:exchange/exchange.dart';
import 'package:exchange/src/decodage_xml.dart';
import 'package:exchange/src/lecture_beerxml.dart';
import 'package:test/test.dart';

import 'support/description.dart';

/// Écriture du BeerXML (L2c d'ADR-005) et critère A1 du cadrage : pour chaque
/// fixture BeerXML écrite à la main, lecture → modèle → écriture → relecture.
/// La recette relue est égale à la recette lue (masses à 0,01 g, couleur à
/// 0,1 EBC, durées exactes), et l'écart entre le fichier source et l'export
/// est la liste des pertes du compte rendu de l'import.

/// Équipement des tests : évaporation, pertes au trub, volume mort.
const _evaporation = 3.0;
const _trub = 1.0;
const _volumeMort = 0.5;
const _rendement = 72.0;

const _fixtures = [
  'beerxml-beersmith',
  'beerxml-brewfather',
  'beerxml-brewers-friend',
  'beerxml-brewtarget',
];

/// Arbre XML d'un fichier, BOM retiré.
ElementXml _arbre(List<int> octets) {
  final debut =
      octets.length >= 3 &&
          octets[0] == 0xEF &&
          octets[1] == 0xBB &&
          octets[2] == 0xBF
      ? 3
      : 0;
  final lu = lireXml(
    decoderXml(octets, debut)!,
    maxRecettes: 500,
    conteneurs: kConteneursBeerXml,
  );
  return (lu as XmlArbre).racine;
}

List<ElementXml> _recettes(ElementXml racine) => racine.nom == 'RECIPE'
    ? [racine]
    : [
        for (final e in racine.enfants)
          if (e.nom == 'RECIPE') e,
      ];

String? _t(ElementXml e, String nom) {
  final t = e.enfant(nom)?.texte.trim();
  return t == null || t.isEmpty ? null : t;
}

/// Style du fichier source, à la place de la fiche de la Bibliothèque.
StyleBeerXml _styleDe(ElementXml recette) {
  final s = recette.enfant('STYLE')!;
  String t(String n) => _t(s, n)!;
  double d(String n) => double.parse(t(n));
  double? o(String n) => _t(s, n) == null ? null : d(n);
  return StyleBeerXml(
    nom: t('NAME'),
    categorie: t('CATEGORY'),
    numeroCategorie: t('CATEGORY_NUMBER'),
    lettre: t('STYLE_LETTER'),
    guide: t('STYLE_GUIDE'),
    type: t('TYPE'),
    ogMin: d('OG_MIN'),
    ogMax: d('OG_MAX'),
    fgMin: d('FG_MIN'),
    fgMax: d('FG_MAX'),
    ibuMin: d('IBU_MIN'),
    ibuMax: d('IBU_MAX'),
    ebcMin: srmToEbc(d('COLOR_MIN')),
    ebcMax: srmToEbc(d('COLOR_MAX')),
    abvMin: o('ABV_MIN'),
    abvMax: o('ABV_MAX'),
  );
}

ResultatExport _exporter(
  Map<String, Object?> recipe, {
  StyleBeerXml? style,
  double? evaporation = _evaporation,
  double? trub = _trub,
  double? volumeMort = _volumeMort,
  double? rendement = _rendement,
  String? ownerName,
  RecipeCalculation? calcul,
  bool chronologie = false,
}) => exporterBeerXml(
  recipe: recipe,
  ownerName: ownerName,
  rendementEmpatage: rendement,
  evaporationLParH: evaporation,
  pertesAuTrubL: trub,
  volumeMortL: volumeMort,
  style: style,
  calcul: calcul,
  chronologie: chronologie,
);

/// Tolérance d'une valeur selon son unité (critère A1).
double _tolerance(Object? unit) => switch (unit) {
  'g' => 0.01,
  'EBC' => 0.1,
  'min' => 0,
  _ => 1e-3,
};

/// Compare [a] et [b] : mêmes clés et valeurs, nombres d'un couple à la
/// tolérance de son unité. Rend la liste des écarts.
List<String> _ecarts(Object? a, Object? b, [String chemin = '', Object? unit]) {
  if (a is Map && b is Map) {
    final cles = {...a.keys, ...b.keys};
    return [
      for (final k in cles) ..._ecarts(a[k], b[k], '$chemin.$k', a['unit']),
    ];
  }
  if (a is List && b is List) {
    if (a.length != b.length) return ['$chemin : longueur'];
    return [
      for (var i = 0; i < a.length; i++) ..._ecarts(a[i], b[i], '$chemin[$i]'),
    ];
  }
  if (a is num && b is num) {
    return (a - b).abs() <= _tolerance(unit) ? [] : ['$chemin : $a ≠ $b'];
  }
  return a == b ? [] : ['$chemin : $a ≠ $b'];
}

// --- Écart entre le fichier source et l'export ------------------------------

/// Parties non importées, par élément de la recette (même table que la
/// lecture, écrite ici à part : le test ne relit pas le code qu'il vérifie).
const Map<String, String> _partiesRecette = {
  'EQUIPMENT': 'equipement',
  'WATERS': 'eau',
  'EFFICIENCY': 'rendement',
  'ACTUAL_EFFICIENCY': 'rendement',
  'BOIL_SIZE': 'ebullition',
  'ASST_BREWER': 'coAuteurEtDate',
  'DATE': 'coAuteurEtDate',
  'OG': 'valeursAnnoncees',
  'FG': 'valeursAnnoncees',
  'EST_OG': 'valeursAnnoncees',
  'EST_FG': 'valeursAnnoncees',
  'EST_COLOR': 'valeursAnnoncees',
  'IBU': 'valeursAnnoncees',
  'IBU_METHOD': 'valeursAnnoncees',
  'EST_ABV': 'valeursAnnoncees',
  'ABV': 'valeursAnnoncees',
  'CALORIES': 'valeursAnnoncees',
  'FERMENTATION_STAGES': 'fermentation',
  'PRIMARY_AGE': 'fermentation',
  'PRIMARY_TEMP': 'fermentation',
  'SECONDARY_AGE': 'fermentation',
  'SECONDARY_TEMP': 'fermentation',
  'TERTIARY_AGE': 'fermentation',
  'TERTIARY_TEMP': 'fermentation',
  'AGE': 'fermentation',
  'AGE_TEMP': 'fermentation',
  'CARBONATION': 'conditionnement',
  'FORCED_CARBONATION': 'conditionnement',
  'PRIMING_SUGAR_NAME': 'conditionnement',
  'CARBONATION_TEMP': 'conditionnement',
  'PRIMING_SUGAR_EQUIV': 'conditionnement',
  'KEG_PRIMING_FACTOR': 'conditionnement',
  'TASTE_NOTES': 'degustation',
  'TASTE_RATING': 'degustation',
};

/// Champs lus de chaque ligne ; les autres sont des détails non importés.
const Map<String, Set<String>> _champsLus = {
  'HOP': {'NAME', 'ALPHA', 'AMOUNT', 'USE', 'TIME', 'FORM'},
  'FERMENTABLE': {'NAME', 'TYPE', 'AMOUNT', 'YIELD', 'COLOR'},
  'MISC': {'NAME', 'TYPE', 'USE', 'TIME', 'AMOUNT', 'AMOUNT_IS_WEIGHT'},
  'YEAST': {
    'NAME',
    'TYPE',
    'FORM',
    'AMOUNT',
    'AMOUNT_IS_WEIGHT',
    'ATTENUATION',
  },
  'MASH_STEP': {'NAME', 'TYPE', 'STEP_TEMP', 'STEP_TIME'},
};

/// Équivalences de la correspondance BeerXML → BeerJSON, sans perte : la
/// valeur source et la valeur écrite disent la même chose.
bool _equivalent(String champ, String source, String ecrit) {
  final s = source.toLowerCase();
  final e = ecrit.toLowerCase();
  if (s == e) return true;
  if (champ == 'TYPE' && s == 'adjunct' && e == 'grain') return true;
  return false;
}

bool _ignore(String nom) =>
    nom == 'VERSION' ||
    nom == 'INVENTORY' ||
    nom == 'POTENTIAL' ||
    nom.startsWith('DISPLAY_') ||
    nom.startsWith('DISP_');

bool _memeValeur(String champ, String? a, String? b) {
  if (a == null || b == null) return a == b;
  final x = double.tryParse(a);
  final y = double.tryParse(b);
  if (x != null && y != null) {
    final tolerance = switch (champ) {
      'AMOUNT' => 1e-5, // 0,01 g en kilogrammes
      'COLOR' => 0.05, // 0,1 EBC en Lovibond
      _ => 1e-3,
    };
    return (x - y).abs() <= tolerance;
  }
  return _equivalent(champ, a, b);
}

/// Écarts entre la recette [src] du fichier et la recette [exp] exportée,
/// rangés par catégorie de perte : `partie:<nom>`, `moment:<ligne>`,
/// `inattendu:<chemin>`.
Set<String> _pertesSource(ElementXml src, ElementXml exp) {
  final pertes = <String>{};
  for (final e in src.enfants) {
    final nom = e.nom;
    if (_ignore(nom) || nom == 'STYLE' || !e.renseigne) continue;
    final partie = _partiesRecette[nom];
    if (partie != null) {
      pertes.add('partie:$partie');
      continue;
    }
    switch (nom) {
      case 'MASH':
        _pertesEmpatage(e, exp.enfant('MASH')!, pertes);
      case 'HOPS' || 'FERMENTABLES' || 'MISCS' || 'YEASTS':
        final element = nom.substring(0, nom.length - 1);
        _pertesLignes(e, exp.enfant(nom)!, element, pertes);
      case 'BOIL_TIME':
        if (!_memeValeur(nom, _t(src, nom), _t(exp, nom))) {
          pertes.add('moment:recette');
        }
      default:
        if (!_memeValeur(nom, e.texte.trim(), _t(exp, nom))) {
          pertes.add('inattendu:$nom');
        }
    }
  }
  return pertes;
}

void _pertesEmpatage(ElementXml src, ElementXml exp, Set<String> pertes) {
  for (final e in src.enfants) {
    if (_ignore(e.nom) || !e.renseigne) continue;
    switch (e.nom) {
      case 'GRAIN_TEMP':
        if (!_memeValeur(e.nom, _t(src, e.nom), _t(exp, e.nom))) {
          pertes.add('inattendu:MASH.GRAIN_TEMP');
        }
      case 'MASH_STEPS':
        _pertesLignes(e, exp.enfant('MASH_STEPS')!, 'MASH_STEP', pertes);
      case 'NAME':
        if (_t(src, 'NAME') != _t(exp, 'NAME')) {
          pertes.add('partie:nomEmpatage');
        }
      default:
        pertes.add('partie:detailsPaliers');
    }
  }
}

void _pertesLignes(
  ElementXml src,
  ElementXml exp,
  String element,
  Set<String> pertes,
) {
  final a = [
    for (final e in src.enfants)
      if (e.nom == element) e,
  ];
  final b = [
    for (final e in exp.enfants)
      if (e.nom == element) e,
  ];
  expect(b, hasLength(a.length), reason: element);
  final details = element == 'MASH_STEP'
      ? 'partie:detailsPaliers'
      : 'partie:detailsIngredients';
  for (var i = 0; i < a.length; i++) {
    final ligne = _t(a[i], 'NAME');
    for (final e in a[i].enfants) {
      if (_ignore(e.nom) || !e.renseigne) continue;
      if (!_champsLus[element]!.contains(e.nom)) {
        pertes.add(details);
        continue;
      }
      if (_memeValeur(e.nom, e.texte.trim(), _t(b[i], e.nom))) continue;
      // Aroma à 0 minute et Boil à 0 minute : l'arrêt du feu, sans perte.
      if (element == 'HOP' &&
          e.nom == 'USE' &&
          e.texte.trim().toLowerCase() == 'aroma' &&
          double.tryParse(_t(a[i], 'TIME') ?? '') == 0 &&
          _t(b[i], 'USE') == 'Boil' &&
          _t(b[i], 'TIME') == '0') {
        continue;
      }
      if (const {'USE', 'TIME', 'STEP_TIME'}.contains(e.nom)) {
        pertes.add('moment:$ligne');
      } else {
        pertes.add('inattendu:$element.$ligne.${e.nom}');
      }
    }
    // Un moment déduit d'un champ absent (Aroma sans TIME) est un écart.
    if (element == 'HOP' &&
        _t(a[i], 'TIME') == null &&
        !_memeValeur('USE', _t(a[i], 'USE'), _t(b[i], 'USE'))) {
      pertes.add('moment:$ligne');
    }
  }
}

/// Pertes annoncées par le compte rendu de l'import, dans les mêmes
/// catégories. Le style est exclu : l'export le reprend du référentiel des
/// styles, pas de la recette. Les unités converties ne sont pas des pertes.
Set<String> _pertesCompteRendu(List<Modification> modifications) => {
  for (final m in modifications)
    ...switch (m) {
      PartiesNonImportees(:final parties) => [
        for (final p in parties) 'partie:${p.name}',
      ],
      FirstWortEnEbullition(:final ligne) ||
      ArretDuFeuSansDuree(:final ligne) ||
      AromaEnEbullition(:final ligne) => ['moment:$ligne'],
      MomentSimplifie(:final ligne) => ['moment:$ligne'],
      DureeArrondie(:final grandeur) => [
        'moment:${grandeur.ligne ?? 'recette'}',
      ],
      StyleReduitAuNom() || UnitesConverties() => const <String>[],
      _ => ['autre:${decrire(m)}'],
    },
};

/// Texte d'une fixture d'export ; écrit si `MAJ_FIXTURES` vaut 1.
void _expectTexte(String chemin, String texte) {
  final file = File('test/fixtures/$chemin');
  if (Platform.environment['MAJ_FIXTURES'] == '1') {
    file.writeAsStringSync(texte);
    return;
  }
  expect(
    texte,
    file.readAsStringSync().replaceAll('\r\n', '\n'),
    reason: 'test/fixtures/$chemin',
  );
}

Map<String, Object?> _m(num value, String unit) => {
  'value': value,
  'unit': unit,
};

/// Recette complète dans la forme qu'écrit l'application.
Map<String, Object?> _complete() => {
  'name': 'Blonde & <essai>',
  'type': 'all grain',
  'author': 'Brasseur Fictif',
  'notes': 'Ligne 1\nLigne 2',
  'batch_size': _m(20.0, 'l'),
  'boil': {'boil_time': _m(60, 'min')},
  'mash': {
    'name': kNomEmpatage,
    'grain_temperature': _m(18.0, 'C'),
    'mash_steps': [
      {
        'name': 'Palier 66',
        'type': 'infusion',
        'step_temperature': _m(66.0, 'C'),
        'step_time': _m(60, 'min'),
      },
    ],
  },
  'ingredients': {
    'fermentable_additions': [
      {
        'name': 'Pils',
        'type': 'grain',
        'amount': _m(4500.0, 'g'),
        'color': _m(3.5, 'EBC'),
        'yield': {'fine_grind': _m(80.0, '%')},
      },
      {
        'name': 'Miel',
        'type': 'honey',
        'amount': _m(500.0, 'g'),
        'color': _m(2.0, 'EBC'),
        'yield': {'fine_grind': _m(100.0, '%')},
      },
    ],
    'hop_additions': [
      {
        'name': 'Magnum',
        'form': 'pellet',
        'alpha_acid': _m(12.0, '%'),
        'amount': _m(22.4, 'g'),
        'timing': {'use': 'add_to_boil', 'time': _m(60, 'min')},
      },
      {
        'name': 'Saaz',
        'form': 'leaf',
        'alpha_acid': _m(3.5, '%'),
        'amount': _m(30.0, 'g'),
        'timing': {
          'use': 'add_to_boil',
          'time': _m(0, 'min'),
          'duration': _m(15, 'min'),
        },
      },
      {
        'name': 'Citra',
        'form': 'powder',
        'alpha_acid': _m(12.0, '%'),
        'amount': _m(50.0, 'g'),
        'timing': {
          'use': 'add_to_fermentation',
          'time': _m(4320, 'min'),
          'duration': _m(4320, 'min'),
        },
      },
    ],
    'miscellaneous_additions': [
      {
        'name': 'Coriandre',
        'type': 'spice',
        'amount': _m(10.0, 'g'),
        'timing': {'use': 'add_to_boil', 'time': _m(5, 'min')},
      },
      {
        'name': 'Acide lactique',
        'type': 'water agent',
        'amount': _m(0.005, 'l'),
        'timing': {'use': 'add_to_mash', 'duration': _m(60, 'min')},
      },
    ],
    'culture_additions': [
      {
        'name': 'S-04',
        'type': 'ale',
        'form': 'dry',
        'attenuation': _m(75.0, '%'),
        'amount': _m(11.5, 'g'),
      },
    ],
  },
};

const _style = StyleBeerXml(
  nom: 'Blonde Ale',
  categorie: 'Pale American Ale',
  numeroCategorie: '18',
  lettre: 'A',
  guide: 'BJCP 2021',
  type: 'Ale',
  ogMin: 1.038,
  ogMax: 1.054,
  fgMin: 1.008,
  fgMax: 1.013,
  ibuMin: 15,
  ibuMax: 28,
  ebcMin: 5.91,
  ebcMax: 11.82,
);

RecipeCalculation _calcul() => computeRecipe(
  recipe: RecipeInput(
    fermentables: [
      FermentableInput(
        name: 'Pils',
        kind: FermentableKind.malt,
        massGrams: 4500,
        colorEbc: 3.5,
        yieldPercent: 80,
      ),
    ],
    hops: [
      HopInput(
        name: 'Magnum',
        massGrams: 22.4,
        use: HopUse.boil,
        form: HopForm.pellet,
        alphaPercent: 12,
        minutes: 60,
      ),
    ],
    yeasts: [YeastInput(name: 'S-04', attenuationPercent: 75)],
    batchVolumeLitres: 20,
    boilMinutes: 60,
  ),
  mashEfficiencyPercent: _rendement,
);

String _manque(ManqueExport m) => switch (m) {
  ManqueDeCalcul(:final manque) => 'calcul:${manque.kind.name}',
  ManqueDeFormat(:final champ, :final noms) =>
    noms.isEmpty ? champ.name : '${champ.name}(${noms.join(', ')})',
};

String _perte(PerteExport p) => switch (p) {
  ValeurEcriteAutrement(
    :final ligne,
    :final liste,
    :final champ,
    :final source,
    :final ecrite,
  ) =>
    'ValeurEcriteAutrement($ligne, ${liste.name}, ${champ.name}, $source, $ecrite)',
  VolumeInfusionNonExporte(:final paliers) =>
    'VolumeInfusionNonExporte(${paliers.join(', ')})',
  JourAjoutNonExporte(:final lignes) =>
    'JourAjoutNonExporte(${lignes.join(', ')})',
  DureeApresArretNonExportee(:final lignes) =>
    'DureeApresArretNonExportee(${lignes.join(', ')})',
  EmpatageNonExporte() => 'EmpatageNonExporte',
  ChronologieNonExportee() => 'ChronologieNonExportee',
  _ => p.runtimeType.toString(),
};

void main() {
  group('A1 : aller-retour des fixtures BeerXML', () {
    for (final nom in _fixtures) {
      test(nom, () {
        final octets = File('test/fixtures/lecture/$nom.xml').readAsBytesSync();
        final lu = analyserFichier(octets) as FichierLu;
        final sources = _recettes(_arbre(octets));
        final exports = <String>[];
        for (final (i, r) in lu.recettes.indexed) {
          final resultat = r.resultat;
          if (resultat is! RecetteLue || r.enDouble) continue;
          final source = sources[i];
          final export =
              _exporter(resultat.recipe, style: _styleDe(source)) as ExportPret;
          exports.add(export.contenu);
          // Relecture : la même recette, aux tolérances près.
          final relu =
              analyserFichier(utf8.encode(export.contenu)) as FichierLu;
          final recipeRelu =
              (relu.recettes.single.resultat as RecetteLue).recipe;
          expect(_ecarts(recipeRelu, resultat.recipe), isEmpty, reason: nom);
          // L'écart entre la source et l'export : les pertes annoncées.
          final exportee = _recettes(
            _arbre(utf8.encode(export.contenu)),
          ).single;
          expect(
            _pertesSource(source, exportee),
            _pertesCompteRendu(resultat.modifications),
            reason: nom,
          );
          // BOIL_SIZE calculé par brewing/.
          final batch = (resultat.recipe['batch_size']! as Map)['value'] as num;
          final boil =
              (((resultat.recipe['boil']! as Map)['boil_time']) as Map)['value']
                  as num;
          expect(
            double.parse(_t(exportee, 'BOIL_SIZE')!),
            closeTo(
              preBoilVolumeLitres(
                batchLitres: batch.toDouble(),
                boilMinutes: boil.toDouble(),
                boilOffLitresPerHour: _evaporation,
                trubLossLitres: _trub,
                kettleDeadSpaceLitres: _volumeMort,
              ),
              1e-4,
            ),
          );
          expect(_t(exportee, 'EFFICIENCY'), '72');
        }
        expect(exports, isNotEmpty);
        _expectTexte('export/$nom.xml', exports.join('\n'));
      });
    }
  });

  group('export', () {
    test('fichier complet : champs, valeurs calculées, pertes listées', () {
      final r =
          _exporter(
                _complete(),
                style: _style,
                calcul: _calcul(),
                chronologie: true,
              )
              as ExportPret;
      _expectTexte('export/blonde-essai.xml', r.contenu);
      expect(r.auteur, 'Brasseur Fictif');
      expect(
        [for (final p in r.pertes) _perte(p)],
        [
          'ValeurEcriteAutrement(Saaz, houblons, moment, whirlpool, Aroma)',
          'ValeurEcriteAutrement(Citra, houblons, forme, powder, Pellet)',
          'JourAjoutNonExporte(Citra)',
          'ValeurEcriteAutrement(Miel, malts, type, honey, Sugar)',
          'VolumeInfusionNonExporte(Palier 66)',
          'ChronologieNonExportee',
        ],
      );
      for (final interdit in [
        'price',
        'PRICE',
        'INVENTORY',
        'owner_uid',
        'equipment_id',
      ]) {
        expect(r.contenu.contains(interdit), isFalse, reason: interdit);
      }
      expect(r.contenu, contains('<NAME>Blonde &amp; &lt;essai&gt;</NAME>'));
      expect(r.contenu, contains('<EST_OG>'));
      expect(r.contenu, contains('<IBU_METHOD>Tinseth</IBU_METHOD>'));
    });

    test('relu : texte échappé, notes sur deux lignes, litres gardés', () {
      final r = _exporter(_complete(), style: _style) as ExportPret;
      final relu = analyserFichier(utf8.encode(r.contenu)) as FichierLu;
      final recipe = (relu.recettes.single.resultat as RecetteLue).recipe;
      expect(recipe['name'], 'Blonde & <essai>');
      expect(recipe['notes'], 'Ligne 1\nLigne 2');
      final miscs =
          (recipe['ingredients']! as Map)['miscellaneous_additions']! as List;
      expect((miscs[1] as Map)['amount'], {'value': 0.005, 'unit': 'l'});
    });

    test('E7 : deux exports de la même recette donnent le même texte', () {
      final a = _exporter(_complete(), style: _style, calcul: _calcul());
      final b = _exporter(_complete(), style: _style, calcul: _calcul());
      expect((a as ExportPret).contenu, (b as ExportPret).contenu);
    });

    test('sans style BJCP : bloqué (décision 2), aucune valeur inventée', () {
      final r = _exporter(_complete()) as ExportBloque;
      expect([for (final m in r.manques) _manque(m)], ['style']);
    });

    test('sans volumes d\'équipement ni durée d\'ébullition : bloqué', () {
      final recipe = _complete()..remove('boil');
      final r =
          _exporter(
                recipe,
                style: _style,
                evaporation: null,
                trub: null,
                volumeMort: null,
                rendement: null,
              )
              as ExportBloque;
      expect(
        [for (final m in r.manques) _manque(m)],
        [
          'calcul:mashEfficiency',
          'dureeEbullition',
          'evaporation',
          'pertesAuTrub',
          'volumeMort',
        ],
      );
    });

    test(
      'houblon en volume, ajout sans moment, durées absentes, type cidre : bloqué',
      () {
        final recipe = _complete()..['type'] = 'cider';
        final ingredients = recipe['ingredients']! as Map<String, Object?>;
        final hops = ingredients['hop_additions']! as List<Object?>;
        (hops[0]! as Map)['amount'] = _m(0.01, 'l');
        (hops[2]! as Map)['timing'] = {'use': 'add_to_fermentation'};
        final miscs = ingredients['miscellaneous_additions']! as List<Object?>;
        (miscs[0]! as Map).remove('timing');
        (miscs[1]! as Map)['timing'] = {'use': 'add_to_mash'};
        final r = _exporter(recipe, style: _style) as ExportBloque;
        expect(
          [for (final m in r.manques) _manque(m)],
          [
            'typeRecetteBeerXml(cider)',
            'houblonEnVolume(Magnum)',
            'momentAjout(Coriandre)',
            'dureeAjout(Citra, Acide lactique)',
          ],
        );
      },
    );

    test('houblon sans forme (recette publique, D8) : bloqué, sans erreur', () {
      final recipe = _complete();
      final ingredients = recipe['ingredients']! as Map<String, Object?>;
      final hops = ingredients['hop_additions']! as List<Object?>;
      for (final h in hops) {
        (h! as Map).remove('form');
      }
      final noms = [for (final h in hops) '${(h! as Map)['name']}'];
      final r = _exporter(recipe, style: _style) as ExportBloque;
      expect(
        [for (final m in r.manques) _manque(m)],
        ['formeHoublon(${noms.join(', ')})'],
      );
    });

    test('ce qui manque au BeerJSON manque aussi au BeerXML', () {
      final recipe = _complete()..remove('type');
      final ingredients = recipe['ingredients']! as Map<String, Object?>;
      ((ingredients['culture_additions']! as List).single as Map).remove(
        'amount',
      );
      final r = _exporter(recipe, style: _style) as ExportBloque;
      expect(
        [for (final m in r.manques) _manque(m)],
        ['typeRecette', 'quantiteLevure(S-04)'],
      );
    });

    test('recette à l\'extrait sans empâtage : MASH omis, perte listée', () {
      final recipe = _complete()
        ..remove('mash')
        ..['type'] = 'extract';
      final r = _exporter(recipe, style: _style) as ExportPret;
      expect(r.contenu.contains('<MASH>'), isFalse);
      expect([
        for (final p in r.pertes) _perte(p),
      ], contains('EmpatageNonExporte'));
    });

    test('auteur : recipe.author, sinon owner_name, sinon bloqué', () {
      final sansAuteur = _complete()..remove('author');
      final r =
          _exporter(sansAuteur, style: _style, ownerName: 'Membre Fictif')
              as ExportPret;
      expect(r.contenu, contains('<BREWER>Membre Fictif</BREWER>'));
      final bloque = _exporter(sansAuteur, style: _style) as ExportBloque;
      expect([for (final m in bloque.manques) _manque(m)], ['auteur']);
    });

    test('nom du fichier : extension xml', () {
      expect(nomFichierExport('IPA maison', 'xml'), 'ipa-maison.xml');
    });
  });

  group('style de la Bibliothèque (E4)', () {
    const fiche = StyleBibliotheque(
      nom: 'Blonde Ale',
      categorie: 'Pale American Ale',
      numeroCategorie: '18',
      code: '18A',
      guide: 'BJCP2021',
      type: 'beer',
      ogMin: 1.038,
      ogMax: 1.054,
      fgMin: 1.008,
      fgMax: 1.013,
      ibuMin: 15,
      ibuMax: 28,
      ebcMin: 5.91,
      ebcMax: 11.82,
      abvMin: 3.8,
      abvMax: 5.5,
    );

    Map<String, Object?> avecLevures(List<String?> types) {
      final recipe = _complete();
      final ingredients = recipe['ingredients']! as Map<String, Object?>;
      ingredients['culture_additions'] = [
        for (final (i, t) in types.indexed)
          {
            'name': 'Levure $i',
            'type': ?t,
            'form': 'dry',
            'attenuation': _m(75.0, '%'),
            'amount': _m(11.5, 'g'),
          },
      ];
      return recipe;
    }

    test('lettre tirée du code, type Ale lu dans la levure, export prêt', () {
      final recipe = _complete();
      final s = styleBeerXmlDe(fiche, recipe);
      expect(s.manques, isEmpty);
      final style = s.style!;
      expect(style.numeroCategorie, '18');
      expect(style.lettre, 'A');
      expect(style.type, 'Ale');
      expect(style.guide, 'BJCP2021');
      final r = _exporter(recipe, style: style) as ExportPret;
      expect(r.contenu, contains('<STYLE_LETTER>A</STYLE_LETTER>'));
      expect(r.contenu, contains('<TYPE>Ale</TYPE>'));
      expect(r.contenu, contains('<ABV_MAX>5.5</ABV_MAX>'));
    });

    test('catégorie X : X1 donne la lettre 1', () {
      const x = StyleBibliotheque(
        nom: 'Dorada Pampeana',
        categorie: 'Argentine Styles',
        numeroCategorie: 'X',
        code: 'X1',
        guide: 'BJCP2021',
        type: 'beer',
        ogMin: 1.042,
        ogMax: 1.054,
        fgMin: 1.009,
        fgMax: 1.013,
        ibuMin: 15,
        ibuMax: 22,
        ebcMin: 5.9,
        ebcMax: 9.9,
      );
      expect(styleBeerXmlDe(x, _complete()).style!.lettre, '1');
    });

    test('type selon les levures : Lager, Wheat, Mixed', () {
      String? type(List<String?> t) =>
          styleBeerXmlDe(fiche, avecLevures(t)).style?.type;
      expect(type(['lager']), 'Lager');
      expect(type(['wheat']), 'Wheat');
      expect(type(['kveik', 'ale']), 'Ale');
      expect(type(['ale', 'lager']), 'Mixed');
      expect(type(['ale', 'brett']), 'Mixed');
      expect(type(['lacto']), 'Mixed');
    });

    test('type indéterminé : sans levure typée, levure de vin, autre type', () {
      List<String> manques(
        Map<String, Object?> recipe, [
        StyleBibliotheque? s,
      ]) => [
        for (final m in styleBeerXmlDe(s ?? fiche, recipe).manques) _manque(m),
      ];
      expect(manques(avecLevures([])), ['typeStyle']);
      expect(manques(avecLevures([null])), ['typeStyle(Levure 0)']);
      expect(manques(avecLevures(['ale', 'wine'])), ['typeStyle(Levure 1)']);
      const kombucha = StyleBibliotheque(
        nom: 'Kombucha Fictif',
        type: 'kombucha',
      );
      expect(manques(_complete(), kombucha), ['ficheStyle(Kombucha Fictif)']);
    });

    test('hydromel et cidre : type du style, sans lire la levure', () {
      const mead = StyleBibliotheque(nom: 'Hydromel Fictif', type: 'mead');
      const cider = StyleBibliotheque(nom: 'Cidre Fictif', type: 'cider');
      List<String> manques(StyleBibliotheque s) => [
        for (final m in styleBeerXmlDe(s, avecLevures([])).manques) _manque(m),
      ];
      expect(manques(mead), ['ficheStyle(Hydromel Fictif)']);
      expect(manques(cider), ['ficheStyle(Cidre Fictif)']);
    });

    test('style sans plages (28A dans la Bibliothèque) : export bloqué', () {
      const sansPlages = StyleBibliotheque(
        nom: 'Brett Beer',
        categorie: 'American Wild Ale',
        numeroCategorie: '28',
        code: '28A',
        guide: 'BJCP2021',
        type: 'beer',
      );
      final s = styleBeerXmlDe(sansPlages, _complete());
      expect(s.style, isNull);
      final r =
          exporterBeerXml(
                recipe: _complete(),
                ownerName: null,
                rendementEmpatage: _rendement,
                evaporationLParH: _evaporation,
                pertesAuTrubL: _trub,
                volumeMortL: _volumeMort,
                style: s.style,
                manquesStyle: s.manques,
                calcul: null,
                chronologie: false,
              )
              as ExportBloque;
      expect(
        [for (final m in r.manques) _manque(m)],
        ['ficheStyle(Brett Beer)'],
      );
    });
  });

  test('fins de ligne CRLF et LF : même empreinte, même recette', () {
    final lf = File(
      'test/fixtures/lecture/beerxml-brewfather.xml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final crlf = lf.replaceAll('\n', '\r\n');
    final a = analyserFichier(utf8.encode(lf)) as FichierLu;
    final b = analyserFichier(utf8.encode(crlf)) as FichierLu;
    expect(a.recettes.single.empreinte, b.recettes.single.empreinte);
    expect(
      (a.recettes.single.resultat as RecetteLue).recipe,
      (b.recettes.single.resultat as RecetteLue).recipe,
    );
  });

  test('nom affiché d\'une recette XML : nettoyé', () {
    final arbre = _arbre(
      utf8.encode(
        '<RECIPE><NAME>  Rousse ${String.fromCharCode(0x200E)}</NAME></RECIPE>',
      ),
    );
    expect(nomAfficheXml(arbre), 'Rousse');
  });
}
