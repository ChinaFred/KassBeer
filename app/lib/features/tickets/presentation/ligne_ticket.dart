import 'package:flutter/material.dart';

import '../../../core/presentation/ligne_liste.dart';
import '../domain/ticket.dart';
import 'ticket_statut.dart';

/// Ligne d'un ticket, dans « Mes tickets » et Admin › Tickets : icône de son
/// type (lue), titre sur deux lignes au plus, [details], statut et
/// [pastilles] dessous, pastille de non-lu à droite si [nonLu].
class LigneTicket extends StatelessWidget {
  const LigneTicket({
    super.key,
    required this.ticket,
    required this.details,
    required this.selected,
    required this.onTap,
    this.pastilles = const [],
    this.nonLu = false,
  });

  /// Lecture de la pastille de non-lu.
  static const nonLuLabel = 'Nouveau suivi à lire';

  final Ticket ticket;

  /// « #12 · Zoé · 07/11/26 » ; vide : aucune ligne.
  final String details;

  /// Ticket affiché à côté de la liste, en grand écran.
  final bool selected;
  final VoidCallback onTap;

  /// Pastilles après le statut (Admin › Tickets : échéance, lancement,
  /// livraison).
  final List<Widget> pastilles;
  final bool nonLu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LigneListe(
      icone: ticketTypeIcon(ticket.type),
      iconeLabel: ticket.type.label,
      titre: ticket.title,
      titreMaxLignes: 2,
      details: [if (details.isNotEmpty) Text(details)],
      etiquettes: [
        EtiquetteStatut(ticket: ticket),
        ...pastilles,
      ],
      trailing: nonLu
          ? Semantics(
              label: nonLuLabel,
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            )
          : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
