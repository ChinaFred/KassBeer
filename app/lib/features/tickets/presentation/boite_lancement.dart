import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../domain/ticket_analysis.dart';
import '../domain/ticket_launch.dart';
import 'lien_usage_claude.dart';

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
/// [echecValidation] quand la validation demandée avant le lancement a
/// échoué (aucun lancement n'est parti) ; [detache] quand « Fermer » l'a
/// fermée pendant l'envoi (les appels continuent).
typedef FinBoiteLancement = ({
  ResultatLancement? resultat,
  EchecReponse? echecValidation,
  bool detache,
});

/// Boîte de confirmation d'un lancement (P39). Rien n'est appelé avant
/// « Lancer ». Pendant l'envoi, « Fermer » et le retour la ferment
/// sans couper l'appel. Un refus du serveur reste affiché dans la boîte.
///
/// Avec [validationAvant] et [valider] (« Valider et lancer le
/// développement ») : la boîte appelle d'abord [valider], puis [envoyer]
/// seulement si la validation est appliquée. Elle se ferme sur tout
/// résultat : la fiche l'affiche dans un message.
class BoiteLancement extends StatefulWidget {
  const BoiteLancement({
    super.key,
    required this.action,
    required this.issueNumber,
    required this.quota,
    required this.relanceDe,
    required this.envoyer,
    this.prNumber,
    this.avertissement,
    this.typeTicket,
    this.validationAvant,
    this.valider,
  }) : assert((validationAvant == null) == (valider == null));

  final ActionLancement action;
  final int? issueNumber;

  /// PR à livrer ou à corriger (« PR #34 »), lue dans `admin/delivery`.
  final int? prNumber;

  /// Avertissement d'une relance, à la place de [avertissementRelance]
  /// (livraison arrêtée ou sans fusion).
  final String? avertissement;

  /// « Bug », rappelé dans la boîte « Livrer ».
  final String? typeTicket;

  /// `ticket_status/launches` lu, ou `null` : « Lancements restants :
  /// inconnu. ».
  final EtatLancements? quota;

  /// Date du lancement relancé, ou `null` pour un premier lancement.
  final DateTime? relanceDe;

  /// Appel du serveur, fait par la fiche.
  final Future<ResultatLancement> Function() envoyer;

  /// Phrase de la boîte « Valider ce ticket ? », affichée en tête quand la
  /// validation précède le lancement.
  final String? validationAvant;

  /// Appel de `validateTicket`, fait par la fiche avant [envoyer]. Rend
  /// l'échec, ou `null` si le serveur a appliqué la validation (`changed:
  /// false` compris).
  final Future<EchecReponse?> Function()? valider;

  static const cout =
      'Facturé sur l\'abonnement Claude de l\'administrateur. Ce coût '
      'n\'apparaît pas dans le suivi des coûts de l\'application.';
  static const titreValiderEtLancer = 'Valider et lancer le développement ?';
  static const validationEnCours =
      'Validation en cours. Vous pouvez fermer : le résultat s\'affichera en '
      'bas de l\'écran.';

  /// Plafond atteint dans la boîte « Valider et lancer le développement ».
  static const validerSansLancer =
      'Annulez, puis appuyez sur « Valider » : « Lancer le développement » '
      'sera proposé ensuite.';

  static const envoiEnCours =
      'Lancement en cours. Vous pouvez fermer : le résultat s\'affichera dans '
      'la section Lancements.';

  /// Accord de fusion de « Livrer » (P39).
  static const accordFusion =
      'La fusion met l\'application en ligne pour tout le groupe, sur le web '
      'et sur Android, sans autre accord. Appuyer sur « Livrer » vaut accord '
      'de fusion.';

  /// « Une session Claude Code va lire l'Issue #12… » (P39).
  static String effet(
    ActionLancement action,
    int? issueNumber, {
    int? prNumber,
  }) {
    final issue = issueNumber == null ? 'l\'Issue' : 'l\'Issue #$issueNumber';
    final pr = prNumber == null ? 'la pull request' : 'la PR #$prNumber';
    return switch (action) {
      ActionLancement.analyse =>
        'Une session Claude Code va lire $issue et publier son analyse sur '
            'GitHub.',
      ActionLancement.developpement =>
        'Une session Claude Code va écrire le code de $issue et ouvrir une '
            'pull request. Elle ne fusionne rien.',
      ActionLancement.livraison =>
        'Une session Claude Code va mettre $pr à jour avec main, la '
            'fusionner, puis suivre le déploiement.',
      ActionLancement.reprise =>
        'Une session Claude Code va reprendre $pr, corriger la CI et '
            'pousser sur la même branche. Elle ne fusionne pas.',
    };
  }

  /// Titre de la boîte.
  static String titre(ActionLancement action, {required bool relance}) =>
      switch (action) {
        ActionLancement.livraison =>
          relance
              ? 'Relancer la livraison de ce ticket ?'
              : 'Livrer ce ticket ?',
        ActionLancement.reprise => 'Relancer le développement ?',
        _ =>
          '${relance ? 'Relancer' : 'Lancer'} ${action.complement} de ce '
              'ticket ?',
      };

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

