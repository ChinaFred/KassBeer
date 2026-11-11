import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../domain/etat_jeton_github.dart';
import '../domain/ticket.dart';
import 'tickets_providers.dart';

/// Message du bandeau des tickets d'Admin.
typedef MessageBandeau = ({String text, bool error});

/// Panne de lecture de la liste des tickets : comptée par la tuile d'Admin,
/// absente du bandeau d'Admin › Tickets, où la liste ou la fiche affiche déjà
/// « Impossible de lire les tickets. ».
const kPanneComptageTickets = 'Impossible de compter les tickets bloqués.';

/// Messages du bandeau : jeton refusé, expiré ou proche de l'échéance,
/// tickets non transmis, Issues disparues. Liste vide quand tout va bien.
List<MessageBandeau> messagesBandeauTickets({
  required AsyncValue<RechercheDocument<EtatJetonGithub>> status,
  required AsyncValue<ListeLue<Ticket>> tickets,
  required DateTime now,
}) {
  final messages = <MessageBandeau>[];
  final lookup = status.value;
  if (lookup == null && status.hasError) {
    messages.add((
      text: 'Impossible de lire l\'état du jeton GitHub.',
      error: true,
    ));
  }
  switch (lookup) {
    case DocumentTrouve<EtatJetonGithub>(:final value):
      final invalid = value.tokenInvalidSince;
      final expires = value.tokenExpiresAt;
      if (invalid != null) {
        messages.add((
          text:
              'Jeton GitHub refusé ou expiré depuis le '
              '${formatDateChiffres(invalid)} : remplacez GITHUB_TICKETS_TOKEN '
              'dans Secret Manager.',
          error: true,
        ));
      } else if (expires != null && expires.isBefore(now)) {
        messages.add((
          text: 'Le jeton GitHub a expiré le ${formatDateChiffres(expires)}.',
          error: true,
        ));
      } else if (expires != null &&
          expires.difference(now) <= kTokenExpiryWarning) {
        messages.add((
          text: 'Le jeton GitHub expire le ${formatDateChiffres(expires)}.',
          error: false,
        ));
      }
    // Sans échéance (jeton sans expiration : GitHub n'envoie pas l'en-tête),
    // le bandeau ne dit rien de l'expiration.
    case DocumentIllisibleTrouve<EtatJetonGithub>():
      messages.add((text: 'État du jeton GitHub illisible.', error: true));
    case DocumentAbsent<EtatJetonGithub>() ||
        DocumentAbsentDuCache<EtatJetonGithub>() ||
        null:
      break;
  }

  final list = tickets.value;
  if (list == null && tickets.hasError) {
    messages.add((text: kPanneComptageTickets, error: true));
  } else if (list != null) {
    final valid = list.valides;
    final notSent = valid
        .where((t) => t.status == TicketStatus.sendFailed || t.isLate(now))
        .length;
    if (notSent > 0) {
      messages.add((
        text: notSent == 1
            ? '1 ticket n\'est pas arrivé sur GitHub.'
            : '$notSent tickets ne sont pas arrivés sur GitHub.',
        error: true,
      ));
    }
    final missing = valid.where((t) => t.issueMissingSince != null).length;
    if (missing > 0) {
      messages.add((
        text: missing == 1
            ? '1 ticket dont l\'Issue a disparu.'
            : '$missing tickets dont l\'Issue a disparu.',
        error: true,
      ));
    }
  }
  return messages;
}

/// Messages du bandeau pour l'administrateur ; leur nombre est aussi la
/// pastille de la tuile « Tickets des membres » d'Admin.
final messagesBandeauTicketsProvider =
    Provider.autoDispose<List<MessageBandeau>>(
      (ref) => messagesBandeauTickets(
        status: ref.watch(githubStatusProvider),
        tickets: ref.watch(adminTicketsProvider),
        now: ref.watch(horlogeProvider)(),
      ),
    );

/// Bandeau des tickets en tête d'Admin › Tickets (liste et fiche), lu par
/// l'administrateur seul (le routeur réserve Admin à son rôle, les règles
/// réservent `ticket_status/`). Borné au tiers de la hauteur, défilant
/// au-delà.
class BandeauTicketsAdmin extends ConsumerWidget {
  const BandeauTicketsAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = [
      for (final m in ref.watch(messagesBandeauTicketsProvider))
        if (m.text != kPanneComptageTickets) m,
    ];
    if (messages.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height / 3,
        ),
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in messages)
                  Material(
                    color: m.error
                        ? scheme.errorContainer
                        : scheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ExcludeSemantics(
                            child: Icon(
                              m.error ? Icons.error_outline : Icons.schedule,
                              color: m.error
                                  ? scheme.onErrorContainer
                                  : scheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              m.text,
                              style: TextStyle(
                                color: m.error
                                    ? scheme.onErrorContainer
                                    : scheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
