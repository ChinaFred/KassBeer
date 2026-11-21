import 'package:kass_beer/features/library/domain/recette_publique.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';

/// Documents de la Bibliothèque écrits à la main, à la forme de la spécification
/// d'ADR-005 (L3) et des documents de l'ingestion. Aucun fichier de source n'est
/// copié (P20). Les plages de l'« American IPA » sont celles du guide BJCP 2021,
/// que P20 permet en base (nom, code, catégorie, plages chiffrées) ; la recette
/// publique et les ingrédients sont inventés.

Map<String, Object> mesure(num value, String unit) => {
  'value': value,
  'unit': unit,
};

Map<String, Object> plage(num min, num max, String unit) => {
  'minimum': mesure(min, unit),
  'maximum': mesure(max, unit),
};

Map<String, Object> provenance({
  String source = 'brewtarget-003',
  String licence = 'GPL-3.0',
  String version = 'v5.2.3 ea10908',
  String retrieved = '2026-11-08',
}) => {
  'source': source,
  'source_id': 'élément 12',
  'version': version,
  'licence': licence,
  'retrieved': retrieved,
};

/// `beer_index/{nature}`.
Map<String, dynamic> indexDoc(List<Object?> entries) => {
  'count': entries.length,
  'content_sha256': 'cd' * 32,
  'entries': entries,
};

final hopsIndex = indexDoc([
  {
    'id': 'hop-cascade',
    'name': 'Cascade',
    'aliases': ['Cascade US'],
    'form': 'pellet',
    'alpha': 6.5,
    'purpose': 'aroma',
    'origin': 'United States',
    'champ_futur': 'ignoré',
  },
  {
    'id': 'hop-houblon-dore',
    'name': 'Houblon doré',
    'form': 'leaf',
    'alpha': 4,
  },
  // Mal typé : l'entrée est écartée et comptée.
  {'id': 'hop-saaz', 'name': 'Saaz', 'alpha': '3,5'},
]);

/// `beer_index/hop_aromas` : Cascade en confiance faible ; Houblon doré absent
/// (« Sans description »).
Map<String, dynamic> aromesIndex([List<Object?>? entries]) {
  final e =
      entries ??
      [
        {'id': 'hop-cascade', 'confidence': 'low'},
      ];
  return {'count': e.length, 'content_sha256': 'ef' * 32, 'entries': e};
}

final stylesIndex = indexDoc([
  {
    'id': 'bjcp2021-21a',
    'name': 'American IPA',
    'code': '21A',
    'category': 'IPA',
    'og': [1.056, 1.070],
    'fg': [1.008, 1.014],
    'ibu': [40, 70],
    'ebc': [12, 28],
    'abv': [5.5, 7.5],
  },
  {'id': 'bjcp2021-1a', 'name': 'American Light Lager', 'code': '1A'},
]);

/// `beer_styles/bjcp2021-21a`.
Map<String, dynamic> styleDoc() => {
  'name': 'American IPA',
  'category': 'IPA',
  'category_id': '21',
  'style_id': '21A',
  'type': 'beer',
  'style_guide': 'BJCP2021',
  'original_gravity': plage(1.056, 1.070, 'sg'),
  'final_gravity': plage(1.008, 1.014, 'sg'),
  'international_bitterness_units': plage(40, 70, 'IBUs'),
  'color': plage(12, 28, 'EBC'),
  'alcohol_by_volume': plage(5.5, 7.5, '%'),
  'provenance': [
    provenance(source: 'brewtarget-002', licence: 'BJCP (noms et plages)'),
  ],
  'content_sha256': 'ef' * 32,
};

/// `beer_hops/hop-cascade`, issu de la part CC BY-SA 4.0 du fichier 005.
Map<String, dynamic> hopDoc() => {
  'name': 'Cascade',
  'aliases': ['Cascade US'],
  'form': 'pellet',
  'alpha_acid': mesure(6.5, '%'),
  'beta_acid': mesure(5.5, '%'),
  'origin': 'US',
  'purpose': 'aroma',
  'provenance': [provenance(source: 'brewtarget-005', licence: 'CC BY-SA 4.0')],
  'content_sha256': '01' * 32,
};

