import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/bandeau_liste_perimee.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/tickets/domain/etat_jeton_github.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/presentation/my_tickets_screen.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_detail_screen.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_form_screen.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_lien_github.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';
import 'support/ticket_fixtures.dart';

void main() {
  Future<TestApp> signedIn(
    WidgetTester tester, {
    bool admin = false,
    bool offline = false,
    double width = 400,
  }) async {
    final app = TestApp();
    await app.pump(tester, width: width);
    if (admin) {
      app.signIn(adminUser, member: adminMember, fromCache: offline);
    } else {
      app.signIn(brewerUser, member: brewerMember, fromCache: offline);
    }
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> go(WidgetTester tester, TestApp app, String location) async {
    app.container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  /// [settle] faux : un indicateur de chargement tourne, `pumpAndSettle` ne
  /// finirait pas.
  Future<void> push(
    WidgetTester tester,
    TestApp app,
    String location, {
    bool settle = true,
  }) async {
    unawaited(app.container.read(routerProvider).push(location));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
  }

  String dropdownLabel(WidgetTester tester) {
    final field = find.byType(DropdownButtonFormField<String>);
    final selected = find.descendant(of: field, matching: find.byType(Text));
    return tester.widget<Text>(selected.first).data!;
  }

  Future<void> fillValid(WidgetTester tester) async {
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

  group('menu du compte', () {
    testWidgets('pastille : suivis à lire comptés, pending et received non', (
      tester,
    ) async {
      final app = await signedIn(tester);
      expect(find.byTooltip('Mon compte'), findsOneWidget);
      final changed = DateTime(2026, 11, 7);
      app.tickets.publish([
        unTicket(
          id: 'a',
          status: TicketStatus.validated,
          statusChangedAt: changed,
        ),
        unTicket(
          id: 'b',
          status: TicketStatus.refused,
          statusChangedAt: changed,
          seenByAuthorAt: DateTime(2026, 11, 6),
        ),
        unTicket(id: 'c', status: TicketStatus.pending),
        unTicket(id: 'd', status: TicketStatus.received),
        unTicket(
          id: 'e',
          status: TicketStatus.closed,
          statusChangedAt: changed,
          seenByAuthorAt: DateTime(2026, 11, 8),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(app.tickets.watchedUids, contains(brewerUser.uid));
      expect(
        find.byTooltip('Mon compte, 2 suivis de ticket à lire'),
        findsOneWidget,
      );
      await openMenu(tester);
      final entry = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'Mes tickets'),
      );
      expect(entry.semanticsLabel, 'Mes tickets, 2 à lire');
      expect(
        find.descendant(
          of: find.widgetWithText(MenuItemButton, 'Mes tickets'),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sans suivi à lire : aucune pastille', (tester) async {
      final app = await signedIn(tester);
      app.tickets.publish([unTicket(status: TicketStatus.received)]);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mon compte'), findsOneWidget);
      final badge = tester.widget<Badge>(
        find.ancestor(
          of: find.byType(CircleAvatar),
          matching: find.byType(Badge),
        ),
      );
      expect(badge.isLabelVisible, isFalse);
    });

    testWidgets('plus de 99 suivis : « 99+ »', (tester) async {
      final app = await signedIn(tester);
      app.tickets.publish([
        for (var i = 0; i < 120; i++)
          unTicket(
            id: 't$i',
            status: TicketStatus.validated,
            statusChangedAt: DateTime(2026, 11, 7),
          ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('Signaler ou proposer : écran d\'origine prérempli', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await tester.tap(find.byTooltip('Équipements'));
      await tester.pumpAndSettle();
      await openMenu(tester);
      await tester.tap(find.text('Signaler ou proposer'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.warningTitle), findsOneWidget);
      expect(dropdownLabel(tester), 'Équipements');
      expect(app.tickets.idsGiven, 1);
    });

    testWidgets('depuis la fiche d\'un équipement : modèle de route, sans id', (
      tester,
    ) async {
      final app = await signedIn(tester);
      app.equipment.publish([
        const Equipment(
          id: 'eq-secret',
          ownerUid: 'uid-brasseur',
          content: equipementTest,
        ),
      ]);
      await go(tester, app, AppRoutes.equipmentItem('eq-secret'));
      await openMenu(tester);
      await tester.tap(find.text('Signaler ou proposer'));
      await tester.pumpAndSettle();
      expect(dropdownLabel(tester), 'Équipement');
      await fillValid(tester);
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(app.tickets.created.single.brouillon.screen, '/equipements/:id');
      // Revenu à l'écran d'origine.
      expect(find.text('Grainfather'), findsWidgets);
    });

    testWidgets('élément précis : jamais prérempli, envoyé dans « screen »', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await tester.tap(find.byTooltip('Équipements'));
      await tester.pumpAndSettle();
      await openMenu(tester);
      await tester.tap(find.text('Signaler ou proposer'));
      await tester.pumpAndSettle();
      final element = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Élément précis',
      );
      expect(
        find.descendant(of: element, matching: find.text("L'écran entier")),
        findsOneWidget,
      );
      await fillValid(tester);
      await tester.ensureVisible(element);
      await tester.pumpAndSettle();
      await tester.tap(element);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Menu du compte').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(
        app.tickets.created.single.brouillon.screen,
        '/equipements/menu/compte',
      );
    });

    testWidgets('admin, depuis Membres : « Admin › Membres »', (tester) async {
      final app = await signedIn(tester, admin: true);
      app.members.all.add(const [adminMember]);
      await go(tester, app, AppRoutes.adminMembers);
      await openMenu(tester);
      await tester.tap(find.text('Signaler ou proposer'));
      await tester.pumpAndSettle();
      expect(dropdownLabel(tester), 'Admin › Membres');
    });

    testWidgets('admin, depuis Membres : « Inviter un membre » proposé', (
      tester,
    ) async {
      final app = await signedIn(tester, admin: true);
      app.members.all.add(const [adminMember]);
      await go(tester, app, AppRoutes.adminMembers);
      await openMenu(tester);
      await tester.tap(find.text('Signaler ou proposer'));
      await tester.pumpAndSettle();
      final element = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Élément précis',
      );
      await tester.ensureVisible(element);
      await tester.pumpAndSettle();
      await tester.tap(element);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inviter un membre').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: element, matching: find.text('Inviter un membre')),
        findsOneWidget,
      );
    });

    testWidgets('Mes tickets s\'ouvre par push et revient par pop', (
      tester,
    ) async {
      final app = await signedIn(tester);
      app.tickets.publish(const []);
      await openMenu(tester);
      await tester.tap(find.text('Mes tickets'));
      await tester.pumpAndSettle();
      expect(find.text(MyTicketsScreen.titre), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Recettes'), findsWidgets);
    });
  });

  group('formulaire', () {
    testWidgets('champs vides : messages, rien d\'écrit', (tester) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.newTicket);
      expect(dropdownLabel(tester), 'Je ne sais pas');
      expect(
        find.textContaining('Envoyé avec : version 0.1.0'),
        findsOneWidget,
      );
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.typeMissing), findsOneWidget);
      expect(find.text(TicketFormScreen.titleTooShort), findsOneWidget);
      expect(find.text(TicketFormScreen.descriptionTooShort), findsOneWidget);
      expect(app.tickets.created, isEmpty);
    });

    testWidgets('titre de 4 caractères refusé ; aide du type affichée', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.newTicket);
      await tester.tap(find.text('Évolution'));
      await tester.pump();
      expect(find.textContaining('Ce qui existe aujourd\'hui'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Titre'),
        'Abcd',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Une description assez longue.',
      );
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.titleTooShort), findsOneWidget);
      expect(find.text(TicketFormScreen.typeMissing), findsNothing);
      expect(app.tickets.created, isEmpty);
    });

    testWidgets('en ligne : un seul ticket au double appui, message et Voir', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.newTicket);
      await fillValid(tester);
      await tester.tap(find.text('Envoyer'));
      await tester.tap(find.text('Envoyer'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(app.tickets.created, hasLength(1));
      final t = app.tickets.created.single;
      expect(t.id, 'ticket-1');
      expect(t.brouillon.type, TicketType.bug);
      expect(t.brouillon.title, 'Densité fausse');
      expect(t.authorUid, brewerUser.uid);
      expect(t.authorEmail, 'brasseur@exemple.fr');
      expect(t.appVersion, '0.1.0');
      expect(t.platform, 'android');
      expect(find.text(TicketFormScreen.warningTitle), findsNothing);
      expect(find.text(TicketFormScreen.sentOnline), findsOneWidget);
      app.tickets.publish([
        unTicket(id: 'ticket-1', status: TicketStatus.pending),
      ]);
      await tester.tap(find.text('Voir'));
      await tester.pumpAndSettle();
      expect(find.text(TicketDetailScreen.titre), findsOneWidget);
    });

    testWidgets('hors ligne : fermeture et message du retour du réseau', (
      tester,
    ) async {
      final app = await signedIn(tester, offline: true);
      await push(tester, app, AppRoutes.newTicket);
      await fillValid(tester);
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(app.tickets.created, hasLength(1));
      expect(find.text(TicketFormScreen.sentOffline), findsOneWidget);
    });

    testWidgets('refus du serveur : annoncé, Reprendre rouvre le texte', (
      tester,
    ) async {
      final app = await signedIn(tester);
      app.tickets.serverAnswer = () => Future.error(StateError('refusé'));
      await push(tester, app, AppRoutes.newTicket);
      await fillValid(tester);
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.refused), findsOneWidget);
      await tester.tap(find.text('Reprendre'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.warningTitle), findsOneWidget);
      expect(find.text('Densité fausse'), findsOneWidget);
      expect(find.text('La densité affichée est fausse.'), findsOneWidget);
      app.tickets.serverAnswer = () => Completer<void>().future;
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(app.tickets.created, hasLength(2));
      expect(app.tickets.created.last.id, isNot(app.tickets.created.first.id));
      expect(app.tickets.created.last.brouillon.type, TicketType.bug);
    });

    testWidgets('brasseur : Admin absent de « Écran concerné »', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.newTicket);
      final values = tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .items!
          .map((i) => i.value)
          .toList();
      expect(values, isNot(contains('/admin')));
      expect(values, isNot(contains('/admin/membres')));
      expect(values, contains('/prix'));
    });

    testWidgets('quitter avec saisie : confirmation, rien d\'écrit', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.newTicket);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Titre'),
        'Idée',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.abandonMessage), findsOneWidget);
      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.warningTitle), findsNothing);
      expect(find.text('Recettes'), findsWidgets);
      expect(app.tickets.created, isEmpty);
    });

    testWidgets('quitter sans saisie : fermeture directe', (tester) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.newTicket);
      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.abandonMessage), findsNothing);
      expect(find.text(TicketFormScreen.warningTitle), findsNothing);
    });

    testWidgets('texte × 2 sur 360 px : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await signedIn(tester, width: 360);
      await push(tester, app, AppRoutes.newTicket);
      expect(tester.takeException(), isNull);
    });
  });

  group('Mes tickets', () {
    testWidgets('chargement, puis liste vide', (tester) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.tickets, settle: false);
      expect(
        find.bySemanticsLabel('Chargement de vos tickets'),
        findsOneWidget,
      );
      app.tickets.publish(const []);
      await tester.pumpAndSettle();
      expect(find.text(MyTicketsScreen.emptyMessage), findsOneWidget);
      // Un seul « Signaler ou proposer » : pas de bouton flottant.
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Signaler ou proposer'),
      );
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.warningTitle), findsOneWidget);
    });

    testWidgets(
      'panne : message et Réessayer ; panne après une liste : bandeau',
      (tester) async {
        final app = await signedIn(tester);
        await push(tester, app, AppRoutes.tickets, settle: false);
        app.tickets.mine.addError(StateError('panne'));
        await tester.pumpAndSettle();
        expect(find.text(MyTicketsScreen.loadError), findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
        app.tickets.publish([unTicket()]);
        await tester.tap(find.text('Réessayer'));
        await tester.pumpAndSettle();
        expect(find.text('Densité fausse'), findsOneWidget);
        app.tickets.mine.addError(StateError('panne'));
        await tester.pumpAndSettle();
        expect(find.byType(BandeauListePerimee), findsOneWidget);
        expect(find.text('Densité fausse'), findsOneWidget);
      },
    );

    testWidgets('lignes : ordre, date, statut, point de non-lu, illisible', (
      tester,
    ) async {
      final app = await signedIn(tester);
      await push(tester, app, AppRoutes.tickets, settle: false);
      app.tickets.publish(
        [
          unTicket(
            id: 'ancien',
            title: 'Ancien',
            createdAt: DateTime(2026, 10, 1),
          ),
          unTicket(
            id: 'lu',
            title: 'Récent',
            status: TicketStatus.validated,
            createdAt: DateTime(2026, 11, 7),
            statusChangedAt: DateTime(2026, 11, 7, 10),
          ),
          unTicket(
            id: 'attente',
            title: 'Sur l\'appareil',
            status: TicketStatus.pending,
            createdAt: null,
            hasPendingWrites: true,
          ),
        ],
        invalid: ['casse'],
      );
      await tester.pumpAndSettle();
      final y = [
        'Sur l\'appareil',
        'Récent',
        'Ancien',
      ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
      expect(y, orderedEquals([...y]..sort()));
      expect(find.text('07/11/26'), findsOneWidget);
      expect(find.text('En attente du réseau'), findsOneWidget);
      expect(find.text('Validé'), findsOneWidget);
      // Pastille de non-lu lue avec la ligne du ticket validé.
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Récent[\\s\\S]*${RegExp.escape(MyTicketsScreen.unreadLabel)}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(MyTicketsScreen.unreadLabel)),
        findsOneWidget,
      );
      expect(find.text('Ticket illisible'), findsOneWidget);
      expect(
        find.text(
          'Mettez l\'application à jour, ou prévenez l\'administrateur.',
        ),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  group('suivi d\'un ticket', () {
    Future<TestApp> openDetail(
      WidgetTester tester,
      Ticket ticket, {
      String? appVersion,
    }) async {
      final app = await signedIn(tester);
      app.tickets.publish([ticket]);
      await push(tester, app, AppRoutes.ticket(ticket.id));
      return app;
    }

    testWidgets('contenu : type, titre, date, description, écran, version', (
      tester,
    ) async {
      await openDetail(tester, unTicket(replyText: 'Merci, c\'est noté.'));
      expect(find.text('Bug'), findsOneWidget);
      expect(find.text('Densité fausse'), findsOneWidget);
      expect(find.widgetWithText(Etiquette, 'Reçu'), findsOneWidget);
      expect(find.text('Envoyé le 08/11/26 à 09:30'), findsOneWidget);
      expect(
        find.text('L\'administrateur a reçu votre ticket.'),
        findsOneWidget,
      );
      expect(find.text('Réponse de l\'administrateur'), findsOneWidget);
      expect(find.text('Merci, c\'est noté.'), findsOneWidget);
      expect(find.text('La densité affichée est fausse.'), findsOneWidget);
      expect(find.text('Écran : Recette'), findsOneWidget);
      expect(find.text('Envoyé avec : version 0.1.0, Android'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    for (final (status, phrase) in [
      (TicketStatus.validated, 'Votre demande sera traitée.'),
      (TicketStatus.inProgress, 'Le travail a commencé.'),
      (TicketStatus.refused, 'Cette demande ne sera pas traitée.'),
      (TicketStatus.closed, 'Ce ticket est clos.'),
      (
        TicketStatus.sendFailed,
        'Votre ticket n\'a pas pu être transmis. Il reste enregistré dans '
            'l\'application. L\'administrateur est prévenu.',
      ),
      (
        TicketStatus.unknown,
        'Mettez l\'application à jour pour lire ce statut.',
      ),
    ]) {
      testWidgets('statut ${status.name} : sa phrase', (tester) async {
        await openDetail(tester, unTicket(status: status));
        expect(find.text(phrase), findsOneWidget);
        expect(find.text(TicketDetailScreen.resume), findsNothing);
      });
    }

    testWidgets('livré dans une version plus récente : mise à jour', (
      tester,
    ) async {
      final app = await openDetail(
        tester,
        unTicket(
          status: TicketStatus.delivered,
          deliveredVersion: '0.2.3',
          deliveredPrUrl: 'https://github.com/ChinaFred/KassBeer/pull/12',
        ),
      );
      expect(
        find.text('C\'est fait. Livré dans la version 0.2.3.'),
        findsOneWidget,
      );
      expect(find.text(TicketDetailScreen.updateNeeded), findsOneWidget);
      await tester.tap(find.text(BoutonVoirSurGithub.defaultLabel));
      await tester.pumpAndSettle();
      expect(app.openedLinks, [
        Uri.parse('https://github.com/ChinaFred/KassBeer/pull/12'),
      ]);
    });

    testWidgets('livré dans la version installée ou avant', (tester) async {
      await openDetail(
        tester,
        unTicket(status: TicketStatus.delivered, deliveredVersion: '0.1.0'),
      );
      expect(find.text(TicketDetailScreen.upToDate), findsOneWidget);
      expect(find.text(BoutonVoirSurGithub.defaultLabel), findsNothing);
    });

    testWidgets('livré sans version : « C\'est fait. », aucune comparaison', (
      tester,
    ) async {
      await openDetail(tester, unTicket(status: TicketStatus.delivered));
      expect(find.text('C\'est fait.'), findsOneWidget);
      expect(find.text(TicketDetailScreen.upToDate), findsNothing);
      expect(find.text(TicketDetailScreen.updateNeeded), findsNothing);
    });

    testWidgets('adresse hors de https://github.com : aucun bouton', (
      tester,
    ) async {
      await openDetail(
        tester,
        unTicket(
          status: TicketStatus.delivered,
          deliveredPrUrl: 'http://github.com/ChinaFred/KassBeer/pull/12',
        ),
      );
      expect(find.text(BoutonVoirSurGithub.defaultLabel), findsNothing);
    });

    testWidgets('ouverture refusée par le système : rapportée et annoncée', (
      tester,
    ) async {
      final app = await signedIn(tester);
      app.openLinkResult = false;
      app.tickets.publish([
        unTicket(
          status: TicketStatus.delivered,
          deliveredPrUrl: 'https://github.com/ChinaFred/KassBeer/pull/12',
        ),
      ]);
      await push(tester, app, AppRoutes.ticket('t1'));
      await tester.tap(find.text(BoutonVoirSurGithub.defaultLabel));
      await tester.pumpAndSettle();
      expect(find.text(BoutonVoirSurGithub.failure), findsOneWidget);
      expect(
        app.errors.reports.map((r) => r.feature),
        contains('tickets.open_github'),
      );
    });

    testWidgets('limite du jour : Reprendre crée un nouveau ticket prérempli', (
      tester,
    ) async {
      final app = await openDetail(
        tester,
        unTicket(
          status: TicketStatus.overQuota,
          type: TicketType.feature,
          screen: '/brassins',
        ),
      );
      expect(
        find.widgetWithText(Etiquette, 'Limite du jour atteinte'),
        findsOneWidget,
      );
      await tester.tap(find.text(TicketDetailScreen.resume));
      await tester.pumpAndSettle();
      expect(find.text(TicketFormScreen.warningTitle), findsOneWidget);
      expect(dropdownLabel(tester), 'Brassins');
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      final created = app.tickets.created.single;
      expect(created.id, isNot('t1'));
      expect(created.brouillon.type, TicketType.feature);
      expect(created.brouillon.title, 'Densité fausse');
      expect(created.brouillon.screen, '/brassins');
    });

    testWidgets('Reprendre rend l\'élément précis du ticket repris', (
      tester,
    ) async {
      const bottling = '/brassins/:id/fenetre/embouteillage';
      final app = await openDetail(
        tester,
        unTicket(status: TicketStatus.overQuota, screen: bottling),
      );
      await tester.tap(find.text(TicketDetailScreen.resume));
      await tester.pumpAndSettle();
      expect(dropdownLabel(tester), 'Brassin');
      final element = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Élément précis',
      );
      expect(
        find.descendant(of: element, matching: find.text('Embouteillage')),
        findsOneWidget,
      );
      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();
      expect(app.tickets.created.single.brouillon.screen, bottling);
    });

    testWidgets('suivi à lire : seen_by_author_at écrit une fois', (
      tester,
    ) async {
      final app = await openDetail(
        tester,
        unTicket(
          status: TicketStatus.validated,
          statusChangedAt: DateTime(2026, 11, 7),
        ),
      );
      expect(app.tickets.seen, ['t1']);
    });

    testWidgets('déjà lu : rien n\'est écrit', (tester) async {
      final app = await openDetail(tester, unTicket());
      expect(app.tickets.seen, isEmpty);
    });

    testWidgets('absent, illisible, hors ligne', (tester) async {
      final app = await signedIn(tester);
      app.tickets.publish(const [], invalid: ['casse']);
      await push(tester, app, AppRoutes.ticket('absent'));
      expect(find.text('Ce ticket n\'existe plus.'), findsOneWidget);
      await go(tester, app, AppRoutes.ticket('casse'));
      expect(find.text('Ce ticket est illisible.'), findsOneWidget);
    });

    testWidgets('hors ligne, absent du cache', (tester) async {
      final app = await signedIn(tester, offline: true);
      app.tickets.publish(const [], fromCache: true);
      await push(tester, app, AppRoutes.ticket('absent'));
      expect(
        find.text('Ce ticket n\'est pas disponible hors ligne.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retour à mes tickets'));
      await tester.pumpAndSettle();
      expect(find.text(MyTicketsScreen.titre), findsOneWidget);
    });
  });

  group('bandeau Admin', () {
    testWidgets('jeton refusé et tickets bloqués : dans Admin › Tickets', (
      tester,
    ) async {
      final app = await signedIn(tester, admin: true);
      app.tickets.githubStatus.add(
        DocumentTrouve(
          EtatJetonGithub(tokenInvalidSince: DateTime(2026, 11, 7)),
        ),
      );
      app.tickets.publishAll([
        unTicket(id: 'f', status: TicketStatus.sendFailed),
      ]);
      await tester.tap(find.byTooltip('Admin'));
      await tester.pumpAndSettle();
      // Accueil d'Admin : la tuile porte le nombre d'alertes, sans bandeau.
      expect(find.textContaining('Secret Manager'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Tickets des membres, 2 alertes, Bugs et idées des membres, et leur '
          'suivi sur GitHub',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tickets des membres'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Jeton GitHub refusé ou expiré depuis le 07/11/26 : remplacez '
          'GITHUB_TICKETS_TOKEN dans Secret Manager.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('1 ticket n\'est pas arrivé sur GitHub.'),
        findsOneWidget,
      );
    });

    testWidgets('tout va bien : aucun bandeau, aucune pastille', (
      tester,
    ) async {
      final app = await signedIn(tester, admin: true);
      app.tickets.githubStatus.add(const DocumentAbsent());
      app.tickets.publishAll(const []);
      await tester.tap(find.byTooltip('Admin'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('alerte')), findsNothing);
      await tester.tap(find.text('Tickets des membres'));
      await tester.pumpAndSettle();
      expect(find.textContaining('GitHub'), findsNothing);
    });
  });
}
