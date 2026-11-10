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

/// Messages du bandeau : jeton refusé ou proche de l'échéance, tickets non
/// transmis, Issues disparues. Liste vide quand tout va bien.
List<MessageBandeau> messagesBandeauTickets({
  required AsyncValue<RechercheDocument<EtatJetonGithub>> status,
  required AsyncValue<ListeLue<Ticket>> notSent,
  required AsyncValue<ListeLue<Ticket>> issueMissing,
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
      } else if (expires == null) {
        messages.add((
          text: 'Date d\'expiration du jeton GitHub inconnue.',
          error: false,
        ));
      } else if (expires.isBefore(now)) {
        messages.add((
          text: 'Le jeton GitHub a expiré le ${formatDateChiffres(expires)}.',
          error: true,
        ));
      } else if (expires.difference(now) <= kTokenExpiryWarning) {
        messages.add((
          text: 'Le jeton GitHub expire le ${formatDateChiffres(expires)}.',
          error: false,
        ));
      }
    case DocumentIllisibleTrouve<EtatJetonGithub>():
      messages.add((text: 'État du jeton GitHub illisible.', error: true));
    case DocumentAbsent<EtatJetonGithub>() ||
        DocumentAbsentDuCache<EtatJetonGithub>() ||
        null:
      break;
  }

  final notSentList = notSent.value;
  if (notSentList == null && notSent.hasError) {
    messages.add((
      text: 'Impossible de compter les tickets non transmis.',
      error: true,
    ));
  } else if (notSentList != null) {
    final count = notSentList.valides.where((t) {
      if (t.status == TicketStatus.sendFailed) return true;
      final created = t.createdAt;
      return t.status == TicketStatus.pending &&
          created != null &&
          now.difference(created) > kTicketSendDelay;
    }).length;
    if (count > 0) {
      messages.add((
        text: count == 1
            ? '1 ticket n\'est pas arrivé sur GitHub.'
            : '$count tickets ne sont pas arrivés sur GitHub.',
        error: true,
      ));
    }
  }

  final missingList = issueMissing.value;
  if (missingList == null && issueMissing.hasError) {
    messages.add((
      text: 'Impossible de compter les tickets dont l\'Issue a disparu.',
      error: true,
    ));
  } else if (missingList != null) {
    final count = missingList.valides.length;
    if (count > 0) {
      messages.add((
        text: count == 1
            ? '1 ticket dont l\'Issue a disparu.'
            : '$count tickets dont l\'Issue a disparu.',
        error: true,
      ));
    }
  }
  return messages;
}

/// Bandeau des tickets en tête d'Admin, lu par l'administrateur seul (le
/// routeur réserve Admin à son rôle, les règles réservent `ticket_status/`).
class BandeauTicketsAdmin extends ConsumerWidget {
  const BandeauTicketsAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = messagesBandeauTickets(
      status: ref.watch(githubStatusProvider),
      notSent: ref.watch(notSentTicketsProvider),
      issueMissing: ref.watch(issueMissingTicketsProvider),
      now: ref.watch(horlogeProvider)(),
    );
    if (messages.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
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
    );
  }
}
