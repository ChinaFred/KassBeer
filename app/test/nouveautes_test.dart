import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/nouveautes.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/core/presentation/nouveautes_screen.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/auth/presentation/access_providers.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/fakes.dart';

const _sample = '''
{
  "versions": [
    {
      "version": "0.1.2",
      "date": "2026-11-08",
      "paragraphs": ["Deuxième version.", "• Une puce."]
    },
    {
      "version": "0.1.0",
      "date": "2026-11-01",
      "paragraphs": ["Première version."]
    }
  ]
}
''';

void main() {
  group('lireNouveautes', () {
    test('lit versions, dates et paragraphes dans l\'ordre', () {
      final versions = lireNouveautes(_sample);
      expect(versions.map((v) => v.version), ['0.1.2', '0.1.0']);
      expect(versions.first.date, DateTime(2026, 11, 8));
      expect(versions.first.paragraphs, ['Deuxième version.', '• Une puce.']);
    });

    test('liste vide acceptée', () {
      expect(lireNouveautes('{"versions": []}'), isEmpty);
    });

    String une(Map<String, Object?> version) => jsonEncode({
      'versions': [version],
    });
    const valide = {
      'version': '0.1.0',
      'date': '2026-11-01',
      'paragraphs': ['Texte.'],
    };

    for (final (label, source) in [
      ('JSON illisible', '{'),
      ('racine liste', '[]'),
      ('versions absent', '{}'),
      ('version non objet', '{"versions": ["0.1.0"]}'),
      ('version absente', une({...valide}..remove('version'))),
      ('version mal formée', une({...valide, 'version': 'v0.1'})),
      ('date absente', une({...valide}..remove('date'))),
      ('date invalide', une({...valide, 'date': '2026-02-30'})),
      ('date avec heure', une({...valide, 'date': '2026-11-01T10:00'})),
      ('paragraphes absents', une({...valide}..remove('paragraphs'))),
      ('paragraphes vides', une({...valide, 'paragraphs': <String>[]})),
      (
        'paragraphe non texte',
        une({
          ...valide,
          'paragraphs': [3],
        }),
      ),
      (
        'paragraphe blanc',
        une({
          ...valide,
          'paragraphs': ['  '],
        }),
      ),
    ]) {
      test('lève : $label', () {
        expect(() => lireNouveautes(source), throwsFormatException);
      });
    }

    test('la copie versionnée de l\'asset est lisible', () {
      final versions = lireNouveautes(
        File('assets/changelog_recent.json').readAsStringSync(),
      );
      expect(versions, isNotEmpty);
      expect(versions.length, lessThanOrEqualTo(6));
    });
  });

  group('route', () {
    test('/nouveautes : membre accepté, non connecté renvoyé', () {
      const granted = AccessGranted(
        user: brewerUser,
        member: brewerMember,
        offline: false,
      );
      expect(redirectFor(granted, Uri.parse(AppRoutes.news)), isNull);
      expect(
        redirectFor(const AccessSignedOut(), Uri.parse(AppRoutes.news)),
        '/connexion?depuis=%2Fnouveautes',
      );
    });
  });

  Future<TestApp> signedIn(
    WidgetTester tester, {
    double width = 400,
    String? appVersion = '0.1.0',
    Future<String> Function()? source,
  }) async {
    final app = TestApp(appVersion: appVersion);
    app.nouveautes = source ?? () async => _sample;
    await app.pump(tester, width: width);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> openFromMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mon compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouveautés'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'menu du compte : Nouveautés après Mes tickets, avant la déconnexion',
    (tester) async {
      await signedIn(tester);
      await tester.tap(find.byTooltip('Mon compte'));
      await tester.pumpAndSettle();
      final items = tester
          .widgetList<MenuItemButton>(find.byType(MenuItemButton))
          .map((b) => (b.child! as Text).data)
          .toList();
      expect(items, [
        'Mes prix',
        'Préférences',
        'Signaler ou proposer',
        'Mes tickets',
        'Nouveautés',
        'Sources des données',
        'Se déconnecter',
      ]);
      expect(find.byIcon(Icons.new_releases_outlined), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
    },
  );

  testWidgets('ouvert depuis le menu : liste, pastille, retour par pop', (
    tester,
  ) async {
    await signedIn(tester);
    await openFromMenu(tester);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Nouveautés'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Version installée : 0.1.0. Seules les versions qui changent ce que '
        'vous voyez sont listées.',
      ),
      findsOneWidget,
    );
    expect(find.text('Version 0.1.2'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('8 novembre 2026'), findsOneWidget);
    expect(find.text('1er novembre 2026'), findsOneWidget);
    expect(find.text('• Une puce.'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    // Une seule pastille, sur la carte de la version installée.
    expect(find.byType(Etiquette), findsOneWidget);
    final card = find.ancestor(
      of: find.text('Version 0.1.0'),
      matching: find.byType(Card),
    );
    expect(
      find.descendant(of: card, matching: find.text('Installée')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('Version 0.1.2')),
      matchesSemantics(label: 'Version 0.1.2', isHeader: true),
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NouveautesScreen), findsNothing);
    expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('version illisible : en-tête « indisponible », aucune pastille', (
    tester,
  ) async {
    await signedIn(tester, appVersion: null);
    await openFromMenu(tester);
    expect(
      find.text(
        'Version installée indisponible. Seules les versions qui changent ce '
        'que vous voyez sont listées.',
      ),
      findsOneWidget,
    );
    expect(find.byType(Etiquette), findsNothing);
  });

  testWidgets('fichier mal formé : panne journalisée, Réessayer relit', (
    tester,
  ) async {
    var content = '{"versions": [{"version": "x"}]}';
    final app = await signedIn(tester, source: () async => content);
    await openFromMenu(tester);
    expect(find.text(NouveautesScreen.errorMessage), findsOneWidget);
    expect(app.errors.reports.map((r) => r.feature), ['nouveautes']);
    expect(app.errors.reports.single.error, isA<FormatException>());

    content = _sample;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Version 0.1.2'), findsOneWidget);
    expect(app.errors.reports, hasLength(1));
  });

  testWidgets('aucune version : état vide, retour à l\'accueil', (
    tester,
  ) async {
    await signedIn(tester, source: () async => '{"versions": []}');
    await openFromMenu(tester);
    expect(find.text(NouveautesScreen.emptyMessage), findsOneWidget);
    await tester.tap(find.text("Revenir à l'accueil"));
    await tester.pumpAndSettle();
    expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('ouvert par son adresse : la flèche retour mène à l\'accueil', (
    tester,
  ) async {
    final app = await signedIn(tester);
    app.container.read(routerProvider).go(AppRoutes.news);
    await tester.pumpAndSettle();
    expect(find.byType(NouveautesScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('grand écran : colonne bornée à 840 px', (tester) async {
    await signedIn(tester, width: 1400);
    await openFromMenu(tester);
    expect(
      tester.getSize(find.byType(Card).first).width,
      lessThanOrEqualTo(840),
    );
  });

  testWidgets('texte × 2 sur 360 px : aucun débordement', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await signedIn(tester, width: 360);
    await openFromMenu(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Version 0.1.2'), findsOneWidget);
  });
}
