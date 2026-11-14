import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/ticket.dart';
import '../domain/ticket_analysis.dart';
import '../domain/ticket_delivery.dart';
import '../domain/ticket_launch.dart';
import '../domain/ticket_screens.dart';
import 'admin_tickets_screen.dart';
import 'bandeau_tickets_admin.dart';
import 'boite_lancement.dart';
import 'encadre_reponse.dart';
import 'frise_ticket.dart';
import 'section_analyses.dart';
import 'section_lancements.dart';
import 'section_livraison.dart';
import 'ticket_lien_github.dart';
import 'ticket_statut.dart';
import 'tickets_providers.dart';
import 'vignette_capture.dart';

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

/// Hors ligne, sous les boutons de la barre : décisions, « Répondre » et
/// lancements appellent le serveur (ADR-008, T7). Les boutons restent visibles
/// et inactifs.
const kActionsHorsLigne = 'Ces actions demandent le réseau.';

/// Hors ligne, dans le bloc « Envoi impossible ».
const kRelancerEnvoiHorsLigne = 'Relancer l\'envoi demande le réseau.';

/// Libellé lu de l'indicateur d'une décision en cours : « Refus en cours ».
String indicateurDecision(TicketDecisionAction action) =>
    '${action.nom} en cours';

/// Ligne de la barre pendant l'appel d'une décision, boîte fermée ou non.
String ligneDecisionEnCours(TicketDecisionAction action) =>
    '${action.nom} en cours sur GitHub.';

/// Message en bas d'écran après une décision appliquée. [valideSurGithub] :
/// le ticket était validé par une étiquette posée sur GitHub. [texteGarde] :
/// le texte publié par un essai précédent est gardé, le texte envoyé n'est
/// pas publié (P53).
String messageDecisionAppliquee(
  TicketDecisionAction action, {
  required bool valideSurGithub,
  bool texteGarde = false,
}) {
  final base = switch (action) {
    TicketDecisionAction.validate when valideSurGithub =>
      'Validation enregistrée. Vous pouvez lancer le développement.',
    TicketDecisionAction.validate =>
      'Ticket validé. Le membre voit « Validé ».',
    TicketDecisionAction.refuse => 'Ticket refusé. L\'Issue est fermée.',
    TicketDecisionAction.close => 'Ticket clos. L\'Issue est fermée.',
  };
  if (!texteGarde || action == TicketDecisionAction.validate) return base;
  final garde = action == TicketDecisionAction.refuse
      ? 'Le motif déjà publié est gardé'
      : 'Le commentaire déjà publié est gardé';
  return '$base $garde : votre nouveau texte n\'est pas publié.';
}

/// Durée d'un message d'échec en bas d'écran : le temps de le lire et d'agir.
const kDureeMessageEchec = Duration(seconds: 10);

/// Message d'un échec de [action], dans la boîte ou en bas d'écran.
String messageEchecDecision(TicketDecisionAction action, EchecReponse echec) {
  final valider = action == TicketDecisionAction.validate;
  final verbe = switch (action) {
    TicketDecisionAction.validate => 'valider',
    TicketDecisionAction.refuse => 'refuser',
    TicketDecisionAction.close => 'clore',
  };
  final echoue = switch (action) {
    TicketDecisionAction.validate => 'Validation non enregistrée',
    TicketDecisionAction.refuse => 'Refus non publié',
    TicketDecisionAction.close => 'Clôture non publiée',
  };
  final garde = valider ? '' : ' Votre texte est gardé.';
  if (echec.partiel) {
    return action == TicketDecisionAction.refuse
        ? 'Le motif est publié sur GitHub, mais l\'Issue n\'est pas fermée. '
              'Refuser à nouveau termine sans republier.'
        : 'Le commentaire est publié sur GitHub, mais l\'Issue n\'est pas '
              'fermée. Clore à nouveau termine sans republier.';
  }
  return switch (echec.cause) {
    CauseEchecReponse.motif => '$echoue : ${echec.motif}$garde',
    CauseEchecReponse.reseau => '$echoue : pas de réseau.$garde',
    CauseEchecReponse.delai =>
      'Résultat inconnu : le serveur n\'a pas répondu à temps. Regardez le '
          'statut du ticket avant de $verbe à nouveau.$garde',
    CauseEchecReponse.acces => '$echoue : accès administrateur refusé.',
    CauseEchecReponse.autre => '$echoue.$garde',
  };
}

/// Message après « Relancer l'envoi ».
String messageRelanceEnvoi(ResultatRelanceEnvoi resultat) {
  final echec = resultat.echec;
  if (echec != null) {
    return switch (echec.cause) {
      CauseEchecReponse.motif => 'Envoi non relancé : ${echec.motif}',
      CauseEchecReponse.reseau => 'Envoi non relancé : pas de réseau.',
      CauseEchecReponse.delai =>
        'Résultat inconnu : regardez le statut du ticket avant de relancer.',
      CauseEchecReponse.acces =>
        'Envoi non relancé : accès administrateur refusé.',
      CauseEchecReponse.autre => 'Envoi non relancé.',
    };
  }
  final issue = resultat.issueNumber;
  if (resultat.status == TicketStatus.received && issue != null) {
    return 'Ticket envoyé sur GitHub : Issue #$issue.';
  }
  if (resultat.status == TicketStatus.pending) {
    return 'Envoi relancé, mais GitHub n\'a pas encore publié l\'Issue. Un '
        'nouvel essai partira dans l\'heure.';
  }
  return 'Envoi relancé.';
}

/// Ligne d'un ticket reçu : « Valider » n'est offert que depuis Analysé
/// (ADR-008, P42).
const kValiderApresAnalyse =
    'Valider sera possible une fois le ticket analysé.';

/// Ligne d'un ticket validé par une étiquette posée sur GitHub : le serveur
/// offre « Valider » à nouveau et réserve « Lancer le développement » à une
/// validation faite dans l'application (ADR-008, décision du 2026-11-13).
const kValiderDepuisApplication =
    'Validé sur GitHub : validez depuis l\'application pour lancer le '
    'développement.';

/// Boîte « Valider ce ticket ? » d'un ticket à valider.
const kValiderConfirmation =
    'L\'étiquette « validé » sera posée sur l\'Issue. Le membre verra '
    '« Validé ».';

/// Boîte « Valider ce ticket ? » d'un ticket validé sur GitHub seul :
/// l'étiquette est déjà posée.
const kValiderConfirmationGithub =
    'La validation sera enregistrée dans l\'application. « Lancer le '
    'développement » sera ensuite proposé.';

/// Valider offert par le serveur sur un ticket déjà validé : la validation
/// vient d'une étiquette posée sur GitHub. Le client lit `allowed_decisions`
/// et ne recalcule rien.
bool _valideSurGithub(Ticket ticket) =>
    ticket.status == TicketStatus.validated &&
    (ticket.allowedDecisions?.contains(TicketDecisionAction.validate) ?? false);

/// État des lancements d'une fiche, dérivé une fois et lu par la barre et
/// par la section « Lancements ».
typedef _EtatLancementsFiche = ({
  AsyncValue<RechercheDocument<TicketLaunchesDoc>>? lancements,
  TicketLaunchesDoc? historique,
  ActionLancement? lancement,
  EtatLancements? quota,
  bool appelEnCours,
  TicketLaunch? enCours,
  TicketLaunch? aRelancer,
  ActionLancement? actif,
  LigneLivraison? livraison,
  TicketDelivery? etatPr,
});

