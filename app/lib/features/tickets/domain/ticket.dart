import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import 'ticket_launch.dart';

/// Bornes d'un ticket, les mêmes que `firestore.rules` (P23).
const kTicketTitleMinLength = 5;
const kTicketTitleMaxLength = 100;
const kTicketDescriptionMinLength = 10;
const kTicketDescriptionMaxLength = 2000;

/// Capture d'écran jointe à un ticket (ADR-008, T6) : 5 Mo au plus, comme
/// `storage.rules` et `attachTicketScreenshot`.
const kTicketScreenshotMaxBytes = 5 * 1024 * 1024;

/// Chemin Storage d'une capture : `tickets/{uid}/{ticketId}/screenshot.png`,
/// seul nom que `storage.rules` accepte.
final kTicketScreenshotPathPattern = RegExp(
  r'^tickets/[A-Za-z0-9_-]{1,128}/[A-Za-z0-9_-]{1,128}/screenshot\.png$',
);

/// Chemin Storage de la capture PNG du ticket [ticketId] de [uid].
String ticketScreenshotPath(String uid, String ticketId) =>
    'tickets/$uid/$ticketId/screenshot.png';

/// Au-delà de ce délai, un ticket `pending` est en retard : la tâche horaire
/// aurait dû le transmettre.
const kTicketSendDelay = Duration(hours: 1);

/// Bornes du texte d'un refus ou d'une clôture, les mêmes que `firestore.rules`
/// (P23).
const kDecisionTextMinLength = 5;
const kDecisionTextMaxLength = 2000;

/// Au-delà de ce délai, une décision `pending` n'a pas été prise en compte par
/// le serveur : l'écran le dit.
const kDecisionPendingDelay = Duration(minutes: 2);

/// Type d'un ticket (`tickets/{id}.type`).
enum TicketType {
  bug('bug', 'Bug', 'Quelque chose ne marche pas'),
  evolution('evolution', 'Évolution', 'Améliorer ce qui existe'),
  feature(
    'feature',
    'Nouvelle fonctionnalité',
    'Pouvoir faire quelque chose de nouveau',
  );

  const TicketType(this.storedValue, this.label, this.help);

  final String storedValue;
  final String label;

  /// Aide sous le libellé, dans le formulaire.
  final String help;

  /// Plan de description proposé au-dessus du champ.
  String get descriptionPlan => switch (this) {
    TicketType.bug =>
      'Ce que vous faisiez : …\nCe qui s\'est passé : …\n'
          'Ce que vous attendiez : …',
    TicketType.evolution =>
      'Ce qui existe aujourd\'hui : …\nCe que vous aimeriez changer : …\n'
          'Pourquoi ce serait utile : …',
    TicketType.feature =>
      'Ce que vous aimeriez pouvoir faire : …\nDans quelle situation (jour de '
          'brassage, préparation d\'une recette…) : …\n'
          'Comment vous faites aujourd\'hui : …',
  };

  static TicketType? fromStored(Object? value) {
    for (final t in values) {
      if (t.storedValue == value) return t;
    }
    return null;
  }
}

/// Statut d'un ticket, écrit par le serveur seul (sauf `pending` à la création).
///
/// Une valeur que cette version ne connaît pas se lit [unknown] : le ticket
/// reste lisible, l'écran dit « Statut inconnu ».
enum TicketStatus {
  pending('pending'),
  received('received'),

  /// Analysé : étiquette `statut:analysé` posée sur l'Issue (ADR-008).
  analyzed('analyzed'),
  validated('validated'),
  inProgress('in_progress'),
  delivered('delivered'),
  refused('refused'),
  closed('closed'),
  sendFailed('send_failed'),
  overQuota('over_quota'),
  unknown(null);

  const TicketStatus(this.storedValue);

  /// Valeur de Firestore ; `null` pour [unknown].
  final String? storedValue;

  static TicketStatus fromStored(String value) {
    for (final s in values) {
      if (s.storedValue == value) return s;
    }
    return unknown;
  }
}

