import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import 'ticket.dart';

/// Bornes de la réponse de « Répondre », les mêmes que `answerTicketAnalysis`
/// (P34), comptées en points de code comme le serveur. Le client ne contrôle
/// que la longueur : le serveur retire les adresses et les mentions (P24).
const kTicketAnswerMinLength = 5;
const kTicketAnswerMaxLength = 4000;

/// Nature d'une entrée relevée sur l'Issue (P32) : analyse du mainteneur
/// (`## Analyse…`), réponse publiée par « Répondre » (`## Précisions…` dont
/// l'identifiant est dans `answer_comment_ids`), ou `## Précisions…` du même
/// compte publié hors de l'application.
enum TicketAnalysisKind {
  analysis('analysis'),
  reply('reply'),
  unverifiedReply('unverified_reply');

  const TicketAnalysisKind(this.storedValue);

  final String storedValue;

  /// `null` pour une valeur que cette version ne connaît pas.
  static TicketAnalysisKind? fromStored(Object? value) {
    for (final k in values) {
      if (k.storedValue == value) return k;
    }
    return null;
  }
}

/// Une entrée de `tickets/{id}/admin/analysis.analyses`, écrite par le serveur
/// seul et lue par l'administrateur seul.
@immutable
class TicketAnalysis {
  const TicketAnalysis({
    required this.kind,
    required this.body,
    this.createdAt,
    this.truncated = false,
  });

  final TicketAnalysisKind kind;

  /// Texte Markdown du commentaire, ligne de titre (`## …`) comprise.
  final String body;
  final DateTime? createdAt;

  /// Le texte dépassait 20 000 caractères : coupé à une ligne vide, la suite
  /// reste sur GitHub.
  final bool truncated;
}

/// Document `tickets/{id}/admin/analysis` (ADR-008, P32).
@immutable
class TicketAnalysisDoc {
  const TicketAnalysisDoc({required this.analyses, this.skippedCount = 0});

  /// Entrées dans l'ordre chronologique, dix au plus.
  final List<TicketAnalysis> analyses;

  /// Entrées écartées au-delà de dix : elles restent sur GitHub.
  final int skippedCount;

  /// Lit le document ; lève [DocumentIllisible] pour un champ mal typé. Une
  /// entrée d'une nature inconnue de cette version est écartée. Aucune
  /// valeur reçue n'entre dans l'erreur.
  factory TicketAnalysisDoc.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    int? entier(LecteurChamps r, String key) {
      final number = r.nombreFacultatif(key);
      if (number == null) return null;
      if (number != number.truncateToDouble()) {
        throw DocumentIllisible(key, 'entier attendu');
      }
      return number.toInt();
    }

    final analyses = <TicketAnalysis>[];
    for (final entry in read.liste('analyses')) {
      final kind = TicketAnalysisKind.fromStored(entry.data['kind']);
      if (kind == null) continue;
      analyses.add(
        TicketAnalysis(
          kind: kind,
          body: entry.texte('body'),
          createdAt: entry.date('created_at'),
          truncated: entry.boolFacultatif('truncated') ?? false,
        ),
      );
    }
    return TicketAnalysisDoc(
      analyses: analyses,
      skippedCount: entier(read, 'skipped_count') ?? 0,
    );
  }

  /// Nombre d'analyses du mainteneur, réponses exclues.
  int get analysisCount =>
      analyses.where((a) => a.kind == TicketAnalysisKind.analysis).length;

  /// Date de la dernière analyse, ou `null`.
  DateTime? get lastAnalysisAt {
    DateTime? best;
    for (final a in analyses) {
      final at = a.createdAt;
      if (a.kind != TicketAnalysisKind.analysis || at == null) continue;
      if (best == null || at.isAfter(best)) best = at;
    }
    return best;
  }

  /// Date de la dernière réponse publiée après la dernière analyse (sans
  /// analyse : la dernière réponse), ou `null`. La prochaine analyse la lira.
  DateTime? get pendingAnswerAt {
    final last = lastAnalysisAt;
    DateTime? best;
    for (final a in analyses) {
      final at = a.createdAt;
      if (a.kind != TicketAnalysisKind.reply || at == null) continue;
      if (last != null && !at.isAfter(last)) continue;
      if (best == null || at.isAfter(best)) best = at;
    }
    return best;
  }
}

