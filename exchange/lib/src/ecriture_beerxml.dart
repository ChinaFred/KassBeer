import 'package:brewing/brewing.dart';

import 'compte_rendu.dart' show Champ, ListeRecette;
import 'ecriture_beerjson.dart';
import 'lecture_beerjson.dart' show kNomEmpatage;

/// Export BeerXML 1.0 d'une recette (ADR-005, L2c) : le sous-arbre `recipe`
/// stocké, l'auteur, le rendement d'empâtage de l'équipement (`EFFICIENCY`), le
/// volume avant ébullition calculé par `brewing/` (`BOIL_SIZE`), le style BJCP
/// complet et les valeurs calculées par `computeRecipe`. Les couleurs passent
/// en Lovibond ou en SRM par `brewing/` (P3) ; les masses en kilogrammes. Aucun
/// prix, stock, coût, e-mail, `owner_uid`, `equipment_id` ni nom d'équipement.
///
/// L'application garde l'export BeerXML bloqué tant que le référentiel des
/// styles (`beer_styles`, L3) manque : sans [StyleBeerXml], l'export est
/// bloqué (ADR-005, amendements de L2 ; aucune valeur de style inventée).

/// Style de la liste BJCP, champs obligatoires du `STYLE` de BeerXML. Il vient
/// du référentiel des styles, jamais d'une valeur par défaut.
class StyleBeerXml {
  /// Crée le style.
  const StyleBeerXml({
    required this.nom,
    required this.categorie,
    required this.numeroCategorie,
    required this.lettre,
    required this.guide,
    required this.type,
    required this.ogMin,
    required this.ogMax,
    required this.fgMin,
    required this.fgMax,
    required this.ibuMin,
    required this.ibuMax,
    required this.ebcMin,
    required this.ebcMax,
    this.abvMin,
    this.abvMax,
  });

  /// Nom du style (`NAME`).
  final String nom;

  /// Catégorie (`CATEGORY`).
  final String categorie;

  /// Numéro de catégorie (`CATEGORY_NUMBER`).
  final String numeroCategorie;

  /// Lettre du style dans sa catégorie (`STYLE_LETTER`).
  final String lettre;

  /// Guide (`STYLE_GUIDE`), par exemple « BJCP 2021 ».
  final String guide;

  /// Type BeerXML (`TYPE`) : `Lager`, `Ale`, `Mead`, `Wheat`, `Mixed` ou
  /// `Cider`.
  final String type;

  /// Densité initiale, SG décimal.
  final double ogMin, ogMax;

  /// Densité finale, SG décimal.
  final double fgMin, fgMax;

  /// Amertume, IBU.
  final double ibuMin, ibuMax;

  /// Couleur, EBC : écrite en SRM.
  final double ebcMin, ebcMax;

  /// Degré d'alcool, % du volume, facultatif.
  final double? abvMin, abvMax;
}

