import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../tickets/domain/ticket.dart';
import '../../../core/providers.dart';
import '../domain/ticket_depuis_panne.dart';

/// « Analyser » et marque « Ticket #N créé le… » d'Admin › Rapports d'erreur
/// et d'Admin › Journaux (ticket #67). La marque se dérive des tickets, lus
/// une fois (`get()`) : rien n'est écrit sur le rapport, et aucun écouteur ne
/// tourne sur ces écrans (P50).

/// Tickets par rapport ou entrée de journal, lus une fois à l'ouverture de
/// l'écran et relus par [ref.invalidate] (« Actualiser », « Rechercher »).
/// Sans valeur (lecture en cours ou en échec, panne rapportée par le dépôt de
/// données), aucune marque.
final marquesPannesProvider =
    FutureProvider.autoDispose<Map<ClePanne, MarquePanne>>((ref) async {
      final liste = await ref.watch(ticketsRepositoryProvider).readAll();
      return indexTicketsParPanne(liste.valides);
    }, retry: (retryCount, error) => null);

/// Marques lues ; `null` pendant la première lecture et après une panne,
/// même si une lecture précédente avait réussi.
Map<ClePanne, MarquePanne>? _marques(
  AsyncValue<Map<ClePanne, MarquePanne>> lu,
) => lu.hasError ? null : lu.value;

abstract final class TextesAnalyser {
  static const analyser = 'Analyser';
  static const creerSecond = 'Créer un second ticket';

  /// « Un ticket existe déjà pour ce rapport (#12). Créer un second
  /// ticket ? ».
  static String doublon(NaturePanne nature, MarquePanne marque) {
    final cible = switch (nature) {
      NaturePanne.rapport => 'ce rapport',
      NaturePanne.journal => 'cette entrée',
    };
    final numero = marque.recent.issueNumber;
    final reference = numero == null ? '' : ' (#$numero)';
    return 'Un ticket existe déjà pour $cible$reference. Créer un second '
        'ticket ?';
  }
}

/// Ouvre « Signaler ou proposer » prérempli par [brouillon] ; si [cle] a déjà
/// un ticket, une boîte le demande d'abord.
Future<void> ouvrirAnalyse(
  BuildContext context,
  WidgetRef ref, {
  required ClePanne? cle,
  required NaturePanne nature,
  required TicketBrouillon brouillon,
}) async {
  final router = GoRouter.of(context);
  final marque = cle == null
      ? null
      : _marques(ref.read(marquesPannesProvider))?[cle];
  if (marque != null) {
    // ticket: /admin/rapports-erreur/fenetre/doublon, /admin/journaux/fenetre/doublon
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(TextesAnalyser.doublon(nature, marque)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(TextesAnalyser.creerSecond),
          ),
        ],
      ),
    );
    if (confirme != true) return;
  }
  unawaited(
    router.push(AppRoutes.newTicket, extra: BrouillonAnalyse(brouillon)),
  );
}

/// Boutons d'une ligne dépliée : [copier] puis « Analyser », l'un sous
/// l'autre sur une ligne trop étroite.
class BoutonsPanne extends StatelessWidget {
  const BoutonsPanne({super.key, required this.copier, required this.analyser});

  final Widget copier;
  final VoidCallback analyser;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      copier,
      OutlinedButton.icon(
        onPressed: analyser,
        icon: const Icon(Icons.manage_search),
        label: const Text(TextesAnalyser.analyser),
      ),
    ],
  );
}

/// Marque d'une ligne repliée, ou rien si [cle] n'a pas de ticket. Un appui
/// ouvre la fiche du ticket le plus récent.
class MarqueTicketPanne extends ConsumerWidget {
  const MarqueTicketPanne({super.key, required this.cle});

  final ClePanne? cle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cle = this.cle;
    final marque = cle == null
        ? null
        : ref.watch(marquesPannesProvider.select((m) => _marques(m)?[cle]));
    if (marque == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          textStyle: theme.textTheme.bodyMedium,
        ),
        onPressed: () => unawaited(
          GoRouter.of(context).push(AppRoutes.adminTicket(marque.recent.id)),
        ),
        icon: const Icon(Icons.confirmation_number_outlined, size: 18),
        label: Text(marque.libelle),
      ),
    );
  }
}