/// `public_recipes/diydog-{id}` : recette inventée, à la forme des documents
/// de l'ingestion (pas de `type`, pas de `boil`, pas de `style_id` pour DIY
/// Dog). [avecForme] faux : aucun houblon ne porte `form`, comme dans DIY Dog.
/// [styleId] : style résolu, absent par défaut.
Map<String, dynamic> publicRecipeDoc({
  String id = '1',
  String name = 'Blonde du Verger',
  bool avecForme = true,
  String? styleId,
}) => {
  'format_version': 1,
  'owner_uid': 'system',
  'owner_name': 'DIY Dog',
  'imported_from': 'DIY Dog · diydog-$id',
  'search_name': normaliserNomRecherche(name),
  'style_id': ?styleId,
  'ingredient_refs': {
    'malt-pilsner-du-verger': 'fermentable-pilsner-du-verger',
  },
  'source_hop_timing': [
    {'hop_index': 1, 'label': 'middle'},
  ],
  'announced': {
    'original_gravity': mesure(1.052, 'sg'),
    'final_gravity': mesure(1.009, 'sg'),
    'alcohol_by_volume': mesure(5.6, '%'),
    'ibu_estimate': mesure(28, 'IBUs'),
    'color_estimate': mesure(9, 'EBC'),
  },
  'provenance': [
    provenance(
      source: 'diydog',
      licence: 'DIY Dog (usage privé)',
      version: 'e6c12ab',
    ),
  ],
  'content_sha256': '23' * 32,
  'recipe': {
    'name': name,
    'author': 'BrewDog',
    'notes': 'Zeste de citron à la fin de l\'ébullition.',
    'style': {'name': 'Blonde fruitée'},
    'batch_size': mesure(23, 'l'),
    'mash': {
      'name': 'Empâtage',
      'mash_steps': [
        {
          'name': 'Saccharification',
          'type': 'infusion',
          'step_temperature': mesure(66, 'C'),
          'step_time': mesure(60, 'min'),
        },
      ],
    },
    'ingredients': {
      'fermentable_additions': [
        {
          'name': 'Pilsner du Verger',
          'type': 'grain',
          'yield': {'fine_grind': mesure(81, '%')},
          'color': mesure(4, 'EBC'),
          'amount': mesure(4800, 'g'),
        },
      ],
      'hop_additions': [
        {
          'name': 'Houblon Alpha',
          'form': ?(avecForme ? 'pellet' : null),
          'alpha_acid': mesure(8.2, '%'),
          'amount': mesure(30, 'g'),
          'timing': {'use': 'add_to_boil', 'time': mesure(60, 'min')},
        },
        {
          'name': 'Houblon Arôme',
          'form': ?(avecForme ? 'pellet' : null),
          'alpha_acid': mesure(5.1, '%'),
          'amount': mesure(15, 'g'),
          'timing': {'use': 'add_to_boil'},
        },
      ],
      'miscellaneous_additions': [],
      'culture_additions': [
        {
          'name': 'Levure blonde fictive',
          'type': 'ale',
          'form': 'dry',
          'attenuation': mesure(78, '%'),
        },
      ],
    },
  },
};

RecettePublique publicRecipe({
  String id = '1',
  String name = 'Blonde du Verger',
  bool avecForme = true,
  String? styleId,
}) => RecettePublique.fromFirestore(
  'diydog-$id',
  publicRecipeDoc(id: id, name: name, avecForme: avecForme, styleId: styleId),
);

/// Textes inventés pour les tests, de 40 à 400 caractères comme le veut la
/// validation de l'écriture (ADR-013) ; aucun n'est tiré d'un catalogue.
const kTexteAmertume =
    'Amertume nette et franche, sans dureté, qui laisse la place au malt.';
const kTexteCru =
    'Pamplemousse et fleurs blanches, avec une pointe résineuse en finale.';
const kTexteWhirlpool =
    'Agrumes mûrs et notes florales, plus rondes qu\'en fin d\'ébullition.';

