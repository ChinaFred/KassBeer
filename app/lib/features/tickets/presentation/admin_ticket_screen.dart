import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_screens.dart';
import 'admin_tickets_screen.dart';
import 'bandeau_tickets_admin.dart';
import 'encadre_reponse.dart';
import 'frise_ticket.dart';
import 'ticket_lien_github.dart';
import 'ticket_statut.dart';
import 'tickets_providers.dart';

/// Textes des états de la fiche d'un ticket d'Admin.
const textesTicketAdmin = TextesDocument(
  chargement: 'Chargement du ticket',
  lectureImpossible: AdminTicketsScreen.loadError,
  absent: 'Ce ticket n\'existe plus.',
  horsLigne: 'Ce ticket n\'est pas disponible hors ligne.',
  illisible: 'Ticket illisible. Mettez l\'application à jour.',
  retour: 'Retour aux tickets',
);

/// Nom d'une décision dans les phrases de l'écran ; une action inconnue de
/// cette version se dit « Décision ».
({String nom, bool feminin}) nomDecision(TicketDecisionAction? action) =>
    action == null
    ? (nom: 'Décision', feminin: true)
    : (nom: action.nom, feminin: action.feminin);

/// Écriture de [action] faite sur l'appareil hors ligne : « Refus enregistré
/// sur cet appareil. Il partira au retour du réseau. ».
String phraseHorsLigne(TicketDecisionAction? action) {
  final (:nom, :feminin) = nomDecision(action);
  return '$nom enregistré${feminin ? 'e' : ''} sur cet appareil. '
      '${feminin ? 'Elle' : 'Il'} partira au retour du réseau.';
}

/// Relance d'un envoi ou d'une décision faite sur l'appareil hors ligne.
const kRelanceEnvoiHorsLigne =
    'Nouvel essai enregistré sur cet appareil. Il partira au retour du '
    'réseau.';

/// Phrase au-dessus de « Réessayer » et des décisions après un échec.
const kApresEchec = 'Réessayez, ou prenez une autre décision.';

/// Ligne d'état de la dernière décision, au-dessus des boutons.
typedef LigneDecision = ({
  IconData? icon,
  bool error,
  bool progress,
  String text,
  bool retry,
});

/// Ligne d'état de [decision] (la plus récente), ou `null` quand il n'y a rien
/// à dire (décision appliquée). [offline] : l'appareil est hors ligne ;
/// [ticketLease] : bail du ticket, à défaut de celui de la décision.
LigneDecision? ligneDecision(
  TicketDecision decision, {
  required bool offline,
  required DateTime now,
  required DateTime? ticketLease,
}) {
  final (:nom, :feminin) = nomDecision(decision.action);
  final e = feminin ? 'e' : '';
  final petit = nom.toLowerCase();
  final ce = feminin ? 'cette' : 'ce';
  final le = feminin ? 'La' : 'Le';
  if (decision.hasPendingWrites && offline) {
    // Une reprise demandée hors ligne laisse la décision `failed` dans le
    // cache, avec `retry_requested_at` en attente : c'est un nouvel essai, pas
    // une création.
    return (
      icon: Icons.cloud_off,
      error: false,
      progress: false,
      text: decision.state == TicketDecisionState.failed
          ? kRelanceEnvoiHorsLigne
          : phraseHorsLigne(decision.action),
      retry: false,
    );
  }
  switch (decision.state) {
    case TicketDecisionState.pending || TicketDecisionState.applying:
      final lease = decision.leaseUntil ?? ticketLease;
      if (decision.state == TicketDecisionState.applying &&
          lease != null &&
          lease.isBefore(now)) {
        return (
          icon: Icons.schedule,
          error: false,
          progress: false,
          text:
              '$nom interrompu$e. Le serveur ${feminin ? 'la' : 'le'} '
              'reprendra dans l\'heure.',
          retry: false,
        );
      }
      final requested = decision.requestedAt;
      final late =
          decision.state == TicketDecisionState.pending &&
          !decision.hasPendingWrites &&
          requested != null &&
          now.difference(requested) > kDecisionPendingDelay;
      return (
        icon: null,
        error: false,
        progress: true,
        text: late
            ? 'Le serveur n\'a pas encore pris $ce $petit en compte.'
            : '$nom en cours sur GitHub.',
        retry: false,
      );
    case TicketDecisionState.applied:
      return null;
    case TicketDecisionState.rejected:
      return (
        icon: Icons.info_outline,
        error: false,
        progress: false,
        text: decision.errorReason ?? 'Le serveur a écarté $ce $petit.',
        retry: false,
      );
    case TicketDecisionState.failed:
      final reason = decision.errorReason;
      return (
        icon: Icons.error_outline,
        error: true,
        progress: false,
        text: reason == null
            ? '$le $petit n\'a pas abouti.'
            : '$le $petit n\'a pas abouti : $reason',
        retry: true,
      );
    case TicketDecisionState.unknown:
      return (
        icon: Icons.help_outline,
        error: false,
        progress: false,
        text: 'État de la décision inconnu. Mettez l\'application à jour.',
        retry: false,
      );
  }
}