/// Exporte [recipe] (sous-arbre `recipe` en BeerJSON partiel) en BeerXML 1.0.
///
/// Auteur et rendement comme [exporterBeerJson]. `BOIL_SIZE` vaut
/// [preBoilVolumeLitres] de `brewing/`, calculé avec le volume en fermenteur,
/// la durée d'ébullition et [evaporationLParH], [pertesAuTrubL] et
/// [volumeMortL] de l'équipement de la recette ; sans l'une de ces valeurs,
/// l'export est bloqué. [style] : style BJCP résolu, sinon l'export est
/// bloqué. Lève [BrewingInputException] pour une valeur d'équipement négative.
ResultatExport exporterBeerXml({
  required Map<String, Object?> recipe,
  required String? ownerName,
  required double? rendementEmpatage,
  required double? evaporationLParH,
  required double? pertesAuTrubL,
  required double? volumeMortL,
  required StyleBeerXml? style,
  required RecipeCalculation? calcul,
  required bool chronologie,
}) {
  final author = texteExport(recipe['author']) ?? texteExport(ownerName);
  final manques = manquesExportBeerXml(
    recipe: recipe,
    auteur: author,
    rendementEmpatage: rendementEmpatage,
    evaporationLParH: evaporationLParH,
    pertesAuTrubL: pertesAuTrubL,
    volumeMortL: volumeMortL,
    style: style,
  );
  if (manques.isNotEmpty) return ExportBloque(List.unmodifiable(manques));
  // Non nuls : sans eux, l'export est bloqué plus haut.
  final batch = (mapExport(recipe['batch_size'])['value']! as num).toDouble();
  final boil =
      (mapExport(mapExport(recipe['boil'])['boil_time'])['value']! as num)
          .toInt();
  final boilSize = preBoilVolumeLitres(
    batchLitres: batch,
    boilMinutes: boil.toDouble(),
    boilOffLitresPerHour: evaporationLParH!,
    trubLossLitres: pertesAuTrubL!,
    kettleDeadSpaceLitres: volumeMortL!,
  );
  final pertes = <PerteExport>[];
  final ingredients = mapExport(recipe['ingredients']);
  final x = _Xml()..ouvrir('RECIPES');
  x
    ..ouvrir('RECIPE')
    ..champ('NAME', '${recipe['name']}')
    ..champ('VERSION', '1')
    ..champ('TYPE', _typesRecette[recipe['type']]!);
  _style(x, style!);
  x
    ..champ('BREWER', author!)
    ..champ('BATCH_SIZE', _n(batch, 4))
    ..champ('BOIL_SIZE', _n(boilSize, 4))
    ..champ('BOIL_TIME', '$boil')
    ..champ('EFFICIENCY', _n(rendementEmpatage!, 3));
  _houblons(x, mapsExport(ingredients['hop_additions']), pertes);
  _malts(x, mapsExport(ingredients['fermentable_additions']), pertes);
  _ajouts(x, mapsExport(ingredients['miscellaneous_additions']), pertes);
  _levures(x, mapsExport(ingredients['culture_additions']), pertes);
  x.vide('WATERS');
  _empatage(x, mapExport(recipe['mash']), pertes);
  final notes = texteExport(recipe['notes']);
  if (notes != null) x.champ('NOTES', notes);
  if (calcul != null) _estimations(x, calcul);
  x
    ..fermer('RECIPE')
    ..fermer('RECIPES');
  if (chronologie) pertes.add(const ChronologieNonExportee());
  return ExportPret(x.texte, List.unmodifiable(pertes), author);
}

/// Ce qui manque à [recipe] pour un export BeerXML : ce qui manque au
/// BeerJSON, puis le style, la durée d'ébullition et les volumes de
/// l'équipement (`BOIL_SIZE`), le moment et la durée des ajouts (`USE` et
/// `TIME` sont obligatoires), un houblon mesuré en volume et un type de
/// recette sans équivalent. Vide si l'export est possible.
List<ManqueExport> manquesExportBeerXml({
  required Map<String, Object?> recipe,
  required String? auteur,
  required double? rendementEmpatage,
  required double? evaporationLParH,
  required double? pertesAuTrubL,
  required double? volumeMortL,
  required StyleBeerXml? style,
}) {
  final manques = manquesExportBeerJson(
    recipe: recipe,
    auteur: auteur,
    rendementEmpatage: rendementEmpatage,
  );
  void format(ChampExport champ, [List<String> noms = const []]) =>
      manques.add(ManqueDeFormat(champ, List.unmodifiable(noms)));

  final type = recipe['type'];
  if (type != null && !_typesRecette.containsKey(type)) {
    format(ChampExport.typeRecetteBeerXml, ['$type']);
  }
  if (style == null) format(ChampExport.style);
  if (mapExport(recipe['boil'])['boil_time'] == null) {
    format(ChampExport.dureeEbullition);
  }
  if (evaporationLParH == null) format(ChampExport.evaporation);
  if (pertesAuTrubL == null) format(ChampExport.pertesAuTrub);
  if (volumeMortL == null) format(ChampExport.volumeMort);
  final ingredients = mapExport(recipe['ingredients']);
  final hops = mapsExport(ingredients['hop_additions']);
  final miscs = mapsExport(ingredients['miscellaneous_additions']);
  final enVolume = [
    for (final h in hops)
      if (mapExport(h['amount'])['unit'] == 'l') '${h['name']}',
  ];
  if (enVolume.isNotEmpty) format(ChampExport.houblonEnVolume, enVolume);
  final sansMoment = [
    for (final o in miscs)
      if (mapExport(o['timing'])['use'] == null) '${o['name']}',
  ];
  if (sansMoment.isNotEmpty) format(ChampExport.momentAjout, sansMoment);
  final sansDuree = [
    for (final l in [...hops, ...miscs])
      if (mapExport(l['timing'])['use'] != null &&
          _minutes(mapExport(l['timing'])) == null)
        '${l['name']}',
  ];
  if (sansDuree.isNotEmpty) format(ChampExport.dureeAjout, sansDuree);
  return manques;
}