  /// Appel de la validation en cours, avant le lancement.
  bool _validation = false;
  String? _erreur;

  /// Échec d'ouverture du lien d'usage Claude, affiché sous le lien.
  String? _erreurLien;

  /// Refus `delivery_sensitive_files` ou `delivery_files_unreadable`
  /// ([kRefusFusionALaMain]) : « Livrer » reste inactif tant que la boîte est
  /// ouverte.
  bool _bloque = false;

  /// La fermeture est demandée : un second `pop` fermerait la fiche.
  bool _fermeture = false;

  void _fermer(FinBoiteLancement? fin) {
    if (_fermeture || !mounted) return;
    _fermeture = true;
    Navigator.of(context).pop(fin);
  }

  Future<void> _lancer() async {
    // Appels lus avant le premier `await` : boîte fermée pendant la
    // validation, le lancement part quand même.
    final valider = widget.valider;
    final envoyer = widget.envoyer;
    setState(() {
      _erreur = null;
      _envoi = true;
      _validation = valider != null;
    });
    if (valider != null) {
      final echec = await valider();
      if (echec != null) {
        _fermer((resultat: null, echecValidation: echec, detache: false));
        return;
      }
      if (mounted && !_fermeture) setState(() => _validation = false);
    }
    final resultat = await envoyer();
    if (!mounted || _fermeture) return;
    if (resultat.rienNestParti && valider == null) {
      setState(() {
        _erreur = resultat.message;
        _envoi = false;
        _bloque = kRefusFusionALaMain.contains(resultat.code);
      });
      return;
    }
    _fermer((resultat: resultat, echecValidation: null, detache: false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final relanceDe = widget.relanceDe;
    final erreur = _erreur;
    final relance = relanceDe != null;
    final action = widget.action;
    final livraison = action == ActionLancement.livraison;
    final avertissement =
        widget.avertissement ??
        (relanceDe == null
            ? null
            : BoiteLancement.avertissementRelance(relanceDe));
    final typeTicket = widget.typeTicket;
    final validationAvant = widget.validationAvant;
    final plafondAtteint = widget.quota?.plafondAtteint ?? false;
    final libelle = switch (action) {
      _ when validationAvant != null => 'Valider et lancer',
      ActionLancement.livraison => relance ? 'Relancer' : 'Livrer',
      ActionLancement.reprise => 'Relancer',
      _ => relance ? 'Relancer' : 'Lancer',
    };

    return PopScope(
      canPop: !_envoi,
      // Le retour pendant l'envoi vaut « Fermer ».
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _envoi) {
          _fermer((resultat: null, echecValidation: null, detache: true));
        }
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(
          validationAvant != null
              ? BoiteLancement.titreValiderEtLancer
              : BoiteLancement.titre(action, relance: relance),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (validationAvant != null) ...[
              Text(validationAvant),
              const SizedBox(height: 12),
            ],
            Text(
              BoiteLancement.effet(
                action,
                widget.issueNumber,
                prNumber: widget.prNumber,
              ),
            ),
            if (livraison) ...[
              const SizedBox(height: 12),
              const Text(BoiteLancement.accordFusion),
              if (typeTicket != null) ...[
                const SizedBox(height: 12),
                Text('Type du ticket : $typeTicket.'),
              ],
            ],
            const SizedBox(height: 12),
            Text(ligneQuota(widget.quota)),
            const SizedBox(height: 4),
            // Usage de l'abonnement Claude : lien seul, aucun chiffre.
            LienUsageClaude(
              onEchec: (message) {
                if (mounted) setState(() => _erreurLien = message);
              },
            ),
            if (_erreurLien case final erreurLien?)
              Semantics(
                liveRegion: true,
                child: Text(
                  erreurLien,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            if (validationAvant != null && plafondAtteint) ...[
              const SizedBox(height: 12),
              const Text(BoiteLancement.validerSansLancer),
            ],
            if (avertissement != null) ...[
              const SizedBox(height: 12),
              Encadre(
                ton: TonEncadre.avertissement,
                icone: Icons.warning_amber_outlined,
                child: Text(avertissement),
              ),
            ],
            const SizedBox(height: 12),
            const Encadre(
              icone: Icons.payments_outlined,
              child: Text(BoiteLancement.cout),
            ),
            if (_envoi) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _validation
                      ? BoiteLancement.validationEnCours
                      : BoiteLancement.envoiEnCours,
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
                ? () => _fermer((
                    resultat: null,
                    echecValidation: null,
                    detache: true,
                  ))
                : () => _fermer(null),
            child: Text(_envoi ? 'Fermer' : 'Annuler'),
          ),
          FilledButton(
            // Plafond atteint : la ligne du quota dit pourquoi.
            onPressed: _envoi || _bloque || plafondAtteint ? null : _lancer,
            child: _envoi
                ? IndicateurBouton(
                    label: _validation
                        ? 'Validation en cours'
                        : livraison
                        ? 'Livraison en cours'
                        : 'Lancement en cours',
                  )
                : Text(libelle),
          ),
        ],
      ),
    );
  }
}
