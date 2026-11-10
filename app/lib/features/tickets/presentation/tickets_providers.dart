import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/etat_jeton_github.dart';
import '../domain/ticket.dart';

/// Tickets du compte [uid], lus avec le cache hors ligne.
final myTicketsProvider = StreamProvider.autoDispose
    .family<ListeLue<Ticket>, String>(
      (ref, uid) => ref.watch(ticketsRepositoryProvider).watchMine(uid),
      // Une panne s'affiche ; « Réessayer » relance la lecture.
      retry: (retryCount, error) => null,
    );

/// Nombre de tickets du membre connecté dont le suivi est à lire
/// ([Ticket.unread]) ; 0 tant que la liste n'est pas lue.
final unreadTicketsCountProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(grantedAccessProvider)?.user.uid;
  if (uid == null) return 0;
  final list = ref.watch(myTicketsProvider(uid)).value;
  if (list == null) return 0;
  return list.valides.where((t) => t.unread).length;
});

/// `ticket_status/github`, lu par l'administrateur seul.
final githubStatusProvider =
    StreamProvider.autoDispose<RechercheDocument<EtatJetonGithub>>(
      (ref) => ref.watch(ticketsRepositoryProvider).watchGithubStatus(),
      retry: (retryCount, error) => null,
    );

/// Tickets `pending` ou `send_failed`, lus par l'administrateur seul.
final notSentTicketsProvider = StreamProvider.autoDispose<ListeLue<Ticket>>(
  (ref) => ref.watch(ticketsRepositoryProvider).watchNotSent(),
  retry: (retryCount, error) => null,
);

/// Tickets dont l'Issue a disparu, lus par l'administrateur seul.
final issueMissingTicketsProvider =
    StreamProvider.autoDispose<ListeLue<Ticket>>(
      (ref) => ref.watch(ticketsRepositoryProvider).watchIssueMissing(),
      retry: (retryCount, error) => null,
    );

/// Ouvre une adresse dans le navigateur ou l'application GitHub ; rend faux si
/// le système refuse. Remplacée dans les tests.
final ouvrirLienProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