/// Ligne de l'historique : « Refus demandé le 11/11/26 à 10:02 · Appliqué ».
String ligneHistorique(TicketDecision decision) {
  final (:nom, :feminin) = nomDecision(decision.action);
  final e = feminin ? 'e' : '';
  final requested = decision.requestedAt;
  final quand = requested == null
      ? 'sur cet appareil'
      : 'le ${formatDateChiffres(requested)} à ${formatHeure(requested)}';
  final reason = decision.errorReason;
  final etat = switch (decision.state) {
    TicketDecisionState.pending => 'En attente',
    TicketDecisionState.applying => 'En cours',
    TicketDecisionState.applied => 'Appliqué$e',
    TicketDecisionState.rejected =>
      reason == null
          ? 'Refusé$e par le serveur'
          : 'Refusé$e par le serveur : $reason',
    TicketDecisionState.failed => reason == null ? 'Échec' : 'Échec : $reason',
    TicketDecisionState.unknown => 'État inconnu',
  };
  return '$nom demandé$e $quand · $etat';
}

/// Fiche « Ticket d'un membre » d'Admin › Tickets : contenu, frise,
/// historique des décisions, barre de décision selon `allowed_decisions`.
///
/// [avecBandeau] : le bandeau des tickets en tête (téléphone) ; à côté de la
/// liste, il est déjà au-dessus des deux panneaux.
class AdminTicketScreen extends ConsumerWidget {
  const AdminTicketScreen({
    super.key,
    required this.id,
    this.avecBandeau = true,
  });

  final String id;
  final bool avecBandeau;

  static const titre = 'Ticket d\'un membre';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final page = PageDocument<Ticket>(
      async: ref.watch(adminTicketsProvider),
      id: id,
      offline: offline,
      textes: textesTicketAdmin,
      onRetry: () => ref.invalidate(adminTicketsProvider),
      onBack: () => context.go(AppRoutes.adminTickets),
      builder: (context, ticket) =>
          _Fiche(key: ValueKey(ticket.id), ticket: ticket),
    );
    // Material propre : l'encre de « Décisions (N) » se peint sur lui, pas
    // sous le fond de la transition de page.
    final fiche = Material(type: MaterialType.transparency, child: page);
    if (!avecBandeau) return fiche;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BandeauTicketsAdmin(),
        Expanded(child: fiche),
      ],
    );
  }
}

/// Brouillons et décision écrite d'une fiche, hors de l'état du widget : un
/// changement de disposition (liste et fiche côte à côte, ou fiche seule)
/// reconstruit la fiche sans perdre le texte saisi ni la décision en cours.
typedef EtatDecisionsFiche = ({
  Map<TicketDecisionAction, String> brouillons,
  TicketDecision? ecrite,
});

/// Brouillons d'un refus ou d'une clôture, et décision écrite par cet appareil
/// en attendant que la lecture des décisions la rende.
class DecisionsFicheNotifier extends Notifier<EtatDecisionsFiche> {
  DecisionsFicheNotifier(this.ticketId);

  final String ticketId;

  @override
  EtatDecisionsFiche build() => (brouillons: const {}, ecrite: null);

  void garderBrouillon(TicketDecisionAction action, String text) => state = (
    brouillons: {...state.brouillons, action: text},
    ecrite: state.ecrite,
  );

