import 'dart:convert';

import 'package:brewing/brewing.dart';
import 'package:exchange/exchange.dart';
import 'package:test/test.dart';

import 'support/description.dart';

Map<String, Object?> _m(num value, String unit) => {
  'value': value,
  'unit': unit,
};

/// Recette complète, dans la forme qu'écrit l'application (`toFirestore`).
Map<String, Object?> _complete() => {
  'name': 'Blonde d\'essai',
  'type': 'all grain',
  'style': {'name': 'Blonde'},
  'notes': 'Recette de test.',
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
        'name': 'Candi',
        'type': 'sugar',
        'amount': _m(500.0, 'g'),
        'color': _m(0.0, 'EBC'),
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
    ],
    'miscellaneous_additions': [
      {
        'name': 'Coriandre',
        'type': 'spice',
        'amount': _m(10.0, 'g'),
        'timing': {'use': 'add_to_boil', 'time': _m(5, 'min')},
      },
    ],
    'culture_additions': [
      {
        'name': 'US-05',
        'type': 'ale',
        'form': 'dry',
        'attenuation': _m(78.0, '%'),
        'amount': _m(11.5, 'g'),
      },
    ],
  },
};

/// Calcul de la recette complète par `brewing/`, comme le fait l'application.
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
      FermentableInput(
        name: 'Candi',
        kind: FermentableKind.sugar,
        massGrams: 500,
        colorEbc: 0,
        yieldPercent: 100,
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
      HopInput(
        name: 'Saaz',
        massGrams: 30,
        use: HopUse.afterBoil,
        form: HopForm.whole,
        alphaPercent: 3.5,
        minutes: 15,
      ),
    ],
    yeasts: [YeastInput(name: 'US-05', attenuationPercent: 78)],
    batchVolumeLitres: 20,
    boilMinutes: 60,
  ),
  mashEfficiencyPercent: 72,
);

ResultatExport _exporter(
  Map<String, Object?> recipe, {
  String? ownerName = 'Brasseur Exemple',
  double? rendement = 72,
  RecipeCalculation? calcul,
  bool chronologie = false,
}) => exporterBeerJson(
  recipe: recipe,
  ownerName: ownerName,
  rendementEmpatage: rendement,
  calcul: calcul,
  chronologie: chronologie,
);

List<String> _manques(ResultatExport r) => [
  for (final m in (r as ExportBloque).manques)
    switch (m) {
      ManqueDeCalcul(:final manque) =>
        '${manque.kind.name}(${manque.items.map((i) => i.name).join(', ')})',
      ManqueDeFormat(:final champ, :final noms) =>
        '${champ.name}(${noms.join(', ')})',
    },
];