/// Contenu saisi d'un ticket, ou repris d'un ticket non transmis.
@immutable
class TicketBrouillon {
  const TicketBrouillon({
    required this.type,
    required this.title,
    required this.description,
    required this.screen,
  });

  final TicketType type;
  final String title;
  final String description;

  /// Modèle de route, `autre` ou `inconnu` (ticket_screens.dart).
  final String screen;
}

/// Document `tickets/{id}`, lu par son auteur et par l'administrateur.
///
/// Aucun prix, stock ni coût (P5). Le titre et la description partent sur une
/// Issue publique, nettoyés par le serveur ; Firestore garde le texte saisi.
@immutable
class Ticket {
  const Ticket({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.screen,
    required this.status,
    this.appVersion,
    this.platform,
    this.createdAt,
    this.statusChangedAt,
    this.seenByAuthorAt,
    this.replyText,
    this.deliveredPrUrl,
    this.deliveredVersion,
    this.authorEmail,
    this.issueNumber,
    this.issueUrl,
    this.deliveredPrNumber,
    this.sendAttempts,
    this.lastSendError,
    this.issueMissingSince,
    this.allowedDecisions,
    this.canAnswer = false,
    this.canLaunchAnalysis = false,
    this.canLaunchDevelopment = false,
    this.canLaunchDelivery = false,
    this.canRelaunchDevelopment = false,
    this.decisionLeaseUntil,
    this.retryRequestedAt,
    this.screenshotPath,
    this.hasPendingWrites = false,
  });

  final String id;
  final TicketType type;
  final String title;
  final String description;
  final String screen;
  final TicketStatus status;
  final String? appVersion;

  /// `android` ou `web` ; une autre valeur s'affiche telle quelle.
  final String? platform;

  /// Heure du serveur ; tant que la création l'attend, heure de l'appareil si
  /// le ticket a été créé dans cette session, sinon `null`.
  final DateTime? createdAt;
  final DateTime? statusChangedAt;
  final DateTime? seenByAuthorAt;

  /// Réponse de l'administrateur, relevée sur l'Issue par le serveur.
  final String? replyText;

  /// Adresse de la modification fusionnée, écrite par le serveur.
  final String? deliveredPrUrl;

  /// Version lue au commit de fusion, sans `+build`.
  final String? deliveredVersion;

  /// E-mail de l'auteur, en minuscules ; montré à l'administrateur seul.
  final String? authorEmail;

  /// Numéro et adresse de l'Issue, écrits par le serveur à la publication.
  final int? issueNumber;
  final String? issueUrl;

  /// Numéro de la modification fusionnée.
  final int? deliveredPrNumber;

  /// Essais de publication en échec, et message du dernier (serveur).
  final int? sendAttempts;
  final String? lastSendError;

  /// L'Issue est introuvable sur GitHub depuis cette date (serveur).
  final DateTime? issueMissingSince;

  /// Chemin Cloud Storage de la capture jointe, écrit par
  /// `attachTicketScreenshot` seul (ADR-008, T6) ; `null` sans capture. Un
  /// chemin hors de [kTicketScreenshotPathPattern] n'est jamais lu dans
  /// Storage : « Capture indisponible. ».
  final String? screenshotPath;

  /// Décisions que le statut permet, calculées par le serveur seul (P26).
  /// `null` : le serveur ne les a pas encore écrites. Une valeur que cette
  /// version ne connaît pas est ignorée.
  final List<TicketDecisionAction>? allowedDecisions;

  /// `answer` figure dans `allowed_decisions` : « Répondre » est permis
  /// (callable `answerTicketAnalysis`, ADR-008). Écrit par le serveur seul
  /// (P26) ; ce n'est pas un document de `decisions/`, d'où un champ à part.
  final bool canAnswer;

