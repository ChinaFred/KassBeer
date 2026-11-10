import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/bandeau_hors_ligne.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_screens.dart';
import 'my_tickets_screen.dart';
import 'ticket_lien_github.dart';
import 'ticket_statut.dart';
import 'tickets_providers.dart';

/// Textes des états du suivi d'un ticket.
const textesTicket = TextesDocument(
  chargement: 'Chargement du ticket',
  lectureImpossible: MyTicketsScreen.loadError,
  absent: 'Ce ticket n\'existe plus.',
  horsLigne: 'Ce ticket n\'est pas disponible hors ligne.',
  illisible: 'Ce ticket est illisible.',
  retour: 'Retour à mes tickets',
);

/// « Suivi d'un ticket » : statut, réponse, contenu envoyé. L'ouverture d'un
/// suivi à lire écrit `seen_by_author_at`, hors ligne compris.
class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.id});

  final String id;

  static const titre = 'Suivi d\'un ticket';
  static const resume = 'Reprendre ce ticket';
  static const replyTitle = 'Réponse de l\'administrateur';
  static const updateNeeded = 'Disponible après mise à jour';
  static const upToDate = 'Disponible dans votre version';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(grantedAccessProvider);
    final uid = access?.user.uid;
    final offline = access?.offline ?? false;
    final Widget body = uid == null
        ? const EtatChargement(label: 'Chargement du ticket')
        : PageDocument<Ticket>(
            async: ref.watch(myTicketsProvider(uid)),
            id: id,
            offline: offline,
            textes: textesTicket,
            onRetry: () => ref.invalidate(myTicketsProvider(uid)),
            onBack: () => context.go(AppRoutes.tickets),
            builder: (context, ticket) =>
                _Detail(key: ValueKey(ticket.id), ticket: ticket),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text(titre),
        leading: BackButton(
          onPressed: () => quitterPageTicket(context, AppRoutes.tickets),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offline) const BandeauHorsLigne(),
            Expanded(child: body),
          ],
        ),
      ),
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
        padding: const EdgeInsets.all(16),
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
                  if (reply != null) ...[gap, _Reponse(text: reply)],
                  gap,
                  Semantics(
                    header: true,
                    child: Text(
                      'Description',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(ticket.description, style: theme.textTheme.bodyLarge),
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

/// Encadré « Réponse de l'administrateur ».
class _Reponse extends StatelessWidget {
  const _Reponse({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  TicketDetailScreen.replyTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
