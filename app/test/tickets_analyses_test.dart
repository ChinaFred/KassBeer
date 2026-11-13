import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_analysis.dart';
import 'package:kass_beer/features/tickets/presentation/admin_ticket_screen.dart';
import 'package:kass_beer/features/tickets/presentation/section_analyses.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_lien_github.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_statut.dart';

import 'support/fakes.dart';
import 'support/ticket_fixtures.dart';

/// Lot T3 d'ADR-008 : statut « Analysé », section « Analyses (N) »,
/// « Répondre ».
void main() {
  final t1 = DateTime(2026, 11, 8, 10, 2);
  final t2 = DateTime(2026, 11, 8, 11, 15);
  final t3 = DateTime(2026, 11, 8, 11, 40);

  TicketAnalysis entree(
    TicketAnalysisKind kind,
    String body, {
    DateTime? at,
    bool truncated = false,
  }) => TicketAnalysis(
    kind: kind,
    body: body,
    createdAt: at,
    truncated: truncated,
  );

  group('domaine', () {
    test('statut analysed et « answer » lu à part des décisions', () {
      final t = Ticket.fromFirestore('t1', {
        'type': 'bug',
        'title': 'Densité fausse',
        'description': 'La densité affichée est fausse.',
        'screen': '/recettes/:id',
        'status': 'analyzed',
        'allowed_decisions': ['validate', 'answer', 'inconnue'],
      });
      expect(t.status, TicketStatus.analyzed);
      expect(t.allowedDecisions, [TicketDecisionAction.validate]);
      expect(t.canAnswer, isTrue);
      expect(t.toProcess, isTrue);
      final sans = Ticket.fromFirestore('t2', {
        'type': 'bug',
        'title': 'Densité fausse',
        'description': 'La densité affichée est fausse.',
        'screen': '/recettes/:id',
        'status': 'received',
      });
      expect(sans.canAnswer, isFalse);
      // « answer » n'est jamais une décision de `decisions/`.
      expect(TicketDecisionAction.fromStored(kAnswerDecision), isNull);
    });

    test('Analysé : pastille, phrase du membre', () {
      final s = statutAfficheDe(TicketStatus.analyzed);
      expect(s.label, 'Analysé');
      expect(s.icon, Icons.manage_search);
      expect(s.ton, statutAfficheDe(TicketStatus.received).ton);
      expect(
        phrasesStatut(unTicket(status: TicketStatus.analyzed), DateTime(2026)),
        ['Votre ticket a été lu et étudié.'],
      );
    });

    test('document : entrées, nature inconnue écartée, compteurs', () {
      final doc = TicketAnalysisDoc.fromFirestore({
        'analyses': [
          {
            'comment_id': 101,
            'kind': 'analysis',
            'body': '## Analyse\n\nTexte',
            'created_at': Timestamp.fromDate(t1),
            'updated_at': Timestamp.fromDate(t1),
            'truncated': false,
          },
          {
            'comment_id': 102,
            'kind': 'reply',
            'body': '## Précisions de l\'administrateur\n\nOui.',
            'created_at': Timestamp.fromDate(t2),
          },
          {'kind': 'futur', 'body': 'x'},
          {
            'comment_id': 103,
            'kind': 'unverified_reply',
            'body': '## Précisions\n\nAutre.',
            'created_at': Timestamp.fromDate(t3),
            'truncated': true,
          },
        ],
        'checked_at': Timestamp.fromDate(t3),
        'skipped_count': 2,
      });
      expect(doc.analyses.map((a) => a.kind), [
        TicketAnalysisKind.analysis,
        TicketAnalysisKind.reply,
        TicketAnalysisKind.unverifiedReply,
      ]);
      expect(doc.analyses.last.truncated, isTrue);
      expect(doc.analysisCount, 1);
      expect(doc.skippedCount, 2);
      expect(doc.lastAnalysisAt, t1);
      // Réponse après la dernière analyse : la prochaine analyse la lira.
      expect(doc.pendingAnswerAt, t2);
    });

    test('document : réponse avant la dernière analyse, déjà lue', () {
      final doc = TicketAnalysisDoc(
        analyses: [
          entree(TicketAnalysisKind.reply, 'r', at: t1),
          entree(TicketAnalysisKind.analysis, 'a', at: t2),
        ],
      );
      expect(doc.pendingAnswerAt, isNull);
    });

    test('document mal typé : illisible, sans valeur reçue', () {
      expect(
        () => TicketAnalysisDoc.fromFirestore({'analyses': 'texte'}),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(
        () => TicketAnalysisDoc.fromFirestore({
          'analyses': [
            {'kind': 'analysis', 'body': 12},
          ],
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('corps sans ligne de titre', () {
      expect(corpsAffiche('## Analyse du ticket\n\nTexte'), 'Texte');
      expect(
        corpsAffiche('  ## Précisions de l\'administrateur\r\nOui'),
        'Oui',
      );
      expect(corpsAffiche('## Analyse'), '');
      expect(corpsAffiche('Texte libre'), 'Texte libre');
    });

    test('liens : http et https avec hôte seuls', () {
      expect(lienAnalyseOuvrable('https://github.com/x'), isNotNull);
      expect(lienAnalyseOuvrable('http://exemple.fr/a'), isNotNull);
      for (final href in [
        null,
        'javascript:alert(1)',
        'intent://x#Intent;end',
        'mailto:a@exemple.fr',
        'file:///etc/passwd',
        '/relatif',
        'https:///sans-hote',
        'data:text/html,x',
      ]) {
        expect(lienAnalyseOuvrable(href), isNull, reason: '$href');
      }
    });

    test('image : texte alternatif à la place', () {
      expect(imageNonAffichee(null), '[Image non affichée]');
      expect(imageNonAffichee('  '), '[Image non affichée]');
      expect(imageNonAffichee('capture'), '[Image non affichée : capture]');
    });

    test('section vide : pas encore analysé ou pas encore relevée', () {
      expect(
        vueAnalysesVide(status: TicketStatus.received, documentExiste: false),
        VueAnalysesVide.pasEncoreAnalyse,
      );
      expect(
        vueAnalysesVide(status: TicketStatus.analyzed, documentExiste: false),
        VueAnalysesVide.pasEncoreRelevee,
      );
      expect(
        vueAnalysesVide(status: TicketStatus.analyzed, documentExiste: true),
        VueAnalysesVide.pasEncoreAnalyse,
      );
    });

    test('échec de Répondre : cause, motif, champ, partiel', () {
      expect(
        EchecReponse.depuis(code: 'unavailable').cause,
        CauseEchecReponse.reseau,
      );
      // GitHub indisponible : le serveur donne son motif.
      final github = EchecReponse.depuis(
        code: 'unavailable',
        details: {
          'reason': 'GitHub ne répond pas.',
          'code': 'github_unavailable',
        },
      );
      expect(github.cause, CauseEchecReponse.motif);
      expect(github.codeServeur, 'github_unavailable');
      expect(
        EchecReponse.depuis(code: 'deadline-exceeded').cause,
        CauseEchecReponse.delai,
      );
      expect(
        EchecReponse.depuis(code: 'permission-denied').cause,
        CauseEchecReponse.acces,
      );
      expect(
        EchecReponse.depuis(code: 'unauthenticated').cause,
        CauseEchecReponse.acces,
      );
      final champ = EchecReponse.depuis(
        code: 'invalid-argument',
        details: {'field': 'answer', 'reason': 'Texte trop long.'},
      );
      expect(champ.cause, CauseEchecReponse.motif);
      expect(champ.surLeChamp, isTrue);
      expect(champ.motif, 'Texte trop long.');
      final partiel = EchecReponse.depuis(
        code: 'internal',
        details: {'reason': 'Statut non mis à jour.', 'partial': true},
      );
      expect(partiel.partiel, isTrue);
      expect(partiel.surLeChamp, isFalse);
      expect(
        EchecReponse.depuis(code: 'internal', details: 'texte').cause,
        CauseEchecReponse.autre,
      );
      expect(
        messageEchecReponse(champ),
        'Réponse non publiée : Texte trop long. Votre texte est gardé.',
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

    test('lecture de admin/analysis : absent, trouvé, illisible', () async {
      final repository = depot();
      expect(
        await repository.watchAnalysis('t1').first,
        isA<DocumentAbsent<TicketAnalysisDoc>>(),
      );
      final ref = firestore.doc('tickets/t1/admin/analysis');
      await ref.set({
        'analyses': [
          {
            'kind': 'analysis',
            'body': '## Analyse\n\nTexte',
            'created_at': Timestamp.fromDate(t1),
          },
        ],
        'skipped_count': 0,
      });
      final trouve = await repository.watchAnalysis('t1').first;
      expect(
        (trouve as DocumentTrouve<TicketAnalysisDoc>).value.analysisCount,
        1,
      );
      await ref.set({'analyses': 'texte'});
      expect(
        await repository.watchAnalysis('t1').first,
        isA<DocumentIllisibleTrouve<TicketAnalysisDoc>>(),
      );
      expect(errors.reports.single.feature, 'tickets.read_analysis');
    });

    test('Répondre : nom, données, succès', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repository = depot(
        callable: (name, data) async {
          calls.add((name, data));
          return {'status': 'received'};
        },
      );
      expect(
        await repository.answer(ticketId: 't1', answer: 'Précision.'),
        isNull,
      );
      expect(calls.single.$1, 'answerTicketAnalysis');
      expect(calls.single.$2, {'ticketId': 't1', 'answer': 'Précision.'});
      expect(errors.reports, isEmpty);
    });

    test('Répondre refusé : échec rendu, rapporté sans le texte', () async {
      final repository = depot(
        callable: (name, data) async => throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Ce ticket ne permet pas de répondre.',
          details: {
            'reason': 'Ce ticket ne permet pas de répondre.',
            'code': 'not_answerable',
          },
        ),
      );
      final echec = await repository.answer(
        ticketId: 't1',
        answer: 'Texte secret de la réponse',
      );
      expect(echec!.cause, CauseEchecReponse.motif);
      expect(echec.motif, 'Ce ticket ne permet pas de répondre.');
      final report = errors.reports.single;
      expect(report.feature, 'tickets.answer');
      expect(report.context, contains('code=failed-precondition'));
      expect(report.context, contains('reason_code=not_answerable'));
      expect(report.context, isNot(contains('secret')));
      expect('${report.error}', isNot(contains('secret')));
    });

    test('Répondre : erreur inattendue rapportée, cause « autre »', () async {
      final repository = depot(
        callable: (name, data) async => throw StateError('panne'),
      );
      final echec = await repository.answer(ticketId: 't1', answer: 'Texte.');
      expect(echec!.cause, CauseEchecReponse.autre);
      expect(errors.reports.single.feature, 'tickets.answer');
    });
  });

  group('fiche', () {
    const issueUrl = 'https://github.com/ChinaFred/KassBeer/issues/12';

    Future<TestApp> fiche(
      WidgetTester tester,
      Ticket ticket, {
      RechercheDocument<TicketAnalysisDoc>? analyses,
      double width = 400,
      double height = 2000,
      bool offline = false,
    }) async {
      final app = TestApp();
      await app.pump(tester, width: width, height: height);
      app.signIn(adminUser, member: adminMember, fromCache: offline);
      await tester.pumpAndSettle();
      app.tickets.publishAll([ticket]);
      app.tickets.publishDecisions(ticket.id, const []);
      if (analyses != null) app.tickets.analysesOf(ticket.id).add(analyses);
      app.container.read(routerProvider).go(AppRoutes.adminTicket(ticket.id));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return app;
    }

    Ticket analyse0({
      TicketStatus status = TicketStatus.analyzed,
      bool canAnswer = true,
      List<TicketDecisionAction> allowed = const [
        TicketDecisionAction.refuse,
        TicketDecisionAction.close,
        TicketDecisionAction.validate,
      ],
    }) => unTicket(
      status: status,
      issueNumber: 12,
      issueUrl: issueUrl,
      allowedDecisions: allowed,
      canAnswer: canAnswer,
    );

    final docComplet = DocumentTrouve(
      TicketAnalysisDoc(
        analyses: [
          entree(
            TicketAnalysisKind.analysis,
            '## Analyse du ticket\n\nVoir [le dépôt](https://github.com/x) et '
            '[ceci](javascript:alert(1)).\n\n![capture](https://exemple.fr/i.png)',
            at: t1,
          ),
          entree(
            TicketAnalysisKind.reply,
            '## Précisions de l\'administrateur\n\nOui, sur Android.',
            at: t2,
          ),
          entree(
            TicketAnalysisKind.unverifiedReply,
            '## Précisions\n\nTexte d\'une session.',
            at: t3,
            truncated: true,
          ),
        ],
        skippedCount: 1,
      ),
    );

    /// Appuie sur le lien [texte] d'un corps Markdown.
    void toucherLien(WidgetTester tester, String texte) {
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        GestureRecognizer? found;
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == texte) {
            found = span.recognizer;
            return false;
          }
          return true;
        });
        if (found case final TapGestureRecognizer r) {
          r.onTap!();
          return;
        }
      }
      fail('lien « $texte » introuvable');
    }

    testWidgets('sans Issue : aucune section, aucune lecture', (tester) async {
      final app = await fiche(tester, unTicket(allowedDecisions: const []));
      expect(find.text('Analyses'), findsNothing);
      expect(app.tickets.analysesOf('t1').subscriptions, 0);
    });

    testWidgets('chargement, panne et Réessayer', (tester) async {
      final app = await fiche(tester, analyse0());
      expect(find.text('Analyses'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is LinearProgressIndicator &&
              w.semanticsLabel == 'Lecture des analyses',
        ),
        findsOneWidget,
      );
      app.tickets.analysesOf('t1').addError(StateError('panne'));
      await tester.pump();
      await tester.pump();
      expect(find.text(SectionAnalyses.loadError), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Réessayer'));
      await tester.pump();
      app.tickets
          .analysesOf('t1')
          .add(const DocumentAbsent<TicketAnalysisDoc>());
      await tester.pumpAndSettle();
      expect(find.text(SectionAnalyses.loadError), findsNothing);
      expect(find.text(SectionAnalyses.pasEncoreRelevee), findsOneWidget);
    });

    testWidgets('panne après « absent du cache » : panne et Réessayer', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        analyse0(),
        analyses: const DocumentAbsentDuCache(),
      );
      final lecture = find.byWidgetPredicate(
        (w) =>
            w is LinearProgressIndicator &&
            w.semanticsLabel == 'Lecture des analyses',
      );
      // En ligne, le cache vide attend le serveur.
      expect(lecture, findsOneWidget);
      app.tickets.analysesOf('t1').addError(StateError('panne'));
      await tester.pump();
      await tester.pump();
      expect(find.text(SectionAnalyses.loadError), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Réessayer'), findsOneWidget);
      expect(lecture, findsNothing);
    });

    testWidgets('panne après un document trouvé : les cartes restent', (
      tester,
    ) async {
      final app = await fiche(tester, analyse0(), analyses: docComplet);
      await tester.pumpAndSettle();
      app.tickets.analysesOf('t1').addError(StateError('panne'));
      await tester.pumpAndSettle();
      expect(find.text('Analyse du 08/11/26 à 10:02'), findsOneWidget);
      expect(find.text(SectionAnalyses.loadError), findsNothing);
    });

    testWidgets('panne après un document sans entrée : panne et Réessayer', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        analyse0(),
        analyses: const DocumentTrouve(TicketAnalysisDoc(analyses: [])),
      );
      await tester.pumpAndSettle();
      expect(find.text(SectionAnalyses.pasEncoreAnalyse), findsOneWidget);
      app.tickets.analysesOf('t1').addError(StateError('panne'));
      await tester.pumpAndSettle();
      expect(find.text(SectionAnalyses.loadError), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Réessayer'), findsOneWidget);
      expect(find.text(SectionAnalyses.pasEncoreAnalyse), findsNothing);
    });

    testWidgets('vide : reçu, hors ligne', (tester) async {
      await fiche(
        tester,
        analyse0(status: TicketStatus.received),
        analyses: const DocumentAbsent(),
      );
      expect(find.text(SectionAnalyses.pasEncoreAnalyse), findsOneWidget);
    });

    testWidgets('hors ligne, absent du cache : le dit', (tester) async {
      await fiche(
        tester,
        analyse0(),
        analyses: const DocumentAbsentDuCache(),
        offline: true,
      );
      expect(find.text(SectionAnalyses.horsLigne), findsOneWidget);
      expect(find.text(SectionAnalyses.pasEncoreAnalyse), findsNothing);
    });

    testWidgets('cartes : titres, corps sans titre, image remplacée', (
      tester,
    ) async {
      await fiche(tester, analyse0(), analyses: docComplet);
      await tester.pumpAndSettle();
      // N compte les analyses seules.
      expect(find.text('Analyses (1)'), findsOneWidget);
      expect(find.text('Analyse du 08/11/26 à 10:02'), findsOneWidget);
      expect(find.text('Votre réponse du 08/11/26 à 11:15'), findsOneWidget);
      expect(find.text('Précisions du 08/11/26 à 11:40'), findsOneWidget);
      expect(find.text('Non publiée depuis l\'application.'), findsOneWidget);
      expect(find.textContaining('Analyse du ticket'), findsNothing);
      expect(find.text('[Image non affichée : capture]'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Précisions tronquées, voir GitHub.'), findsOneWidget);
      expect(find.text('Réponse tronquée, voir GitHub.'), findsNothing);
      expect(find.text(SectionAnalyses.plusDeDix), findsOneWidget);
      // Un bouton sous la carte tronquée, un sous « Seules les 10… ».
      final issue = find.descendant(
        of: find.byType(SectionAnalyses),
        matching: find.widgetWithText(
          BoutonVoirSurGithub,
          'Ouvrir l\'Issue #12',
        ),
      );
      expect(issue, findsNWidgets(2));
      expect(
        tester.getTopLeft(issue.last).dy,
        greaterThan(tester.getTopLeft(find.text(SectionAnalyses.plusDeDix)).dy),
      );
      // Ordre chronologique.
      expect(
        tester.getTopLeft(find.text('Analyse du 08/11/26 à 10:02')).dy,
        lessThan(
          tester.getTopLeft(find.text('Votre réponse du 08/11/26 à 11:15')).dy,
        ),
      );
    });

    testWidgets('liens : https ouvert, javascript ignoré, échec rapporté', (
      tester,
    ) async {
      final app = await fiche(tester, analyse0(), analyses: docComplet);
      await tester.pumpAndSettle();
      toucherLien(tester, 'ceci');
      await tester.pumpAndSettle();
      expect(app.openedLinks, isEmpty);
      toucherLien(tester, 'le dépôt');
      await tester.pumpAndSettle();
      expect(app.openedLinks.single, Uri.parse('https://github.com/x'));
      app.openLinkResult = false;
      toucherLien(tester, 'le dépôt');
      await tester.pumpAndSettle();
      expect(find.text(CorpsAnalyse.lienImpossible), findsOneWidget);
      final report = app.errors.reports.last;
      expect(report.feature, 'tickets.open_analysis_link');
      expect(report.context, isNot(contains('github.com')));
    });

    testWidgets('lien exposé aux lecteurs d\'écran comme lien activable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await fiche(tester, analyse0(), analyses: docComplet);
      await tester.pumpAndSettle();
      expect(
        find.semantics.byPredicate(
          (node) =>
              node.label == 'le dépôt' &&
              node.flagsCollection.isLink &&
              node.getSemanticsData().hasAction(SemanticsAction.tap),
        ),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('Répondre : ordre, absent sans « answer »', (tester) async {
      final app = await fiche(
        tester,
        analyse0(),
        analyses: docComplet,
        width: 700,
      );
      await tester.pumpAndSettle();
      // Ordre des boutons dans la barre, quelle que soit la largeur.
      final barre = tester.widget<OverflowBar>(
        find.ancestor(
          of: find.text('Répondre'),
          matching: find.byType(OverflowBar),
        ),
      );
      expect(
        [
          for (final b in barre.children)
            find
                .descendant(of: find.byWidget(b), matching: find.byType(Text))
                .evaluate()
                .map((e) => (e.widget as Text).data)
                .single,
        ],
        ['Refuser', 'Répondre', 'Clore', 'Valider'],
      );
      // Le client ne déduit rien du statut (P26).
      app.tickets.publishAll([analyse0(canAnswer: false)]);
      await tester.pumpAndSettle();
      expect(find.text('Répondre'), findsNothing);
      // « answer » seul : la barre existe.
      app.tickets.publishAll([analyse0(allowed: const [])]);
      await tester.pumpAndSettle();
      expect(find.text('Répondre'), findsOneWidget);
    });

    testWidgets('hors ligne : Répondre inactif, phrase', (tester) async {
      await fiche(tester, analyse0(), analyses: docComplet, offline: true);
      await tester.pumpAndSettle();
      final bouton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Répondre'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
      );
      expect(bouton.onPressed, isNull);
      expect(find.text(kRepondreHorsLigne), findsOneWidget);
    });

    testWidgets('reçu : précisions en attente annoncées', (tester) async {
      await fiche(
        tester,
        analyse0(status: TicketStatus.received),
        analyses: DocumentTrouve(
          TicketAnalysisDoc(
            analyses: [
              entree(TicketAnalysisKind.analysis, 'a', at: t1),
              entree(TicketAnalysisKind.reply, 'r', at: t2),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Vos précisions du 08/11/26 à 11:15 seront lues par la prochaine '
          'analyse.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('boîte : textes, trop court, publication réussie', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        analyse0(status: TicketStatus.validated),
        analyses: docComplet,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      expect(find.text('Répondre à l\'analyse'), findsOneWidget);
      expect(find.text(FormulaireReponse.publicWarning), findsOneWidget);
      expect(find.text('La validation sera retirée.'), findsOneWidget);
      expect(find.text('0/4000'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), ' abc ');
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();
      expect(find.text(FormulaireReponse.tropCourt), findsOneWidget);
      expect(app.tickets.answers, isEmpty);

      final server = Completer<EchecReponse?>();
      app.tickets.answerResult = () => server.future;
      await tester.enterText(find.byType(TextFormField), '  Sur Android.  ');
      await tester.tap(find.text('Publier'));
      await tester.pump();
      expect(app.tickets.answers.single, (
        ticketId: 't1',
        answer: 'Sur Android.',
      ));
      expect(find.text(FormulaireReponse.enCours), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
      expect(find.bySemanticsLabel('Publication en cours'), findsOneWidget);
      server.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(FormulaireReponse), findsNothing);
      expect(
        find.text('Réponse publiée. Le ticket repasse à Reçu.'),
        findsOneWidget,
      );
      // Brouillon effacé après la publication.
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      expect(find.text('Sur Android.'), findsNothing);
    });

    testWidgets('boîte fermée pendant l\'envoi : échec en message', (
      tester,
    ) async {
      final app = await fiche(tester, analyse0(), analyses: docComplet);
      await tester.pumpAndSettle();
      final server = Completer<EchecReponse?>();
      app.tickets.answerResult = () => server.future;
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Sur Android.');
      await tester.tap(find.text('Publier'));
      await tester.pump();
      await tester.tap(find.text('Fermer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Bouton masqué pendant la publication.
      expect(find.text('Répondre'), findsNothing);
      expect(find.text(kPublicationReponseEnCours), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is LinearProgressIndicator &&
              w.semanticsLabel == 'Publication en cours',
        ),
        findsOneWidget,
      );
      server.complete(const EchecReponse(CauseEchecReponse.reseau));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Réponse non publiée : pas de réseau. Votre texte est gardé.',
        ),
        findsOneWidget,
      );
      // Le texte est gardé.
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      expect(find.text('Sur Android.'), findsOneWidget);
    });

    testWidgets('boîte : motif sur le champ, échec partiel figé', (
      tester,
    ) async {
      final app = await fiche(tester, analyse0(), analyses: docComplet);
      await tester.pumpAndSettle();
      app.tickets.answerResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        motif: 'Texte vide après nettoyage.',
        champ: 'answer',
      );
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '@@@@@@');
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();
      expect(find.text('Texte vide après nettoyage.'), findsOneWidget);
      expect(find.byType(FormulaireReponse), findsOneWidget);

      app.tickets.answerResult = () async => const EchecReponse(
        CauseEchecReponse.motif,
        motif: 'Statut non remis à Reçu.',
        partiel: true,
      );
      await tester.enterText(find.byType(TextFormField), 'Sur Android.');
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();
      expect(find.text(FormulaireReponse.dejaPubliee), findsOneWidget);
      expect(find.textContaining('Réponse non publiée'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isTrue);
    });

    testWidgets('publication : sa ligne passe avant une décision écartée', (
      tester,
    ) async {
      final app = await fiche(tester, analyse0(), analyses: docComplet);
      app.tickets.publishDecisions('t1', [
        uneDecision(
          state: TicketDecisionState.rejected,
          errorReason: 'Cette décision n\'est plus possible pour ce statut.',
        ),
      ]);
      await tester.pumpAndSettle();
      const rejet = 'Cette décision n\'est plus possible pour ce statut.';
      expect(find.text(rejet), findsOneWidget);
      final server = Completer<EchecReponse?>();
      app.tickets.answerResult = () => server.future;
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Sur Android.');
      await tester.tap(find.text('Publier'));
      await tester.pump();
      await tester.tap(find.text('Fermer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(kPublicationReponseEnCours), findsOneWidget);
      expect(find.text(rejet), findsNothing);
      server.complete(null);
      await tester.pumpAndSettle();
      expect(find.text(rejet), findsOneWidget);
    });

    testWidgets('publication : sa ligne passe avant une décision en échec', (
      tester,
    ) async {
      final app = await fiche(tester, analyse0(), analyses: docComplet);
      app.tickets.publishDecisions('t1', [
        uneDecision(
          state: TicketDecisionState.failed,
          errorReason: 'GitHub indisponible.',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('n\'a pas abouti'), findsOneWidget);
      final server = Completer<EchecReponse?>();
      app.tickets.answerResult = () => server.future;
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Sur Android.');
      await tester.tap(find.text('Publier'));
      await tester.pump();
      await tester.tap(find.text('Fermer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(kPublicationReponseEnCours), findsOneWidget);
      expect(find.textContaining('n\'a pas abouti'), findsNothing);
      server.complete(null);
      await tester.pumpAndSettle();
      expect(find.textContaining('n\'a pas abouti'), findsOneWidget);
    });

    testWidgets('boîte : compteur et limite en points de code', (tester) async {
      final app = await fiche(tester, analyse0(), analyses: docComplet);
      await tester.pumpAndSettle();
      app.tickets.answerResult = () async => null;
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      // 2 600 émojis : 5 200 unités UTF-16, 2 600 points de code.
      final emojis = List.filled(2600, '\u{1F37A}').join();
      await tester.enterText(find.byType(TextFormField), emojis);
      await tester.pump();
      expect(find.text('2600/4000'), findsOneWidget);
      expect(find.bySemanticsLabel('1400 caractères restants'), findsOneWidget);
      // La saisie n'est pas coupée.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        emojis,
      );
      // Espaces de bord non comptés, comme au validateur.
      await tester.enterText(find.byType(TextFormField), '  abcdef  ');
      await tester.pump();
      expect(find.text('6/4000'), findsOneWidget);
      final trop = 'a' * 4001;
      await tester.enterText(find.byType(TextFormField), trop);
      await tester.pump();
      expect(find.text('4001/4000'), findsOneWidget);
      expect(find.bySemanticsLabel('1 caractère en trop'), findsOneWidget);
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();
      expect(find.text(FormulaireReponse.tropLong), findsOneWidget);
      expect(app.tickets.answers, isEmpty);
      await tester.enterText(find.byType(TextFormField), emojis);
      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();
      expect(app.tickets.answers.single.answer, emojis);
    });

    testWidgets('tableau large sur 360 px, texte × 2 : défilement horizontal', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final colonnes = [for (var i = 1; i <= 8; i++) 'Colonne$i'];
      final tableau =
          '## Analyse\n\n| ${colonnes.join(' | ')} |\n'
          '|${List.filled(colonnes.length, '---').join('|')}|\n'
          '| ${List.filled(colonnes.length, 'valeur_longue').join(' | ')} |';
      await fiche(
        tester,
        analyse0(),
        analyses: DocumentTrouve(
          TicketAnalysisDoc(
            analyses: [entree(TicketAnalysisKind.analysis, tableau, at: t1)],
          ),
        ),
        width: 360,
        height: 700,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final defilement = find.ancestor(
        of: find.byType(Table),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(defilement, findsOneWidget);
      // Le tableau dépasse la largeur visible : il défile.
      expect(
        tester.getSize(find.byType(Table)).width,
        greaterThan(tester.getSize(defilement).width),
      );
    });

    testWidgets('texte × 2 sur 360 px : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await fiche(
        tester,
        analyse0(),
        analyses: docComplet,
        width: 360,
        height: 700,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Répondre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Répondre'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
