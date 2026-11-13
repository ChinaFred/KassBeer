import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart'
    show ProcessRecipe, ProcessStepSource, resolveProcess;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/processes/domain/modele_exemple.dart';
import 'package:kass_beer/features/processes/domain/modele_processus.dart';

/// Clés successives, comme `doc().id`.
String Function() compteur() {
  var n = 0;
  return () => 'cle-${n++}';
}

/// Modèle de deux journées : brassage et embouteillage.
ContenuModele deuxJournees({
  String name = 'Brassage et embouteillage',
  List<JourneeModele>? journees,
}) => ContenuModele(
  name: name,
  journees:
      journees ??
      const [
        JourneeModele(
          key: 'j1',
          name: 'Brassage',
          offsetDays: 0,
          elements: [
            ElementModele.etape(
              key: 'e1',
              name: 'Mise en place',
              durationMin: 30,
            ),
            ElementModele.bloc(
              key: 'e2',
              nature: NatureElement.chronologieRecette,
            ),
          ],
        ),
        JourneeModele(
          key: 'j2',
          name: 'Embouteillage',
          offsetDays: 14,
          elements: [
            ElementModele.etape(
              key: 'e3',
              name: 'Lavage',
              durationMin: 60,
              tempC: 40,
            ),
            ElementModele.bloc(
              key: 'e4',
              nature: NatureElement.ajoutsEmbouteillage,
            ),
          ],
        ),
      ],
);

