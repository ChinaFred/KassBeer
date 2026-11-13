import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_launch.dart';
import 'encadre_reponse.dart';
import 'tickets_providers.dart';

/// Reconstruit [builder] à l'instant [instant] (échéance `retry_after` d'un
/// lancement) : l'écran passe de « en cours » à « Relancer » sans autre
/// événement. Le minuteur ne déclenche qu'un nouveau dessin ; l'état se
/// recalcule à partir de l'heure enregistrée et de `horlogeProvider`.
class ReconstruireA extends ConsumerStatefulWidget {
  const ReconstruireA({super.key, required this.instant, required this.child});

  final DateTime? instant;
  final Widget child;

  @override
  ConsumerState<ReconstruireA> createState() => _ReconstruireAState();
}

class _ReconstruireAState extends ConsumerState<ReconstruireA> {
  Timer? _timer;
  DateTime? _armeA;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _armer(DateTime? instant) {
    if (instant == _armeA) return;
    _timer?.cancel();
    _timer = null;
    _armeA = instant;
    if (instant == null) return;
    final delai = instant.difference(ref.read(horlogeProvider)());
    // Une seconde de marge : à l'instant exact, l'échéance n'est pas passée.
    _timer = Timer(
      (delai.isNegative ? Duration.zero : delai) + const Duration(seconds: 1),
      () {
        _armeA = null;
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _armer(widget.instant);
    return widget.child;
  }
}

/// Pastille de la liste d'Admin › Tickets : lancement en cours ou relance
/// possible. Lit `admin/launches` pour les seuls tickets dont un lancement
/// est permis par le serveur (tickets reçus ou validés).
class PastilleLancement extends ConsumerWidget {
  const PastilleLancement({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      for (final a in ActionLancement.values)
        if (ticket.canLaunch(a)) a,
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    final doc = switch (ref.watch(ticketLaunchesProvider(ticket.id)).value) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    if (doc == null) return const SizedBox.shrink();
    final now = ref.watch(horlogeProvider)();
    for (final action in actions) {
      final enCours = doc.enCours(action, now);
      final since = enCours?.at;
      if (enCours != null) {
        return ReconstruireA(
          instant: enCours.retryAfter,
          child: Semantics(
            label: since == null
                ? '${action.nom} en cours'
                : ligneEnCours(action, since, now),
            excludeSemantics: true,
            child: Etiquette(
              label: '${action.nom} en cours',
              icon: Icons.hourglass_top,
              ton: TonEtiquette.neutre,
            ),
          ),
        );
      }
      if (doc.aRelancer(action, now, statusChangedAt: ticket.statusChangedAt) !=
          null) {
        return const Etiquette(
          label: 'Relance possible',
          icon: Icons.refresh,
          ton: TonEtiquette.neutre,
        );
      }
    }
    return const SizedBox.shrink();
  }
}

/// Compteur en tête de la liste d'Admin › Tickets, lu dans
/// `ticket_status/launches`.
class CompteurLancements extends ConsumerWidget {
  const CompteurLancements({super.key});

  static const indisponible = 'Lancements de sessions : compteur indisponible.';
  static const illisible = 'Lancements de sessions : compteur illisible.';
  static const horsLigne =
      'Lancements de sessions : compteur non disponible hors ligne.';
  static const lecture = 'Lancements de sessions : lecture en cours.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(launchStatusProvider);
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final lookup = async.value;
    final erreur = lookup == null && async.hasError;
    final texte = erreur
        ? indisponible
        : switch (lookup) {
            null => lecture,
            DocumentTrouve(:final value) => ligneCompteur(value),
            DocumentIllisibleTrouve() => illisible,
            DocumentAbsentDuCache() => offline ? horsLigne : lecture,
            DocumentAbsent() => 'Lancements de sessions : aucun compté.',
          };
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                texte,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: erreur ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (erreur)
            IconButton(
              tooltip: 'Réessayer',
              onPressed: async.isLoading
                  ? null
                  : () => ref.invalidate(launchStatusProvider),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }
}

/// Section « Lancements (N) » de la fiche d'Admin (ADR-008, P41) : sessions
/// lancées sur ce ticket, la plus récente en tête, vingt au plus. Repliée,
/// après « Analyses ».
class SectionLancements extends ConsumerWidget {
  const SectionLancements({
    super.key,
    required this.ticket,
    required this.lancementActif,
  });

  final Ticket ticket;

  /// Action du bouton de lancement de la barre quand il est affiché et
  /// actif, dérivée par la fiche ; `null` sinon.
  final ActionLancement? lancementActif;

  static const loadError = 'Impossible de lire les lancements.';
  static const horsLigne = 'Lancements non disponibles hors ligne.';
  static const illisible =
      'Lancements illisibles. Mettez l\'application à jour.';
  static const vide = 'Aucune session lancée pour ce ticket.';

  /// Suit [vide] quand le bouton de lancement de la barre est actif.
  static String invitation(ActionLancement action) =>
      'Appuyez sur « Lancer ${action.complement} », en bas de la fiche.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final async = ref.watch(ticketLaunchesProvider(ticket.id));
    final lecture = async.value;
    Widget phrase(String text, {bool erreur = false}) => Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: erreur ? scheme.error : null,
        ),
      ),
    );
    const progression = LinearProgressIndicator(
      semanticsLabel: 'Lecture des lancements',
    );
    List<Widget> horsListe(List<Widget> corps) => [
      const TitreSection('Lancements'),
      ...corps,
    ];

