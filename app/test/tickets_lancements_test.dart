import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_analysis.dart';
import 'package:kass_beer/features/tickets/domain/ticket_launch.dart';
import 'package:kass_beer/features/tickets/presentation/admin_ticket_screen.dart';
import 'package:kass_beer/features/tickets/presentation/boite_lancement.dart';
import 'package:kass_beer/features/tickets/presentation/lien_usage_claude.dart';
import 'package:kass_beer/features/tickets/presentation/section_lancements.dart';

import 'support/fakes.dart';
import 'support/ticket_fixtures.dart';

/// Lot T4 d'ADR-008 : lancements de sessions Claude Code (P39, P41, P42).
void main() {
  final t0 = DateTime(2026, 11, 8, 9, 30);
  final t1 = DateTime(2026, 11, 8, 11, 50);

  Map<String, Object?> ticketData(List<String> allowed) => {
    'type': 'bug',
    'title': 'Densité fausse',
    'description': 'La densité affichée est fausse.',
    'screen': '/recettes/:id',
    'status': 'received',
    'allowed_decisions': allowed,
  };

  group('domaine', () {
    test('lancements lus dans allowed_decisions, hors des décisions', () {
      final t = Ticket.fromFirestore(
        't1',
        ticketData(['refuse', 'answer', 'launch_analysis']),
      );
      expect(t.canLaunchAnalysis, isTrue);
      expect(t.canLaunchDevelopment, isFalse);
      expect(t.canLaunch(ActionLancement.analyse), isTrue);
      expect(t.allowedDecisions, [TicketDecisionAction.refuse]);
      expect(TicketDecisionAction.fromStored(kLaunchAnalysisDecision), isNull);
      final dev = Ticket.fromFirestore(
        't2',
        ticketData(['launch_development']),
      );
      expect(dev.canLaunch(ActionLancement.developpement), isTrue);
      expect(
        Ticket.fromFirestore('t3', ticketData([])).canLaunchAnalysis,
        isFalse,
      );
    });

    test('historique : tri, valeurs inconnues gardées, vingt au plus', () {
      final doc = TicketLaunchesDoc.fromFirestore({
        'entries': [
          {
            'action': 'analyse',
            'state': 'launched',
            'at': Timestamp.fromDate(t0),
            'by_uid': 'uid-admin',
            'retry_after': Timestamp.fromDate(t0.add(const Duration(hours: 1))),
            'session_url': 'https://claude.ai/code/session_1',
          },
          {'action': 'futur', 'state': 'futur', 'at': Timestamp.fromDate(t1)},
          for (var i = 0; i < 25; i++)
            {
              'action': 'developpement',
              'state': 'failed',
              'at': Timestamp.fromDate(DateTime(2026, 11, 1, 0, i)),
              'reason': 'Refus.',
            },
        ],
      });
      expect(doc.entries, hasLength(kTicketLaunchHistoryMax));
      expect(doc.entries.first.action, isNull);
      expect(doc.entries.first.etat, isNull);
      expect(doc.entries[1].action, ActionLancement.analyse);
      expect(doc.entries[1].sessionUrl, 'https://claude.ai/code/session_1');
    });

    test('ended_by « stopped » lu : développement arrêté par la session', () {
      final doc = TicketLaunchesDoc.fromFirestore({
        'entries': [
          {
            'action': 'developpement',
            'state': 'launched',
            'at': Timestamp.fromDate(t0),
            'retry_after': Timestamp.fromDate(t0),
            'ended_by': 'stopped',
          },
          {
            'action': 'livraison',
            'state': 'launched',
            'at': Timestamp.fromDate(t1),
            'ended_by': 'blocked',
          },
        ],
      });
      final dev = doc.entries.firstWhere(
        (e) => e.action == ActionLancement.developpement,
      );
      expect(dev.arreteParLaSession, isTrue);
      expect(dev.arreteeParBlocage, isFalse);
      expect(doc.entries.first.arreteParLaSession, isFalse);
    });

    test('historique mal typé : illisible', () {
      expect(
        () => TicketLaunchesDoc.fromFirestore({'entries': 'texte'}),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(
        () => TicketLaunchesDoc.fromFirestore({
          'entries': [
            {'action': 'analyse', 'at': 'hier'},
          ],
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('en cours d\'après retry_after seul ; relance après échéance', () {
      final now = DateTime(2026, 11, 8, 12, 10);
      TicketLaunch entree(
        EtatLancement etat,
        DateTime at,
        Duration delai, [
        ActionLancement action = ActionLancement.analyse,
      ]) => TicketLaunch(
        action: action,
        etat: etat,
        at: at,
        retryAfter: at.add(delai),
      );
      final enCours = TicketLaunchesDoc(
        entries: [entree(EtatLancement.unknown, t1, const Duration(hours: 1))],
      );
      expect(enCours.enCours(ActionLancement.analyse, now), isNotNull);
      expect(enCours.enCours(ActionLancement.developpement, now), isNull);
      expect(
        enCours.aRelancer(ActionLancement.analyse, now, statusChangedAt: null),
        isNull,
      );

      final passe = TicketLaunchesDoc(
        entries: [entree(EtatLancement.launched, t0, const Duration(hours: 1))],
      );
      expect(passe.enCours(ActionLancement.analyse, now), isNull);
      expect(
        passe
            .aRelancer(ActionLancement.analyse, now, statusChangedAt: null)
            ?.at,
        t0,
      );
      // Statut changé après le lancement : premier lancement, pas une relance.
      expect(
        passe.aRelancer(ActionLancement.analyse, now, statusChangedAt: t1),
        isNull,
      );
      // Dernier lancement en échec : rien n'est parti, pas une relance.
      final echec = TicketLaunchesDoc(
        entries: [
          entree(EtatLancement.failed, t1, Duration.zero),
          entree(EtatLancement.launched, t0, const Duration(hours: 1)),
        ],
      );
      expect(
        echec.aRelancer(ActionLancement.analyse, now, statusChangedAt: null),
        isNull,
      );
    });

    test('état des lancements : lu, mal formé, quota', () {
      final etat = EtatLancements.fromFirestore({
        'day': '20261108',
        'count_day': 3,
        'month': '202611',
        'count_month': 7,
        'per_day': 10,
        'analysis_invalid_since': null,
        'development_invalid_since': Timestamp.fromDate(t0),
      });
      expect(etat.restants, 7);
      expect(etat.plafondAtteint, isFalse);
      expect(etat.developmentInvalidSince, t0);
      expect(ligneQuota(etat), 'Lancements restants le 08/11 : 7 sur 10.');
      expect(
        ligneCompteur(etat),
        'Lancements de sessions : 3 sur 10 le 08/11 · 7 en novembre 2026',
      );
      // Le plafond vient du serveur : sans lui, inconnu (P39).
      expect(
        ligneQuota(const EtatLancements(day: '20261108', countDay: 3)),
        'Lancements restants : inconnu.',
      );
      expect(ligneQuota(null), 'Lancements restants : inconnu.');
      const plein = EtatLancements(day: '20261108', countDay: 4, perDay: 4);
      expect(plein.plafondAtteint, isTrue);
      expect(
        ligneQuota(plein),
        'Plafond atteint le 08/11 : 4 lancements sur 4. Le compteur repart '
        'à zéro peu après minuit.',
      );
      expect(
        lignePlafondAnalyse(plein),
        'Plafond atteint le 08/11 : 4 lancements sur 4. Vous pouvez valider. '
        'Le compteur repart à zéro peu après minuit.',
      );
      expect(const EtatLancements(month: '202601').moisAffiche, 'janvier 2026');
      expect(
        () => EtatLancements.fromFirestore({'day': '8 novembre'}),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(
        () => EtatLancements.fromFirestore({'count_day': 1.5}),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('compte fondateur : son compteur et son plafond, à part du groupe', () {
      final etat = EtatLancements.fromFirestore({
        'day': '20261114',
        'count_day': 10,
        'founder_count_day': 4,
        'month': '202611',
        'count_month': 14,
        'per_day': 10,
        'founder_per_day': 50,
      });
      expect(etat.vuePour(fondateur: false).plafondAtteint, isTrue);
      final fondateur = etat.vuePour(fondateur: true);
      expect(fondateur.restants, 46);
      expect(
        ligneQuota(fondateur),
        'Lancements restants le 14/11 : 46 sur 50.',
      );
      expect(
        ligneCompteur(fondateur),
        'Lancements de sessions : 4 sur 50 le 14/11 · 14 en novembre 2026',
      );
      // Document d'avant le compteur du fondateur : inconnu, jamais le groupe.
      expect(
        ligneQuota(
          const EtatLancements(
            day: '20261114',
            countDay: 10,
            perDay: 10,
          ).vuePour(fondateur: true),
        ),
        'Lancements restants : inconnu.',
      );
    });

    test('lien de session : https sur claude.ai seul', () {
      expect(
        lienSessionOuvrable('https://claude.ai/code/session_1'),
        Uri.parse('https://claude.ai/code/session_1'),
      );
      for (final url in [
        null,
        'http://claude.ai/code/x',
        'https://claude.ai.exemple.fr/x',
        'https://user@claude.ai/x',
        'https://claude.ai:8443/x',
        'javascript:alert(1)',
      ]) {
        expect(lienSessionOuvrable(url), isNull, reason: '$url');
      }
    });

    test('résultat : réponse et erreurs du serveur', () {
      expect(
        ResultatLancement.depuisReponse({'outcome': 'launched'}).issue,
        IssueLancement.lance,
      );
      final inconnu = ResultatLancement.depuisReponse({
        'outcome': 'unknown',
        'reason': 'Claude ne répond pas.',
      });
      expect(inconnu.issue, IssueLancement.inconnu);
      expect(inconnu.message, contains('Résultat inconnu, compté'));
      expect(inconnu.message, contains('Claude ne répond pas.'));
      expect(
        ResultatLancement.depuisReponse('illisible').issue,
        IssueLancement.inconnu,
      );

      final refus = ResultatLancement.depuisErreur(
        code: 'resource-exhausted',
        details: {
          'reason': 'Vous avez lancé 10 sessions aujourd\'hui.',
          'code': 'quota_exceeded',
        },
      );
      expect(refus.issue, IssueLancement.refuse);
      expect(refus.rienNestParti, isTrue);
      expect(refus.code, 'quota_exceeded');
      expect(refus.message, 'Vous avez lancé 10 sessions aujourd\'hui.');
      expect(
        ResultatLancement.depuisErreur(
          code: 'internal',
          details: {'reason': 'Le lancement a échoué.', 'code': 'internal'},
        ).issue,
        IssueLancement.perdu,
      );
      expect(
        ResultatLancement.depuisErreur(
          code: 'internal',
          details: {'reason': 'Rien n\'a été lancé.', 'code': 'not_recorded'},
        ).issue,
        IssueLancement.refuse,
      );
      expect(
        ResultatLancement.depuisErreur(code: 'permission-denied').issue,
        IssueLancement.acces,
      );
      expect(
        ResultatLancement.depuisErreur(code: 'deadline-exceeded').issue,
        IssueLancement.perdu,
      );
      expect(
        ResultatLancement.depuisErreur(code: 'unavailable').issue,
        IssueLancement.perdu,
      );
    });
  });

  group('dépôt', () {
    late FakeFirebaseFirestore firestore;
    late RecordingErrorReportService errors;

    FirestoreTicketsRepository depot({AppelCallable? callable}) =>
        FirestoreTicketsRepository(
          errorReportService: errors,
          firestore: firestore,
          callable: callable,
        );

    setUp(() {
      firestore = FakeFirebaseFirestore();
      errors = RecordingErrorReportService();
    });

    test('historique et état : absent, trouvé, illisible', () async {
      final repository = depot();
      expect(
        await repository.watchLaunches('t1').first,
        isA<DocumentAbsent<TicketLaunchesDoc>>(),
      );
      final ref = firestore.doc('tickets/t1/admin/launches');
      await ref.set({
        'entries': [
          {'action': 'analyse', 'state': 'launched'},
        ],
      });
      final trouve = await repository.watchLaunches('t1').first;
      expect(
        (trouve as DocumentTrouve<TicketLaunchesDoc>).value.entries,
        hasLength(1),
      );
      await ref.set({'entries': 'texte'});
      expect(
        await repository.watchLaunches('t1').first,
        isA<DocumentIllisibleTrouve<TicketLaunchesDoc>>(),
      );
      expect(errors.reports.single.feature, 'tickets.read_launches');

      await firestore.doc('ticket_status/launches').set({
        'day': '20261108',
        'count_day': 2,
        'per_day': 10,
      });
      final etat = await repository.watchLaunchStatus().first;
      expect((etat as DocumentTrouve<EtatLancements>).value.restants, 8);
    });

    test('lancement : nom, données, succès', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repository = depot(
        callable: (name, data) async {
          calls.add((name, data));
          return {
            'outcome': 'launched',
            'sessionUrl': 'https://claude.ai/code/s',
          };
        },
      );
      final r = await repository.launch(
        ticketId: 't1',
        action: ActionLancement.developpement,
      );
      expect(r.issue, IssueLancement.lance);
      expect(calls.single.$1, 'launchTicketDevelopment');
      expect(calls.single.$2, {'ticketId': 't1'});
      expect(errors.reports, isEmpty);
    });

    test('lancement refusé : rapporté par codes, sans le motif', () async {
      final repository = depot(
        callable: (name, data) async => throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Le ticket a changé sur GitHub. Rien n\'a été lancé.',
          details: {
            'reason': 'Le ticket a changé sur GitHub. Rien n\'a été lancé.',
            'code': 'ticket_changed',
          },
        ),
      );
      final r = await repository.launch(
        ticketId: 't1',
        action: ActionLancement.analyse,
      );
      expect(r.issue, IssueLancement.refuse);
      expect(r.message, 'Le ticket a changé sur GitHub. Rien n\'a été lancé.');
      final report = errors.reports.single;
      expect(report.feature, 'tickets.launch');
      expect(report.context, contains('action=analyse'));
      expect(report.context, contains('code=failed-precondition'));
      expect(report.context, contains('reason_code=ticket_changed'));
      expect(report.context, isNot(contains('GitHub')));
    });

    test('lancement sans réponse : perdu, rapporté', () async {
      final repository = depot(
        callable: (name, data) async => throw StateError('coupure'),
      );
      final r = await repository.launch(
        ticketId: 't1',
        action: ActionLancement.analyse,
      );
      expect(r.issue, IssueLancement.perdu);
      expect(r.rienNestParti, isFalse);
      expect(errors.reports.single.feature, 'tickets.launch');
    });
  });

  group('fiche', () {
    const issueUrl = 'https://github.com/ChinaFred/KassBeer/issues/12';

    Future<TestApp> fiche(
      WidgetTester tester,
      Ticket ticket, {
      RechercheDocument<TicketLaunchesDoc>? lancements,
      RechercheDocument<EtatLancements>? etat,
      RechercheDocument<TicketAnalysisDoc> analyses = const DocumentAbsent(),
      bool lectureEnCours = false,
      bool offline = false,
      bool decisionsLues = true,
      double width = 400,
      double height = 2000,
    }) async {
      final app = TestApp();
      await app.pump(tester, width: width, height: height);
      app.signIn(adminUser, member: adminMember, fromCache: offline);
      await tester.pumpAndSettle();
      if (lectureEnCours) app.tickets.launchHistories[ticket.id] = Replay();
      if (lancements != null) app.tickets.launchesOf(ticket.id).add(lancements);
      if (etat != null) app.tickets.launchStatus.add(etat);
      app.tickets.publishAll([ticket]);
      if (decisionsLues) app.tickets.publishDecisions(ticket.id, const []);
      app.tickets.analysesOf(ticket.id).add(analyses);
      app.container.read(routerProvider).go(AppRoutes.adminTicket(ticket.id));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return app;
    }

    Ticket recu({bool canAnswer = true}) => unTicket(
      issueNumber: 12,
      issueUrl: issueUrl,
      allowedDecisions: const [
        TicketDecisionAction.refuse,
        TicketDecisionAction.close,
      ],
      canAnswer: canAnswer,
      canLaunchAnalysis: true,
    );

    Ticket valide() => unTicket(
      status: TicketStatus.validated,
      issueNumber: 12,
      issueUrl: issueUrl,
      allowedDecisions: const [
        TicketDecisionAction.refuse,
        TicketDecisionAction.close,
      ],
      canAnswer: true,
      canLaunchDevelopment: true,
    );

    final quota = DocumentTrouve(
      EtatLancements(day: '20261108', countDay: 3, perDay: 10),
    );

    Finder bouton(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );

    testWidgets('reçu : Lancer l\'analyse, Valider annoncé après analyse', (
      tester,
    ) async {
      await fiche(tester, recu());
      await tester.pumpAndSettle();
      expect(find.text('Lancer l\'analyse'), findsOneWidget);
      expect(find.text('Valider'), findsNothing);
      expect(find.text(kValiderApresAnalyse), findsOneWidget);
      // Section repliée, après les Analyses.
      expect(find.text('Lancements (0)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Lancements (0)')).dy,
        greaterThan(tester.getTopLeft(find.text('Analyses')).dy),
      );
      // Dépliée : section vide, puis où appuyer.
      await tester.ensureVisible(find.text('Lancements (0)'));
      await tester.tap(find.text('Lancements (0)'));
      await tester.pumpAndSettle();
      expect(find.text(SectionLancements.vide), findsOneWidget);
      expect(
        find.text('Appuyez sur « Lancer l\'analyse », en bas de la fiche.'),
        findsOneWidget,
      );
    });

    testWidgets('analysé : Valider, aucun lancement', (tester) async {
      await fiche(
        tester,
        unTicket(
          status: TicketStatus.analyzed,
          issueNumber: 12,
          issueUrl: issueUrl,
          allowedDecisions: const [TicketDecisionAction.validate],
        ),
        etat: const DocumentTrouve(
          EtatLancements(day: '20261108', countDay: 10, perDay: 10),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Valider'), findsOneWidget);
      expect(find.textContaining('Lancer'), findsNothing);
      expect(find.text(kValiderApresAnalyse), findsNothing);
      expect(
        find.text(
          'Plafond atteint le 08/11 : 10 lancements sur 10. Vous pouvez '
          'valider. Le compteur repart à zéro peu après minuit.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('boîte : textes, Annuler sans appel, succès en message', (
      tester,
    ) async {
      final app = await fiche(tester, valide(), etat: quota);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lancer le développement'));
      await tester.pumpAndSettle();
      expect(
        find.text('Lancer le développement de ce ticket ?'),
        findsOneWidget,
      );
      expect(
        find.text(BoiteLancement.effet(ActionLancement.developpement, 12)),
        findsOneWidget,
      );
      expect(find.text('Lancements restants le 08/11 : 7 sur 10.'), findsOne);
      expect(find.text(BoiteLancement.cout), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(app.tickets.launches, isEmpty);

      final server = Completer<ResultatLancement>();
      app.tickets.launchResult = () => server.future;
      await tester.tap(find.text('Lancer le développement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lancer'));
      await tester.pump();
      expect(app.tickets.launches.single, (
        ticketId: 't1',
        action: ActionLancement.developpement,
      ));
      expect(find.text(BoiteLancement.envoiEnCours), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
      expect(find.bySemanticsLabel('Lancement en cours'), findsWidgets);
      server.complete(const ResultatLancement(IssueLancement.lance));
      await tester.pumpAndSettle();
      expect(find.byType(BoiteLancement), findsNothing);
      expect(
        find.text('Session lancée. Le lien est dans la section Lancements.'),
        findsOneWidget,
      );
    });

    testWidgets('usage Claude : lien de la boîte, rien lancé', (tester) async {
      final app = await fiche(tester, valide(), etat: quota);
      await tester.pumpAndSettle();
      final usage = Uri.parse('https://claude.ai/settings/usage');
      // Fiche seule (téléphone) : le bandeau ne porte pas le lien.
      expect(find.text(LienUsageClaude.libelle), findsNothing);

      await tester.tap(find.text('Lancer le développement'));
      await tester.pumpAndSettle();
      final lienBoite = find.descendant(
        of: find.byType(BoiteLancement),
        matching: find.text(LienUsageClaude.libelle),
      );
      expect(lienBoite, findsOneWidget);
      // Sous « Lancements restants », avant le coût.
      expect(
        tester.getTopLeft(lienBoite).dy,
        greaterThan(
          tester
              .getTopLeft(find.text('Lancements restants le 08/11 : 7 sur 10.'))
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(lienBoite).dy,
        lessThan(tester.getTopLeft(find.text(BoiteLancement.cout)).dy),
      );
      expect(
        tester.getSize(find.byType(LienUsageClaude)).height,
        greaterThanOrEqualTo(48),
      );
      // Lecteur d'écran : bouton au libellé visible, action d'appui.
      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byType(LienUsageClaude),
            matching: find.byWidgetPredicate((w) => w is TextButton),
          ),
        ),
        matchesSemantics(
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          label: LienUsageClaude.libelle,
        ),
      );
      expect(find.byTooltip(LienUsageClaude.description), findsOneWidget);
      await tester.tap(lienBoite);
      await tester.pumpAndSettle();
      expect(app.openedLinks.single, usage);
      // Le lien ne lance rien et la boîte reste ouverte.
      expect(app.tickets.launches, isEmpty);
      expect(find.byType(BoiteLancement), findsOneWidget);
      expect(app.errors.reports, isEmpty);
    });

    testWidgets('usage Claude : ouverture refusée, rapportée', (tester) async {
      final app = await fiche(tester, valide(), etat: quota);
      await tester.pumpAndSettle();
      app.openLinkResult = false;
      await tester.tap(find.text('Lancer le développement'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(LienUsageClaude.libelle));
      await tester.pumpAndSettle();
      // Échec affiché dans la boîte, au-dessus du voile.
      expect(
        find.descendant(
          of: find.byType(BoiteLancement),
          matching: find.text(LienUsageClaude.echec),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      final report = app.errors.reports.single;
      expect(report.feature, 'tickets.open_claude_usage');
      expect(report.context, isNot(contains('claude.ai')));
      // Un second appui réussi efface le message.
      app.openLinkResult = true;
      await tester.tap(find.text(LienUsageClaude.libelle));
      await tester.pumpAndSettle();
      expect(find.text(LienUsageClaude.echec), findsNothing);
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('boîte : refus affiché, la boîte reste ouverte', (
      tester,
    ) async {
      final app = await fiche(tester, recu(), etat: quota);
      await tester.pumpAndSettle();
      app.tickets.launchResult = () async => const ResultatLancement(
        IssueLancement.refuse,
        motif: 'Le ticket a changé sur GitHub. Rien n\'a été lancé.',
      );
      await tester.tap(find.text('Lancer l\'analyse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lancer'));
      await tester.pumpAndSettle();
      expect(find.byType(BoiteLancement), findsOneWidget);
      expect(
        find.text('Le ticket a changé sur GitHub. Rien n\'a été lancé.'),
        findsOneWidget,
      );
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('boîte fermée pendant l\'envoi : résultat en message', (
      tester,
    ) async {
      final app = await fiche(tester, recu(), etat: quota);
      await tester.pumpAndSettle();
      final server = Completer<ResultatLancement>();
      app.tickets.launchResult = () => server.future;
      await tester.tap(find.text('Lancer l\'analyse'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lancer'));
      await tester.pump();
      await tester.tap(find.text('Fermer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BoiteLancement), findsNothing);
      // Un seul appel à la fois : bouton inactif pendant l'appel.
      expect(find.text('Lancement de l\'analyse en cours.'), findsOneWidget);
      expect(
        tester.widget<ButtonStyleButton>(bouton('Lancer l\'analyse')).onPressed,
        isNull,
      );
      server.complete(const ResultatLancement(IssueLancement.perdu));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Réponse perdue. Regardez la section Lancements avant de relancer.',
        ),
        findsOneWidget,
      );
      // Résultat inconnu : message d'échec de 10 s.
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        kDureeMessageEchec,
      );
      expect(app.tickets.launches, hasLength(1));
    });

    testWidgets('en cours : ligne datée, aucun bouton ; Répondre masqué', (
      tester,
    ) async {
      await fiche(
        tester,
        valide(),
        etat: quota,
        lancements: DocumentTrouve(
          TicketLaunchesDoc(
            entries: [
              TicketLaunch(
                action: ActionLancement.developpement,
                etat: EtatLancement.launched,
                at: t1,
                retryAfter: t1.add(const Duration(hours: 3)),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Développement en cours depuis 11:50'), findsOneWidget);
      expect(find.text('Lancer le développement'), findsNothing);
      expect(find.text('Répondre'), findsNothing);
      expect(find.text('Refuser'), findsOneWidget);
    });

    testWidgets('relance : bouton tonal, avertissement dans la boîte', (
      tester,
    ) async {
      await fiche(
        tester,
        recu(),
        etat: quota,
        lancements: DocumentTrouve(
          TicketLaunchesDoc(
            entries: [
              TicketLaunch(
                action: ActionLancement.analyse,
                etat: EtatLancement.unknown,
                at: t0,
                retryAfter: t0.add(const Duration(hours: 1)),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final relance = BoiteLancement.avertissementRelance(t0);
      expect(find.text(relance), findsOneWidget);
      await tester.tap(find.text('Relancer l\'analyse'));
      await tester.pumpAndSettle();
      expect(find.text('Relancer l\'analyse de ce ticket ?'), findsOneWidget);
      expect(find.text(relance), findsNWidgets(2));
      expect(find.text('Relancer'), findsOneWidget);
    });

    testWidgets('développement arrêté : « s\'est arrêté », relance offerte', (
      tester,
    ) async {
      await fiche(
        tester,
        valide(),
        etat: quota,
        lancements: DocumentTrouve(
          TicketLaunchesDoc(
            entries: [
              TicketLaunch(
                action: ActionLancement.developpement,
                etat: EtatLancement.launched,
                at: t0,
                // Ramené par le serveur à l'heure du relevé de l'arrêt.
                retryAfter: t0.add(const Duration(minutes: 20)),
                endedBy: kDeveloppementFinArret,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ligne = ligneDeveloppementArrete(t0);
      expect(ligne, contains('s\'est arrêté'));
      expect(find.text(ligne), findsOneWidget);
      expect(find.text(BoiteLancement.avertissementRelance(t0)), findsNothing);
      await tester.tap(find.text('Relancer le développement'));
      await tester.pumpAndSettle();
      expect(find.text(ligne), findsNWidgets(2));
      expect(find.text('Relancer'), findsOneWidget);
    });

    testWidgets('plafond atteint : bouton inactif, ligne', (tester) async {
      await fiche(
        tester,
        recu(),
        etat: const DocumentTrouve(
          EtatLancements(day: '20261108', countDay: 10, perDay: 10),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ButtonStyleButton>(bouton('Lancer l\'analyse')).onPressed,
        isNull,
      );
      expect(
        find.text(
          'Plafond atteint le 08/11 : 10 lancements sur 10. Le compteur '
          'repart à zéro peu après minuit.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'validé sur GitHub seul : Valider offert, ligne, aucun lancement',
      (tester) async {
        await fiche(
          tester,
          unTicket(
            status: TicketStatus.validated,
            issueNumber: 12,
            issueUrl: issueUrl,
            allowedDecisions: const [
              TicketDecisionAction.validate,
              TicketDecisionAction.refuse,
              TicketDecisionAction.close,
            ],
            canAnswer: true,
          ),
          etat: quota,
        );
        await tester.pumpAndSettle();
        expect(find.text('Valider'), findsOneWidget);
        expect(find.text('Lancer le développement'), findsNothing);
        expect(find.text(kValiderDepuisApplication), findsOneWidget);
        expect(find.text(kValiderApresAnalyse), findsNothing);
      },
    );

    testWidgets(
      'validé dans l\'application : lancement, sans la ligne GitHub',
      (tester) async {
        await fiche(tester, valide(), etat: quota);
        await tester.pumpAndSettle();
        expect(find.text('Lancer le développement'), findsOneWidget);
        expect(find.text(kValiderDepuisApplication), findsNothing);
      },
    );

    testWidgets('relance et précisions en attente : deux lignes', (
      tester,
    ) async {
      await fiche(
        tester,
        recu(),
        etat: quota,
        lancements: DocumentTrouve(
          TicketLaunchesDoc(
            entries: [
              TicketLaunch(
                action: ActionLancement.analyse,
                etat: EtatLancement.unknown,
                at: t0,
                retryAfter: t0.add(const Duration(hours: 1)),
              ),
            ],
          ),
        ),
        analyses: DocumentTrouve(
          TicketAnalysisDoc(
            analyses: [
              TicketAnalysis(
                kind: TicketAnalysisKind.reply,
                body: '## Précisions de l\'administrateur\n\nTexte.',
                createdAt: t1,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(BoiteLancement.avertissementRelance(t0)),
        findsOneWidget,
      );
      expect(
        find.text(
          'Vos précisions du 08/11/26 à 11:50 seront lues par la prochaine '
          'analyse.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('section vide : pas d\'invitation au plafond', (tester) async {
      const invitation =
          'Appuyez sur « Lancer l\'analyse », en bas de la fiche.';
      await fiche(
        tester,
        recu(),
        etat: const DocumentTrouve(
          EtatLancements(day: '20261108', countDay: 10, perDay: 10),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lancements (0)'));
      await tester.tap(find.text('Lancements (0)'));
      await tester.pumpAndSettle();
      expect(find.text(SectionLancements.vide), findsOneWidget);
      expect(find.text(invitation), findsNothing);
    });

    testWidgets(
      'section vide : pas d\'invitation sans bouton (décision en cours)',
      (tester) async {
        const invitation =
            'Appuyez sur « Lancer l\'analyse », en bas de la fiche.';
        Future<void> deplier() async {
          await tester.ensureVisible(find.text('Lancements (0)'));
          await tester.tap(find.text('Lancements (0)'));
          await tester.pump(const Duration(seconds: 1));
        }

        // Décision en cours sur GitHub : la barre n'a aucun bouton.
        final enCours = unTicket(
          issueNumber: 12,
          issueUrl: issueUrl,
          allowedDecisions: const [
            TicketDecisionAction.refuse,
            TicketDecisionAction.close,
          ],
          canLaunchAnalysis: true,
          decisionLeaseUntil: DateTime(2026, 11, 8, 13),
        );
        await fiche(tester, enCours, etat: quota);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Lancer l\'analyse'), findsNothing);
        await deplier();
        expect(find.text(SectionLancements.vide), findsOneWidget);
        expect(find.text(invitation), findsNothing);
      },
    );

    testWidgets('section vide : invitation sans attendre l\'historique des '
        'décisions (T7)', (tester) async {
      const invitation =
          'Appuyez sur « Lancer l\'analyse », en bas de la fiche.';
      await fiche(tester, recu(), etat: quota, decisionsLues: false);
      await tester.pump(const Duration(seconds: 1));
      // La barre ne dépend plus de l'historique des décisions : le bouton
      // vient de `allowed_decisions` seul.
      expect(find.text('Lancer l\'analyse'), findsOneWidget);
      await tester.ensureVisible(find.text('Lancements (0)'));
      await tester.tap(find.text('Lancements (0)'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(SectionLancements.vide), findsOneWidget);
      expect(find.text(invitation), findsOneWidget);
    });

    testWidgets('plafond atteint et précisions en attente : deux lignes', (
      tester,
    ) async {
      await fiche(
        tester,
        recu(),
        etat: const DocumentTrouve(
          EtatLancements(day: '20261108', countDay: 10, perDay: 10),
        ),
        analyses: DocumentTrouve(
          TicketAnalysisDoc(
            analyses: [
              TicketAnalysis(
                kind: TicketAnalysisKind.reply,
                body: '## Précisions de l\'administrateur\n\nTexte.',
                createdAt: t1,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ButtonStyleButton>(bouton('Lancer l\'analyse')).onPressed,
        isNull,
      );
      expect(
        find.text(
          'Plafond atteint le 08/11 : 10 lancements sur 10. Le compteur '
          'repart à zéro peu après minuit.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Vos précisions du 08/11/26 à 11:50 seront lues par la prochaine '
          'analyse.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('hors ligne : bouton inactif, phrase commune', (tester) async {
      await fiche(tester, recu(), offline: true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ButtonStyleButton>(bouton('Lancer l\'analyse')).onPressed,
        isNull,
      );
      expect(find.text(kActionsHorsLigne), findsOneWidget);
      expect(find.byType(BoiteLancement), findsNothing);
    });

    testWidgets('hors ligne, historique absent du cache : phrase, sans barre', (
      tester,
    ) async {
      await fiche(
        tester,
        recu(canAnswer: false),
        offline: true,
        lancements: DocumentAbsentDuCache<TicketLaunchesDoc>(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lancer l\'analyse'), findsNothing);
      expect(find.text(kActionsHorsLigne), findsOneWidget);
      expect(find.text(SectionLancements.horsLigne), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('historique en lecture : progression à la place du bouton', (
      tester,
    ) async {
      await fiche(tester, recu(), lectureEnCours: true);
      await tester.pump();
      expect(find.text('Lancer l\'analyse'), findsNothing);
      expect(find.bySemanticsLabel('Lecture des lancements'), findsWidgets);
    });

    testWidgets('section : cartes, lien ouvert, lien invalide', (tester) async {
      final app = await fiche(
        tester,
        recu(),
        lancements: DocumentTrouve(
          TicketLaunchesDoc(
            entries: [
              TicketLaunch(
                action: ActionLancement.analyse,
                etat: EtatLancement.failed,
                at: t1,
                byUid: 'uid-autre',
                retryAfter: t1,
                reason: 'Routine en pause.',
              ),
              TicketLaunch(
                action: ActionLancement.analyse,
                etat: EtatLancement.launched,
                at: t0,
                byUid: 'uid-admin',
                retryAfter: t0,
                sessionUrl: 'https://claude.ai/code/session_1',
              ),
              TicketLaunch(
                action: ActionLancement.developpement,
                etat: EtatLancement.launched,
                at: DateTime(2026, 11, 7, 9),
                retryAfter: DateTime(2026, 11, 7, 9),
                sessionUrl: 'http://ailleurs.exemple.fr/x',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lancements (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Échec : Routine en pause.'), findsOneWidget);
      expect(
        find.text('le 08/11/26 à 11:50 par un autre administrateur'),
        findsOne,
      );
      expect(find.text('le 08/11/26 à 09:30 par vous'), findsOneWidget);
      expect(find.text(CarteLancement.sessionCreee), findsNWidgets(2));
      expect(find.text(CarteLancement.lienInvalide), findsOneWidget);
      expect(find.text(CarteLancement.visibilite), findsOneWidget);
      await tester.ensureVisible(find.text('Ouvrir la session'));
      await tester.tap(find.text('Ouvrir la session'));
      await tester.pumpAndSettle();
      expect(
        app.openedLinks.single,
        Uri.parse('https://claude.ai/code/session_1'),
      );
    });

    testWidgets('section : panne, Réessayer', (tester) async {
      final app = await fiche(tester, recu(), lectureEnCours: true);
      app.tickets.launchesOf('t1').addError(StateError('panne'));
      await tester.pump();
      await tester.pump();
      expect(find.text(SectionLancements.loadError), findsOneWidget);
      // Historique illisible : aucun bouton de lancement.
      expect(find.text('Lancer l\'analyse'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Réessayer'));
      await tester.pump();
      app.tickets.launchesOf('t1').add(const DocumentAbsent());
      await tester.pumpAndSettle();
      expect(find.text(SectionLancements.loadError), findsNothing);
      expect(find.text('Lancer l\'analyse'), findsOneWidget);
    });
    // Ticket #64 : « Valider et lancer le développement ».
    group('valider et lancer', () {
      Ticket analyse() => unTicket(
        status: TicketStatus.analyzed,
        issueNumber: 12,
        issueUrl: issueUrl,
        allowedDecisions: const [
          TicketDecisionAction.validate,
          TicketDecisionAction.refuse,
          TicketDecisionAction.close,
        ],
      );

      Ticket valideSurGithub() => unTicket(
        status: TicketStatus.validated,
        issueNumber: 12,
        issueUrl: issueUrl,
        allowedDecisions: const [
          TicketDecisionAction.validate,
          TicketDecisionAction.refuse,
          TicketDecisionAction.close,
        ],
      );

      Finder confirmer() =>
          find.widgetWithText(FilledButton, 'Valider et lancer');

      /// Ordre des appels au serveur simulé.
      List<String> journal(
        TestApp app, {
        Future<EchecReponse?> Function()? validation,
        Future<ResultatLancement> Function()? lancement,
      }) {
        final appels = <String>[];
        app.tickets.decideResult = () {
          appels.add('validateTicket');
          return validation == null ? Future.value() : validation();
        };
        app.tickets.launchResult = () {
          appels.add('launchTicketDevelopment');
          return lancement == null
              ? Future.value(const ResultatLancement(IssueLancement.lance))
              : lancement();
        };
        return appels;
      }

      testWidgets('analysé : Valider à contour, l\'action pleine en dernier', (
        tester,
      ) async {
        await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(OutlinedButton, 'Valider'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, kValiderEtLancer),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.text(kValiderEtLancer)).dy,
          greaterThan(tester.getTopLeft(find.text('Valider')).dy),
        );
      });

      testWidgets('reçu et validé dans l\'application : bouton absent', (
        tester,
      ) async {
        final app = await fiche(tester, recu(), etat: quota);
        await tester.pumpAndSettle();
        expect(find.text(kValiderEtLancer), findsNothing);
        app.tickets.publishAll([valide()]);
        await tester.pumpAndSettle();
        expect(find.text('Lancer le développement'), findsOneWidget);
        expect(find.text(kValiderEtLancer), findsNothing);
      });

      testWidgets('Valider seul : aucun lancement', (tester) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        final appels = journal(app);
        await tester.tap(find.text('Valider'));
        await tester.pumpAndSettle();
        expect(find.text('Valider ce ticket ?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Valider').last);
        await tester.pumpAndSettle();
        expect(appels, ['validateTicket']);
        expect(app.tickets.launches, isEmpty);
      });

      testWidgets('boîte : textes dans l\'ordre, Annuler sans appel', (
        tester,
      ) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        final appels = journal(app);
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        expect(find.text(BoiteLancement.titreValiderEtLancer), findsOneWidget);
        final textes = [
          kValiderConfirmation,
          BoiteLancement.effet(ActionLancement.developpement, 12),
          'Lancements restants le 08/11 : 7 sur 10.',
          BoiteLancement.cout,
        ];
        for (final t in textes) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        for (var i = 1; i < textes.length; i++) {
          expect(
            tester.getTopLeft(find.text(textes[i])).dy,
            greaterThan(tester.getTopLeft(find.text(textes[i - 1])).dy),
          );
        }
        expect(find.text(BoiteLancement.validerSansLancer), findsNothing);
        expect(find.text('Annuler'), findsOneWidget);
        expect(tester.widget<FilledButton>(confirmer()).onPressed, isNotNull);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(appels, isEmpty);
        expect(find.byType(BoiteLancement), findsNothing);
      });

      testWidgets('validé sur GitHub seul : phrase propre dans la boîte', (
        tester,
      ) async {
        await fiche(tester, valideSurGithub(), etat: quota);
        await tester.pumpAndSettle();
        expect(find.text('Valider'), findsOneWidget);
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        // Le lancement suit : la phrase de « Valider » seul, qui annonce
        // « Lancer le développement », n'a pas sa place ici.
        expect(
          find.text('La validation sera enregistrée dans l\'application.'),
          findsOneWidget,
        );
        expect(find.text(kValiderConfirmationGithub), findsNothing);
        expect(find.text(kValiderConfirmation), findsNothing);
      });

      testWidgets(
        'succès : validation puis lancement, une fois chacun, états',
        (tester) async {
          final app = await fiche(tester, analyse(), etat: quota);
          await tester.pumpAndSettle();
          final validation = Completer<EchecReponse?>();
          final lancement = Completer<ResultatLancement>();
          final appels = journal(
            app,
            validation: () => validation.future,
            lancement: () => lancement.future,
          );
          await tester.tap(find.text(kValiderEtLancer));
          await tester.pumpAndSettle();
          await tester.tap(confirmer());
          await tester.pump();
          expect(appels, ['validateTicket']);
          expect(find.text(BoiteLancement.validationEnCours), findsOneWidget);
          expect(find.text('Fermer'), findsOneWidget);
          // Double appui : bouton inactif, aucun second appel.
          await tester.tap(
            find.descendant(
              of: find.byType(BoiteLancement),
              matching: find.byType(FilledButton),
            ),
            warnIfMissed: false,
          );
          await tester.pump();
          expect(appels, ['validateTicket']);
          validation.complete(null);
          await tester.pump();
          await tester.pump();
          expect(appels, ['validateTicket', 'launchTicketDevelopment']);
          expect(find.text(BoiteLancement.envoiEnCours), findsOneWidget);
          expect(find.text(BoiteLancement.validationEnCours), findsNothing);
          lancement.complete(const ResultatLancement(IssueLancement.lance));
          await tester.pumpAndSettle();
          expect(find.byType(BoiteLancement), findsNothing);
          expect(
            find.text('Ticket #12 validé. Développement lancé.'),
            findsOneWidget,
          );
          expect(
            app.tickets.decisionsAppelees.single.action,
            TicketDecisionAction.validate,
          );
          expect(app.tickets.launches.single, (
            ticketId: 't1',
            action: ActionLancement.developpement,
          ));
        },
      );

      testWidgets('validation en échec : aucun lancement, message', (
        tester,
      ) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        const echec = EchecReponse(
          CauseEchecReponse.motif,
          motif: 'Cette décision n\'est plus possible pour ce statut.',
        );
        final appels = journal(app, validation: () async => echec);
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        await tester.tap(confirmer());
        await tester.pumpAndSettle();
        expect(appels, ['validateTicket']);
        expect(app.tickets.launches, isEmpty);
        expect(find.byType(BoiteLancement), findsNothing);
        expect(
          find.text(messageEchecDecision(TicketDecisionAction.validate, echec)),
          findsOneWidget,
        );
      });

      testWidgets('validation partielle : aucun lancement', (tester) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        const echec = EchecReponse(
          CauseEchecReponse.motif,
          motif: 'Étiquette posée, mais la décision n\'est pas terminée.',
          partiel: true,
        );
        final appels = journal(app, validation: () async => echec);
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        await tester.tap(confirmer());
        await tester.pumpAndSettle();
        expect(appels, ['validateTicket']);
        expect(app.tickets.launches, isEmpty);
      });

      testWidgets('lancement refusé : la validation faite et le motif', (
        tester,
      ) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        journal(
          app,
          lancement: () async => const ResultatLancement(
            IssueLancement.refuse,
            motif: 'Un développement est déjà en cours. Rien n\'a été lancé.',
          ),
        );
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        await tester.tap(confirmer());
        await tester.pumpAndSettle();
        expect(find.byType(BoiteLancement), findsNothing);
        expect(
          find.text(
            'Ticket #12 validé. Le développement n\'a pas été lancé : Un '
            'développement est déjà en cours. Rien n\'a été lancé.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('lancement refusé sans motif : phrase courte', (
        tester,
      ) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        journal(
          app,
          lancement: () async => const ResultatLancement(IssueLancement.refuse),
        );
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        await tester.tap(confirmer());
        await tester.pumpAndSettle();
        expect(
          find.text('Ticket #12 validé. Le développement n\'a pas été lancé.'),
          findsOneWidget,
        );
      });

      testWidgets('texte × 2 sur 360 px : barre sans débordement', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await fiche(tester, analyse(), etat: quota, width: 360, height: 700);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(bouton(kValiderEtLancer)).right,
          lessThanOrEqualTo(360),
        );
        expect(
          tester.getSize(bouton(kValiderEtLancer)).height,
          greaterThanOrEqualTo(48),
        );
      });

      testWidgets('lancement au résultat inconnu : compté, sans relance', (
        tester,
      ) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        journal(
          app,
          lancement: () async =>
              const ResultatLancement(IssueLancement.inconnu),
        );
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        await tester.tap(confirmer());
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Ticket #12 validé. Résultat du lancement inconnu, compté.',
          ),
          findsOneWidget,
        );
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).duration,
          kDureeMessageEchec,
        );
        expect(find.byType(SnackBarAction), findsNothing);
      });

      testWidgets('plafond atteint : Valider et lancer inactif, phrase', (
        tester,
      ) async {
        final app = await fiche(
          tester,
          analyse(),
          etat: const DocumentTrouve(
            EtatLancements(day: '20261108', countDay: 10, perDay: 10),
          ),
        );
        await tester.pumpAndSettle();
        final appels = journal(app);
        // Le bouton de la barre reste actif : la boîte dit pourquoi.
        expect(
          tester.widget<ButtonStyleButton>(bouton(kValiderEtLancer)).onPressed,
          isNotNull,
        );
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        expect(find.text(BoiteLancement.validerSansLancer), findsOneWidget);
        expect(tester.widget<FilledButton>(confirmer()).onPressed, isNull);
        await tester.tap(confirmer(), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(appels, isEmpty);
      });

      testWidgets('quota illisible : inconnu, bouton actif', (tester) async {
        final app = await fiche(tester, analyse());
        await tester.pumpAndSettle();
        journal(app);
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        expect(find.text('Lancements restants : inconnu.'), findsOneWidget);
        expect(find.text(BoiteLancement.validerSansLancer), findsNothing);
        expect(tester.widget<FilledButton>(confirmer()).onPressed, isNotNull);
      });

      testWidgets('boîte fermée pendant la validation : le lancement part', (
        tester,
      ) async {
        final app = await fiche(tester, analyse(), etat: quota);
        await tester.pumpAndSettle();
        final validation = Completer<EchecReponse?>();
        final appels = journal(app, validation: () => validation.future);
        await tester.tap(find.text(kValiderEtLancer));
        await tester.pumpAndSettle();
        await tester.tap(confirmer());
        await tester.pump();
        await tester.tap(find.text('Fermer'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BoiteLancement), findsNothing);
        // Validation en cours, boîte fermée : la barre dit pourquoi.
        expect(find.text('Validation en cours sur GitHub.'), findsOneWidget);
        expect(appels, ['validateTicket']);
        validation.complete(null);
        await tester.pumpAndSettle();
        expect(appels, ['validateTicket', 'launchTicketDevelopment']);
        expect(
          find.text('Ticket #12 validé. Développement lancé.'),
          findsOneWidget,
        );
      });

      testWidgets('hors ligne : deux boutons inactifs, phrase réseau', (
        tester,
      ) async {
        final app = await fiche(tester, analyse(), etat: quota, offline: true);
        await tester.pumpAndSettle();
        for (final label in ['Valider', kValiderEtLancer]) {
          expect(
            tester.widget<ButtonStyleButton>(bouton(label)).onPressed,
            isNull,
            reason: label,
          );
        }
        expect(find.text(kActionsHorsLigne), findsOneWidget);
        await tester.tap(find.text(kValiderEtLancer), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(BoiteLancement), findsNothing);
        expect(app.tickets.decisionsAppelees, isEmpty);
      });
    });
  });

  group('liste', () {
    Future<TestApp> liste(
      WidgetTester tester,
      List<Ticket> tickets, {
      RechercheDocument<EtatLancements>? etat,
    }) async {
      final app = TestApp();
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      if (etat != null) app.tickets.launchStatus.add(etat);
      app.tickets.publishAll(tickets);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('usage Claude : lien du bandeau, sans autre message', (
      tester,
    ) async {
      final app = await liste(tester, [recuSimple()]);
      expect(find.text(LienUsageClaude.libelle), findsOneWidget);
      await tester.tap(find.text(LienUsageClaude.libelle));
      await tester.pumpAndSettle();
      expect(
        app.openedLinks.single,
        Uri.parse('https://claude.ai/settings/usage'),
      );
      expect(app.tickets.launches, isEmpty);
    });

    testWidgets('compteur lu dans ticket_status/launches', (tester) async {
      await liste(
        tester,
        [recuSimple()],
        etat: const DocumentTrouve(
          EtatLancements(
            day: '20261108',
            countDay: 2,
            month: '202611',
            countMonth: 3,
            perDay: 10,
          ),
        ),
      );
      expect(
        find.text(
          'Lancements de sessions : 2 sur 10 le 08/11 · 3 en novembre 2026',
        ),
        findsOneWidget,
      );
    });

    testWidgets('compteur en panne : Réessayer', (tester) async {
      final app = TestApp();
      app.tickets.launchStatus.addError(StateError('refusé'));
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.publishAll([recuSimple()]);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      expect(find.text(CompteurLancements.indisponible), findsOneWidget);
      expect(find.byTooltip('Réessayer'), findsOneWidget);
    });

    testWidgets('pastilles : en cours, relance possible, rien sinon', (
      tester,
    ) async {
      final app = TestApp();
      app.tickets
          .launchesOf('a')
          .add(
            DocumentTrouve(
              TicketLaunchesDoc(
                entries: [
                  TicketLaunch(
                    action: ActionLancement.analyse,
                    etat: EtatLancement.launched,
                    at: t1,
                    retryAfter: t1.add(const Duration(hours: 1)),
                  ),
                ],
              ),
            ),
          );
      app.tickets
          .launchesOf('b')
          .add(
            DocumentTrouve(
              TicketLaunchesDoc(
                entries: [
                  TicketLaunch(
                    action: ActionLancement.developpement,
                    etat: EtatLancement.launched,
                    at: t0,
                    retryAfter: t0,
                  ),
                ],
              ),
            ),
          );
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.publishAll([
        unTicket(id: 'a', issueNumber: 1, canLaunchAnalysis: true),
        unTicket(
          id: 'b',
          title: 'Autre',
          status: TicketStatus.validated,
          issueNumber: 2,
          canLaunchDevelopment: true,
        ),
        unTicket(id: 'c', title: 'Troisième', issueNumber: 3),
      ]);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tous'));
      await tester.pumpAndSettle();
      expect(find.text('Analyse en cours'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label ==
                  'Analyse en cours '
                      'depuis 11:50',
        ),
        findsOneWidget,
      );
      expect(find.text('Relance possible'), findsOneWidget);
      // Ticket sans lancement permis : aucune lecture de son historique.
      expect(app.tickets.launchHistories.containsKey('c'), isFalse);
    });
  });
}

Ticket recuSimple() => unTicket(issueNumber: 12);
