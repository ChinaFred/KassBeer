import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/menu_compte.dart';
import 'package:kass_beer/core/presentation/zone_capture.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_screens.dart';
import 'package:kass_beer/features/tickets/presentation/capture_ticket.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_form_screen.dart';
import 'package:kass_beer/features/tickets/presentation/vignette_capture.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';
import 'support/ticket_fixtures.dart';

/// Ticket #38 : « Écran concerné » est l'écran quitté, et la capture de cet
/// écran se joint au ticket (ADR-008, T6).
void main() {
  Future<void> avancer(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> signaler(WidgetTester tester) async {
    await tester.tap(find.byType(MenuCompte).last);
    await avancer(tester);
    await tester.tap(
      find.widgetWithText(MenuItemButton, 'Signaler ou proposer'),
    );
    await avancer(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  /// « Écran concerné » affiche [label].
  void ecranConcerne(String label) {
    final champ = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Écran concerné',
    );
    expect(champ, findsOneWidget);
    expect(
      find.descendant(of: champ, matching: find.text(label)),
      findsOneWidget,
    );
  }

  group('écran concerné', () {
    testWidgets('admin au téléphone : fiche ouverte par push', (tester) async {
      final app = TestApp();
      await app.pump(tester, width: 400);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.publishAll([unTicket(title: 'Densité fausse')]);
      app.tickets.publishDecisions('t1', const []);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await avancer(tester);
      await tester.tap(find.text('Densité fausse'));
      await avancer(tester);
      expect(
        app.container.read(routerProvider).state.fullPath,
        '/admin/tickets/:id',
      );
      await signaler(tester);
      expect(
        app.container.read(routerProvider).state.uri.path,
        AppRoutes.newTicket,
      );
      ecranConcerne('Admin › Ticket d\'un membre');
    });

    testWidgets('brasseur : recette empilée par push dans la coquille', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester, width: 400);
      app.signIn(brewerUser, member: brewerMember);
      app.recipes.publish([
        const Recipe(
          id: 'r1',
          ownerUid: 'uid-brasseur',
          ownerName: 'Bruno Brasseur',
          content: RecipeContent(name: 'Blonde'),
        ),
      ]);
      await tester.pumpAndSettle();
      final router = app.container.read(routerProvider);
      router.go(AppRoutes.brews);
      await avancer(tester);
      unawaited(router.push(AppRoutes.recipe('r1')));
      await avancer(tester);
      await signaler(tester);
      ecranConcerne('Recette');
      expect(app.tickets.created, isEmpty);
    });
  });

  const recette = Recipe(
    id: 'r1',
    ownerUid: 'uid-brasseur',
    ownerName: 'Bruno Brasseur',
    content: RecipeContent(name: 'Blonde'),
  );

  Future<TestApp> brasseur(
    WidgetTester tester, {
    bool offline = false,
    String path = '/recettes/r1',
  }) async {
    final app = TestApp();
    await app.pump(tester, width: 400);
    app.signIn(brewerUser, member: brewerMember, fromCache: offline);
    app.recipes.publish([recette]);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go(path);
    await avancer(tester);
    return app;
  }

  Future<void> remplir(WidgetTester tester) async {
    await tester.tap(find.text('Bug'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Titre'),
      'Densité fausse',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'La densité affichée est fausse.',
    );
    await tester.pump();
  }

  Finder caseCapture() =>
      find.widgetWithText(CheckboxListTile, TicketFormScreen.captureAttach);

  Future<void> cocher(WidgetTester tester) async {
    await tester.ensureVisible(caseCapture());
    await tester.pump();
    await tester.tap(caseCapture());
    await tester.pump();
  }

  Future<void> envoyer(WidgetTester tester) async {
    await tester.tap(find.text('Envoyer'));
    await avancer(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  group('capture dans le formulaire', () {
    testWidgets('prise au moment de l\'appui, case décochée, vignette', (
      tester,
    ) async {
      final app = await brasseur(tester);
      expect(app.captureCalls, 0);
      await signaler(tester);
      expect(app.captureCalls, 1);
      expect(find.text(TextesCapture.titre), findsOneWidget);
      final tile = tester.widget<CheckboxListTile>(caseCapture());
      expect(tile.value, isFalse);
      expect(find.text(TicketFormScreen.captureHelp), findsOneWidget);
      expect(find.byType(VignetteCapture), findsOneWidget);
    });

    testWidgets('Recette : avertissement des prix', (tester) async {
      await brasseur(tester);
      await signaler(tester);
      expect(find.text(TicketFormScreen.capturePrices), findsOneWidget);
    });

    testWidgets('Préférences : aucun avertissement des prix', (tester) async {
      await brasseur(tester, path: AppRoutes.preferences);
      await signaler(tester);
      expect(caseCapture(), findsOneWidget);
      expect(find.text(TicketFormScreen.capturePrices), findsNothing);
    });

    test('écrans qui montrent des prix', () {
      for (final ecran in kTicketScreensWithPrices) {
        expect(kTicketScreenNames, contains(ecran), reason: ecran);
      }
      expect(kTicketScreensWithPrices, {
        '/recettes/:id',
        '/brassins/:id',
        '/brassins/:id/jour',
        '/brassins/:id/jour/:journee',
        '/brassins/:id/jour/:journee/preparer',
        '/prix',
      });
    });

    testWidgets('case décochée : le ticket part sans capture', (tester) async {
      final app = await brasseur(tester);
      app.tickets.serverAnswer = () async {};
      await signaler(tester);
      await remplir(tester);
      await envoyer(tester);
      expect(app.tickets.created, hasLength(1));
      expect(app.tickets.screenshotsAttached, isEmpty);
    });

    testWidgets('case cochée : dépôt après l\'acceptation du ticket', (
      tester,
    ) async {
      final app = await brasseur(tester);
      final accepte = Completer<void>();
      app.tickets.serverAnswer = () => accepte.future;
      await signaler(tester);
      await remplir(tester);
      await cocher(tester);
      await envoyer(tester);
      // Formulaire fermé sans attendre ; rien n'est déposé avant le serveur.
      expect(find.byType(TicketFormScreen), findsNothing);
      expect(find.text(TicketFormScreen.sentOnline), findsOneWidget);
      expect(app.tickets.screenshotsAttached, isEmpty);
      accepte.complete();
      await avancer(tester);
      final jointe = app.tickets.screenshotsAttached.single;
      expect(jointe.ticketId, app.tickets.created.single.id);
      expect(jointe.authorUid, 'uid-brasseur');
      expect(jointe.png, kPngDeTest);
      expect(find.text(TicketFormScreen.sentWithoutCapture), findsNothing);
    });

    testWidgets('dépôt en échec : « Ticket enregistré sans la capture. »', (
      tester,
    ) async {
      final app = await brasseur(tester);
      app.tickets.serverAnswer = () async {};
      app.tickets.attachResult = () async => false;
      await signaler(tester);
      await remplir(tester);
      await cocher(tester);
      await envoyer(tester);
      expect(app.tickets.screenshotsAttached, hasLength(1));
      expect(find.text(TicketFormScreen.sentWithoutCapture), findsOneWidget);
    });

    testWidgets('ticket non accepté en 30 s : sans la capture, rapporté', (
      tester,
    ) async {
      final app = await brasseur(tester);
      await signaler(tester);
      await remplir(tester);
      await cocher(tester);
      await envoyer(tester);
      await tester.pump(TicketFormScreen.captureWaitTimeout);
      await avancer(tester);
      expect(app.tickets.screenshotsAttached, isEmpty);
      expect(find.text(TicketFormScreen.sentWithoutCapture), findsOneWidget);
      final report = app.errors.reports.singleWhere(
        (r) => r.feature == 'tickets.screenshot',
      );
      expect(report.context, isNot(contains('screenshot')));
    });

    testWidgets('ticket refusé : aucune capture déposée', (tester) async {
      final app = await brasseur(tester);
      app.tickets.serverAnswer = () async => throw StateError('refusé');
      await signaler(tester);
      await remplir(tester);
      await cocher(tester);
      await envoyer(tester);
      expect(app.tickets.screenshotsAttached, isEmpty);
      expect(find.text(TicketFormScreen.refused), findsOneWidget);
    });

    testWidgets('hors ligne : le ticket part sans la capture', (tester) async {
      final app = await brasseur(tester, offline: true);
      await signaler(tester);
      await remplir(tester);
      await cocher(tester);
      await envoyer(tester);
      expect(app.tickets.created, hasLength(1));
      expect(app.tickets.screenshotsAttached, isEmpty);
      expect(
        find.text(TicketFormScreen.sentOfflineWithoutCapture),
        findsOneWidget,
      );
    });

    testWidgets('capture impossible : pas de section', (tester) async {
      final app = await brasseur(tester);
      app.capture = null;
      await signaler(tester);
      expect(app.captureCalls, 1);
      expect(find.text(TicketFormScreen.titre), findsWidgets);
      expect(caseCapture(), findsNothing);
    });

    testWidgets('depuis « Mes tickets » : aucune capture', (tester) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.publish(const []);
      await avancer(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, TicketFormScreen.titre),
      );
      await avancer(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TicketFormScreen), findsOneWidget);
      expect(app.captureCalls, 0);
      expect(caseCapture(), findsNothing);
    });

    testWidgets('adresse directe : aucune capture, même en attente', (
      tester,
    ) async {
      final app = await brasseur(tester);
      app.container
          .read(captureEnAttenteProvider)
          .poser(CaptureEcran(png: kPngDeTest, ecran: '/recettes/:id'));
      app.container.read(routerProvider).go(AppRoutes.newTicket);
      await avancer(tester);
      expect(find.byType(TicketFormScreen), findsOneWidget);
      expect(caseCapture(), findsNothing);
      // Prise une fois : le dépôt est vide.
      expect(app.container.read(captureEnAttenteProvider).prendre(), isNull);
    });

    testWidgets('« Reprendre » : aucune capture', (tester) async {
      final app = await brasseur(tester);
      app.container
          .read(captureEnAttenteProvider)
          .poser(CaptureEcran(png: kPngDeTest, ecran: kTicketScreenUnknown));
      unawaited(
        app.container
            .read(routerProvider)
            .push(
              AppRoutes.newTicket,
              extra: const TicketBrouillon(
                type: TicketType.bug,
                title: 'Densité fausse',
                description: 'La densité affichée est fausse.',
                screen: '/recettes/:id',
              ),
            ),
      );
      await avancer(tester);
      expect(find.byType(TicketFormScreen), findsOneWidget);
      expect(caseCapture(), findsNothing);
    });

    testWidgets('écran du jour : capture locale, prix signalés, verrou pris', (
      tester,
    ) async {
      final h = DateTime(2026, 11, 8);
      final app = TestApp()..now = DateTime(h.year, h.month, h.day, 12, 10);
      await app.pump(tester, height: 900);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([
        unBrassin(id: 'b1', brewedAt: DateTime(h.year, h.month, h.day, 11, 45)),
      ]);
      app.brews.publishEvents('b1', [
        debut('e1', 'k-palier', DateTime(h.year, h.month, h.day, 11, 45)),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1/jour');
      await tester.pumpAndSettle();
      expect(find.byType(BrewDayScreen), findsOneWidget);
      await signaler(tester);
      expect(app.captureCalls, 1);
      ecranConcerne('Jour de brassage');
      expect(caseCapture(), findsOneWidget);
      expect(find.text(TicketFormScreen.capturePrices), findsOneWidget);
      // L'écran du jour reste dessous, verrou d'écran pris ; rien n'est
      // déposé tant que le ticket n'est pas envoyé.
      expect(find.byType(BrewDayScreen, skipOffstage: false), findsOneWidget);
      expect(app.wakelockCalls.last, isTrue);
      expect(app.tickets.screenshotsAttached, isEmpty);
    });
  });

  group('capture dans le suivi', () {
    const chemin = 'tickets/uid-brasseur/t1/screenshot.png';

    testWidgets('auteur : vignette lue par getData', (tester) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.screenshots[chemin] = kPngDeTest;
      app.tickets.publish([unTicket(screenshotPath: chemin)]);
      app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
      await avancer(tester);
      expect(app.tickets.screenshotReads, [chemin]);
      expect(find.byType(VignetteCapture), findsOneWidget);
    });

    testWidgets('lecture en échec : « Capture indisponible. »', (tester) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.publish([unTicket(screenshotPath: chemin)]);
      app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
      await avancer(tester);
      expect(find.text(TextesCapture.indisponible), findsOneWidget);
    });

    testWidgets('sans capture : rien', (tester) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.publish([unTicket()]);
      app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
      await avancer(tester);
      expect(find.byType(CaptureDuTicket), findsNothing);
      expect(app.tickets.screenshotReads, isEmpty);
    });

    testWidgets('Admin › Tickets : vignette agrandissable', (tester) async {
      final app = TestApp();
      await app.pump(tester, width: 400);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.screenshots[chemin] = kPngDeTest;
      app.tickets.publishAll([unTicket(screenshotPath: chemin)]);
      app.tickets.publishDecisions('t1', const []);
      app.container.read(routerProvider).go(AppRoutes.adminTicket('t1'));
      await avancer(tester);
      final vignette = find.descendant(
        of: find.byType(VignetteCapture),
        matching: find.byType(InkWell),
      );
      await tester.ensureVisible(vignette);
      await tester.pump();
      await tester.tap(vignette);
      await avancer(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip(TextesCapture.fermer));
      await avancer(tester);
      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });

  group('domaine et dépôt de données', () {
    testWidgets('zone : le corps du Scaffold, sans la barre du haut', (
      tester,
    ) async {
      late BuildContext barre;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                Builder(
                  builder: (context) {
                    barre = context;
                    return const SizedBox(width: 10);
                  },
                ),
              ],
            ),
            body: const ZoneCapture(child: Text('Contenu')),
          ),
        ),
      );
      final zone = zoneCaptureDe(barre);
      expect(zone, isNotNull);
      expect(zone, tester.renderObject(find.byType(ZoneCapture)));
      expect(zone!.size.height, lessThan(600 - kToolbarHeight + 1));
    });

    test('chaque page qui porte le menu du compte a sa zone de capture', () {
      final sansZone = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              !f.path.endsWith('menu_compte.dart') &&
              f.readAsStringSync().contains('MenuCompte(') &&
              !f.readAsStringSync().contains('ZoneCapture('))
            f.path,
      ];
      expect(sansZone, isEmpty);
    });

    test('échelle : 2 au plus, 2 000 px au plus de côté', () {
      expect(
        echelleCapture(width: 400, height: 800, devicePixelRatio: 3),
        kCaptureMaxScale,
      );
      expect(
        echelleCapture(width: 400, height: 800, devicePixelRatio: 1.5),
        1.5,
      );
      expect(
        echelleCapture(width: 1600, height: 900, devicePixelRatio: 2),
        closeTo(1.25, 1e-9),
      );
      expect(echelleCapture(width: 0, height: 0, devicePixelRatio: 2), isNull);
    });

    test('screenshot_path lu sur le ticket', () {
      final t = Ticket.fromFirestore('t1', {
        'type': 'bug',
        'title': 'Densité fausse',
        'description': 'La densité affichée est fausse.',
        'screen': '/recettes/:id',
        'status': 'received',
        'screenshot_path': 'tickets/u/t1/screenshot.png',
      });
      expect(t.screenshotPath, 'tickets/u/t1/screenshot.png');
      expect(kTicketScreenshotPathPattern.hasMatch(t.screenshotPath!), isTrue);
      expect(ticketScreenshotPath('u', 't1'), t.screenshotPath);
    });

    FirestoreTicketsRepository depot(
      RecordingErrorReportService errors, {
      required List<String> journal,
      Object? panneDepot,
      Object? panneAppel,
      Map<String, Uint8List?> fichiers = const {},
    }) => FirestoreTicketsRepository(
      errorReportService: errors,
      firestore: FakeFirebaseFirestore(),
      deposer: (path, bytes, contentType) async {
        journal.add('depot $path $contentType ${bytes.length}');
        if (panneDepot != null) throw panneDepot;
      },
      callable: (name, data) async {
        journal.add('appel $name ${data['ticketId']} ${data['path']}');
        if (panneAppel != null) throw panneAppel;
        return {'ok': true};
      },
      lire: (path, maxBytes) async {
        journal.add('lecture $path $maxBytes');
        return fichiers[path];
      },
    );

    test('attachScreenshot : dépôt PNG, puis callable', () async {
      final errors = RecordingErrorReportService();
      final journal = <String>[];
      final ok = await depot(
        errors,
        journal: journal,
      ).attachScreenshot(ticketId: 't1', authorUid: 'u', png: kPngDeTest);
      expect(ok, isTrue);
      expect(journal, [
        'depot tickets/u/t1/screenshot.png image/png ${kPngDeTest.length}',
        'appel attachTicketScreenshot t1 tickets/u/t1/screenshot.png',
      ]);
      expect(errors.reports, isEmpty);
    });

    test('dépôt refusé : faux, rapporté sans chemin ni contenu', () async {
      final errors = RecordingErrorReportService();
      final journal = <String>[];
      final ok = await depot(
        errors,
        journal: journal,
        panneDepot: FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
        ),
      ).attachScreenshot(ticketId: 't1', authorUid: 'u', png: kPngDeTest);
      expect(ok, isFalse);
      expect(journal, hasLength(1));
      final report = errors.reports.single;
      expect(report.feature, 'tickets.screenshot');
      expect(report.context, 'tickets/t1 step=upload code=unauthorized');
    });

    test('callable refusée : faux, rapportée', () async {
      final errors = RecordingErrorReportService();
      final ok = await depot(
        errors,
        journal: [],
        panneAppel: FirebaseFunctionsException(
          code: 'invalid-argument',
          message:
              'Seules les images PNG ou JPEG de 5 Mo au plus sont '
              'acceptées.',
        ),
      ).attachScreenshot(ticketId: 't1', authorUid: 'u', png: kPngDeTest);
      expect(ok, isFalse);
      expect(
        errors.reports.single.context,
        'tickets/t1 step=attach code=invalid-argument',
      );
    });

    test('loadScreenshot : bornée à 5 Mo, chemin hors motif non lu', () async {
      final errors = RecordingErrorReportService();
      final journal = <String>[];
      final repo = depot(
        errors,
        journal: journal,
        fichiers: {'tickets/u/t1/screenshot.png': kPngDeTest},
      );
      expect(
        await repo.loadScreenshot('tickets/u/t1/screenshot.png'),
        kPngDeTest,
      );
      expect(
        journal.single,
        'lecture tickets/u/t1/screenshot.png $kTicketScreenshotMaxBytes',
      );
      await expectLater(
        repo.loadScreenshot('tickets/u/../t1/screenshot.png'),
        throwsFormatException,
      );
      await expectLater(
        repo.loadScreenshot('tickets/u/t2/screenshot.png'),
        throwsFormatException,
      );
      expect(journal, hasLength(2));
      expect(errors.reports, hasLength(2));
      for (final r in errors.reports) {
        expect(r.context, isNot(contains('tickets/')));
      }
    });
  });
}
