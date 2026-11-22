import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_delivery.dart';
import 'package:kass_beer/features/tickets/domain/ticket_launch.dart';
import 'package:kass_beer/features/tickets/presentation/admin_ticket_screen.dart';

import 'support/ticket_fixtures.dart';

/// File des livraisons (ADR-008, amendement du 2026-11-22, ticket #104), côté
/// client : le bouton et la ligne se lisent dans `delivery_running`,
/// `delivery_last`, `delivery_queue` et `queue_exit`, sans condition de
/// départ ni éligibilité recopiée (P39).
void main() {
  final now = DateTime(2026, 11, 22, 14, 10);

  Ticket enCours({String id = 't1', int issue = 12}) => unTicket(
    id: id,
    status: TicketStatus.inProgress,
    issueNumber: issue,
    issueUrl: 'https://github.com/ChinaFred/KassBeer/issues/$issue',
    allowedDecisions: const [
      TicketDecisionAction.refuse,
      TicketDecisionAction.close,
    ],
    canLaunchDelivery: true,
    canRelaunchDevelopment: true,
  );

  const prete = TicketDelivery(
    eligiblePrCount: 1,
    prNumber: 34,
    ciStatus: 'completed',
    ciConclusion: 'success',
    ready: true,
  );
  const rouge = TicketDelivery(
    eligiblePrCount: 1,
    prNumber: 34,
    ciStatus: 'completed',
    ciConclusion: 'failure',
    relaunchReady: true,
  );
  const historiqueVide = TicketLaunchesDoc(entries: []);

  EntreeFileLivraison entree(String id, int issue, {String by = 'moi'}) =>
      EntreeFileLivraison(
        ticketId: id,
        issueNumber: issue,
        prNumber: 34,
        queuedAt: DateTime(2026, 11, 22, 14, 5),
        byUid: by,
      );

  final verrou9 = VerrouLivraison(
    ticketId: 't9',
    issueNumber: 9,
    launchedAt: DateTime(2026, 11, 22, 14, 5),
    retryAfter: DateTime(2026, 11, 22, 17, 5),
  );
  final derniere9 = DerniereLivraison(
    ticketId: 't9',
    issueNumber: 9,
    launchedAt: DateTime(2026, 11, 22, 14, 5),
    retryAfter: DateTime(2026, 11, 22, 17, 5),
  );

  EtatLancements etat({
    VerrouLivraison? verrou,
    DerniereLivraison? derniere,
    List<EntreeFileLivraison> file = const [],
    int countDay = 3,
    DateTime? jetonRefuse,
  }) => EtatLancements(
    day: '20261122',
    countDay: countDay,
    perDay: 10,
    deliveryRunning: verrou,
    deliveryLast: derniere,
    deliveryQueue: file,
    developmentInvalidSince: jetonRefuse,
  );

  LigneLivraison ligne(
    EtatLancements quota, {
    Ticket? ticket,
    TicketDelivery doc = prete,
    TicketLaunchesDoc historique = historiqueVide,
    bool offline = false,
  }) => ligneLivraison(
    ticket: ticket ?? enCours(),
    livraison: DocumentTrouve(doc),
    livraisonEnPanne: false,
    historique: historique,
    quota: quota,
    now: now,
    offline: offline,
    appelEnCours: false,
    uid: 'moi',
  )!;

  group('lecture de ticket_status/launches', () {
    test(
      'delivery_queue et delivery_last lus ; e-mail de l\'accord ignoré',
      () {
        final e = EtatLancements.fromFirestore({
          'delivery_queue': [
            {
              'ticket_id': 't2',
              'issue_number': 15,
              'pr_number': 40,
              'head_sha': 'a' * 40,
              'queued_at': Timestamp.fromDate(DateTime(2026, 11, 22, 14)),
              'by_uid': 'u1',
              'by_email': 'admin@example.com',
            },
            {'ticket_id': ''},
          ],
          'delivery_last': {
            'ticket_id': 't9',
            'issue_number': 9,
            'launched_at': Timestamp.fromDate(DateTime(2026, 11, 22, 14)),
            'retry_after': Timestamp.fromDate(DateTime(2026, 11, 22, 17)),
            'reported_at': null,
          },
        });
        expect(e.deliveryQueue.length, 1);
        expect(e.deliveryQueue.first.issueNumber, 15);
        expect(e.positionFile('t2')?.position, 1);
        expect(e.positionFile('t1'), isNull);
        expect(e.deliveryLast?.compteRenduAttendu(now), isTrue);
        expect(
          e.vuePour(fondateur: true).deliveryQueue.first.ticketId,
          't2',
          reason: 'la vue du fondateur garde la file',
        );
      },
    );

    test('queue_exit lu ; code inconnu lisible', () {
      final d = TicketDelivery.fromFirestore({
        'queue_exit': {
          'code': 'code_futur',
          'at': Timestamp.fromDate(DateTime(2026, 11, 22, 14, 15)),
        },
      });
      expect(d.queueExit?.code, 'code_futur');
      expect(
        ligneSortieFile(d.queueExit!).texte,
        'Sortie de la file le 22/11/26 à 14:15. Mettez l\'application à jour '
        'pour lire la raison.',
      );
    });
  });

  group('bouton hors de la file', () {
    test('verrou d\'un autre ticket et file non vide : « Mettre en file »', () {
      final l = ligne(etat(verrou: verrou9, file: [entree('t2', 15)]));
      expect(l.mode, ModeLivraison.mettreEnFile);
      expect(
        l.texte,
        'Livraison du ticket #9 en cours depuis 14:05. Une seule livraison à '
        'la fois. 1 ticket attend déjà.',
      );
      expect(l.verrouTicketId, 't9');
    });

    test('compte rendu de la précédente attendu : « Mettre en file »', () {
      final l = ligne(etat(derniere: derniere9));
      expect(l.mode, ModeLivraison.mettreEnFile);
      expect(
        l.texte,
        'La livraison du ticket #9 n\'a pas encore publié son compte rendu. '
        'Une seule livraison à la fois.',
      );
      // Compte rendu relevé : « Livrer ».
      final fini = ligne(
        etat(
          derniere: DerniereLivraison(
            ticketId: 't9',
            retryAfter: DateTime(2026, 11, 22, 17, 5),
            reportedAt: DateTime(2026, 11, 22, 14, 8),
          ),
        ),
      );
      expect(fini.mode, isNull);
      expect(fini.action, ActionLancement.livraison);
    });

    test('file non vide, précédente finie : « Mettre en file »', () {
      final l = ligne(etat(file: [entree('t2', 15), entree('t3', 16)]));
      expect(l.mode, ModeLivraison.mettreEnFile);
      expect(
        l.texte,
        '2 livraisons attendent dans la file. La prochaine part dans 5 '
        'minutes au plus.',
      );
    });

    test('plafond atteint : « Mettre en file » reste actif', () {
      final l = ligne(etat(verrou: verrou9, countDay: 10));
      expect(l.mode, ModeLivraison.mettreEnFile);
      expect(l.actif, isTrue);
      expect(ligne(etat(countDay: 10)).actif, isFalse);
    });

    test('hors ligne : inactif', () {
      expect(ligne(etat(verrou: verrou9), offline: true).actif, isFalse);
    });

    test('sortie de file affichée, masquée après un départ', () {
      final sortie = SortieFile(
        code: 'delivery_queue_head_changed',
        at: DateTime(2026, 11, 22, 14, 15),
      );
      const base = TicketDelivery(
        eligiblePrCount: 1,
        prNumber: 34,
        ciStatus: 'completed',
        ciConclusion: 'success',
        ready: true,
      );
      final doc = TicketDelivery(
        eligiblePrCount: base.eligiblePrCount,
        prNumber: base.prNumber,
        ciStatus: base.ciStatus,
        ciConclusion: base.ciConclusion,
        ready: true,
        queueExit: sortie,
      );
      final l = ligne(etat(), doc: doc);
      expect(
        l.sortie?.texte,
        'Sortie de la file le 22/11/26 à 14:15 : le code de la PR a changé '
        'depuis votre accord.',
      );
      expect(l.sortie?.erreur, isTrue);
      final apres = ligne(
        etat(),
        doc: doc,
        historique: TicketLaunchesDoc(
          entries: [
            TicketLaunch(
              action: ActionLancement.livraison,
              etat: EtatLancement.failed,
              at: DateTime(2026, 11, 22, 14, 20),
              retryAfter: DateTime(2026, 11, 22, 14, 20),
            ),
          ],
        ),
      );
      expect(apres.sortie, isNull);
      expect(
        ligneSortieFile(
          SortieFile(code: kSortieRetrait, at: DateTime(2026, 11, 22, 14, 15)),
        ),
        (texte: 'Retiré de la file le 22/11/26 à 14:15.', erreur: false),
      );
    });
  });

  group('dans la file', () {
    test('pas en tête : position, derrière le ticket #15, accord', () {
      final l = ligne(
        etat(verrou: verrou9, file: [entree('t2', 15), entree('t1', 12)]),
      );
      expect(l.mode, ModeLivraison.retirer);
      expect(
        l.texte,
        'Dans la file (position 2 sur 2), derrière le ticket #15.',
      );
      expect(l.ligneAccord, 'Accord du 22/11/26 à 14:05 pour la PR #34.');
      expect(l.verrouTicketId, 't2');
    });

    test('en tête : verrou, compte rendu, plafond, jeton, rien à attendre', () {
      expect(
        ligne(etat(verrou: verrou9, file: [entree('t1', 12)])).texte,
        'Dans la file (position 1 sur 1) : partira après la livraison du '
        'ticket #9.',
      );
      expect(
        ligne(etat(derniere: derniere9, file: [entree('t1', 12)])).texte,
        'Dans la file (position 1 sur 1) : partira après le compte rendu de la '
        'livraison du ticket #9, à 17:05 au plus tard.',
      );
      expect(
        ligne(etat(countDay: 10, file: [entree('t1', 12)])).texte,
        'Dans la file (position 1 sur 1) : plafond atteint le 22/11 (10 sur '
        '10). Elle partira quand le compteur repartira à zéro, peu après '
        'minuit.',
      );
      // Accord d'un autre administrateur : aucune ligne de plafond.
      expect(
        ligne(etat(countDay: 10, file: [entree('t1', 12, by: 'autre')])).texte,
        'Dans la file (position 1 sur 1) : départ dans 5 minutes au plus.',
      );
      final jeton = ligne(
        etat(jetonRefuse: DateTime(2026, 11, 22, 9), file: [entree('t1', 12)]),
      );
      expect(jeton.ton, TonLivraison.erreur);
      expect(
        jeton.texte,
        'Dans la file (position 1 sur 1) : la file attend, le jeton de la '
        'routine de développement est refusé depuis le 22/11/26.',
      );
    });

    test(
      'CI rouge : sortie annoncée, Retirer et Relancer le développement',
      () {
        final l = ligne(etat(file: [entree('t1', 12)]), doc: rouge);
        expect(l.mode, ModeLivraison.retirer);
        expect(
          l.ligneDetail,
          'CI de la PR #34 en échec : la livraison sortira de la file au '
          'départ.',
        );
        expect(l.repriseAussi, isTrue);
      },
    );

    test('départ depuis la file : « partie de la file », Refuser et Clore '
        'masqués', () {
      final l = ligne(
        etat(),
        historique: TicketLaunchesDoc(
          entries: [
            TicketLaunch(
              action: ActionLancement.livraison,
              etat: EtatLancement.launched,
              at: DateTime(2026, 11, 22, 14, 10),
              retryAfter: DateTime(2026, 11, 22, 17, 10),
              queued: true,
            ),
          ],
        ),
      );
      expect(l.texte, 'Livraison en cours depuis 14:10, partie de la file.');
      expect(l.masquerRefuserClore, isTrue);
    });
  });

  group('relectures du 2026-11-22', () {
    test('file arrêtée par la routine : « la file attend », ton d\'erreur', () {
      final arret = EtatLancements.fromFirestore({
        'day': '20261122',
        'count_day': 3,
        'per_day': 10,
        'delivery_queue': [
          {'ticket_id': 't1', 'issue_number': 12, 'pr_number': 34},
        ],
        'delivery_queue_halted': {
          'code': 'routine_paused',
          'at': Timestamp.fromDate(DateTime(2026, 11, 22, 9)),
        },
      });
      final l = ligne(arret);
      expect(l.ton, TonLivraison.erreur);
      expect(
        l.texte,
        'Dans la file (position 1 sur 1) : la file attend, la routine de '
        'développement est en pause depuis le 22/11/26. Réactivez-la sur '
        'claude.ai.',
      );
      final refuse = EtatLancements(
        deliveryQueue: [entree('t1', 12)],
        deliveryQueueHalted: const ArretFile(code: 'routine_failed'),
      );
      expect(
        ligne(refuse).texte,
        'Dans la file (position 1 sur 1) : la file attend, la routine de '
        'développement a refusé le lancement.',
      );
    });

    test('CI en cours : phrase neutre ; lecture de la CI refusée : aucune', () {
      const enCours = TicketDelivery(
        eligiblePrCount: 1,
        prNumber: 34,
        ciStatus: 'in_progress',
      );
      final l = ligne(etat(file: [entree('t1', 12)]), doc: enCours);
      expect(
        l.ligneDetail,
        'CI de la PR #34 en cours : si elle n\'est pas verte au départ, la '
        'livraison sortira de la file.',
      );
      expect(l.detailErreur, isFalse);
      final sansPr = ligne(
        etat(file: [entree('t1', 12)]),
        doc: const TicketDelivery(),
      );
      expect(sansPr.detailErreur, isTrue);
      final refusee = EtatLancements(
        deliveryQueue: [entree('t1', 12)],
        ciReadDeniedSince: DateTime(2026, 11, 22, 9),
      );
      expect(ligne(refusee, doc: enCours).ligneDetail, isNull);
      expect(ligne(refusee, doc: rouge).ligneDetail, isNull);
    });

    test('appel « Mettre en file » en cours avec un verrou tenu : « Mise en '
        'file en cours. »', () {
      final l = ligneLivraison(
        ticket: enCours(),
        livraison: const DocumentTrouve(prete),
        livraisonEnPanne: false,
        historique: historiqueVide,
        quota: etat(verrou: verrou9),
        now: now,
        offline: false,
        appelEnCours: true,
        modeEnCours: ModeLivraison.mettreEnFile,
        uid: 'moi',
      )!;
      expect(l.texte, 'Mise en file en cours.');
    });

    test('boîte « Mettre en file » : sa propre dernière livraison ignorée', () {
      final propre = DerniereLivraison(
        ticketId: 't1',
        issueNumber: 12,
        retryAfter: DateTime(2026, 11, 22, 17),
      );
      expect(
        positionDansFileApres(etat(derniere: propre), 't1', now),
        'Position dans la file : 1 sur 1.',
      );
    });
  });

  group('pastille et filtre', () {
    test(
      '« En file » après CI en échec, avant PR prête ; hors « À traiter »',
      () {
        final quota = etat(file: [entree('t2', 15), entree('t1', 12)]);
        expect(
          pastilleLivraison(
            ticket: enCours(),
            livraison: prete,
            historique: historiqueVide,
            quota: quota,
            now: now,
          ),
          PastilleLivraisonType.enFile,
        );
        expect(
          pastilleLivraison(
            ticket: enCours(),
            livraison: rouge,
            historique: historiqueVide,
            quota: quota,
            now: now,
          ),
          PastilleLivraisonType.ciRouge,
        );
        expect(
          ticketATraiter(
            ticket: enCours(),
            historique: historiqueVide,
            livraison: prete,
            quota: quota,
            now: now,
          ),
          isFalse,
        );
      },
    );
  });

  group('réponses du serveur', () {
    test('queued, unqueued, refus de la file', () {
      final enFile = ResultatLancement.depuisReponse({
        'outcome': 'queued',
        'position': 2,
        'total': 2,
      });
      expect(enFile.issue, IssueLancement.enFile);
      expect(enFile.position, 2);
      final retire = ResultatLancement.depuisReponse({
        'outcome': 'unqueued',
        'changed': false,
      });
      expect(
        messageRetraitFile(retire, 12),
        'Ce ticket n\'était plus dans la file.',
      );
      expect(
        messageRetraitFile(
          ResultatLancement.depuisReponse({
            'outcome': 'unqueued',
            'changed': true,
          }),
          12,
        ),
        'Ticket #12 retiré de la file.',
      );
      final plein = ResultatLancement.depuisErreur(
        code: 'failed-precondition',
        details: {
          'code': 'delivery_queue_full',
          'reason':
              'La file compte déjà 10 livraisons. Rien n\'a été mis en file.',
        },
      );
      expect(
        plein.message,
        'La file compte déjà 10 livraisons. Rien n\'a été mis en file.',
      );
      final libre = ResultatLancement.depuisErreur(
        code: 'failed-precondition',
        details: {'code': 'delivery_lock_free', 'reason': 'x'},
      );
      expect(
        libre.message,
        'La livraison précédente est finie : appuyez sur « Livrer ».',
      );
      expect(
        messageRetraitFile(
          ResultatLancement.depuisErreur(code: 'unavailable'),
          12,
        ),
        'Retrait non fait : pas de réseau.',
      );
    });

    test('position dans la boîte « Mettre en file »', () {
      expect(
        positionDansFileApres(
          etat(verrou: verrou9, file: [entree('t2', 15)]),
          't1',
          now,
        ),
        'Position dans la file : 2 sur 2, derrière le ticket #15.',
      );
      expect(
        positionDansFileApres(etat(verrou: verrou9), 't1', now),
        'Position dans la file : 1 sur 1, après la livraison du ticket #9.',
      );
    });
  });
}
