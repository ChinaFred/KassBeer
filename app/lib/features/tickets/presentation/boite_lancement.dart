import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../domain/ticket_launch.dart';
import 'encadre_avertissement.dart';

/// Appel de lancement en cours sur une fiche, hors de l'état du widget : un
/// changement de disposition garde le bouton inactif, et un seul appel part
/// à la fois.
class LancementFicheNotifier extends Notifier<bool> {
  LancementFicheNotifier(this.ticketId);

  final String ticketId;

  @override
  bool build() => false;

  /// Appelle le serveur une fois, jamais rejoué. Un second appel pendant le
  /// premier est refusé sans rien envoyer.
  Future<ResultatLancement> lancer(ActionLancement action) async {
    if (state) {
      return const ResultatLancement(
        IssueLancement.refuse,
        motif: 'Un lancement est déjà en cours. Rien n\'a été lancé.',
      );
    }
    final repository = ref.read(ticketsRepositoryProvider);
    state = true;
    final resultat = await repository.launch(
      ticketId: ticketId,
      action: action,
    );
    if (ref.mounted) state = false;
    return resultat;
  }
}

final lancementFicheProvider = NotifierProvider.autoDispose
    .family<LancementFicheNotifier, bool, String>(LancementFicheNotifier.new);

/// Fin de la boîte : [resultat] quand l'appel a conclu boîte ouverte ;
/// [detache] quand « Fermer » l'a fermée pendant l'envoi (l'appel continue).
typedef FinBoiteLancement = ({ResultatLancement? resultat, bool detache});

/// Boîte de confirmation d'un lancement (P39). Rien n'est appelé avant
/// « Lancer ». Pendant l'envoi, « Fermer », le retour et Échap la ferment
/// sans couper l'appel. Un refus du serveur reste affiché dans la boîte.
class BoiteLancement extends StatefulWidget {
  const BoiteLancement({
    super.key,
    required this.action,
    required this.issueNumber,
    required this.quota,
    required this.relanceDe,
    required this.envoyer,
  });

  final ActionLancement action;
  final int? issueNumber;

  /// `ticket_status/launches` lu, ou `null` : « Lancements restants :
  /// inconnu. ».
  final EtatLancements? quota;

  /// Date du lancement relancé, ou `null` pour un premier lancement.
  final DateTime? relanceDe;

  /// Appel du serveur, fait par la fiche.
  final Future<ResultatLancement> Function() envoyer;

  static const cout =
      'Facturé sur l\'abonnement Claude de l\'administrateur. Ce coût '
      'n\'apparaît pas dans le suivi des coûts de l\'application.';
  static const envoiEnCours =
      'Lancement en cours. Vous pouvez fermer : le résultat s\'affichera dans '
      'la section Lancements.';

  /// « Une session Claude Code va lire l'Issue #12… » (P39).
  static String effet(ActionLancement action, int? issueNumber) {
    final issue = issueNumber == null ? 'l\'Issue' : 'l\'Issue #$issueNumber';
    return switch (action) {
      ActionLancement.analyse =>
        'Une session Claude Code va lire $issue et publier son analyse sur '
            'GitHub.',
      ActionLancement.developpement =>
        'Une session Claude Code va écrire le code de $issue et ouvrir une '
            'pull request. Elle ne fusionne rien.',
    };
  }

  /// Avertissement d'une relance.
  static String avertissementRelance(DateTime relanceDe) =>
      'Le lancement du ${formatDateChiffres(relanceDe)} à '
      '${formatHeure(relanceDe)} n\'a rien '
      'changé au ticket. Vérifiez sur claude.ai/code qu\'aucune session ne '
      'tourne encore.';

  @override
  State<BoiteLancement> createState() => _BoiteLancementState();
}

class _BoiteLancementState extends State<BoiteLancement> {
  bool _envoi = false;
  String? _erreur;

  /// La fermeture est demandée : un second `pop` fermerait la fiche.
  bool _fermeture = false;

  void _fermer(FinBoiteLancement? fin) {
    if (_fermeture || !mounted) return;
    _fermeture = true;
    Navigator.of(context).pop(fin);
  }

  Future<void> _lancer() async {
    setState(() {
      _erreur = null;
      _envoi = true;
    });
    final resultat = await widget.envoyer();
    if (!mounted || _fermeture) return;
    if (resultat.rienNestParti) {
      setState(() {
        _erreur = resultat.message;
        _envoi = false;
      });
      return;
    }
    _fermer((resultat: resultat, detache: false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final relanceDe = widget.relanceDe;
    final erreur = _erreur;
    final relance = relanceDe != null;

    return PopScope(
      canPop: !_envoi,
      // Le retour et Échap pendant l'envoi valent « Fermer ».
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _envoi) _fermer((resultat: null, detache: true));
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(
          '${relance ? 'Relancer' : 'Lancer'} ${widget.action.complement} de '
          'ce ticket ?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(BoiteLancement.effet(widget.action, widget.issueNumber)),
            const SizedBox(height: 12),
            Text(ligneQuota(widget.quota)),
            if (relance) ...[
              const SizedBox(height: 12),
              EncadreAvertissement(
                icone: Icons.warning_amber_outlined,
                texte: BoiteLancement.avertissementRelance(relanceDe),
              ),
            ],
            const SizedBox(height: 12),
            const EncadreAvertissement(
              icone: Icons.payments_outlined,
              texte: BoiteLancement.cout,
            ),
            if (_envoi) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  BoiteLancement.envoiEnCours,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (erreur != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  erreur,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Focus initial sur « Annuler » : rien ne part sur un Entrée.
          TextButton(
            autofocus: true,
            onPressed: _envoi
                ? () => _fermer((resultat: null, detache: true))
                : () => _fermer(null),
            child: Text(_envoi ? 'Fermer' : 'Annuler'),
          ),
          FilledButton(
            // Plafond atteint : la ligne du quota dit pourquoi.
            onPressed: _envoi || (widget.quota?.plafondAtteint ?? false)
                ? null
                : _lancer,
            child: _envoi
                ? const IndicateurBouton(label: 'Lancement en cours')
                : Text(relance ? 'Relancer' : 'Lancer'),
          ),
        ],
      ),
    );
  }
}