void main() {
  test(
    'recette complète : fichier attendu, auteur = owner_name, rendement de l\'équipement',
    () {
      final r =
          _exporter(_complete(), calcul: _calcul(), chronologie: true)
              as ExportPret;
      expectFixture('export/blonde-essai.json', jsonDecode(r.contenu));
      final recette =
          ((jsonDecode(r.contenu) as Map)['beerjson'] as Map)['recipes']
              as List;
      final sortie = recette.single as Map;
      expect(sortie['author'], 'Brasseur Exemple');
      expect(r.auteur, 'Brasseur Exemple');
      expect(sortie['efficiency'], {'brewhouse': _m(72, '%')});
      expect(sortie.containsKey('style'), isFalse);
      expect(r.pertes.whereType<StyleNonExporte>().single.nom, 'Blonde');
      expect(r.pertes.whereType<ChronologieNonExportee>(), hasLength(1));
    },
  );

  test('houblon sans forme (D8) : export BeerJSON permis, sans `form`', () {
    final recipe = _complete();
    final hops =
        (recipe['ingredients']! as Map<String, Object?>)['hop_additions']!
            as List<Object?>;
    for (final h in hops) {
      (h! as Map).remove('form');
    }
    final r = _exporter(recipe, calcul: _calcul()) as ExportPret;
    final ecrits =
        ((((jsonDecode(r.contenu) as Map)['beerjson'] as Map)['recipes']
                        as List)
                    .single
                as Map)['ingredients']
            as Map;
    for (final h in ecrits['hop_additions'] as List) {
      expect((h as Map).containsKey('form'), isFalse);
    }
  });

  test(
    'E3 : ni prix, ni stock, ni propriétaire, ni équipement dans le fichier',
    () {
      final r = _exporter(_complete(), calcul: _calcul()) as ExportPret;
      for (final interdit in [
        'price',
        'prix',
        'inventory',
        'stock',
        'cost',
        'owner_uid',
        'equipment',
        '@',
      ]) {
        expect(r.contenu, isNot(contains(interdit)), reason: interdit);
      }
    },
  );

  test(
    'E6 : recipe.author passe avant owner_name ; sans les deux, export bloqué',
    () {
      final avecAuteur = {..._complete(), 'author': 'Brasseuse Fictive'};
      final r = _exporter(avecAuteur) as ExportPret;
      expect(r.contenu, contains('"author": "Brasseuse Fictive"'));
      expect(_manques(_exporter(_complete(), ownerName: null)), ['auteur()']);
    },
  );

  test('E7 : deux exports de la même recette donnent le même texte', () {
    final a = _exporter(_complete(), calcul: _calcul()) as ExportPret;
    final b = _exporter(_complete(), calcul: _calcul()) as ExportPret;
    expect(a.contenu, b.contenu);
  });

  test('sans calcul : aucune valeur estimée écrite', () {
    final r = _exporter(_complete()) as ExportPret;
    expect(r.contenu, isNot(contains('original_gravity')));
  });

  test(
    'export bloqué : chaque valeur à compléter, dans l\'ordre de la recette',
    () {
      final incomplete = {
        'name': 'Incomplète',
        'mash': {
          'name': kNomEmpatage,
          'mash_steps': [
            {
              'name': 'Palier',
              'step_temperature': _m(65, 'C'),
              'step_time': _m(60, 'min'),
            },
          ],
        },
        'ingredients': {
          'fermentable_additions': [
            {'name': 'Pils', 'type': 'grain', 'amount': _m(4000, 'g')},
          ],
          'hop_additions': [
            {
              'name': 'Saaz',
              'form': 'leaf',
              'amount': _m(20, 'g'),
              'timing': {'use': 'add_to_boil'},
            },
          ],
          'miscellaneous_additions': [
            {'name': 'Sel', 'amount': _m(2, 'g')},
          ],
          'culture_additions': [
            {'name': 'S-04'},
          ],
        },
      };
      expect(_manques(_exporter(incomplete, rendement: null)), [
        'typeRecette()',
        'batchVolume()',
        'mashEfficiency()',
        'temperatureGrain()',
        'typePalier(Palier)',
        'extractYield(Pils)',
        'color(Pils)',
        'hopAlpha(Saaz)',
        'typeLevure(S-04)',
        'formeLevure(S-04)',
        'quantiteLevure(S-04)',
        'typeAjout(Sel)',
      ]);
      // Température du grain sans palier : le schéma demande un palier.
      final sansPalier = {
        ..._complete(),
        'mash': {'name': kNomEmpatage, 'grain_temperature': _m(18.0, 'C')},
      };
      expect(_manques(_exporter(sansPalier)), ['paliers()']);
    },
  );

  test(
    "B : sans empâtage ni durée d'ébullition, mash et boil omis et listés",
    () {
      final extrait = {
        'name': "Blonde à l'extrait",
        'type': 'extract',
        'batch_size': _m(20.0, 'l'),
        'ingredients': {
          'fermentable_additions': [
            {
              'name': 'Extrait sec clair',
              'type': 'dry extract',
              'amount': _m(3000.0, 'g'),
              'color': _m(8.0, 'EBC'),
              'yield': {'fine_grind': _m(95.0, '%')},
            },
          ],
          'hop_additions': [
            {
              'name': 'Cascade',
              'form': 'pellet',
              'alpha_acid': _m(6.0, '%'),
              'amount': _m(30.0, 'g'),
              'timing': {'use': 'add_to_boil', 'time': _m(30, 'min')},
            },
          ],
          'miscellaneous_additions': <Object?>[],
          'culture_additions': [
            {
              'name': 'US-05',
              'type': 'ale',
              'form': 'dry',
              'amount': _m(11.5, 'g'),
            },
          ],
        },
      };
      final r = _exporter(extrait) as ExportPret;
      expectFixture('export/extrait-sans-empatage.json', jsonDecode(r.contenu));
      final sortie =
          (((jsonDecode(r.contenu) as Map)['beerjson'] as Map)['recipes']
                      as List)
                  .single
              as Map;
      expect(sortie.containsKey('mash'), isFalse);
      expect(sortie.containsKey('boil'), isFalse);
      expect(r.pertes.whereType<EmpatageNonExporte>(), hasLength(1));
      expect(r.pertes.whereType<EbullitionNonExportee>(), hasLength(1));
    },
  );

  test('A2 : export puis réimport donnent la même recette, auteur ajouté', () {
    final r = _exporter(_complete(), calcul: _calcul()) as ExportPret;
    final lu = analyserFichier(utf8.encode(r.contenu)) as FichierLu;
    final recette = lu.recettes.single.resultat as RecetteLue;
    // Le style (nom seul) n'est pas exporté : il ne revient pas.
    final attendu = {..._complete(), 'author': 'Brasseur Exemple'}
      ..remove('style');
    expect(recette.recipe, attendu);
  });

  test('nom du fichier : sans accents, minuscules, tirets ; recette sinon', () {
    expect(nomFichierExport('IPA Maison', 'json'), 'ipa-maison.json');
    expect(
      nomFichierExport('Blonde d\'Été n° 2', 'json'),
      'blonde-d-ete-n-2.json',
    );
    expect(nomFichierExport('%%%', 'json'), 'recette.json');
    expect(nomFichierExport('a' * 300, 'json').length, 105);
  });
}
