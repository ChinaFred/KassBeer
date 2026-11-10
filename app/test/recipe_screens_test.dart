import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
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
    testWidgets('recette illisible : texte, erreur signalée', (tester) async {
      await open(
        tester,
        '/recettes/r1',
        before: (app) => app.recipes.all.add(
          const ListeLue(
            documents: [
              DocumentInvalide('r1', DocumentIllisible('format_version', 'x')),
            ],
            fromCache: false,
          ),
        ),
      );
      expect(
        find.text(
          'Cette recette ne peut pas s\'afficher. Elle a peut-être été '
          'enregistrée par une version plus récente de Kass\'Beer : mettez '
          'l\'application à jour. L\'erreur est signalée à l\'administrateur.',
        ),
        findsOneWidget,
      );
    });

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

    testWidgets('houblon : chaque moment garde sa durée, un moment jamais '
        'saisi est vide', (tester) async {
      await open(tester, '/recettes/nouvelle');
      await tester.scrollUntilVisible(
        find.text('Ajouter un houblon'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Ajouter un houblon'));
      await tester.pumpAndSettle();
      String textOf(String label) => tester
          .widget<EditableText>(
            find.descendant(
              of: sheetField(label),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      Future<void> moment(String label) async {
        await tester.ensureVisible(inSheet(find.text(label)));
        await tester.tap(inSheet(find.text(label)));
        await tester.pumpAndSettle();
      }

      await tester.enterText(sheetField('Durée d\x27ébullition (min)'), '60');
      await moment('À cru');
      expect(textOf('Durée à cru (jours)'), isEmpty);
      await tester.enterText(sheetField('Durée à cru (jours)'), '3');
      await moment('Whirlpool');
      expect(textOf('Durée d\x27infusion (min)'), isEmpty);
      await moment('Ébullition');
      expect(textOf('Durée d\x27ébullition (min)'), '60');
      await moment('À cru');
      expect(textOf('Durée à cru (jours)'), '3');
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

  group('v0.1.14 — champs BeerJSON', () {
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

    /// Choisit [value] dans la liste déroulante [label] (dans la feuille si
    /// [sheet]).
    Future<void> choose(
      WidgetTester tester,
      String label,
      String value, {
      bool sheet = false,
    }) async {
      final field = find.ancestor(
        of: find.text(label),
        matching: find.byType(DropdownButtonFormField<String?>),
      );
      final target = sheet ? inSheet(field) : field;
      await tester.ensureVisible(target.first);
      await tester.tap(target.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    Future<void> nameAndSave(WidgetTester tester, String name) async {
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Nom').first,
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom').first,
        name,
      );
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
    }

    String errorOf(WidgetTester tester, Finder field) => tester
        .widget<InputDecorator>(
          find.descendant(of: field, matching: find.byType(InputDecorator)),
        )
        .decoration
        .errorText!;

    testWidgets('houblon whirlpool : aide, durée obligatoire de 1 à 600 min, '
        'durée vide au premier passage', (tester) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un houblon');
      await tester.enterText(sheetField('Nom'), 'Saaz');
      await tester.enterText(sheetField('Quantité (g)'), '30');
      await tester.enterText(sheetField('Durée d\'ébullition (min)'), '60');
      await tester.ensureVisible(inSheet(find.text('Whirlpool')));
      await tester.tap(inSheet(find.text('Whirlpool')));
      await tester.pumpAndSettle();
      final infusion = sheetField('Durée d\'infusion (min)');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: infusion,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
      expect(
        inSheet(find.textContaining('Temps entre l\'arrêt du feu')),
        findsOneWidget,
      );
      await tester.ensureVisible(inSheet(find.text('Cônes')));
      await tester.tap(inSheet(find.text('Cônes')));
      await tester.pump();
      Future<void> submit() async {
        final button = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await submit();
      expect(errorOf(tester, infusion), 'Champ obligatoire.');
      await tester.enterText(infusion, '0');
      await submit();
      expect(
        errorOf(tester, infusion),
        'Au moins 1 min. Pour un ajout à l\'arrêt du feu, choisissez '
        'Ébullition et 0 min.',
      );
      await tester.enterText(infusion, '601');
      await submit();
      expect(errorOf(tester, infusion), 'Entre 1 et 600.');
      await tester.enterText(infusion, '12,5');
      await submit();
      expect(errorOf(tester, infusion), 'Nombre entier attendu.');
      await tester.enterText(infusion, '15');
      await submit();
      expect(find.byType(BottomSheet), findsNothing);
      await nameAndSave(tester, 'Blonde');
      final hop = app.recipes.writes.single.content!.hops.single;
      expect((hop.use, hop.timeMin), (HopUse.afterBoil, 15));
    });

    testWidgets('houblon à cru : jours décimaux, minutes entières', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un houblon');
      await tester.enterText(sheetField('Nom'), 'Citra');
      await tester.enterText(sheetField('Quantité (g)'), '50');
      await tester.ensureVisible(inSheet(find.text('À cru')));
      await tester.tap(inSheet(find.text('À cru')));
      await tester.pumpAndSettle();
      await tester.enterText(sheetField('Durée à cru (jours)'), '2,7');
      await tester.ensureVisible(inSheet(find.text('Pellets')));
      await tester.tap(inSheet(find.text('Pellets')));
      await tester.pump();
      final button = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await nameAndSave(tester, 'Houblonnée');
      // 2,7 × 1 440 = 3 888 minutes.
      expect(app.recipes.writes.single.content!.hops.single.timeMin, 3888);
    });

    testWidgets('ajout : durée sans utilisation refusée ; type en tête des '
        'détails', (tester) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un ajout');
      await tester.enterText(sheetField('Nom'), 'Gypse');
      await tester.enterText(sheetField('Quantité (g)'), '5');
      await tester.enterText(sheetField('Durée (min)'), '60');
      final button = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Choisissez une utilisation.')), findsOneWidget);
      await choose(
        tester,
        'Type d\'ajout',
        'Correction de l\'eau',
        sheet: true,
      );
      final use = inSheet(
        find.ancestor(
          of: find.text('Utilisation'),
          matching: find.byType(DropdownButtonFormField<OtherUse?>),
        ),
      );
      await tester.ensureVisible(use);
      await tester.tap(use);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empâtage').last);
      await tester.pumpAndSettle();
      // L'erreur s'efface dès qu'une utilisation est choisie.
      expect(inSheet(find.text('Choisissez une utilisation.')), findsNothing);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.text(
          'Correction de l\'eau · ${formatGrammes(5)} · Empâtage · '
          '${formatMinutes(60)}',
        ),
        findsOneWidget,
      );
      await nameAndSave(tester, 'Eau corrigée');
      final other = app.recipes.writes.single.content!.others.single;
      expect(
        (other.type, other.use, other.timeMin),
        ('water agent', OtherUse.mash, 60),
      );
    });

    testWidgets('ajout : durée vidée, l\'erreur d\'utilisation s\'efface ; '
        '« Après ébullition » sans durée, aide', (tester) async {
      await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un ajout');
      await tester.enterText(sheetField('Nom'), 'Coriandre');
      await tester.enterText(sheetField('Quantité (g)'), '10');
      await tester.enterText(sheetField('Durée (min)'), '5');
      final button = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Choisissez une utilisation.')), findsOneWidget);
      await tester.enterText(sheetField('Durée (min)'), '');
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Choisissez une utilisation.')), findsNothing);
      const help =
          'Sans durée, l\'ajout est enregistré à l\'arrêt du feu (Ébullition, '
          '0 min).';
      expect(inSheet(find.text(help)), findsNothing);
      final use = inSheet(
        find.ancestor(
          of: find.text('Utilisation'),
          matching: find.byType(DropdownButtonFormField<OtherUse?>),
        ),
      );
      await tester.ensureVisible(use);
      await tester.tap(use);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Après ébullition').last);
      await tester.pumpAndSettle();
      expect(inSheet(find.text(help)), findsOneWidget);
      await tester.enterText(sheetField('Durée (min)'), '10');
      await tester.pumpAndSettle();
      expect(inSheet(find.text(help)), findsNothing);
    });

    testWidgets('levure : quantité, type et forme', (tester) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter une levure');
      // Aide seule : le coût compte un sachet par levure, sans calcul sur la masse.
      expect(
        inSheet(
          find.text(
            'Le coût compte un sachet par levure, quelle que soit la quantité.',
          ),
        ),
        findsOneWidget,
      );
      await tester.enterText(sheetField('Nom'), 'US-05');
      await tester.enterText(sheetField('Quantité (g)'), '11,5');
      await tester.enterText(sheetField('Atténuation (%)'), '78');
      await choose(
        tester,
        'Type de levure',
        'Haute fermentation (ale)',
        sheet: true,
      );
      await tester.ensureVisible(inSheet(find.text('Sèche')));
      await tester.tap(inSheet(find.text('Sèche')));
      await tester.pump();
      final button = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Haute fermentation (ale) · ${formatGrammes(11.5)} · atténuation '
          '${formatPourcent(78)} · Sèche',
        ),
        findsOneWidget,
      );
      await nameAndSave(tester, 'Ale');
      final yeast = app.recipes.writes.single.content!.yeasts.single;
      expect((yeast.type, yeast.form, yeast.amountG), ('ale', 'dry', 11.5));
    });

    testWidgets('palier : type, durée entière', (tester) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un palier');
      await tester.enterText(sheetField('Nom'), 'Saccharification');
      await tester.enterText(sheetField('Température (°C)'), '65');
      await tester.enterText(sheetField('Durée (min)'), '60,5');
      await choose(
        tester,
        'Type de palier',
        'Infusion (eau chaude ajoutée)',
        sheet: true,
      );
      // Libellé long dans le menu, court dans le champ.
      expect(inSheet(find.text('Infusion')), findsOneWidget);
      final button = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Nombre entier attendu.')), findsOneWidget);
      await tester.enterText(sheetField('Durée (min)'), '60');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text('Infusion · ${formatCelsius(65)} · ${formatMinutes(60)}'),
        findsOneWidget,
      );
      await nameAndSave(tester, 'Empâtée');
      final step = app.recipes.writes.single.content!.mashSteps.single;
      expect((step.type, step.durationMin), ('infusion', 60));
    });

    testWidgets('général : type de recette, ébullition entière, température '
        'du grain bornée', (tester) async {
      final app = await open(tester, '/recettes/nouvelle');
      await choose(tester, 'Type de recette', 'Tout grain');
      final boil = find.widgetWithText(
        TextFormField,
        'Durée d\'ébullition (min)',
      );
      await tester.enterText(boil, '60,5');
      final grain = find.widgetWithText(
        TextFormField,
        'Température du grain (°C)',
      );
      await tester.scrollUntilVisible(
        grain,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.text(
          'Température des malts au moment de l\'empâtage, souvent celle de la '
          'pièce.',
        ),
        findsOneWidget,
      );
      await tester.enterText(grain, '70');
      await tester.pump();
      await nameAndSave(tester, 'Blonde');
      expect(app.recipes.writes, isEmpty);
      await tester.scrollUntilVisible(
        grain,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(errorOf(tester, grain), 'Entre -20 et 60.');
      await tester.enterText(grain, '-2,5');
      await tester.scrollUntilVisible(
        boil,
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(errorOf(tester, boil), 'Nombre entier attendu.');
      await tester.enterText(boil, '60');
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final content = app.recipes.writes.single.content!;
      expect(
        (content.type, content.boilTimeMin, content.grainTempC),
        ('all grain', 60, -2.5),
      );
      expect(content.mashSteps, isEmpty);
    });

    testWidgets('valeur du schéma hors des listes de l\'éditeur : conservée', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/recettes/m/modifier',
        before: (app) => app.recipes.publish([
          recipe(
            'm',
            const RecipeContent(
              name: 'Pommé',
              type: 'cider',
              yeasts: [YeastLine(name: 'Levure', type: 'wheat', form: 'slant')],
            ),
          ),
        ]),
      );
      // Libellés français des valeurs que l'éditeur ne propose pas.
      expect(find.text('Cidre'), findsOneWidget);
      expect(find.text('cider'), findsNothing);
      final yeastLine = find.text('Levure de blanche · Gélose');
      await tester.scrollUntilVisible(
        yeastLine,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(yeastLine, findsOneWidget);
      // La forme importée reste visible et choisie dans le formulaire.
      await tester.tap(yeastLine);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      final segments = tester.widget<SegmentedButton<String>>(
        inSheet(find.byType(SegmentedButton<String>)),
      );
      expect(segments.selected, {'slant'});
      expect(inSheet(find.text('Gélose')), findsOneWidget);
      expect(inSheet(find.text('Levure de blanche')), findsOneWidget);
      await tester.tap(inSheet(find.text('Annuler')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      final content = app.recipes.writes.single.content!;
      expect(content.type, 'cider');
      expect(
        (content.yeasts.single.type, content.yeasts.single.form),
        ('wheat', 'slant'),
      );
    });

    testWidgets(
      'fiche : type de recette, ajout, levure, température du grain',
      (tester) async {
        final app = await open(tester, '/recettes/r');
        app.recipes.publish([
          recipe(
            'r',
            const RecipeContent(
              name: 'Complète',
              type: 'partial mash',
              grainTempC: 18,
              others: [
                OtherLine(
                  name: 'Gypse',
                  weightG: 5,
                  type: 'water agent',
                  use: OtherUse.mash,
                  timeMin: 60,
                ),
              ],
              yeasts: [
                YeastLine(
                  name: 'US-05',
                  type: 'ale',
                  form: 'dry',
                  attenuationPct: 75,
                  amountG: 11,
                ),
              ],
              mashSteps: [
                MashStep(
                  name: 'Palier',
                  tempC: 65,
                  durationMin: 60,
                  type: 'infusion',
                ),
              ],
            ),
          ),
        ]);
        await tester.pumpAndSettle();
        for (final line in [
          'Empâtage partiel',
          'Correction de l\'eau · ${formatGrammes(5)} · Empâtage · '
              '${formatMinutes(60)}',
          'Haute fermentation (ale) · ${formatGrammes(11)} · atténuation '
              '${formatPourcent(75)} · Sèche',
          'Température du grain',
          formatCelsius(18),
          'Infusion · ${formatCelsius(65)} · ${formatMinutes(60)}',
        ]) {
          await tester.scrollUntilVisible(
            find.text(line),
            200,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text(line), findsOneWidget, reason: line);
        }
      },
    );

    testWidgets('fiche : type de recette absent, « Non renseigné »', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/s');
      app.recipes.publish([
        recipe('s', const RecipeContent(name: 'Sans type')),
      ]);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Type de recette'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      final typeRow = find.ancestor(
        of: find.text('Type de recette'),
        matching: find.byType(Wrap),
      );
      expect(
        find.descendant(of: typeRow, matching: find.text('Non renseigné')),
        findsOneWidget,
      );
    });
  });
}
