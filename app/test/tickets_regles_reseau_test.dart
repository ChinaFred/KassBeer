import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_delivery.dart';
import 'package:kass_beer/features/tickets/domain/ticket_launch.dart';
import 'package:kass_beer/features/tickets/presentation/boite_lancement.dart';
import 'package:kass_beer/features/tickets/presentation/section_livraison.dart';

import 'support/fakes.dart';
import 'support/ticket_fixtures.dart';

/// Lot R2 d'ADR-020 : règles du réseau modifiées par la PR d'un ticket,
/// accord lié à la tête (P39, P45, P46). Le client lit `admin/delivery` tel
/// que le serveur l'écrit : ni motif, ni patch, ni comparaison de têtes.
void main() {
  final now = DateTime(2026, 11, 8, 12, 10);
  const prUrl = 'https://github.com/ChinaFred/KassBeer/pull/34';
  final head = 'a' * 40;

  Ticket enCours({String id = 't1'}) => unTicket(
    id: id,
    status: TicketStatus.inProgress,
    issueNumber: 12,
    issueUrl: 'https://github.com/ChinaFred/KassBeer/issues/12',
    allowedDecisions: const [
      TicketDecisionAction.refuse,
      TicketDecisionAction.close,
    ],
    canLaunchDelivery: true,
    canRelaunchDevelopment: true,
  );

  TicketDelivery regles({
    String? sensitive,
    bool complete = true,
    AccordRegles? ack,
    bool ackValid = false,
  }) => TicketDelivery(
    eligiblePrCount: 1,
    prNumber: 34,
    prUrl: prUrl,
    headSha: head,
    ciStatus: 'completed',
    ciConclusion: 'success',
    ready: true,
    networkRulesFiles: const ['CLAUDE.md', 'scripts/changelog-recent.mjs'],
    networkRulesControls: const [10, 65],
    networkRulesControlsComplete: complete,
    sensitiveFile: sensitive,
    networkRulesAck: ack,
    networkRulesAckValid: ackValid,
  );
  const quota = EtatLancements(day: '20261108', countDay: 3, perDay: 10);

  LigneLivraison? ligne(TicketDelivery doc) => ligneLivraison(
    ticket: enCours(),
    livraison: DocumentTrouve(doc),
    livraisonEnPanne: false,
    historique: const TicketLaunchesDoc(entries: []),
    quota: quota,
    now: now,
    offline: false,
    appelEnCours: false,
  );

  group('domaine', () {
    test('admin/delivery : champs des règles du réseau lus tels quels', () {
      final d = TicketDelivery.fromFirestore({
        'eligible_pr_count': 1,
        'pr_number': 34,
        'head_sha': head,
        'ready': true,
        'network_rules_files': ['CLAUDE.md'],
        'network_rules_controls': [10, 65],
        'network_rules_controls_complete': false,
        'sensitive_files': 'functions/src/auth.ts',
        'files_complete': true,
        'network_rules_ack': {'head_sha': head, 'ack_id': 'x', 'comment_id': 7},
        'network_rules_ack_valid': true,
      });
      expect(d.headSha, head);
      expect(d.reglesDuReseau, isTrue);
      expect(d.networkRulesControls, [10, 65]);
      expect(d.networkRulesControlsComplete, isFalse);
      expect(d.sensitiveFile, 'functions/src/auth.ts');
      expect(d.networkRulesAck?.publie, isTrue);
      expect(d.etatAccord(), 'Accord donné pour la tête aaaaaaa.');
    });

    test('document d\'avant R2 : aucune règle, rien d\'illisible', () {
      final d = TicketDelivery.fromFirestore({'ready': true});
      expect(d.reglesDuReseau, isFalse);
      expect(d.networkRulesControlsComplete, isTrue);
      expect(d.filesComplete, isTrue);
      expect(d.etatAccord(), isNull);
    });

    test('champ mal typé : illisible', () {
      expect(
        () =>
            TicketDelivery.fromFirestore({'network_rules_files': 'CLAUDE.md'}),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(
        () => TicketDelivery.fromFirestore({
          'network_rules_controls': ['P10'],
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('état de l\'accord : lu dans network_rules_ack_valid, sans sha', () {
      final publie = AccordRegles(headSha: head, publie: true);
      expect(
        regles(ack: publie, ackValid: false).etatAccord(),
        'Accord annulé par un nouveau commit.',
      );
      // Accord jamais publié : rien à dire.
      expect(regles(ack: AccordRegles(headSha: head)).etatAccord(), isNull);
      // Livraison en cours : son commit de fusion n'annule pas l'accord affiché.
      expect(
        regles(ack: publie).etatAccord(livraisonEnCours: true),
        'Accord donné pour la tête aaaaaaa. Livraison en cours.',
      );
    });

    test('lien du diff : ce dépôt, https, /files', () {
      expect(
        lienDiffPullRequest(34).toString(),
        'https://github.com/ChinaFred/KassBeer/pull/34/files',
      );
      expect(lienDiffPullRequest(null), isNull);
      expect(lienDiffPullRequest(0), isNull);
      expect(lienDiffPullRequest(-3), isNull);
      expect(listeControles(const []), 'aucun');
      expect(listeControles(const [10, 65]), 'P10, P65');
    });

    test('refus des contrôles illisibles : fusion à la main', () {
      expect(
        kRefusFusionALaMain,
        contains('delivery_network_rules_unreadable'),
      );
    });
  });

  group('ligne de la barre', () {
    test('PR de règles prête : bouton de livraison marqué règles', () {
      final l = ligne(regles())!;
      expect(l.action, ActionLancement.livraison);
      expect(l.reglesDuReseau, isTrue);
      expect(l.actif, isTrue);
      expect(
        l.texte,
        'PR #34 prête : CI verte. Elle change les règles du réseau : lisez le '
        'diff avant d\'approuver.',
      );
    });

    test('fichier protégé ou contrôles illisibles : aucun bouton', () {
      final protege = ligne(regles(sensitive: 'functions/src/auth.ts'))!;
      expect(protege.action, isNull);
      expect(protege.texte, contains('fusionnez-la vous-même'));
      final illisible = ligne(regles(complete: false))!;
      expect(illisible.action, isNull);
      expect(illisible.texte, contains('ne peuvent pas être lus'));
    });

    test('liste des fichiers trop longue : texte à part, aucun bouton', () {
      final l = ligne(
        TicketDelivery(
          eligiblePrCount: 1,
          prNumber: 34,
          prUrl: prUrl,
          headSha: head,
          ciStatus: 'completed',
          ciConclusion: 'success',
          ready: true,
          networkRulesFiles: const ['CLAUDE.md'],
          filesComplete: false,
        ),
      )!;
      expect(l.action, isNull);
      expect(
        l.texte,
        'La liste des fichiers de la PR #34 est trop longue pour être '
        'vérifiée. Fusionnez-la vous-même après relecture.',
      );
    });

    test('tête absente : état incomplet, aucun bouton', () {
      final l = ligne(
        const TicketDelivery(
          eligiblePrCount: 1,
          prNumber: 34,
          prUrl: prUrl,
          ciStatus: 'completed',
          ciConclusion: 'success',
          ready: true,
          networkRulesFiles: ['CLAUDE.md'],
        ),
      )!;
      expect(l.action, isNull);
      expect(l.texte, kEtatPrIncomplet);
    });

    test('CI en cours : le bouton annoncé suit la PR', () {
      const enCoursCi = TicketDelivery(
        eligiblePrCount: 1,
        prNumber: 34,
        prUrl: prUrl,
        ciStatus: 'in_progress',
        networkRulesFiles: ['CLAUDE.md'],
      );
      expect(
        ligne(enCoursCi)!.texte,
        'CI de la PR #34 en cours. « Approuver les règles et livrer » sera '
        'proposé quand elle sera verte.',
      );
    });

    test('PR sans règle : « Livrer » comme avant', () {
      const prete = TicketDelivery(
        eligiblePrCount: 1,
        prNumber: 34,
        prUrl: prUrl,
        ciStatus: 'completed',
        ciConclusion: 'success',
        ready: true,
      );
      expect(ligne(prete)!.reglesDuReseau, isFalse);
    });
  });

  group('dépôt', () {
    test(
      'Approuver les règles : mode network_rules et tête affichée',
      () async {
        final calls = <(String, Map<String, Object?>)>[];
        final repository = FirestoreTicketsRepository(
          errorReportService: RecordingErrorReportService(),
          firestore: FakeFirebaseFirestore(),
          callable: (name, data) async {
            calls.add((name, data));
            return {'outcome': 'launched'};
          },
        );
        await repository.launch(
          ticketId: 't1',
          action: ActionLancement.livraison,
          teteAccordee: head,
        );
        expect(calls.single.$1, 'launchTicketDelivery');
        expect(calls.single.$2, {
          'ticketId': 't1',
          'mode': 'network_rules',
          'headSha': head,
        });
      },
    );
  });

  group('fiche et liste', () {
    Future<TestApp> fiche(WidgetTester tester, TicketDelivery doc) async {
      final app = TestApp();
      await app.pump(tester, width: 400, height: 2400);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.deliveryOf('t1').add(DocumentTrouve(doc));
      app.tickets.launchStatus.add(const DocumentTrouve(quota));
      app.tickets.publishAll([enCours()]);
      app.tickets.publishDecisions('t1', const []);
      app.tickets.analysesOf('t1').add(const DocumentAbsent());
      app.container.read(routerProvider).go(AppRoutes.adminTicket('t1'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('« Approuver les règles et livrer » remplace « Livrer » ; '
        'boîte : fichiers, contrôles, diff, numéro à saisir, tête envoyée', (
      tester,
    ) async {
      final app = await fiche(tester, regles());
      expect(find.widgetWithText(FilledButton, 'Livrer'), findsNothing);
      expect(find.text(kReglesModifiees), findsOneWidget);
      expect(
        find.text('Fichiers : CLAUDE.md, scripts/changelog-recent.mjs.'),
        findsOneWidget,
      );
      expect(find.text('Contrôles changés : P10, P65.'), findsOneWidget);
      expect(
        find.text(
          '${SectionLivraison.vide} ${SectionLivraison.invitationRegles}',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(kApprouverRegles));
      await tester.pumpAndSettle();
      expect(find.text(BoiteLancement.titreAccordRegles), findsOneWidget);
      expect(find.text('PR #34, tête aaaaaaa.'), findsOneWidget);
      expect(find.text('• CLAUDE.md'), findsOneWidget);
      expect(find.text('• scripts/changelog-recent.mjs'), findsOneWidget);
      expect(find.text(BoiteLancement.avertissementRegles), findsOneWidget);
      expect(find.text(BoiteLancement.lireLeDiff), findsOneWidget);
      expect(find.text(BoiteLancement.accordFusionRegles), findsOneWidget);
      expect(find.text(ligneQuota(quota)), findsOneWidget);
      FilledButton approuver() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, BoiteLancement.libelleApprouver),
      );
      expect(approuver().onPressed, isNull);
      expect(find.text(BoiteLancement.libelleNumero), findsOneWidget);
      expect(find.text(BoiteLancement.saisieNumero), findsOneWidget);
      await tester.enterText(find.byType(TextField), '3a');
      await tester.pump();
      // Chiffres seuls : la lettre est retirée.
      expect(find.text(BoiteLancement.numeroFaux(34)), findsNothing);
      await tester.enterText(find.byType(TextField), '35');
      await tester.pump();
      expect(approuver().onPressed, isNull);
      expect(find.text(BoiteLancement.numeroFaux(34)), findsOneWidget);
      // Saisie plus longue que le numéro : même erreur.
      await tester.enterText(find.byType(TextField), '345');
      await tester.pump();
      expect(find.text(BoiteLancement.numeroFaux(34)), findsOneWidget);
      expect(approuver().onPressed, isNull);
      // Saisie plus courte : pas encore d'erreur.
      await tester.enterText(find.byType(TextField), '3');
      await tester.pump();
      expect(find.text(BoiteLancement.numeroFaux(34)), findsNothing);
      await tester.enterText(find.byType(TextField), '34');
      await tester.pump();
      expect(approuver().onPressed, isNotNull);
      await tester.tap(
        find.widgetWithText(FilledButton, BoiteLancement.libelleApprouver),
      );
      await tester.pump();
      expect(app.tickets.launches.single.action, ActionLancement.livraison);
      expect(app.tickets.teteAccordees.single, head);
    });

    testWidgets('refus « la PR a changé » : bouton inactif, relire la PR ; '
        'accord non publié : nouvel essai possible', (tester) async {
      final app = await fiche(tester, regles());
      app.tickets.launchResult = () async => const ResultatLancement(
        IssueLancement.refuse,
        motif:
            'La PR a changé depuis l\'affichage. Relisez-la, puis approuvez à '
            'nouveau. Rien n\'a été lancé ni décompté.',
        code: 'delivery_head_changed',
      );
      await tester.tap(find.text(kApprouverRegles));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '34');
      await tester.pump();
      final bouton = find.widgetWithText(
        FilledButton,
        BoiteLancement.libelleApprouver,
      );
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(find.textContaining(BoiteLancement.relirePr), findsOneWidget);
      expect(tester.widget<FilledButton>(bouton).onPressed, isNull);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      app.tickets.launchResult = () async => const ResultatLancement(
        IssueLancement.refuse,
        motif:
            'L\'accord n\'a pas pu être publié sur GitHub. Réessayez. Rien '
            'n\'a été lancé ni décompté.',
        code: 'delivery_ack_publish_failed',
      );
      await tester.tap(find.text(kApprouverRegles));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '34');
      await tester.pump();
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      expect(find.textContaining('Réessayez.'), findsOneWidget);
      expect(find.textContaining(BoiteLancement.relirePr), findsNothing);
      expect(tester.widget<FilledButton>(bouton).onPressed, isNotNull);
    });

    testWidgets('accord annulé par un nouveau commit : affiché', (
      tester,
    ) async {
      await fiche(
        tester,
        regles(ack: AccordRegles(headSha: 'b' * 40, publie: true)),
      );
      expect(find.text('Accord annulé par un nouveau commit.'), findsOneWidget);
    });

    testWidgets('« Livrer » : aucune tête envoyée', (tester) async {
      final app = await fiche(
        tester,
        const TicketDelivery(
          eligiblePrCount: 1,
          prNumber: 34,
          prUrl: prUrl,
          ciStatus: 'completed',
          ciConclusion: 'success',
          ready: true,
        ),
      );
      expect(find.text(kReglesModifiees), findsNothing);
      await tester.tap(find.text('Livrer'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Livrer').last);
      await tester.pump();
      expect(app.tickets.teteAccordees.single, isNull);
    });

    testWidgets('liste : étiquette « Règles du réseau modifiées »', (
      tester,
    ) async {
      final app = TestApp();
      app.tickets.deliveryOf('a').add(DocumentTrouve(regles()));
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.publishAll([enCours(id: 'a')]);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      expect(find.text(kReglesModifiees), findsOneWidget);
    });
  });
}
