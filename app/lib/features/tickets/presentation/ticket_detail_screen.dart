import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/bandeau_hors_ligne.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/menu_compte.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/presentation/zone_capture.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_screens.dart';
import 'encadre_reponse.dart';
import 'frise_ticket.dart';
import 'my_tickets_screen.dart';
import 'ticket_lien_github.dart';
import 'ticket_statut.dart';
import 'tickets_providers.dart';
import 'vignette_capture.dart';

/// Textes des états du suivi d'un ticket.
const textesTicket = TextesDocument(
  chargement: 'Chargement du ticket',
  lectureImpossible: MyTicketsScreen.loadError,
  absent: 'Ce ticket n\'existe plus.',
  horsLigne: 'Ce ticket n\'est pas disponible hors ligne.',
  illisible: 'Ce ticket est illisible.',
  retour: 'Retour à mes tickets',
);

/// « Suivi d'un ticket » au téléphone : statut, réponse, frise, contenu
/// envoyé. L'ouverture d'un suivi à lire écrit `seen_by_author_at`, hors ligne
/// compris. En large, [TicketDetailPane] s'affiche à droite de la liste.
class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.id});

  final String id;

  static const titre = 'Suivi d\'un ticket';
  static const resume = 'Reprendre ce ticket';
  static const updateNeeded = 'Disponible après mise à jour';
  static const upToDate = 'Disponible dans votre version';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text(titre),
        leading: BackButton(
          onPressed: () => quitterPageTicket(context, AppRoutes.tickets),
        ),
        actions: const [MenuCompte(), SizedBox(width: 8)],
      ),
      body: ZoneCapture(
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (offline) const BandeauHorsLigne(),
              Expanded(child: TicketDetailPane(id: id)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenu du suivi de [id], seul au téléphone ou à droite de la liste de
/// « Mes tickets » en large.
class TicketDetailPane extends ConsumerWidget {
  const TicketDetailPane({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(grantedAccessProvider);
    final uid = access?.user.uid;
    if (uid == null) return const EtatChargement(label: 'Chargement du ticket');
    return PageDocument<Ticket>(
      async: ref.watch(myTicketsProvider(uid)),
      id: id,
      offline: access?.offline ?? false,
      textes: textesTicket,
      onRetry: () => ref.invalidate(myTicketsProvider(uid)),
      onBack: () => context.go(AppRoutes.tickets),
      builder: (context, ticket) =>
          _Detail(key: ValueKey(ticket.id), ticket: ticket),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({super.key, required this.ticket});

  final Ticket ticket;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  /// `status_changed_at` du dernier suivi marqué lu par cet écran : un même
  /// suivi n'est écrit qu'une fois.
  DateTime? _markedFor;

  @override
  void initState() {
    super.initState();
    _markIfUnread();
  }

  @override
  void didUpdateWidget(covariant _Detail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _markIfUnread();
  }

  void _markIfUnread() {
    final ticket = widget.ticket;
    if (!ticket.unread || _markedFor == ticket.statusChangedAt) return;
    _markedFor = ticket.statusChangedAt;
    // Le dépôt rapporte un échec ; la pastille reste allumée.
    unawaited(ref.read(ticketsRepositoryProvider).markSeen(ticket.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ticket = widget.ticket;
    final now = ref.watch(horlogeProvider)();
    final installed = ref.watch(appVersionProvider)?.split('+').first;
    final created = ticket.createdAt;
    final delivered = ticket.status == TicketStatus.delivered;
    final deliveredVersion = ticket.deliveredVersion;
    final comparison =
        delivered && deliveredVersion != null && installed != null
        ? compareVersions(installed, deliveredVersion)
        : null;
    final link = delivered ? lienGithub(ticket.deliveredPrUrl) : null;
    final reply = ticket.replyText;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    const gap = SizedBox(height: 16);

    return SelectionArea(
      child: ListView(
        // Marge basse de 96 : à côté de la liste, le bouton flottant
        // « Signaler ou proposer » ne cache pas les dernières lignes.
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          ticketTypeIcon(ticket.type),
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(ticket.type.label, style: muted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    child: Text(
                      ticket.title,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      EtiquetteStatut(ticket: ticket),
                      if (comparison != null)
                        Etiquette(
                          label: comparison < 0
                              ? TicketDetailScreen.updateNeeded
                              : TicketDetailScreen.upToDate,
                        ),
                    ],
                  ),
                  if (created != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Envoyé le ${formatDateChiffres(created)} à '
                      '${formatHeure(created)}',
                      style: muted,
                    ),
                  ],
                  gap,
                  for (final p in phrasesStatut(ticket, now))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(p, style: theme.textTheme.bodyLarge),
                    ),
                  if (link != null) ...[
                    const SizedBox(height: 8),
                    BoutonVoirSurGithub(uri: link),
                  ],
                  if (ticket.status == TicketStatus.overQuota) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => unawaited(
                        context.push(
                          AppRoutes.newTicket,
                          extra: ticket.brouillon,
                        ),
                      ),
                      icon: const Icon(Icons.replay),
                      label: const Text(TicketDetailScreen.resume),
                    ),
                  ],
                  if (reply != null) ...[
                    gap,
                    EncadreReponse(
                      titre: titreReponse(ticket.status),
                      texte: reply,
                    ),
                  ],
                  gap,
                  FriseTicket(ticket: ticket),
                  const TitreSection('Description'),
                  Text(ticket.description, style: theme.textTheme.bodyLarge),
                  if (ticket.screenshotPath case final path?) ...[
                    gap,
                    CaptureDuTicket(
                      path: path,
                      expiresAt: ticket.screenshotExpiresAt,
                    ),
                  ],
                  gap,
                  Text(
                    'Écran : ${ticketScreenLabel(ticket.screen)}',
                    style: muted,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    envoyeAvec(
                      version: ticket.appVersion,
                      platform: ticket.platform,
                    ),
                    style: muted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
