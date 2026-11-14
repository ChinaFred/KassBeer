import 'package:cloud_firestore/cloud_firestore.dart';
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

/// Lot T5 d'ADR-008 : livraison et reprise du développement, côté client
/// (P39, P45, P46). Le client lit `admin/delivery`, `admin/launches` et
/// `ticket_status/launches` sans recopier de règle du serveur.
void main() {
  // Heure de l'horloge de [TestApp] : 08/11/26 à 12:10.
  final now = DateTime(2026, 11, 8, 12, 10);
  final t0 = DateTime(2026, 11, 8, 9, 30);
  const prUrl = 'https://github.com/ChinaFred/KassBeer/pull/34';

  Ticket enCours({
    String id = 't1',
    bool parApplication = true,
    DateTime? statusChangedAt,
  }) => unTicket(
    id: id,
    status: TicketStatus.inProgress,
    issueNumber: 12,
    issueUrl: 'https://github.com/ChinaFred/KassBeer/issues/12',
    statusChangedAt: statusChangedAt,
    allowedDecisions: const [
      TicketDecisionAction.refuse,
      TicketDecisionAction.close,
    ],
    canLaunchDelivery: parApplication,
    canRelaunchDevelopment: parApplication,
  );

  const prete = TicketDelivery(
    eligiblePrCount: 1,
    prNumber: 34,
    prUrl: prUrl,
    ciStatus: 'completed',
    ciConclusion: 'success',
    ready: true,
  );
  const rouge = TicketDelivery(
    eligiblePrCount: 1,
    prNumber: 34,
    prUrl: prUrl,
    ciStatus: 'completed',
    ciConclusion: 'failure',
    relaunchReady: true,
  );
  const quota = EtatLancements(day: '20261108', countDay: 3, perDay: 10);
  const historiqueVide = TicketLaunchesDoc(entries: []);

  TicketLaunchesDoc historique(
    ActionLancement action, {
    required DateTime at,
    required DateTime retryAfter,
    EtatLancement etat = EtatLancement.launched,
    String? endedBy,
  }) => TicketLaunchesDoc(
    entries: [
      TicketLaunch(
        action: action,
        etat: etat,
        at: at,
        retryAfter: retryAfter,
        endedBy: endedBy,
      ),
    ],
  );

  LigneLivraison? ligne(
    Ticket ticket, {
    RechercheDocument<TicketDelivery>? livraison = const DocumentTrouve(prete),
    bool panne = false,
    TicketLaunchesDoc? lancements = historiqueVide,
    EtatLancements? etat = quota,
    bool offline = false,
    bool appel = false,
  }) => ligneLivraison(
    ticket: ticket,
    livraison: livraison,
    livraisonEnPanne: panne,
    historique: lancements,
    quota: etat,
    now: now,
    offline: offline,
    appelEnCours: appel,
  );

  group('domaine', () {
    test('admin/delivery lu champ par champ, compte rendu inconnu écarté', () {
      final d = TicketDelivery.fromFirestore({
        'eligible_pr_count': 1,
        'pr_number': 34,
        'pr_url': prUrl,
        'head_sha': 'a' * 40,
        'ci_status': 'completed',
        'ci_conclusion': 'success',
        'ci_completed_at': Timestamp.fromDate(t0),
        'ready': true,
        'relaunch_ready': false,
        'reports': [
          {
            'kind': 'blocked',
            'body': '## Livraison — blocage\n\nL7.',
            'created_at': Timestamp.fromDate(t0),
            'truncated': false,
          },
          {'kind': 'futur', 'body': 'x'},
        ],
      });
      expect(d.ready, isTrue);
      expect(d.prNumber, 34);
      expect(d.reports, hasLength(1));
      expect(d.reports.single.createdAt, t0);
      expect(
        () => TicketDelivery.fromFirestore({'ready': 'oui'}),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(corpsCompteRendu('## Livraison — blocage\n\nL7.'), 'L7.');
    });

    test('verrou des livraisons lu dans ticket_status/launches', () {
      final e = EtatLancements.fromFirestore({
        'delivery_running': {
          'ticket_id': 't9',
          'issue_number': 9,
          'launched_at': Timestamp.fromDate(t0),
          'retry_after': Timestamp.fromDate(t0.add(const Duration(hours: 3))),
        },
      });
      expect(e.deliveryRunning?.ticketId, 't9');
      expect(e.deliveryRunning?.tient(now), isTrue);
      expect(
        EtatLancements.fromFirestore({
          'delivery_running': null,
        }).deliveryRunning,
        isNull,
      );
    });

    test('Livrer et Relancer lus dans allowed_decisions', () {
      final t = Ticket.fromFirestore('t1', {
        'type': 'bug',
        'title': 'Densité fausse',
        'description': 'La densité affichée est fausse.',
        'screen': '/recettes/:id',
        'status': 'in_progress',
        'allowed_decisions': [
          'refuse',
          'close',
          'launch_delivery',
          'relaunch_development',
        ],
      });
      expect(t.canLaunch(ActionLancement.livraison), isTrue);
      expect(t.canLaunch(ActionLancement.reprise), isTrue);
      expect(t.allowedDecisions, [
        TicketDecisionAction.refuse,
        TicketDecisionAction.close,
      ]);
      expect(ActionLancement.reprise.callable, 'launchTicketDevelopment');
      expect(ActionLancement.reprise.arguments, {'mode': 'resume'});
      expect(ActionLancement.livraison.callable, 'launchTicketDelivery');
      expect(ActionLancement.livraison.arguments, isEmpty);
    });

    test('adresse d\'une PR : ce dépôt, https, numéro seul', () {
      expect(lienPullRequestOuvrable(prUrl), isNotNull);
      for (final url in [
        'http://github.com/ChinaFred/KassBeer/pull/34',
        'https://github.com/Autre/KassBeer/pull/34',
        'https://github.com/ChinaFred/KassBeer/issues/34',
        'https://github.com/ChinaFred/KassBeer/pull/34/files',
        'https://github.com/ChinaFred/KassBeer/pull/0',
        'https://github.com/ChinaFred/KassBeer/pull/34?x=1',
        'https://x@github.com/ChinaFred/KassBeer/pull/34',
        'https://github.com.evil.example/ChinaFred/KassBeer/pull/34',
        'javascript:alert(1)',
      ]) {
        expect(lienPullRequestOuvrable(url), isNull, reason: url);
      }
    });
  });

  group('ligne de la barre', () {
    test('PR prête : Livrer actif ; hors ligne ou plafond : inactif', () {
      final l = ligne(enCours())!;
      expect(l.action, ActionLancement.livraison);
      expect(l.actif, isTrue);
      expect(l.ton, TonLivraison.prete);
      expect(l.texte, 'PR #34 prête : CI verte.');
      expect(ligne(enCours(), offline: true)!.actif, isFalse);
      final plafond = ligne(
        enCours(),
        etat: const EtatLancements(day: '20261108', countDay: 10, perDay: 10),
      )!;
      expect(plafond.actif, isFalse);
      expect(plafond.ton, TonLivraison.plafond);
    });

    test('livraison de ce ticket en cours : aucun bouton, Refuser et Clore '
        'masqués', () {
      final l = ligne(
        enCours(),
        lancements: historique(
          ActionLancement.livraison,
          at: DateTime(2026, 11, 8, 11, 5),
          retryAfter: DateTime(2026, 11, 8, 14, 5),
        ),
      )!;
      expect(l.action, isNull);
      expect(l.masquerRefuserClore, isTrue);
      expect(l.texte, 'Livraison en cours depuis 11:05.');
      final verrou = ligne(
        enCours(),
        etat: EtatLancements(
          deliveryRunning: VerrouLivraison(
            ticketId: 't1',
            launchedAt: DateTime(2026, 11, 8, 11, 5),
            retryAfter: DateTime(2026, 11, 8, 14, 5),
          ),
        ),
      )!;
      expect(verrou.masquerRefuserClore, isTrue);
    });

    test('verrou tenu par un autre ticket : « Ouvrir le ticket #9 »', () {
      final l = ligne(
        enCours(),
        etat: EtatLancements(
          deliveryRunning: VerrouLivraison(
            ticketId: 't9',
            issueNumber: 9,
            launchedAt: DateTime(2026, 11, 8, 11, 5),
            retryAfter: DateTime(2026, 11, 8, 14, 5),
          ),
        ),
      )!;
      expect(l.action, isNull);
      expect(l.verrouTicketId, 't9');
      expect(
        l.texte,
        'Livraison du ticket #9 en cours depuis 11:05. Une seule livraison à '
        'la fois.',
      );
      // Échéance passée : le verrou ne tient plus.
      final passe = ligne(
        enCours(),
        etat: EtatLancements(
          deliveryRunning: VerrouLivraison(
            ticketId: 't9',
            retryAfter: DateTime(2026, 11, 8, 12),
          ),
        ),
      )!;
      expect(passe.action, ActionLancement.livraison);
    });

    test('CI rouge : Relancer le développement ; validé sur GitHub : rien', () {
      final l = ligne(enCours(), livraison: const DocumentTrouve(rouge))!;
      expect(l.action, ActionLancement.reprise);
      expect(l.actif, isTrue);
      expect(
        l.texte,
        'CI de la PR #34 en échec. Une session peut la corriger sur la même '
        'branche.',
      );
      final github = ligne(
        enCours(parApplication: false),
        livraison: const DocumentTrouve(rouge),
      )!;
      expect(github.action, isNull);
      expect(
        github.texte,
        'CI de la PR #34 en échec. Ouvrez la PR pour voir l\'erreur.',
      );
    });

    test('CI rouge pendant le développement : relance possible après '
        'l\'échéance', () {
      final l = ligne(
        enCours(),
        livraison: const DocumentTrouve(rouge),
        lancements: historique(
          ActionLancement.developpement,
          at: DateTime(2026, 11, 8, 11, 5),
          retryAfter: DateTime(2026, 11, 8, 14, 5),
        ),
      )!;
      expect(l.action, isNull);
      expect(
        l.texte,
        'CI de la PR #34 en échec. Développement lancé le 08/11/26 à 11:05 : '
        'relance possible après 14:05.',
      );
    });

    test('correction en cours : ligne datée, aucun bouton', () {
      final l = ligne(
        enCours(),
        livraison: const DocumentTrouve(rouge),
        lancements: historique(
          ActionLancement.reprise,
          at: DateTime(2026, 11, 8, 11, 5),
          retryAfter: DateTime(2026, 11, 8, 14, 5),
        ),
      )!;
      expect(l.action, isNull);
      expect(l.texte, 'Correction de la PR #34 en cours depuis 11:05.');
    });

    test('plusieurs PR, CI en cours, aucune PR, panne, hors ligne', () {
      expect(
        ligne(
          enCours(),
          livraison: const DocumentTrouve(TicketDelivery(eligiblePrCount: 3)),
        )!.texte,
        '3 pull requests ferment l\'Issue #12 : fermez sur GitHub celles à '
        'abandonner.',
      );
      expect(
        ligne(
          enCours(),
          livraison: const DocumentTrouve(
            TicketDelivery(
              eligiblePrCount: 1,
              prNumber: 34,
              ciStatus: 'in_progress',
            ),
          ),
        )!.texte,
        'CI de la PR #34 en cours. « Livrer » sera proposé quand elle sera '
        'verte.',
      );
      expect(
        ligne(enCours(), livraison: const DocumentAbsent())!.texte,
        'Aucune pull request prête pour l\'Issue #12.',
      );
      final panne = ligne(enCours(), livraison: null, panne: true)!;
      expect(panne.reessayer, isTrue);
      expect(panne.texte, 'État de la pull request illisible.');
      expect(
        ligne(
          enCours(),
          livraison: const DocumentAbsentDuCache(),
          offline: true,
        )!.texte,
        'État de la pull request non disponible hors ligne.',
      );
      expect(
        ligne(enCours(), livraison: null)!.progression,
        'Lecture de la pull request',
      );
    });

    test('livraison arrêtée par un blocage ou sans fusion : Relancer la '
        'livraison, texte choisi par ended_by du serveur', () {
      final at = DateTime(2026, 11, 8, 8, 5);
      final lancements = historique(
        ActionLancement.livraison,
        at: at,
        retryAfter: DateTime(2026, 11, 8, 9),
      );
      final bloquee = ligne(
        enCours(),
        lancements: historique(
          ActionLancement.livraison,
          at: at,
          retryAfter: DateTime(2026, 11, 8, 9),
          endedBy: kLivraisonFinBlocage,
        ),
      )!;
      expect(bloquee.relanceDe, at);
      expect(bloquee.ton, TonLivraison.erreur);
      expect(
        bloquee.texte,
        'La livraison du 08/11/26 à 08:05 s\'est arrêtée. Lisez le blocage '
        'dans la section Livraison.',
      );
      // Un blocage relevé sans `ended_by` ne change pas le texte : le client
      // ne compare aucune date (P46).
      final sansChamp = ligne(
        enCours(),
        lancements: lancements,
        livraison: DocumentTrouve(
          TicketDelivery(
            eligiblePrCount: 1,
            prNumber: 34,
            ciStatus: 'completed',
            ready: true,
            reports: [
              CompteRenduLivraison(
                type: TypeCompteRendu.blocage,
                body: '## Livraison — blocage',
                createdAt: DateTime(2026, 11, 8, 8, 40),
              ),
            ],
          ),
        ),
      )!;
      expect(sansChamp.texte, ligneLivraisonSansFusion(at));
      final sansFusion = ligne(enCours(), lancements: lancements)!;
      expect(sansFusion.texte, ligneLivraisonSansFusion(at));
      expect(sansFusion.action, ActionLancement.livraison);
    });

    test('CI absente ou terminée sans succès : deux textes', () {
      expect(
        ligne(
          enCours(),
          livraison: const DocumentTrouve(
            TicketDelivery(eligiblePrCount: 1, prNumber: 34),
          ),
        )!.texte,
        'CI de la PR #34 pas encore lancée. Ouvrez la PR pour la suivre sur '
        'GitHub.',
      );
      expect(
        ligne(
          enCours(),
          livraison: const DocumentTrouve(
            TicketDelivery(
              eligiblePrCount: 1,
              prNumber: 34,
              ciStatus: 'completed',
              ciConclusion: 'cancelled',
            ),
          ),
        )!.texte,
        'CI de la PR #34 terminée sans succès. Ouvrez la PR pour la suivre '
        'sur GitHub.',
      );
    });

    test('document illisible : mettre à jour, sans Réessayer', () {
      final l = ligne(
        enCours(),
        livraison: const DocumentIllisibleTrouve('x'),
      )!;
      expect(l.texte, kEtatPrIllisible);
      expect(l.reessayer, isFalse);
    });

    test(
      'lecture de la CI refusée au jeton : ligne d\'erreur, aucun bouton',
      () {
        final l = ligne(
          enCours(),
          etat: EtatLancements(day: '20261108', ciReadDeniedSince: t0),
        )!;
        expect(l.texte, kCiLectureRefusee);
        expect(l.ton, TonLivraison.erreur);
        expect(l.action, isNull);
        // Sans PR éligible, le serveur ne relit aucun run : la ligne ne
        // masque pas « Aucune pull request prête ».
        final sansPr = ligne(
          enCours(),
          livraison: const DocumentTrouve(TicketDelivery()),
          etat: EtatLancements(day: '20261108', ciReadDeniedSince: t0),
        )!;
        expect(sansPr.texte, isNot(kCiLectureRefusee));
        expect(
          ligne(
            enCours(),
            livraison: const DocumentAbsent(),
            etat: EtatLancements(day: '20261108', ciReadDeniedSince: t0),
          )!.texte,
          isNot(kCiLectureRefusee),
        );
        expect(
          EtatLancements.fromFirestore({
            'ci_read_denied_since': Timestamp.fromDate(t0),
          }).ciReadDeniedSince,
          t0,
        );
      },
    );

    test('relance après une échéance le lendemain : date affichée', () {
      final l = ligne(
        enCours(),
        livraison: const DocumentTrouve(rouge),
        lancements: historique(
          ActionLancement.developpement,
          at: DateTime(2026, 11, 8, 11, 5),
          retryAfter: DateTime(2026, 11, 9, 2),
        ),
      )!;
      expect(
        l.texte,
        'CI de la PR #34 en échec. Développement lancé le 08/11/26 à 11:05 : '
        'relance possible après le 09/11/26 à 02:00.',
      );
    });

    test('validé sur GitHub : fusionner sur GitHub, ou valider si offert', () {
      expect(
        ligne(enCours(parApplication: false))!.texte,
        'PR #34 prête. Ce ticket a été validé sur GitHub : fusionnez la PR sur '
        'GitHub.',
      );
      final avecValider = unTicket(
        id: 't1',
        status: TicketStatus.inProgress,
        issueNumber: 12,
        allowedDecisions: const [
          TicketDecisionAction.validate,
          TicketDecisionAction.refuse,
          TicketDecisionAction.close,
        ],
      );
      expect(
        ligne(avecValider)!.texte,
        'PR #34 prête. Ce ticket a été validé sur GitHub : fusionnez la PR sur '
        'GitHub, ou validez-le depuis l\'application pour la livrer d\'ici.',
      );
    });

    test('ticket hors « En cours » : aucune ligne', () {
      expect(ligne(unTicket(issueNumber: 12)), isNull);
    });

    test('pastille : correction en cours avant CI et PR prête', () {
      expect(
        pastilleLivraison(
          ticket: enCours(),
          livraison: rouge,
          historique: historique(
            ActionLancement.reprise,
            at: t0,
            retryAfter: DateTime(2026, 11, 8, 13),
          ),
          quota: null,
          now: now,
        ),
        PastilleLivraisonType.correctionEnCours,
      );
    });

    test('pastille : livraison en cours, CI en cours, PR prête', () {
      expect(
        pastilleLivraison(
          ticket: enCours(),
          livraison: prete,
          historique: historique(
            ActionLancement.livraison,
            at: t0,
            retryAfter: DateTime(2026, 11, 8, 13),
          ),
          quota: null,
          now: now,
        ),
        PastilleLivraisonType.livraisonEnCours,
      );
      expect(
        pastilleLivraison(
          ticket: enCours(),
          livraison: const TicketDelivery(
            prNumber: 34,
            ciStatus: 'queued',
            eligiblePrCount: 1,
          ),
          historique: null,
          quota: null,
          now: now,
        ),
        PastilleLivraisonType.ciEnCours,
      );
      expect(
        pastilleLivraison(
          ticket: enCours(),
          livraison: prete,
          historique: null,
          quota: null,
          now: now,
        ),
        PastilleLivraisonType.prPrete,
      );
      expect(
        pastilleLivraison(
          ticket: unTicket(issueNumber: 12),
          livraison: prete,
          historique: null,
          quota: null,
          now: now,
        ),
        isNull,
      );
    });

    test('pastille : ni CI en cours ni PR prête tant que la lecture de la CI '
        'est refusée', () {
      final refusee = EtatLancements(day: '20261108', ciReadDeniedSince: t0);
      expect(
        pastilleLivraison(
          ticket: enCours(),
          livraison: prete,
          historique: null,
          quota: refusee,
          now: now,
        ),
        isNull,
      );
      expect(
        pastilleLivraison(
          ticket: enCours(),
          livraison: const TicketDelivery(
            prNumber: 34,
            ciStatus: 'queued',
            eligiblePrCount: 1,
          ),
          historique: null,
          quota: refusee,
          now: now,
        ),
        isNull,
      );
    });
  });

  group('dépôt', () {
    test('reprise : mode resume ; livraison : launchTicketDelivery', () async {
      final calls = <(String, Map<String, Object?>)>[];
      final repository = FirestoreTicketsRepository(
        errorReportService: RecordingErrorReportService(),
        firestore: FakeFirebaseFirestore(),
        callable: (name, data) async {
          calls.add((name, data));
          return {'outcome': 'launched'};
        },
      );
      await repository.launch(ticketId: 't1', action: ActionLancement.reprise);
      await repository.launch(
        ticketId: 't1',
        action: ActionLancement.livraison,
      );
      expect(calls.map((c) => c.$1), [
        'launchTicketDevelopment',
        'launchTicketDelivery',
      ]);
      expect(calls[0].$2, {'ticketId': 't1', 'mode': 'resume'});
      expect(calls[1].$2, {'ticketId': 't1'});
    });

    test('admin/delivery : absent, trouvé, illisible rapporté', () async {
      final firestore = FakeFirebaseFirestore();
      final errors = RecordingErrorReportService();
      final repository = FirestoreTicketsRepository(
        errorReportService: errors,
        firestore: firestore,
      );
      expect(
        await repository.watchDelivery('t1').first,
        isA<DocumentAbsent<TicketDelivery>>(),
      );
      await firestore.doc('tickets/t1/admin/delivery').set({'ready': true});
      expect(
        await repository.watchDelivery('t1').first,
        isA<DocumentTrouve<TicketDelivery>>(),
      );
      await firestore.doc('tickets/t1/admin/delivery').set({'ready': 'oui'});
      expect(
        await repository.watchDelivery('t1').first,
        isA<DocumentIllisibleTrouve<TicketDelivery>>(),
      );
      expect(errors.reports.single.feature, 'tickets.read_delivery');
      // Ni le texte d'un compte rendu ni une adresse dans le rapport (P45).
      expect(
        errors.reports.single.context,
        'tickets/t1/admin/delivery illisible',
      );
    });
  });

  group('fiche', () {
    Future<TestApp> fiche(
      WidgetTester tester,
      Ticket ticket, {
      RechercheDocument<TicketDelivery> livraison = const DocumentTrouve(prete),
      RechercheDocument<EtatLancements> etat = const DocumentTrouve(quota),
      RechercheDocument<TicketLaunchesDoc>? lancements,
    }) async {
      final app = TestApp();
      await app.pump(tester, width: 400, height: 2400);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.deliveryOf(ticket.id).add(livraison);
      app.tickets.launchStatus.add(etat);
      if (lancements != null) app.tickets.launchesOf(ticket.id).add(lancements);
      app.tickets.publishAll([ticket]);
      app.tickets.publishDecisions(ticket.id, const []);
      app.tickets.analysesOf(ticket.id).add(const DocumentAbsent());
      app.container.read(routerProvider).go(AppRoutes.adminTicket(ticket.id));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('PR prête : Livrer, boîte qui nomme la PR et l\'accord de '
        'fusion', (tester) async {
      final app = await fiche(tester, enCours());
      expect(find.text('PR #34 prête : CI verte.'), findsOneWidget);
      expect(find.text('Ouvrir la PR #34'), findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);
      // Section Livraison avant Analyses.
      expect(find.text('Livraison (0)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Livraison (0)')).dy,
        lessThan(tester.getTopLeft(find.text('Analyses')).dy),
      );
      expect(
        find.text('${SectionLivraison.vide} ${SectionLivraison.invitation}'),
        findsOneWidget,
      );
      await tester.tap(find.text('Livrer'));
      await tester.pumpAndSettle();
      expect(find.text('Livrer ce ticket ?'), findsOneWidget);
      expect(
        find.text(
          BoiteLancement.effet(ActionLancement.livraison, 12, prNumber: 34),
        ),
        findsOneWidget,
      );
      expect(find.text(BoiteLancement.accordFusion), findsOneWidget);
      expect(find.text('Type du ticket : Bug.'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(app.tickets.launches, isEmpty);
      await tester.tap(find.text('Livrer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Livrer').last);
      await tester.pump();
      expect(app.tickets.launches.single, (
        ticketId: 't1',
        action: ActionLancement.livraison,
      ));
    });

    testWidgets('refus fichier protégé : message et Livrer inactif', (
      tester,
    ) async {
      final app = await fiche(tester, enCours());
      app.tickets.launchResult = () async => const ResultatLancement(
        IssueLancement.refuse,
        motif:
            'La PR #34 modifie un fichier protégé (app/pubspec.lock). '
            'Fusionnez-la vous-même après relecture. Rien n\'a été lancé ni '
            'décompté.',
        code: 'delivery_sensitive_files',
      );
      await tester.tap(find.text('Livrer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Livrer').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Fusionnez-la vous-même après relecture.'),
        findsOneWidget,
      );
      final livrer = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Livrer').last,
      );
      expect(livrer.onPressed, isNull);
    });

    testWidgets('refus liste de fichiers trop longue : Livrer inactif aussi', (
      tester,
    ) async {
      final app = await fiche(tester, enCours());
      app.tickets.launchResult = () async => const ResultatLancement(
        IssueLancement.refuse,
        motif:
            'La liste des fichiers de la PR #34 est trop longue pour être '
            'vérifiée. Fusionnez-la vous-même après relecture. Rien n\'a été '
            'lancé ni décompté.',
        code: 'delivery_files_unreadable',
      );
      await tester.tap(find.text('Livrer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Livrer').last);
      await tester.pumpAndSettle();
      final livrer = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Livrer').last,
      );
      expect(livrer.onPressed, isNull);
    });

    testWidgets('icône de la ligne : primary pour une PR prête, error pour '
        'un échec', (tester) async {
      await fiche(tester, enCours());
      final prete = tester.widget<Icon>(
        find.byIcon(Icons.check_circle_outline),
      );
      final scheme = Theme.of(
        tester.element(find.byIcon(Icons.check_circle_outline)),
      ).colorScheme;
      expect(prete.color, scheme.primary);
    });

    testWidgets('lecture de la CI refusée au jeton : ligne sur la fiche', (
      tester,
    ) async {
      await fiche(
        tester,
        enCours(),
        etat: DocumentTrouve(
          EtatLancements(
            day: '20261108',
            countDay: 3,
            perDay: 10,
            ciReadDeniedSince: t0,
          ),
        ),
      );
      expect(find.text(kCiLectureRefusee), findsOneWidget);
      expect(find.text('Livrer'), findsNothing);
      final icone = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      final scheme = Theme.of(
        tester.element(find.byIcon(Icons.error_outline)),
      ).colorScheme;
      expect(icone.color, scheme.error);
    });

    testWidgets('relance de la livraison : pas d\'invitation à « Livrer »', (
      tester,
    ) async {
      await fiche(
        tester,
        enCours(),
        lancements: DocumentTrouve(
          historique(
            ActionLancement.livraison,
            at: DateTime(2026, 11, 8, 8, 5),
            retryAfter: DateTime(2026, 11, 8, 11, 5),
          ),
        ),
      );
      expect(find.text('Relancer la livraison'), findsOneWidget);
      expect(find.text(SectionLivraison.vide), findsOneWidget);
      expect(find.textContaining(SectionLivraison.invitation), findsNothing);
    });

    testWidgets('relecture en panne avec comptes rendus affichés : cartes, '
        'ligne et Réessayer', (tester) async {
      final app = await fiche(
        tester,
        enCours(),
        livraison: DocumentTrouve(
          TicketDelivery(
            eligiblePrCount: 1,
            prNumber: 34,
            prUrl: prUrl,
            ciStatus: 'completed',
            ready: true,
            reports: [
              CompteRenduLivraison(
                type: TypeCompteRendu.blocage,
                body: '## Livraison — blocage\n\nL7 : CI rouge.',
                createdAt: t0,
              ),
            ],
          ),
        ),
      );
      app.tickets.deliveryOf('t1').addError(StateError('panne'));
      await tester.pumpAndSettle();
      expect(find.text('L7 : CI rouge.'), findsOneWidget);
      expect(find.text(SectionLivraison.loadError), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Réessayer'), findsOneWidget);
    });

    testWidgets('livraison en cours : Refuser et Clore masqués', (
      tester,
    ) async {
      await fiche(
        tester,
        enCours(),
        lancements: DocumentTrouve(
          historique(
            ActionLancement.livraison,
            at: DateTime(2026, 11, 8, 11, 5),
            retryAfter: DateTime(2026, 11, 8, 14, 5),
          ),
        ),
      );
      expect(find.text('Livraison en cours depuis 11:05.'), findsOneWidget);
      expect(find.text('Refuser'), findsNothing);
      expect(find.text('Clore'), findsNothing);
      expect(find.text('Livrer'), findsNothing);
    });

    testWidgets('CI rouge : Relancer le développement, boîte « Elle ne '
        'fusionne pas »', (tester) async {
      final app = await fiche(
        tester,
        enCours(),
        livraison: const DocumentTrouve(rouge),
      );
      await tester.tap(find.text('Relancer le développement'));
      await tester.pumpAndSettle();
      expect(find.text('Relancer le développement ?'), findsOneWidget);
      expect(
        find.text(
          BoiteLancement.effet(ActionLancement.reprise, 12, prNumber: 34),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Relancer'));
      await tester.pump();
      expect(app.tickets.launches.single.action, ActionLancement.reprise);
    });

    testWidgets(
      'comptes rendus : blocage et livraison terminée, titre retiré',
      (tester) async {
        await fiche(
          tester,
          enCours(),
          livraison: DocumentTrouve(
            TicketDelivery(
              eligiblePrCount: 1,
              prNumber: 34,
              prUrl: prUrl,
              ciStatus: 'completed',
              ready: true,
              reports: [
                CompteRenduLivraison(
                  type: TypeCompteRendu.blocage,
                  body: '## Livraison — blocage\n\nL7 : CI rouge.',
                  createdAt: t0,
                ),
                CompteRenduLivraison(
                  type: TypeCompteRendu.terminee,
                  body: '## Livraison — terminée\n\nVersion 0.1.40.',
                  createdAt: DateTime(2026, 11, 8, 10),
                ),
              ],
            ),
          ),
        );
        expect(find.text('Livraison (2)'), findsOneWidget);
        expect(find.text('Blocage du 08/11/26 à 09:30'), findsOneWidget);
        expect(
          find.text('Livraison terminée le 08/11/26 à 10:00'),
          findsOneWidget,
        );
        expect(find.text('L7 : CI rouge.'), findsOneWidget);
        expect(find.textContaining('## Livraison'), findsNothing);
      },
    );
  });

  group('liste', () {
    testWidgets('seul ticket à traiter : PR prête lue après la liste, '
        'filtre gardé sur « À traiter »', (tester) async {
      final app = TestApp();
      final livraison = app.tickets.deliveries['a'] = Replay();
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.publishAll([
        enCours(id: 'a'),
        unTicket(
          id: 'c',
          title: 'Troisième',
          status: TicketStatus.delivered,
          issueNumber: 4,
        ),
      ]);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      livraison.add(const DocumentTrouve(prete));
      await tester.pumpAndSettle();
      expect(find.text('À traiter (1)'), findsOneWidget);
      expect(find.text('Densité fausse'), findsOneWidget);
      expect(find.text('Troisième'), findsNothing);
    });

    testWidgets('PR prête mais lecture de la CI refusée : hors « À traiter », '
        'sans pastille', (tester) async {
      final app = TestApp();
      app.tickets.deliveryOf('a').add(const DocumentTrouve(prete));
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.launchStatus.add(
        DocumentTrouve(EtatLancements(day: '20261108', ciReadDeniedSince: t0)),
      );
      app.tickets.publishAll([
        enCours(id: 'a'),
        unTicket(id: 'b', title: 'Autre', issueNumber: 3),
      ]);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      await tester.tap(find.text('À traiter (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Densité fausse'), findsNothing);
      expect(find.text('Autre'), findsOneWidget);
      await tester.tap(find.text('Tous'));
      await tester.pumpAndSettle();
      expect(find.text('Densité fausse'), findsOneWidget);
      expect(find.text('PR prête'), findsNothing);
    });

    testWidgets('PR prête mais livraison en cours : hors « À traiter »', (
      tester,
    ) async {
      final app = TestApp();
      app.tickets.deliveryOf('a').add(const DocumentTrouve(prete));
      app.tickets
          .launchesOf('a')
          .add(
            DocumentTrouve(
              historique(
                ActionLancement.livraison,
                at: DateTime(2026, 11, 8, 11, 5),
                retryAfter: DateTime(2026, 11, 8, 14, 5),
              ),
            ),
          );
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.publishAll([
        enCours(id: 'a'),
        unTicket(id: 'b', title: 'Autre', issueNumber: 3),
      ]);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      await tester.tap(find.text('À traiter (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Densité fausse'), findsNothing);
      expect(find.text('Autre'), findsOneWidget);
    });

    testWidgets('PR prête : pastille, et sous « À traiter »', (tester) async {
      final app = TestApp();
      app.tickets.deliveryOf('a').add(const DocumentTrouve(prete));
      await app.pump(tester, width: 400, height: 1200);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.tickets.publishAll([
        enCours(id: 'a'),
        unTicket(id: 'b', title: 'Autre', issueNumber: 3),
        unTicket(
          id: 'c',
          title: 'Troisième',
          status: TicketStatus.inProgress,
          issueNumber: 4,
        ),
      ]);
      app.container.read(routerProvider).go(AppRoutes.adminTickets);
      await tester.pumpAndSettle();
      await tester.tap(find.text('À traiter (2)'));
      await tester.pumpAndSettle();
      expect(find.text('PR prête'), findsOneWidget);
      expect(find.text('Densité fausse'), findsOneWidget);
      expect(find.text('Autre'), findsOneWidget);
      expect(find.text('Troisième'), findsNothing);
    });
  });
}