  /// Écrit la décision (dans le cache dès l'appel) ; vrai si le serveur
  /// l'accepte. Un refus est rapporté par le dépôt, sans le texte (P13), et
  /// le brouillon revient.
  Future<bool> ecrire({
    required TicketDecisionAction action,
    required String? text,
    required String requestedByUid,
  }) async {
    final repository = ref.read(ticketsRepositoryProvider);
    final id = repository.newDecisionId(ticketId);
    final written = repository.createDecision(
      ticketId: ticketId,
      id: id,
      action: action,
      text: text,
      requestedByUid: requestedByUid,
    );
    state = (
      brouillons: {...state.brouillons}..remove(action),
      ecrite: TicketDecision(
        id: id,
        action: action,
        state: TicketDecisionState.pending,
        text: text,
        hasPendingWrites: true,
      ),
    );
    final accepted = await written;
    if (accepted || !ref.mounted) return accepted;
    state = (
      brouillons: {...state.brouillons, action: ?text},
      ecrite: state.ecrite?.id == id ? null : state.ecrite,
    );
    return false;
  }
}

final decisionsFicheProvider = NotifierProvider.autoDispose
    .family<DecisionsFicheNotifier, EtatDecisionsFiche, String>(
      DecisionsFicheNotifier.new,
    );

class _Fiche extends ConsumerStatefulWidget {
  const _Fiche({super.key, required this.ticket});

  final Ticket ticket;

  @override
  ConsumerState<_Fiche> createState() => _FicheState();
}

class _FicheState extends ConsumerState<_Fiche> {
  bool _relanceEnvoi = false;
  bool _relanceDecision = false;

  static const decisionNotSaved = 'Décision non enregistrée. Réessayez.';
  static const retryNotSaved = 'Relance non enregistrée. Réessayez.';
  static const decisionsLoadError = 'Impossible de lire les décisions.';

  Ticket get _ticket => widget.ticket;

  List<TicketDecision> _decisions(
    ListeLue<TicketDecision>? list,
    TicketDecision? ecrite,
  ) {
    final decisions = [...?list?.valides];
    if (ecrite != null && !decisions.any((d) => d.id == ecrite.id)) {
      decisions.add(ecrite);
    }
    return decisions..sort(compareDecisionsRecentFirst);
  }

  Future<void> _valider() async {
    final avant = _avantBoite();
    if (avant == null) return;
    final ok = await confirmerAction(
      context,
      titre: 'Valider ce ticket ?',
      paragraphes: const [
        'L\'étiquette « validé » sera posée sur l\'Issue. Le membre verra '
            '« Validé ».',
      ],
      libelle: 'Valider',
    );
    if (!ok) return;
    await _ecrire(avant, TicketDecisionAction.validate, null);
  }

  Future<void> _demanderTexte(
    TicketDecisionAction action,
    List<TicketDecision> decisions,
  ) async {
    // Après un rejet ou un échec, la boîte reprend le texte envoyé.
    String? previous;
    for (final d in decisions) {
      if (d.action != action) continue;
      if (d.state == TicketDecisionState.rejected ||
          d.state == TicketDecisionState.failed) {
        previous = d.text;
      }
      break;
    }
    final avant = _avantBoite();
    if (avant == null) return;
    final initial =
        ref.read(decisionsFicheProvider(_ticket.id)).brouillons[action] ??
        previous ??
        '';
    final text = await showFeuilleOuDialogue<String>(
      context: context,
      fermetureProtegee: true,
      builder: (context) => FormulaireDecision(
        action: action,
        enCours: _ticket.status == TicketStatus.inProgress,
        initial: initial,
        onChanged: (t) => avant.fiche.garderBrouillon(action, t),
      ),
    );
    if (text == null) return;
    await _ecrire(avant, action, text);
  }

  /// Ce dont une écriture a besoin, lu avant d'ouvrir une boîte : si la
  /// fenêtre change de disposition pendant la saisie, cet état est détruit,
  /// mais le fournisseur reste (la nouvelle fiche l'écoute) et l'écriture
  /// part quand même. `null` sans compte connecté.
  ({
    DecisionsFicheNotifier fiche,
    String uid,
    ScaffoldMessengerState messenger,
  })?
  _avantBoite() {
    final uid = ref.read(grantedAccessProvider)?.user.uid;
    if (uid == null) return null;
    return (
      fiche: ref.read(decisionsFicheProvider(_ticket.id).notifier),
      uid: uid,
      messenger: ScaffoldMessenger.of(context),
    );
  }

  /// L'écriture locale est faite dès l'appel : la boîte est fermée, les
  /// boutons disparaissent. Un refus est rapporté par le dépôt, sans le texte
  /// (P13) ; le brouillon revient et l'écran l'annonce.
  static Future<void> _ecrire(
    ({
      DecisionsFicheNotifier fiche,
      String uid,
      ScaffoldMessengerState messenger,
    })
    avant,
    TicketDecisionAction action,
    String? text,
  ) async {
    final accepted = await avant.fiche.ecrire(
      action: action,
      text: text,
      requestedByUid: avant.uid,
    );
    if (accepted) return;
    avant.messenger.hideCurrentSnackBar();
    avant.messenger.showSnackBar(
      const SnackBar(content: Text(decisionNotSaved)),
    );
  }

