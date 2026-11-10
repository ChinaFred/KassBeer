import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Bornes d'un ticket, les mêmes que `firestore.rules` (P23).
const kTicketTitleMinLength = 5;
const kTicketTitleMaxLength = 100;
const kTicketDescriptionMinLength = 10;
const kTicketDescriptionMaxLength = 2000;

/// Au-delà de ce délai, un ticket `pending` est en retard : la tâche horaire
/// aurait dû le transmettre.
const kTicketSendDelay = Duration(hours: 1);

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

  /// Une écriture locale attend le serveur : la création, ou la date de
  /// lecture (`seen_by_author_at`), seules écritures permises au membre.
  final bool hasPendingWrites;

  /// Création encore sur l'appareil seul : « En attente du réseau ».
  bool get waitingForNetwork =>
      status == TicketStatus.pending && hasPendingWrites;

  /// Un suivi est à lire : le statut ou la réponse a changé depuis la dernière
  /// ouverture du détail.
  ///
  /// Le passage `pending` → `received` n'écrit pas `status_changed_at` : il ne
  /// compte pas. Une écriture en attente sur un ticket déjà publié ne peut être
  /// que `seen_by_author_at`, nulle dans le cache tant que le serveur n'a pas
  /// répondu : le suivi est alors lu.
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
    final number = read.nombreFacultatif('delivered_pr_number');
    if (number != null && number != number.truncateToDouble()) {
      throw const DocumentIllisible('delivered_pr_number', 'entier attendu');
    }
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
      hasPendingWrites: hasPendingWrites,
    );
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