const Map<Object?, String> _typesRecette = {
  'all grain': 'All Grain',
  'partial mash': 'Partial Mash',
  'extract': 'Extract',
};

/// Minutes de `TIME` d'un ajout : à l'ébullition, `time` (sinon `duration`
/// d'un whirlpool, voir [_houblons]) ; hors ébullition, `duration`.
int? _minutes(Map<String, Object?> timing) {
  int? v(String cle) => (mapExport(timing[cle])['value'] as num?)?.toInt();
  return timing['use'] == 'add_to_boil' ? v('time') : v('duration');
}

void _style(_Xml x, StyleBeerXml s) {
  x
    ..ouvrir('STYLE')
    ..champ('NAME', s.nom)
    ..champ('VERSION', '1')
    ..champ('CATEGORY', s.categorie)
    ..champ('CATEGORY_NUMBER', s.numeroCategorie)
    ..champ('STYLE_LETTER', s.lettre)
    ..champ('STYLE_GUIDE', s.guide)
    ..champ('TYPE', s.type)
    ..champ('OG_MIN', _n(s.ogMin, 4))
    ..champ('OG_MAX', _n(s.ogMax, 4))
    ..champ('FG_MIN', _n(s.fgMin, 4))
    ..champ('FG_MAX', _n(s.fgMax, 4))
    ..champ('IBU_MIN', _n(s.ibuMin, 1))
    ..champ('IBU_MAX', _n(s.ibuMax, 1))
    ..champ('COLOR_MIN', _n(ebcToSrm(s.ebcMin), 2))
    ..champ('COLOR_MAX', _n(ebcToSrm(s.ebcMax), 2));
  final abvMin = s.abvMin;
  final abvMax = s.abvMax;
  if (abvMin != null) x.champ('ABV_MIN', _n(abvMin, 2));
  if (abvMax != null) x.champ('ABV_MAX', _n(abvMax, 2));
  x.fermer('STYLE');
}

const Map<String, String> _formesHoublon = {
  'pellet': 'Pellet',
  'leaf': 'Leaf',
  'plug': 'Plug',
  'leaf (wet)': 'Leaf',
  'powder': 'Pellet',
  'extract': 'Pellet',
};

