import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_analysis.dart';
import '../domain/ticket_launch.dart';
import 'lien_usage_claude.dart';
import 'tickets_providers.dart';

/// Appel de lancement en cours sur une fiche, hors de l'état du widget : un
/// changement de disposition garde le bouton inactif, et un seul appel part
/// à la fois.
class LancementFicheNotifier extends Notifier<bool> {
  LancementFicheNotifier(this.ticketId);

  final String ticketId;

  @override
  bool build() => false;

  /// Mode de l'appel de livraison en cours (« Mettre en file », « Retirer de
  /// la file »), lu par la barre pendant l'appel ; `null` sinon.
  ModeLivraison? modeEnCours;

  /// Appelle le serveur une fois, jamais rejoué. Un second appel pendant le
  /// premier est refusé sans rien envoyer.
  Future<ResultatLancement> lancer(
    ActionLancement action, {
    ModeLivraison? mode,
  }) async {
    if (state) {
      return const ResultatLancement(
        IssueLancement.refuse,
        motif: 'Un lancement est déjà en cours. Rien n\'a été lancé.',
      );
    }
    final repository = ref.read(ticketsRepositoryProvider);
    modeEnCours = mode;
    state = true;
    final resultat = await repository.launch(
      ticketId: ticketId,
      action: action,
      mode: mode,
    );
    if (ref.mounted) {
      modeEnCours = null;
      state = false;
    }
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
    this.positionFile,
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

  /// Boîte « Mettre en file » (livraison seule, ticket #104) : ligne de la
  /// position que prendra le ticket ; `null` pour « Livrer ».
  final String? positionFile;

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

  /// Titre de la boîte « Mettre en file ».
  static const titreFile = 'Mettre ce ticket en file de livraison ?';

  /// Départ différé (P39, ADR-008, amendement du 2026-11-22), mot pour mot.
  static const delaiFile =
      'La livraison partira sans autre accord quand la livraison en cours '
      'aura publié son compte rendu, environ 5 minutes après, ou 3 h après son '
      'lancement s\'il n\'arrive pas. Elle sera comptée au départ ; si le '
      'plafond du jour est atteint, elle attendra. Si le code de la PR change '
      'd\'ici là, ou si une livraison se bloque, elle sortira de la file.';

  /// Accord de fusion de « Mettre en file ».
  static const accordFusionFile =
      'La fusion met l\'application en ligne pour tout le groupe, sur le web '
      'et sur Android, sans autre accord. Appuyer sur « Mettre en file » vaut '
      'accord de fusion.';

  /// Plafond atteint dans la boîte « Mettre en file ».
  static const attenteRemiseAZero = 'La livraison attendra la remise à zéro.';

  static const miseEnFileEnCours =
      'Mise en file en cours. Vous pouvez fermer : le résultat s\'affichera '
      'en bas de l\'écran.';

  /// Effet de « Mettre en file », au futur : la session part plus tard.
  static String effetFile(int? prNumber) =>
      'Une session Claude Code mettra '
      '${prNumber == null ? 'la pull request' : 'la PR #$prNumber'} à jour '
      'avec main, la fusionnera, puis suivra le déploiement.';

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
    final positionFile = widget.positionFile;
    final file = positionFile != null;
    final plafond = widget.quota?.plafondAtteint ?? false;
    // « Mettre en file » reste actif au plafond : l'entrée attendra.
    final plafondAtteint = plafond && !file;
    final libelle = switch (action) {
      _ when validationAvant != null => 'Valider et lancer',
      _ when file => 'Mettre en file',
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
              : file
              ? BoiteLancement.titreFile
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
              file
                  ? BoiteLancement.effetFile(widget.prNumber)
                  : BoiteLancement.effet(
                      action,
                      widget.issueNumber,
                      prNumber: widget.prNumber,
                    ),
            ),
            if (file) ...[
              const SizedBox(height: 12),
              const Text(BoiteLancement.delaiFile),
            ],
            if (livraison) ...[
              const SizedBox(height: 12),
              Text(
                file
                    ? BoiteLancement.accordFusionFile
                    : BoiteLancement.accordFusion,
              ),
              if (positionFile != null) ...[
                const SizedBox(height: 12),
                Text(positionFile),
              ],
              if (typeTicket != null) ...[
                const SizedBox(height: 12),
                Text('Type du ticket : $typeTicket.'),
              ],
            ],
            const SizedBox(height: 12),
            Text(
              file && plafond
                  ? '${ligneQuota(widget.quota)} '
                        '${BoiteLancement.attenteRemiseAZero}'
                  : ligneQuota(widget.quota),
            ),
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
                      : file
                      ? BoiteLancement.miseEnFileEnCours
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
                        : file
                        ? 'Mise en file en cours'
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

/// Fin de [BoiteEnvoiAnalyse] quand le ticket est écrit : « Voir le ticket »
/// appuyé ([voir]), message à afficher sous la fiche fermée ([annonce]), ou
/// lancement parti boîte fermée ([enVol], résultat en message).
@immutable
class FinEnvoiAnalyse {
  const FinEnvoiAnalyse({this.voir = false, this.annonce, this.enVol});

  final bool voir;
  final String? annonce;
  final Future<ResultatLancement>? enVol;
}

/// Boîte « Envoyer et lancer » d'un ticket ouvert par « Analyser » (ticket
/// #67, P39). Rien n'est écrit avant l'appui sur « Envoyer et lancer ».
/// Ensuite : écriture du ticket ([ecrire]), suivi du ticket dans la liste de
/// l'administrateur, puis un seul appel de `launchTicketAnalysis`, dès que le
/// serveur a écrit le numéro d'Issue, le statut « reçu » et `launch_analysis`
/// dans `allowed_decisions`. Le serveur garde toutes ses vérifications.
///
/// Sans publication en [delaiPublication], ticket « quota dépassé » ou
/// « envoi en échec », ou boîte fermée avant la publication : aucun
/// lancement, [nonLance]. Plafond du jour atteint, lu dans
/// `ticket_status/launches` : « Envoyer sans lancer » écrit le ticket et
/// ferme la boîte, sans appel. Rend `null` si rien n'est écrit (« Annuler »)
/// ou si le ticket est refusé.
class BoiteEnvoiAnalyse extends ConsumerStatefulWidget {
  const BoiteEnvoiAnalyse({
    super.key,
    required this.ticketId,
    required this.ecrire,
  });

  final String ticketId;

  /// Écrit le ticket ; la `Future` se termine quand le serveur l'a accepté,
  /// et échoue sur un refus, déjà rapporté par le dépôt de données.
  final Future<void> Function() ecrire;

  static const titre = 'Envoyer le ticket et lancer l\'analyse ?';
  static const titreEnvoi = 'Envoi en cours';
  static const titreEnvoye = 'Ticket envoyé';
  static const titreRefuse = 'Ticket non envoyé';
  static const envoyerSansLancer = 'Envoyer sans lancer';
  static const plafond =
      'Le ticket partira. L\'analyse ne sera pas lancée aujourd\'hui.';
  static const fermerAvantPublication =
      'Si vous fermez maintenant, l\'analyse ne sera pas lancée.';
  static const envoye = 'Ticket envoyé.';
  static const effet =
      'Le ticket sera publié sur GitHub, puis une session Claude Code partira '
      'sur son Issue.';
  static const envoyer = 'Envoyer et lancer';
  static const publication = 'Publication du ticket…';
  static const lancement = 'Lancement…';
  static const nonLance =
      'Ticket envoyé. Analyse non lancée : lancez-la depuis la fiche du '
      'ticket.';
  static const voir = 'Voir le ticket';
  static const refuse =
      'Votre ticket a été refusé. Il n\'est pas enregistré. Votre texte reste '
      'dans le formulaire.';

  /// Attente de la publication de l'Issue avant d'abandonner le lancement.
  static const delaiPublication = Duration(minutes: 2);

  @override
  ConsumerState<BoiteEnvoiAnalyse> createState() => _BoiteEnvoiAnalyseState();
}

enum _PhaseEnvoi { confirmation, publication, lancement, resultat, refus }

class _BoiteEnvoiAnalyseState extends ConsumerState<BoiteEnvoiAnalyse> {
  var _phase = _PhaseEnvoi.confirmation;

  /// Texte de la fin : résultat du lancement ou [BoiteEnvoiAnalyse.nonLance].
  String? _texte;

  /// Le texte de la fin est un refus du lancement : affiché en ton d'erreur.
  bool _texteRefus = false;

  /// Échec d'ouverture du lien d'usage Claude, affiché sous le lien.
  String? _erreurLien;
  ProviderSubscription<AsyncValue<ListeLue<Ticket>>>? _suivi;
  Timer? _delai;
  Future<ResultatLancement>? _enVol;

  /// La fermeture est demandée : un second `pop` fermerait le formulaire.
  bool _fermeture = false;

  @override
  void dispose() {
    _arreterSuivi();
    super.dispose();
  }

  void _arreterSuivi() {
    _delai?.cancel();
    _delai = null;
    _suivi?.close();
    _suivi = null;
  }

  void _fermer(FinEnvoiAnalyse? fin) {
    if (_fermeture || !mounted) return;
    _fermeture = true;
    _arreterSuivi();
    Navigator.of(context).pop(fin);
  }

  /// « Fermer », ou le retour, selon l'étape.
  void _fermerSelonPhase() => switch (_phase) {
    _PhaseEnvoi.confirmation || _PhaseEnvoi.refus => _fermer(null),
    _PhaseEnvoi.publication => _fermer(
      const FinEnvoiAnalyse(annonce: BoiteEnvoiAnalyse.nonLance),
    ),
    _PhaseEnvoi.lancement => _fermer(FinEnvoiAnalyse(enVol: _enVol)),
    _PhaseEnvoi.resultat => _fermer(const FinEnvoiAnalyse()),
  };

  void _envoyer({required bool sansLancer}) {
    if (_phase != _PhaseEnvoi.confirmation) return;
    if (sansLancer) {
      // Plafond atteint : aucun appel. Un refus d'écriture arrive au
      // formulaire, qui l'annonce avec « Reprendre ».
      unawaited(
        widget.ecrire().then(
          (_) {},
          // Déjà rapporté par le dépôt de données ; annoncé par le formulaire.
          onError: (Object _) {},
        ),
      );
      _fermer(const FinEnvoiAnalyse(annonce: BoiteEnvoiAnalyse.nonLance));
      return;
    }
    setState(() => _phase = _PhaseEnvoi.publication);
    _delai = Timer(BoiteEnvoiAnalyse.delaiPublication, _abandonner);
    _suivi = ref.listenManual<AsyncValue<ListeLue<Ticket>>>(
      adminTicketsProvider,
      (_, next) => _suivre(next.value),
      fireImmediately: true,
    );
    unawaited(
      widget.ecrire().then(
        (_) {},
        // Refus déjà rapporté par le dépôt de données, sans le texte du ticket.
        onError: (Object _) {
          if (!mounted || _fermeture || _phase != _PhaseEnvoi.publication) {
            return;
          }
          _arreterSuivi();
          setState(() => _phase = _PhaseEnvoi.refus);
        },
      ),
    );
  }

  void _suivre(ListeLue<Ticket>? liste) {
    if (liste == null || _phase != _PhaseEnvoi.publication) return;
    final ticket = switch (liste.chercher(widget.ticketId)) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    if (ticket == null) return;
    switch (ticket.status) {
      case TicketStatus.overQuota || TicketStatus.sendFailed:
        _abandonner();
      case TicketStatus.received
          when ticket.issueNumber != null && ticket.canLaunchAnalysis:
        unawaited(_lancer());
      default:
    }
  }

  /// Aucun lancement : le ticket reste envoyé.
  void _abandonner() {
    if (!mounted || _phase != _PhaseEnvoi.publication) return;
    _arreterSuivi();
    setState(() {
      _phase = _PhaseEnvoi.resultat;
      _texte = BoiteEnvoiAnalyse.nonLance;
    });
  }

  /// Un seul appel : la phase quitte « publication » avant l'appel.
  Future<void> _lancer() async {
    _arreterSuivi();
    setState(() => _phase = _PhaseEnvoi.lancement);
    final appel = _enVol = ref
        .read(ticketsRepositoryProvider)
        .launch(ticketId: widget.ticketId, action: ActionLancement.analyse);
    final resultat = await appel;
    if (!mounted || _fermeture) return;
    setState(() {
      _phase = _PhaseEnvoi.resultat;
      _texteRefus = resultat.rienNestParti;
      _texte = resultat.rienNestParti
          ? '${BoiteEnvoiAnalyse.envoye} ${resultat.message}'
          : resultat.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quota = switch (ref.watch(launchStatusProvider).value) {
      DocumentTrouve(:final value) => value,
      _ => null,
    };
    final attente = switch (_phase) {
      _PhaseEnvoi.publication => BoiteEnvoiAnalyse.publication,
      _PhaseEnvoi.lancement => BoiteEnvoiAnalyse.lancement,
      _ => null,
    };
    final texte = _texte;
    final fin = _phase == _PhaseEnvoi.resultat;
    final plafond = quota?.plafondAtteint ?? false;
    final titre = switch (_phase) {
      _PhaseEnvoi.confirmation => BoiteEnvoiAnalyse.titre,
      _PhaseEnvoi.publication ||
      _PhaseEnvoi.lancement => BoiteEnvoiAnalyse.titreEnvoi,
      _PhaseEnvoi.resultat => BoiteEnvoiAnalyse.titreEnvoye,
      _PhaseEnvoi.refus => BoiteEnvoiAnalyse.titreRefuse,
    };
    return PopScope(
      canPop: false,
      // Le retour vaut « Annuler » ou « Fermer ».
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _fermerSelonPhase();
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(titre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(BoiteEnvoiAnalyse.effet),
            const SizedBox(height: 12),
            Text(ligneQuota(quota)),
            const SizedBox(height: 4),
            // Usage de l'abonnement Claude : lien seul, aucun chiffre (#96).
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
            if (plafond && _phase == _PhaseEnvoi.confirmation) ...[
              const SizedBox(height: 12),
              const Text(BoiteEnvoiAnalyse.plafond),
            ],
            const SizedBox(height: 12),
            const Encadre(
              icone: Icons.payments_outlined,
              child: Text(BoiteLancement.cout),
            ),
            if (attente != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Flexible(child: Text(attente)),
                  ],
                ),
              ),
              if (_phase == _PhaseEnvoi.publication) ...[
                const SizedBox(height: 8),
                Text(
                  BoiteEnvoiAnalyse.fermerAvantPublication,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
            if (fin && texte != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  texte,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _texteRefus ? scheme.error : null,
                  ),
                ),
              ),
            ],
            if (_phase == _PhaseEnvoi.refus) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  BoiteEnvoiAnalyse.refuse,
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
            onPressed: _fermerSelonPhase,
            child: Text(
              _phase == _PhaseEnvoi.confirmation ? 'Annuler' : 'Fermer',
            ),
          ),
          if (fin)
            FilledButton(
              onPressed: () => _fermer(const FinEnvoiAnalyse(voir: true)),
              child: const Text(BoiteEnvoiAnalyse.voir),
            )
          else if (_phase != _PhaseEnvoi.refus)
            // Un seul indicateur pendant l'attente, dans le contenu : le
            // bouton reste grisé sous son libellé.
            FilledButton(
              onPressed: _phase == _PhaseEnvoi.confirmation
                  ? () => _envoyer(sansLancer: plafond)
                  : null,
              child: Text(
                plafond
                    ? BoiteEnvoiAnalyse.envoyerSansLancer
                    : BoiteEnvoiAnalyse.envoyer,
              ),
            ),
        ],
      ),
    );
  }
}
