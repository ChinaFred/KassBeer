import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/menu_compte.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/members/domain/member.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/tickets/domain/etat_jeton_github.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_analysis.dart';
import 'package:kass_beer/features/tickets/domain/ticket_launch.dart';
import 'package:kass_beer/features/tickets/presentation/admin_ticket_screen.dart';
import 'package:kass_beer/features/tickets/presentation/admin_tickets_screen.dart';
import 'package:kass_beer/features/tickets/presentation/bandeau_tickets_admin.dart';
import 'package:kass_beer/features/tickets/presentation/boite_lancement.dart';
import 'package:kass_beer/features/tickets/presentation/frise_ticket.dart';
import 'package:kass_beer/features/tickets/presentation/my_tickets_screen.dart';
import 'package:kass_beer/features/tickets/presentation/section_analyses.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_detail_screen.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_statut.dart';

import 'support/fakes.dart';
import 'support/ticket_fixtures.dart';

void main() {
  final now = DateTime(2026, 11, 8, 12, 10);
  const all = TicketDecisionAction.values;

  group('domaine', () {
    test('À traiter : reçu, analysé ou envoi impossible, jamais validé', () {
      expect(unTicket(status: TicketStatus.received).toProcess, isTrue);
      expect(unTicket(status: TicketStatus.analyzed).toProcess, isTrue);
      expect(unTicket(status: TicketStatus.sendFailed).toProcess, isTrue);
      for (final s in [
        TicketStatus.pending,
        TicketStatus.validated,
        TicketStatus.inProgress,
        TicketStatus.delivered,
        TicketStatus.refused,
        TicketStatus.closed,
        TicketStatus.overQuota,
        TicketStatus.unknown,
      ]) {
        expect(unTicket(status: s).toProcess, isFalse, reason: s.name);
      }
    });

    test('Bloqué : envoi impossible, en retard, Issue disparue', () {
      expect(unTicket(status: TicketStatus.sendFailed).isBlocked(now), isTrue);
      final late = unTicket(status: TicketStatus.pending);
      expect(late.isLate(now), isTrue);
      expect(late.isBlocked(now), isTrue);
      expect(
        unTicket(
          status: TicketStatus.pending,
          createdAt: now.subtract(const Duration(minutes: 10)),
        ).isBlocked(now),
        isFalse,
      );
      // Encore sur l'appareil : jamais « En retard ».
      expect(
        unTicket(
          status: TicketStatus.pending,
          hasPendingWrites: true,
        ).isLate(now),
        isFalse,
      );
      expect(
        unTicket(issueMissingSince: DateTime(2026, 11, 7)).isBlocked(now),
        isTrue,
      );
      expect(unTicket().isBlocked(now), isFalse);
    });

    test('décision en cours : bail du serveur dans le futur', () {
      expect(
        unTicket(
          decisionLeaseUntil: now.add(const Duration(minutes: 1)),
        ).decisionInProgress(now),
        isTrue,
      );
      expect(
        unTicket(
          decisionLeaseUntil: now.subtract(const Duration(minutes: 1)),
        ).decisionInProgress(now),
        isFalse,
      );
    });

    test('frise : étapes et étape actuelle de chaque statut', () {
      List<String> labels(Ticket t) => [
        for (final e in etapesFrise(t)!.etapes) e.label,
      ];
      const suivi = [
        'Envoi en cours',
        'Reçu',
        'Analysé',
        'Validé',
        'En cours',
        'Livré',
      ];
      for (final (status, actuelle) in [
        (TicketStatus.pending, 0),
        (TicketStatus.received, 1),
        (TicketStatus.analyzed, 2),
        (TicketStatus.validated, 3),
        (TicketStatus.inProgress, 4),
        (TicketStatus.delivered, 5),
      ]) {
        final t = unTicket(status: status);
        expect(labels(t), suivi, reason: status.name);
        expect(etapesFrise(t)!.actuelle, actuelle, reason: status.name);
      }
      final local = unTicket(
        status: TicketStatus.pending,
        hasPendingWrites: true,
      );
      expect(labels(local).first, 'En attente du réseau');
      expect(labels(unTicket(status: TicketStatus.refused)), [
        'Envoi en cours',
        'Reçu',
        'Refusé',
      ]);
      expect(labels(unTicket(status: TicketStatus.closed)), [
        'Envoi en cours',
        'Reçu',
        'Clos',
      ]);
      final failed = etapesFrise(unTicket(status: TicketStatus.sendFailed))!;
      expect(failed.etapes.map((e) => e.label), [
        'Envoi en cours',
        'Envoi impossible',
      ]);
      expect(failed.etapes.last.erreur, isTrue);
      expect(
        etapesFrise(unTicket(status: TicketStatus.overQuota))!.etapes.last,
        (
          label: 'Limite du jour atteinte',
          icon: Icons.event_busy,
          erreur: true,
        ),
      );
      expect(etapesFrise(unTicket(status: TicketStatus.unknown)), isNull);
    });

    test('tons et icônes des pastilles', () {
      expect(statutAfficheDe(TicketStatus.pending).ton, TonEtiquette.neutre);
      expect(statutAfficheDe(TicketStatus.received).ton, TonEtiquette.primaire);
      expect(
        statutAfficheDe(TicketStatus.received).icon,
        Icons.mark_email_read_outlined,
      );
      expect(
        statutAfficheDe(TicketStatus.validated).ton,
        TonEtiquette.primaire,
      );
      expect(
        statutAfficheDe(TicketStatus.inProgress).ton,
        TonEtiquette.tertiaire,
      );
      expect(
        statutAfficheDe(TicketStatus.delivered).ton,
        TonEtiquette.primaire,
      );
      expect(statutAfficheDe(TicketStatus.refused).ton, TonEtiquette.neutre);
      expect(statutAfficheDe(TicketStatus.closed).ton, TonEtiquette.normal);
      expect(statutAfficheDe(TicketStatus.closed).icon, Icons.archive_outlined);
      expect(statutAfficheDe(TicketStatus.sendFailed).ton, TonEtiquette.erreur);
      expect(statutAfficheDe(TicketStatus.overQuota).ton, TonEtiquette.erreur);
      expect(statutAfficheDe(TicketStatus.unknown).ton, TonEtiquette.neutre);
      expect(
        statutAffiche(
          unTicket(status: TicketStatus.pending, hasPendingWrites: true),
        ).ton,
        TonEtiquette.neutre,
      );
    });

    test('titre de l\'encadré selon le statut', () {
      expect(titreReponse(TicketStatus.refused), 'Motif du refus');
      expect(titreReponse(TicketStatus.closed), 'Commentaire de clôture');
      expect(
        titreReponse(TicketStatus.validated),
        'Réponse de l\'administrateur',
      );
    });

    test('infobulle de l\'avatar', () {
      expect(infobulleCompte(unread: 0, toProcess: 0), 'Mon compte');
      expect(
        infobulleCompte(unread: 1, toProcess: 3),
        'Mon compte, 1 suivi de ticket à lire, 3 tickets à traiter',
      );
      expect(
        infobulleCompte(unread: 0, toProcess: 1),
        'Mon compte, 1 ticket à traiter',
      );
    });

    group('messages des décisions (T7)', () {
      test('décision appliquée', () {
        expect(
          messageDecisionAppliquee(
            TicketDecisionAction.validate,
            valideSurGithub: false,
          ),
          'Ticket validé. Le membre voit « Validé ».',
        );
        expect(
          messageDecisionAppliquee(
            TicketDecisionAction.validate,
            valideSurGithub: true,
          ),
          'Validation enregistrée. Vous pouvez lancer le développement.',
        );
        expect(
          messageDecisionAppliquee(
            TicketDecisionAction.refuse,
            valideSurGithub: false,
          ),
          'Ticket refusé. L\'Issue est fermée.',
        );
        expect(
          messageDecisionAppliquee(
            TicketDecisionAction.close,
            valideSurGithub: false,
          ),
          'Ticket clos. L\'Issue est fermée.',
        );
      });

      test('échec : motif, réseau, résultat inconnu, accès, partiel', () {
        const refus = TicketDecisionAction.refuse;
        expect(
          messageEchecDecision(
            refus,
            const EchecReponse(
              CauseEchecReponse.motif,
              motif: 'Une décision est déjà en cours sur ce ticket.',
            ),
          ),
          'Refus non publié : Une décision est déjà en cours sur ce ticket. '
          'Votre texte est gardé.',
        );
        expect(
          messageEchecDecision(
            refus,
            const EchecReponse(CauseEchecReponse.reseau),
          ),
          'Refus non publié : pas de réseau. Votre texte est gardé.',
        );
        expect(
          messageEchecDecision(
            TicketDecisionAction.close,
            const EchecReponse(CauseEchecReponse.delai),
          ),
          'Résultat inconnu : le serveur n\'a pas répondu à temps. Regardez '
          'le statut du ticket avant de clore à nouveau. Votre texte est '
          'gardé.',
        );
        expect(
          messageEchecDecision(
            TicketDecisionAction.validate,
            const EchecReponse(CauseEchecReponse.acces),
          ),
          'Validation non enregistrée : accès administrateur refusé.',
        );
        expect(
          messageEchecDecision(
            TicketDecisionAction.validate,
            const EchecReponse(CauseEchecReponse.reseau),
          ),
          'Validation non enregistrée : pas de réseau.',
        );
        expect(
          messageEchecDecision(
            refus,
            const EchecReponse(CauseEchecReponse.motif, partiel: true),
          ),
          'Le motif est publié sur GitHub, mais l\'Issue n\'est pas fermée. '
          'Refuser à nouveau termine sans republier.',
        );
      });

      test('relance d\'envoi', () {
        expect(
          messageRelanceEnvoi(
            const ResultatRelanceEnvoi.envoi(
              status: TicketStatus.received,
              issueNumber: 12,
            ),
          ),
          'Ticket envoyé sur GitHub : Issue #12.',
        );
        expect(
          messageRelanceEnvoi(
            const ResultatRelanceEnvoi.envoi(status: TicketStatus.pending),
          ),
          startsWith('Envoi relancé, mais GitHub'),
        );
        expect(
          messageRelanceEnvoi(
            const ResultatRelanceEnvoi.echec(
              EchecReponse(CauseEchecReponse.reseau),
            ),
          ),
          'Envoi non relancé : pas de réseau.',
        );
        expect(
          messageRelanceEnvoi(
            const ResultatRelanceEnvoi.echec(
              EchecReponse(CauseEchecReponse.delai),
            ),
          ),
          'Résultat inconnu : regardez le statut du ticket avant de relancer.',
        );
      });
    });

    test('historique des décisions', () {
      expect(
        ligneHistorique(uneDecision(state: TicketDecisionState.applied)),
        'Refus demandé le 08/11/26 à 11:00 · Appliqué',
      );
      expect(
        ligneHistorique(
          uneDecision(
            action: TicketDecisionAction.close,
            state: TicketDecisionState.failed,
            errorReason: 'Issue non fermée.',
          ),
        ),
        'Clôture demandée le 08/11/26 à 11:00 · Échec : Issue non fermée.',
      );
      expect(
        ligneHistorique(
          uneDecision(
            action: TicketDecisionAction.validate,
            state: TicketDecisionState.rejected,
            errorReason: 'Ce ticket a déjà été clos sur GitHub.',
          ),
        ),
        'Validation demandée le 08/11/26 à 11:00 · Refusée par le serveur : '
        'Ce ticket a déjà été clos sur GitHub.',
      );
      expect(
        ligneHistorique(uneDecision(action: null)),
        startsWith('Décision demandée'),
      );
    });
  });

  // ------------------------------------------------------------- écrans

  Future<TestApp> admin(
    WidgetTester tester, {
    double width = 400,
    double height = 900,
    bool offline = false,
  }) async {
    final app = TestApp();
    await app.pump(tester, width: width, height: height);
    app.signIn(adminUser, member: adminMember, fromCache: offline);
    await tester.pumpAndSettle();
    return app;
  }

  Future<void> go(WidgetTester tester, TestApp app, String location) async {
    app.container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }

  /// Une barre de progression indéterminée tourne : `pumpAndSettle` ne
  /// finirait pas.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(CircleAvatar));
    await tester.pumpAndSettle();
  }

  group('menu du compte', () {
    testWidgets('admin : Tickets à traiter, compteur et pastille', (
      tester,
    ) async {
      final app = await admin(tester);
      app.tickets.publish([
        unTicket(
          id: 'mien',
          status: TicketStatus.validated,
          statusChangedAt: DateTime(2026, 11, 7),
        ),
      ]);
      app.tickets.publishAll([
        unTicket(id: 'a', status: TicketStatus.received),
        unTicket(id: 'b', status: TicketStatus.sendFailed),
        unTicket(id: 'c', status: TicketStatus.validated),
        unTicket(id: 'd', status: TicketStatus.received),
      ]);
      await tester.pumpAndSettle();
      expect(
        find.byTooltip(
          'Mon compte, 1 suivi de ticket à lire, 3 tickets à traiter',
        ),
        findsOneWidget,
      );
      final avatar = tester.widget<Badge>(
        find.ancestor(
          of: find.byType(CircleAvatar),
          matching: find.byType(Badge),
        ),
      );
      expect((avatar.label! as Text).data, '4');
      await openMenu(tester);
      final entry = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'Tickets à traiter'),
      );
      expect(entry.semanticsLabel, 'Tickets à traiter, 3');
      // Ordre : Mes tickets, Tickets à traiter, Nouveautés.
      final y = [
        'Mes tickets',
        'Tickets à traiter',
        'Nouveautés',
      ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
      expect(y, orderedEquals([...y]..sort()));
      await tester.tap(find.text('Tickets à traiter'));
      await tester.pumpAndSettle();
      expect(find.text(AdminTicketsScreen.titre), findsWidgets);
      expect(find.text('À traiter (3)'), findsOneWidget);
    });

    testWidgets('rien à traiter : pas de compteur', (tester) async {
      final app = await admin(tester);
      app.tickets.publishAll([unTicket(status: TicketStatus.validated)]);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mon compte'), findsOneWidget);
      await openMenu(tester);
      final entry = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, 'Tickets à traiter'),
      );
      expect(entry.trailingIcon, isNull);
    });

    testWidgets(
      'brasseur : pas d\'entrée, pas de lecture de tous les tickets',
      (tester) async {
        final app = TestApp();
        await app.pump(tester);
        app.signIn(brewerUser, member: brewerMember);
        await tester.pumpAndSettle();
        await openMenu(tester);
        expect(find.text('Tickets à traiter'), findsNothing);
        expect(app.tickets.all.subscriptions, 0);
      },
    );
  });

  group('Admin › Tickets des membres', () {
    testWidgets('tuile de l\'accueil Admin', (tester) async {
      final app = await admin(tester);
      app.tickets.publishAll(const []);
      await go(tester, app, AppRoutes.admin);
      expect(find.text(AdminTicketsScreen.titre), findsOneWidget);
      expect(
        find.text('Bugs et idées des membres, et leur suivi sur GitHub'),
        findsOneWidget,
      );
      final y = [
        'Membres',
        'Tickets des membres',
        'Import',
      ].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
      expect(y, orderedEquals([...y]..sort()));
      await tester.tap(find.text(AdminTicketsScreen.titre));
      await tester.pumpAndSettle();
      expect(find.text('À traiter (0)'), findsOneWidget);
    });

    testWidgets('tuile : une échéance proche n\'allume pas la pastille', (
      tester,
    ) async {
      final app = await admin(tester);
      app.tickets.githubStatus.add(
        DocumentTrouve(
          EtatJetonGithub(tokenExpiresAt: now.add(const Duration(days: 3))),
        ),
      );
      app.tickets.publishAll(const []);
      await go(tester, app, AppRoutes.admin);
      expect(find.bySemanticsLabel(RegExp('alerte')), findsNothing);
      await tester.tap(find.text(AdminTicketsScreen.titre));
      await tester.pumpAndSettle();
      expect(find.text('Le jeton GitHub expire le 11/11/26.'), findsOneWidget);
    });

    testWidgets('tuile : panne de lecture comptée', (tester) async {
      final app = await admin(tester);
      app.tickets.githubStatus.add(const DocumentAbsent());
      app.tickets.all.addError(StateError('panne'));
      await go(tester, app, AppRoutes.admin);
      expect(
        find.bySemanticsLabel(RegExp(r'^Tickets des membres, 1 alerte, ')),
        findsOneWidget,
      );
    });

    testWidgets('chargement, panne, puis liste', (tester) async {
      final app = await admin(tester);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Chargement des tickets'), findsOneWidget);
      expect(find.text('À traiter'), findsOneWidget);
      app.tickets.all.addError(StateError('panne'));
      await tester.pumpAndSettle();
      expect(find.text(AdminTicketsScreen.loadError), findsOneWidget);
      // La panne n'est pas répétée par le bandeau.
      expect(find.text(kPanneComptageTickets), findsNothing);
      app.tickets.publishAll([unTicket()]);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('Densité fausse'), findsOneWidget);
    });

    testWidgets('aucun ticket : message', (tester) async {
      final app = await admin(tester);
      app.tickets.publishAll(const []);
      await go(tester, app, AppRoutes.adminTickets);
      expect(find.text(AdminTicketsScreen.emptyMessage), findsOneWidget);
    });

    testWidgets('lignes : numéro, nom de l\'auteur, date, pastilles', (
      tester,
    ) async {
      // Le compteur des lancements occupe une ligne au-dessus des filtres.
      final app = await admin(tester, height: 1100);
      app.members.all.add(const [
        Member(
          email: 'brasseur@exemple.fr',
          role: MemberRole.brewer,
          displayName: 'Bruno Brasseur',
        ),
      ]);
      app.tickets.publishAll(
        [
          unTicket(
            id: 'a',
            issueNumber: 12,
            decisionLeaseUntil: now.add(const Duration(minutes: 1)),
          ),
          unTicket(
            id: 'b',
            title: 'Autre',
            status: TicketStatus.sendFailed,
            authorEmail: 'parti@exemple.fr',
            createdAt: DateTime(2026, 11, 7),
          ),
          unTicket(
            id: 'c',
            title: 'Disparue',
            status: TicketStatus.validated,
            issueMissingSince: DateTime(2026, 11, 7),
          ),
          unTicket(id: 'd', title: 'Lent', status: TicketStatus.pending),
        ],
        invalid: ['casse'],
      );
      await go(tester, app, AppRoutes.adminTickets);
      // « À traiter » : reçu et envoi impossible.
      expect(find.text('À traiter (2)'), findsOneWidget);
      expect(find.text('Bloqués (3)'), findsOneWidget);
      expect(find.text('#12 · Bruno Brasseur · 08/11/26'), findsOneWidget);
      expect(find.text('parti@exemple.fr · 07/11/26'), findsOneWidget);
      expect(find.text('Décision en cours'), findsOneWidget);
      expect(find.text('Disparue'), findsNothing);
      expect(find.text('Ticket illisible'), findsNothing);
      await tapChip(tester, 'Tous');
      expect(find.text('Issue disparue'), findsOneWidget);
      expect(find.text('En retard'), findsOneWidget);
      expect(find.text('Ticket illisible'), findsOneWidget);
      expect(find.text('Mettez l\'application à jour.'), findsOneWidget);
      await tapChip(tester, 'Bloqués (3)');
      expect(find.text('Densité fausse'), findsNothing);
      expect(find.text('Lent'), findsOneWidget);
    });

    testWidgets('rien à traiter : ouvre sur Tous ; Bloqués vide', (
      tester,
    ) async {
      final app = await admin(tester);
      app.tickets.publishAll([unTicket(status: TicketStatus.validated)]);
      await go(tester, app, AppRoutes.adminTickets);
      final tous = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Tous'),
      );
      expect(tous.selected, isTrue);
      expect(find.text('Densité fausse'), findsOneWidget);
      await tapChip(tester, 'À traiter (0)');
      expect(find.text(AdminTicketsScreen.nothingToProcess), findsOneWidget);
      await tapChip(tester, 'Bloqués (0)');
      expect(find.text(AdminTicketsScreen.nothingBlocked), findsOneWidget);
      await tester.tap(find.text(AdminTicketsScreen.showAll));
      await tester.pumpAndSettle();
      expect(find.text('Densité fausse'), findsOneWidget);
    });

    testWidgets('téléphone : la fiche s\'ouvre seule, le filtre reste', (
      tester,
    ) async {
      final app = await admin(tester);
      app.tickets.publishAll([
        unTicket(status: TicketStatus.validated, title: 'Validé déjà'),
      ]);
      app.tickets.publishDecisions('t1', const []);
      await go(tester, app, AppRoutes.adminTickets);
      await tester.tap(find.text('Validé déjà'));
      await tester.pumpAndSettle();
      expect(find.text(AdminTicketScreen.titre), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      final tous = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Tous'),
      );
      expect(tous.selected, isTrue);
    });

    testWidgets('large : fiche à droite, même page, titre de la liste', (
      tester,
    ) async {
      final app = await admin(tester, width: 1400);
      app.tickets.publishAll([
        unTicket(allowedDecisions: all),
        unTicket(id: 't2', title: 'Autre idée', allowedDecisions: all),
      ]);
      app.tickets.publishDecisions('t1', const []);
      app.tickets.publishDecisions('t2', const []);
      await go(tester, app, AppRoutes.adminTickets);
      expect(find.text(AdminTicketsScreen.noSelection), findsOneWidget);
      final liste = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Densité fausse'));
      // Même page : aucune transition à attendre.
      await tester.pump();
      final router = app.container.read(routerProvider);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.adminTicket('t1'),
      );
      expect(
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        ),
        same(liste),
      );
      await tester.pumpAndSettle();
      // La liste reste à gauche, la fiche est à droite, la barre du haut
      // garde le titre de la liste.
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.text('Valider'), findsOneWidget);
      expect(find.text(AdminTicketsScreen.noSelection), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(AdminTicketsScreen.titre),
        ),
        findsOneWidget,
      );
      final chip = tester.getRect(find.text('À traiter (2)'));
      final valider = tester.getRect(find.text('Valider'));
      expect(valider.left, greaterThan(chip.right));
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Densité fausse'),
      );
      expect(tile.selected, isTrue);
      expect(
        tile.selectedTileColor,
        Theme.of(
          tester.element(find.text('Valider')),
        ).colorScheme.secondaryContainer,
      );
      await tester.tap(find.text('Autre idée'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.adminTicket('t2'),
      );
      // Retour : l'accueil d'Admin.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.admin,
      );
    });
  });

  group('fiche d\'un ticket', () {
    Future<TestApp> fiche(
      WidgetTester tester,
      Ticket ticket, {
      List<TicketDecision>? decisions = const [],
      RechercheDocument<TicketAnalysisDoc>? analyses =
          const DocumentAbsent<TicketAnalysisDoc>(),
      double width = 400,
      double height = 900,
      bool offline = false,
    }) async {
      final app = await admin(
        tester,
        width: width,
        height: height,
        offline: offline,
      );
      app.tickets.publishAll([ticket]);
      if (decisions != null) {
        app.tickets.publishDecisions(ticket.id, decisions);
      }
      if (analyses != null) app.tickets.analysesOf(ticket.id).add(analyses);
      app.container.read(routerProvider).go(AppRoutes.adminTicket(ticket.id));
      await settle(tester);
      return app;
    }

    testWidgets('contenu : Issue, auteur, frise, description, réponse', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unTicket(
          status: TicketStatus.refused,
          issueNumber: 12,
          issueUrl: 'https://github.com/ChinaFred/KassBeer/issues/12',
          replyText: 'Hors du périmètre.',
          allowedDecisions: const [],
        ),
        decisions: [uneDecision(state: TicketDecisionState.applied)],
      );
      expect(find.text('Issue #12'), findsOneWidget);
      expect(find.text('Auteur : brasseur@exemple.fr'), findsOneWidget);
      expect(find.text('Envoyé le 08/11/26 à 09:30'), findsOneWidget);
      expect(find.text('Motif du refus'), findsOneWidget);
      expect(find.text('Hors du périmètre.'), findsOneWidget);
      expect(find.text('La densité affichée est fausse.'), findsOneWidget);
      expect(find.byType(FriseTicket), findsOneWidget);
      expect(find.text('Décisions (1)'), findsOneWidget);
      // Ticket refusé : aucune décision possible, aucune barre.
      expect(find.text('Valider'), findsNothing);
      expect(find.text('Refuser'), findsNothing);
      // Refusé sans document d'analyses : « pas encore relevée », et un
      // second bouton vers l'Issue.
      expect(find.text('Analyses'), findsOneWidget);
      expect(find.text(SectionAnalyses.pasEncoreRelevee), findsOneWidget);
      expect(find.text('Ouvrir l\'Issue #12'), findsNWidgets(2));
      await tester.tap(find.text('Ouvrir l\'Issue #12').first);
      await tester.pumpAndSettle();
      expect(app.openedLinks.single.path, '/ChinaFred/KassBeer/issues/12');
      await tester.ensureVisible(find.text('Décisions (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Décisions (1)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Refus demandé le 08/11/26 à 11:00 · Appliqué'),
        findsOneWidget,
      );
    });

    testWidgets('livré : Ouvrir la PR', (tester) async {
      await fiche(
        tester,
        unTicket(
          status: TicketStatus.delivered,
          deliveredPrUrl: 'https://github.com/ChinaFred/KassBeer/pull/34',
          deliveredPrNumber: 34,
          allowedDecisions: const [],
        ),
      );
      expect(find.text('Ouvrir la PR #34'), findsOneWidget);
    });

    testWidgets('boutons selon allowed_decisions seulement', (tester) async {
      final app = await fiche(
        tester,
        unTicket(allowedDecisions: all),
        width: 700,
      );
      expect(find.text('Refuser'), findsOneWidget);
      expect(find.text('Clore'), findsOneWidget);
      expect(find.text('Valider'), findsOneWidget);
      // Principal à droite.
      expect(
        tester.getTopLeft(find.text('Valider')).dx,
        greaterThan(tester.getTopLeft(find.text('Clore')).dx),
      );
      // Un statut reçu sans décision écrite par le serveur : aucun bouton
      // dérivé du statut.
      app.tickets.publishAll([unTicket()]);
      await tester.pumpAndSettle();
      expect(find.text('Valider'), findsNothing);
      expect(
        find.text(
          'Le serveur n\'a pas encore calculé les décisions possibles pour ce '
          'ticket.',
        ),
        findsOneWidget,
      );
      app.tickets.publishAll([
        unTicket(
          status: TicketStatus.validated,
          allowedDecisions: const [
            TicketDecisionAction.refuse,
            TicketDecisionAction.close,
          ],
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Valider'), findsNothing);
      expect(find.text('Refuser'), findsOneWidget);
    });

    testWidgets('Valider : confirmation, appel, ligne en cours, message', (
      tester,
    ) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      final server = Completer<EchecReponse?>();
      app.tickets.decideResult = () => server.future;
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Valider ce ticket ?'), findsOneWidget);
      expect(
        find.text(
          'L\'étiquette « validé » sera posée sur l\'Issue. Le membre verra '
          '« Validé ».',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Valider').last);
      await settle(tester);
      final d = app.tickets.decisionsAppelees.single;
      expect(d.action, TicketDecisionAction.validate);
      expect(d.text, isNull);
      expect(find.text('Refuser'), findsNothing);
      expect(find.text('Validation en cours sur GitHub.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Validation en cours')),
        findsWidgets,
      );
      server.complete(null);
      await settle(tester);
      expect(
        find.text('Ticket validé. Le membre voit « Validé ».'),
        findsOneWidget,
      );
      expect(find.text('Validation en cours sur GitHub.'), findsNothing);
    });

    testWidgets('Valider un ticket validé sur GitHub seul : texte propre', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unTicket(
          status: TicketStatus.validated,
          allowedDecisions: const [
            TicketDecisionAction.refuse,
            TicketDecisionAction.close,
            TicketDecisionAction.validate,
          ],
        ),
      );
      app.tickets.decideResult = () async => null;
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Valider ce ticket ?'), findsOneWidget);
      expect(find.text(kValiderConfirmationGithub), findsOneWidget);
      expect(
        find.text(
          'La validation sera enregistrée dans l\'application. « Lancer le '
          'développement » sera ensuite proposé.',
        ),
        findsOneWidget,
      );
      expect(find.text(kValiderConfirmation), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Valider').last);
      await settle(tester);
      expect(
        app.tickets.decisionsAppelees.single.action,
        TicketDecisionAction.validate,
      );
      expect(
        find.text(
          'Validation enregistrée. Vous pouvez lancer le développement.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Valider en échec : boutons revenus, message', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.decideResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        motif: 'Cette décision n\'est plus possible pour ce statut.',
      );
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Valider').last);
      await settle(tester);
      expect(
        find.text(
          'Validation non enregistrée : Cette décision n\'est plus possible '
          'pour ce statut.',
        ),
        findsOneWidget,
      );
      expect(find.text('Valider'), findsOneWidget);
    });

    testWidgets('Refuser : avertissement, motif trop court, appel, boîte '
        'ouverte pendant l\'appel', (tester) async {
      final app = await fiche(
        tester,
        unTicket(status: TicketStatus.inProgress, allowedDecisions: all),
      );
      final server = Completer<EchecReponse?>();
      app.tickets.decideResult = () => server.future;
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(find.text('Refuser ce ticket'), findsOneWidget);
      expect(find.text(FormulaireDecision.publicWarning), findsOneWidget);
      expect(find.text(FormulaireDecision.prWarning), findsOneWidget);
      expect(
        find.text('L\'Issue sera fermée comme non prévue.'),
        findsOneWidget,
      );
      expect(find.text('0/4000'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Non');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le motif doit faire au moins 5 caractères.'),
        findsOneWidget,
      );
      expect(app.tickets.decisionsAppelees, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'm' * 4001);
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le motif ne doit pas dépasser 4 000 caractères.'),
        findsOneWidget,
      );
      expect(app.tickets.decisionsAppelees, isEmpty);
      await tester.enterText(
        find.byType(TextFormField),
        '  Hors du périmètre.  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      final d = app.tickets.decisionsAppelees.single;
      expect(d.action, TicketDecisionAction.refuse);
      expect(d.text, 'Hors du périmètre.');
      // La boîte reste ouverte : champ inactif, « Fermer », phrase annoncée.
      expect(find.text('Refuser ce ticket'), findsOneWidget);
      expect(
        find.text(
          'Refus en cours. Vous pouvez fermer : le résultat s\'affichera dans '
          'un message.',
        ),
        findsOneWidget,
      );
      expect(find.text('Fermer'), findsOneWidget);
      server.complete(null);
      await settle(tester);
      expect(find.text('Refuser ce ticket'), findsNothing);
      expect(find.text('Ticket refusé. L\'Issue est fermée.'), findsOneWidget);
    });

    testWidgets('Clore : annuler garde le brouillon', (tester) async {
      await fiche(tester, unTicket(allowedDecisions: all));
      await tester.tap(find.text('Clore'));
      await tester.pumpAndSettle();
      expect(find.text('Clore ce ticket'), findsOneWidget);
      expect(
        find.text('Le ticket passera à « Clos » et l\'Issue sera fermée.'),
        findsOneWidget,
      );
      expect(find.text(FormulaireDecision.prWarning), findsNothing);
      await tester.enterText(find.byType(TextFormField), 'Fai');
      await tester.tap(find.widgetWithText(FilledButton, 'Clore'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le commentaire doit faire au moins 5 caractères.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), 'Déjà fait.');
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clore'));
      await tester.pumpAndSettle();
      expect(find.text('Déjà fait.'), findsOneWidget);
    });

    testWidgets('échec, boîte ouverte : message dans la boîte, texte gardé', (
      tester,
    ) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.decideResult = () async =>
          const EchecReponse(CauseEchecReponse.reseau);
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Hors du périmètre.');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      expect(find.text('Refuser ce ticket'), findsOneWidget);
      expect(
        find.text('Refus non publié : pas de réseau. Votre texte est gardé.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.text('Hors du périmètre.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('motif refusé par le serveur : sous le champ', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.decideResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        champ: 'text',
        motif: 'Le motif doit faire au moins 5 caractères.',
      );
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '@@@@@@');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      expect(
        find.text('Le motif doit faire au moins 5 caractères.'),
        findsOneWidget,
      );
    });

    testWidgets('échec, boîte fermée : message, brouillon rendu à la '
        'réouverture', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      final server = Completer<EchecReponse?>();
      app.tickets.decideResult = () => server.future;
      await tester.tap(find.text('Clore'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Déjà fait.');
      await tester.tap(find.widgetWithText(FilledButton, 'Clore'));
      await settle(tester);
      await tester.tap(find.text('Fermer'));
      // Barre de progression indéfinie : pas de pumpAndSettle pendant l'appel.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Clôture en cours sur GitHub.'), findsOneWidget);
      expect(find.text('Clore'), findsNothing);
      server.complete(const EchecReponse(CauseEchecReponse.delai));
      await settle(tester);
      expect(
        find.text(
          'Résultat inconnu : le serveur n\'a pas répondu à temps. Regardez le '
          'statut du ticket avant de clore à nouveau. Votre texte est gardé.',
        ),
        findsWidgets,
      );
      // Le message d'échec (10 s) couvre la barre : il se retire avant la
      // réouverture.
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clore'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.text('Déjà fait.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('texte gardé par le serveur : message dédié', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.decideResult = () async => null;
      app.tickets.texteGarde = true;
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Nouveau motif.');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      expect(
        find.text(
          'Ticket refusé. L\'Issue est fermée. Le motif déjà publié est '
          'gardé : votre nouveau texte n\'est pas publié.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('boîte fermée pendant son animation : échec en message de '
        '10 s', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      final server = Completer<EchecReponse?>();
      app.tickets.decideResult = () => server.future;
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Hors du périmètre.');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await tester.pump();
      await tester.tap(find.text('Fermer'));
      // La boîte est encore montée : son animation de sortie n'est pas finie.
      await tester.pump(const Duration(milliseconds: 50));
      server.complete(const EchecReponse(CauseEchecReponse.reseau));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      const message =
          'Refus non publié : pas de réseau. Votre texte est gardé.';
      expect(find.text(message), findsOneWidget);
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.duration, kDureeMessageEchec);
    });

    testWidgets('motif sur le texte : réaffiché à la réouverture, effacé à la '
        'frappe', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      const motif = 'Le motif doit faire au moins 5 caractères.';
      app.tickets.decideResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        champ: 'text',
        motif: motif,
      );
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '@@@@@@');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      expect(find.text(motif), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(find.text(motif), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Hors du périmètre.');
      await tester.pumpAndSettle();
      expect(find.text(motif), findsNothing);
    });

    testWidgets('focus après un échec : champ, puis bouton si le texte est '
        'figé', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.decideResult = () async =>
          const EchecReponse(CauseEchecReponse.reseau);
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Hors du périmètre.');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      app.tickets.decideResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        motif: 'Motif publié, mais l\'Issue n\'a pas été fermée. Réessayez.',
        partiel: true,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Refuser'),
      );
      expect(bouton.focusNode?.hasFocus, isTrue);
    });

    testWidgets('réouverture après un échec partiel : focus au bouton', (
      tester,
    ) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.decideResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        motif: 'Motif publié, mais l\'Issue n\'a pas été fermée. Réessayez.',
        partiel: true,
      );
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Hors du périmètre.');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Refuser'),
      );
      expect(bouton.focusNode?.hasFocus, isTrue);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
    });

    testWidgets('lancement en cours d\'appel : décisions inactives, aucune '
        'décision ne part', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      final lancement = app.container.read(
        lancementFicheProvider('t1').notifier,
      );
      unawaited(lancement.lancer(ActionLancement.analyse));
      await tester.pump();
      // Aucun bouton de lancement sur ce ticket : la ligne dit pourquoi les
      // décisions sont inactives.
      expect(find.text('Lancement en cours.'), findsOneWidget);
      for (final label in ['Valider', 'Refuser', 'Clore']) {
        final button = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        );
        expect(button.onPressed, isNull, reason: label);
      }
      final resultat = await app.container
          .read(decisionsFicheProvider('t1').notifier)
          .decider(TicketDecisionAction.validate);
      expect(resultat.echec?.cause, CauseEchecReponse.autre);
      expect(app.tickets.decisionsAppelees, isEmpty);
    });

    testWidgets('échec partiel : texte figé, message dédié', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.decideResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        motif: 'Motif publié, mais l\'Issue n\'a pas été fermée. Réessayez.',
        partiel: true,
      );
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Hors du périmètre.');
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      expect(
        find.text(
          'Le motif est publié sur GitHub, mais l\'Issue n\'est pas fermée. '
          'Refuser à nouveau termine sans republier.',
        ),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isTrue);
    });

    testWidgets('hors ligne : boutons inactifs, une seule ligne, aucun appel', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unTicket(allowedDecisions: all, canAnswer: true),
        offline: true,
      );
      for (final label in ['Valider', 'Refuser', 'Clore', 'Répondre']) {
        final button = tester.widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.bySubtype<ButtonStyleButton>(),
          ),
        );
        expect(button.onPressed, isNull, reason: label);
      }
      expect(find.text(kActionsHorsLigne), findsOneWidget);
      await tester.tap(find.text('Valider'));
      await tester.pumpAndSettle();
      expect(find.text('Valider ce ticket ?'), findsNothing);
      expect(app.tickets.decisionsAppelees, isEmpty);
    });

    testWidgets('rejetée : boutons présents, texte repris dans la boîte', (
      tester,
    ) async {
      await fiche(
        tester,
        unTicket(allowedDecisions: all),
        decisions: [
          uneDecision(
            state: TicketDecisionState.rejected,
            errorReason: 'Une décision est déjà en cours sur ce ticket.',
          ),
        ],
      );
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.text('Hors du périmètre.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hors ligne : Relancer l\'envoi inactif, phrase', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unTicket(status: TicketStatus.sendFailed, allowedDecisions: const []),
        offline: true,
      );
      await tester.tap(find.text('Relancer l\'envoi'));
      await settle(tester);
      expect(app.tickets.sendRetries, isEmpty);
      expect(find.text(kRelancerEnvoiHorsLigne), findsOneWidget);
    });

    testWidgets('historique en lecture : boutons affichés', (tester) async {
      await fiche(tester, unTicket(allowedDecisions: all), decisions: null);
      expect(find.text('Valider'), findsOneWidget);
    });

    testWidgets('historique illisible : panne, Réessayer, boutons gardés', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unTicket(allowedDecisions: all),
        decisions: null,
      );
      app.tickets.decisionsOf('t1').addError(StateError('panne'));
      await settle(tester);
      expect(find.text('Impossible de lire les décisions.'), findsOneWidget);
      expect(find.text('Valider'), findsOneWidget);
      app.tickets.publishDecisions('t1', const []);
      await tester.tap(find.text('Réessayer'));
      await settle(tester);
      expect(find.text('Impossible de lire les décisions.'), findsNothing);
      expect(find.text('Valider'), findsOneWidget);
    });

    testWidgets('boîte ouverte pendant un passage en large : appel parti', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unTicket(allowedDecisions: all),
        width: 1000,
      );
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Hors du périmètre.');
      // La fenêtre passe le seuil côte à côte : la fiche est reconstruite
      // à droite de la liste, la boîte reste ouverte.
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.text('Refuser ce ticket'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
      await settle(tester);
      final d = app.tickets.decisionsAppelees.single;
      expect(d.action, TicketDecisionAction.refuse);
      expect(d.text, 'Hors du périmètre.');
      // La nouvelle fiche montre l'appel en cours.
      expect(find.text('Refus en cours sur GitHub.'), findsOneWidget);
    });

    testWidgets('boîte annulée puis passage en large : brouillon gardé', (
      tester,
    ) async {
      await fiche(tester, unTicket(allowedDecisions: all), width: 1000);
      await tester.tap(find.text('Clore'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Déjà fait.');
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clore'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.text('Déjà fait.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('décision en cours sur le serveur : aucun bouton', (
      tester,
    ) async {
      await fiche(
        tester,
        unTicket(
          allowedDecisions: all,
          decisionLeaseUntil: now.add(const Duration(minutes: 1)),
        ),
      );
      expect(find.text('Décision en cours sur GitHub.'), findsOneWidget);
      expect(find.text('Valider'), findsNothing);
    });

    testWidgets('Relancer l\'envoi : appel, indicateur, message', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unTicket(
          status: TicketStatus.sendFailed,
          sendAttempts: 10,
          lastSendError: 'GitHub indisponible',
          statusChangedAt: DateTime(2026, 11, 8, 10),
          allowedDecisions: const [],
        ),
      );
      expect(find.text('Essais d\'envoi : 10'), findsOneWidget);
      expect(
        find.text('Dernière erreur : GitHub indisponible'),
        findsOneWidget,
      );
      final server = Completer<ResultatRelanceEnvoi>();
      app.tickets.retrySendResult = () => server.future;
      await tester.tap(find.text('Relancer l\'envoi'));
      await tester.pump();
      expect(app.tickets.sendRetries, ['t1']);
      expect(find.text('Relance en cours'), findsOneWidget);
      server.complete(
        const ResultatRelanceEnvoi.envoi(
          status: TicketStatus.received,
          issueNumber: 12,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ticket envoyé sur GitHub : Issue #12.'),
        findsOneWidget,
      );
    });

    testWidgets('relance en échec : annoncée, bouton revenu', (tester) async {
      final app = await fiche(
        tester,
        unTicket(status: TicketStatus.sendFailed, allowedDecisions: const []),
      );
      app.tickets.retrySendResult = () async =>
          const ResultatRelanceEnvoi.echec(
            EchecReponse(
              CauseEchecReponse.motif,
              motif:
                  'GitHub refuse le jeton. L\'envoi reprendra quand le jeton '
                  'sera remplacé.',
            ),
          );
      await tester.tap(find.text('Relancer l\'envoi'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Envoi non relancé : GitHub refuse le jeton. L\'envoi reprendra '
          'quand le jeton sera remplacé.',
        ),
        findsOneWidget,
      );
      expect(find.text('Relancer l\'envoi'), findsOneWidget);
    });

    testWidgets('Issue disparue : phrase datée', (tester) async {
      await fiche(
        tester,
        unTicket(
          issueMissingSince: DateTime(2026, 11, 7),
          allowedDecisions: const [],
        ),
      );
      expect(
        find.text(
          'Issue introuvable sur GitHub depuis le 07/11/26. Vérifiez qu\'elle '
          'n\'a pas été supprimée.',
        ),
        findsOneWidget,
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.link_off).last);
      expect(
        icon.color,
        Theme.of(
          tester.element(find.byIcon(Icons.link_off).last),
        ).colorScheme.error,
      );
    });

    testWidgets('écran bas : la barre passe en fin de fiche', (tester) async {
      await fiche(tester, unTicket(allowedDecisions: all), height: 400);
      await tester.scrollUntilVisible(find.text('Valider'), 200);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Valider', skipOffstage: false),
        ),
        findsOneWidget,
      );
    });

    testWidgets('écran haut : la barre reste hors de la liste défilante', (
      tester,
    ) async {
      await fiche(tester, unTicket(allowedDecisions: all));
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Valider'),
        ),
        findsNothing,
      );
      expect(find.text('Valider'), findsOneWidget);
    });

    testWidgets('changement de statut : clignote et annonce', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(EtiquetteStatut),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(opacity(), 1);
      app.tickets.publishAll([
        unTicket(status: TicketStatus.validated, allowedDecisions: const []),
      ]);
      // Le nouveau statut arrive en une ou deux trames selon l'ordre des
      // abonnements ; le clignotement se mesure 100 ms après son affichage.
      final valide = find.descendant(
        of: find.byType(EtiquetteStatut),
        matching: find.text('Validé'),
      );
      for (var i = 0; i < 3 && valide.evaluate().isEmpty; i++) {
        await tester.pump();
      }
      expect(valide, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      final fading = tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(EtiquetteStatut),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(fading, lessThan(1));
      await tester.pumpAndSettle();
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Statut : Validé'),
      );
    });

    testWidgets('animations réduites : aucun clignotement, annonce faite', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final app = await fiche(tester, unTicket(allowedDecisions: all));
      app.tickets.publishAll([
        unTicket(status: TicketStatus.refused, allowedDecisions: const []),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final value = tester
          .widget<FadeTransition>(
            find.descendant(
              of: find.byType(EtiquetteStatut),
              matching: find.byType(FadeTransition),
            ),
          )
          .opacity
          .value;
      expect(value, 1);
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('Statut : Refusé'),
      );
    });

    testWidgets('texte × 2 sur 360 px : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await admin(tester, width: 360, height: 700);
      app.tickets.publishAll([
        unTicket(
          allowedDecisions: all,
          issueNumber: 12,
          issueUrl: 'https://github.com/ChinaFred/KassBeer/issues/12',
        ),
      ]);
      app.tickets.publishDecisions('t1', const []);
      app.tickets
          .analysesOf('t1')
          .add(const DocumentAbsent<TicketAnalysisDoc>());
      await go(tester, app, AppRoutes.adminTickets);
      expect(tester.takeException(), isNull);
      await go(tester, app, AppRoutes.adminTicket('t1'));
      expect(tester.takeException(), isNull);
    });
  });

  group('Mes tickets', () {
    Future<TestApp> brasseur(WidgetTester tester, {double width = 400}) async {
      final app = TestApp();
      await app.pump(tester, width: width);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('suivi : frise lue étape par étape, titre de l\'encadré', (
      tester,
    ) async {
      final app = await brasseur(tester);
      app.tickets.publish([
        unTicket(status: TicketStatus.closed, replyText: 'Déjà possible.'),
      ]);
      unawaited(
        app.container.read(routerProvider).push(AppRoutes.ticket('t1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Commentaire de clôture'), findsOneWidget);
      expect(find.bySemanticsLabel('Reçu : étape passée'), findsOneWidget);
      expect(find.bySemanticsLabel('Clos : étape actuelle'), findsOneWidget);
      // La frise est avant la description.
      expect(
        tester.getTopLeft(find.bySemanticsLabel('Clos : étape actuelle')).dy,
        lessThan(tester.getTopLeft(find.text('Description')).dy),
      );
      // Côté membre, la pastille ne clignote pas.
      expect(
        find.descendant(
          of: find.byType(EtiquetteStatut),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('suivi en cours : étapes à venir', (tester) async {
      final app = await brasseur(tester);
      app.tickets.publish([unTicket(status: TicketStatus.validated)]);
      unawaited(
        app.container.read(routerProvider).push(AppRoutes.ticket('t1')),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Validé : étape actuelle'), findsOneWidget);
      expect(find.bySemanticsLabel('Livré : à venir'), findsOneWidget);
    });

    testWidgets('téléphone : le suivi s\'ouvre seul, par push', (tester) async {
      final app = await brasseur(tester);
      app.tickets.publish([unTicket()]);
      unawaited(app.container.read(routerProvider).push(AppRoutes.tickets));
      await tester.pumpAndSettle();
      expect(find.text(MyTicketsScreen.noSelection), findsNothing);
      await tester.tap(find.text('Densité fausse'));
      await tester.pumpAndSettle();
      expect(find.text('Suivi d\'un ticket'), findsOneWidget);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.text(MyTicketsScreen.titre), findsOneWidget);
    });

    testWidgets('large : suivi à droite par replace, retour à l\'origine', (
      tester,
    ) async {
      final app = await brasseur(tester, width: 1000);
      app.tickets.publish([
        unTicket(),
        unTicket(id: 't2', title: 'Autre idée'),
      ]);
      final router = app.container.read(routerProvider);
      unawaited(router.push(AppRoutes.tickets));
      await tester.pumpAndSettle();
      expect(find.text(MyTicketsScreen.noSelection), findsOneWidget);
      final liste = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Densité fausse'));
      // Même page : aucune transition à attendre.
      await tester.pump();
      expect(router.state.uri.path, AppRoutes.ticket('t1'));
      expect(find.text('Autre idée'), findsOneWidget);
      expect(find.text('La densité affichée est fausse.'), findsOneWidget);
      expect(find.text(MyTicketsScreen.noSelection), findsNothing);
      // La liste est la même : son état de défilement est gardé.
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable).first),
        same(liste),
      );
      expect(
        tester.getTopLeft(find.text('La densité affichée est fausse.')).dx,
        greaterThan(380),
      );
      // Marge basse : le bouton flottant ne cache pas les dernières lignes.
      final suivi = tester.widget<ListView>(
        find.descendant(
          of: find.byType(TicketDetailPane),
          matching: find.byType(ListView),
        ),
      );
      expect((suivi.padding! as EdgeInsets).bottom, greaterThanOrEqualTo(96));
      await tester.tap(find.text('Autre idée'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.ticket('t2'));
      // Ligne choisie marquée.
      final tile = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('Autre idée').first,
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        tile.color,
        Theme.of(
          tester.element(find.text('Autre idée').first),
        ).colorScheme.secondaryContainer,
      );
      // La flèche retour ramène à l'écran d'où « Mes tickets » a été ouvert.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.recipes);
      expect(find.text(MyTicketsScreen.titre), findsNothing);
    });
  });
}
