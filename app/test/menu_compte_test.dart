import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/menu_compte.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/auth/domain/session_user.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/tickets/domain/ticket_screens.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

/// Menu du compte sur les pages pleines, hors de la coquille (ticket #39).
void main() {
  /// Avance de 1 s : une page en chargement (indicateur animé) ne se pose
  /// jamais, `pumpAndSettle` attendrait sans fin.
  Future<void> avancer(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<TestApp> ouvrir(
    WidgetTester tester,
    String path, {
    bool admin = false,
    double width = 400,
  }) async {
    final app = TestApp();
    await app.pump(tester, width: width);
    if (admin) {
      app.signIn(adminUser, member: adminMember);
    } else {
      app.signIn(brewerUser, member: brewerMember);
    }
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go(path);
    await avancer(tester);
    return app;
  }

  Future<void> ouvrirMenu(WidgetTester tester) async {
    await tester.tap(find.byType(MenuCompte));
    await avancer(tester);
  }

  Finder entree(String label) =>
      find.widgetWithText(MenuItemButton, label, skipOffstage: false);

  const toutes = [
    'Mes prix',
    'Mes processus',
    'Préférences',
    'Signaler ou proposer',
    'Mes tickets',
    'Nouveautés',
    'Sources des données',
    'Se déconnecter',
  ];

  for (final (path, masquee) in [
    ('/prix', 'Mes prix'),
    ('/processus', 'Mes processus'),
    ('/preferences', 'Préférences'),
    ('/tickets/nouveau', 'Signaler ou proposer'),
    ('/tickets', 'Mes tickets'),
    ('/nouveautes', 'Nouveautés'),
    ('/sources-des-donnees', 'Sources des données'),
  ]) {
    testWidgets('$path : menu présent, sans « $masquee »', (tester) async {
      await ouvrir(tester, path);
      expect(find.byType(MenuCompte), findsOneWidget);
      await ouvrirMenu(tester);
      for (final label in toutes) {
        expect(
          entree(label),
          label == masquee ? findsNothing : findsOneWidget,
          reason: label,
        );
      }
    });
  }

  for (final (path, gardee) in [
    ('/processus/nouveau', 'Mes processus'),
    ('/tickets/t1', 'Mes tickets'),
    ('/admin', 'Tickets à traiter'),
  ]) {
    testWidgets('$path garde « $gardee »', (tester) async {
      await ouvrir(tester, path, admin: true);
      await ouvrirMenu(tester);
      expect(entree(gardee), findsOneWidget);
    });
  }

  testWidgets('admin sur Admin › Tickets : pas de « Tickets à traiter »', (
    tester,
  ) async {
    await ouvrir(tester, '/admin/tickets', admin: true);
    await ouvrirMenu(tester);
    expect(entree('Tickets à traiter'), findsNothing);
    expect(entree('Mes tickets'), findsOneWidget);
  });

  testWidgets('Admin › Import : menu du compte', (tester) async {
    await ouvrir(tester, '/admin/import', admin: true);
    expect(find.byType(MenuCompte), findsOneWidget);
  });

  testWidgets('écran d\'accès : aucun menu', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.auth.session.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Se connecter avec Google'), findsOneWidget);
    expect(find.byType(MenuCompte), findsNothing);
  });

  group('éditeur', () {
    Future<void> modifier(WidgetTester tester) async {
      await tester.enterText(find.byType(TextFormField).first, 'Ma recette');
      await tester.pumpAndSettle();
    }

    testWidgets('sans modification : déconnexion directe', (tester) async {
      final app = await ouvrir(tester, '/recettes/nouvelle');
      await ouvrirMenu(tester);
      await tester.tap(entree('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(app.auth.signOutCalls, 1);
    });

    testWidgets('modifié : « Abandonner les modifications ? » d\'abord', (
      tester,
    ) async {
      final app = await ouvrir(tester, '/recettes/nouvelle');
      await modifier(tester);
      await ouvrirMenu(tester);
      await tester.tap(entree('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      expect(app.auth.signOutCalls, 0);
      expect(find.text('Ma recette'), findsOneWidget);

      await ouvrirMenu(tester);
      await tester.tap(entree('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(app.auth.signOutCalls, 1);
    });

    testWidgets('modifié : « Mes processus » confirme aussi', (tester) async {
      await ouvrir(tester, '/recettes/nouvelle');
      await modifier(tester);
      await ouvrirMenu(tester);
      await tester.tap(entree('Mes processus'));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner les modifications ?'), findsOneWidget);
      await tester.tap(find.text('Abandonner'));
      await avancer(tester);
      expect(find.text('Mes processus'), findsWidgets);
      expect(find.byType(MenuCompte), findsOneWidget);
    });

    testWidgets('360 dp, texte à 200 % : barre sans débordement', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ouvrir(tester, '/recettes/nouvelle', width: 360);
      expect(tester.takeException(), isNull);
      expect(find.byType(MenuCompte), findsOneWidget);
      expect(find.text('Enregistrer'), findsOneWidget);
    });
  });

  group('écran du jour', () {
    final h = DateTime(2026, 11, 8);
    DateTime hm(int hh, int mm) => DateTime(h.year, h.month, h.day, hh, mm);
    const avecPhoto = SessionUser(
      uid: 'uid-brasseur',
      email: 'Brasseur@Exemple.fr',
      displayName: 'Bruno Brasseur',
      photoUrl: 'https://exemple.fr/photo.png',
    );

    Future<TestApp> jour(
      WidgetTester tester, {
      List<BrewEvent> events = const [],
    }) async {
      final app = TestApp()..now = hm(12, 10);
      await app.pump(tester, height: 900);
      app.signIn(avecPhoto, member: brewerMember);
      app.brews.publish([unBrassin(id: 'b1', brewedAt: hm(11, 45))]);
      app.brews.publishEvents('b1', events);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1/jour');
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('initiale seule, aucune photo chargée', (tester) async {
      await jour(tester, events: [debut('e1', 'k-palier', hm(11, 45))]);
      expect(find.byType(BrewDayScreen), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(
        find.descendant(
          of: find.byType(MenuCompte),
          matching: find.byType(CircleAvatar),
        ),
      );
      expect(avatar.foregroundImage, isNull);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('« Mes prix » par push : l\'écran du jour reste, verrou pris', (
      tester,
    ) async {
      final app = await jour(
        tester,
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      await ouvrirMenu(tester);
      await tester.tap(entree('Mes prix'));
      await avancer(tester);
      expect(app.container.read(routerProvider).state.uri.path, '/prix');
      expect(find.byType(BrewDayScreen, skipOffstage: false), findsOneWidget);
      expect(app.wakelockCalls.last, isTrue);
    });

    testWidgets('aucune saisie en attente : déconnexion directe', (
      tester,
    ) async {
      final app = await jour(
        tester,
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      await ouvrirMenu(tester);
      await tester.tap(entree('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(app.auth.signOutCalls, 1);
    });

    testWidgets('saisies en attente : « Se déconnecter ? »', (tester) async {
      final app = await jour(
        tester,
        events: [
          debut('e1', 'k-palier', hm(11, 45)),
          mesure(
            'm1',
            'k-palier',
            MeasureType.gravity,
            1.05,
            hm(12, 0),
            pending: true,
          ),
          mesure(
            'm2',
            'k-palier',
            MeasureType.temperature,
            66,
            hm(12, 5),
            pending: true,
          ),
        ],
      );
      await ouvrirMenu(tester);
      await tester.tap(entree('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(find.text(TextesDeconnexion.titre), findsOneWidget);
      expect(find.text(TextesDeconnexion.message(2)), findsOneWidget);
      await tester.tap(find.text(TextesDeconnexion.rester));
      await tester.pumpAndSettle();
      expect(app.auth.signOutCalls, 0);
      expect(find.byType(BrewDayScreen), findsOneWidget);

      await ouvrirMenu(tester);
      await tester.tap(entree('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(TextesDeconnexion.deconnecter),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.auth.signOutCalls, 1);
    });
  });

  test('texte de la déconnexion : singulier et pluriel', () {
    expect(
      TextesDeconnexion.message(1),
      '1 saisie attend le réseau. Si vous vous déconnectez maintenant, elle '
      'risque de ne jamais partir.',
    );
    expect(
      TextesDeconnexion.message(3),
      '3 saisies attendent le réseau. Si vous vous déconnectez maintenant, '
      'elles risquent de ne jamais partir.',
    );
  });

  test('pages pleines : élément « Menu du compte » proposé', () {
    for (final screen in kTicketAccountMenuScreens) {
      expect(
        ticketElementOptions(screen, isAdmin: true).map((o) => o.value),
        contains('$screen/menu/compte'),
        reason: screen,
      );
    }
    expect(ticketScreenLabel('/prix/menu/compte'), 'Mes prix › Menu du compte');
  });

  test('kEntreeDeLEcran : un écran par entrée', () {
    expect(kEntreeDeLEcran.values.toSet().length, kEntreeDeLEcran.length);
    expect(kEntreeDeLEcran.values.toSet(), EntreeCompte.values.toSet());
  });
}
