import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart';
import 'package:kass_beer/features/tickets/domain/etat_jeton_github.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_analysis.dart';

import 'support/fakes.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;
  late FirestoreTicketsRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
    repository = FirestoreTicketsRepository(
      errorReportService: errors,
      firestore: firestore,
      clock: () => DateTime(2026, 11, 8, 10),
    );
  });

  const brouillon = TicketBrouillon(
    type: TicketType.evolution,
    title: 'Trier les recettes',
    description: 'Pouvoir trier les recettes par style.',
    screen: '/recettes',
  );

  test(
    'création : champs du contrat seuls, identifiant de l\'appareil',
    () async {
      final id = repository.newTicketId();
      await repository.create(
        id: id,
        brouillon: brouillon,
        authorUid: 'uid-brasseur',
        authorEmail: ' Brasseur@Exemple.fr ',
        appVersion: '0.2.0',
        platform: 'android',
      );
      final data = (await firestore.collection('tickets').doc(id).get())
          .data()!;
      expect(data.keys.toSet(), {
        'type',
        'title',
        'description',
        'screen',
        'app_version',
        'platform',
        'author_uid',
        'author_email',
        'created_at',
        'status',
      });
      expect(data['type'], 'evolution');
      expect(data['screen'], '/recettes');
      expect(data['author_email'], 'brasseur@exemple.fr');
      expect(data['status'], 'pending');
      expect(data['created_at'], isA<Timestamp>());
    },
  );

  test('version illisible : app_version absent', () async {
    await repository.create(
      id: 't-sans-version',
      brouillon: brouillon,
      authorUid: 'uid-brasseur',
      authorEmail: 'brasseur@exemple.fr',
      appVersion: null,
      platform: 'web',
    );
    final data =
        (await firestore.collection('tickets').doc('t-sans-version').get())
            .data()!;
    expect(data.containsKey('app_version'), isFalse);
  });

  test(
    'mes tickets : ceux de l\'auteur, un illisible rapporté sans texte',
    () async {
      final tickets = firestore.collection('tickets');
      await tickets.doc('a').set({
        'type': 'bug',
        'title': 'Titre secret',
        'description': 'Description secrète.',
        'screen': 'inconnu',
        'status': 'over_quota',
        'author_uid': 'uid-brasseur',
        'author_email': 'brasseur@exemple.fr',
        'created_at': Timestamp.fromDate(DateTime(2026, 11, 8)),
      });
      await tickets.doc('b').set({
        'type': 'question',
        'title': 'Titre secret',
        'description': 'Description secrète.',
        'screen': 'inconnu',
        'status': 'pending',
        'author_uid': 'uid-brasseur',
      });
      await tickets.doc('c').set({
        'type': 'bug',
        'title': 'Autre auteur',
        'description': 'Ticket d\'un autre membre.',
        'screen': 'inconnu',
        'status': 'pending',
        'author_uid': 'uid-autre',
      });
      final list = await repository.watchMine('uid-brasseur').first;
      expect(list.documents.map((d) => d.id).toSet(), {'a', 'b'});
      expect(list.chercher('a'), isA<DocumentTrouve<Ticket>>());
      expect(list.chercher('b'), isA<DocumentIllisibleTrouve<Ticket>>());
      final report = errors.reports.single;
      expect(report.feature, 'tickets.read');
      expect(report.context, 'tickets/b illisible');
      expect('${report.error}', isNot(contains('secret')));
    },
  );

  test('markSeen écrit seen_by_author_at, seul champ', () async {
    await firestore.collection('tickets').doc('a').set({
      'type': 'bug',
      'status': 'received',
    });
    await repository.markSeen('a');
    final data = (await firestore.collection('tickets').doc('a').get()).data()!;
    expect(data['seen_by_author_at'], isA<Timestamp>());
    expect(data.keys.toSet(), {'type', 'status', 'seen_by_author_at'});
  });

  test('markSeen en échec : rapporté, sans erreur levée', () async {
    await repository.markSeen('absent');
    expect(errors.reports.single.feature, 'tickets.mark_seen');
  });

  test('admin : tous les tickets, champs serveur lus', () async {
    final tickets = firestore.collection('tickets');
    Map<String, Object?> t(
      String status, [
      Map<String, Object?> extra = const {},
    ]) => {
      'type': 'bug',
      'title': 'Titre',
      'description': 'Description longue.',
      'screen': 'inconnu',
      'status': status,
      ...extra,
    };
    await tickets.doc('p').set(t('pending'));
    await tickets.doc('f').set(t('send_failed'));
    await tickets.doc('r').set(t('received'));
    await tickets
        .doc('m')
        .set(t('validated', {'issue_missing_since': Timestamp.now()}));
    await tickets
        .doc('x')
        .set(
          t('received', {
            'github_issue_number': 12,
            'github_url': 'https://github.com/ChinaFred/KassBeer/issues/12',
            'author_email': 'brasseur@exemple.fr',
            'allowed_decisions': ['validate', 'refuse', 'close', 'futur'],
            'decision_lease_until': Timestamp.fromDate(
              DateTime(2026, 11, 8, 10),
            ),
            'send_attempts': 3,
            'last_send_error': 'GitHub indisponible',
          }),
        );
    final all = await repository.watchAll().first;
    expect(all.documents.map((d) => d.id).toSet(), {'p', 'f', 'r', 'm', 'x'});
    final x = all.valides.singleWhere((t) => t.id == 'x');
    expect(x.issueNumber, 12);
    expect(x.authorEmail, 'brasseur@exemple.fr');
    // Une décision inconnue de cette version est ignorée.
    expect(x.allowedDecisions, TicketDecisionAction.values);
    expect(x.decisionLeaseUntil, DateTime(2026, 11, 8, 10));
    expect(x.sendAttempts, 3);
    expect(x.lastSendError, 'GitHub indisponible');
    final m = all.valides.singleWhere((t) => t.id == 'm');
    expect(m.issueMissingSince, isNotNull);
    expect(m.allowedDecisions, isNull);
  });

  group('décisions par callable (T7)', () {
    final calls = <(String, Map<String, Object?>)>[];
    FirestoreTicketsRepository depot(AppelCallable callable) =>
        FirestoreTicketsRepository(
          errorReportService: errors,
          firestore: firestore,
          callable: callable,
        );

    setUp(calls.clear);

    test('Valider, Refuser, Clore : nom de la callable et arguments', () async {
      final repository = depot((name, data) async {
        calls.add((name, data));
        return {'status': 'refused', 'changed': true, 'textKept': false};
      });
      final valide = await repository.decide(
        ticketId: 'a',
        action: TicketDecisionAction.validate,
      );
      expect(valide.echec, isNull);
      expect(valide.texteGarde, isFalse);
      await repository.decide(
        ticketId: 'a',
        action: TicketDecisionAction.refuse,
        text: 'Hors du périmètre.',
      );
      await repository.decide(
        ticketId: 'a',
        action: TicketDecisionAction.close,
        text: 'Fait.',
      );
      expect(calls.map((c) => c.$1), [
        'validateTicket',
        'refuseTicket',
        'closeTicket',
      ]);
      expect(calls.map((c) => c.$2), [
        {'ticketId': 'a'},
        {'ticketId': 'a', 'text': 'Hors du périmètre.'},
        {'ticketId': 'a', 'text': 'Fait.'},
      ]);
      expect(errors.reports, isEmpty);
      // Aucune écriture client dans `decisions/` ni sur le ticket.
      expect((await firestore.collection('tickets').get()).docs, isEmpty);
    });

    test('texte gardé par le serveur : rendu', () async {
      final repository = depot(
        (name, data) async => {
          'status': 'refused',
          'changed': true,
          'decisionId': 'd1',
          'textKept': true,
        },
      );
      final resultat = await repository.decide(
        ticketId: 'a',
        action: TicketDecisionAction.refuse,
        text: 'Nouveau texte.',
      );
      expect(resultat.echec, isNull);
      expect(resultat.texteGarde, isTrue);
    });

    test('refus motivé : rendu, rapporté sans le texte', () async {
      final repository = depot(
        (name, data) async => throw FirebaseFunctionsException(
          code: 'aborted',
          message: 'Motif publié, mais l\'Issue n\'a pas été fermée.',
          details: {
            'reason': 'Motif publié, mais l\'Issue n\'a pas été fermée.',
            'code': 'refuse_partial',
            'partial': true,
          },
        ),
      );
      final echec = await repository.decide(
        ticketId: 'a',
        action: TicketDecisionAction.refuse,
        text: 'Texte secret du motif',
      );
      expect(echec.echec!.partiel, isTrue);
      final report = errors.reports.single;
      expect(report.feature, 'tickets.decide');
      expect(report.context, contains('action=refuse'));
      expect(report.context, contains('reason_code=refuse_partial'));
      expect(report.context, contains('partial'));
      expect(report.context, isNot(contains('secret')));
    });

    test('panne interne ou erreur sans réponse : résultat inconnu', () async {
      final interne = depot(
        (name, data) async =>
            throw FirebaseFunctionsException(code: 'internal', message: 'x'),
      );
      expect(
        (await interne.decide(
          ticketId: 'a',
          action: TicketDecisionAction.validate,
        )).echec!.cause,
        CauseEchecReponse.delai,
      );
      final perdu = depot((name, data) async => throw StateError('coupure'));
      expect(
        (await perdu.decide(
          ticketId: 'a',
          action: TicketDecisionAction.validate,
        )).echec!.cause,
        CauseEchecReponse.delai,
      );
      expect(errors.reports.map((r) => r.feature), [
        'tickets.decide',
        'tickets.decide',
      ]);
    });

    test('Relancer l\'envoi : statut et Issue rendus par le serveur', () async {
      final repository = depot((name, data) async {
        calls.add((name, data));
        return {'status': 'received', 'changed': true, 'issueNumber': 12};
      });
      final resultat = await repository.retrySend('a');
      expect(calls.single.$1, 'retryTicketSend');
      expect(calls.single.$2, {'ticketId': 'a'});
      expect(resultat.status, TicketStatus.received);
      expect(resultat.issueNumber, 12);
      expect(resultat.echec, isNull);
    });

    test('relance refusée : rapportée, échec rendu', () async {
      final repository = depot(
        (name, data) async => throw FirebaseFunctionsException(
          code: 'not-found',
          message: 'Ce ticket n\'existe plus.',
          details: {
            'reason': 'Ce ticket n\'existe plus.',
            'code': 'ticket_missing',
          },
        ),
      );
      final resultat = await repository.retrySend('absent');
      expect(resultat.echec!.cause, CauseEchecReponse.motif);
      expect(errors.reports.single.feature, 'tickets.retry_send');
      expect(errors.reports.single.context, startsWith('tickets/absent '));
    });
  });

  test('décisions lues : tolérance aux valeurs inconnues', () async {
    final decisions = firestore.collection('tickets/a/decisions');
    await decisions.doc('d1').set({
      'action': 'escalate',
      'state': 'archived',
      'requested_at': Timestamp.fromDate(DateTime(2026, 11, 8)),
    });
    await decisions.doc('d2').set({
      'action': 'close',
      'state': 'failed',
      'text': 'Fait.',
      'error_reason': 'Issue non fermée.',
    });
    await decisions.doc('d3').set({
      'action': 'refuse',
      'state': 'pending',
      'text': 12,
    });
    final list = await repository.watchDecisions('a').first;
    final d1 = list.valides.singleWhere((d) => d.id == 'd1');
    expect(d1.action, isNull);
    expect(d1.state, TicketDecisionState.unknown);
    final d2 = list.valides.singleWhere((d) => d.id == 'd2');
    expect(d2.state, TicketDecisionState.failed);
    expect(d2.errorReason, 'Issue non fermée.');
    expect(
      list.documents.whereType<DocumentInvalide<TicketDecision>>().single.id,
      'd3',
    );
    expect(errors.reports.single.feature, 'tickets.read_decision');
    expect(errors.reports.single.context, isNot(contains('12')));
  });

  test('état du jeton : absent, lu, illisible', () async {
    expect(
      await repository.watchGithubStatus().first,
      isA<DocumentAbsent<EtatJetonGithub>>(),
    );
    final doc = firestore.collection('ticket_status').doc('github');
    await doc.set({
      'token_expires_at': Timestamp.fromDate(DateTime(2026, 12, 1)),
    });
    final found = await repository.watchGithubStatus().first;
    expect(
      (found as DocumentTrouve<EtatJetonGithub>).value.tokenExpiresAt,
      DateTime(2026, 12, 1),
    );
    await doc.set({'token_invalid_since': 'hier'});
    expect(
      await repository.watchGithubStatus().first,
      isA<DocumentIllisibleTrouve<EtatJetonGithub>>(),
    );
    expect(errors.reports.single.feature, 'tickets.read_github_status');
  });
}
