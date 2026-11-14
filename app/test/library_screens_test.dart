import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/data_sources_screen.dart';
import 'package:kass_beer/features/library/presentation/library_providers.dart';
import 'package:kass_beer/features/library/presentation/library_screen.dart';
import 'package:kass_beer/features/library/presentation/public_recipe_screen.dart';
import 'package:kass_beer/features/library/presentation/reference_entry_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_editor_screen.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

Future<TestApp> open(
  WidgetTester tester,
  String path, {
  bool offline = false,
  double height = 900,
  void Function(TestApp app)? before,
}) async {
  final app = TestApp();
  before?.call(app);
  await app.pump(tester, height: height);
  app.signIn(brewerUser, member: brewerMember, fromCache: offline);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

String location(TestApp app) => app.container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .path;

/// Défilement de la page, et non du champ de recherche.
Finder get _liste => find.byType(Scrollable).first;

/// Appuie sur la puce [label] : sur téléphone, la ligne des puces défile.
Future<void> tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

DocumentTrouve<IndexReferentiel> found(
  NatureReferentiel nature,
  Map<String, dynamic> doc,
) => DocumentTrouve(IndexReferentiel.fromFirestore(nature, doc));

void main() {
  group('navigation', () {
    testWidgets('entrée Bibliothèque après Recettes ; styles à l\'ouverture', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      expect(labels, ['Recettes', 'Bibliothèque', 'Brassins', 'Équipements']);
      await tester.tap(find.byTooltip('Bibliothèque'));
      await tester.pumpAndSettle();
      // `/bibliotheque` redirige vers les styles.
      expect(location(app), '/bibliotheque/styles');
      expect(app.library.indexReads, [NatureReferentiel.styles]);
      expect(find.text(SegmentBibliotheque.styles.vide), findsOneWidget);
      expect(
        find.text(
          'Aucun style dans la bibliothèque pour l\'instant. '
          'L\'administrateur la remplit.',
        ),
        findsOneWidget,
      );
      for (final label in [
        'Styles',
        'Malts et sucres',
        'Houblons',
        'Levures',
        'Divers',
        'Recettes publiques',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
    });

    testWidgets('un segment par chemin', (tester) async {
      final app = await open(tester, '/bibliotheque');
      await tapChip(tester, 'Houblons');
      expect(location(app), '/bibliotheque/houblons');
      expect(find.text(SegmentBibliotheque.hops.vide), findsOneWidget);
      expect(app.library.indexReads.last, NatureReferentiel.hops);
    });
  });

  group('référentiels', () {
    testWidgets('liste, illisibles comptés, recherche locale', (tester) async {
      final app = await open(
        tester,
        '/bibliotheque/houblons',
        before: (app) => app.library.index[NatureReferentiel.hops] = found(
          NatureReferentiel.hops,
          hopsIndex,
        ),
      );
      expect(find.text('Cascade'), findsOneWidget);
      expect(find.text('Houblon doré'), findsOneWidget);
      expect(find.text('2 entrées'), findsOneWidget);
      expect(find.text(LibraryScreen.unreadableEntries(1)), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'DORE');
      await tester.pumpAndSettle();
      expect(find.text('Cascade'), findsNothing);
      expect(find.text('Houblon doré'), findsOneWidget);
      expect(find.text('1 sur 2'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text(LibraryScreen.noMatch('zzz')), findsOneWidget);
      await tester.tap(find.text('Effacer la recherche'));
      await tester.pumpAndSettle();
      expect(find.text('Cascade'), findsOneWidget);
      // Aucune nouvelle lecture pendant la recherche.
      expect(app.library.indexReads, [NatureReferentiel.hops]);
    });

    testWidgets('fiche d\'un houblon : valeurs, provenance, licence', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/bibliotheque/houblons',
        before: (app) {
          app.library.index[NatureReferentiel.hops] = found(
            NatureReferentiel.hops,
            hopsIndex,
          );
          app.library.fiches['hop-cascade'] = DocumentTrouve(
            FicheReferentiel.fromFirestore(
              NatureReferentiel.hops,
              'hop-cascade',
              hopDoc(),
            ),
          );
        },
      );
      await tester.tap(find.text('Cascade'));
      await tester.pumpAndSettle();
      expect(location(app), '/bibliotheque/houblons/hop-cascade');
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Houblon'),
        ),
        findsOneWidget,
      );
      expect(find.text('Autres noms : Cascade US'), findsOneWidget);
      expect(find.text('Acides alpha'), findsOneWidget);
      expect(find.text(formatPourcent(6.5)), findsOneWidget);
      expect(find.text('Aromatique'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(
          'Brewtarget 5.2.3 · licence CC BY-SA 4.0 · relevé le 8 novembre 2026',
        ),
        200,
        scrollable: _liste,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(location(app), '/bibliotheque/houblons');
    });

    testWidgets('fiche d\'un style : plages chiffrées', (tester) async {
      await open(
        tester,
        '/bibliotheque/styles/bjcp2021-21a',
        before: (app) => app.library.fiches['bjcp2021-21a'] = DocumentTrouve(
          FicheReferentiel.fromFirestore(
            NatureReferentiel.styles,
            'bjcp2021-21a',
            styleDoc(),
          ),
        ),
      );
      expect(find.text('21 · IPA'), findsOneWidget);
      expect(find.text('Bière'), findsOneWidget);
      expect(find.text('1056,0 à 1070,0'), findsOneWidget);
      expect(find.text('1008,0 à 1014,0'), findsOneWidget);
      expect(
        find.text('${formatDegre(5.5)} à ${formatDegre(7.5)}'),
        findsOneWidget,
      );
      expect(find.text('${formatIbu(40)} à ${formatIbu(70)}'), findsOneWidget);
      expect(find.text('${formatEbc(12)} à ${formatEbc(28)}'), findsOneWidget);
    });

    testWidgets('fiche absente, fiche illisible', (tester) async {
      final app = await open(
        tester,
        '/bibliotheque/levures/inconnue',
        before: (app) => app.library.fiches['illisible'] =
            const DocumentIllisibleTrouve(DocumentIllisible('name', 'absent')),
      );
      expect(find.text(TextesFicheBibliotheque.absent), findsOneWidget);
      app.container.read(routerProvider).go('/bibliotheque/levures/illisible');
      await tester.pumpAndSettle();
      expect(find.text(TextesFicheBibliotheque.unreadable), findsOneWidget);
      await tester.tap(find.text('Revenir à la bibliothèque'));
      await tester.pumpAndSettle();
      expect(location(app), '/bibliotheque/levures');
    });

    testWidgets('panne : message et Réessayer, qui relit', (tester) async {
      final app = await open(
        tester,
        '/bibliotheque/malts',
        before: (app) =>
            app.library.indexErrors[NatureReferentiel.fermentables] = Exception(
              'refus',
            ),
      );
      expect(find.text(LibraryScreen.loadError), findsOneWidget);
      app.library.indexErrors.clear();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text(SegmentBibliotheque.fermentables.vide), findsOneWidget);
      expect(app.library.indexReads, [
        NatureReferentiel.fermentables,
        NatureReferentiel.fermentables,
      ]);
    });

    testWidgets('hors ligne : panne ou absent du cache', (tester) async {
      final app = await open(
        tester,
        '/bibliotheque/divers',
        offline: true,
        before: (app) =>
            app.library.indexErrors[NatureReferentiel.miscs] = Exception('x'),
      );
      expect(find.text(LibraryScreen.offlineMessage), findsOneWidget);
      app.library.indexErrors.clear();
      app.library.index[NatureReferentiel.miscs] =
          const DocumentAbsentDuCache();
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text(LibraryScreen.offlineMessage), findsOneWidget);
      expect(find.text(SegmentBibliotheque.miscs.vide), findsNothing);
    });

    testWidgets('référentiel illisible', (tester) async {
      await open(
        tester,
        '/bibliotheque/styles',
        before: (app) => app.library.index[NatureReferentiel.styles] =
            const DocumentIllisibleTrouve(DocumentIllisible('entries', 'x')),
      );
      expect(
        find.text(
          'Cette liste ne peut pas s\'afficher. L\'erreur est signalée à '
          'l\'administrateur.',
        ),
        findsOneWidget,
      );
    });
  });

  group('disposition', () {
    testWidgets('la recherche survit au retour d\'une fiche', (tester) async {
      await open(
        tester,
        '/bibliotheque/houblons',
        before: (app) {
          app.library.index[NatureReferentiel.hops] = found(
            NatureReferentiel.hops,
            hopsIndex,
          );
          app.library.fiches['hop-cascade'] = DocumentTrouve(
            FicheReferentiel.fromFirestore(
              NatureReferentiel.hops,
              'hop-cascade',
              hopDoc(),
            ),
          );
        },
      );
      await tester.enterText(find.byType(TextField), 'casc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cascade'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'casc'), findsOneWidget);
      expect(find.text('1 sur 2'), findsOneWidget);
      // Le compte est annoncé aux lecteurs d'écran.
      expect(
        find.ancestor(
          of: find.text('1 sur 2'),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('téléphone : puces sur une ligne qui défile', (tester) async {
      await open(tester, '/bibliotheque/styles');
      final rows = find.ancestor(
        of: find.widgetWithText(ChoiceChip, 'Styles'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(rows, findsOneWidget);
      expect(
        tester.getTopLeft(find.widgetWithText(ChoiceChip, 'Styles')).dy,
        tester.getTopLeft(find.widgetWithText(ChoiceChip, 'Divers')).dy,
      );
      expect(find.byTooltip(LibraryScreen.sourcesLabel), findsOneWidget);
    });

    testWidgets('au-delà de 600 px : puces à la ligne, lien en texte', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester, width: 900);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/bibliotheque/styles');
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextButton, LibraryScreen.sourcesLabel),
        findsOneWidget,
      );
      expect(find.byType(Wrap), findsWidgets);
    });

    testWidgets('barre du bas à 360 px, admin, texte × 2 : aucun débordement', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp();
      await app.pump(tester, width: 360, height: 800);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/bibliotheque/styles');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byTooltip('Bibliothèque'),
        ),
        findsOneWidget,
      );
    });
  });

  group('recettes publiques', () {
    void seed(TestApp app, int count) {
      for (var i = 1; i <= count; i++) {
        app.library.recettes.add(
          publicRecipe(
            id: '$i',
            name: 'Recette ${i.toString().padLeft(3, '0')}',
          ),
        );
      }
    }

    testWidgets('pages de 50, page suivante sur demande', (tester) async {
      final app = await open(
        tester,
        '/bibliotheque/recettes',
        before: (app) => seed(app, 60),
      );
      expect(find.text('Recette 001'), findsOneWidget);
      expect(
        find.text(
          'Blonde fruitée · ${formatLitres(23)} · ${formatDegre(5.6)} annoncés',
        ),
        findsWidgets,
      );
      final next = find.text('Afficher les recettes suivantes');
      await tester.scrollUntilVisible(next, 500, scrollable: _liste);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(app.library.pages, hasLength(2));
      expect(app.library.pages.last.apres?.valeur, 50);
      await tester.scrollUntilVisible(
        find.text('Recette 060'),
        500,
        scrollable: _liste,
      );
      expect(next, findsNothing);
    });

    testWidgets('recherche par préfixe à la validation, pas à la frappe', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/bibliotheque/recettes',
        before: (app) {
          seed(app, 2);
          app.library.recettes.add(publicRecipe(id: '9', name: 'Punk IPA'));
        },
      );
      await tester.enterText(find.byType(TextField), 'Punk');
      await tester.pumpAndSettle();
      expect(app.library.pages, hasLength(1));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(app.library.pages.last.prefixe, 'Punk');
      expect(find.text('Punk IPA'), findsOneWidget);
      expect(find.text('Recette 001'), findsNothing);
      expect(find.text(LibraryScreen.searchHelp), findsOneWidget);
      expect(find.textContaining('ajuscules'), findsNothing);
      // Majuscules et accents ne comptent pas.
      await tester.enterText(find.byType(TextField), 'pùnk');
      await tester.tap(find.byTooltip('Rechercher'));
      await tester.pumpAndSettle();
      expect(find.text('Punk IPA'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.tap(find.byTooltip('Rechercher'));
      await tester.pumpAndSettle();
      expect(find.text(LibraryScreen.noRecipeMatch('zzz')), findsOneWidget);
    });

    testWidgets('vide, panne', (tester) async {
      final app = await open(tester, '/bibliotheque/recettes');
      expect(
        find.text('Aucune recette publique pour l\'instant.'),
        findsOneWidget,
      );
      app.library.pageError = Exception('refus');
      await tapChip(tester, 'Styles');
      await tapChip(tester, 'Recettes publiques');
      expect(find.text(LibraryScreen.loadError), findsOneWidget);
    });

    testWidgets('fiche : calculs, annoncé par la source, moments d\'origine', (
      tester,
    ) async {
      await open(
        tester,
        '/bibliotheque/recettes/diydog-1',
        height: 3200,
        before: (app) => seed(app, 1),
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Recette publique'),
        ),
        findsOneWidget,
      );
      expect(find.text('Recette publique · DIY Dog'), findsOneWidget);
      expect(find.text('Dupliquer'), findsOneWidget);
      expect(find.text('Calculs'), findsOneWidget);
      // Fenêtre haute : toute la fiche est construite.
      // Un seul message à la place de la liste « À compléter ».
      expect(find.text(PublicRecipeScreen.missingNote), findsOneWidget);
      expect(find.text('À compléter'), findsNothing);
      expect(find.text('Aucun équipement choisi.'), findsNothing);
      expect(find.text(PublicRecipeScreen.announcedTitle), findsOneWidget);
      expect(find.text(PublicRecipeScreen.announcedNote), findsOneWidget);
      // « Annoncé par la source » avant « Calculs ».
      expect(
        tester.getTopLeft(find.text(PublicRecipeScreen.announcedTitle)).dy,
        lessThan(tester.getTopLeft(find.text('Calculs')).dy),
      );
      expect(find.text('1052,0'), findsOneWidget);
      expect(find.text('1009,0'), findsOneWidget);
      expect(find.text(formatDegre(5.6)), findsOneWidget);
      expect(find.text(formatIbu(28)), findsOneWidget);
      expect(find.text(formatEbc(9)), findsOneWidget);
      // Aucun style résolu (DIY Dog) : pas de lien.
      expect(find.text('Voir le style'), findsNothing);
      expect(find.text('BrewDog'), findsOneWidget);
      expect(
        find.textContaining("moment d'origine : milieu d'ébullition (middle)"),
        findsOneWidget,
      );
      expect(find.text('Saccharification'), findsOneWidget);
      expect(
        find.text(
          'DIY Dog · licence DIY Dog (usage privé) · relevé le 8 novembre 2026',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Dupliquer : création sous le compte du lecteur, éditeur', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/bibliotheque/recettes/diydog-1',
        before: (app) => seed(app, 1),
      );
      await tester.tap(find.text('Dupliquer'));
      await tester.pumpAndSettle();
      final write = app.recipes.writes.single;
      expect(write.kind, 'create');
      expect(write.ownerUid, 'uid-brasseur');
      expect(write.ownerName, 'Bruno Brasseur');
      expect(write.content!.name, 'Recette 001');
      expect(write.content!.importedFrom, 'DIY Dog · diydog-1');
      // L'éditeur est ouvert par `push`, par-dessus la fiche.
      expect(
        find.byWidgetPredicate(
          (w) => w is RecipeEditorScreen && w.id == write.id,
        ),
        findsOneWidget,
      );
      expect(find.text(PublicRecipeScreen.duplicated), findsOneWidget);
    });

    testWidgets('« Voir le style » ouvre par-dessus la fiche du style résolu', (
      tester,
    ) async {
      final app = await open(
        tester,
        '/bibliotheque/recettes/diydog-1',
        before: (app) =>
            app.library.recettes.add(publicRecipe(styleId: 'bjcp2021-21a')),
      );
      await tester.tap(find.text('Voir le style'));
      await tester.pumpAndSettle();
      expect(app.library.ficheReads, ['bjcp2021-21a']);
      expect(
        find.byWidgetPredicate(
          (w) => w is ReferenceEntryScreen && w.id == 'bjcp2021-21a',
        ),
        findsOneWidget,
      );
    });

    testWidgets('houblons sans forme : « forme non renseignée », copie sans '
        'forme', (tester) async {
      final app = await open(
        tester,
        '/bibliotheque/recettes/diydog-1',
        height: 3200,
        before: (app) =>
            app.library.recettes.add(publicRecipe(avecForme: false)),
      );
      expect(find.textContaining('forme non renseignée'), findsNWidgets(2));
      expect(find.text(PublicRecipeScreen.missingNote), findsOneWidget);
      await tester.tap(find.text('Dupliquer'));
      await tester.pumpAndSettle();
      final hops = app.recipes.writes.single.content!.hops;
      expect(hops.map((h) => h.form), [null, null]);
    });

    testWidgets('fiche absente', (tester) async {
      await open(tester, '/bibliotheque/recettes/diydog-404');
      expect(find.text(TextesFicheBibliotheque.absent), findsOneWidget);
      expect(find.text('Revenir aux recettes publiques'), findsOneWidget);
    });
  });

  group('Sources des données', () {
    testWidgets('depuis la Bibliothèque : attributions, lien de la licence', (
      tester,
    ) async {
      final app = await open(tester, '/bibliotheque');
      // Téléphone : une icône à droite des puces.
      await tester.tap(find.byTooltip(LibraryScreen.sourcesLabel));
      await tester.pumpAndSettle();
      expect(find.byType(DataSourcesScreen), findsOneWidget);
      expect(find.text(DataSourcesScreen.brewtarget), findsOneWidget);
      expect(find.text(DataSourcesScreen.bjcp), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(DataSourcesScreen.beerAnalytics),
        200,
        scrollable: _liste,
      );
      await tester.scrollUntilVisible(
        find.text('Licence : https://creativecommons.org/licenses/by-sa/4.0/'),
        200,
        scrollable: _liste,
      );
      await tester.scrollUntilVisible(
        find.text(DataSourcesScreen.diyDog),
        200,
        scrollable: _liste,
      );
      await tester.tap(find.text('Lire la licence CC BY-SA 4.0'));
      await tester.pumpAndSettle();
      expect(app.openedLinks, [kLicenceCcBySa]);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(location(app), '/bibliotheque/styles');
    });

    testWidgets('depuis le menu du compte ; échec d\'ouverture rapporté', (
      tester,
    ) async {
      final app = await open(tester, '/recettes');
      app.openLinkResult = false;
      await tester.tap(find.byTooltip('Mon compte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sources des données'));
      await tester.pumpAndSettle();
      expect(find.byType(DataSourcesScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Lire la licence CC BY-SA 4.0'),
        200,
        scrollable: _liste,
      );
      await tester.tap(find.text('Lire la licence CC BY-SA 4.0'));
      await tester.pumpAndSettle();
      expect(find.text(DataSourcesScreen.openFailure), findsOneWidget);
      expect(app.errors.reports.single.feature, 'library.open_licence');
    });
  });
}
