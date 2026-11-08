import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/ligne_editeur.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/presentation/brew_detail_screen.dart';
import 'package:kass_beer/features/brews/presentation/brews_providers.dart';
import 'package:kass_beer/features/brews/presentation/brews_screen.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

Future<TestApp> go(
  WidgetTester tester,
  String path, {
  void Function(TestApp app)? before,
  bool fromCache = false,
}) async {
  final app = TestApp();
  await app.pump(tester);
  app.signIn(brewerUser, member: brewerMember, fromCache: fromCache);
  before?.call(app);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

void main() {
  group('liste', () {
    testWidgets('vide : message et lien vers les recettes', (tester) async {
      await go(tester, '/brassins');
      expect(find.text(BrewsScreen.emptyMessage), findsOneWidget);
      expect(find.text('Voir les recettes'), findsOneWidget);
    });

    testWidgets('statut, auteur, date, filtre Les miens', (tester) async {
      await go(
        tester,
        '/brassins',
        before: (app) => app.brews.publish([
          unBrassin(
            id: 'a',
            status: BrewStatus.planned,
            plannedFor: DateTime(2026, 11, 14),
          ),
          unBrassin(id: 'z', owner: 'uid-zoe', status: BrewStatus.done),
        ]),
      );
      expect(find.text('Prévu · Grainfather · Vous'), findsOneWidget);
      expect(find.text('Prévu le sam. 14 nov. 2026'), findsOneWidget);
      expect(find.textContaining('Terminé · Grainfather'), findsOneWidget);
      await tester.tap(find.text('Les miens'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Terminé'), findsNothing);
    });

    testWidgets('panne : Réessayer', (tester) async {
      await go(
        tester,
        '/brassins',
        before: (app) => app.brews.all.addError(Exception('refus')),
      );
      expect(find.text(BrewsScreen.loadError), findsOneWidget);
    });
  });

  group('fiche', () {
    testWidgets('propriétaire d\'un prévu : Préparer, Modifier, Supprimer', (
      tester,
    ) async {
      await go(
        tester,
        '/brassins/b1',
        before: (app) {
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
          app.brews.publishEvents('b1', const []);
        },
      );
      expect(find.text('Préparer le brassage'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
      expect(find.text('Pas encore préparé sur cet appareil'), findsNothing);
      expect(find.text('Préparé sur cet appareil'), findsNothing);
    });

    testWidgets('R5 : préparé dans la session, affiché', (tester) async {
      await go(
        tester,
        '/brassins/b1',
        before: (app) {
          app.container.read(preparedBrewsProvider).add('b1');
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
          app.brews.publishEvents('b1', const []);
        },
      );
      expect(find.text('Préparé sur cet appareil'), findsOneWidget);
    });

    testWidgets('C23 : lecture des saisies en échec, message et Réessayer', (
      tester,
    ) async {
      await go(
        tester,
        '/brassins/b1',
        before: (app) {
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
          app.brews.eventsOf('b1').addError(Exception('refus'));
        },
      );
      await tester.scrollUntilVisible(
        find.text('Impossible de lire les saisies.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('autre brasseur : aucune action', (tester) async {
      await go(
        tester,
        '/brassins/b1',
        before: (app) {
          app.brews.publish([unBrassin(owner: 'uid-zoe')]);
          app.brews.publishEvents('b1', const []);
        },
      );
      expect(find.text('Reprendre le brassage'), findsNothing);
      expect(find.text('Supprimer'), findsNothing);
      expect(find.textContaining('Brassin de'), findsOneWidget);
    });

    testWidgets('suppression sans saisie : immédiate', (tester) async {
      final app = await go(
        tester,
        '/brassins/b1',
        before: (app) {
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
          app.brews.publishEvents('b1', const [], fromCache: true);
        },
        fromCache: true,
      );
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'delete');
    });

    testWidgets('suppression avec saisies hors ligne : refusée', (
      tester,
    ) async {
      final app = await go(
        tester,
        '/brassins/b1',
        before: (app) {
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
          app.brews.publishEvents('b1', [
            debut('e1', 'k-palier', DateTime(2026, 11, 8, 11)),
          ], fromCache: true);
        },
        fromCache: true,
      );
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text(BrewDetailScreen.deleteOffline), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('suppression avec saisies en ligne : événements compris', (
      tester,
    ) async {
      final app = await go(
        tester,
        '/brassins/b1',
        before: (app) {
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
          app.brews.publishEvents('b1', [
            debut('e1', 'k-palier', DateTime(2026, 11, 8, 11)),
          ]);
        },
      );
      await tester.ensureVisible(find.text('Supprimer'));
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'delete_with_events');
    });
  });

  group('Préparer', () {
    testWidgets('n\'écrit rien, puis Commencer : lot, nom lu à l\'ouverture', (
      tester,
    ) async {
      final app = await go(
        tester,
        '/brassins/b1/preparer',
        before: (app) {
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
          app.brews.publishEvents('b1', const []);
        },
      );
      expect(
        find.text('Tout est prêt. Vous pouvez couper le réseau.'),
        findsOneWidget,
      );
      expect(app.brews.writes, isEmpty);
      expect(app.brews.prepareCalls, 1);
      await tester.ensureVisible(find.text('Commencer le brassage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer le brassage'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'start');
      expect(write.detail['first'], 'k-palier');
      expect(write.detail['owner_name'], 'Bruno Brasseur');
    });

    testWidgets('C21 : autre brasseur, message et aucun démarrage', (
      tester,
    ) async {
      final app = await go(
        tester,
        '/brassins/b1/preparer',
        before: (app) {
          app.brews.publish([
            unBrassin(owner: 'uid-zoe', status: BrewStatus.planned),
          ]);
        },
      );
      expect(find.text(BrewDayScreen.notOwner), findsOneWidget);
      expect(find.text('Commencer le brassage'), findsNothing);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('C21 : brassin en fermentation, aucun démarrage', (
      tester,
    ) async {
      final app = await go(
        tester,
        '/brassins/b1/preparer',
        before: (app) {
          app.brews.publish([unBrassin(status: BrewStatus.fermenting)]);
        },
      );
      expect(find.text(kBrassageTermine), findsOneWidget);
      expect(find.text('Commencer le brassage'), findsNothing);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('R4 : chronologie illisible affichée à la préparation', (
      tester,
    ) async {
      await go(
        tester,
        '/brassins/b1/preparer',
        before: (app) {
          app.brews.publish([
            Brew(
              id: 'b1',
              ownerUid: 'uid-brasseur',
              name: 'Blonde',
              status: BrewStatus.planned,
              recipe: const RecipeContent(
                name: 'Blonde',
                brewStepsProblem: 'clé absente (0)',
              ),
              equipment: equipementTest,
            ),
          ]);
        },
      );
      expect(
        find.text('Chronologie de ce brassin illisible : clé absente (0).'),
        findsOneWidget,
      );
      expect(find.text('Aucune étape'), findsNothing);
    });

    testWidgets('délai dépassé : brassin lisible, peut ne pas être à jour', (
      tester,
    ) async {
      final app = await go(
        tester,
        '/brassins/b1/preparer',
        before: (app) {
          app.brews.serverReachable = false;
          app.brews.publish([unBrassin(status: BrewStatus.planned)]);
        },
      );
      expect(find.textContaining('peut ne pas être à jour'), findsOneWidget);
      expect(find.textContaining('Tout est prêt'), findsNothing);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('première étape de 0 min : commencée sur l\'écran du jour', (
      tester,
    ) async {
      final app = await go(
        tester,
        '/brassins/b1/preparer',
        before: (app) {
          app.brews.publish([
            unBrassin(status: BrewStatus.planned, steps: const [ajout, palier]),
          ]);
        },
      );
      await tester.ensureVisible(find.text('Commencer le brassage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer le brassage'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.detail['first'], isNull);
    });
  });

  group('création depuis la recette', () {
    const equipment = Equipment(
      id: 'e1',
      ownerUid: 'uid-brasseur',
      ownerName: 'Bruno',
      content: equipementTest,
    );

    Recipe recette({List<BrewStepLine> steps = const [palier]}) => Recipe(
      id: 'r1',
      ownerUid: 'uid-brasseur',
      content: RecipeContent(
        name: 'Blonde',
        equipmentId: 'e1',
        brewSteps: steps,
      ),
    );

    testWidgets(
      'équipement présélectionné, chronologie indiquée, créé avec le nom',
      (tester) async {
        final app = await go(
          tester,
          '/recettes/r1',
          before: (app) {
            app.recipes.publish([recette()]);
            app.equipment.publish([equipment]);
          },
        );
        await tester.tap(find.text('Nouveau brassin'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Chronologie : 1 étape ·'), findsOneWidget);
        await tester.tap(find.text('Créer le brassin'));
        await tester.pumpAndSettle();
        final write = app.brews.writes.single;
        expect(write.kind, 'create');
        expect(write.detail['equipment_id'], 'e1');
        expect(write.detail['owner_name'], 'Bruno Brasseur');
      },
    );

    testWidgets('sans équipement : message, rien n\'est créé', (tester) async {
      final app = await go(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([
            Recipe(
              id: 'r1',
              ownerUid: 'uid-brasseur',
              content: const RecipeContent(name: 'Blonde'),
            ),
          ]);
          // Deux équipements à soi : aucune présélection.
          app.equipment.publish([
            equipment,
            const Equipment(
              id: 'e2',
              ownerUid: 'uid-brasseur',
              content: EquipmentContent(
                name: 'Cuve',
                kind: EquipmentKind.multiVessel,
              ),
            ),
          ]);
        },
      );
      await tester.tap(find.text('Nouveau brassin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer le brassin'));
      await tester.pumpAndSettle();
      expect(find.text('Choisissez un équipement.'), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('fiche recette : chronologie et son bouton pour l\'auteur', (
      tester,
    ) async {
      await go(
        tester,
        '/recettes/r1',
        before: (app) => app.recipes.publish([recette()]),
      );
      await tester.scrollUntilVisible(
        find.text('Modifier la chronologie'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Chronologie du jour'), findsOneWidget);
      expect(find.text('Modifier la chronologie'), findsOneWidget);
    });
  });

  group('éditeur de chronologie', () {
    Recipe recette() => Recipe(
      id: 'r1',
      ownerUid: 'uid-brasseur',
      content: const RecipeContent(
        name: 'Blonde',
        boilTimeMin: 60,
        mashSteps: [MashStep(name: 'Empâtage', tempC: 67, durationMin: 60)],
      ),
    );

    testWidgets(
      'préremplir puis enregistrer : clés créées, nom de l\'ébullition',
      (tester) async {
        final app = await go(
          tester,
          '/recettes/r1/chronologie',
          before: (app) => app.recipes.publish([recette()]),
        );
        await tester.tap(find.text('Préremplir depuis la recette'));
        await tester.pumpAndSettle();
        expect(find.textContaining('1. Empâtage'), findsOneWidget);
        expect(find.textContaining('2. Ébullition'), findsOneWidget);
        expect(find.byType(LigneEditeur), findsNWidgets(2));
        await tester.tap(find.text('Enregistrer'));
        await tester.pumpAndSettle();
        final saved = app.recipes.savedBrewSteps!;
        expect(saved.map((s) => s.key).toSet().length, 2);
        expect(saved.last.name, 'Ébullition');
      },
    );

    testWidgets('ajout d\'une étape avec le formulaire', (tester) async {
      await go(
        tester,
        '/recettes/r1/chronologie',
        before: (app) => app.recipes.publish([recette()]),
      );
      await tester.tap(find.text('Ajouter une étape').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom de l\'étape'),
        'Rinçage',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Durée (min)'),
        '10',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1. Rinçage'), findsOneWidget);
    });
  });

  test('ListeLue chercher : absent du cache, jamais annoncé supprimé', () {
    const liste = ListeLue<Brew>(documents: [], fromCache: true);
    expect(liste.chercher('b1'), isA<DocumentAbsentDuCache<Brew>>());
  });
}