/// `beer_hop_aromas/hop-cascade`, `described`, relu le 14 novembre 2026.
/// [uses] remplace la map des usages ; [extra] ajoute ou remplace des champs.
Map<String, dynamic> hopAromaDoc({
  Map<String, Object?>? uses,
  Map<String, Object?> extra = const {},
}) => {
  'hop_name': 'Cascade',
  'status': 'described',
  'confidence': 'high',
  'descriptors': [
    {'key': 'pamplemousse', 'label': 'Pamplemousse'},
    {'key': 'floral', 'label': 'Floral'},
  ],
  'uses':
      uses ??
      {
        'dry_hop': {'text': kTexteCru},
        'bittering': {'text': kTexteAmertume},
      },
  'reviewed': true,
  'reviewed_at': '2026-11-14',
  'provenance': [
    {
      'source': 'claude-api',
      'source_id': 'hop-cascade',
      'version': 'claude-fable-5-2 / prompt 1 / effort medium',
      'licence': 'Texte généré pour Kass\'Beer',
      'retrieved': '2026-11-14',
    },
  ],
  'input_sha256': 'ab' * 32,
  'content_sha256': 'cd' * 32,
  ...extra,
};

/// `beer_hop_aromas/{id}` en `unknown`, non relu.
Map<String, dynamic> hopAromaUnknownDoc() => {
  'hop_name': 'Houblon doré',
  'status': 'unknown',
  'descriptors': <Object>[],
  'uses': <String, Object>{},
  'reviewed': false,
  'input_sha256': 'ab' * 32,
  'content_sha256': 'cd' * 32,
};

/// `beer_cultures/culture-levure-fictive`, levure inventée. [temperature] :
/// `temperature_range` ; `null` : plage absente.
Map<String, dynamic> cultureDoc({
  Map<String, Object>? temperature = const {
    'minimum': {'value': 15, 'unit': 'C'},
    'maximum': {'value': 20, 'unit': 'C'},
  },
}) => {
  'name': 'Levure fictive',
  'producer': 'Brasserie inventée',
  'type': 'ale',
  'form': 'dry',
  'attenuation': plage(75, 80, '%'),
  'temperature_range': ?temperature,
  'provenance': [provenance()],
  'content_sha256': '45' * 32,
};

/// Textes inventés pour les tests des levures, de 40 à 400 caractères.
const kTexteProfil =
    'Profil net et sec, quelques esters de poire, laisse parler le malt.';
const kTexteBas =
    'Très propre au bas de la plage, presque neutre, finale sèche et nette.';
const kTexteHaut =
    'Esters de banane et de poire plus marqués en haut de plage, corps rond.';

/// `beer_culture_aromas/culture-levure-fictive`, `described`.
/// [texts] remplace la map des textes ; [extra] ajoute ou remplace des champs.
Map<String, dynamic> cultureAromaDoc({
  Map<String, Object?>? texts,
  Map<String, Object?> extra = const {},
}) => {
  'culture_name': 'Levure fictive',
  'status': 'described',
  'confidence': 'high',
  'descriptors': [
    {'key': 'pear', 'label': 'poire'},
    {'key': 'dry', 'label': 'sec'},
  ],
  'texts':
      texts ??
      {
        'profile': {'text': kTexteProfil},
        'cool': {'text': kTexteBas},
        'warm': {'text': kTexteHaut},
      },
  'styles': [
    {'code': 'bjcp2021-21a', 'name': 'American IPA'},
    {'code': 'bjcp2021-18b', 'name': 'American Pale Ale'},
  ],
  'reviewed': true,
  'reviewed_at': '2026-11-21',
  'provenance': [
    {
      'source': 'claude-api',
      'source_id': 'culture-levure-fictive',
      'version': 'claude-fable-5-2 / prompt 1 / effort medium',
      'licence': 'Texte généré pour Kass\'Beer',
      'retrieved': '2026-11-21',
    },
  ],
  'input_sha256': 'ab' * 32,
  'content_sha256': 'cd' * 32,
  ...extra,
};

/// `beer_culture_aromas/{id}` en `unknown`, non relu.
Map<String, dynamic> cultureAromaUnknownDoc() => {
  'culture_name': 'Levure rare',
  'status': 'unknown',
  'descriptors': <Object>[],
  'texts': <String, Object>{},
  'styles': <Object>[],
  'reviewed': false,
  'input_sha256': 'ab' * 32,
  'content_sha256': 'cd' * 32,
};
