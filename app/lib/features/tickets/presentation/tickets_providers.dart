import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../../members/presentation/members_providers.dart';
import '../domain/etat_jeton_github.dart';
import '../domain/ticket.dart';
import '../domain/ticket_analysis.dart';
import '../domain/ticket_launch.dart';

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

/// Tous les tickets, lus par l'administrateur seul (Admin › Tickets, compteur
/// du menu, bandeau).
final adminTicketsProvider = StreamProvider.autoDispose<ListeLue<Ticket>>(
  (ref) => ref.watch(ticketsRepositoryProvider).watchAll(),
  retry: (retryCount, error) => null,
);

/// Nombre de tickets « À traiter » ([Ticket.toProcess]) pour l'administrateur ;
/// 0 pour un brasseur ou tant que la liste n'est pas lue.
final ticketsToProcessCountProvider = Provider.autoDispose<int>((ref) {
  final isAdmin = ref.watch(grantedAccessProvider)?.member.isAdmin ?? false;
  if (!isAdmin) return 0;
  final list = ref.watch(adminTicketsProvider).value;
  if (list == null) return 0;
  return list.valides.where((t) => t.toProcess).length;
});

/// Décisions d'un ticket, lues par l'administrateur seul.
final ticketDecisionsProvider = StreamProvider.autoDispose
    .family<ListeLue<TicketDecision>, String>(
      (ref, ticketId) =>
          ref.watch(ticketsRepositoryProvider).watchDecisions(ticketId),
      retry: (retryCount, error) => null,
    );

/// `tickets/{id}/admin/analysis`, lu par l'administrateur seul (ADR-008).
final ticketAnalysisProvider = StreamProvider.autoDispose
    .family<RechercheDocument<TicketAnalysisDoc>, String>(
      (ref, ticketId) =>
          ref.watch(ticketsRepositoryProvider).watchAnalysis(ticketId),
      retry: (retryCount, error) => null,
    );

/// `tickets/{id}/admin/launches`, lu par l'administrateur seul (P41) : fiche,
/// et pastille de la liste pour un ticket dont un lancement est permis.
final ticketLaunchesProvider = StreamProvider.autoDispose
    .family<RechercheDocument<TicketLaunchesDoc>, String>(
      (ref, ticketId) =>
          ref.watch(ticketsRepositoryProvider).watchLaunches(ticketId),
      retry: (retryCount, error) => null,
    );

/// `ticket_status/launches`, lu par l'administrateur seul (P41) : compteur
/// de la liste, quota de la boîte, jetons des routines du bandeau.
final launchStatusProvider =
    StreamProvider.autoDispose<RechercheDocument<EtatLancements>>(
      (ref) => ref.watch(ticketsRepositoryProvider).watchLaunchStatus(),
      retry: (retryCount, error) => null,
    );

/// Nom déclaré de chaque membre (`members/{email}.display_name`), par e-mail,
/// pour l'auteur d'un ticket. Vide tant que la liste n'est pas lue ou si elle
/// ne peut pas l'être : l'écran montre alors l'adresse.
final memberNamesProvider = Provider.autoDispose<Map<String, String>>((ref) {
  final members = ref.watch(membersListProvider).value;
  if (members == null) return const {};
  return {for (final m in members) m.email: ?m.displayName};
});

/// Ouvre une adresse dans le navigateur ou l'application GitHub ; rend faux si
/// le système refuse. Remplacée dans les tests.
final ouvrirLienProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