void _houblons(_Xml x, List<Map<String, Object?>> hops, List<PerteExport> p) {
  final jours = <String>[];
  x.ouvrir('HOPS');
  for (final h in hops) {
    final nom = '${h['name']}';
    final timing = mapExport(h['timing']);
    final use = timing['use'];
    final time = (mapExport(timing['time'])['value'] as num?)?.toInt();
    final duration = (mapExport(timing['duration'])['value'] as num?)?.toInt();
    final String usage;
    final int minutes;
    switch (use) {
      case 'add_to_boil' when time == 0 && duration != null && duration > 0:
        // Whirlpool : BeerXML 1.0 n'a pas ce moment.
        usage = 'Aroma';
        minutes = duration;
        p.add(
          ValeurEcriteAutrement(
            nom,
            ListeRecette.houblons,
            Champ.moment,
            'whirlpool',
            usage,
          ),
        );
      case 'add_to_boil':
        usage = 'Boil';
        minutes = time!;
      case 'add_to_fermentation':
        usage = 'Dry Hop';
        minutes = duration!;
        if (time != null) jours.add(nom);
      case 'add_to_mash':
        usage = 'Mash';
        minutes = duration!;
      default:
        usage = 'Dry Hop';
        minutes = duration!;
        p.add(
          ValeurEcriteAutrement(
            nom,
            ListeRecette.houblons,
            Champ.moment,
            '$use',
            usage,
          ),
        );
    }
    final form = '${h['form']}';
    final forme = _formesHoublon[form]!;
    if (forme.toLowerCase() != form) {
      p.add(
        ValeurEcriteAutrement(
          nom,
          ListeRecette.houblons,
          Champ.forme,
          form,
          forme,
        ),
      );
    }
    x
      ..ouvrir('HOP')
      ..champ('NAME', nom)
      ..champ('VERSION', '1')
      ..champ('ALPHA', _n(_valeur(h['alpha_acid']), 3))
      ..champ('AMOUNT', _n(_valeur(h['amount']) / 1000, 7))
      ..champ('USE', usage)
      ..champ('TIME', '$minutes')
      ..champ('FORM', forme)
      ..fermer('HOP');
  }
  x.fermer('HOPS');
  if (jours.isNotEmpty) p.add(JourAjoutNonExporte(List.unmodifiable(jours)));
}

const Map<String, String> _typesMalt = {
  'grain': 'Grain',
  'sugar': 'Sugar',
  'extract': 'Extract',
  'dry extract': 'Dry Extract',
  'honey': 'Sugar',
  'fruit': 'Sugar',
  'juice': 'Sugar',
  'other': 'Adjunct',
};

void _malts(_Xml x, List<Map<String, Object?>> malts, List<PerteExport> p) {
  x.ouvrir('FERMENTABLES');
  for (final f in malts) {
    final nom = '${f['name']}';
    final type = '${f['type']}';
    final ecrit = _typesMalt[type]!;
    if (ecrit.toLowerCase() != type) {
      p.add(
        ValeurEcriteAutrement(nom, ListeRecette.malts, Champ.type, type, ecrit),
      );
    }
    final ebc = _valeur(f['color']);
    // Lovibond, et SRM pour un extrait liquide, comme le dit la norme.
    final couleur = type == 'extract' ? ebcToSrm(ebc) : ebcToLovibond(ebc);
    x
      ..ouvrir('FERMENTABLE')
      ..champ('NAME', nom)
      ..champ('VERSION', '1')
      ..champ('TYPE', ecrit)
      ..champ('AMOUNT', _n(_valeur(f['amount']) / 1000, 7))
      ..champ('YIELD', _n(_valeur(mapExport(f['yield'])['fine_grind']), 3))
      ..champ('COLOR', _n(couleur, 4))
      ..fermer('FERMENTABLE');
  }
  x.fermer('FERMENTABLES');
}

const Map<String, String> _typesAjout = {
  'spice': 'Spice',
  'fining': 'Fining',
  'water agent': 'Water Agent',
  'herb': 'Herb',
  'flavor': 'Flavor',
  'other': 'Other',
  'wood': 'Other',
};

const Map<String, String> _usagesAjout = {
  'add_to_boil': 'Boil',
  'add_to_mash': 'Mash',
  'add_to_fermentation': 'Primary',
  'add_to_package': 'Bottling',
};

void _ajouts(_Xml x, List<Map<String, Object?>> miscs, List<PerteExport> p) {
  final apresArret = <String>[];
  x.ouvrir('MISCS');
  for (final o in miscs) {
    final nom = '${o['name']}';
    final type = '${o['type']}';
    final ecrit = _typesAjout[type]!;
    if (ecrit.toLowerCase() != type) {
      p.add(
        ValeurEcriteAutrement(
          nom,
          ListeRecette.ajouts,
          Champ.type,
          type,
          ecrit,
        ),
      );
    }
    final timing = mapExport(o['timing']);
    if (timing['use'] == 'add_to_boil' && timing['duration'] != null) {
      apresArret.add(nom);
    }
    final amount = mapExport(o['amount']);
    final poids = amount['unit'] == 'g';
    final valeur = (amount['value']! as num).toDouble();
    x
      ..ouvrir('MISC')
      ..champ('NAME', nom)
      ..champ('VERSION', '1')
      ..champ('TYPE', ecrit)
      ..champ('USE', _usagesAjout[timing['use']]!)
      ..champ('TIME', '${_minutes(timing)!}')
      ..champ('AMOUNT', _n(poids ? valeur / 1000 : valeur, 7))
      ..champ('AMOUNT_IS_WEIGHT', poids ? 'TRUE' : 'FALSE')
      ..fermer('MISC');
  }
  x.fermer('MISCS');
  if (apresArret.isNotEmpty) {
    p.add(DureeApresArretNonExportee(List.unmodifiable(apresArret)));
  }
}