/// Ce que montre la section « Analyses » quand il n'y a aucune entrée.
enum VueAnalysesVide {
  /// « Pas encore analysé. »
  pasEncoreAnalyse,

  /// « Analyse pas encore relevée. » : le ticket a dépassé Reçu, mais le
  /// serveur n'a pas encore écrit le document.
  pasEncoreRelevee,
}

/// État vide de la section, selon le statut et la présence du document.
VueAnalysesVide vueAnalysesVide({
  required TicketStatus status,
  required bool documentExiste,
}) {
  final auDelaDeRecu =
      status != TicketStatus.pending && status != TicketStatus.received;
  return !documentExiste && auDelaDeRecu
      ? VueAnalysesVide.pasEncoreRelevee
      : VueAnalysesVide.pasEncoreAnalyse;
}

/// Texte d'une entrée sans sa ligne de titre (`## Analyse…`,
/// `## Précisions…`), que le titre de la carte remplace (P33).
String corpsAffiche(String body) {
  final text = body.replaceAll('\r\n', '\n').trimLeft();
  if (!text.startsWith('## Analyse') && !text.startsWith('## Précisions')) {
    return text;
  }
  final newline = text.indexOf('\n');
  return newline < 0 ? '' : text.substring(newline + 1).trim();
}

/// Adresse d'un lien d'analyse, si elle est en `http` ou `https` avec un
/// hôte ; `null` sinon : le lien n'est pas ouvert (P33).
Uri? lienAnalyseOuvrable(String? href) {
  if (href == null) return null;
  final uri = Uri.tryParse(href.trim());
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

/// Ce qui remplace une image : elle n'est jamais chargée (P33).
String imageNonAffichee(String? alt) {
  final text = alt?.trim() ?? '';
  return text.isEmpty ? '[Image non affichée]' : '[Image non affichée : $text]';
}

/// Cause d'un échec de « Répondre ».
enum CauseEchecReponse {
  /// `unavailable` sans motif : pas de réseau. Avec un motif (GitHub
  /// indisponible, écrit par le serveur), c'est [motif].
  reseau,

  /// `deadline-exceeded` : le serveur n'a pas répondu à temps ; la réponse
  /// est peut-être publiée.
  delai,

  /// `permission-denied` ou `unauthenticated`.
  acces,

  /// Refus motivé du serveur (`details.reason`).
  motif,

  /// Toute autre erreur.
  autre,
}

/// Échec de `answerTicketAnalysis`, rendu par le dépôt après son rapport.
@immutable
class EchecReponse {
  const EchecReponse(
    this.cause, {
    this.motif,
    this.champ,
    this.codeServeur,
    this.partiel = false,
  });

  final CauseEchecReponse cause;

  /// `details.reason` : texte français court écrit par le serveur.
  final String? motif;

  /// `details.field` : champ refusé (`answer`, `ticketId`).
  final String? champ;

  /// `details.code` : code stable du serveur (`not_answerable`,
  /// `github_unavailable`…), pour le rapport d'erreur seul.
  final String? codeServeur;

  /// `details.partial` : la réponse est publiée sur GitHub, mais le statut n'a
  /// pas été ramené à Reçu. Le texte ne doit plus changer.
  final bool partiel;

  /// Lit le code et les `details` d'une `HttpsError`.
  factory EchecReponse.depuis({required String code, Object? details}) {
    final map = details is Map ? details : const {};
    final motif = switch (map['reason']) {
      final String r when r.trim().isNotEmpty => r.trim(),
      _ => null,
    };
    final champ = switch (map['field']) {
      final String f => f,
      _ => null,
    };
    final codeServeur = switch (map['code']) {
      final String c when RegExp(r'^[a-z_]{1,40}$').hasMatch(c) => c,
      _ => null,
    };
    final partiel = map['partial'] == true;
    final cause = switch (code) {
      'deadline-exceeded' => CauseEchecReponse.delai,
      'permission-denied' || 'unauthenticated' => CauseEchecReponse.acces,
      _ when motif != null => CauseEchecReponse.motif,
      'unavailable' => CauseEchecReponse.reseau,
      _ => CauseEchecReponse.autre,
    };
    return EchecReponse(
      cause,
      motif: motif,
      champ: champ,
      codeServeur: codeServeur,
      partiel: partiel,
    );
  }

  /// Le motif se pose sous le champ « Votre réponse ».
  bool get surLeChamp => cause == CauseEchecReponse.motif && champ == 'answer';
}
