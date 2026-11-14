import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/couleur_ebc.dart';
import 'package:kass_beer/features/library/presentation/couleurs_ebc_screen.dart';
import 'package:kass_beer/features/library/presentation/data_sources_screen.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

Future<TestApp> open(
  WidgetTester tester,
  String path, {
  double width = 400,
  void Function(TestApp app)? before,
}) async {
  final app = TestApp();
  before?.call(app);
  await app.pump(tester, width: width);
  app.signIn(brewerUser, member: brewerMember);
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

void seedStyle(TestApp app, Map<String, dynamic> doc) =>
    app.library.fiches['bjcp2021-21a'] = DocumentTrouve(
      FicheReferentiel.fromFirestore(
        NatureReferentiel.styles,
        'bjcp2021-21a',
        doc,
      ),
    );

/// Couleurs des arrêts du dégradé affiché.
List<Color> couleursBande(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(BandeTeintes),
      matching: find.byType(Container),
    ),
  );
  final decoration = container.decoration! as BoxDecoration;
  return (decoration.gradient! as LinearGradient).colors;
}

void main() {
  group('fiche d\'un style', () {
    testWidgets('barre de 12 à 28 EBC, mention, lien vers l\'échelle', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(
        tester,
        '/bibliotheque/styles/bjcp2021-21a',
        before: (app) => seedStyle(app, styleDoc()),
      );
      expect(find.text('${formatEbc(12)} à ${formatEbc(28)}'), findsOneWidget);
      expect(find.byType(BandeTeintes), findsOneWidget);
      final couleurs = couleursBande(tester);
      expect(couleurs.first, couleurTeinte(teinteEbc(12)));
      expect(couleurs.last, couleurTeinte(teinteEbc(28)));
      expect(
        find.bySemanticsLabel('Couleur de ${formatEbc(12)} à ${formatEbc(28)}'),
        findsOneWidget,
      );
      expect(find.text(TextesCouleurEbc.mention), findsOneWidget);
      await tester.ensureVisible(find.text(TextesCouleurEbc.echelle));
      await tester.tap(find.text(TextesCouleurEbc.echelle));
      await tester.pumpAndSettle();
      expect(find.byType(CouleursEbcScreen), findsOneWidget);
      handle.dispose();
    });

    testWidgets('« à partir de » : jusqu\'à la limite ; « jusqu\'à » : de 0', (
      tester,
    ) async {
      await open(
        tester,
        '/bibliotheque/styles/bjcp2021-21a',
        before: (app) => seedStyle(app, {
          ...styleDoc(),
          'color': {
            'minimum': {'value': 50, 'unit': 'EBC'},
          },
        }),
      );
      final couleurs = couleursBande(tester);
      expect(couleurs.first, couleurTeinte(teinteEbc(50)));
      expect(couleurs.last, couleurTeinte(teinteEbc(teinteEbcLimite)));
    });

    testWidgets('sans plage de couleur : aucune barre', (tester) async {
      final doc = styleDoc()..remove('color');
      await open(
        tester,
        '/bibliotheque/styles/bjcp2021-21a',
        before: (app) => seedStyle(app, doc),
      );
      expect(find.byType(BandeTeintes), findsNothing);
      expect(find.text(TextesCouleurEbc.mention), findsNothing);
    });
  });

  group('barre seule', () {
    Future<RecordingErrorReportService> pumpBarre(
      WidgetTester tester,
      Plage plage,
    ) async {
      final errors = RecordingErrorReportService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [errorReportServiceProvider.overrideWithValue(errors)],
          child: MaterialApp(
            home: Scaffold(body: BarreCouleurEbc(plage: plage)),
          ),
        ),
      );
      return errors;
    }

    testWidgets('minimum au-dessus du maximum : ordre croissant', (
      tester,
    ) async {
      await pumpBarre(tester, const Plage(minimum: 16, maximum: 8));
      final couleurs = couleursBande(tester);
      expect(couleurs.first, couleurTeinte(teinteEbc(8)));
      expect(couleurs.last, couleurTeinte(teinteEbc(16)));
    });

    testWidgets('borne négative : pas de barre, un seul rapport', (
      tester,
    ) async {
      final errors = await pumpBarre(
        tester,
        const Plage(minimum: -2, maximum: 10),
      );
      expect(find.byType(BandeTeintes), findsNothing);
      await tester.pump();
      expect(errors.reports, hasLength(1));
      expect(errors.reports.single.feature, 'library.color_gradient');
      expect(errors.reports.single.error, isA<BrewingInputException>());
    });
  });

  group('page Couleurs EBC', () {
    testWidgets('téléphone : depuis la Bibliothèque, pas de 4 EBC, en EBC '
        'seulement', (tester) async {
      final app = await open(tester, '/bibliotheque');
      await tester.tap(find.byTooltip(TextesCouleurEbc.echelle));
      await tester.pumpAndSettle();
      expect(find.text(CouleursEbcScreen.title), findsOneWidget);
      expect(find.text(TextesCouleurEbc.mention), findsOneWidget);
      expect(find.text(formatEbc(0)), findsOneWidget);
      expect(find.text(formatEbc(4)), findsOneWidget);
      final liste = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('79${nbsp}EBC et plus'),
        200,
        scrollable: liste,
      );
      expect(find.text(formatEbc(76)), findsOneWidget);
      expect(find.textContaining('SRM'), findsNothing);
      final pastille = tester.widget<Container>(
        find.byKey(const ValueKey('pastille 79${nbsp}EBC et plus')),
      );
      final decoration = pastille.decoration! as BoxDecoration;
      expect(decoration.color, couleurTeinte(teinteEbc(teinteEbcLimite)));
      expect(
        (decoration.border! as Border).top.color,
        Theme.of(
          tester.element(find.byType(CouleursEbcScreen)),
        ).colorScheme.outlineVariant,
      );
      // Aucune lecture de la Bibliothèque pour cette page.
      expect(app.library.ficheReads, isEmpty);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(location(app), '/bibliotheque/styles');
    });

    testWidgets('au-delà de 600 px : lien en texte, dégradé continu', (
      tester,
    ) async {
      await open(tester, '/bibliotheque', width: 900);
      await tester.tap(find.text(TextesCouleurEbc.echelle));
      await tester.pumpAndSettle();
      expect(find.byType(CouleursEbcScreen), findsOneWidget);
      expect(find.byType(BandeTeintes), findsOneWidget);
      expect(find.byType(Wrap), findsWidgets);
    });

    testWidgets('texte × 2 à 360 px : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, '/bibliotheque/couleurs', width: 360);
      expect(tester.takeException(), isNull);
      expect(find.byType(CouleursEbcScreen), findsOneWidget);
    });
  });

  testWidgets('Sources des données nomme srm2hex', (tester) async {
    await open(tester, '/sources-des-donnees');
    await tester.scrollUntilVisible(
      find.text(DataSourcesScreen.srm2hex),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(DataSourcesScreen.srm2hex), findsOneWidget);
  });
}