  /// `launch_analysis` et `launch_development` figurent dans
  /// `allowed_decisions` : « Lancer l'analyse » et « Lancer le
  /// développement » sont permis (ADR-008, T4). Écrits par le serveur seul ;
  /// l'application ne recopie aucune précondition (P39).
  final bool canLaunchAnalysis;
  final bool canLaunchDevelopment;

  /// `launch_delivery` et `relaunch_development` (ADR-008, T5) : ticket En
  /// cours validé dans l'application. Le serveur recontrôle chaque appel.
  final bool canLaunchDelivery;
  final bool canRelaunchDevelopment;

  /// Lancement que le serveur permet pour [action].
  bool canLaunch(ActionLancement action) => switch (action) {
    ActionLancement.analyse => canLaunchAnalysis,
    ActionLancement.developpement => canLaunchDevelopment,
    ActionLancement.livraison => canLaunchDelivery,
    ActionLancement.reprise => canRelaunchDevelopment,
  };

  /// Une décision s'applique sur GitHub jusqu'à cette heure (bail du serveur).
  final DateTime? decisionLeaseUntil;

  /// Nouvel essai de publication demandé par l'administrateur (heure du
  /// serveur ; `null` tant que l'écriture l'attend).
  final DateTime? retryRequestedAt;

  /// Une écriture locale attend le serveur : la création ou la date de
  /// lecture (`seen_by_author_at`) du membre, ou la relance
  /// (`retry_requested_at`) de l'admin.
  final bool hasPendingWrites;

  /// Création encore sur l'appareil seul : « En attente du réseau ».
  bool get waitingForNetwork =>
      status == TicketStatus.pending && hasPendingWrites;

  /// « À traiter » pour l'administrateur : reçu ou analysé sans décision
  /// (`received`, `analyzed`), ou envoi impossible (`send_failed`). Un ticket
  /// `validated` a déjà sa décision. Même définition pour le compteur du menu,
  /// le filtre et la pastille de l'avatar.
  bool get toProcess =>
      status == TicketStatus.received ||
      status == TicketStatus.analyzed ||
      status == TicketStatus.sendFailed;

  /// Création transmise par l'appareil, mais toujours pas publiée après
  /// [kTicketSendDelay].
  bool isLate(DateTime now) {
    final created = createdAt;
    return status == TicketStatus.pending &&
        !hasPendingWrites &&
        created != null &&
        now.difference(created) > kTicketSendDelay;
  }

  /// « Bloqué » : envoi impossible, en retard, ou Issue disparue.
  bool isBlocked(DateTime now) =>
      status == TicketStatus.sendFailed ||
      isLate(now) ||
      issueMissingSince != null;

  /// Une décision s'applique sur GitHub (bail du serveur encore valable).
  bool decisionInProgress(DateTime now) {
    final lease = decisionLeaseUntil;
    return lease != null && lease.isAfter(now);
  }

  /// Un suivi est à lire : le statut ou la réponse a changé depuis la dernière
  /// ouverture du détail.
  ///
  /// Le passage `pending` → `received` n'écrit pas `status_changed_at` : il ne
  /// compte pas. Sur l'appareil de l'auteur, une écriture en attente sur un ticket
  /// déjà publié est `seen_by_author_at` (la relance `retry_requested_at` de
  /// l'admin ne vise qu'un ticket `send_failed`), nulle dans le cache tant que
  /// le serveur n'a pas répondu : le suivi est alors lu.
  bool get unread {
    if (status == TicketStatus.pending || hasPendingWrites) return false;
    final changed = statusChangedAt;
    if (changed == null) return false;
    final seen = seenByAuthorAt;
    return seen == null || changed.isAfter(seen);
  }