    // Après une panne, seul un historique déjà lu reste affiché.
    if (async.hasError && lecture is! DocumentTrouve<TicketLaunchesDoc>) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: horsListe([
          phrase(loadError, erreur: true),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonal(
              onPressed: async.isLoading
                  ? null
                  : () => ref.invalidate(ticketLaunchesProvider(ticket.id)),
              child: async.isLoading
                  ? const IndicateurBouton(label: 'Lecture en cours')
                  : const Text('Réessayer'),
            ),
          ),
        ]),
      );
    }
    final List<TicketLaunch> entries;
    switch (lecture) {
      case null:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: horsListe(const [progression]),
        );
      case DocumentAbsentDuCache():
        // En ligne, le cache répond d'abord : le serveur va répondre.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: horsListe([offline ? phrase(horsLigne) : progression]),
        );
      case DocumentIllisibleTrouve():
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: horsListe([phrase(illisible, erreur: true)]),
        );
      case DocumentAbsent():
        entries = const [];
      case DocumentTrouve(:final value):
        entries = value.entries;
    }
    final uid = ref.watch(grantedAccessProvider)?.user.uid;
    // La section dit où appuyer seulement quand le bouton de la barre est
    // actif ([lancementActif], dérivé par la fiche).
    final permis = lancementActif;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SectionRepliable(
        titre: 'Lancements (${entries.length})',
        storageKey: 'lancements-${ticket.id}',
        children: entries.isEmpty
            ? [
                phrase(vide),
                if (permis case final a?) ...[
                  const SizedBox(height: 4),
                  Text(
                    invitation(a),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ]
            : [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  CarteLancement(lancement: entries[i], lecteurUid: uid),
                ],
              ],
      ),
    );
  }
}

/// Carte d'un lancement : action, date, compte, résultat, lien de la session.
class CarteLancement extends ConsumerWidget {
  const CarteLancement({
    super.key,
    required this.lancement,
    required this.lecteurUid,
  });

  final TicketLaunch lancement;

  /// Compte connecté : « par vous » quand il a lancé.
  final String? lecteurUid;

  static const sessionCreee = 'Session créée';
  static const lienInvalide = 'Lien de session invalide.';
  static const ouvertureImpossible = 'Impossible d\'ouvrir la session.';
  static const lienCopie = 'Lien copié.';
  static const copieImpossible = 'Impossible de copier le lien.';
  static const visibilite =
      'Visible seulement depuis le compte Claude de l\'administrateur.';
  static const arret = 'Pour l\'arrêter, ouvrez-la sur claude.ai/code.';

  Future<void> _ouvrir(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    Object? error;
    StackTrace? stackTrace;
    var opened = false;
    try {
      opened = await ref.read(ouvrirLienProvider)(uri);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    if (opened) return;
    errors.reportError(
      feature: 'tickets.open_session',
      error: error ?? StateError('ouverture refusée par le système'),
      stackTrace: stackTrace ?? StackTrace.current,
      // Jamais l'adresse de la session (P41).
      context: 'lien d\'une session',
    );
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text(ouvertureImpossible)));
  }

  Future<void> _copier(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    var texte = lienCopie;
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
    } catch (error, stackTrace) {
      errors.reportError(
        feature: 'tickets.copy_session',
        error: error,
        stackTrace: stackTrace,
        context: 'lien d\'une session',
      );
      texte = copieImpossible;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l = lancement;
    final at = l.at;
    final by = l.byUid;
    final sousTitre = [
      if (at != null) dateLancement(at),
      if (by != null)
        by == lecteurUid ? 'par vous' : 'par un autre administrateur',
    ].join(' ');
    final (IconData icone, Color couleur, String resultat) = switch (l.etat) {
      EtatLancement.launched => (
        Icons.check_circle_outline,
        scheme.primary,
        sessionCreee,
      ),
      EtatLancement.failed => (
        Icons.error_outline,
        scheme.error,
        'Échec : ${l.reason ?? 'raison inconnue'}',
      ),
      EtatLancement.unknown => (
        Icons.help_outline,
        scheme.secondary,
        'Résultat inconnu : vérifiez sur claude.ai/code',
      ),
      null => (
        Icons.help_outline,
        scheme.onSurfaceVariant,
        'Résultat inconnu de cette version. Mettez l\'application à jour.',
      ),
    };
    final lien = l.etat == EtatLancement.launched
        ? lienSessionOuvrable(l.sessionUrl)
        : null;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return EncadreReponse.contenu(
      titre: l.action?.titreHistorique ?? 'Lancement',
      icone: switch (l.action) {
        ActionLancement.analyse => Icons.manage_search,
        ActionLancement.developpement => Icons.code,
        null => Icons.rocket_launch_outlined,
      },
      sousTitre: sousTitre.isEmpty ? null : sousTitre,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icone, size: 20, color: couleur)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  resultat,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: l.etat == EtatLancement.failed ? scheme.error : null,
                  ),
                ),
              ),
            ],
          ),
          if (lien != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _ouvrir(context, ref, lien),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ouvrir la session'),
                ),
                IconButton(
                  tooltip: 'Copier le lien',
                  onPressed: () => _copier(context, ref, lien),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(visibilite, style: muted),
            Text(arret, style: muted),
          ] else if (l.etat == EtatLancement.launched &&
              l.sessionUrl != null) ...[
            const SizedBox(height: 8),
            Text(lienInvalide, style: muted),
          ],
        ],
      ),
    );
  }
}
