import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/features/tickets/domain/etat_jeton_github.dart';
import 'package:kass_beer/features/tickets/domain/ticket.dart';
import 'package:kass_beer/features/tickets/domain/ticket_launch.dart';
import 'package:kass_beer/features/tickets/presentation/bandeau_tickets_admin.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_lien_github.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_statut.dart';

import 'support/ticket_fixtures.dart';

void main() {
  final now = DateTime(2026, 11, 20, 12);

  group('Ticket.fromFirestore', () {
    Map<String, dynamic> doc([Map<String, dynamic> extra = const {}]) => {
      'type': 'bug',
      'title': 'Densité fausse',
      'description': 'La densité affichée est fausse.',
      'screen': '/recettes/:id',
      'status': 'received',
      'app_version': '0.2.0',
      'platform': 'android',
      'author_uid': 'uid-brasseur',
      'author_email': 'brasseur@exemple.fr',
      'created_at': Timestamp.fromDate(DateTime(2026, 11, 8, 9, 30)),
      ...extra,
    };

    test('lit les champs du contrat', () {
      final t = Ticket.fromFirestore(
        't1',
        doc({
          'status': 'delivered',
          'delivered_version': '0.2.3',
          'delivered_pr_url': 'https://github.com/ChinaFred/KassBeer/pull/12',
          'delivered_pr_number': 12,
          'reply_text': 'Corrigé.',
          'status_changed_at': Timestamp.fromDate(DateTime(2026, 11, 9)),
        }),
      );
      expect(t.type, TicketType.bug);
      expect(t.status, TicketStatus.delivered);
      expect(t.screen, '/recettes/:id');
      expect(t.createdAt, DateTime(2026, 11, 8, 9, 30));
      expect(t.deliveredVersion, '0.2.3');
      expect(t.replyText, 'Corrigé.');
      expect(t.appVersion, '0.2.0');
    });

    test(
      'chaque statut connu est lu, une valeur inconnue devient inconnue',
      () {
        for (final s in TicketStatus.values) {
          if (s == TicketStatus.unknown) continue;
          expect(
            Ticket.fromFirestore('t', doc({'status': s.storedValue})).status,
            s,
          );
        }
        expect(
          Ticket.fromFirestore('t', doc({'status': 'archived'})).status,
          TicketStatus.unknown,
        );
      },
    );

    test('type inconnu, titre absent, champ mal typé : illisible', () {
      for (final bad in [
        doc({'type': 'question'}),
        doc({'title': null}),
        doc({'status': 3}),
        doc({'created_at': 'hier'}),
        doc({'reply_text': 12}),
        doc({'delivered_pr_number': 1.5}),
      ]) {
        expect(
          () => Ticket.fromFirestore('t', bad),
          throwsA(isA<DocumentIllisible>()),
        );
      }
    });

    test('création en attente : heure de l\'appareil, sinon aucune date', () {
      final pending = doc({'created_at': null, 'status': 'pending'});
      expect(Ticket.fromFirestore('t', pending).createdAt, isNull);
      expect(
        Ticket.fromFirestore(
          't',
          pending,
          createdOnDevice: DateTime(2026, 11, 8, 10),
        ).createdAt,
        DateTime(2026, 11, 8, 10),
      );
    });
  });

  group('suivi à lire', () {
    final changed = DateTime(2026, 11, 10);

    test('statut changé après la dernière lecture', () {
      expect(unTicket(statusChangedAt: changed).unread, isTrue);
      expect(
        unTicket(
          statusChangedAt: changed,
          seenByAuthorAt: changed.subtract(const Duration(minutes: 1)),
        ).unread,
        isTrue,
      );
    });

    test('déjà lu, ou lecture en attente du serveur : rien à lire', () {
      expect(
        unTicket(
          statusChangedAt: changed,
          seenByAuthorAt: changed.add(const Duration(seconds: 1)),
        ).unread,
        isFalse,
      );
      expect(
        unTicket(statusChangedAt: changed, hasPendingWrites: true).unread,
        isFalse,
      );
    });

    test('pending et received sans changement de statut : rien à lire', () {
      expect(unTicket(status: TicketStatus.pending).unread, isFalse);
      expect(
        unTicket(status: TicketStatus.pending, statusChangedAt: changed).unread,
        isFalse,
      );
      expect(unTicket(status: TicketStatus.received).unread, isFalse);
    });
  });

  test('comparaison de versions', () {
    expect(compareVersions('0.2.1', '0.2.3'), lessThan(0));
    expect(compareVersions('0.2.3', '0.2.3'), 0);
    expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareVersions('0.2.3+14', '0.2.3'), 0);
    expect(compareVersions('0.2', '0.2.3'), isNull);
    expect(compareVersions('abc', '0.2.3'), isNull);
  });

  test('tri : création en attente d\'abord, puis la plus récente', () {
    final list = [
      unTicket(id: 'ancien', createdAt: DateTime(2026, 11, 1)),
      unTicket(id: 'attente', createdAt: null),
      unTicket(id: 'recent', createdAt: DateTime(2026, 11, 9)),
    ]..sort(compareTicketsRecentFirst);
    expect(list.map((t) => t.id), ['attente', 'recent', 'ancien']);
  });

  group('lienGithub', () {
    test('https sur github.com : ouvert', () {
      expect(
        lienGithub('https://github.com/ChinaFred/KassBeer/pull/12'),
        Uri.parse('https://github.com/ChinaFred/KassBeer/pull/12'),
      );
    });

    test('tout le reste : refusé', () {
      for (final url in [
        null,
        'http://github.com/ChinaFred/KassBeer/pull/12',
        'https://github.com.exemple.fr/pull/12',
        'https://gist.github.com/x',
        'https://exemple.fr@github.com/x',
        'https://user@github.com/x',
        'https://github.com:8443/x',
        'javascript:alert(1)',
        'intent://github.com/x',
        '',
      ]) {
        expect(lienGithub(url), isNull, reason: url);
      }
    });
  });

  group('statuts affichés', () {
    test('chaque statut a son étiquette et sa phrase', () {
      final expected = {
        TicketStatus.pending: 'Envoi en cours',
        TicketStatus.received: 'Reçu',
        TicketStatus.validated: 'Validé',
        TicketStatus.inProgress: 'En cours',
        TicketStatus.delivered: 'Livré',
        TicketStatus.refused: 'Refusé',
        TicketStatus.closed: 'Clos',
        TicketStatus.sendFailed: 'Envoi impossible',
        TicketStatus.overQuota: 'Limite du jour atteinte',
        TicketStatus.unknown: 'Statut inconnu',
      };
      for (final e in expected.entries) {
        final t = unTicket(status: e.key);
        expect(statutAffiche(t).label, e.value);
        expect(phrasesStatut(t, now), isNotEmpty);
      }
      expect(
        statutAffiche(unTicket(status: TicketStatus.sendFailed)).ton,
        TonEtiquette.erreur,
      );
      expect(
        statutAffiche(unTicket(status: TicketStatus.overQuota)).ton,
        TonEtiquette.erreur,
      );
    });

    test('création sur l\'appareil seul : « En attente du réseau »', () {
      final t = unTicket(status: TicketStatus.pending, hasPendingWrites: true);
      expect(statutAffiche(t).label, 'En attente du réseau');
      expect(phrasesStatut(t, now).single, contains('retour du réseau'));
    });

    test('pending depuis plus d\'une heure : retard annoncé', () {
      final t = unTicket(
        status: TicketStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 61)),
      );
      expect(
        phrasesStatut(t, now),
        contains('La transmission prend du retard.'),
      );
      final recent = unTicket(
        status: TicketStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 30)),
      );
      expect(phrasesStatut(recent, now), hasLength(1));
    });

    test('livré avec ou sans version', () {
      expect(
        phrasesStatut(
          unTicket(status: TicketStatus.delivered, deliveredVersion: '0.2.3'),
          now,
        ),
        ['C\'est fait. Livré dans la version 0.2.3.'],
      );
      expect(phrasesStatut(unTicket(status: TicketStatus.delivered), now), [
        'C\'est fait.',
      ]);
    });

    test('aucune phrase ne cite un plafond chiffré ni GitHub', () {
      for (final s in TicketStatus.values) {
        for (final p in phrasesStatut(unTicket(status: s), now)) {
          expect(p, isNot(matches(RegExp(r'\b(5|20)\b'))));
          expect(p, isNot(contains('Issue')));
          expect(p, isNot(contains('PR')));
        }
      }
    });
  });

  group('bandeau Admin', () {
    List<MessageBandeau> messages({
      RechercheDocument<EtatJetonGithub>? status,
      AsyncValue<RechercheDocument<EtatLancements>> launches =
          const AsyncLoading(),
      List<Ticket> notSent = const [],
      List<Ticket> missing = const [],
    }) => messagesBandeauTickets(
      status: status == null ? const AsyncLoading() : AsyncData(status),
      launches: launches,
      tickets: AsyncData(
        ListeLue(
          documents: [
            for (final t in [...notSent, ...missing]) DocumentValide(t.id, t),
          ],
          fromCache: false,
        ),
      ),
      now: now,
    );

    test('document absent, jeton valide loin de l\'échéance : rien', () {
      expect(messages(status: const DocumentAbsent()), isEmpty);
      expect(
        messages(
          status: DocumentTrouve(
            EtatJetonGithub(tokenExpiresAt: now.add(const Duration(days: 15))),
          ),
        ),
        isEmpty,
      );
    });

    test('jeton refusé', () {
      final m = messages(
        status: DocumentTrouve(
          EtatJetonGithub(tokenInvalidSince: DateTime(2026, 11, 18)),
        ),
      );
      expect(
        m.single.text,
        'Jeton GitHub refusé ou expiré depuis le 18/11/26 : remplacez '
        'GITHUB_TICKETS_TOKEN dans Secret Manager.',
      );
      expect(m.single.error, isTrue);
    });

    test('échéance à 14 jours ou moins ; sans échéance, rien', () {
      final soon = messages(
        status: DocumentTrouve(
          EtatJetonGithub(tokenExpiresAt: now.add(const Duration(days: 14))),
        ),
      );
      expect(soon.single.text, 'Le jeton GitHub expire le 04/12/26.');
      expect(soon.single.error, isFalse);
      // Jeton sans expiration : rien sur l'échéance.
      expect(
        messages(status: const DocumentTrouve(EtatJetonGithub())),
        isEmpty,
      );
    });

    test('échéance passée : « a expiré le »', () {
      final past = messages(
        status: DocumentTrouve(
          EtatJetonGithub(tokenExpiresAt: DateTime(2026, 11, 19)),
        ),
      );
      expect(past.single.text, 'Le jeton GitHub a expiré le 19/11/26.');
      expect(past.single.error, isTrue);
    });

    test('phrases envoi impossible et limite du jour', () {
      expect(
        phrasesStatut(unTicket(status: TicketStatus.sendFailed), now).single,
        endsWith('L\'administrateur est prévenu.'),
      );
      expect(
        phrasesStatut(unTicket(status: TicketStatus.overQuota), now).single,
        'Ce ticket n\'a pas été transmis : la limite de tickets du jour était '
        'atteinte. Reprenez-le demain avec le bouton ci-dessous.',
      );
    });

    test('document illisible', () {
      expect(
        messages(
          status: const DocumentIllisibleTrouve(
            DocumentIllisible('token_expires_at', 'date attendue'),
          ),
        ).single.text,
        'État du jeton GitHub illisible.',
      );
    });

    test(
      'tickets non transmis : send_failed, ou pending depuis plus d\'1 h',
      () {
        final m = messages(
          status: const DocumentAbsent(),
          notSent: [
            unTicket(id: 'a', status: TicketStatus.sendFailed),
            unTicket(
              id: 'b',
              status: TicketStatus.pending,
              createdAt: now.subtract(const Duration(hours: 2)),
            ),
            unTicket(
              id: 'c',
              status: TicketStatus.pending,
              createdAt: now.subtract(const Duration(minutes: 10)),
            ),
          ],
          missing: [
            unTicket(id: 'd', issueMissingSince: DateTime(2026, 11, 19)),
            unTicket(id: 'e'),
          ],
        );
        expect(m.map((e) => e.text), [
          '2 tickets ne sont pas arrivés sur GitHub.',
          '1 ticket dont l\'Issue a disparu.',
        ]);
      },
    );

    test('liste illisible : panne annoncée', () {
      final m = messagesBandeauTickets(
        status: const AsyncData(DocumentAbsent()),
        launches: const AsyncData(DocumentAbsent()),
        tickets: AsyncError(StateError('refusé'), StackTrace.empty),
        now: now,
      );
      expect(m.single.text, 'Impossible de compter les tickets bloqués.');
    });

    test('routines : jetons refusés, en ton d\'erreur', () {
      final m = messages(
        status: const DocumentAbsent(),
        launches: AsyncData(
          DocumentTrouve(
            EtatLancements(
              day: '20261108',
              countDay: 10,
              perDay: 10,
              analysisInvalidSince: DateTime(2026, 11, 7),
              developmentInvalidSince: DateTime(2026, 11, 6),
            ),
          ),
        ),
      );
      expect(m.map((e) => e.text), [
        'Jeton de la routine d\'analyse refusé depuis le 07/11/26. '
            'Remplacez-le dans Secret Manager.',
        'Jeton de la routine de développement refusé depuis le 06/11/26. '
            'Remplacez-le dans Secret Manager.',
      ]);
      expect(m.every((e) => e.error), isTrue);
    });

    test('routines : plafond atteint sans ligne, pannes annoncées', () {
      expect(
        messages(
          status: const DocumentAbsent(),
          launches: const AsyncData(
            DocumentTrouve(
              EtatLancements(day: '20261108', countDay: 10, perDay: 10),
            ),
          ),
        ),
        isEmpty,
      );
      expect(
        messages(
          status: const DocumentAbsent(),
          launches: AsyncError(StateError('refusé'), StackTrace.empty),
        ).single,
        (text: 'Impossible de lire l\'état des lancements.', error: true),
      );
      expect(
        messages(
          status: const DocumentAbsent(),
          launches: const AsyncData(
            DocumentIllisibleTrouve(DocumentIllisible('day', 'mal formé')),
          ),
        ).single,
        (text: 'État des lancements illisible.', error: true),
      );
    });
  });
}