/// Ligne de lancement de la barre, au-dessus des boutons.
typedef _LigneLancement = ({
  IconData? icon,
  String? progress,
  String text,
  bool precisionsVisibles,
  bool error,
  // Ton d'une ligne de livraison : couleur de son icône ; `null` ailleurs.
  TonLivraison? ton,
});

/// Ligne de la barre pendant la publication d'une réponse, boîte fermée ou
/// non.
const kPublicationReponseEnCours =
    'Publication de la réponse en cours sur GitHub.';

/// Ligne de l'historique : « Refus demandé le 11/11/26 à 10:02 · Appliqué ».
String ligneHistorique(TicketDecision decision) {
  final (:nom, :feminin) = nomDecision(decision.action);
  final e = feminin ? 'e' : '';
  final requested = decision.requestedAt;
  final quand = requested == null
      ? ''
      : ' le ${formatDateChiffres(requested)} à ${formatHeure(requested)}';
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
  return '$nom demandé$e$quand · $etat';
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

/// Brouillons et appels en cours d'une fiche, hors de l'état du widget : un
/// changement de disposition (liste et fiche côte à côte, ou fiche seule)
/// reconstruit la fiche sans perdre le texte saisi ni l'appel en cours.
///
/// [decisionEnCours], [echecDecision] : Valider, Refuser, Clore (ADR-008, T7) ;
/// [relanceEnCours] : « Relancer l'envoi » ; [brouillonReponse],
/// [reponseEnCours], [echecReponse] : « Répondre ». Chaque appel continue
/// quand sa boîte est fermée.
@immutable
class EtatDecisionsFiche {
  const EtatDecisionsFiche({
    this.brouillons = const {},
    this.decisionEnCours,
    this.echecDecision,
    this.relanceEnCours = false,
    this.brouillonReponse,
    this.reponseEnCours = false,
    this.echecReponse,
  });

  final Map<TicketDecisionAction, String> brouillons;
  final TicketDecisionAction? decisionEnCours;

  /// Dernier échec d'une décision, avec son action ; effacé par une frappe
  /// (sauf un échec partiel : texte figé) ou par un nouvel appel.
  final ({TicketDecisionAction action, EchecReponse echec})? echecDecision;
  final bool relanceEnCours;
  final String? brouillonReponse;
  final bool reponseEnCours;
  final EchecReponse? echecReponse;

  /// Un appel au serveur part déjà de cette fiche : aucun autre ne part.
  bool get appelEnCours =>
      decisionEnCours != null || reponseEnCours || relanceEnCours;

  /// Échec de [action] à afficher, ou `null`.
  EchecReponse? echecDe(TicketDecisionAction action) =>
      echecDecision?.action == action ? echecDecision?.echec : null;

  EtatDecisionsFiche copyWith({
    Map<TicketDecisionAction, String>? brouillons,
    ValueGetter<TicketDecisionAction?>? decisionEnCours,
    ValueGetter<({TicketDecisionAction action, EchecReponse echec})?>?
    echecDecision,
    bool? relanceEnCours,
    ValueGetter<String?>? brouillonReponse,
    bool? reponseEnCours,
    ValueGetter<EchecReponse?>? echecReponse,
  }) => EtatDecisionsFiche(
    brouillons: brouillons ?? this.brouillons,
    decisionEnCours: decisionEnCours == null
        ? this.decisionEnCours
        : decisionEnCours(),
    echecDecision: echecDecision == null ? this.echecDecision : echecDecision(),
    relanceEnCours: relanceEnCours ?? this.relanceEnCours,
    brouillonReponse: brouillonReponse == null
        ? this.brouillonReponse
        : brouillonReponse(),
    reponseEnCours: reponseEnCours ?? this.reponseEnCours,
    echecReponse: echecReponse == null ? this.echecReponse : echecReponse(),
  );
}

/// Brouillons d'un refus ou d'une clôture, décision, relance et réponse en
/// cours d'appel.
class DecisionsFicheNotifier extends Notifier<EtatDecisionsFiche> {
  DecisionsFicheNotifier(this.ticketId);

  final String ticketId;

  @override
  EtatDecisionsFiche build() => const EtatDecisionsFiche();

  /// Garde le texte de [action] à chaque frappe ; un échec affiché s'efface,
  /// sauf un échec partiel (texte figé).
  void garderBrouillon(TicketDecisionAction action, String text) {
    final echec = state.echecDecision;
    state = state.copyWith(
      brouillons: {...state.brouillons, action: text},
      echecDecision:
          echec != null && echec.action == action && !echec.echec.partiel
          ? () => null
          : null,
    );
  }

  /// Le ticket est refusé ou clos : les brouillons de Refuser et Clore sont
  /// sans objet (résultat d'un appel au résultat inconnu, ou décision prise
  /// ailleurs).
  void effacerBrouillons() {
    if (state.brouillons.isEmpty && state.echecDecision == null) return;
    state = state.copyWith(brouillons: const {}, echecDecision: () => null);
  }

  /// Garde le texte de « Répondre » à chaque frappe ; un échec affiché
  /// s'efface, sauf un échec partiel (texte figé).
  void garderBrouillonReponse(String text) => state = state.copyWith(
    brouillonReponse: () => text,
    echecReponse: (state.echecReponse?.partiel ?? false) ? null : () => null,
  );

  /// Applique [action] par sa callable ; un seul appel à la fois par fiche,
  /// lancement compris. Rend un échec `null` si le serveur l'a appliquée (le
  /// brouillon s'efface), sinon l'échec, déjà rapporté par le dépôt sans le
  /// texte (P13), et le texte reste en brouillon. Aucun envoi automatique au
  /// retour du réseau.
  Future<ResultatDecision> decider(
    TicketDecisionAction action, {
    String? text,
  }) async {
    if (state.appelEnCours || ref.read(lancementFicheProvider(ticketId))) {
      return (
        echec: const EchecReponse(CauseEchecReponse.autre),
        texteGarde: false,
      );
    }
    final repository = ref.read(ticketsRepositoryProvider);
    state = state.copyWith(
      brouillons: text == null ? null : {...state.brouillons, action: text},
      decisionEnCours: () => action,
      echecDecision: () => null,
    );
    final resultat = await repository.decide(
      ticketId: ticketId,
      action: action,
      text: text,
    );
    final echec = resultat.echec;
    if (!ref.mounted) return resultat;
    state = state.copyWith(
      brouillons: echec == null
          ? ({...state.brouillons}..remove(action))
          : null,
      decisionEnCours: () => null,
      echecDecision: () =>
          echec == null ? null : (action: action, echec: echec),
    );
    return resultat;
  }

  /// Relance l'envoi par `retryTicketSend` ; un seul appel à la fois.
  Future<ResultatRelanceEnvoi> relancerEnvoi() async {
    if (state.appelEnCours || ref.read(lancementFicheProvider(ticketId))) {
      return const ResultatRelanceEnvoi.echec(
        EchecReponse(CauseEchecReponse.autre),
      );
    }
    final repository = ref.read(ticketsRepositoryProvider);
    state = state.copyWith(relanceEnCours: true);
    final resultat = await repository.retrySend(ticketId);
    if (ref.mounted) state = state.copyWith(relanceEnCours: false);
    return resultat;
  }

  /// Publie [text] par `answerTicketAnalysis` ; un seul appel à la fois.
  /// Rend `null` si le serveur l'a publié (le brouillon s'efface), sinon
  /// l'échec, déjà rapporté par le dépôt sans le texte (P13), et le texte
  /// reste en brouillon.
  Future<EchecReponse?> publierReponse(String text) async {
    if (state.appelEnCours || ref.read(lancementFicheProvider(ticketId))) {
      return const EchecReponse(CauseEchecReponse.autre);
    }
    final repository = ref.read(ticketsRepositoryProvider);
    state = state.copyWith(brouillonReponse: () => text, reponseEnCours: true);
    final echec = await repository.answer(ticketId: ticketId, answer: text);
    if (!ref.mounted) return echec;
    state = state.copyWith(
      brouillonReponse: () => echec == null ? null : text,
      reponseEnCours: false,
      echecReponse: () => echec,
    );
    return echec;
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
  static const decisionsLoadError = 'Impossible de lire les décisions.';

  Ticket get _ticket => widget.ticket;

  @override
  void didUpdateWidget(covariant _Fiche oldWidget) {
    super.didUpdateWidget(oldWidget);
    final status = widget.ticket.status;
    // Ticket devenu Refusé ou Clos (décision au résultat inconnu, ou prise
    // ailleurs) : les brouillons de Refuser et Clore s'effacent. Après le
    // dessin : un fournisseur ne change pas pendant la construction.
    if (status != oldWidget.ticket.status &&
        (status == TicketStatus.refused || status == TicketStatus.closed)) {
      final fiche = ref.read(decisionsFicheProvider(widget.ticket.id).notifier);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => fiche.effacerBrouillons(),
      );
    }
  }

  /// Confirmation, puis appel de `validateTicket`. Le résultat s'affiche
  /// dans un message de la fiche, même si la disposition change pendant
  /// l'appel (le fournisseur reste).
  Future<void> _valider() async {
    final fiche = ref.read(decisionsFicheProvider(_ticket.id).notifier);
    final messenger = ScaffoldMessenger.of(context);
    final valideSurGithub = _valideSurGithub(_ticket);
    // ticket: aucun (confirmation)
    final ok = await confirmerAction(
      context,
      titre: 'Valider ce ticket ?',
      paragraphes: [
        valideSurGithub ? kValiderConfirmationGithub : kValiderConfirmation,
      ],
      libelle: 'Valider',
    );
    if (!ok) return;
    const action = TicketDecisionAction.validate;
    final echec = (await fiche.decider(action)).echec;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      echec == null
          ? SnackBar(
              content: Text(
                messageDecisionAppliquee(
                  action,
                  valideSurGithub: valideSurGithub,
                ),
              ),
            )
          : SnackBar(
              duration: kDureeMessageEchec,
              content: Text(messageEchecDecision(action, echec)),
            ),
    );
  }

  /// Ouvre la boîte « Refuser ce ticket » ou « Clore ce ticket ». L'appel part
  /// de la boîte et continue si elle est fermée : le résultat s'affiche alors
  /// dans un message de la fiche.
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
    final fiche = ref.read(decisionsFicheProvider(_ticket.id).notifier);
    final brouillon = ref
        .read(decisionsFicheProvider(_ticket.id))
        .brouillons[action];
    if (brouillon == null && previous != null) {
      fiche.garderBrouillon(action, previous);
    }
    // ticket: /admin/tickets/:id/fenetre/decision
    await showFeuilleOuDialogue<void>(
      context: context,
      fermetureProtegee: true,
      builder: (context) => FormulaireDecision(
        ticketId: _ticket.id,
        action: action,
        enCours: _ticket.status == TicketStatus.inProgress,
        messenger: ScaffoldMessenger.of(this.context),
      ),
    );
  }

  /// « Relancer l'envoi » : un appel, sans confirmation ; le résultat
  /// s'affiche dans un message.
  Future<void> _relancerEnvoi() async {
    final fiche = ref.read(decisionsFicheProvider(_ticket.id).notifier);
    final messenger = ScaffoldMessenger.of(context);
    final resultat = await fiche.relancerEnvoi();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: resultat.echec == null
            ? const Duration(milliseconds: 4000)
            : kDureeMessageEchec,
        content: Text(messageRelanceEnvoi(resultat)),
      ),
    );
  }

  /// Ouvre la boîte « Répondre ». La publication part de la boîte et
  /// continue si elle est fermée : le résultat s'affiche alors dans un
  /// message de la fiche.
  Future<void> _repondre(TicketAnalysisDoc? analyses) async {
    final messenger = ScaffoldMessenger.of(context);
    // ticket: /admin/tickets/:id/fenetre/reponse
    await showFeuilleOuDialogue<void>(
      context: context,
      fermetureProtegee: true,
      builder: (context) => FormulaireReponse(
        ticketId: _ticket.id,
        status: _ticket.status,
        derniereAnalyse: analyses?.lastAnalysisAt,
        messenger: messenger,
      ),
    );
  }

  /// Ouvre la boîte de lancement (P39). L'appel part de la boîte et
  /// continue si elle est fermée : le résultat s'affiche alors dans un
  /// message de la fiche. Un refus reste affiché dans la boîte.
  Future<void> _lancer(
    ActionLancement action, {
    required DateTime? relanceDe,
    required EtatLancements? quota,
    int? prNumber,
    String? avertissement,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(lancementFicheProvider(_ticket.id).notifier);
    Future<ResultatLancement>? enVol;
    // ticket: /admin/tickets/:id/fenetre/lancement
    final fin = await showDialog<FinBoiteLancement>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BoiteLancement(
        action: action,
        issueNumber: _ticket.issueNumber,
        quota: quota,
        relanceDe: relanceDe,
        prNumber: prNumber,
        avertissement: avertissement,
        typeTicket: action == ActionLancement.livraison
            ? _ticket.type.label
            : null,
        envoyer: () => enVol = notifier.lancer(action),
      ),
    );
    var resultat = fin?.resultat;
    if (fin != null && fin.detache) {
      final appel = enVol;
      if (appel == null) return;
      resultat = await appel;
    }
    if (resultat == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        // Échec ou résultat inconnu : le temps de le lire et d'agir.
        duration: resultat.issue == IssueLancement.lance
            ? const Duration(milliseconds: 4000)
            : kDureeMessageEchec,
        content: Text(resultat.message),
      ),
    );
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
    final decisions = [...?decisionsAsync.value?.valides]
      ..sort(compareDecisionsRecentFirst);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final etatLancements = _etatLancements(offline: offline, now: now);
    const gap = SizedBox(height: 16);
    final number = ticket.issueNumber;
    final issueLink = lienGithub(ticket.issueUrl);
    // Ticket En cours : la PR éligible lue dans `admin/delivery`, adresse de
    // ce dépôt seule (P39) ; ticket Livré : la PR qui l'a fermé.
    final etatPr = etatLancements.etatPr;
    final prLink = switch (ticket.status) {
      TicketStatus.delivered => lienGithub(ticket.deliveredPrUrl),
      TicketStatus.inProgress when etatPr?.eligiblePrCount == 1 =>
        lienPullRequestOuvrable(etatPr?.prUrl),
      _ => null,
    };
    final prNumber = ticket.status == TicketStatus.delivered
        ? ticket.deliveredPrNumber
        : etatPr?.prNumber;
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
                contexte: 'PR d\'un ticket',
              ),
          ],
        ),
      ],
      if (ticket.status == TicketStatus.sendFailed) ...[
        gap,
        _EnvoiImpossible(
          ticket: ticket,
          busy: ref.watch(decisionsFicheProvider(ticket.id)).relanceEnCours,
          offline: offline,
          onRetry: _relancerEnvoi,
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
      if (ticket.screenshotPath case final path?) ...[
        gap,
        CaptureDuTicket(path: path, expiresAt: ticket.screenshotExpiresAt),
      ],
      // Livraison avant Analyses : pour un ticket En cours, le blocage est le
      // texte à lire maintenant (UX T5, point 4).
      if (ticket.issueNumber != null)
        SectionLivraison(
          ticket: ticket,
          // Invitation seulement quand le bouton s'appelle « Livrer », pas
          // « Relancer la livraison ».
          livrerActif:
              etatLancements.actif == ActionLancement.livraison &&
              etatLancements.aRelancer == null,
        ),
      // Sans Issue, il n'y a rien à analyser.
      if (ticket.issueNumber != null) SectionAnalyses(ticket: ticket),
      if (ticket.issueNumber != null)
        SectionLancements(ticket: ticket, lancementActif: etatLancements.actif),
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

    // La barre ne dépend pas de l'historique des décisions : les boutons
    // viennent de `allowed_decisions`, l'appel en cours du fournisseur de la
    // fiche et du bail du ticket.
    final barre = _barre(
      context,
      decisions: decisions,
      offline: offline,
      now: now,
      etat: etatLancements,
    );

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

  /// Ligne de livraison d'un ticket En cours, dans la forme de la barre.
  _LigneLancement _ligneDeLivraison(LigneLivraison l) => (
    icon: iconeLivraison(l.ton),
    progress: l.progression,
    text: l.texte,
    precisionsVisibles: true,
    error: l.ton == TonLivraison.erreur,
    ton: l.ton,
  );

  /// « Ouvrir le ticket #9 » : la fiche du ticket qui tient le verrou ; à côté
  /// de la liste, elle remplace celle-ci (`go`), sinon elle s'empile (`push`).
  void _ouvrirTicket(BuildContext context, String id) {
    final location = AppRoutes.adminTicket(id);
    if (adminTicketsCoteACote(context)) {
      context.go(location);
    } else {
      unawaited(context.push(location));
    }
  }

  /// Décision, relance ou réponse en cours d'appel, ou bail du serveur posé :
  /// la barre n'affiche aucun bouton.
  bool _occupe(DateTime now) =>
      _ticket.decisionInProgress(now) ||
      ref.watch(decisionsFicheProvider(_ticket.id)).appelEnCours;

  /// Lancements (ADR-008, T4) : offerts d'après `allowed_decisions` seul
  /// (P39) ; « en cours » tant que `retry_after` n'est pas passé. `actif` est
  /// l'action du bouton de lancement de la barre quand il est affiché et
  /// actif : la section « Lancements » n'invite à appuyer que dans ce cas.
  _EtatLancementsFiche _etatLancements({
    required bool offline,
    required DateTime now,
  }) {
    final ticket = _ticket;
    final lancements = ticket.issueNumber == null
        ? null
        : ref.watch(ticketLaunchesProvider(ticket.id));
    final historique = switch (lancements?.value) {
      DocumentTrouve(:final value) => value,
      DocumentAbsent() => const TicketLaunchesDoc(entries: []),
      _ => null,
    };
    ActionLancement? lancement;
    for (final a in [ActionLancement.analyse, ActionLancement.developpement]) {
      if (ticket.canLaunch(a) && ticket.issueNumber != null) {
        lancement = a;
        break;
      }
    }
    final enCoursDeLivraison =
        ticket.status == TicketStatus.inProgress && ticket.issueNumber != null;
    // Le plafond se lit aussi pour un ticket à valider (« Vous pouvez
    // valider. ») et pour un ticket En cours (verrou des livraisons).
    final quota =
        lancement == null &&
            ticket.status != TicketStatus.analyzed &&
            !_valideSurGithub(ticket) &&
            !enCoursDeLivraison
        ? null
        : switch (ref.watch(launchStatusProvider).value) {
            DocumentTrouve(:final value) => value,
            _ => null,
          };
    final appelEnCours = ref.watch(lancementFicheProvider(ticket.id));
    // Ticket En cours (T5) : ligne et bouton lus dans `admin/delivery`,
    // `admin/launches` et `ticket_status/launches`, sans règle recopiée.
    LigneLivraison? livraison;
    TicketDelivery? etatPr;
    if (enCoursDeLivraison) {
      final async = ref.watch(ticketDeliveryProvider(ticket.id));
      etatPr = switch (async.value) {
        DocumentTrouve(:final value) => value,
        _ => null,
      };
      livraison = ligneLivraison(
        ticket: ticket,
        livraison: async.value,
        livraisonEnPanne:
            async.hasError && async.value is! DocumentTrouve<TicketDelivery>,
        historique: historique,
        quota: quota,
        now: now,
        offline: offline,
        appelEnCours: appelEnCours,
      );
      lancement = livraison?.action;
    }
    final enCours = lancement == null
        ? null
        : historique?.enCours(lancement, now);
    final aRelancer = switch (lancement) {
      null || ActionLancement.reprise => null,
      final a => historique?.aRelancer(
        a,
        now,
        statusChangedAt: ticket.statusChangedAt,
      ),
    };
    // Le bouton est affiché quand l'historique est lu et rien n'est en cours,
    // dans une barre qui montre ses boutons (aucune décision, relance ni
    // réponse en cours, `allowed_decisions` calculé). Il est actif en ligne,
    // sans appel en cours, plafond du jour non atteint.
    final actif =
        lancement != null &&
            historique != null &&
            enCours == null &&
            ticket.allowedDecisions != null &&
            !_occupe(now) &&
            !offline &&
            !appelEnCours &&
            !(quota?.plafondAtteint ?? false) &&
            (livraison == null || livraison.actif)
        ? lancement
        : null;
    return (
      lancements: lancements,
      historique: historique,
      lancement: lancement,
      quota: quota,
      appelEnCours: appelEnCours,
      enCours: enCours,
      aRelancer: aRelancer,
      actif: actif,
      livraison: livraison,
      etatPr: etatPr,
    );
  }

  /// Barre de décision : ligne de l'appel en cours, puis les boutons de
  /// `allowed_decisions` (P26). `null` s'il n'y a rien à montrer.
  Widget? _barre(
    BuildContext context, {
    required List<TicketDecision> decisions,
    required bool offline,
    required DateTime now,
    required _EtatLancementsFiche etat,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ticket = _ticket;
    final fiche = ref.watch(decisionsFicheProvider(ticket.id));
    final busy = _occupe(now);
    final enCoursDecision = fiche.decisionEnCours;
    // Une seule ligne d'appel : la décision de cette fiche, la réponse, puis
    // le bail du serveur (décision prise depuis un autre appareil).
    final ({String progress, String text})? ligne = switch (enCoursDecision) {
      final action? => (
        progress: indicateurDecision(action),
        text: ligneDecisionEnCours(action),
      ),
      null when fiche.reponseEnCours => (
        progress: 'Publication en cours',
        text: kPublicationReponseEnCours,
      ),
      null when ticket.decisionInProgress(now) => (
        progress: 'Décision en cours',
        text: 'Décision en cours sur GitHub.',
      ),
      null => null,
    };

    final allowed = ticket.allowedDecisions;
    // Les analyses ne se lisent que pour un ticket publié (section de la
    // fiche) : la date de la dernière analyse et des précisions en attente.
    final analyses = ticket.issueNumber == null
        ? null
        : switch (ref.watch(ticketAnalysisProvider(ticket.id)).value) {
            DocumentTrouve(:final value) => value,
            _ => null,
          };
    final enAttente = ticket.status == TicketStatus.received
        ? analyses?.pendingAnswerAt
        : null;

    final lancements = etat.lancements;
    final historique = etat.historique;
    final lancement = etat.lancement;
    final valideSurGithub = _valideSurGithub(ticket);
    final quota = etat.quota;
    final appelEnCours = etat.appelEnCours;
    final enCours = etat.enCours;
    final aRelancer = etat.aRelancer;
    // Pendant un développement en cours, « Répondre » est masqué (Kass'Dalle).
    final developpementEnCours =
        historique?.enCours(ActionLancement.developpement, now) != null;
    final repondre = ticket.canAnswer && !developpementEnCours;

    // Une seule ligne de lancement, par ordre de priorité. La ligne des
    // précisions en attente s'affiche en plus, sous elle, sauf pendant un
    // lancement en cours (`precisionsVisibles`).
    final enCoursDepuis = enCours?.at;
    final relanceDe = aRelancer?.at;
    final _LigneLancement? ligneLancement = switch (lancement) {
      _ when etat.livraison != null => _ligneDeLivraison(etat.livraison!),
      // Appel d'un lancement sans bouton de lancement affiché (statut changé
      // entre-temps) : la ligne explique les boutons inactifs.
      null when appelEnCours => (
        icon: null,
        progress: 'Lancement en cours',
        text: 'Lancement en cours.',
        precisionsVisibles: false,
        error: false,
        ton: null,
      ),
      null when quota != null && quota.plafondAtteint => (
        icon: Icons.event_busy,
        progress: null,
        text: lignePlafondAnalyse(quota),
        precisionsVisibles: true,
        error: false,
        ton: null,
      ),
      null => null,
      final a when appelEnCours => (
        icon: null,
        progress: 'Lancement en cours',
        text: 'Lancement de ${a.complement} en cours.',
        precisionsVisibles: false,
        error: false,
        ton: null,
      ),
      final a when enCours != null => (
        icon: Icons.hourglass_top,
        progress: null,
        text: enCoursDepuis == null
            ? '${a.nom} en cours.'
            : ligneEnCours(a, enCoursDepuis, now),
        precisionsVisibles: false,
        error: false,
        ton: null,
      ),
      // Plafond avant la relance : il explique le bouton inactif.
      _ when quota?.plafondAtteint ?? false => (
        icon: Icons.event_busy,
        progress: null,
        text: ligneQuota(quota),
        precisionsVisibles: true,
        error: false,
        ton: null,
      ),
      _ when relanceDe != null => (
        icon: Icons.info_outline,
        progress: null,
        text: BoiteLancement.avertissementRelance(relanceDe),
        precisionsVisibles: true,
        error: false,
        ton: null,
      ),
      _ => null,
    };

    // Historique en lecture : une barre de progression à la place du bouton ;
    // illisible : aucun bouton, la panne est dans la section. Hors ligne, ou
    // historique absent du cache : pas de barre, la ligne « hors ligne » dit
    // pourquoi aucun lancement n'est possible.
    final lectureLancements =
        lancement != null &&
        !offline &&
        historique == null &&
        !(lancements?.hasError ?? false) &&
        lancements?.value is! DocumentIllisibleTrouve &&
        lancements?.value is! DocumentAbsentDuCache;
    Widget? boutonLancement;
    final livraison = etat.livraison;
    if (lancement != null && historique != null && enCours == null) {
      final action = lancement;
      final avertissement =
          action == ActionLancement.livraison && relanceDe != null
          ? livraison?.texte
          : null;
      // Hors ligne, appel en cours ou plafond atteint le jour écrit par le
      // serveur : bouton inactif, la ligne de la barre dit pourquoi.
      final onPressed = etat.actif == null
          ? null
          : () => _lancer(
              action,
              relanceDe: relanceDe,
              quota: quota,
              prNumber: etat.etatPr?.prNumber,
              avertissement: avertissement,
            );
      boutonLancement = switch (action) {
        ActionLancement.livraison when relanceDe == null => FilledButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Livrer'),
        ),
        ActionLancement.reprise => FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(Icons.refresh),
          label: const Text('Relancer le développement'),
        ),
        _ when relanceDe == null => FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(switch (action) {
            ActionLancement.analyse => Icons.manage_search,
            _ => Icons.code,
          }),
          label: Text('Lancer ${action.complement}'),
        ),
        _ => FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(Icons.refresh),
          label: Text('Relancer ${action.complement}'),
        ),
      };
    }
    // Livraison de ce ticket en cours : Refuser et Clore masqués (P39, P44).
    final masquer = livraison?.masquerRefuserClore ?? false;
    // Relecture de `admin/delivery` après « Réessayer » : bouton inactif,
    // avec un indicateur, jusqu'à la fin de la lecture.
    final relectureLivraison =
        (livraison?.reessayer ?? false) &&
        ref.watch(ticketDeliveryProvider(ticket.id)).isLoading;

    // Un lancement en cours d'appel : décisions et « Répondre » inactifs.
    final inactif = offline || appelEnCours;
    Widget? actions;
    if (!busy) {
      if (allowed == null) {
        actions = Text(
          'Le serveur n\'a pas encore calculé les décisions possibles pour ce '
          'ticket.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        );
      } else if (allowed.isNotEmpty || repondre || lancement != null) {
        final boutons = OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 8,
          overflowSpacing: 8,
          children: [
            // Décisions et « Répondre » appellent le serveur : inactifs hors
            // ligne, la ligne sous les boutons dit pourquoi ; inactifs aussi
            // pendant l'appel d'un lancement (un seul appel à la fois).
            if (allowed.contains(TicketDecisionAction.refuse) && !masquer)
              OutlinedButton.icon(
                onPressed: inactif
                    ? null
                    : () => _demanderTexte(
                        TicketDecisionAction.refuse,
                        decisions,
                      ),
                icon: const Icon(Icons.block),
                label: const Text('Refuser'),
              ),
            if (repondre)
              OutlinedButton.icon(
                onPressed: inactif ? null : () => _repondre(analyses),
                icon: const Icon(Icons.reply),
                label: const Text('Répondre'),
              ),
            if (allowed.contains(TicketDecisionAction.close) && !masquer)
              OutlinedButton.icon(
                onPressed: inactif
                    ? null
                    : () =>
                          _demanderTexte(TicketDecisionAction.close, decisions),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Clore'),
              ),
            if (allowed.contains(TicketDecisionAction.validate))
              FilledButton.icon(
                onPressed: inactif ? null : _valider,
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: const Text('Valider'),
              ),
            ?boutonLancement,
          ],
        );
        // La ligne des précisions reste sous la ligne du plafond ou de la
        // relance ; seul un lancement en cours la masque.
        final lignePrecisions =
            enAttente != null &&
            (ligneLancement == null || ligneLancement.precisionsVisibles);
        // Hors ligne, une seule ligne pour tous les boutons offerts : elle
        // s'affiche aussi quand l'historique des lancements, absent du cache,
        // retient le bouton de lancement.
        final horsLigne = offline ? kActionsHorsLigne : null;
        actions = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ligneLancement case final l?) ...[
              Semantics(
                liveRegion: true,
                container: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (l.progress case final label?) ...[
                      LinearProgressIndicator(semanticsLabel: label),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (l.icon case final icon?) ...[
                          ExcludeSemantics(
                            child: Icon(
                              icon,
                              color: switch (l.ton) {
                                final ton? => couleurIconeLivraison(
                                  ton,
                                  scheme,
                                ),
                                null => scheme.onSurface,
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            l.text,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: l.error ? scheme.error : null,
                            ),
                          ),
                        ),
                        if (livraison != null && livraison.reessayer)
                          IconButton(
                            tooltip: relectureLivraison
                                ? 'Lecture en cours'
                                : 'Réessayer',
                            onPressed: relectureLivraison
                                ? null
                                : () => ref.invalidate(
                                    ticketDeliveryProvider(ticket.id),
                                  ),
                            icon: relectureLivraison
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      semanticsLabel: 'Lecture en cours',
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                          ),
                      ],
                    ),
                    if (livraison?.verrouTicketId case final autre?) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: () => _ouvrirTicket(context, autre),
                          child: Text(
                            livraison?.verrouIssue == null
                                ? 'Ouvrir le ticket'
                                : 'Ouvrir le ticket #${livraison?.verrouIssue}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (lignePrecisions) ...[
              Text(
                'Vos précisions du ${formatDateChiffres(enAttente)} à '
                '${formatHeure(enAttente)} seront lues par la prochaine '
                'analyse.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
            ],
            if (lectureLancements) ...[
              const LinearProgressIndicator(
                semanticsLabel: 'Lecture des lancements',
              ),
              const SizedBox(height: 8),
            ],
            boutons,
            if (ticket.status == TicketStatus.received &&
                !allowed.contains(TicketDecisionAction.validate)) ...[
              const SizedBox(height: 8),
              Text(
                kValiderApresAnalyse,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (valideSurGithub) ...[
              const SizedBox(height: 8),
              Text(
                kValiderDepuisApplication,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (horsLigne != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                container: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Icon(Icons.cloud_off, color: scheme.onSurface),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(horsLigne, style: theme.textTheme.bodyLarge),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      }
    }
    if (ligne == null && actions == null) return null;
    // À l'échéance d'un lancement en cours, la barre se redessine et propose
    // « Relancer » ou rend « Répondre ».
    final verrou = quota?.deliveryRunning;
    final echeances = [
      ?enCours?.retryAfter,
      ?historique?.enCours(ActionLancement.developpement, now)?.retryAfter,
      ?historique?.enCours(ActionLancement.livraison, now)?.retryAfter,
      ?historique?.enCours(ActionLancement.reprise, now)?.retryAfter,
      if (verrou != null && verrou.tient(now)) ?verrou.retryAfter,
    ]..sort();
    return ReconstruireA(
      instant: echeances.isEmpty ? null : echeances.first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ligne case final l?)
            Semantics(
              liveRegion: true,
              container: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(semanticsLabel: l.progress),
                  const SizedBox(height: 8),
                  Text(l.text, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          if (ligne != null && actions != null) const SizedBox(height: 12),
          ?actions,
        ],
      ),
    );
  }
}

/// Couleur de l'icône d'une ligne de livraison : `primary` pour une PR
/// prête, `error` pour un échec, sinon la couleur du texte.
Color couleurIconeLivraison(TonLivraison ton, ColorScheme scheme) =>
    switch (ton) {
      TonLivraison.prete => scheme.primary,
      TonLivraison.erreur => scheme.error,
      _ => scheme.onSurface,
    };

/// Icône d'une ligne de livraison ; `null` pour une barre de progression.
IconData? iconeLivraison(TonLivraison ton) => switch (ton) {
  TonLivraison.progression => null,
  TonLivraison.enCours => Icons.hourglass_top,
  TonLivraison.info => Icons.info_outline,
  TonLivraison.prete => Icons.check_circle_outline,
  TonLivraison.erreur => Icons.error_outline,
  TonLivraison.plafond => Icons.event_busy,
};

/// Bloc d'un ticket `send_failed` : essais, dernière erreur, « Relancer
/// l'envoi » (`retryTicketSend`, ADR-008, T7).
class _EnvoiImpossible extends StatelessWidget {
  const _EnvoiImpossible({
    required this.ticket,
    required this.busy,
    required this.offline,
    required this.onRetry,
  });

  final Ticket ticket;
  final bool busy;

  /// Hors ligne, le bouton est inactif et une ligne dit pourquoi.
  final bool offline;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attempts = ticket.sendAttempts;
    final error = ticket.lastSendError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attempts != null)
          Text('Essais d\'envoi : $attempts', style: theme.textTheme.bodyLarge),
        if (error != null)
          Text('Dernière erreur : $error', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: busy || offline ? null : onRetry,
          icon: const Icon(Icons.refresh),
          label: busy
              ? const IndicateurBouton(label: 'Relance en cours')
              : const Text('Relancer l\'envoi'),
        ),
        if (offline) ...[
          const SizedBox(height: 8),
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
                    kRelancerEnvoiHorsLigne,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Boîte « Refuser ce ticket » ou « Clore ce ticket » (ADR-008, T7) : publie
/// le motif ou le commentaire par `refuseTicket` ou `closeTicket`. La boîte
/// peut se fermer pendant l'appel : le résultat s'affiche alors par
/// [messenger], celui de la fiche. Le texte saisi reste en brouillon dans la
/// fiche ; hors ligne, il est gardé et rien ne part.
class FormulaireDecision extends ConsumerStatefulWidget {
  const FormulaireDecision({
    super.key,
    required this.ticketId,
    required this.action,
    required this.enCours,
    required this.messenger,
  });

  final String ticketId;
  final TicketDecisionAction action;

  /// Le ticket est « En cours » : une pull request est peut-être ouverte.
  final bool enCours;
  final ScaffoldMessengerState messenger;

  static const publicWarning =
      'Publié sur un site public : n\'écrivez ni nom ni adresse. Le membre '
      'lira aussi ce texte.';
  static const prWarning =
      'Une pull request est peut-être ouverte. Elle ne sera pas fermée.';

  @override
  ConsumerState<FormulaireDecision> createState() => _FormulaireDecisionState();
}

class _FormulaireDecisionState extends ConsumerState<FormulaireDecision> {
  final _formKey = GlobalKey<FormState>();
  final _focus = FocusNode();
  final _focusBouton = FocusNode();
  late final TextEditingController _text = TextEditingController(
    text:
        ref
            .read(decisionsFicheProvider(widget.ticketId))
            .brouillons[widget.action] ??
        '',
  );

  bool get _refus => widget.action == TicketDecisionAction.refuse;

  String get _nom => _refus ? 'Le motif' : 'Le commentaire';

  @override
  void initState() {
    super.initState();
    // Réouverture après un motif du serveur sur le texte : l'erreur revient
    // sous le champ dès le premier dessin.
    final echec = ref
        .read(decisionsFicheProvider(widget.ticketId))
        .echecDe(widget.action);
    if (echec != null && echec.surLeChamp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formKey.currentState?.validate();
      });
    }
  }

  /// Texte figé : focus au bouton d'action après le dessin qui reflète
  /// l'échec, ou au champ en lecture seule si ce bouton est inactif.
  void _focusApresRendu() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_focusBouton.canRequestFocus ? _focusBouton : _focus).requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _focusBouton.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _focus.requestFocus();
      return;
    }
    final messenger = widget.messenger;
    final action = widget.action;
    final fiche = ref.read(decisionsFicheProvider(widget.ticketId).notifier);
    // Une boîte fermée pendant l'appel reste montée le temps de son animation
    // de sortie : seule une route encore active affiche le résultat.
    final route = ModalRoute.of(context);
    final resultat = await fiche.decider(action, text: _text.text.trim());
    final echec = resultat.echec;
    final ouverte = route?.isActive ?? false;
    if (echec == null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            messageDecisionAppliquee(
              action,
              valideSurGithub: false,
              texteGarde: resultat.texteGarde,
            ),
          ),
        ),
      );
      if (mounted && ouverte) Navigator.of(context).pop();
      return;
    }
    if (mounted && ouverte) {
      // L'échec est affiché dans la boîte. Focus au champ ; texte figé (motif
      // déjà publié) : au bouton d'action, seul geste utile, ou au champ en
      // lecture seule si ce bouton est inactif (hors ligne, autre appel).
      _formKey.currentState?.validate();
      if (echec.partiel) {
        _focusApresRendu();
      } else {
        _focus.requestFocus();
      }
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: kDureeMessageEchec,
        content: Text(messageEchecDecision(action, echec)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final etat = ref.watch(decisionsFicheProvider(widget.ticketId));
    final enCours = etat.decisionEnCours == widget.action;
    final echec = etat.echecDe(widget.action);
    final partiel = echec?.partiel ?? false;
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final verbe = _refus ? 'Refuser' : 'Clore';
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
          const Encadre(
            ton: TonEncadre.avertissement,
            icone: Icons.public,
            child: Text(FormulaireDecision.publicWarning),
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
            // Texte figé (motif déjà publié) : le focus va au bouton d'action,
            // ou à « Annuler » si ce bouton est inactif.
            autofocus: !partiel,
            enabled: !enCours,
            readOnly: partiel,
            // Une frappe revalide : le motif du serveur s'efface avec elle.
            autovalidateMode: AutovalidateMode.onUserInteraction,
            minLines: 3,
            maxLines: 8,
            maxLength: kDecisionTextMaxLength,
            // Le serveur compte en points de code : un émoji compte pour un,
            // et la saisie n'est pas coupée au-delà (le validateur refuse).
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) {
                  // Même compte que le validateur : texte sans ses espaces
                  // de bord.
                  final n = _text.text.trim().runes.length;
                  final reste = kDecisionTextMaxLength - n;
                  return Semantics(
                    label: reste >= 0
                        ? (reste > 1
                              ? '$reste caractères restants'
                              : '$reste caractère restant')
                        : (reste < -1
                              ? '${-reste} caractères en trop'
                              : '1 caractère en trop'),
                    liveRegion: isFocused,
                    child: ExcludeSemantics(
                      child: Text(
                        '$n/$kDecisionTextMaxLength',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: n > kDecisionTextMaxLength
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
            onChanged: (t) => ref
                .read(decisionsFicheProvider(widget.ticketId).notifier)
                .garderBrouillon(widget.action, t),
            decoration: InputDecoration(
              labelText: _refus ? 'Motif du refus' : 'Commentaire de clôture',
              helperText: _refus
                  ? 'L\'Issue sera fermée comme non prévue.'
                  : 'Le membre lira ce texte : réponse, ou raison de la '
                        'clôture.',
              helperMaxLines: 3,
              errorMaxLines: 3,
            ),
            validator: (value) {
              // Points de code, comme le serveur.
              final n = (value ?? '').trim().runes.length;
              if (n < kDecisionTextMinLength) {
                return '$_nom doit faire au moins 5 caractères.';
              }
              if (n > kDecisionTextMaxLength) {
                return '$_nom ne doit pas dépasser 4 000 caractères.';
              }
              final e = ref
                  .read(decisionsFicheProvider(widget.ticketId))
                  .echecDe(widget.action);
              return e != null && e.surLeChamp ? e.motif : null;
            },
          ),
          if (enCours) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                '${widget.action.nom} en cours. Vous pouvez fermer : le '
                'résultat s\'affichera dans un message.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ] else if (echec != null && !echec.surLeChamp) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                messageEchecDecision(widget.action, echec),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: partiel ? null : scheme.error,
                ),
              ),
            ),
          ],
          if (offline && !enCours) ...[
            const SizedBox(height: 8),
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
                      '$verbe demande le réseau. Votre texte est gardé.',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              // La fermeture ne coupe pas l'appel.
              TextButton(
                // Texte figé et action inactive (hors ligne, autre appel) :
                // le focus va à « Annuler » plutôt que nulle part.
                autofocus: partiel && (enCours || offline || etat.appelEnCours),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(enCours ? 'Fermer' : 'Annuler'),
              ),
              FilledButton(
                focusNode: _focusBouton,
                autofocus:
                    partiel && !(enCours || offline || etat.appelEnCours),
                onPressed: enCours || offline || etat.appelEnCours
                    ? null
                    : _envoyer,
                child: enCours
                    ? IndicateurBouton(label: indicateurDecision(widget.action))
                    : Text(verbe),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Message d'un échec de « Répondre », dans la boîte ou en bas d'écran. Un
/// échec partiel dit que la réponse est déjà sur GitHub.
String messageEchecReponse(EchecReponse echec) =>
    echec.partiel ? FormulaireReponse.dejaPubliee : _messageEchec(echec);

String _messageEchec(EchecReponse echec) => switch (echec.cause) {
  CauseEchecReponse.reseau =>
    'Réponse non publiée : pas de réseau. Votre texte est gardé.',
  CauseEchecReponse.delai =>
    'Réponse non publiée : le serveur n\'a pas répondu à temps. Vérifiez '
        'l\'Issue avant de publier à nouveau.',
  CauseEchecReponse.acces =>
    'Réponse non publiée : accès administrateur refusé.',
  CauseEchecReponse.motif =>
    'Réponse non publiée : ${echec.motif} Votre texte est gardé.',
  CauseEchecReponse.autre => 'Réponse non publiée. Votre texte est gardé.',
};

/// Message d'une réponse publiée ; [recu] : le ticket était « Reçu ».
String messageReponsePubliee({required bool recu}) => recu
    ? 'Réponse publiée. Elle sera lue par la prochaine analyse.'
    : 'Réponse publiée. Le ticket repasse à Reçu.';

/// Boîte « Répondre » (ADR-008) : publie les précisions de l'administrateur
/// par `answerTicketAnalysis`. La boîte peut se fermer pendant l'envoi : le
/// résultat s'affiche alors par [messenger], celui de la fiche.
class FormulaireReponse extends ConsumerStatefulWidget {
  const FormulaireReponse({
    super.key,
    required this.ticketId,
    required this.status,
    required this.derniereAnalyse,
    required this.messenger,
  });

  final String ticketId;

  /// Statut à l'ouverture : il choisit les textes de la boîte.
  final TicketStatus status;

  /// Date de la dernière analyse, en sous-titre.
  final DateTime? derniereAnalyse;
  final ScaffoldMessengerState messenger;

  static const publicWarning =
      'Publié sur un site public : n\'écrivez ni nom ni adresse. Le membre ne '
      'lira pas ce texte dans l\'application.';
  static const tropCourt = 'La réponse doit faire au moins 5 caractères.';
  static const tropLong = 'La réponse ne doit pas dépasser 4 000 caractères.';
  static const enCours =
      'Publication en cours. Vous pouvez fermer : le résultat s\'affichera '
      'dans un message.';
  static const horsLigne = 'Répondre demande le réseau. Votre texte est gardé.';
  static const dejaPubliee =
      'Cette réponse est déjà publiée sur GitHub. Publier remet le ticket à '
      'Reçu.';

  @override
  ConsumerState<FormulaireReponse> createState() => _FormulaireReponseState();
}

class _FormulaireReponseState extends ConsumerState<FormulaireReponse> {
  final _formKey = GlobalKey<FormState>();
  final _focus = FocusNode();
  final _focusBouton = FocusNode();
  late final TextEditingController _text = TextEditingController(
    text:
        ref.read(decisionsFicheProvider(widget.ticketId)).brouillonReponse ??
        '',
  );

  bool get _recu => widget.status == TicketStatus.received;

  @override
  void initState() {
    super.initState();
    // Réouverture après un motif du serveur sur le texte : l'erreur revient
    // sous le champ dès le premier dessin.
    final echec = ref
        .read(decisionsFicheProvider(widget.ticketId))
        .echecReponse;
    if (echec != null && echec.surLeChamp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formKey.currentState?.validate();
      });
    }
  }

  /// Texte figé : focus au bouton d'action après le dessin qui reflète
  /// l'échec, ou au champ en lecture seule si ce bouton est inactif.
  void _focusApresRendu() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_focusBouton.canRequestFocus ? _focusBouton : _focus).requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _focusBouton.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _publier() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _focus.requestFocus();
      return;
    }
    final messenger = widget.messenger;
    final recu = _recu;
    final notifier = ref.read(decisionsFicheProvider(widget.ticketId).notifier);
    // Une boîte fermée pendant l'appel reste montée le temps de son animation
    // de sortie : seule une route encore active affiche le résultat.
    final route = ModalRoute.of(context);
    final echec = await notifier.publierReponse(_text.text.trim());
    final ouverte = route?.isActive ?? false;
    if (echec == null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(messageReponsePubliee(recu: recu))),
      );
      if (mounted && ouverte) Navigator.of(context).pop();
      return;
    }
    if (mounted && ouverte) {
      // L'échec est affiché dans la boîte. Focus au champ ; texte figé
      // (réponse déjà publiée) : au bouton « Publier », ou au champ en
      // lecture seule si ce bouton est inactif (hors ligne, autre appel).
      _formKey.currentState?.validate();
      if (echec.partiel) {
        _focusApresRendu();
      } else {
        _focus.requestFocus();
      }
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: kDureeMessageEchec,
        content: Text(messageEchecReponse(echec)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final etat = ref.watch(decisionsFicheProvider(widget.ticketId));
    final enCours = etat.reponseEnCours;
    final echec = etat.echecReponse;
    final partiel = echec?.partiel ?? false;
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final analyse = widget.derniereAnalyse;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              _recu ? 'Répondre au ticket' : 'Répondre à l\'analyse',
              style: theme.textTheme.headlineSmall,
            ),
          ),
          if (analyse != null) ...[
            const SizedBox(height: 4),
            Text(
              dateAnalyse('Analyse', analyse),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Encadre(
            ton: TonEncadre.avertissement,
            icone: Icons.public,
            child: Text(FormulaireReponse.publicWarning),
          ),
          const SizedBox(height: 12),
          Text(
            _recu
                ? 'Ajoutez une précision avant l\'analyse. Elle sera lue par la '
                      'session d\'analyse.'
                : 'Le ticket repassera à « Reçu ». La prochaine analyse lira '
                      'votre réponse.',
          ),
          if (widget.status == TicketStatus.validated) ...[
            const SizedBox(height: 8),
            const Text('La validation sera retirée.'),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _text,
            focusNode: _focus,
            // Texte figé (réponse déjà publiée) : le focus va à « Publier »,
            // ou à « Annuler » si ce bouton est inactif.
            autofocus: !partiel,
            enabled: !enCours,
            readOnly: partiel,
            // Une frappe revalide : le motif du serveur s'efface avec elle.
            autovalidateMode: AutovalidateMode.onUserInteraction,
            minLines: 4,
            maxLines: 10,
            maxLength: kTicketAnswerMaxLength,
            // Le serveur compte en points de code : un émoji compte pour un,
            // et la saisie n'est pas coupée au-delà (le validateur refuse).
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) {
                  // Même compte que le validateur : texte sans ses espaces
                  // de bord.
                  final n = _text.text.trim().runes.length;
                  final reste = kTicketAnswerMaxLength - n;
                  return Semantics(
                    label: reste >= 0
                        ? (reste > 1
                              ? '$reste caractères restants'
                              : '$reste caractère restant')
                        : (reste < -1
                              ? '${-reste} caractères en trop'
                              : '1 caractère en trop'),
                    liveRegion: isFocused,
                    child: ExcludeSemantics(
                      child: Text(
                        '$n/$kTicketAnswerMaxLength',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: n > kTicketAnswerMaxLength
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
            onChanged: (t) => ref
                .read(decisionsFicheProvider(widget.ticketId).notifier)
                .garderBrouillonReponse(t),
            decoration: InputDecoration(
              labelText: 'Votre réponse',
              helperText:
                  '${_recu ? 'Précisez votre demande.' : 'Répondez aux '
                            'questions de l\'analyse.'} Les adresses e-mail et '
                  'les mentions seront retirées.',
              helperMaxLines: 3,
              errorMaxLines: 3,
            ),
            validator: (value) {
              // Points de code, comme le serveur.
              final n = (value ?? '').trim().runes.length;
              if (n < kTicketAnswerMinLength) {
                return FormulaireReponse.tropCourt;
              }
              if (n > kTicketAnswerMaxLength) {
                return FormulaireReponse.tropLong;
              }
              final e = ref
                  .read(decisionsFicheProvider(widget.ticketId))
                  .echecReponse;
              return e != null && e.surLeChamp ? e.motif : null;
            },
          ),
          if (enCours) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                FormulaireReponse.enCours,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ] else if (partiel) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                FormulaireReponse.dejaPubliee,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ] else if (echec != null && !echec.surLeChamp) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                messageEchecReponse(echec),
                style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error),
              ),
            ),
          ],
          if (offline && !enCours) ...[
            const SizedBox(height: 8),
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
                      FormulaireReponse.horsLigne,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              // La fermeture ne coupe pas l'appel.
              TextButton(
                // Texte figé et action inactive (hors ligne, autre appel) :
                // le focus va à « Annuler » plutôt que nulle part.
                autofocus: partiel && (enCours || offline || etat.appelEnCours),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(enCours ? 'Fermer' : 'Annuler'),
              ),
              FilledButton(
                focusNode: _focusBouton,
                autofocus:
                    partiel && !(enCours || offline || etat.appelEnCours),
                onPressed: enCours || offline || etat.appelEnCours
                    ? null
                    : _publier,
                child: enCours
                    ? const IndicateurBouton(label: 'Publication en cours')
                    : const Text('Publier'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
