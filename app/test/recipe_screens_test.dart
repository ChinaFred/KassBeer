import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_calculations_view.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_editor_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/fakes.dart';

Recipe recipe(
  String id,
  RecipeContent content, {
  String owner = 'uid-brasseur',
  String? ownerName = 'Bruno Brasseur',
}) => Recipe(id: id, ownerUid: owner, ownerName: ownerName, content: content);

const pils = FermentableLine(
  name: 'Pils',
  kind: FermentableKind.malt,
  weightG: 4500,
);

const citra = HopLine(
  name: 'Citra',
  weightG: 20,
  use: HopUse.boil,
  form: HopForm.pellet,
  timeMin: 60,
);

Future<TestApp> open(
  WidgetTester tester,
  String path, {
  double width = 400,
  void Function(TestApp app)? before,
}) async {
  final app = TestApp();
  await app.pump(tester, width: width);
  app.signIn(brewerUser, member: brewerMember);
  before?.call(app);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Finder sheetField(String label) =>
    inSheet(find.widgetWithText(TextFormField, label));

void main() {
  group('liste', () {
    testWidgets('vide : message ; Nouvelle recette', (tester) async {
      await open(tester, '/recettes');
      expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
      expect(find.text('Nouvelle recette'), findsOneWidget);
    });

    testWidgets('illisible : panne et Réessayer', (tester) async {
      await open(
        tester,
        '/recettes',
        before: (app) => app.recipes.all.addError(Exception('refus')),
      );
      expect(find.text(RecipesListScreen.loadError), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('recherche, « Les miennes », auteur, en attente du réseau', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.recipes.publish([
        recipe(
          'z',
          const RecipeContent(name: 'IPA', style: 'IPA', batchVolumeL: 20),
          owner: 'uid-zoe',
          ownerName: 'Zoé',
        ),
        recipe(
          'a',
          const RecipeContent(name: 'Anonyme'),
          owner: 'uid-x',
          ownerName: null,
        ),
        Recipe(
          id: 'm',
          ownerUid: 'uid-brasseur',
          content: const RecipeContent(name: 'Blonde'),
          hasPendingWrites: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('IPA · 20 L · Zoé'), findsOneWidget);
      expect(find.text('Autre brasseur'), findsOneWidget);
      expect(find.text('Vous'), findsOneWidget);
      expect(find.text('En attente du réseau'), findsOneWidget);

      await tester.tap(find.text('Les miennes'));
      await tester.pumpAndSettle();
      expect(find.text('IPA'), findsNothing);
      expect(find.text('Blonde'), findsOneWidget);

      await tester.tap(find.text('Toutes'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher une recette'),
        'stout',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Aucune recette ne correspond à « stout ».'),
        findsOneWidget,
      );
      await tester.tap(find.text('Effacer la recherche'));
      await tester.pumpAndSettle();
      expect(find.text('Blonde'), findsOneWidget);
    });

    testWidgets('« Les miennes » vide', (tester) async {
      final app = await open(tester, '/recettes');
      app.recipes.publish([
        recipe('z', const RecipeContent(name: 'IPA'), owner: 'uid-zoe'),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Les miennes'));
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.mineEmptyMessage), findsOneWidget);
    });
  });

  group('détail et calculs', () {
    testWidgets('calcul indisponible : liste « À compléter » (C7)', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/r');
      app.recipes.publish([
        recipe(
          'r',
          const RecipeContent(
            name: 'Incomplète',
            batchVolumeL: 20,
            fermentables: [pils],
            hops: [
              HopLine(
                name: 'Citra',
                weightG: 20,
                use: HopUse.boil,
                form: HopForm.pellet,
                timeMin: 60,
              ),
            ],
          ),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Indisponible'), findsNWidgets(5));
      expect(find.text('À compléter'), findsOneWidget);
      for (final line in [
        'Aucun équipement choisi.',
        'Rendement d\'extrait non renseigné : Pils.',
        'Aucune levure.',
        'Acides alpha non renseignés : Citra.',
        'Couleur non renseignée : Pils.',
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.text('Compléter la recette'), findsOneWidget);
      // Aucune valeur de repli : aucune densité affichée.
      expect(find.textContaining('1057'), findsNothing);
      expect(app.errors.reports, isEmpty);
    });

    testWidgets(
      'équipement supprimé (E10), puis indisponible hors ligne (H4)',
      (tester) async {
        final app = await open(tester, '/recettes/r');
        app.recipes.publish([
          recipe(
            'r',
            const RecipeContent(
              name: 'Orpheline',
              batchVolumeL: 20,
              equipmentId: 'disparu',
              fermentables: [
                FermentableLine(
                  name: 'Pils',
                  kind: FermentableKind.malt,
                  weightG: 4500,
                  ebc: 3.5,
                  yieldPct: 80,
                ),
              ],
            ),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(
          find.text('L\'équipement de cette recette n\'existe plus.'),
          findsOneWidget,
        );
        // DI, DF et degré en panne ; sans houblon d'ébullition, 0 IBU ; la
        // couleur ne dépend pas de l'équipement (C6).
        expect(find.text('Indisponible'), findsNWidgets(3));
        await tester.scrollUntilVisible(find.text('Équipement supprimé'), 200);
        expect(find.text('Équipement supprimé'), findsOneWidget);

        app.signIn(brewerUser, member: brewerMember, fromCache: true);
        app.equipment.publish(const [], fromCache: true);
        await tester.pumpAndSettle();
        // Ligne « Équipement » de la section Général, déjà à l'écran.
        expect(find.text('Équipement indisponible hors ligne'), findsOneWidget);
        expect(find.text('Équipement supprimé'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Équipement indisponible hors ligne.'),
          -200,
        );
        expect(
          find.text('L\'équipement de cette recette n\'existe plus.'),
          findsNothing,
        );
      },
    );

    testWidgets('recette complète : cinq valeurs, rien à compléter', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/r');
      app.equipment.publish([
        const Equipment(
          id: 'e',
          ownerUid: 'uid-brasseur',
          content: EquipmentContent(
            name: 'Grainfather',
            kind: EquipmentKind.allInOne,
            mashEfficiencyPct: 72,
          ),
        ),
      ]);
      app.recipes.publish([
        recipe(
          'r',
          const RecipeContent(
            name: 'Complète',
            batchVolumeL: 20,
            boilTimeMin: 60,
            equipmentId: 'e',
            fermentables: [
              FermentableLine(
                name: 'Pils',
                kind: FermentableKind.malt,
                weightG: 4500,
                ebc: 3.5,
                yieldPct: 80,
              ),
            ],
            hops: [
              HopLine(
                name: 'Citra',
                weightG: 20,
                alphaPct: 12,
                use: HopUse.boil,
                form: HopForm.pellet,
                timeMin: 60,
              ),
            ],
            yeasts: [YeastLine(name: 'US-05', attenuationPct: 78)],
          ),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Indisponible'), findsNothing);
      expect(find.text('À compléter'), findsNothing);
      expect(
        find.text('Pour 20 L · Grainfather (72 %) · US-05 78 %'),
        findsOneWidget,
      );
    });

    testWidgets('recette d\'un autre : lecture seule, Dupliquer à mon nom', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/z');
      app.recipes.publish([
        recipe(
          'z',
          const RecipeContent(name: 'IPA', fermentables: [pils]),
          owner: 'uid-zoe',
          ownerName: 'Zoé',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Recette de Zoé'), findsOneWidget);
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Supprimer'), findsNothing);
      expect(find.text('Compléter la recette'), findsNothing);
      await tester.tap(find.text('Dupliquer'));
      await tester.pumpAndSettle();
      final write = app.recipes.writes.single;
      expect(write.kind, 'duplicate');
      expect(write.ownerUid, 'uid-brasseur');
      expect(write.ownerName, 'Bruno Brasseur');
      expect(write.content!.name, 'Copie de IPA');
      expect(find.text(RecipeDetailScreen.duplicated), findsOneWidget);

      app.container.read(routerProvider).go('/recettes/z/modifier');
      await tester.pumpAndSettle();
      expect(find.text(RecipeEditorScreen.readOnlyMessage), findsOneWidget);
      expect(find.text('Voir la recette'), findsOneWidget);
    });

    testWidgets('recette absente du serveur ; absente du cache hors ligne', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/x');
      expect(
        find.text('Cette recette n\'existe pas ou a été supprimée.'),
        findsOneWidget,
      );
      app.signIn(brewerUser, member: brewerMember, fromCache: true);
      app.recipes.publish(const [], fromCache: true);
      await tester.pumpAndSettle();
      expect(find.text('Recette indisponible hors ligne.'), findsOneWidget);
    });

    testWidgets('suppression par l\'auteur après confirmation', (tester) async {
      final app = await open(tester, '/recettes/m');
      app.recipes.publish([recipe('m', const RecipeContent(name: 'Blonde'))]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer « Blonde » ?'), findsOneWidget);
      expect(find.text(RecipeDetailScreen.deleteMessage), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(app.recipes.writes.single.kind, 'delete');
    });

    testWidgets('refus du serveur annoncé', (tester) async {
      final app = await open(tester, '/recettes/m');
      app.recipes.publish([recipe('m', const RecipeContent(name: 'Blonde'))]);
      app.recipes.serverAnswer = () async => throw Exception('refus');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();
      expect(
        find.text('La suppression de « Blonde » a échoué.'),
        findsOneWidget,
      );
    });
  });

  group('éditeur', () {
    Future<void> openSheet(WidgetTester tester, String button) async {
      await tester.scrollUntilVisible(
        find.text(button),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    }

    testWidgets('malts : « Ajouter et continuer » puis « Ajouter », tri par '
        'masse', (tester) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un malt ou un sucre');
      await tester.enterText(sheetField('Nom'), 'Munich');
      await tester.enterText(sheetField('Quantité (kg)'), '1.5');
      await tester.tap(inSheet(find.text('Ajouter et continuer')));
      await tester.pumpAndSettle();
      // La feuille reste ouverte, vidée, curseur sur « Nom ».
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('« Munich » ajouté.'), findsOneWidget);
      final name = tester.widget<EditableText>(
        find.descendant(
          of: sheetField('Nom'),
          matching: find.byType(EditableText),
        ),
      );
      expect(name.controller.text, isEmpty);
      expect(name.focusNode.hasFocus, isTrue);

      await tester.enterText(sheetField('Nom'), 'Pils');
      await tester.enterText(sheetField('Quantité (kg)'), '4,5');
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Ajouter')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Malts et sucres (2)'), findsOneWidget);
      final pilsTop = tester.getTopLeft(find.text('Pils')).dy;
      final munichTop = tester.getTopLeft(find.text('Munich')).dy;
      expect(pilsTop, lessThan(munichTop));

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Nom').first,
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom').first,
        'Blonde',
      );
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final write = app.recipes.writes.single;
      expect(write.kind, 'create');
      expect(write.content!.fermentables.map((f) => f.weightG), [4500, 1500]);
      expect(write.ownerName, 'Bruno Brasseur');
      expect(find.text(RecipeDetailScreen.saved), findsOneWidget);
    });

    testWidgets('houblon « 22.4 » et « 22,4 » : 22,4 g ; « 1.234,5 » refusé', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un houblon');
      Future<void> hop(
        String quantity, {
        bool continuer = true,
        bool pickForm = true,
      }) async {
        await tester.enterText(sheetField('Nom'), 'Citra');
        await tester.enterText(sheetField('Quantité (g)'), quantity);
        await tester.enterText(sheetField('Durée d\'ébullition (min)'), '10');
        if (pickForm) {
          await tester.ensureVisible(inSheet(find.text('Pellets')));
          await tester.tap(inSheet(find.text('Pellets')));
          await tester.pump();
        }
        final button = continuer
            ? inSheet(find.text('Ajouter et continuer'))
            : inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await hop('1.234,5', pickForm: false);
      expect(inSheet(find.text('Nombre illisible.')), findsOneWidget);
      expect(inSheet(find.text('Choisissez une forme.')), findsOneWidget);
      expect(find.text('Houblons (0)'), findsOneWidget);
      await hop('22.4');
      await hop('22,4', continuer: false);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Houblons (2)'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Nom').first,
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom').first,
        'Houblonnée',
      );
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.recipes.writes.single.content!.hops.map((h) => h.weightG), [
        22.4,
        22.4,
      ]);
    });

    testWidgets('nom manquant : message, rien n\'est enregistré', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/nouvelle');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Donnez un nom à la recette.'), findsOneWidget);
      expect(app.recipes.writes, isEmpty);
    });

    testWidgets('nouvelle recette : mon seul équipement présélectionné', (
      tester,
    ) async {
      await open(
        tester,
        '/recettes/nouvelle',
        before: (app) => app.equipment.publish([
          const Equipment(
            id: 'e',
            ownerUid: 'uid-brasseur',
            content: EquipmentContent(
              name: 'Grainfather',
              kind: EquipmentKind.allInOne,
            ),
          ),
        ]),
      );
      expect(find.text('Grainfather'), findsOneWidget);
      expect(find.text('Aucun équipement'), findsNothing);
    });

    testWidgets('modification : owner et contenu ; barre des calculs', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/recettes/m/modifier',
        before: (app) => app.recipes.publish([
          recipe(
            'm',
            const RecipeContent(
              name: 'Blonde',
              batchVolumeL: 20,
              fermentables: [pils],
              hops: [citra],
            ),
          ),
        ]),
      );
      expect(find.text('Modifier la recette'), findsOneWidget);
      expect(find.textContaining('DI —'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final write = app.recipes.writes.single;
      expect(write.kind, 'update');
      expect(write.id, 'm');
      expect(write.content!.hops.single.name, 'Citra');
    });
  });

  group('disposition', () {
    const full = RecipeContent(
      name: 'Complète',
      batchVolumeL: 20,
      fermentables: [pils],
      hops: [citra],
      mashSteps: [MashStep(name: 'Empâtage', tempC: 67, durationMin: 60)],
    );

    testWidgets(
      'éditeur au-delà de 840 px : panneau des calculs, pas de barre',
      (tester) async {
        await open(
          tester,
          '/recettes/m/modifier',
          width: 1200,
          before: (app) => app.recipes.publish([recipe('m', full)]),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Calculs'), findsOneWidget);
        expect(find.textContaining('DI —'), findsNothing);
        expect(find.text('Densité initiale'), findsOneWidget);
      },
    );

    testWidgets('texte à 200 % : détail et éditeur sans débordement', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await open(
        tester,
        '/recettes/m',
        before: (app) => app.recipes.publish([recipe('m', full)]),
      );
      expect(tester.takeException(), isNull);
      app.container.read(routerProvider).go('/recettes/m/modifier');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('corrections de relecture', () {
    const blonde = RecipeContent(
      name: 'Blonde',
      batchVolumeL: 20,
      fermentables: [pils],
      hops: [citra],
    );

    testWidgets(
      'lecteur d\x27écran : ligne et barre des calculs portent l\x27appui',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await open(
          tester,
          '/recettes/m/modifier',
          before: (app) => app.recipes.publish([recipe('m', blonde)]),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Pils, '))),
          matchesSemantics(
            isButton: true,
            hasTapAction: true,
            label: 'Pils, Malt, 4,5 kg. Modifier.',
          ),
        );
        expect(
          tester.getSemantics(
            find.bySemanticsLabel(RegExp('Ouvrir le détail des calculs')),
          ),
          matchesSemantics(isButton: true, hasTapAction: true),
        );
        semantics.dispose();
      },
    );

    testWidgets('nom manquant : focus sur « Nom »', (tester) async {
      await open(tester, '/recettes/nouvelle');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final name = tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Nom').first,
          matching: find.byType(EditableText),
        ),
      );
      expect(name.focusNode.hasFocus, isTrue);
    });

    testWidgets('Dupliquer : un double appui crée une seule copie', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/m');
      app.recipes.publish([recipe('m', blonde)]);
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      app.auth.tokenGate = gate;
      await tester.tap(find.text('Dupliquer'));
      await tester.pump();
      expect(find.text('Duplication'), findsOneWidget);
      expect(find.text('Dupliquer'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(app.auth.tokenReads, 1);
      expect(
        app.recipes.writes.where((w) => w.kind == 'duplicate'),
        hasLength(1),
      );
    });

    testWidgets('houblon : passer à « À cru » vide la durée', (tester) async {
      await open(tester, '/recettes/nouvelle');
      await tester.scrollUntilVisible(
        find.text('Ajouter un houblon'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Ajouter un houblon'));
      await tester.pumpAndSettle();
      await tester.enterText(sheetField('Durée d\x27ébullition (min)'), '60');
      await tester.ensureVisible(inSheet(find.text('À cru')));
      await tester.tap(inSheet(find.text('À cru')));
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(
        find.descendant(
          of: sheetField('Durée à cru (jours)'),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, isEmpty);
    });

    test('calcul refusé : un seul rapport par recette et par champ', () {
      final errors = RecordingErrorReportService();
      final reported = <String>{};
      const huge = RecipeContent(
        name: 'Sirop',
        batchVolumeL: 1,
        fermentables: [
          FermentableLine(
            name: 'Sucre',
            kind: FermentableKind.sugar,
            weightG: 20000,
            yieldPct: 100,
          ),
        ],
      );
      for (var i = 0; i < 3; i++) {
        final result = evaluerRecette(
          huge,
          const SansEquipement(),
          errors: errors,
          reported: reported,
          recipeKey: 'r1',
        );
        expect(result, isA<CalculsImpossibles>());
      }
      expect(errors.reports, hasLength(1));
      evaluerRecette(
        huge,
        const SansEquipement(),
        errors: errors,
        reported: reported,
        recipeKey: 'r2',
      );
      expect(errors.reports, hasLength(2));
    });
  });
}
