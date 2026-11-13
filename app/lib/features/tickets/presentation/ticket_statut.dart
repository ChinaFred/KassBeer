import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
      ton: TonEtiquette.neutre,
    );
  }
  return statutAfficheDe(ticket.status);
}

/// Étiquette d'un statut stocké (frise, liste d'Admin).
StatutAffiche statutAfficheDe(TicketStatus status) => switch (status) {
  TicketStatus.pending => (
    label: 'Envoi en cours',
    icon: Icons.schedule_send_outlined,
    ton: TonEtiquette.neutre,
  ),
  TicketStatus.received => (
    label: 'Reçu',
    icon: Icons.mark_email_read_outlined,
    ton: TonEtiquette.primaire,
  ),
  TicketStatus.analyzed => (
    label: 'Analysé',
    icon: Icons.manage_search,
    ton: TonEtiquette.primaire,
  ),
  TicketStatus.validated => (
    label: 'Validé',
    icon: Icons.thumb_up_alt_outlined,
    ton: TonEtiquette.primaire,
  ),
  TicketStatus.inProgress => (
    label: 'En cours',
    icon: Icons.construction_outlined,
    ton: TonEtiquette.tertiaire,
  ),
  TicketStatus.delivered => (
    label: 'Livré',
    icon: Icons.check_circle_outline,
    ton: TonEtiquette.primaire,
  ),
  TicketStatus.refused => (
    label: 'Refusé',
    icon: Icons.block,
    ton: TonEtiquette.neutre,
  ),
  TicketStatus.closed => (
    label: 'Clos',
    icon: Icons.archive_outlined,
    ton: TonEtiquette.normal,
  ),
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
    ton: TonEtiquette.neutre,
  ),
};

/// Étiquette du statut de [ticket].
///
/// [clignoteAuChangement] (fiche d'Admin seule) : quand le statut change, la
/// pastille fait trois pulsations d'opacité en 1 200 ms, jamais au premier
/// affichage ni avec les animations réduites, et « Statut : … » est annoncé
/// aux lecteurs d'écran dans tous les cas.
class EtiquetteStatut extends StatefulWidget {
  const EtiquetteStatut({
    super.key,
    required this.ticket,
    this.clignoteAuChangement = false,
  });

  final Ticket ticket;
  final bool clignoteAuChangement;

  /// Durée des trois pulsations.
  static const dureeClignotement = Duration(milliseconds: 1200);

  @override
  State<EtiquetteStatut> createState() => _EtiquetteStatutState();
}

class _EtiquetteStatutState extends State<EtiquetteStatut>
    with SingleTickerProviderStateMixin {
  /// Créé seulement pour une étiquette qui clignote.
  AnimationController? _controller;

  AnimationController _controleur() => _controller ??= AnimationController(
    vsync: this,
    duration: EtiquetteStatut.dureeClignotement,
  );

  @override
  void initState() {
    super.initState();
    if (widget.clignoteAuChangement) _controleur();
  }

  @override
  void didUpdateWidget(covariant EtiquetteStatut oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.clignoteAuChangement) return;
    final before = statutAffiche(oldWidget.ticket).label;
    final now = statutAffiche(widget.ticket).label;
    if (before == now) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Statut : $now',
        Directionality.of(context),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return;
    unawaited(_controleur().forward(from: 0));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = statutAffiche(widget.ticket);
    final pill = Etiquette(label: s.label, icon: s.icon, ton: s.ton);
    if (!widget.clignoteAuChangement) return pill;
    return FadeTransition(
      opacity: _controleur().drive(_pulsations),
      child: pill,
    );
  }
}

/// Trois pulsations d'opacité (1 → 0,35 → 1), puis fixe.
final Animatable<double> _pulsations = TweenSequence<double>([
  for (var i = 0; i < 3; i++) ...[
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.35), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.35, end: 1.0), weight: 1),
  ],
]);

/// Titre de l'encadré du texte de l'administrateur, selon le statut.
String titreReponse(TicketStatus status) => switch (status) {
  TicketStatus.refused => 'Motif du refus',
  TicketStatus.closed => 'Commentaire de clôture',
  _ => 'Réponse de l\'administrateur',
};

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
    TicketStatus.analyzed => const ['Votre ticket a été lu et étudié.'],
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
