import 'package:flutter/material.dart';

import '../domain/ticket.dart';
import 'ticket_statut.dart';

/// Étape de la frise d'un ticket. [erreur] : l'étape actuelle est un échec
/// (envoi impossible, limite du jour), son icône prend la couleur d'erreur.
typedef EtapeFrise = ({String label, IconData icon, bool erreur});

/// Étapes de la frise de [ticket] et rang de l'étape actuelle ; `null` pour un
/// statut inconnu (pas de frise).
({List<EtapeFrise> etapes, int actuelle})? etapesFrise(Ticket ticket) {
  EtapeFrise etape(TicketStatus status, {bool erreur = false}) {
    final s = statutAfficheDe(status);
    return (label: s.label, icon: s.icon, erreur: erreur);
  }

  final envoi = ticket.waitingForNetwork
      ? (label: 'En attente du réseau', icon: Icons.cloud_off, erreur: false)
      : etape(TicketStatus.pending);
  final recu = etape(TicketStatus.received);
  final suivi = [
    envoi,
    recu,
    etape(TicketStatus.validated),
    etape(TicketStatus.inProgress),
    etape(TicketStatus.delivered),
  ];
  return switch (ticket.status) {
    TicketStatus.pending => (etapes: suivi, actuelle: 0),
    TicketStatus.received => (etapes: suivi, actuelle: 1),
    TicketStatus.validated => (etapes: suivi, actuelle: 2),
    TicketStatus.inProgress => (etapes: suivi, actuelle: 3),
    TicketStatus.delivered => (etapes: suivi, actuelle: 4),
    TicketStatus.refused => (
      etapes: [envoi, recu, etape(TicketStatus.refused)],
      actuelle: 2,
    ),
    TicketStatus.closed => (
      etapes: [envoi, recu, etape(TicketStatus.closed)],
      actuelle: 2,
    ),
    TicketStatus.sendFailed => (
      etapes: [envoi, etape(TicketStatus.sendFailed, erreur: true)],
      actuelle: 1,
    ),
    TicketStatus.overQuota => (
      etapes: [envoi, etape(TicketStatus.overQuota, erreur: true)],
      actuelle: 1,
    ),
    TicketStatus.unknown => null,
  };
}

/// Frise verticale des étapes d'un ticket (suivi du membre, fiche d'Admin).
///
/// Étape passée : coche ; étape actuelle : icône du statut, texte en gras ;
/// étape à venir : cercle vide. Chaque étape est lue d'un bloc (« Reçu : étape
/// passée »). Rien pour un statut inconnu.
class FriseTicket extends StatelessWidget {
  const FriseTicket({super.key, required this.ticket});

  final Ticket ticket;

  static String libelleEtape(String label, int rang, int actuelle) =>
      rang < actuelle
      ? '$label : étape passée'
      : rang == actuelle
      ? '$label : étape actuelle'
      : '$label : à venir';

  @override
  Widget build(BuildContext context) {
    final frise = etapesFrise(ticket);
    if (frise == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final etapes = frise.etapes;
    final actuelle = frise.actuelle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < etapes.length; i++)
          Semantics(
            container: true,
            label: libelleEtape(etapes[i].label, i, actuelle),
            excludeSemantics: true,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 24,
                    child: Column(
                      children: [
                        Icon(
                          i < actuelle
                              ? Icons.check_circle
                              : i == actuelle
                              ? etapes[i].icon
                              : Icons.radio_button_unchecked,
                          size: 24,
                          color: i > actuelle
                              ? scheme.outline
                              : etapes[i].erreur
                              ? scheme.error
                              : scheme.primary,
                        ),
                        if (i < etapes.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: i < actuelle
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 12),
                      child: Text(
                        etapes[i].label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: i == actuelle ? FontWeight.w600 : null,
                          color: i > actuelle
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