const Map<String, String> _typesLevure = {
  'ale': 'Ale',
  'lager': 'Lager',
  'wheat': 'Wheat',
  'wine': 'Wine',
  'champagne': 'Champagne',
};

const Map<String, String> _formesLevure = {
  'liquid': 'Liquid',
  'dry': 'Dry',
  'slant': 'Slant',
  'culture': 'Culture',
  'dregs': 'Culture',
};

void _levures(_Xml x, List<Map<String, Object?>> levures, List<PerteExport> p) {
  x.ouvrir('YEASTS');
  for (final y in levures) {
    final nom = '${y['name']}';
    final type = '${y['type']}';
    // Bactéries, kveik, brett… : BeerXML 1.0 ne connaît que cinq types.
    final typeEcrit = _typesLevure[type] ?? 'Ale';
    if (typeEcrit.toLowerCase() != type) {
      p.add(
        ValeurEcriteAutrement(
          nom,
          ListeRecette.levures,
          Champ.type,
          type,
          typeEcrit,
        ),
      );
    }
    final form = '${y['form']}';
    final formeEcrite = _formesLevure[form]!;
    if (formeEcrite.toLowerCase() != form) {
      p.add(
        ValeurEcriteAutrement(
          nom,
          ListeRecette.levures,
          Champ.forme,
          form,
          formeEcrite,
        ),
      );
    }
    final amount = mapExport(y['amount']);
    final poids = amount['unit'] == 'g';
    final valeur = (amount['value']! as num).toDouble();
    final attenuation = y['attenuation'];
    x
      ..ouvrir('YEAST')
      ..champ('NAME', nom)
      ..champ('VERSION', '1')
      ..champ('TYPE', typeEcrit)
      ..champ('FORM', formeEcrite)
      ..champ('AMOUNT', _n(poids ? valeur / 1000 : valeur, 7))
      ..champ('AMOUNT_IS_WEIGHT', poids ? 'TRUE' : 'FALSE');
    if (attenuation != null) {
      x.champ('ATTENUATION', _n(_valeur(attenuation), 3));
    }
    x.fermer('YEAST');
  }
  x.fermer('YEASTS');
}

const Map<String, String> _typesPalier = {
  'infusion': 'Infusion',
  'temperature': 'Temperature',
  'decoction': 'Decoction',
};

void _empatage(_Xml x, Map<String, Object?> mash, List<PerteExport> p) {
  final steps = mapsExport(mash['mash_steps']);
  final grain = mash['grain_temperature'];
  if (steps.isEmpty && grain == null) {
    // Recette à l'extrait : MASH est omis, comme en BeerJSON.
    p.add(const EmpatageNonExporte());
    return;
  }
  final infusions = <String>[];
  x
    ..ouvrir('MASH')
    ..champ('NAME', texteExport(mash['name']) ?? kNomEmpatage)
    ..champ('VERSION', '1')
    // Non nul : un palier sans température du grain bloque l'export.
    ..champ('GRAIN_TEMP', _n(_valeur(grain), 4))
    ..ouvrir('MASH_STEPS');
  for (final s in steps) {
    final nom = '${s['name']}';
    final type = '${s['type']}';
    // Brassage acide, rinçage… : BeerXML 1.0 ne connaît que trois types.
    final ecrit = _typesPalier[type] ?? 'Temperature';
    if (ecrit.toLowerCase() != type) {
      p.add(
        ValeurEcriteAutrement(
          nom,
          ListeRecette.paliers,
          Champ.type,
          type,
          ecrit,
        ),
      );
    }
    if (ecrit == 'Infusion') infusions.add(nom);
    x
      ..ouvrir('MASH_STEP')
      ..champ('NAME', nom)
      ..champ('VERSION', '1')
      ..champ('TYPE', ecrit)
      ..champ('STEP_TEMP', _n(_valeur(s['step_temperature']), 4))
      ..champ('STEP_TIME', '${_valeur(s['step_time']).toInt()}')
      ..fermer('MASH_STEP');
  }
  x
    ..fermer('MASH_STEPS')
    ..fermer('MASH');
  if (infusions.isNotEmpty) {
    p.add(VolumeInfusionNonExporte(List.unmodifiable(infusions)));
  }
}

