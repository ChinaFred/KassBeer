import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/bandeau_hors_ligne.dart';

import 'package:kass_beer/features/equipment/presentation/equipment_list_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/fakes.dart';

void main() {
  Future<TestApp> signedIn(
    WidgetTester tester, {
    required double width,
    bool admin = false,
  }) async {
    final app = TestApp();
    await app.pump(tester, width: width);
    if (admin) {
      app.signIn(adminUser, member: adminMember);
    } else {
      app.signIn(brewerUser, member: brewerMember);
    }
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets(
    'moins de 600 px : barre de navigation en bas, libellés visibles',
    (tester) async {
      await signedIn(tester, width: 400);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
      for (final label in ['Recettes', 'Brassins', 'Équipements']) {
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('de 600 à 839 px : rail, libellés visibles', (tester) async {
    await signedIn(tester, width: 700);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.all);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('840 px et plus : rail étendu, contenu à 840 px au plus', (
    tester,
  ) async {
    await signedIn(tester, width: 1400);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    final message = find.text(RecipesListScreen.emptyMessage);
    final box = find
        .ancestor(of: message, matching: find.byType(ConstrainedBox))
        .evaluate()
        .map((e) => (e.widget as ConstrainedBox).constraints.maxWidth);
    expect(box, contains(840));
  });

  testWidgets('un brasseur ne voit pas Admin', (tester) async {
    await signedIn(tester, width: 400);
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('un admin voit Admin et ouvre Membres', (tester) async {
    await signedIn(tester, width: 400, admin: true);
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(find.text('Membres'), findsOneWidget);
    expect(find.text('Inviter et retirer les comptes'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Disponible dans une prochaine version'), findsOneWidget);
    final import = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Import'),
    );
    expect(import.enabled, isFalse);
  });

  testWidgets('navigation entre les sections', (tester) async {
    await signedIn(tester, width: 400);
    await tester.tap(find.text('Brassins'));
    await tester.pumpAndSettle();
    expect(
      find.text('Les brassins arriveront dans une prochaine version.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Équipements'));
    await tester.pumpAndSettle();
    expect(find.text(EquipmentListScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('menu du compte : nom, e-mail, version, déconnexion', (
    tester,
  ) async {
    final app = await signedIn(tester, width: 400);
    await tester.tap(find.byTooltip('Mon compte'));
    await tester.pumpAndSettle();
    expect(find.text('Bruno Brasseur'), findsOneWidget);
    expect(find.text('Brasseur@Exemple.fr'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(app.auth.signOutCalls, 1);
    expect(find.text('Se connecter avec Google'), findsOneWidget);
  });

  testWidgets('640 × 360, texte × 2 : aucun débordement, rail défilable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = TestApp();
    await app.pump(tester, width: 640, height: 360);
    app.signIn(adminUser, member: adminMember, fromCache: true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(NavigationRail),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('840 px et plus : bandeau hors ligne en pleine largeur', (
    tester,
  ) async {
    final app = TestApp();
    await app.pump(tester, width: 1400);
    app.signIn(brewerUser, member: brewerMember, fromCache: true);
    await tester.pumpAndSettle();
    final banner = tester.getSize(find.byType(BandeauHorsLigne));
    expect(banner.width, greaterThan(840));
  });
}
