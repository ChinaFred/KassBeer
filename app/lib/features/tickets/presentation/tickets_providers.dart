import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../../members/presentation/members_providers.dart';
import '../domain/etat_jeton_github.dart';
import '../domain/ticket.dart';
import '../domain/ticket_analysis.dart';
import '../domain/ticket_delivery.dart';
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

/// `tickets/{id}/admin/delivery`, lu par l'administrateur seul (P45) : fiche,
/// et pastille de la liste pour un ticket En cours seulement.
final ticketDeliveryProvider = StreamProvider.autoDispose
    .family<RechercheDocument<TicketDelivery>, String>(
      (ref, ticketId) =>
          ref.watch(ticketsRepositoryProvider).watchDelivery(ticketId),
      retry: (retryCount, error) => null,
    );

/// Tickets En cours dont la PR est prête (`admin/delivery.ready`, écrit par
/// le serveur), dont aucune livraison ni correction n'est en cours et sans
/// `ticket_status/launches.ci_read_denied_since` (même lecture que la
/// pastille, [pastilleLivraison]) : ils entrent dans le filtre
/// « À traiter » de la liste seule ; le compteur du menu reste calculé sur le
/// statut (décision 7 du 2026-11-14). `admin/delivery` n'est lu que pour les
/// tickets En cours. [lu] : chaque `admin/delivery` de ces tickets a rendu
/// une lecture (document, absence ou panne) ; la liste attend ce moment pour
/// choisir son premier filtre.
final ticketsPrPreteProvider =
    Provider.autoDispose<({Set<String> ids, bool lu})>((ref) {
      final list = ref.watch(adminTicketsProvider).value;
      if (list == null) return (ids: const {}, lu: false);
      final now = ref.watch(horlogeProvider)();
      final quota = switch (ref.watch(launchStatusProvider).value) {
        DocumentTrouve(:final value) => value,
        _ => null,
      };
      final ids = <String>{};
      var lu = true;
      for (final t in list.valides) {
        if (t.status != TicketStatus.inProgress || t.issueNumber == null) {
          continue;
        }
        final async = ref.watch(ticketDeliveryProvider(t.id));
        if (async.value == null && !async.hasError) lu = false;
        final livraison = switch (async.value) {
          DocumentTrouve(:final value) => value,
          _ => null,
        };
        if (livraison == null || !livraison.ready) continue;
        final historique = switch (ref
            .watch(ticketLaunchesProvider(t.id))
            .value) {
          DocumentTrouve(:final value) => value,
          _ => null,
        };
        final pastille = pastilleLivraison(
          ticket: t,
          livraison: livraison,
          historique: historique,
          quota: quota,
          now: now,
        );
        if (pastille == PastilleLivraisonType.prPrete) ids.add(t.id);
      }
      return (ids: ids, lu: lu);
    });

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
