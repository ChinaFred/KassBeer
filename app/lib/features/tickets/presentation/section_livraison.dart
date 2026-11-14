import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_delivery.dart';
import '../domain/ticket_launch.dart';
import 'encadre_reponse.dart';
import 'section_analyses.dart';
import 'section_lancements.dart';
import 'ticket_lien_github.dart';
import 'tickets_providers.dart';

/// Section « Livraison (N) » de la fiche d'Admin (ADR-008, T5, P45) :
/// comptes rendus `## Livraison — blocage` et `## Livraison — terminée`
/// relevés par le serveur, dans l'ordre chronologique, rendus en Markdown
/// avec les garde-fous de P33. Ouverte, juste après « Description ». Affichée
/// pour un ticket En cours ou Livré, ou s'il a déjà un compte rendu.
class SectionLivraison extends ConsumerWidget {
  const SectionLivraison({
    super.key,
    required this.ticket,
    required this.livrerActif,
  });

  final Ticket ticket;

  /// « Livrer » est affiché et actif dans la barre (dérivé par la fiche).
  final bool livrerActif;

  static const loadError = 'Impossible de lire la livraison.';
  static const horsLigne = 'Livraison non disponible hors ligne.';
  static const illisible = 'Livraison illisible. Mettez l\'application à jour.';
  static const vide = 'Aucun compte rendu de livraison.';
  static const invitation = 'Appuyez sur « Livrer », en bas de la fiche.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final async = ref.watch(ticketDeliveryProvider(ticket.id));
    final lecture = async.value;
    final doc = switch (lecture) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    final suivi =
        ticket.status == TicketStatus.inProgress ||
        ticket.status == TicketStatus.delivered;
    if (!suivi && (doc == null || doc.reports.isEmpty)) {
      return const SizedBox.shrink();
    }
    Widget phrase(String text, {bool erreur = false}) => Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: erreur ? scheme.error : null,
        ),
      ),
    );
    final number = ticket.issueNumber;
    final issueLink = lienGithub(ticket.issueUrl);
    List<Widget> cartes(TicketDelivery value) => [
      for (var i = 0; i < value.reports.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        _CarteCompteRendu(
          compteRendu: value.reports[i],
          ouvrirIssue: issueLink == null
              ? null
              : BoutonVoirSurGithub(
                  uri: issueLink,
                  label: number == null
                      ? 'Ouvrir l\'Issue'
                      : 'Ouvrir l\'Issue #$number',
                  contexte: 'Issue d\'un ticket',
                ),
        ),
      ],
    ];
    // Relecture en panne : la ligne et « Réessayer », sous les comptes rendus
    // déjà affichés s'il y en a.
    final panne = [
      phrase(loadError, erreur: true),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.tonal(
          onPressed: async.isLoading
              ? null
              : () => ref.invalidate(ticketDeliveryProvider(ticket.id)),
          child: async.isLoading
              ? const IndicateurBouton(label: 'Lecture en cours')
              : const Text('Réessayer'),
        ),
      ),
    ];
    final avecInvitation = livrerActif ? '$vide $invitation' : vide;
    final List<Widget> corps;
    if (async.hasError) {
      corps = [
        if (doc != null && doc.reports.isNotEmpty) ...[
          ...cartes(doc),
          const SizedBox(height: 12),
        ],
        ...panne,
      ];
    } else {
      corps = switch (lecture) {
        null => const [
          LinearProgressIndicator(semanticsLabel: 'Lecture de la livraison'),
        ],
        DocumentAbsentDuCache() =>
          offline
              ? [phrase(horsLigne)]
              : const [
                  LinearProgressIndicator(
                    semanticsLabel: 'Lecture de la livraison',
                  ),
                ],
        DocumentIllisibleTrouve() => [phrase(illisible, erreur: true)],
        DocumentAbsent() => [phrase(avecInvitation)],
        DocumentTrouve(:final value) when value.reports.isEmpty => [
          phrase(avecInvitation),
        ],
        DocumentTrouve(:final value) => cartes(value),
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TitreSection(
          doc == null ? 'Livraison' : 'Livraison (${doc.reports.length})',
        ),
        ...corps,
      ],
    );
  }
}

