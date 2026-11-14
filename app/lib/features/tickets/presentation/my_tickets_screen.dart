import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/presentation/page_secondaire.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import 'ligne_ticket.dart';
import 'ticket_detail_screen.dart';
import 'tickets_providers.dart';

/// Retour d'une page de ticket ouverte par `push` : l'écran précédent, sinon
/// [fallback] (adresse ouverte directement).
void quitterPageTicket(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Liste et suivi côte à côte dans « Mes tickets » : fenêtre d'au moins
/// [kExpandedMinWidth] (page pleine, sans rail).
bool mesTicketsCoteACote(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kExpandedMinWidth;

/// « Mes tickets » : tickets du membre, du plus récent au plus ancien.
///
/// Fenêtre d'au moins [kExpandedMinWidth] : la liste à gauche
/// ([kListeMesTicketsWidth]) et le suivi [selectedId] à droite, ouvert par
/// `replace` : la page garde sa clé (ni transition ni défilement perdu) et la
/// pile ouverte par `push` reste, la flèche retour ramène à l'écran d'origine. En dessous : la liste seule, ou le suivi seul si [selectedId] est
/// donné, ouvert par `push`.
class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key, this.selectedId});

  final String? selectedId;

  static const titre = 'Mes tickets';
  static const loadError = 'Impossible de lire vos tickets.';
  static const emptyMessage =
      'Aucun ticket pour l\'instant. Un bug, une idée ? Envoyez-les à '
      'l\'administrateur.';
  static const unreadLabel = LigneTicket.nonLuLabel;
  static const noSelection = 'Choisissez un ticket pour voir son suivi.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = mesTicketsCoteACote(context);
    final selected = selectedId;
    if (!wide && selected != null) return TicketDetailScreen(id: selected);
    void open(String id) {
      if (wide) {
        context.replace(AppRoutes.ticket(id));
      } else {
        unawaited(context.push(AppRoutes.ticket(id)));
      }
    }

    final access = ref.watch(grantedAccessProvider);
    final uid = access?.user.uid;
    final offline = access?.offline ?? false;
    void create() => unawaited(context.push(AppRoutes.newTicket));

    final Widget body;
    // L'état vide porte son propre « Signaler ou proposer » : pas de bouton
    // flottant en plus.
    var empty = false;
    if (uid == null) {
      body = const EtatChargement(label: 'Chargement de vos tickets');
    } else {
      final async = ref.watch(myTicketsProvider(uid));
      final list = async.value;
      void retry() => ref.invalidate(myTicketsProvider(uid));
      if (list == null) {
        body = async.hasError
            ? EtatErreur(
                message: loadError,
                retrying: async.isLoading,
                retryingLabel: 'Lecture en cours',
                onRetry: retry,
              )
            : const EtatChargement(label: 'Chargement de vos tickets');
      } else {
        empty = _estVide(list, stale: async.hasError);
        body = _Liste(
          list: list,
          stale: async.hasError,
          retrying: async.isLoading,
          onRetry: retry,
          onCreate: create,
          selectedId: selected,
          onOpen: open,
        );
      }
    }

    return PageSecondaire(
      titre: titre,
      horsLigne: offline,
      // Grand écran : la liste et le suivi côte à côte, sur toute la largeur.
      largeurMax: null,
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: kListeMesTicketsWidth, child: body),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selected == null
                      ? const EtatVide(
                          icon: Icons.confirmation_number_outlined,
                          message: noSelection,
                        )
                      : TicketDetailPane(key: ValueKey(selected), id: selected),
                ),
              ],
            )
          : body,
      floatingActionButton: empty
          ? null
          : FloatingActionButton.extended(
              onPressed: create,
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('Signaler ou proposer'),
            ),
    );
  }
}

/// Aucun ticket, ni lisible ni illisible, et aucune panne à signaler.
bool _estVide(ListeLue<Ticket> list, {required bool stale}) =>
    list.documents.isEmpty && !stale;

class _Liste extends StatelessWidget {
  const _Liste({
    required this.list,
    required this.stale,
    required this.retrying,
    required this.onRetry,
    required this.onCreate,
    required this.selectedId,
    required this.onOpen,
  });

  final ListeLue<Ticket> list;
  final bool stale;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onCreate;
  final String? selectedId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final tickets = list.valides..sort(compareTicketsRecentFirst);
    final invalid = list.documents.whereType<DocumentInvalide<Ticket>>();
    if (_estVide(list, stale: stale)) {
      return EtatVide(
        icon: Icons.confirmation_number_outlined,
        message: MyTicketsScreen.emptyMessage,
        action: FilledButton(
          onPressed: onCreate,
          child: const Text('Signaler ou proposer'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: kMargeBoutonFlottant),
      children: [
        if (stale) BandeauListePerimee(retrying: retrying, onRetry: onRetry),
        for (final t in tickets)
          LigneTicket(
            ticket: t,
            details: t.createdAt == null
                ? ''
                : formatDateChiffres(t.createdAt!),
            selected: t.id == selectedId,
            nonLu: t.unread,
            onTap: () => onOpen(t.id),
          ),
        for (final d in invalid)
          LigneListe(
            icone: Icons.error_outline,
            erreur: true,
            titre: 'Ticket illisible',
            details: const [
              Text(
                'Mettez l\'application à jour, ou prévenez '
                'l\'administrateur.',
              ),
            ],
            selected: d.id == selectedId,
            onTap: () => onOpen(d.id),
          ),
      ],
    );
  }
}