void main() {
  group('modèle de processus : lecture et écriture', () {
    test('écriture puis lecture : mêmes champs, liste blanche', () {
      final data = deuxJournees().toFirestore();
      expect(data.keys.toSet(), {
        'format_version',
        'name',
        'notes',
        'sessions',
      });
      final sessions = data['sessions']! as List<Object?>;
      final etape =
          ((sessions[1]! as Map)['steps'] as List<Object?>).first! as Map;
      final bloc =
          ((sessions[1]! as Map)['steps'] as List<Object?>).last! as Map;
      expect(etape.keys.toSet(), {
        'key',
        'kind',
        'name',
        'duration_min',
        'temp_c',
      });
      expect(bloc.keys.toSet(), {'key', 'kind'});
      final relu = ModeleProcessus.fromFirestore('t1', {
        ...data,
        'owner_uid': 'u1',
        'owner_name': 'Brasseur A',
        'created_at': Timestamp.fromDate(DateTime(2026, 11, 11)),
        'updated_at': Timestamp.fromDate(DateTime(2026, 11, 11)),
      });
      expect(relu.ownerUid, 'u1');
      expect(relu.content.toFirestore(), data);
    });

    test('champ inconnu ignoré', () {
      final relu = ContenuModele.fromFirestore({
        ...deuxJournees().toFirestore(),
        'futur': true,
      });
      expect(relu.journees, hasLength(2));
    });

    for (final (label, change)
        in <(String, Map<String, Object?> Function(Map<String, Object?>))>[
          ('format inconnu', (d) => {...d, 'format_version': 2}),
          ('sans nom', (d) => {...d, 'name': null}),
          (
            'nature d\'élément inconnue',
            (d) => {
              ...d,
              'sessions': [
                {
                  'key': 'j1',
                  'name': 'Brassage',
                  'offset_days': 0,
                  'steps': [
                    {'key': 'e1', 'kind': 'autre'},
                  ],
                },
              ],
            },
          ),
          (
            'écart décimal',
            (d) => {
              ...d,
              'sessions': [
                {
                  'key': 'j1',
                  'name': 'Brassage',
                  'offset_days': 0.5,
                  'steps': [],
                },
              ],
            },
          ),
          (
            'étape sans durée',
            (d) => {
              ...d,
              'sessions': [
                {
                  'key': 'j1',
                  'name': 'Brassage',
                  'offset_days': 0,
                  'steps': [
                    {'key': 'e1', 'kind': 'step', 'name': 'Mise en place'},
                  ],
                },
              ],
            },
          ),
        ]) {
      test('illisible : $label', () {
        expect(
          () =>
              ContenuModele.fromFirestore(change(deuxJournees().toFirestore())),
          throwsA(isA<DocumentIllisible>()),
        );
      });
    }
  });

  group('erreurModele : contraintes d\'ADR-010', () {
    test('modèle valide', () {
      expect(erreurModele(deuxJournees()), isNull);
    });

    final base = deuxJournees().journees;
    for (final (label, modele, message) in <(String, ContenuModele, String)>[
      ('nom vide', deuxJournees(name: ' '), 'Nom : de 1 à 120 caractères.'),
      ('aucune journée', deuxJournees(journees: []), 'De 1 à 5 journées.'),
      (
        'première journée à J+1',
        deuxJournees(
          journees: [
            JourneeModele(
              key: 'j1',
              name: 'Brassage',
              offsetDays: 1,
              elements: base[0].elements,
            ),
            base[1],
          ],
        ),
        'Journée 1 : la première journée est le jour du brassage, à J+0.',
      ),
      (
        'clé d\'élément en double sur deux journées',
        deuxJournees(
          journees: [
            base[0],
            const JourneeModele(
              key: 'j2',
              name: 'Embouteillage',
              offsetDays: 14,
              elements: [
                ElementModele.etape(key: 'e1', name: 'Lavage', durationMin: 60),
              ],
            ),
          ],
        ),
        'Journée 2, étape 1 : clé invalide.',
      ),
      (
        'condition sur la recette sans bloc',
        deuxJournees(
          journees: [
            base[0],
            const JourneeModele(
              key: 'j2',
              name: 'Contrôle',
              offsetDays: 14,
              requiresRecipeBlock: true,
              elements: [
                ElementModele.etape(key: 'e3', name: 'Lavage', durationMin: 60),
              ],
            ),
          ],
        ),
        'Journée 2 : une journée conditionnée à la recette porte des houblons à '
            'cru ou des ajouts à l\'embouteillage.',
      ),
      (
        'écart qui décroît',
        deuxJournees(
          journees: [
            base[0],
            base[1],
            const JourneeModele(
              key: 'j3',
              name: 'Cru',
              offsetDays: 4,
              elements: [
                ElementModele.bloc(
                  key: 'e9',
                  nature: NatureElement.houblonsACru,
                ),
              ],
            ),
          ],
        ),
        'Journée 3 : écart plus petit que celui de la journée précédente.',
      ),
      (
        'durée de 700 minutes',
        deuxJournees(
          journees: [
            base[0],
            const JourneeModele(
              key: 'j2',
              name: 'Embouteillage',
              offsetDays: 14,
              elements: [
                ElementModele.etape(
                  key: 'e3',
                  name: 'Lavage',
                  durationMin: 700,
                ),
              ],
            ),
          ],
        ),
        'Journée 2, étape 1 : durée hors de 0 à 600 minutes.',
      ),
      (
        'écart de 366 jours',
        deuxJournees(
          journees: [
            base[0],
            JourneeModele(
              key: 'j2',
              name: 'Garde',
              offsetDays: 366,
              elements: base[1].elements,
            ),
          ],
        ),
        'Journée 2 : écart de 0 à 365 jours.',
      ),
      (
        '61 éléments',
        deuxJournees(
          journees: [
            base[0],
            JourneeModele(
              key: 'j2',
              name: 'Embouteillage',
              offsetDays: 14,
              elements: [
                for (var i = 0; i < 61; i++)
                  ElementModele.etape(key: 'x$i', name: 'É$i', durationMin: 1),
              ],
            ),
          ],
        ),
        'Journée 2 : 60 étapes au plus.',
      ),
    ]) {
      test(label, () => expect(erreurModele(modele), message));
    }
  });

  group('modèle d\'exemple', () {
    final fixture =
        jsonDecode(
              File('../brewing/test/fixtures/process.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final attendu =
        (fixture['templates']! as Map<String, Object?>)['exemple']!
            as Map<String, Object?>;

    test('identique au cas « exemple » de la fixture de brewing/', () {
      final modele = modeleExemple(compteur());
      expect(modele.name, attendu['name']);
      expect(modele.notes, 'Durées typiques, à ajuster à votre matériel.');
      expect(modele.notes, attendu['notes']);
      final sessions = attendu['sessions']! as List<Object?>;
      expect(modele.journees, hasLength(sessions.length));
      for (final (i, raw) in sessions.indexed) {
        final s = raw! as Map<String, Object?>;
        final j = modele.journees[i];
        expect(j.name, s['name']);
        expect(j.offsetDays, s['offset_days']);
        expect(j.requiresRecipeBlock, s['requires_recipe_block'] ?? false);
        final items = s['items']! as List<Object?>;
        expect(j.elements, hasLength(items.length), reason: j.name);
        for (final (k, rawItem) in items.indexed) {
          final item = rawItem! as Map<String, Object?>;
          final e = j.elements[k];
          expect(e.nature.storedValue, item['kind'], reason: '${j.name} $k');
          expect(e.name, item['name'], reason: '${j.name} $k');
          expect(e.durationMin, (item['duration_min'] as num?)?.toDouble());
        }
      }
    });

    test('valide, clés neuves et toutes distinctes à chaque copie', () {
      final a = modeleExemple(compteur());
      expect(erreurModele(a), isNull);
      final keys = [
        for (final j in a.journees) ...[
          j.key,
          for (final e in j.elements) e.key,
        ],
      ];
      expect(keys.toSet(), hasLength(keys.length));
      var n = 100;
      final b = modeleExemple(() => 'autre-${n++}');
      expect(b.journees.first.key, isNot(a.journees.first.key));
    });

    test('résolu par brewing/ avec une recette sans houblon à cru', () {
      final modele = modeleExemple(compteur());
      final resolution = resolveProcess(
        template: [for (final j in modele.journees) j.toInput()],
        recipe: ProcessRecipe(brewStepCount: 2),
      );
      expect(resolution.sessions.map((s) => s.offsetDays), [0, 14]);
      expect(
        resolution.sessions.first.steps
            .where((s) => s.source == ProcessStepSource.recipeStep)
            .length,
        2,
      );
    });
  });
}