/// Valeurs calculées, dans les champs d'affichage de l'annexe de la norme
/// (texte avec son unité) : aucun logiciel ne les relit comme une mesure.
void _estimations(_Xml x, RecipeCalculation c) {
  double? v(CalculationResult r) => switch (r) {
    CalculationComputed(:final value) => value,
    CalculationUnavailable() => null,
  };
  final og = v(c.originalGravity);
  final fg = v(c.finalGravity);
  final ebc = v(c.colorEbc);
  final ibu = v(c.bitternessIbu);
  final abv = v(c.alcoholByVolume);
  if (og != null) x.champ('EST_OG', '${og.toStringAsFixed(3)} SG');
  if (fg != null) x.champ('EST_FG', '${fg.toStringAsFixed(3)} SG');
  if (ebc != null) {
    x.champ('EST_COLOR', '${ebcToSrm(ebc).toStringAsFixed(1)} SRM');
  }
  if (ibu != null) {
    x
      ..champ('IBU', '${ibu.toStringAsFixed(1)} IBUs')
      ..champ('IBU_METHOD', 'Tinseth');
  }
  if (abv != null) x.champ('EST_ABV', '${abv.toStringAsFixed(1)} %');
}

/// Valeur d'un couple `{value, unit}` présent.
double _valeur(Object? couple) =>
    (mapExport(couple)['value']! as num).toDouble();

/// [v] écrit avec [decimales] chiffres au plus après le point, sans zéro
/// final : le même texte sur Android et sur le web (E7).
String _n(double v, int decimales) {
  var texte = v.toStringAsFixed(decimales);
  if (texte.contains('.')) {
    texte = texte.replaceFirst(RegExp(r'0+$'), '');
    if (texte.endsWith('.')) texte = texte.substring(0, texte.length - 1);
  }
  return texte == '-0' ? '0' : texte;
}

/// Écriture XML indentée, en UTF-8 déclaré. Les textes sont échappés ; les
/// caractères que XML 1.0 interdit (contrôles C0 hors tabulation et sauts de
/// ligne, U+FFFE, U+FFFF, demi-paires) sont retirés.
class _Xml {
  final _buffer = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
  var _niveau = 0;

  String get texte => _buffer.toString();

  void ouvrir(String nom) {
    _ligne('<$nom>');
    _niveau++;
  }

  void fermer(String nom) {
    _niveau--;
    _ligne('</$nom>');
  }

  void vide(String nom) => _ligne('<$nom/>');

  void champ(String nom, String valeur) =>
      _ligne('<$nom>${_echapper(valeur)}</$nom>');

  void _ligne(String contenu) {
    _buffer
      ..write('  ' * _niveau)
      ..write(contenu)
      ..write('\n');
  }
}

String _echapper(String texte) {
  final buffer = StringBuffer();
  for (final rune in texte.runes) {
    switch (rune) {
      case 0x26:
        buffer.write('&amp;');
      case 0x3C:
        buffer.write('&lt;');
      case 0x3E:
        buffer.write('&gt;');
      case 0x9 || 0xA || 0xD:
        buffer.writeCharCode(rune);
      case < 0x20 || 0xFFFE || 0xFFFF:
        break;
      case >= 0xD800 && <= 0xDFFF:
        break;
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
