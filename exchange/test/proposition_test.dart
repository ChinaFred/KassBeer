import 'dart:convert';
import 'dart:io';

import 'package:exchange/exchange.dart';
import 'package:test/test.dart';

/// Propositions de l'assistant de recette (ADR-015, section 6 ; P61) : la
/// fixture partagée `test-fixtures/recipe_assistant_operations.json` est
/// rejouée ici (liste fermée des opérations, lecture, application, marques)
/// et par `functions/test/proposition.test.ts` (format de sortie).

final Map<String, Object?> _fixture =
    jsonDecode(
          File(
            '../test-fixtures/recipe_assistant_operations.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

Map<String, Object?> _map(Object? v) => (v! as Map).cast<String, Object?>();

List<EntreeBibliotheque> _entrees(Object? brut) => [
  for (final e in (brut! as List).cast<Map<String, Object?>>())
    EntreeBibliotheque(
      id: e['id']! as String,
      nom: e['nom']! as String,
      type: e['type'] as String?,
      couleur: (e['couleur'] as num?)?.toDouble(),
      rendement: (e['rendement'] as num?)?.toDouble(),
      alpha: (e['alpha'] as num?)?.toDouble(),
      forme: e['forme'] as String?,
      attenuation: (e['attenuation'] as num?)?.toDouble(),
    ),
];

final IndexImport _bibliotheque = () {
  final b = _map(_fixture['library']);
  return IndexImport(
    malts: IndexBibliotheque(ListeRecette.malts, _entrees(b['malts'])),
    houblons: IndexBibliotheque(ListeRecette.houblons, _entrees(b['houblons'])),
    ajouts: IndexBibliotheque(ListeRecette.ajouts, _entrees(b['ajouts'])),
    levures: IndexBibliotheque(ListeRecette.levures, _entrees(b['levures'])),
  );
}();

/// Recette de base relue, comme le brouillon de l'éditeur.
final Map<String, Object?> _base =
    (lireRecettePartielle(_map(_fixture['base_recipe'])) as RecetteLue).recipe;

List<MarqueIa> _marques(Object? brut) => [
  for (final t in (brut! as List)) MarqueIa.lire(t)!,
];

List<OperationProposee> _operations(Object? brut) {
  final lue = lireProposition({
    'resume': 'Cas de la fixture.',
    'operations': brut,
  });
  return switch (lue) {
    PropositionLue(:final proposition) => proposition.operations,
    PropositionIllisible(:final chemin) => fail(
      'opérations illisibles : $chemin',
    ),
  };
}

/// Recette attendue : la base, avec `changes` (clés de `recipe`) et `lists`
/// (listes d'ingrédients ; `base:N` désigne la ligne N de la base).
Map<String, Object?> _attendue(Map<String, Object?> expected) {
  final r = jsonDecode(jsonEncode(_base)) as Map<String, Object?>;
  for (final e in _map(expected['changes'] ?? {}).entries) {
    r[e.key] = e.value;
  }
  final ingredients = _map(r['ingredients']);
  for (final e in _map(expected['lists'] ?? {}).entries) {
    final base = _map(_base['ingredients'])[e.key]! as List;
    ingredients[e.key] = [
      for (final l in e.value! as List)
        l is String && l.startsWith('base:')
            ? base[int.parse(l.substring(5))]
            : l,
    ];
  }
  r['ingredients'] = ingredients;
  return r;
}

void main() {
  group('liste fermée des opérations', () {
    test('kOperationsProposition égal à la fixture', () {
      expect({
        for (final e in kOperationsProposition.entries)
          e.key: e.value.versJson(),
      }, _fixture['operations']);
      expect(kMaxOperationsProposition, _fixture['max_operations']);
      expect(kMaxResumeProposition, _fixture['resume_max_chars']);
    });

    test('champs techniques et marques égaux à la fixture', () {
      expect({
        for (final e in kChampsTechniques.entries)
          e.key: {'nature': e.value.nature, 'field': e.value.champ},
      }, _fixture['technical_fields']);
      final marks = _map(_fixture['marks']);
      expect(kMaxMarquesIa, marks['max_entries']);
      expect(kMaxLongueurMarqueIa, marks['max_chars']);
      expect(kChampsMarquesIa, marks['fields_by_nature']);
    });

    test('chaque opération du schéma a son application, et aucune autre', () {
      final appliquees = {
        for (final c in (_fixture['cases']! as List))
          for (final o in (_map(c)['operations']! as List)) _map(o)['op'],
      };
      expect(appliquees, kOperationsProposition.keys.toSet());
    });

    test('aucune opération sur notes, author ou brew_steps', () {
      for (final e in kOperationsProposition.entries) {
        for (final interdit in ['notes', 'author', 'brew_steps']) {
          expect(e.key.contains(interdit), isFalse, reason: e.key);
          expect(e.value.champs.keys, isNot(contains(interdit)));
        }
      }
    });
  });

  group('lecture d\'une proposition (reading_cases)', () {
    for (final c in (_fixture['reading_cases']! as List)) {
      final cas = _map(c);
      test(cas['name'], () {
        final lue = lireProposition(cas['proposition']);
        expect(lue is PropositionLue, cas['valid'], reason: '$lue');
        if (cas['path'] case final String chemin) {
          expect((lue as PropositionIllisible).chemin, chemin);
        }
      });
    }

    test('30 opérations acceptées, 31 refusées', () {
      Map<String, Object?> de(int n) => {
        'resume': 'R.',
        'operations': [
          for (var i = 0; i < n; i++) {'op': 'set_boil_time_min', 'value': i},
        ],
      };
      expect(lireProposition(de(30)), isA<PropositionLue>());
      expect(lireProposition(de(31)), isA<PropositionIllisible>());
    });

    test('résumé de 500 caractères accepté, 501 refusé', () {
      Map<String, Object?> de(int n) => {
        'resume': 'r' * n,
        'operations': [
          {'op': 'set_name', 'value': 'X'},
        ],
      };
      expect(lireProposition(de(500)), isA<PropositionLue>());
      expect(lireProposition(de(501)), isA<PropositionIllisible>());
    });

    test('chemin du champ en faute, sans valeur', () {
      final lue = lireProposition({
        'resume': 'R.',
        'operations': [
          {'op': 'set_name', 'value': 'X'},
          {
            'op': 'add_fermentable',
            'name': 'P',
            'type': 'grain',
            'amount_g': 'x',
          },
        ],
      });
      expect((lue as PropositionIllisible).chemin, 'operations.1.amount_g');
    });
  });

  group('application (cases)', () {
    final marquesBase = _marques(_fixture['base_marks']);
    for (final c in (_fixture['cases']! as List)) {
      final cas = _map(c);
      test(cas['name'], () {
        final expected = _map(cas['expected']);
        final avant = jsonEncode(_base);
        final r = appliquerProposition(
          _base,
          cas.containsKey('marks') ? _marques(cas['marks']) : marquesBase,
          _operations(cas['operations']),
          bibliotheque: _bibliotheque,
        );
        // La recette d'origine n'est pas modifiée.
        expect(jsonEncode(_base), avant);
        expect([
          for (final f in r.refusOperations)
            {'index': f.index, 'reason': f.raison.code, 'field': f.champ},
        ], expected['refusals']);
        if (expected['rejected'] == true) {
          expect(r, isA<PropositionRefusee>());
          return;
        }
        final appliquee = r as PropositionAppliquee;
        expect(appliquee.recipe, _attendue(expected));
        expect([for (final m in appliquee.marques) m.texte], expected['marks']);
      });
    }

    test('liste pleine : 21e palier refusé', () {
      final recipe = {
        ..._base,
        'mash': {
          'name': kNomEmpatage,
          'mash_steps': [
            for (var i = 0; i < 20; i++)
              {
                'name': 'Palier $i',
                'step_temperature': {'value': 65, 'unit': 'C'},
                'step_time': {'value': 10, 'unit': 'min'},
              },
          ],
        },
      };
      final r = appliquerProposition(recipe, const [], [
        const OperationProposee('add_mash_step', {
          'name': 'Un de trop',
          'temperature_c': 70,
          'time_min': 10,
        }),
      ], bibliotheque: _bibliotheque);
      expect(r.refusOperations.single.raison, RaisonRefusOperation.listePleine);
    });

    test('sans index de la Bibliothèque : valeur du modèle marquée', () {
      final r =
          appliquerProposition(_base, const [], [
                const OperationProposee('add_hop', {
                  'name': 'Nelson',
                  'form': 'pellet',
                  'amount_g': 10,
                  'use': 'boil',
                  'time_min': 10,
                  'alpha_acid_pct': 14,
                }),
              ], bibliotheque: const IndexImport())
              as PropositionAppliquee;
      expect(
        [for (final m in r.marques) m.texte],
        ['hop:houblon-nelson:alpha_acid'],
      );
    });
  });

  group('marques ai_proposed', () {
    for (final c in (_fixture['marks_cases']! as List)) {
      final cas = _map(c);
      test(cas['name'], () {
        final lues = lireMarques(cas['input']);
        expect([for (final m in lues.marques) m.texte], cas['marks']);
        expect(lues.illisibles, cas['unreadable']);
      });
    }

    Map<String, Object?> houblons(Object? lignes) => {
      'name': 'R',
      'ingredients': {
        'hop_additions': [
          for (final l in (lignes! as List).cast<Map<String, Object?>>())
            {
              'name': l['name'],
              if (l['alpha'] case final num a)
                'alpha_acid': {'value': a, 'unit': '%'},
            },
        ],
      },
    };
    for (final c in (_fixture['marks_edit_cases']! as List)) {
      final cas = _map(c);
      test('édition : ${cas['name']}', () {
        expect([
          for (final m in marquesApresEdition(
            reference: houblons(cas['reference']),
            edite: houblons(cas['edited']),
            marques: _marques(cas['input']),
          ))
            m.texte,
        ], cas['marks']);
      });
    }

    test('100 marques gardées, la 101e comptée illisible', () {
      final lues = lireMarques([
        for (var i = 0; i < 101; i++) 'hop:houblon-h$i:alpha_acid',
      ]);
      expect(lues.marques, hasLength(100));
      expect(lues.illisibles, 1);
    });

    test('marque de 201 caractères illisible', () {
      final cle = 'houblon-${'a' * 92}';
      final texte = 'hop:$cle:alpha_acid';
      expect(MarqueIa.lire(texte), isNotNull);
      expect(MarqueIa.lire('hop:$cle-b:alpha_acid'), isNull);
      expect(MarqueIa.lire('x' * 201), isNull);
    });

    final marque = MarqueIa.lire('fermentable:malt-maison:color')!;

    test('retrait de l\'ingrédient : marque effacée', () {
      final sans = jsonDecode(jsonEncode(_base)) as Map<String, Object?>;
      (_map(sans['ingredients'])['fermentable_additions']! as List).removeAt(1);
      expect(marquesCoherentes(sans, [marque]), isEmpty);
      expect(marquesCoherentes(_base, [marque]), [marque]);
    });

    test('correction à la main de la valeur : marque effacée', () {
      final edite = jsonDecode(jsonEncode(_base)) as Map<String, Object?>;
      final ligne = _map(
        (_map(edite['ingredients'])['fermentable_additions']! as List)[1],
      );
      ligne['color'] = {'value': 35, 'unit': 'EBC'};
      expect(
        marquesApresEdition(reference: _base, edite: edite, marques: [marque]),
        isEmpty,
      );
    });

    test('autre champ modifié (quantité) : marque gardée', () {
      final edite = jsonDecode(jsonEncode(_base)) as Map<String, Object?>;
      final ligne = _map(
        (_map(edite['ingredients'])['fermentable_additions']! as List)[1],
      );
      ligne['amount'] = {'value': 900, 'unit': 'g'};
      expect(
        marquesApresEdition(reference: _base, edite: edite, marques: [marque]),
        [marque],
      );
    });

    test('écriture : sans doublon', () {
      expect(ecrireMarques([marque, marque]), [marque.texte]);
    });

    test('valeurs proposées : nom de la ligne et valeur', () {
      final v = valeursProposees(_base, [marque]).single;
      expect(v.nom, 'Malt maison');
      expect(v.liste, ListeRecette.malts);
      expect(v.valeur, 30);
    });
  });

  group('compte rendu d\'export', () {
    test('BeerJSON : valeurs proposées listées, marque absente du fichier', () {
      final recipe = jsonDecode(jsonEncode(_base)) as Map<String, Object?>;
      _map(recipe['mash'])['grain_temperature'] = {'value': 18, 'unit': 'C'};
      final ingredients = _map(recipe['ingredients']);
      _map((ingredients['fermentable_additions']! as List)[1])['yield'] = {
        'fine_grind': {'value': 75, 'unit': '%'},
      };
      _map((ingredients['culture_additions']! as List)[0])['amount'] = {
        'value': 11,
        'unit': 'g',
      };
      final r = exporterBeerJson(
        recipe: recipe,
        ownerName: 'Brasseur Fictif',
        rendementEmpatage: 72,
        calcul: null,
        chronologie: false,
        marquesIa: [MarqueIa.lire('fermentable:malt-maison:color')!],
      );
      expect(r, isA<ExportPret>(), reason: '$r');
      r as ExportPret;
      expect(r.valeursIa.single.nom, 'Malt maison');
      expect(r.contenu.contains('ai_proposed'), isFalse);
      expect(r.contenu.contains('malt-maison'), isFalse);
    });
  });
}