  /// Relance d'un envoi ou d'une décision. Hors ligne, l'écriture attend le
  /// réseau : l'écran le dit au lieu de garder « Relance en cours ».
  Future<void> _relancer(
    Future<bool> Function() write,
    void Function(bool) setBusy,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => setBusy(true));
    // Un refus est rapporté par le dépôt ; l'écran l'annonce.
    final accepted = await write();
    if (!mounted) return;
    setState(() => setBusy(false));
    if (accepted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text(retryNotSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ticket = _ticket;
    final now = ref.watch(horlogeProvider)();
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final names = ref.watch(memberNamesProvider);
    final decisionsAsync = ref.watch(ticketDecisionsProvider(ticket.id));
    final decisions = _decisions(
      decisionsAsync.value,
      ref.watch(decisionsFicheProvider(ticket.id)).ecrite,
    );
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    const gap = SizedBox(height: 16);
    final number = ticket.issueNumber;
    final issueLink = lienGithub(ticket.issueUrl);
    final prLink = ticket.status == TicketStatus.delivered
        ? lienGithub(ticket.deliveredPrUrl)
        : null;
    final prNumber = ticket.deliveredPrNumber;
    final created = ticket.createdAt;
    final reply = ticket.replyText;
    final missing = ticket.issueMissingSince;

    final contenu = <Widget>[
      Row(
        children: [
          ExcludeSemantics(
            child: Icon(
              ticketTypeIcon(ticket.type),
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(ticket.type.label, style: muted)),
        ],
      ),
      const SizedBox(height: 8),
      Semantics(
        header: true,
        child: Text(ticket.title, style: theme.textTheme.headlineSmall),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          EtiquetteStatut(ticket: ticket, clignoteAuChangement: true),
          if (number != null) Text('Issue #$number', style: muted),
          ...pastillesAdmin(ticket, now),
        ],
      ),
      if (issueLink != null || prLink != null) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (issueLink != null)
              BoutonVoirSurGithub(
                uri: issueLink,
                label: number == null
                    ? 'Ouvrir l\'Issue'
                    : 'Ouvrir l\'Issue #$number',
                contexte: 'Issue d\'un ticket',
              ),
            if (prLink != null)
              BoutonVoirSurGithub(
                uri: prLink,
                label: prNumber == null
                    ? 'Ouvrir la PR'
                    : 'Ouvrir la PR #$prNumber',
                contexte: 'PR d\'un ticket livré',
              ),
          ],
        ),
      ],
      if (ticket.status == TicketStatus.sendFailed) ...[
        gap,
        _EnvoiImpossible(
          ticket: ticket,
          busy: _relanceEnvoi,
          offline: offline,
          onRetry: () => _relancer(
            () => ref.read(ticketsRepositoryProvider).retrySend(ticket.id),
            (v) => _relanceEnvoi = v,
          ),
        ),
      ],
      if (missing != null) ...[
        gap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(Icons.link_off, color: scheme.error)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Issue introuvable sur GitHub depuis le '
                '${formatDateChiffres(missing)}. Vérifiez qu\'elle n\'a pas '
                'été supprimée.',
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ),
      ],
      if (reply != null) ...[
        gap,
        EncadreReponse(titre: titreReponse(ticket.status), texte: reply),
      ],
      gap,
      FriseTicket(ticket: ticket),
      const SizedBox(height: 8),
      Text('Auteur : ${auteurTicket(ticket, names)}', style: muted),
      if (created != null) ...[
        const SizedBox(height: 4),
        Text(
          'Envoyé le ${formatDateChiffres(created)} à ${formatHeure(created)}',
          style: muted,
        ),
      ],
      const SizedBox(height: 4),
      Text(
        envoyeAvec(version: ticket.appVersion, platform: ticket.platform),
        style: muted,
      ),
      const SizedBox(height: 4),
      Text('Écran : ${ticketScreenLabel(ticket.screen)}', style: muted),
      const TitreSection('Description'),
      Text(ticket.description, style: theme.textTheme.bodyLarge),
      if (decisionsAsync.value == null && decisionsAsync.hasError) ...[
        gap,
        Semantics(
          liveRegion: true,
          child: Text(
            decisionsLoadError,
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonal(
            onPressed: decisionsAsync.isLoading
                ? null
                : () => ref.invalidate(ticketDecisionsProvider(ticket.id)),
            child: decisionsAsync.isLoading
                ? const IndicateurBouton(label: 'Lecture en cours')
                : const Text('Réessayer'),
          ),
        ),
      ] else if (decisions.isNotEmpty) ...[
        gap,
        SectionRepliable(
          titre: 'Décisions (${decisions.length})',
          storageKey: 'decisions-${ticket.id}',
          children: [
            for (final d in decisions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(ligneHistorique(d)),
              ),
          ],
        ),
      ],
    ];

    // Décisions en lecture : une barre de progression à la place de la barre
    // de décision ; illisibles : aucun bouton, la panne est dans la fiche.
    final Widget? barre = switch (decisionsAsync) {
      AsyncValue(value: null, hasError: false) => const LinearProgressIndicator(
        semanticsLabel: 'Lecture des décisions',
      ),
      _ => _barre(
        context,
        decisions: decisions,
        decisionsRead: decisionsAsync.value != null,
        offline: offline,
        now: now,
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final fixed = constraints.maxHeight >= kBarreDecisionFixeMinHeight;
        Widget centre(Widget child) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: child,
          ),
        );
        final liste = SelectionArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              centre(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: contenu,
                ),
              ),
              if (!fixed && barre != null) ...[
                const Divider(height: 32),
                centre(barre),
              ],
            ],
          ),
        );
        // Même arbre avec ou sans barre : la pastille garde son état et
        // clignote quand le statut change.
        final enBas = fixed && barre != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: liste),
            if (enBas) const Divider(height: 1),
            if (enBas)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight / 2,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: centre(barre),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Barre de décision : ligne d'état de la dernière décision, puis les
  /// boutons de `allowed_decisions` (P26). `null` s'il n'y a rien à montrer.
  Widget? _barre(
    BuildContext context, {
    required List<TicketDecision> decisions,
    required bool decisionsRead,
    required bool offline,
    required DateTime now,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ticket = _ticket;
    final last = decisions.isEmpty ? null : decisions.first;
    var ligne = last == null
        ? null
        : ligneDecision(
            last,
            offline: offline,
            now: now,
            ticketLease: ticket.decisionLeaseUntil,
          );
    final busy = (last?.inProgress ?? false) || ticket.decisionInProgress(now);
    if (ligne == null && ticket.decisionInProgress(now)) {
      ligne = (
        icon: null,
        error: false,
        progress: true,
        text: 'Décision en cours sur GitHub.',
        retry: false,
      );
    }

    final allowed = ticket.allowedDecisions;
    Widget? actions;
    if (!busy && decisionsRead) {
      if (allowed == null) {
        actions = Text(
          'Le serveur n\'a pas encore calculé les décisions possibles pour ce '
          'ticket.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        );
      } else if (allowed.isNotEmpty) {
        actions = OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 8,
          overflowSpacing: 8,
          children: [
            if (allowed.contains(TicketDecisionAction.refuse))
              OutlinedButton.icon(
                onPressed: () =>
                    _demanderTexte(TicketDecisionAction.refuse, decisions),
                icon: const Icon(Icons.block),
                label: const Text('Refuser'),
              ),
            if (allowed.contains(TicketDecisionAction.close))
              OutlinedButton.icon(
                onPressed: () =>
                    _demanderTexte(TicketDecisionAction.close, decisions),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Clore'),
              ),
            if (allowed.contains(TicketDecisionAction.validate))
              FilledButton.icon(
                onPressed: _valider,
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: const Text('Valider'),
              ),
          ],
        );
      }
    }
    if (ligne == null && actions == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ligne case final l?)
          Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (l.progress) ...[
                  const LinearProgressIndicator(
                    semanticsLabel: 'Décision en cours',
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (l.icon case final icon?) ...[
                      ExcludeSemantics(
                        child: Icon(
                          icon,
                          color: l.error ? scheme.error : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(l.text, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
                if (l.retry && last != null) ...[
                  const SizedBox(height: 8),
                  Text(kApresEchec, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.tonalIcon(
                      onPressed: _relanceDecision
                          ? null
                          : () => _relancer(
                              () => ref
                                  .read(ticketsRepositoryProvider)
                                  .retryDecision(
                                    ticketId: ticket.id,
                                    decisionId: last.id,
                                  ),
                              (v) => _relanceDecision = v,
                            ),
                      icon: const Icon(Icons.refresh),
                      label: _relanceDecision
                          ? const IndicateurBouton(label: 'Relance en cours')
                          : const Text('Réessayer'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (ligne != null && actions != null) const SizedBox(height: 12),
        ?actions,
      ],
    );
  }
}

/// Bloc d'un ticket `send_failed` : essais, dernière erreur, « Relancer
/// l'envoi » ou la relance déjà demandée.
class _EnvoiImpossible extends StatelessWidget {
  const _EnvoiImpossible({
    required this.ticket,
    required this.busy,
    required this.offline,
    required this.onRetry,
  });

  final Ticket ticket;
  final bool busy;

  /// Hors ligne, une relance en attente le dit au lieu de « Relance en
  /// cours ».
  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attempts = ticket.sendAttempts;
    final error = ticket.lastSendError;
    final retry = ticket.retryRequestedAt;
    final changed = ticket.statusChangedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attempts != null)
          Text('Essais d\'envoi : $attempts', style: theme.textTheme.bodyLarge),
        if (error != null)
          Text('Dernière erreur : $error', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        if (retry != null && (changed == null || retry.isAfter(changed)))
          Semantics(
            liveRegion: true,
            child: Text(
              'Nouvel essai demandé le ${formatDateChiffres(retry)} à '
              '${formatHeure(retry)}. Il partira dans l\'heure.',
              style: theme.textTheme.bodyLarge,
            ),
          )
        // Relance écrite hors ligne : le ticket en cache porte l'écriture en
        // attente, quelle que soit la disposition de l'écran.
        else if (ticket.hasPendingWrites && offline)
          Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(child: Icon(Icons.cloud_off)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kRelanceEnvoiHorsLigne,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          )
        else
          FilledButton.tonalIcon(
            onPressed: busy ? null : onRetry,
            icon: const Icon(Icons.refresh),
            label: busy
                ? const IndicateurBouton(label: 'Relance en cours')
                : const Text('Relancer l\'envoi'),
          ),
      ],
    );
  }
}

/// Boîte « Refuser ce ticket » ou « Clore ce ticket » : rend le texte saisi,
/// sans espaces autour, par `Navigator.pop`.
class FormulaireDecision extends StatefulWidget {
  const FormulaireDecision({
    super.key,
    required this.action,
    required this.enCours,
    required this.initial,
    required this.onChanged,
  });

  final TicketDecisionAction action;

  /// Le ticket est « En cours » : une pull request est peut-être ouverte.
  final bool enCours;
  final String initial;

  /// Brouillon gardé par la fiche à chaque frappe.
  final ValueChanged<String> onChanged;

  static const publicWarning =
      'Publié sur un site public : n\'écrivez ni nom ni adresse. Le membre '
      'lira aussi ce texte.';
  static const prWarning =
      'Une pull request est peut-être ouverte. Elle ne sera pas fermée.';

  @override
  State<FormulaireDecision> createState() => _FormulaireDecisionState();
}

class _FormulaireDecisionState extends State<FormulaireDecision> {
  final _formKey = GlobalKey<FormState>();
  final _focus = FocusNode();
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  bool get _refus => widget.action == TicketDecisionAction.refuse;

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              _refus ? 'Refuser ce ticket' : 'Clore ce ticket',
              style: theme.textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.public, color: scheme.onSurface),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      FormulaireDecision.publicWarning,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_refus) ...[
            const SizedBox(height: 12),
            const Text('Le ticket passera à « Clos » et l\'Issue sera fermée.'),
          ],
          if (widget.enCours) ...[
            const SizedBox(height: 12),
            const Text(FormulaireDecision.prWarning),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: kDecisionTextMaxLength,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              labelText: _refus ? 'Motif du refus' : 'Commentaire de clôture',
              helperText: _refus
                  ? 'L\'Issue sera fermée comme non prévue.'
                  : 'Le membre lira ce texte : réponse, ou raison de la '
                        'clôture.',
              helperMaxLines: 3,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            validator: (value) =>
                (value ?? '').trim().length < kDecisionTextMinLength
                ? (_refus
                      ? 'Le motif doit faire au moins 5 caractères.'
                      : 'Le commentaire doit faire au moins 5 caractères.')
                : null,
          ),
          const SizedBox(height: 16),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: _submit,
                child: Text(_refus ? 'Refuser' : 'Clore'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
