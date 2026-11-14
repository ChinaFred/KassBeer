import 'dart:async';
import 'dart:io';

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/fichiers/echange_fichiers.dart';
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
/// En-tête PNG seul (signature et bloc IHDR) annonçant [largeur] × [hauteur].
Uint8List pngEntete(int largeur, int hauteur) {
  final octets = Uint8List(33);
  octets.setAll(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  final vue = ByteData.sublistView(octets);
  vue.setUint32(8, 13);
  octets.setAll(12, 'IHDR'.codeUnits);
  vue.setUint32(16, largeur);
  vue.setUint32(20, hauteur);
  return octets;
}

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
      // Lu avant la case.
      expect(
        tester.getTopLeft(find.text(TicketFormScreen.capturePrices)).dy,
        lessThan(tester.getTopLeft(caseCapture()).dy),
      );
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

  group('image choisie dans le formulaire', () {
    Finder boutonChoisir() =>
        find.widgetWithText(OutlinedButton, TicketFormScreen.imagePick);

    Future<void> choisir(WidgetTester tester) async {
      await tester.ensureVisible(boutonChoisir());
      await tester.pump();
      await tester.tap(boutonChoisir());
      await avancer(tester);
    }

    final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    final preparee = Uint8List.fromList([...kPngDeTest]);

    Future<TestApp> depuisMesTickets(WidgetTester tester) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.publish(const []);
      await avancer(tester);
      await tester.tap(
        find.widgetWithText(FilledButton, TicketFormScreen.titre),
      );
      await avancer(tester);
      await tester.pump(const Duration(seconds: 1));
      return app;
    }

    testWidgets('sans écran précédent : « Choisir une image » seul', (
      tester,
    ) async {
      await depuisMesTickets(tester);
      expect(caseCapture(), findsNothing);
      expect(boutonChoisir(), findsOneWidget);
      expect(find.text(TicketFormScreen.captureHelp), findsOneWidget);
    });

    testWidgets('sélecteur filtré, borne de 5 Mo, image réencodée envoyée', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      app.tickets.serverAnswer = () async {};
      final recus = <Uint8List>[];
      app.preparer = (octets) async {
        recus.add(octets);
        return preparee;
      };
      app.fichiers.choix = FichierChoisi('photo.jpg', jpeg);
      await remplir(tester);
      await choisir(tester);
      expect(app.fichiers.typesDemandes, kTypesImages);
      expect(app.fichiers.maxOctetsDemande, kTicketScreenshotMaxBytes);
      expect(recus.single, jpeg);
      expect(find.byType(VignetteCapture), findsOneWidget);
      expect(find.text(TicketFormScreen.imageRemove), findsOneWidget);
      expect(boutonChoisir(), findsNothing);
      await envoyer(tester);
      final jointe = app.tickets.screenshotsAttached.single;
      expect(jointe.png, same(preparee));
      expect(jointe.ticketId, app.tickets.created.single.id);
    });

    testWidgets('« Retirer l\'image » : le ticket part sans image', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      app.tickets.serverAnswer = () async {};
      app.fichiers.choix = FichierChoisi('photo.png', kPngDeTest);
      await remplir(tester);
      await choisir(tester);
      await tester.ensureVisible(find.text(TicketFormScreen.imageRemove));
      await tester.tap(find.text(TicketFormScreen.imageRemove));
      await tester.pump();
      expect(boutonChoisir(), findsOneWidget);
      await envoyer(tester);
      expect(app.tickets.created, hasLength(1));
      expect(app.tickets.screenshotsAttached, isEmpty);
    });

    testWidgets('une seule image : choisir décoche, cocher retire', (
      tester,
    ) async {
      final app = await brasseur(tester);
      app.tickets.serverAnswer = () async {};
      app.preparer = (octets) async => preparee;
      app.fichiers.choix = FichierChoisi('photo.png', kPngDeTest);
      await signaler(tester);
      await remplir(tester);
      await cocher(tester);
      expect(tester.widget<CheckboxListTile>(caseCapture()).value, isTrue);
      await choisir(tester);
      expect(tester.widget<CheckboxListTile>(caseCapture()).value, isFalse);
      expect(find.text(TicketFormScreen.imageRemove), findsOneWidget);
      await cocher(tester);
      expect(tester.widget<CheckboxListTile>(caseCapture()).value, isTrue);
      expect(find.text(TicketFormScreen.imageRemove), findsNothing);
      expect(boutonChoisir(), findsOneWidget);
      await envoyer(tester);
      // La capture de l'écran part, pas l'image retirée.
      expect(app.tickets.screenshotsAttached.single.png, kPngDeTest);
    });

    testWidgets('choisir une image après la case : l\'image part seule', (
      tester,
    ) async {
      final app = await brasseur(tester);
      app.tickets.serverAnswer = () async {};
      app.preparer = (octets) async => preparee;
      app.fichiers.choix = FichierChoisi('photo.png', kPngDeTest);
      await signaler(tester);
      await remplir(tester);
      await cocher(tester);
      await choisir(tester);
      await envoyer(tester);
      expect(app.tickets.screenshotsAttached.single.png, same(preparee));
    });

    testWidgets('fichier de plus de 5 Mo : refusé, message', (tester) async {
      final app = await depuisMesTickets(tester);
      app.fichiers.choix = const FichierTropGros(6 * 1024 * 1024);
      await choisir(tester);
      expect(find.text(TicketFormScreen.imageTooLarge), findsOneWidget);
      expect(find.byType(VignetteCapture), findsNothing);
    });

    testWidgets('image réencodée de plus de 5 Mo : refusée, message', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      app.fichiers.choix = FichierChoisi('photo.jpg', jpeg);
      app.preparer = (octets) async => Uint8List(kTicketScreenshotMaxBytes + 1);
      await choisir(tester);
      expect(find.text(TicketFormScreen.imageTooLarge), findsOneWidget);
      expect(find.byType(VignetteCapture), findsNothing);
    });

    testWidgets('ouverture impossible : message', (tester) async {
      final app = await depuisMesTickets(tester);
      app.fichiers.choix = const ChoixImpossible();
      await choisir(tester);
      expect(find.text(TicketFormScreen.imageUnreadable), findsOneWidget);
    });

    testWidgets('image non décodée : message, rapport sans nom ni contenu', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      app.fichiers.choix = FichierChoisi('vacances-bruno.txt', jpeg);
      app.preparer = (octets) async =>
          throw Exception('Invalid image data vacances-bruno.txt');
      await choisir(tester);
      expect(find.text(TicketFormScreen.imageUnreadable), findsOneWidget);
      final report = app.errors.reports.singleWhere(
        (r) => r.feature == 'tickets.image',
      );
      expect('${report.error}', isNot(contains('vacances')));
      expect(report.context, isNot(contains('vacances')));
      expect(report.context, contains('${jpeg.length} octets'));
    });

    testWidgets('préparation : « Envoyer » grisé, indicateur, puis focus', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      final pret = Completer<Uint8List>();
      app.preparer = (octets) => pret.future;
      app.fichiers.choix = FichierChoisi('photo.jpg', jpeg);
      await remplir(tester);
      await choisir(tester);
      FilledButton envoyerBouton() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Envoyer'),
      );
      expect(envoyerBouton().onPressed, isNull);
      expect(find.text(TicketFormScreen.imagePreparing), findsOneWidget);
      expect(boutonChoisir(), findsNothing);
      pret.complete(preparee);
      await avancer(tester);
      expect(envoyerBouton().onPressed, isNotNull);
      expect(find.text(TicketFormScreen.imagePreparing), findsNothing);
      // Focus sur « Retirer l'image », puis rendu à « Choisir une image ».
      Focus? focusDe(Finder bouton) => tester
          .widgetList<Focus>(
            find.descendant(of: bouton, matching: find.byType(Focus)),
          )
          .firstOrNull;
      final retirer = find.widgetWithText(
        TextButton,
        TicketFormScreen.imageRemove,
      );
      expect(focusDe(retirer)?.focusNode?.hasFocus, isTrue);
      await tester.ensureVisible(retirer);
      await tester.tap(retirer);
      await avancer(tester);
      expect(focusDe(boutonChoisir())?.focusNode?.hasFocus, isTrue);
    });

    testWidgets('annulation et refus : focus rendu à « Choisir une image »', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      Focus? focusDe(Finder bouton) => tester
          .widgetList<Focus>(
            find.descendant(of: bouton, matching: find.byType(Focus)),
          )
          .firstOrNull;
      await choisir(tester);
      expect(focusDe(boutonChoisir())?.focusNode?.hasFocus, isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      app.fichiers.choix = const ChoixImpossible();
      await choisir(tester);
      expect(find.text(TicketFormScreen.imageUnreadable), findsOneWidget);
      expect(focusDe(boutonChoisir())?.focusNode?.hasFocus, isTrue);
    });

    testWidgets('préparation en cours : case de la capture désactivée', (
      tester,
    ) async {
      final app = await brasseur(tester);
      final pret = Completer<Uint8List>();
      app.preparer = (octets) => pret.future;
      app.fichiers.choix = FichierChoisi('photo.png', kPngDeTest);
      await signaler(tester);
      await choisir(tester);
      expect(tester.widget<CheckboxListTile>(caseCapture()).onChanged, isNull);
      pret.complete(preparee);
      await avancer(tester);
      expect(
        tester.widget<CheckboxListTile>(caseCapture()).onChanged,
        isNotNull,
      );
    });

    testWidgets('cocher la case efface l\'erreur du choix', (tester) async {
      final app = await brasseur(tester);
      app.fichiers.choix = const ChoixImpossible();
      await signaler(tester);
      await choisir(tester);
      expect(find.text(TicketFormScreen.imageUnreadable), findsOneWidget);
      await cocher(tester);
      expect(find.text(TicketFormScreen.imageUnreadable), findsNothing);
    });

    testWidgets('abandon avec une image : « Le texte saisi et l\'image… »', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      app.fichiers.choix = FichierChoisi('photo.png', kPngDeTest);
      await choisir(tester);
      await tester.tap(find.byTooltip('Fermer').first);
      await avancer(tester);
      expect(find.text(TicketFormScreen.abandonMessageImage), findsOneWidget);
    });

    testWidgets('abandon avec du texte seul : message inchangé', (
      tester,
    ) async {
      await depuisMesTickets(tester);
      await remplir(tester);
      await tester.tap(find.byTooltip('Fermer').first);
      await avancer(tester);
      expect(find.text(TicketFormScreen.abandonMessage), findsOneWidget);
    });

    testWidgets('IHDR de 30 000 × 30 000 : refusée sans décodage', (
      tester,
    ) async {
      final app = await depuisMesTickets(tester);
      app.preparer = preparerImage;
      app.fichiers.choix = FichierChoisi('bombe.png', pngEntete(30000, 30000));
      await choisir(tester);
      expect(find.text(TicketFormScreen.imageUnreadable), findsOneWidget);
      final report = app.errors.reports.singleWhere(
        (r) => r.feature == 'tickets.image',
      );
      expect(report.context, contains('ImageRefusee'));
      expect(report.context, isNot(contains('bombe')));
    });

    test('dimensions lues sans décoder : PNG, JPEG, WebP', () {
      expect(dimensionsImage(pngEntete(1080, 2400)), (
        largeur: 1080,
        hauteur: 2400,
      ));
      // JPEG : APP0, puis SOF0 (hauteur 300, largeur 400).
      final jpegEntete = Uint8List.fromList([
        0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00, //
        0xff, 0xc0, 0x00, 0x11, 0x08, 0x01, 0x2c, 0x01, 0x90, 0x03,
      ]);
      expect(dimensionsImage(jpegEntete), (largeur: 400, hauteur: 300));
      Uint8List webp(String bloc, List<int> suite) => Uint8List.fromList([
        ...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits, //
        ...bloc.codeUnits, 0, 0, 0, 0, ...suite,
        ...List.filled(12, 0),
      ]);
      // VP8X : largeur − 1 et hauteur − 1 sur 24 bits.
      expect(
        dimensionsImage(webp('VP8X', [0, 0, 0, 0, 0x3f, 0x1f, 0, 0x0f, 0, 0])),
        (largeur: 8000, hauteur: 16),
      );
      // VP8 : en-tête de trame, code 9d 01 2a, largeur et hauteur sur 14 bits.
      expect(
        dimensionsImage(
          webp('VP8 ', [0, 0, 0, 0x9d, 0x01, 0x2a, 0x80, 0x02, 0xe0, 0x01]),
        ),
        (largeur: 640, hauteur: 480),
      );
      // VP8L : signature 0x2f, largeur − 1 et hauteur − 1 sur 14 bits.
      final bits = (100 - 1) | ((50 - 1) << 14);
      expect(
        dimensionsImage(
          webp('VP8L', [
            0x2f,
            bits & 0xff,
            (bits >> 8) & 0xff,
            (bits >> 16) & 0xff,
            (bits >> 24) & 0xff,
          ]),
        ),
        (largeur: 100, hauteur: 50),
      );
      expect(dimensionsImage(pngEntete(10, 10).sublist(0, 20)), isNull);
      expect(dimensionsImage(Uint8List.fromList('GIF89a'.codeUnits)), isNull);
      expect(dimensionsImage(Uint8List(0)), isNull);
    });

    test('plafond de pixels comparé sans produit', () {
      expect(depasseMaxPixels(10000, 5000), isFalse);
      expect(depasseMaxPixels(10000, 5001), isTrue);
      expect(depasseMaxPixels(50000000, 1), isFalse);
      expect(depasseMaxPixels(1, 50000001), isTrue);
      expect(depasseMaxPixels(0xFFFFFFFF, 0xFFFFFFFF), isTrue);
      expect(depasseMaxPixels(0xC0000000, 0xC0000000), isTrue);
    });

    test('vérification avant décodage : format, côté nul, pixels', () {
      verifierImageAvantDecodage(pngEntete(10000, 5000));
      for (final (octets, raison) in [
        (pngEntete(10000, 5001), 'pixels'),
        (pngEntete(30000, 30000), 'pixels'),
        (pngEntete(0xFFFFFFFF, 0xFFFFFFFF), 'pixels'),
        (pngEntete(0xC0000000, 0xC0000000), 'pixels'),
        (pngEntete(50000001, 1), 'pixels'),
        (pngEntete(0, 10), 'format'),
        (Uint8List.fromList(List.filled(64, 7)), 'format'),
      ]) {
        expect(
          () => verifierImageAvantDecodage(octets),
          throwsA(
            isA<ImageRefusee>().having((e) => e.raison, 'raison', raison),
          ),
        );
      }
    });

    testWidgets('sélecteur fermé sans choix : rien ne change', (tester) async {
      final app = await depuisMesTickets(tester);
      await choisir(tester);
      expect(app.fichiers.choixDemandes, 1);
      expect(boutonChoisir(), findsOneWidget);
      expect(find.text(TicketFormScreen.imageUnreadable), findsNothing);
      expect(app.errors.reports, isEmpty);
    });

    test('taille visée : côté long à 2 000 px, proportions gardées', () {
      final petite = tailleImageChoisie(1080, 2000);
      expect(petite.width, isNull);
      expect(petite.height, isNull);
      final large = tailleImageChoisie(4000, 3000);
      expect(large.width, 2000);
      expect(large.height, isNull);
      final haute = tailleImageChoisie(3000, 4032);
      expect(haute.width, isNull);
      expect(haute.height, 2000);
    });

    testWidgets('preparerImage : PNG réduit à 2 000 px, non-image refusée', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 3000, 1500),
          Paint()..color = const Color(0xFF336699),
        );
        final source = await recorder.endRecording().toImage(3000, 1500);
        final data = await source.toByteData(format: ui.ImageByteFormat.png);
        source.dispose();
        final png = await preparerImage(data!.buffer.asUint8List());
        // Signature PNG, puis largeur et hauteur de l'en-tête IHDR.
        expect(png.sublist(0, 8), kPngDeTest.sublist(0, 8));
        final ihdr = ByteData.sublistView(png, 16, 24);
        expect(ihdr.getUint32(0), 2000);
        expect(ihdr.getUint32(4), 1000);
        await expectLater(
          preparerImage(Uint8List.fromList(List.filled(64, 7))),
          throwsA(isA<ImageRefusee>()),
        );
      });
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
      expect(find.text(TextesCapture.horsLigne), findsNothing);
      // « Réessayer » relit la capture.
      app.tickets.screenshots[chemin] = kPngDeTest;
      await tester.tap(find.text(TextesCapture.reessayer));
      await avancer(tester);
      expect(app.tickets.screenshotReads, [chemin, chemin]);
      expect(find.byType(VignetteCapture), findsOneWidget);
    });

    testWidgets('hors ligne : « La capture se lit avec le réseau. »', (
      tester,
    ) async {
      final app = await brasseur(
        tester,
        path: AppRoutes.tickets,
        offline: true,
      );
      app.tickets.publish([unTicket(screenshotPath: chemin)]);
      app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
      await avancer(tester);
      expect(find.text(TextesCapture.indisponible), findsOneWidget);
      expect(find.text(TextesCapture.horsLigne), findsOneWidget);
      expect(find.text(TextesCapture.reessayer), findsOneWidget);
    });

    testWidgets('échéance passée : « Capture effacée », rien lu ni rapporté', (
      tester,
    ) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.screenshots[chemin] = kPngDeTest;
      app.tickets.publish([
        unTicket(
          screenshotPath: chemin,
          screenshotExpiresAt: app.now.subtract(const Duration(minutes: 1)),
        ),
      ]);
      app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
      await avancer(tester);
      expect(find.text(TextesCapture.effacee), findsOneWidget);
      expect(find.byType(VignetteCapture), findsNothing);
      expect(find.text(TextesCapture.reessayer), findsNothing);
      expect(app.tickets.screenshotReads, isEmpty);
      expect(app.errors.reports, isEmpty);
    });

    testWidgets('échéance à venir : capture lue', (tester) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.screenshots[chemin] = kPngDeTest;
      app.tickets.publish([
        unTicket(
          screenshotPath: chemin,
          screenshotExpiresAt: app.now.add(const Duration(days: 1)),
        ),
      ]);
      app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
      await avancer(tester);
      expect(app.tickets.screenshotReads, [chemin]);
      expect(find.byType(VignetteCapture), findsOneWidget);
    });

    testWidgets(
      'fichier absent du bucket : « Capture effacée », sans rapport',
      (tester) async {
        final app = await brasseur(tester, path: AppRoutes.tickets);
        app.tickets.screenshotsErased.add(chemin);
        app.tickets.publish([unTicket(screenshotPath: chemin)]);
        app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
        await avancer(tester);
        expect(find.text(TextesCapture.effacee), findsOneWidget);
        expect(find.text(TextesCapture.indisponible), findsNothing);
        expect(find.text(TextesCapture.reessayer), findsNothing);
        expect(app.errors.reports, isEmpty);
      },
    );

    testWidgets(
      'vignette : bouton lu « Agrandir la capture », appui sémantique',
      (tester) async {
        final app = await brasseur(tester, path: AppRoutes.tickets);
        app.tickets.screenshots[chemin] = kPngDeTest;
        app.tickets.publish([unTicket(screenshotPath: chemin)]);
        app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
        await avancer(tester);
        final handle = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(RegExp('Agrandir la capture')),
          findsOneWidget,
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Agrandir la capture')),
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        handle.dispose();
      },
    );

    testWidgets('image illisible : « Capture indisponible. », rapportée', (
      tester,
    ) async {
      final app = await brasseur(tester, path: AppRoutes.tickets);
      app.tickets.screenshots[chemin] = Uint8List.fromList([1, 2, 3, 4]);
      app.tickets.publish([unTicket(screenshotPath: chemin)]);
      await tester.runAsync(() async {
        app.container.read(routerProvider).go(AppRoutes.ticket('t1'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump();
      expect(find.text(TextesCapture.indisponible), findsOneWidget);
      final report = app.errors.reports.singleWhere(
        (r) => r.feature == 'tickets.capture_display',
      );
      expect(report.context, isNot(contains('tickets/')));
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

    test('screenshot_path et screenshot_expires_at lus sur le ticket', () {
      final t = Ticket.fromFirestore('t1', {
        'type': 'bug',
        'title': 'Densité fausse',
        'description': 'La densité affichée est fausse.',
        'screen': '/recettes/:id',
        'status': 'received',
        'screenshot_path': 'tickets/u/t1/screenshot.png',
        'screenshot_expires_at': Timestamp.fromDate(
          DateTime.utc(2027, 5, 7, 9),
        ),
      });
      expect(
        t.screenshotExpiresAt!.isAtSameMomentAs(DateTime.utc(2027, 5, 7, 9)),
        isTrue,
      );
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
      Object? panneLecture,
      FakeFirebaseFirestore? firestore,
    }) => FirestoreTicketsRepository(
      errorReportService: errors,
      firestore: firestore ?? FakeFirebaseFirestore(),
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
        if (panneLecture != null) throw panneLecture;
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

    test(
      'panne Storage dont le message porte le chemin : rapport neutre',
      () async {
        final errors = RecordingErrorReportService();
        const chemin = 'tickets/u/t1/screenshot.png';
        final ok = await depot(
          errors,
          journal: [],
          panneDepot: FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
            message: "User does not have permission to access '$chemin'.",
          ),
        ).attachScreenshot(ticketId: 't1', authorUid: 'u', png: kPngDeTest);
        expect(ok, isFalse);
        final report = errors.reports.single;
        expect(report.error, isA<StateError>());
        expect('${report.error}', isNot(contains(chemin)));
        expect('${report.error}', contains('unauthorized'));
        expect(report.context, isNot(contains('screenshot')));
      },
    );

    test(
      'second dépôt refusé, ticket déjà doté : jointe, rapport neutre',
      () async {
        final errors = RecordingErrorReportService();
        final firestore = FakeFirebaseFirestore();
        await firestore.doc('tickets/t1').set({
          'screenshot_path': 'tickets/u/t1/screenshot.png',
        });
        final ok = await depot(
          errors,
          journal: [],
          firestore: firestore,
          panneDepot: FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
            message: "No permission for 'tickets/u/t1/screenshot.png'.",
          ),
        ).attachScreenshot(ticketId: 't1', authorUid: 'u', png: kPngDeTest);
        expect(ok, isTrue);
        expect(
          errors.reports.single.context,
          'tickets/t1 step=upload code=unauthorized',
        );
      },
    );

    test('loadScreenshot : panne Storage rapportée sans chemin', () async {
      final errors = RecordingErrorReportService();
      const chemin = 'tickets/u/t1/screenshot.png';
      final repo = depot(
        errors,
        journal: [],
        panneLecture: FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
          message: "User does not have permission to access '$chemin'.",
        ),
      );
      await expectLater(repo.loadScreenshot(chemin), throwsA(anything));
      final report = errors.reports.single;
      expect('${report.error}', isNot(contains(chemin)));
      expect(report.context, 'code=unauthorized');
    });

    test('loadScreenshot : capture effacée du bucket, sans rapport', () async {
      final errors = RecordingErrorReportService();
      const chemin = 'tickets/u/t1/screenshot.png';
      final repo = depot(
        errors,
        journal: [],
        panneLecture: FirebaseException(
          plugin: 'firebase_storage',
          code: 'object-not-found',
          message: "No object exists at '$chemin'.",
        ),
      );
      await expectLater(
        repo.loadScreenshot(chemin),
        throwsA(isA<CaptureEffacee>()),
      );
      expect(errors.reports, isEmpty);
    });

    test('motif : screenshot.png seul', () {
      expect(
        kTicketScreenshotPathPattern.hasMatch('tickets/u/t1/screenshot.png'),
        isTrue,
      );
      expect(
        kTicketScreenshotPathPattern.hasMatch('tickets/u/t1/screenshot.jpg'),
        isFalse,
      );
    });

    test('callable refusée : faux, rapportée', () async {
      final errors = RecordingErrorReportService();
      final ok = await depot(
        errors,
        journal: [],
        panneAppel: FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'Seules les images PNG de 5 Mo au plus sont acceptées.',
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