/// Carte d'un compte rendu, par [EncadreReponse.contenu] : blocage sur
/// `errorContainer`, livraison terminée sur la surface avec l'icône en
/// `primary`. Titre de section pour le lecteur d'écran.
class _CarteCompteRendu extends StatelessWidget {
  const _CarteCompteRendu({
    required this.compteRendu,
    required this.ouvrirIssue,
  });

  final CompteRenduLivraison compteRendu;
  final Widget? ouvrirIssue;

  static const tronque = 'Compte rendu tronqué, voir GitHub.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = compteRendu.createdAt;
    final blocage = compteRendu.type == TypeCompteRendu.blocage;
    final encre = EncadreReponse.encreDe(scheme, erreur: blocage);
    final titre = blocage
        ? (at == null
              ? 'Blocage'
              : 'Blocage du ${formatDateChiffres(at)} à ${formatHeure(at)}')
        : (at == null
              ? 'Livraison terminée'
              : 'Livraison terminée ${dateLancement(at)}');
    final bouton = ouvrirIssue;
    return EncadreReponse.contenu(
      titre: titre,
      icone: blocage ? Icons.error_outline : Icons.check_circle,
      erreur: blocage,
      couleurIcone: blocage ? null : scheme.primary,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CorpsAnalyse(texte: corpsCompteRendu(compteRendu.body), encre: encre),
          if (compteRendu.truncated) ...[
            const SizedBox(height: 8),
            Text(
              tronque,
              style: theme.textTheme.bodyMedium?.copyWith(color: encre),
            ),
            if (bouton != null) ...[
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerStart, child: bouton),
            ],
          ],
        ],
      ),
    );
  }
}

/// Pastille de la liste d'Admin › Tickets pour un ticket En cours :
/// « Livraison en cours », « Correction en cours », « CI en cours » ou « PR
/// prête » (une seule). Lit `admin/delivery` et `admin/launches` de ce seul
/// ticket.
class PastilleLivraison extends ConsumerWidget {
  const PastilleLivraison({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ticket.status != TicketStatus.inProgress ||
        ticket.issueNumber == null) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(horlogeProvider)();
    final livraison = switch (ref
        .watch(ticketDeliveryProvider(ticket.id))
        .value) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    final historique = switch (ref
        .watch(ticketLaunchesProvider(ticket.id))
        .value) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    final quota = switch (ref.watch(launchStatusProvider).value) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    final type = pastilleLivraison(
      ticket: ticket,
      livraison: livraison,
      historique: historique,
      quota: quota,
      now: now,
    );
    final verrou = quota?.deliveryRunning;
    final enCours = historique?.enCours(ActionLancement.livraison, now);
    final since =
        enCours?.at ??
        (verrou?.ticketId == ticket.id ? verrou?.launchedAt : null);
    final echeance =
        enCours?.retryAfter ??
        (verrou?.ticketId == ticket.id ? verrou?.retryAfter : null);
    return switch (type) {
      null => const SizedBox.shrink(),
      PastilleLivraisonType.livraisonEnCours => ReconstruireA(
        instant: echeance,
        child: Semantics(
          label: since == null
              ? 'Livraison en cours'
              : ligneEnCours(ActionLancement.livraison, since, now),
          excludeSemantics: true,
          child: const Etiquette(
            label: 'Livraison en cours',
            icon: Icons.hourglass_top,
            ton: TonEtiquette.neutre,
          ),
        ),
      ),
      PastilleLivraisonType.correctionEnCours => ReconstruireA(
        instant: historique?.enCours(ActionLancement.reprise, now)?.retryAfter,
        child: Semantics(
          label: 'Correction de la pull request en cours',
          excludeSemantics: true,
          child: const Etiquette(
            label: 'Correction en cours',
            icon: Icons.hourglass_top,
            ton: TonEtiquette.neutre,
          ),
        ),
      ),
      PastilleLivraisonType.ciEnCours => Semantics(
        label: 'CI de la pull request en cours',
        excludeSemantics: true,
        child: const Etiquette(
          label: 'CI en cours',
          icon: Icons.schedule,
          ton: TonEtiquette.neutre,
        ),
      ),
      PastilleLivraisonType.prPrete => Semantics(
        label: 'Pull request prête à livrer',
        excludeSemantics: true,
        child: const Etiquette(
          label: 'PR prête',
          icon: Icons.local_shipping_outlined,
          ton: TonEtiquette.tertiaire,
        ),
      ),
    };
  }
}