  /// Lit le document ; lève [DocumentIllisible] pour un champ obligatoire
  /// absent ou un champ mal typé. Un statut inconnu reste lisible. Aucune
  /// valeur reçue n'entre dans l'erreur.
  ///
  /// [createdOnDevice] : heure de l'appareil à la création, pour un ticket créé
  /// dans cette session ; elle s'affiche tant que `created_at` attend le
  /// serveur.
  factory Ticket.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
    DateTime? createdOnDevice,
  }) {
    final read = LecteurChamps(data);
    final type = TicketType.fromStored(data['type']);
    if (type == null) throw const DocumentIllisible('type', 'type inconnu');
    int? entier(String key) {
      final number = read.nombreFacultatif(key);
      if (number == null) return null;
      if (number != number.truncateToDouble()) {
        throw DocumentIllisible(key, 'entier attendu');
      }
      return number.toInt();
    }

    final deliveredPrNumber = entier('delivered_pr_number');
    final allowedRaw = switch (data['allowed_decisions']) {
      final List<Object?> list => list,
      _ => const <Object?>[],
    };
    return Ticket(
      id: id,
      type: type,
      title: read.texte('title'),
      description: read.texte('description'),
      screen: read.texte('screen'),
      status: TicketStatus.fromStored(read.texte('status')),
      appVersion: read.texteFacultatif('app_version'),
      platform: read.texteFacultatif('platform'),
      createdAt: read.date('created_at') ?? createdOnDevice,
      statusChangedAt: read.date('status_changed_at'),
      seenByAuthorAt: read.date('seen_by_author_at'),
      replyText: read.texteFacultatif('reply_text'),
      deliveredPrUrl: read.texteFacultatif('delivered_pr_url'),
      deliveredVersion: read.texteFacultatif('delivered_version'),
      authorEmail: read.texteFacultatif('author_email'),
      issueNumber: entier('github_issue_number'),
      issueUrl: read.texteFacultatif('github_url'),
      deliveredPrNumber: deliveredPrNumber,
      sendAttempts: entier('send_attempts'),
      lastSendError: read.texteFacultatif('last_send_error'),
      issueMissingSince: read.date('issue_missing_since'),
      allowedDecisions: _allowedDecisions(data['allowed_decisions']),
      canAnswer: allowedRaw.contains(kAnswerDecision),
      canLaunchAnalysis: allowedRaw.contains(kLaunchAnalysisDecision),
      canLaunchDevelopment: allowedRaw.contains(kLaunchDevelopmentDecision),
      canLaunchDelivery: allowedRaw.contains(kLaunchDeliveryDecision),
      canRelaunchDevelopment: allowedRaw.contains(kRelaunchDevelopmentDecision),
      decisionLeaseUntil: read.date('decision_lease_until'),
      retryRequestedAt: read.date('retry_requested_at'),
      screenshotPath: read.texteFacultatif('screenshot_path'),
      hasPendingWrites: hasPendingWrites,
    );
  }

  static List<TicketDecisionAction>? _allowedDecisions(Object? value) {
    if (value == null) return null;
    if (value is! List) {
      throw const DocumentIllisible('allowed_decisions', 'liste attendue');
    }
    return [for (final v in value) ?TicketDecisionAction.fromStored(v)];
  }

  /// Contenu à reprendre dans un nouveau ticket (« Reprendre ce ticket »).
  TicketBrouillon get brouillon => TicketBrouillon(
    type: type,
    title: title,
    description: description,
    screen: screen,
  );
}

/// Tickets du plus récent au plus ancien ; une création qui attend le serveur
/// (sans date) passe en tête.
int compareTicketsRecentFirst(Ticket a, Ticket b) {
  final da = a.createdAt;
  final db = b.createdAt;
  if (da == null && db == null) return a.id.compareTo(b.id);
  if (da == null) return -1;
  if (db == null) return 1;
  return db.compareTo(da);
}

