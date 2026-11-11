import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/tickets/data/tickets_repository.dart';
import 'package:kass_beer/features/tickets/domain/etat_jeton_github.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';

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

  test(
    'décision : champs du contrat seuls, sans le texte au rapport',
    () async {
      await firestore.collection('tickets').doc('a').set({
        'status': 'received',
      });
      await repository.createDecision(
        ticketId: 'a',
        id: 'd1',
        action: TicketDecisionAction.refuse,
        text: 'Hors du périmètre.',
        requestedByUid: 'uid-admin',
      );
      await repository.createDecision(
        ticketId: 'a',
        id: 'd2',
        action: TicketDecisionAction.validate,
        text: null,
        requestedByUid: 'uid-admin',
      );
      final decisions = firestore.collection('tickets/a/decisions');
      final d1 = (await decisions.doc('d1').get()).data()!;
      expect(d1.keys.toSet(), {
        'action',
        'text',
        'state',
        'requested_by_uid',
        'requested_at',
      });
      expect(d1['action'], 'refuse');
      expect(d1['state'], 'pending');
      expect(d1['requested_at'], isA<Timestamp>());
      final d2 = (await decisions.doc('d2').get()).data()!;
      expect(d2.containsKey('text'), isFalse);
      expect(repository.newDecisionId('a'), isNotEmpty);
    },
  );

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

  test('relances : retry_requested_at seul', () async {
    final ticket = firestore.collection('tickets').doc('a');
    await ticket.set({'status': 'send_failed'});
    await ticket.collection('decisions').doc('d1').set({'state': 'failed'});
    expect(await repository.retrySend('a'), isTrue);
    expect(
      await repository.retryDecision(ticketId: 'a', decisionId: 'd1'),
      isTrue,
    );
    expect(
      (await ticket.get()).data()!['retry_requested_at'],
      isA<Timestamp>(),
    );
    expect(
      (await ticket.collection('decisions').doc('d1').get())
          .data()!['retry_requested_at'],
      isA<Timestamp>(),
    );
  });

  test('relance refusée : rapportée sans texte, rend faux', () async {
    expect(await repository.retrySend('absent'), isFalse);
    expect(errors.reports.single.feature, 'tickets.retry_send');
    expect(errors.reports.single.context, startsWith('tickets/absent '));
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
