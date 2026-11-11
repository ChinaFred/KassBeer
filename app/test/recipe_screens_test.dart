import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/presentation/segments.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/champ_bibliotheque.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/contenu_recette.dart';
import 'package:kass_beer/features/recipes/presentation/ingredient_forms.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_calculations_view.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_editor_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

Recipe recipe(
  String id,
  RecipeContent content, {
  String owner = 'uid-brasseur',
  String? ownerName = 'Bruno Brasseur',
}) => Recipe(id: id, ownerUid: owner, ownerName: ownerName, content: content);

const pils = FermentableLine(name: 'Pils', type: 'grain', weightG: 4500);

const citra = HopLine(
  name: 'Citra',
  amount: Quantite.grammes(20),
  use: HopUse.boil,
  form: 'pellet',
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
  group('outils de la v0.1.17', () {
    test(
      'segmentsTiennent : largeur du plus large libellé, échelle comprise',
      () {
        // Police de test : chaque caractère a la largeur de la taille du texte.
        bool tient(List<String> labels, double maxWidth, double scale) =>
            segmentsTiennent(
              labels: labels,
              style: const TextStyle(fontSize: 14),
              scaler: TextScaler.linear(scale),
              textDirection: TextDirection.ltr,
              maxWidth: maxWidth,
            );
        // 2 × (2 × 14 + 55) = 166.
        expect(tient(const ['g', 'ml'], 166, 1), isTrue);
        expect(tient(const ['g', 'ml'], 165, 1), isFalse);
        // À 200 % : 2 × (2 × 28 + 55) = 222.
        expect(tient(const ['g', 'ml'], 200, 2), isFalse);
        expect(
          tient(const ['Ébullition', 'Whirlpool', 'À cru'], 360, 2),
          isFalse,
        );
      },
    );

    test('en-tête des houblons : masse des houblons pesés seuls', () {
      HopLine h(Quantite q) =>
          HopLine(name: 'H', amount: q, use: HopUse.boil, form: 'pellet');
      expect(enteteHoublons(const []), isNull);
      expect(
        enteteHoublons([
          h(const Quantite.grammes(20)),
          h(const Quantite.grammes(5)),
        ]),
        '2 · ${formatGrammes(25)}',
      );
      expect(
        enteteHoublons([
          h(const Quantite.grammes(20)),
          h(const Quantite.litres(0.005)),
        ]),
        '2 dont 1 en volume · ${formatGrammes(20)}',
      );
      expect(enteteHoublons([h(const Quantite.litres(0.005))]), '1 en volume');
    });
  });

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
                amount: Quantite.grammes(20),
                use: HopUse.boil,
                form: 'pellet',
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
                  type: 'grain',
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
                type: 'grain',
                weightG: 4500,
                ebc: 3.5,
                yieldPct: 80,
              ),
            ],
            hops: [
              HopLine(
                name: 'Citra',
                amount: Quantite.grammes(20),
                alphaPct: 12,
                use: HopUse.boil,
                form: 'pellet',
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
      expect(app.recipes.writes.single.content!.hops.map((h) => h.amount), [
        const Quantite.grammes(22.4),
        const Quantite.grammes(22.4),
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
            type: 'sugar',
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

  group('v0.1.15 — champs BeerJSON', () {
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
      expect(
        (yeast.type, yeast.form, yeast.amount),
        ('ale', 'dry', const Quantite.grammes(11.5)),
      );
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
      await tester.ensureVisible(inSheet(find.text('Annuler')));
      await tester.pumpAndSettle();
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
                  amount: Quantite.grammes(5),
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
                  amount: Quantite.grammes(11),
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

    // v0.1.17 — valeurs importées (L2a d'ADR-005).
    const importee = RecipeContent(
      name: 'Importée',
      author: 'Brasseuse Fictive',
      batchVolumeL: 20,
      boilTimeMin: 60,
      fermentables: [
        FermentableLine(
          name: 'Extrait sec',
          type: 'dry extract',
          weightG: 3000,
          ebc: 6,
          yieldPct: 95,
        ),
        FermentableLine(
          name: 'Sirop maison',
          type: 'other',
          weightG: 200,
          ebc: 2,
          yieldPct: 80,
        ),
      ],
      hops: [
        HopLine(
          name: 'Saaz',
          amount: Quantite.grammes(20),
          use: HopUse.mash,
          form: 'plug',
          alphaPct: 3.5,
          timeMin: 60,
        ),
        HopLine(
          name: 'Cascade',
          amount: Quantite.grammes(10),
          use: HopUse.boil,
          form: 'powder',
          alphaPct: 6,
          timeMin: 10,
        ),
        HopLine(
          name: 'Extrait de houblon',
          amount: Quantite.litres(0.005),
          use: HopUse.boil,
          form: 'extract',
          alphaPct: 50,
          timeMin: 60,
        ),
        HopLine(
          name: 'Citra',
          amount: Quantite.grammes(50),
          use: HopUse.dryHop,
          form: 'pellet',
          timeMin: 4320,
          dayMin: 2880,
        ),
      ],
      others: [
        OtherLine(
          name: 'Acide lactique',
          amount: Quantite.litres(0.005),
          type: 'water agent',
          use: OtherUse.mash,
          timeMin: 60,
        ),
      ],
      yeasts: [
        YeastLine(
          name: 'Levure liquide',
          type: 'wheat',
          attenuationPct: 75,
          amount: Quantite.litres(0.1),
        ),
      ],
    );

    Future<void> voir(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(finder, findsOneWidget);
    }

    testWidgets('fiche : libellés, quantités en volume, À compléter, auteur', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/i');
      app.recipes.publish([recipe('i', importee)]);
      await tester.pumpAndSettle();
      for (final text in [
        'Nature à préciser : Sirop maison.',
        'Moment non pris en charge par le calcul : Saaz.',
        'Forme non prise en charge par le calcul : Cascade.',
        houblonsEnVolume('Extrait de houblon'),
        'Auteur indiqué par le fichier importé',
        'Brasseuse Fictive',
        'Extrait sec · ${formatKilogrammes(3000)} · ${formatEbc(6)} · '
            'rendement ${formatPourcent(95)}',
        'Empâtage ${formatMinutes(60)} · ${formatGrammes(20)} · '
            '${formatPourcent(3.5)} alpha · Cônes pressés',
        'Ébullition ${formatMinutes(60)} · 5${nbsp}ml · '
            '${formatPourcent(50)} alpha · Extrait · '
            'non compté dans l\'amertume (mesuré en volume)',
        'À cru ${formatJours(4320)} · ajout au jour 2 · ${formatGrammes(50)} · '
            'alpha non renseigné · Pellets',
        'Correction de l\'eau · 5${nbsp}ml · Empâtage · ${formatMinutes(60)}',
        'Levure de blanche · 100${nbsp}ml · atténuation ${formatPourcent(75)}',
      ]) {
        await voir(tester, find.text(text));
      }
    });

    testWidgets(
      'éditeur : enregistrée sans changement, recipe identique (I9)',
      (tester) async {
        final app = await open(
          tester,
          '/recettes/i/modifier',
          before: (app) => app.recipes.publish([recipe('i', importee)]),
        );
        await tester.tap(find.text('Enregistrer'));
        await tester.pumpAndSettle();
        final written = app.recipes.writes.single.content!;
        expect(
          written.toFirestore(creation: false)['recipe'],
          importee.toFirestore(creation: false)['recipe'],
        );
        expect(written.author, 'Brasseuse Fictive');
      },
    );

    testWidgets('éditeur : houblon à l\'empâtage et extrait en ml gardés à '
        'l\'enregistrement du formulaire', (tester) async {
      final app = await open(
        tester,
        '/recettes/i/modifier',
        before: (app) => app.recipes.publish([recipe('i', importee)]),
      );
      for (final name in ['Saaz', 'Extrait de houblon', 'Citra']) {
        final line = find.text(name);
        await tester.scrollUntilVisible(
          line,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(line);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        if (name == 'Saaz') {
          expect(inSheet(find.text('Empâtage')), findsOneWidget);
          expect(inSheet(find.text('Cônes pressés')), findsOneWidget);
        }
        if (name == 'Extrait de houblon') {
          expect(sheetField('Quantité (ml)'), findsOneWidget);
        }
        final save = inSheet(find.widgetWithText(FilledButton, 'Enregistrer'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Enregistrer').first);
      await tester.pumpAndSettle();
      // Tri de l'éditeur après chaque formulaire : empâtage, ébullition de la
      // plus longue à la plus courte, à cru.
      final hops = app.recipes.writes.single.content!.hops;
      expect(hops.map((h) => (h.name, h.use, h.form, h.amount, h.dayMin)), [
        ('Saaz', HopUse.mash, 'plug', const Quantite.grammes(20), null),
        (
          'Extrait de houblon',
          HopUse.boil,
          'extract',
          const Quantite.litres(0.005),
          null,
        ),
        ('Cascade', HopUse.boil, 'powder', const Quantite.grammes(10), null),
        ('Citra', HopUse.dryHop, 'pellet', const Quantite.grammes(50), 2880),
      ]);
    });

    testWidgets('segments en colonne quand ils ne tiennent pas : 360 dp à '
        '200 %', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, '/recettes/nouvelle', width: 360);
      await openSheet(tester, 'Ajouter un houblon');
      final usage = tester.widget<SegmentedButton<HopUse>>(
        inSheet(find.byType(SegmentedButton<HopUse>)),
      );
      expect(usage.direction, Axis.vertical);
      expect(tester.takeException(), isNull);
    });

    testWidgets('segments côte à côte quand ils tiennent : g et ml à 400 dp', (
      tester,
    ) async {
      await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un ajout');
      final unite = tester.widget<SegmentedButton<UniteSaisie>>(
        inSheet(find.byType(SegmentedButton<UniteSaisie>)),
      );
      expect(unite.direction, Axis.horizontal);
    });

    testWidgets('unité g ou ml lue « grammes », « millilitres », avant la '
        'quantité', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un ajout');
      expect(inSheet(find.bySemanticsLabel('grammes')), findsOneWidget);
      expect(inSheet(find.bySemanticsLabel('millilitres')), findsOneWidget);
      final unite = tester.getTopLeft(
        inSheet(find.text('Unité de la quantité')),
      );
      final quantite = tester.getTopLeft(sheetField('Quantité (g)'));
      expect(unite.dy, lessThan(quantite.dy));
      semantics.dispose();
    });

    testWidgets('houblon d\'ébullition en poudre : avertissement sous la forme', (
      tester,
    ) async {
      await open(
        tester,
        '/recettes/p/modifier',
        before: (app) => app.recipes.publish([
          recipe(
            'p',
            const RecipeContent(
              name: 'Poudre',
              hops: [
                HopLine(
                  name: 'Cascade',
                  amount: Quantite.grammes(10),
                  use: HopUse.boil,
                  form: 'powder',
                  alphaPct: 6,
                  timeMin: 10,
                ),
              ],
            ),
          ),
        ]),
      );
      final line = find.text('Cascade');
      await tester.scrollUntilVisible(
        line,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(line);
      await tester.pumpAndSettle();
      final message = inSheet(
        find.text(
          'Forme non prise en charge par le calcul de l\'amertume : choisissez '
          'Pellets ou Cônes.',
        ),
      );
      await tester.ensureVisible(message);
      expect(message, findsOneWidget);
      await tester.tap(inSheet(find.text('Pellets')));
      await tester.pumpAndSettle();
      expect(message, findsNothing);
    });

    testWidgets('extrait pesé : avertissement qui propose les ml, pas une '
        'autre forme', (tester) async {
      await open(
        tester,
        '/recettes/e/modifier',
        before: (app) => app.recipes.publish([
          recipe(
            'e',
            const RecipeContent(
              name: 'Extrait',
              hops: [
                HopLine(
                  name: 'Extrait CO2',
                  amount: Quantite.grammes(2),
                  use: HopUse.boil,
                  form: 'extract',
                  alphaPct: 50,
                  timeMin: 60,
                ),
              ],
            ),
          ),
        ]),
      );
      final line = find.text('Extrait CO2');
      await tester.scrollUntilVisible(
        line,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(line);
      await tester.pumpAndSettle();
      final message = inSheet(
        find.text(
          'Forme non prise en charge par le calcul de l\'amertume. Pour un '
          'extrait, indiquez la quantité en ml.',
        ),
      );
      await tester.ensureVisible(message);
      expect(message, findsOneWidget);
      await tester.tap(inSheet(find.text('ml')));
      await tester.pumpAndSettle();
      expect(message, findsNothing);
    });

    testWidgets('ajout et levure saisis en ml : enregistrés en litres', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un ajout');
      await tester.enterText(sheetField('Nom'), 'Acide lactique');
      await tester.tap(inSheet(find.text('ml')));
      await tester.pumpAndSettle();
      await tester.enterText(sheetField('Quantité (ml)'), '5');
      final add = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await openSheet(tester, 'Ajouter une levure');
      await tester.enterText(sheetField('Nom'), 'WLP400');
      await tester.tap(inSheet(find.text('ml')));
      await tester.pumpAndSettle();
      await tester.enterText(sheetField('Quantité (ml)'), '125');
      final addYeast = inSheet(find.widgetWithText(FilledButton, 'Ajouter'));
      await tester.ensureVisible(addYeast);
      await tester.tap(addYeast);
      await tester.pumpAndSettle();
      await nameAndSave(tester, 'Blanche');
      final content = app.recipes.writes.single.content!;
      expect(content.others.single.amount, const Quantite.litres(0.005));
      expect(content.yeasts.single.amount, const Quantite.litres(0.125));
    });
  });

  group('houblon sans forme (recette publique dupliquée)', () {
    const sansForme = RecipeContent(
      name: 'Blonde du Verger',
      batchVolumeL: 23,
      fermentables: [pils],
      hops: [
        HopLine(
          name: 'Houblon Alpha',
          amount: Quantite.grammes(30),
          use: HopUse.boil,
          form: null,
          alphaPct: 8.2,
          timeMin: 60,
        ),
      ],
    );

    testWidgets('fiche : « Forme du houblon à compléter », IBU indisponible', (
      tester,
    ) async {
      await open(
        tester,
        '/recettes/v',
        before: (app) => app.recipes.publish([recipe('v', sansForme)]),
      );
      await tester.scrollUntilVisible(
        find.text('Forme du houblon à compléter : Houblon Alpha.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Forme non prise en charge par le calcul : Houblon Alpha.'),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.textContaining('forme non renseignée'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    });

    testWidgets('éditeur : la copie s\'ouvre, la forme se complète', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/recettes/v/modifier',
        before: (app) => app.recipes.publish([recipe('v', sansForme)]),
      );
      final line = find.text('Houblon Alpha');
      await tester.scrollUntilVisible(
        line,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(line);
      await tester.pumpAndSettle();
      final save = inSheet(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      // Aucune forme inventée : la ligne modifiée en demande une.
      expect(inSheet(find.text('Choisissez une forme.')), findsOneWidget);
      await tester.ensureVisible(inSheet(find.text('Pellets')));
      await tester.tap(inSheet(find.text('Pellets')));
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('Enregistrer').first);
      await tester.pumpAndSettle();
      final hops = app.recipes.writes.single.content!.hops;
      expect(hops.single.form, 'pellet');
      expect(hops.single.toFirestore()['form'], 'pellet');
    });

    test('lecture et écriture sans forme : aucune clé `form` inventée', () {
      final data = sansForme.toFirestore(creation: true);
      final hop =
          (((data['recipe']! as Map)['ingredients'] as Map)['hop_additions']
                      as List)
                  .single
              as Map;
      expect(hop.containsKey('form'), isFalse);
      final relue = RecipeContent.fromFirestore({
        ...data,
        'owner_uid': 'uid-brasseur',
      });
      expect(relue.hops.single.form, isNull);
      expect(relue.hops.single.calcForm, isNull);
    });
  });

  group('Bibliothèque dans l\'éditeur (ADR-005, E2 et E3)', () {
    void bibliotheque(TestApp app) {
      void lu(NatureReferentiel nature, List<Object?> entries) =>
          app.library.index[nature] = DocumentTrouve(
            IndexReferentiel.fromFirestore(nature, indexDoc(entries)),
          );
      lu(NatureReferentiel.fermentables, [
        {
          'id': 'fermentable-pilsner-fictif',
          'name': 'Pilsner Fictif',
          'aliases': ['Pils Fictif'],
          'type': 'grain',
          'yield': 81,
          'color': 3.9,
        },
        {
          'id': 'fermentable-miel-fictif',
          'name': 'Miel Fictif',
          'type': 'honey',
          'yield': 75,
        },
      ]);
      lu(NatureReferentiel.hops, [
        {
          'id': 'hop-cascade',
          'name': 'Cascade',
          'form': 'pellet',
          'alpha': 6.5,
        },
      ]);
      lu(NatureReferentiel.cultures, [
        {
          'id': 'culture-fermentis-us05-safale-american',
          'name': 'Safale American',
          'producer': 'Fermentis',
          'product_id': 'US-05',
          'type': 'ale',
          'form': 'dry',
          'attenuation': 81,
        },
      ]);
      lu(NatureReferentiel.miscs, [
        {
          'id': 'misc-coriandre-fictive',
          'name': 'Coriandre Fictive',
          'type': 'spice',
        },
      ]);
      app.library.index[NatureReferentiel.styles] = DocumentTrouve(
        IndexReferentiel.fromFirestore(NatureReferentiel.styles, stylesIndex),
      );
    }

    Future<void> openSheet(WidgetTester tester, String button) async {
      await tester.scrollUntilVisible(
        find.text(button),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }

    String texteDe(WidgetTester tester, Finder field) => tester
        .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        )
        .controller
        .text;

    testWidgets(
      'malt : suggestion par alias ; valeurs vides remplies ; « Reprendre »',
      (tester) async {
        final app = await open(
          tester,
          '/recettes/nouvelle',
          before: bibliotheque,
        );
        await openSheet(tester, 'Ajouter un malt ou un sucre');
        expect(app.library.indexReads, [NatureReferentiel.fermentables]);
        await tester.enterText(sheetField('Nom'), 'pils fic');
        await tester.pumpAndSettle();
        expect(find.text('Pilsner Fictif'), findsOneWidget);
        await tester.tap(find.text('Pilsner Fictif'));
        await tester.pumpAndSettle();
        expect(texteDe(tester, sheetField('Nom')), 'Pilsner Fictif');
        // Les seules valeurs remplies, sous « Nom ».
        expect(
          find.text(
            'Couleur et rendement d\'extrait repris de la Bibliothèque.',
          ),
          findsOneWidget,
        );
        expect(texteDe(tester, sheetField('Couleur (EBC)')), '3,9');
        expect(texteDe(tester, sheetField('Rendement d\'extrait (%)')), '81');
        expect(find.text(kReprendreBibliotheque), findsNothing);
        // Valeur saisie : jamais remplacée sans geste.
        await tester.enterText(sheetField('Couleur (EBC)'), '5');
        await tester.pumpAndSettle();
        expect(find.text(kReprendreBibliotheque), findsOneWidget);
        await tester.tap(find.text(kReprendreBibliotheque));
        await tester.pumpAndSettle();
        expect(texteDe(tester, sheetField('Couleur (EBC)')), '3,9');
        expect(find.text(kReprendreBibliotheque), findsNothing);
        await tester.enterText(sheetField('Quantité (kg)'), '4');
        await tester.ensureVisible(
          inSheet(find.widgetWithText(FilledButton, 'Ajouter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Ajouter')));
        await tester.pumpAndSettle();
        expect(find.text('Pilsner Fictif'), findsOneWidget);
      },
    );

    testWidgets('malt saisi avant la suggestion : la saisie reste', (
      tester,
    ) async {
      await open(tester, '/recettes/nouvelle', before: bibliotheque);
      await openSheet(tester, 'Ajouter un malt ou un sucre');
      await tester.enterText(sheetField('Couleur (EBC)'), '10');
      await tester.tap(inSheet(find.text('Sucre')));
      await tester.pumpAndSettle();
      await tester.enterText(sheetField('Nom'), 'Miel');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miel Fictif'));
      await tester.pumpAndSettle();
      // Couleur et nature déjà choisies : gardées ; rendement vide : rempli.
      expect(texteDe(tester, sheetField('Couleur (EBC)')), '10');
      expect(texteDe(tester, sheetField('Rendement d\'extrait (%)')), '75');
      // Nature Miel hors de Malt et Sucre, Sucre choisi : ni reprise ni
      // « Reprendre ».
      expect(inSheet(find.text('Miel')), findsNothing);
      expect(find.text(kReprendreBibliotheque), findsNothing);
      expect(
        find.text('Rendement d\'extrait repris de la Bibliothèque.'),
        findsOneWidget,
      );
    });

    testWidgets('houblon et levure : valeurs de la Bibliothèque', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/recettes/nouvelle',
        before: bibliotheque,
      );
      await openSheet(tester, 'Ajouter un houblon');
      await tester.enterText(sheetField('Nom'), 'casc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cascade'));
      await tester.pumpAndSettle();
      expect(texteDe(tester, sheetField('Acides alpha (%)')), '6,5');
      await tester.enterText(sheetField('Quantité (g)'), '20');
      await tester.enterText(sheetField('Durée d\'ébullition (min)'), '60');
      await tester.ensureVisible(
        inSheet(find.widgetWithText(FilledButton, 'Ajouter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Ajouter')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await openSheet(tester, 'Ajouter une levure');
      await tester.enterText(sheetField('Nom'), 'US-05');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Safale American'));
      await tester.pumpAndSettle();
      expect(texteDe(tester, sheetField('Atténuation (%)')), '81');
      await tester.ensureVisible(
        inSheet(find.widgetWithText(FilledButton, 'Ajouter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Ajouter')));
      await tester.pumpAndSettle();

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
      final content = app.recipes.writes.single.content!;
      expect(content.hops.single.form, 'pellet');
      expect(content.hops.single.alphaPct, 6.5);
      expect(content.yeasts.single.name, 'Safale American');
      expect(content.yeasts.single.type, 'ale');
      expect(content.yeasts.single.form, 'dry');
    });

    testWidgets('style : choix par code, nom exact enregistré', (tester) async {
      final app = await open(
        tester,
        '/recettes/nouvelle',
        before: bibliotheque,
      );
      final style = find.widgetWithText(TextFormField, 'Style (facultatif)');
      await tester.ensureVisible(style);
      await tester.tap(style);
      await tester.pumpAndSettle();
      expect(app.library.indexReads, contains(NatureReferentiel.styles));
      await tester.enterText(style, '21a');
      await tester.pumpAndSettle();
      expect(find.text('21A · IPA'), findsOneWidget);
      // La liste est nommée et son nombre annoncé.
      expect(find.text(nombreSuggestions(1)), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^$kSuggestionsLibelle')),
        findsOneWidget,
      );
      // « Suivant » sans ↑ ni ↓ : le texte tapé reste, la liste se ferme.
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(find.text('21A · IPA'), findsNothing);
      expect(tester.widget<TextFormField>(style).controller!.text, '21a');
      // Après ↓, Entrée choisit la suggestion surlignée.
      await tester.tap(style);
      await tester.enterText(style, '21A');
      await tester.pumpAndSettle();
      expect(find.text('21A · IPA'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(find.text('21A · IPA'), findsNothing);
      expect(
        tester.widget<TextFormField>(style).controller!.text,
        'American IPA',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom').first,
        'Mon IPA',
      );
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.recipes.writes.single.content!.style, 'American IPA');
    });

    testWidgets('index lu après la frappe : la suggestion paraît sans touche', (
      tester,
    ) async {
      final attente = Completer<void>();
      final app = await open(
        tester,
        '/recettes/nouvelle',
        before: (app) {
          bibliotheque(app);
          app.library.indexAttente[NatureReferentiel.fermentables] = attente;
        },
      );
      await openSheet(tester, 'Ajouter un malt ou un sucre');
      await tester.enterText(sheetField('Nom'), 'pils');
      await tester.pumpAndSettle();
      expect(find.text('Pilsner Fictif'), findsNothing);
      attente.complete();
      await tester.pumpAndSettle();
      expect(find.text('Pilsner Fictif'), findsOneWidget);
      expect(app.library.indexReads, [NatureReferentiel.fermentables]);
    });

    testWidgets('index absent du serveur : « Bibliothèque vide »', (
      tester,
    ) async {
      await open(tester, '/recettes/nouvelle');
      await openSheet(tester, 'Ajouter un malt ou un sucre');
      expect(find.text(kBibliothequeVide), findsOneWidget);
      expect(find.text(kSuggestionsIndisponibles), findsNothing);
    });

    testWidgets('hors ligne : index lu dans le cache, suggestions', (
      tester,
    ) async {
      final app = TestApp();
      bibliotheque(app);
      await app.pump(tester, width: 400);
      app.signIn(brewerUser, member: brewerMember, fromCache: true);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/recettes/nouvelle');
      await tester.pumpAndSettle();
      await openSheet(tester, 'Ajouter un malt ou un sucre');
      expect(app.library.indexReads, [NatureReferentiel.fermentables]);
      // Hors ligne : le cache seul, aucune lecture serveur.
      expect(app.library.indexCacheReads, [NatureReferentiel.fermentables]);
      await tester.enterText(sheetField('Nom'), 'Pils Fictif');
      await tester.pumpAndSettle();
      expect(find.text('Pilsner Fictif'), findsOneWidget);
    });

    testWidgets('index injoignable : saisie libre, relu au focus suivant', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/recettes/nouvelle',
        before: (app) {
          bibliotheque(app);
          app.library.indexErrors[NatureReferentiel.fermentables] = Exception(
            'réseau',
          );
        },
      );
      await openSheet(tester, 'Ajouter un malt ou un sucre');
      expect(find.text(kSuggestionsIndisponibles), findsOneWidget);
      app.library.indexErrors.clear();
      await tester.tap(sheetField('Quantité (kg)'));
      await tester.pumpAndSettle();
      await tester.tap(sheetField('Nom'));
      await tester.pumpAndSettle();
      expect(app.library.indexReads, [
        NatureReferentiel.fermentables,
        NatureReferentiel.fermentables,
      ]);
      expect(find.text(kSuggestionsIndisponibles), findsNothing);
      await tester.enterText(sheetField('Nom'), 'Pils Fictif');
      await tester.pumpAndSettle();
      expect(find.text('Pilsner Fictif'), findsOneWidget);
    });

    testWidgets('ajout : le type vide est repris de la Bibliothèque', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/recettes/nouvelle',
        before: bibliotheque,
      );
      await openSheet(tester, 'Ajouter un ajout');
      await tester.enterText(sheetField('Nom'), 'corian');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coriandre Fictive'));
      await tester.pumpAndSettle();
      await tester.enterText(sheetField('Quantité (g)'), '10');
      await tester.ensureVisible(
        inSheet(find.widgetWithText(FilledButton, 'Ajouter')),
      );
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Ajouter')));
      await tester.pumpAndSettle();
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
      final ajout = app.recipes.writes.single.content!.others.single;
      expect(ajout.name, 'Coriandre Fictive');
      expect(ajout.type, 'spice');
    });
  });
}
