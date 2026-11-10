import 'package:flutter/material.dart';

import '../../../core/presentation/etiquette.dart';
import '../domain/ticket.dart';

/// Icône du type d'un ticket.
IconData ticketTypeIcon(TicketType type) => switch (type) {
  TicketType.bug => Icons.bug_report_outlined,
  TicketType.evolution => Icons.tune,
  TicketType.feature => Icons.lightbulb_outline,
};

/// Présentation d'un statut : étiquette, icône, ton.
typedef StatutAffiche = ({String label, IconData icon, TonEtiquette ton});

/// Étiquette du statut de [ticket]. « En attente du réseau » se dérive de la
/// création encore sur l'appareil ; elle n'est jamais stockée.
StatutAffiche statutAffiche(Ticket ticket) {
  if (ticket.waitingForNetwork) {
    return (
      label: 'En attente du réseau',
      icon: Icons.cloud_off,
      ton: TonEtiquette.normal,
    );
  }
  const normal = TonEtiquette.normal;
  return switch (ticket.status) {
    TicketStatus.pending => (
      label: 'Envoi en cours',
      icon: Icons.schedule_send,
      ton: normal,
    ),
    TicketStatus.received => (label: 'Reçu', icon: Icons.inbox, ton: normal),
    TicketStatus.validated => (
      label: 'Validé',
      icon: Icons.thumb_up_outlined,
      ton: normal,
    ),
    TicketStatus.inProgress => (
      label: 'En cours',
      icon: Icons.build_outlined,
      ton: normal,
    ),
    TicketStatus.delivered => (
      label: 'Livré',
      icon: Icons.check_circle_outline,
      ton: normal,
    ),
    TicketStatus.refused => (label: 'Refusé', icon: Icons.block, ton: normal),
    TicketStatus.closed => (label: 'Clos', icon: Icons.task_alt, ton: normal),
    TicketStatus.sendFailed => (
      label: 'Envoi impossible',
      icon: Icons.error_outline,
      ton: TonEtiquette.erreur,
    ),
    TicketStatus.overQuota => (
      label: 'Limite du jour atteinte',
      icon: Icons.event_busy,
      ton: TonEtiquette.erreur,
    ),
    TicketStatus.unknown => (
      label: 'Statut inconnu',
      icon: Icons.help_outline,
      ton: normal,
    ),
  };
}

/// Étiquette du statut de [ticket].
class EtiquetteStatut extends StatelessWidget {
  const EtiquetteStatut({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final s = statutAffiche(ticket);
    return Etiquette(label: s.label, icon: s.icon, ton: s.ton);
  }
}

/// Phrase du statut de [ticket], affichée dans le détail. [now] : heure de
/// l'appareil, pour dire qu'une transmission prend du retard.
List<String> phrasesStatut(Ticket ticket, DateTime now) {
  if (ticket.waitingForNetwork) {
    return const [
      'Votre ticket est enregistré sur cet appareil. Il partira au retour du '
          'réseau.',
    ];
  }
  return switch (ticket.status) {
    TicketStatus.pending => [
      'Votre ticket est enregistré. Il sera transmis à l\'administrateur dans '
          'quelques minutes.',
      if (ticket.createdAt case final created?
          when now.difference(created) > kTicketSendDelay)
        'La transmission prend du retard.',
    ],
    TicketStatus.received => const ['L\'administrateur a reçu votre ticket.'],
    TicketStatus.validated => const ['Votre demande sera traitée.'],
    TicketStatus.inProgress => const ['Le travail a commencé.'],
    TicketStatus.delivered => [
      switch (ticket.deliveredVersion) {
        final version? => 'C\'est fait. Livré dans la version $version.',
        null => 'C\'est fait.',
      },
    ],
    TicketStatus.refused => const ['Cette demande ne sera pas traitée.'],
    TicketStatus.closed => const ['Ce ticket est clos.'],
    TicketStatus.sendFailed => const [
      'Votre ticket n\'a pas pu être transmis. Il reste enregistré dans '
          'l\'application. L\'administrateur est prévenu.',
    ],
    TicketStatus.overQuota => const [
      'Ce ticket n\'a pas été transmis : la limite de tickets du jour était '
          'atteinte. Reprenez-le demain avec le bouton ci-dessous.',
    ],
    TicketStatus.unknown => const [
      'Mettez l\'application à jour pour lire ce statut.',
    ],
  };
}

/// Plateforme affichée : « Android », « web », ou la valeur reçue.
String libellePlateforme(String? platform) => switch (platform) {
  'android' => 'Android',
  'web' => 'web',
  null => 'plateforme inconnue',
  final other => other,
};

/// « Envoyé avec : version 0.2.0, Android ».
String envoyeAvec({required String? version, required String? platform}) =>
    'Envoyé avec : '
    '${version == null ? 'version indisponible' : 'version $version'}, '
    '${libellePlateforme(platform)}';
