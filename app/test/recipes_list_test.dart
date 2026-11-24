import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/library/presentation/couleur_ebc.dart';
import 'package:kass_beer/features/recipes/domain/filtres_recettes.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/boite_filtres_recettes.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_editor_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_providers.dart';

import 'support/fakes.dart';

Recipe recipe(
  String id,
  RecipeContent content, {
  String owner = 'uid-brasseur',
  String? ownerName = 'Bruno Brasseur',
}) => Recipe(id: id, ownerUid: owner, ownerName: ownerName, content: content);

Future<TestApp> open(
  WidgetTester tester,
  String path, {
  double width = 400,
  double height = 900,
}) async {
  final app = TestApp();
  await app.pump(tester, width: width, height: height);
  app.signIn(brewerUser, member: brewerMember);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

const grainfather = Equipment(
  id: 'e',
  ownerUid: 'uid-brasseur',
  content: EquipmentContent(
    name: 'Grainfather',
    kind: EquipmentKind.allInOne,
    mashEfficiencyPct: 72,
  ),
);

/// Recette calculable : [ebc] du malt, [kg] de malt, équipement [equipmentId].
RecipeContent complete(
  String name, {
  String? style,
  double ebc = 8,
  double kg = 4.5,
  String? equipmentId = 'e',
  String? aroma,
}) => RecipeContent(
  name: name,
  style: style,
  batchVolumeL: 20,
  boilTimeMin: 60,
  equipmentId: equipmentId,
  aromaDescription: aroma,
  fermentables: [
    FermentableLine(
      name: 'Pils',
      type: 'grain',
      weightG: kg * 1000,
      ebc: ebc,
      yieldPct: 80,
    ),
  ],
  yeasts: const [YeastLine(name: 'US-05', attenuationPct: 78)],
);

RecipeCalculation calcul(RecipeContent c, {double? efficiency = 72}) =>
    computeRecipe(recipe: c.toInput(), mashEfficiencyPercent: efficiency);

double valeur(CalculationResult r) => (r as CalculationComputed).value;

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

/// Appui sur [finder] dans la feuille, après l'avoir fait défiler à l'écran.
Future<void> tapInSheet(WidgetTester tester, Finder finder) async {
  final f = inSheet(finder);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('ligne d\'une recette', () {
    testWidgets('teinte, style · degré · EBC, description, volume · auteur', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      final c = complete(
        'Blonde',
        style: 'Blonde Ale',
        aroma: 'Miel, pain frais et une pointe d\'agrumes.',
      );
      final calc = calcul(c);
      app.equipment.publish([grainfather]);
      app.recipes.publish([recipe('b', c, owner: 'uid-zoe', ownerName: 'Zoé')]);
      await tester.pumpAndSettle();
      expect(find.byType(DisqueTeinte), findsOneWidget);
      expect(
        tester.widget<DisqueTeinte>(find.byType(DisqueTeinte)).teinte,
        teinteEbc(valeur(calc.colorEbc)),
      );
      expect(
        find.text(
          'Blonde Ale · ${formatDegre(valeur(calc.alcoholByVolume))} · '
          '${formatEbc(valeur(calc.colorEbc))}',
        ),
        findsOneWidget,
      );
      final description = tester.widget<Text>(
        find.text('Miel, pain frais et une pointe d\'agrumes.'),
      );
      expect(description.maxLines, 2);
      expect(description.overflow, TextOverflow.ellipsis);
      expect(find.text('${formatLitres(20)} · Zoé'), findsOneWidget);
    });

    testWidgets('sans équipement : couleur sans degré ; sans calcul : livre', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      final sansEquipement = complete('Rousse', equipmentId: null);
      app.recipes.publish([
        recipe('r', sansEquipement),
        recipe('v', const RecipeContent(name: 'Vide')),
      ]);
      await tester.pumpAndSettle();
      final calc = calcul(sansEquipement, efficiency: null);
      expect(calc.alcoholByVolume, isA<CalculationUnavailable>());
      expect(find.text(formatEbc(valeur(calc.colorEbc))), findsOneWidget);
      expect(find.byType(DisqueTeinte), findsOneWidget);
      // « Vide » garde le repère du livre ; aucune ligne de détails vide.
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    });

    testWidgets('calcul refusé : « Calcul impossible », un seul rapport', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      const refusee = RecipeContent(
        name: 'Fausse',
        batchVolumeL: 20,
        fermentables: [
          FermentableLine(
            name: 'Pils',
            type: 'grain',
            weightG: 4500,
            yieldPct: 150,
          ),
        ],
      );
      app.recipes.publish([recipe('f', refusee)]);
      await tester.pumpAndSettle();
      app.recipes.publish([recipe('f', refusee)]);
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.calculImpossible), findsOneWidget);
      expect(
        app.errors.reports.where((r) => r.feature == 'recipes.calculation'),
        hasLength(1),
      );
    });

    testWidgets('grand écran : degré et couleur en colonne à droite', (
      tester,
    ) async {
      final app = await open(tester, '/recettes', width: 1000);
      final c = complete('Blonde', style: 'Blonde Ale');
      final calc = calcul(c);
      app.equipment.publish([grainfather]);
      app.recipes.publish([recipe('b', c)]);
      await tester.pumpAndSettle();
      final degre = find.text(formatDegre(valeur(calc.alcoholByVolume)));
      final ebc = find.text(formatEbc(valeur(calc.colorEbc)));
      expect(degre, findsOneWidget);
      expect(ebc, findsOneWidget);
      expect(find.text('Blonde Ale'), findsOneWidget);
      expect(
        tester.getTopLeft(ebc).dy,
        greaterThan(tester.getTopLeft(degre).dy),
      );
      expect(
        tester.getTopLeft(degre).dx,
        greaterThan(tester.getTopRight(find.text('Blonde Ale')).dx),
      );
    });
  });

  group('origine', () {
    testWidgets('Autres : recettes des autres ; Les miennes sans auteur', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.recipes.publish([
        recipe(
          'z',
          const RecipeContent(name: 'IPA de Zoé', batchVolumeL: 20),
          owner: 'uid-zoe',
          ownerName: 'Zoé',
        ),
        recipe('m', const RecipeContent(name: 'Ma blonde', batchVolumeL: 10)),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Autres'));
      await tester.pumpAndSettle();
      expect(find.text('IPA de Zoé'), findsOneWidget);
      expect(find.text('Ma blonde'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Les miennes'));
      await tester.pumpAndSettle();
      expect(find.text('Ma blonde'), findsOneWidget);
      expect(find.text(formatLitres(10)), findsOneWidget);
      expect(find.textContaining('Vous'), findsNothing);
    });

    testWidgets('Autres vide : « Aucune recette d\'un autre membre »', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.recipes.publish([recipe('m', const RecipeContent(name: 'Blonde'))]);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Autres'));
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.othersEmpty), findsOneWidget);
    });
  });

  group('filtres', () {
    Future<TestApp> trois(WidgetTester tester) async {
      final app = await open(tester, '/recettes');
      app.equipment.publish([grainfather]);
      app.recipes.publish([
        recipe(
          't',
          complete(
            'Triple',
            style: 'Tripel',
            ebc: 6,
            kg: 7,
            aroma: 'Épices, poire et banane.',
          ),
        ),
        recipe(
          'i',
          complete('West Coast', style: 'IPA', aroma: 'Agrumes et pin.'),
        ),
        recipe('s', const RecipeContent(name: 'Sans calcul')),
      ]);
      await tester.pumpAndSettle();
      return app;
    }

    Future<void> ouvrir(WidgetTester tester) async {
      await tester.tap(find.byTooltip(TextesFiltresRecettes.titre));
      await tester.pumpAndSettle();
    }

    testWidgets('icône lue avec le nombre de filtres actifs ; zone de 48 px', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await trois(tester);
      expect(
        find.bySemanticsLabel(TextesFiltresRecettes.titre),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byType(IconButton).first).height,
        greaterThanOrEqualTo(48),
      );
      await ouvrir(tester);
      await tapInSheet(tester, find.text('Tripel (1)'));
      await tester.pumpAndSettle();
      await tapInSheet(tester, find.text('Afficher 1 recette'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Filtrer les recettes, 1 filtre actif'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('styles comptés, Afficher N, puce supprimable, Effacer', (
      tester,
    ) async {
      await trois(tester);
      await ouvrir(tester);
      expect(inSheet(find.text(TextesFiltresRecettes.titre)), findsOneWidget);
      expect(inSheet(find.text('Tripel (1)')), findsOneWidget);
      expect(inSheet(find.text('IPA (1)')), findsOneWidget);
      expect(inSheet(find.text('Sans style (1)')), findsOneWidget);
      expect(inSheet(find.text('Afficher 3 recettes')), findsOneWidget);
      await tapInSheet(tester, find.text('Tripel (1)'));
      await tester.pumpAndSettle();
      await tapInSheet(tester, find.text('Afficher 1 recette'));
      await tester.pumpAndSettle();
      expect(find.text('Triple'), findsOneWidget);
      expect(find.text('West Coast'), findsNothing);
      expect(find.text('Sans calcul'), findsNothing);
      expect(find.widgetWithText(InputChip, 'Style : Tripel'), findsOneWidget);

      // La recherche s'ajoute aux filtres.
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher une recette'),
        'coast',
      );
      await tester.pumpAndSettle();
      expect(
        find.text(RecipesListScreen.noFilterMatchWith('coast')),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Rechercher une recette'),
        '',
      );
      await tester.pumpAndSettle();

      // La puce retire son filtre.
      await tester.tap(find.byTooltip('Retirer le style Tripel'));
      await tester.pumpAndSettle();
      expect(find.text('West Coast'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('arômes : tous les mots ; aucun résultat : état vide', (
      tester,
    ) async {
      await trois(tester);
      await ouvrir(tester);
      await tester.enterText(
        inSheet(
          find.widgetWithText(TextField, TextesFiltresRecettes.motsLabel),
        ),
        'poire, epices',
      );
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Afficher 1 recette')), findsOneWidget);
      await tester.enterText(
        inSheet(
          find.widgetWithText(TextField, TextesFiltresRecettes.motsLabel),
        ),
        'poire, pin',
      );
      await tester.pumpAndSettle();
      final aucune = tester.widget<FilledButton>(
        inSheet(
          find.widgetWithText(FilledButton, TextesFiltresRecettes.aucune),
        ),
      );
      expect(aucune.onPressed, isNull);
      expect(
        inSheet(find.text(TextesFiltresRecettes.aucunResultat)),
        findsOneWidget,
      );

      // « Réinitialiser » vide la boîte sans la fermer.
      await tapInSheet(tester, find.text(TextesFiltresRecettes.reinitialiser));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Afficher 3 recettes')), findsOneWidget);
      await tester.enterText(
        inSheet(
          find.widgetWithText(TextField, TextesFiltresRecettes.motsLabel),
        ),
        'poire',
      );
      await tester.pumpAndSettle();
      await tapInSheet(tester, find.text('Afficher 1 recette'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Arôme : poire'), findsOneWidget);
      expect(find.text('Triple'), findsOneWidget);

      // « Autres » vide : l'état de l'origine passe avant celui des filtres.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Autres'));
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.othersEmpty), findsOneWidget);
    });

    testWidgets('fermer sans valider abandonne ; filtre vide : état dédié', (
      tester,
    ) async {
      final app = await trois(tester);
      await ouvrir(tester);
      await tapInSheet(tester, find.text('IPA (1)'));
      await tester.pumpAndSettle();
      // Fermée sans valider (retour du système).
      Navigator.of(tester.element(inSheet(find.text('IPA (1)')))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Triple'), findsOneWidget);

      await ouvrir(tester);
      await tapInSheet(tester, find.text('IPA (1)'));
      await tester.pumpAndSettle();
      await tapInSheet(tester, find.text('Afficher 1 recette'));
      await tester.pumpAndSettle();
      // L'IPA disparaît : aucune recette ne passe le filtre.
      app.recipes.publish([recipe('s', const RecipeContent(name: 'Autre'))]);
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.noFilterMatch), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt_off), findsOneWidget);
      await tester.tap(find.text(TextesFiltresRecettes.effacer).last);
      await tester.pumpAndSettle();
      expect(find.text('Autre'), findsOneWidget);
    });

    testWidgets('degré : texte des bornes calculées, note des recettes sans '
        'degré', (tester) async {
      await trois(tester);
      await ouvrir(tester);
      final degres = [
        for (final c in [
          complete('Triple', ebc: 6, kg: 7),
          complete('West Coast'),
        ])
          valeur(calcul(c).alcoholByVolume),
      ]..sort();
      final c = curseurDe(Intervalle(degres.first, degres.last), 0.1)!;
      expect(
        inSheet(find.text('De ${TextesFiltresRecettes.plageDegre(c.bornes)}')),
        findsOneWidget,
      );
      final curseur = inSheet(find.byType(RangeSlider)).first;
      final slider = tester.widget<RangeSlider>(curseur);
      expect(slider.min, c.bornes.min);
      expect(slider.max, c.bornes.max);
      slider.onChanged!(RangeValues(c.bornes.min, c.bornes.max - 0.1));
      await tester.pumpAndSettle();
      expect(
        inSheet(find.text(TextesFiltresRecettes.sansDegre(1))),
        findsOneWidget,
      );
      expect(inSheet(find.text('Afficher 1 recette')), findsOneWidget);
    });
  });

  group('filtres (relecture)', () {
    testWidgets('une puce par style et par mot, chacune retirée seule', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.equipment.publish([grainfather]);
      app.recipes.publish([
        recipe(
          't',
          complete('Triple', style: 'Tripel', aroma: 'Poire, épices.'),
        ),
        recipe('i', complete('West Coast', style: 'IPA', aroma: 'Poire, pin.')),
      ]);
      await tester.pumpAndSettle();
      app.container
          .read(filtresRecettesProvider.notifier)
          .appliquer(
            FiltresRecettes.vide
                .avecStyles({'tripel', 'ipa'})
                .avecAromes('poire, epices'),
          );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Style : Tripel'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Style : IPA'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Arôme : poire'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Arôme : epices'), findsOneWidget);
      await tester.tap(find.byTooltip('Retirer l\'arôme epices'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Arôme : epices'), findsNothing);
      expect(find.text('West Coast'), findsOneWidget);
      await tester.tap(find.byTooltip('Retirer le style IPA'));
      await tester.pumpAndSettle();
      expect(find.text('West Coast'), findsNothing);
      expect(find.widgetWithText(InputChip, 'Style : Tripel'), findsOneWidget);
    });

    testWidgets('changer d\'origine ramène la plage dans ses bornes', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.equipment.publish([grainfather]);
      app.recipes.publish([
        recipe('m', complete('Mienne', ebc: 6, kg: 7)),
        recipe('z', complete('Zoé', ebc: 6, kg: 4), owner: 'uid-zoe'),
      ]);
      await tester.pumpAndSettle();
      app.container
          .read(filtresRecettesProvider.notifier)
          .appliquer(FiltresRecettes.vide.avecDegre(const Intervalle(0.5, 20)));
      await tester.pumpAndSettle();
      // Une seule recette par origine : la plage couvre ses bornes.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Les miennes'));
      await tester.pumpAndSettle();
      expect(app.container.read(filtresRecettesProvider).degre, isNull);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('recettes illisibles écartées par un filtre : comptées', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.recipes.all.add(
        const ListeLue(
          documents: [
            DocumentValide(
              'b',
              Recipe(
                id: 'b',
                ownerUid: 'uid-brasseur',
                content: RecipeContent(name: 'Blonde', style: 'Blonde'),
              ),
            ),
            DocumentInvalide('x', DocumentIllisible('format_version', 'x')),
            DocumentInvalide('y', DocumentIllisible('format_version', 'y')),
          ],
          fromCache: false,
        ),
      );
      await tester.pumpAndSettle();
      app.container
          .read(filtresRecettesProvider.notifier)
          .appliquer(FiltresRecettes.vide.avecStyles({'blonde'}));
      await tester.pumpAndSettle();
      expect(find.text('Recette illisible'), findsNothing);
      expect(
        find.text(RecipesListScreen.illisiblesFiltrees(2)),
        findsOneWidget,
      );
    });

    testWidgets('dialogue : « Fermer » en tête, curseurs nommés, boutons '
        'hors du défilement', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await open(tester, '/recettes', width: 1000);
      app.equipment.publish([grainfather]);
      app.recipes.publish([
        recipe('t', complete('Triple', ebc: 6, kg: 7)),
        recipe('i', complete('West Coast')),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesFiltresRecettes.titre));
      await tester.pumpAndSettle();
      final dialogue = find.byType(Dialog);
      expect(
        find.descendant(of: dialogue, matching: find.byTooltip('Fermer')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^Degré d\'alcool')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('^Couleur')), findsWidgets);
      // Le bouton principal n'est pas dans la partie qui défile.
      expect(
        find.ancestor(
          of: find.text('Afficher 2 recettes'),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(dialogue, findsNothing);
      semantics.dispose();
    });
  });

  group('filtres (relecture UX, seconde passe)', () {
    testWidgets('filtre gardé sans curseur : « Filtre en cours » et retrait', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      // Aucune recette n'a d'équipement : aucun degré calculé.
      app.recipes.publish([
        recipe('r', complete('Rousse', equipmentId: null)),
        recipe('b', complete('Blonde', equipmentId: null)),
      ]);
      await tester.pumpAndSettle();
      app.container
          .read(filtresRecettesProvider.notifier)
          .appliquer(FiltresRecettes.vide.avecDegre(const Intervalle(5, 9)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesFiltresRecettes.titre));
      await tester.pumpAndSettle();
      expect(
        inSheet(find.text(TextesFiltresRecettes.aucunDegre)),
        findsOneWidget,
      );
      expect(
        inSheet(
          find.text(
            TextesFiltresRecettes.filtreEnCours(
              TextesFiltresRecettes.plageDegre(const Intervalle(5, 9)),
            ),
          ),
        ),
        findsOneWidget,
      );
      await tapInSheet(tester, find.text(TextesFiltresRecettes.retirerFiltre));
      await tapInSheet(tester, find.text('Afficher 2 recettes'));
      expect(app.container.read(filtresRecettesProvider).degre, isNull);
      expect(find.text('Rousse'), findsOneWidget);
    });

    testWidgets('poignées lues « Degré d\'alcool : … » et « Couleur : … »', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await open(tester, '/recettes');
      app.equipment.publish([grainfather]);
      app.recipes.publish([
        recipe('t', complete('Triple', ebc: 6, kg: 7)),
        recipe('i', complete('West Coast', ebc: 20)),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesFiltresRecettes.titre));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byValue(RegExp('^Degré d\'alcool : [0-9,]+.%.vol\$')),
        findsAtLeast(2),
      );
      expect(
        find.semantics.byValue(RegExp('^Couleur : [0-9]+.EBC\$')),
        findsAtLeast(2),
      );
      semantics.dispose();
    });

    testWidgets('640 × 360, texte à 200 % : boîte sans débordement, pied '
        'dans le défilement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await open(tester, '/recettes', width: 640, height: 360);
      app.equipment.publish([grainfather]);
      app.recipes.publish([
        recipe('t', complete('Triple', style: 'Tripel', ebc: 6, kg: 7)),
        recipe('i', complete('West Coast', style: 'IPA')),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesFiltresRecettes.titre));
      await tester.pumpAndSettle();
      final afficher = find.text('Afficher 2 recettes');
      expect(
        find.ancestor(
          of: afficher,
          matching: find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(SingleChildScrollView),
          ),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(afficher);
      await tester.pumpAndSettle();
      await tester.tap(afficher);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360 px, texte à 200 % : style au nom long sans débordement', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const long =
          'Bière de garde ambrée de tradition flamande longuement houblonnée';
      final app = await open(tester, '/recettes', width: 360);
      app.recipes.publish([
        recipe('l', const RecipeContent(name: 'Longue', style: long)),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesFiltresRecettes.titre));
      await tester.pumpAndSettle();
      await tapInSheet(tester, find.textContaining('Bière de garde'));
      await tapInSheet(tester, find.text('Afficher 1 recette'));
      expect(find.textContaining('Style : Bière de garde'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans résultat : message annoncé (zone dynamique)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await open(tester, '/recettes');
      app.recipes.publish([
        recipe(
          'b',
          const RecipeContent(name: 'Blonde', aromaDescription: 'Miel.'),
        ),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(TextesFiltresRecettes.titre));
      await tester.pumpAndSettle();
      await tester.enterText(
        inSheet(
          find.widgetWithText(TextField, TextesFiltresRecettes.motsLabel),
        ),
        'poivre',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(
          inSheet(find.text(TextesFiltresRecettes.aucunResultat)),
        ),
        matchesSemantics(
          label: TextesFiltresRecettes.aucunResultat,
          isLiveRegion: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('description aromatique', () {
    testWidgets('éditeur : écrite à l\'enregistrement ; au-delà de 500 '
        'caractères, refusée', (tester) async {
      final app = await open(tester, '/recettes/nouvelle');
      await tester.enterText(find.widgetWithText(TextFormField, 'Nom'), 'Ma');
      final champ = find.widgetWithText(
        TextFormField,
        RecipeEditorScreen.aromaLabel,
      );
      await tester.ensureVisible(champ);
      // 507 unités UTF-16 sous 500 graphèmes : le compteur du champ laisse passer.
      await tester.enterText(champ, '${'a' * 499}👨‍👩‍👧');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text(RecipeEditorScreen.aromaTropLongue), findsOneWidget);
      expect(app.recipes.writes, isEmpty);

      await tester.enterText(champ, 'Agrumes et pin.');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        app.recipes.writes.single.content!.aromaDescription,
        'Agrumes et pin.',
      );
    });

    testWidgets('fiche : section seulement si la description existe', (
      tester,
    ) async {
      final app = await open(tester, '/recettes/a');
      app.recipes.publish([
        recipe(
          'a',
          const RecipeContent(name: 'Avec', aromaDescription: 'Fruits rouges.'),
        ),
        recipe('s', const RecipeContent(name: 'Sans')),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(RecipeDetailScreen.aromaTitre), findsOneWidget);
      expect(find.text('Fruits rouges.'), findsOneWidget);
      app.container.read(routerProvider).go('/recettes/s');
      await tester.pumpAndSettle();
      expect(find.text(RecipeDetailScreen.aromaTitre), findsNothing);
    });
  });
}