/// Compare deux versions `X.Y.Z` (un `+build` est ignoré) : négatif si [a] est
/// plus ancienne, `null` si l'une des deux est illisible.
int? compareVersions(String a, String b) {
  List<int>? parse(String v) {
    final parts = v.split('+').first.trim().split('.');
    if (parts.length != 3) return null;
    final numbers = [for (final p in parts) int.tryParse(p)];
    if (numbers.any((n) => n == null || n < 0)) return null;
    return numbers.cast<int>();
  }

  final pa = parse(a);
  final pb = parse(b);
  if (pa == null || pb == null) return null;
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// Valeur de `allowed_decisions` qui permet « Répondre » (ADR-008). Les
/// règles de `decisions/` la refusent : elle ne devient jamais une
/// [TicketDecisionAction].
const kAnswerDecision = 'answer';

/// Décision de l'administrateur sur un ticket (ADR-006).
///
/// [nom] : « Validation », « Refus », « Clôture ». [feminin] accorde les
/// phrases de l'écran (« Refus interrompu », « Clôture interrompue »).
enum TicketDecisionAction {
  validate('validate', 'Validation', feminin: true),
  refuse('refuse', 'Refus', feminin: false),
  close('close', 'Clôture', feminin: true);

  const TicketDecisionAction(
    this.storedValue,
    this.nom, {
    required this.feminin,
  });

  final String storedValue;
  final String nom;
  final bool feminin;

  static TicketDecisionAction? fromStored(Object? value) {
    for (final a in values) {
      if (a.storedValue == value) return a;
    }
    return null;
  }
}

/// État d'une décision : `pending` à la création, puis écrit par le serveur.
enum TicketDecisionState {
  pending('pending'),
  applying('applying'),
  applied('applied'),
  rejected('rejected'),
  failed('failed'),
  unknown(null);

  const TicketDecisionState(this.storedValue);

  final String? storedValue;

  static TicketDecisionState fromStored(Object? value) {
    for (final s in values) {
      if (s.storedValue != null && s.storedValue == value) return s;
    }
    return unknown;
  }
}

/// Document `tickets/{id}/decisions/{decisionId}`, lu par l'administrateur
/// seul.
///
/// Lecture tolérante : une action ou un état que cette version ne connaît pas
/// se lit `null` ou [TicketDecisionState.unknown], et la décision reste
/// affichée. Seul un champ mal typé la rend illisible.
@immutable
class TicketDecision {
  const TicketDecision({
    required this.id,
    required this.action,
    required this.state,
    this.text,
    this.requestedAt,
    this.errorReason,
    this.leaseUntil,
    this.hasPendingWrites = false,
  });

  final String id;

  /// `null` : action inconnue de cette version.
  final TicketDecisionAction? action;
  final TicketDecisionState state;

  /// Motif ou commentaire saisi ; absent pour une validation.
  final String? text;

  /// Heure du serveur ; `null` tant que la création l'attend.
  final DateTime? requestedAt;

  /// Raison d'un rejet ou d'un échec, en français, écrite par le serveur.
  final String? errorReason;

  /// Bail du serveur pendant l'application, s'il l'écrit.
  final DateTime? leaseUntil;

  /// La création, ou la reprise (`retry_requested_at`), attend encore le
  /// serveur.
  final bool hasPendingWrites;

  /// La décision attend ou s'applique : aucune autre ne part.
  bool get inProgress =>
      hasPendingWrites ||
      state == TicketDecisionState.pending ||
      state == TicketDecisionState.applying;

  factory TicketDecision.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    return TicketDecision(
      id: id,
      action: TicketDecisionAction.fromStored(data['action']),
      state: TicketDecisionState.fromStored(data['state']),
      text: read.texteFacultatif('text'),
      requestedAt: read.date('requested_at'),
      errorReason: read.texteFacultatif('error_reason'),
      leaseUntil: read.date('lease_until'),
      hasPendingWrites: hasPendingWrites,
    );
  }
}

/// Décisions de la plus récente à la plus ancienne ; une création qui attend
/// le serveur passe en tête.
int compareDecisionsRecentFirst(TicketDecision a, TicketDecision b) {
  final da = a.requestedAt;
  final db = b.requestedAt;
  if (da == null && db == null) return a.id.compareTo(b.id);
  if (da == null) return -1;
  if (db == null) return 1;
  return db.compareTo(da);
}
