import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/formats.dart';

/// Valeurs de `allowed_decisions` qui permettent « Lancer l'analyse »,
/// « Lancer le développement » (ADR-008, T4), « Livrer » et « Relancer le
/// développement » (T5). Écrites par le serveur seul ; les règles de
/// `decisions/` les refusent : elles ne deviennent jamais une décision.
const kLaunchAnalysisDecision = 'launch_analysis';
const kLaunchDevelopmentDecision = 'launch_development';
const kLaunchDeliveryDecision = 'launch_delivery';
const kRelaunchDevelopmentDecision = 'relaunch_development';

/// Les lancements de session Claude Code d'un ticket. [storedValue] est la
/// valeur `action` de l'historique, écrite par le serveur. `reprise` :
/// « Relancer le développement » d'un ticket En cours dont la CI est rouge.
enum ActionLancement {
  analyse('analyse'),
  developpement('developpement'),
  livraison('livraison'),
  reprise('reprise');

  const ActionLancement(this.storedValue);

  final String storedValue;

  /// `null` pour une valeur que cette version ne connaît pas.
  static ActionLancement? fromStored(Object? value) {
    for (final a in values) {
      if (a.storedValue == value) return a;
    }
    return null;
  }

  /// Callable du serveur (ADR-008, « Points d'accès autorisés ») : la reprise
  /// passe par `launchTicketDevelopment` avec `mode: "resume"` (P47).
  String get callable => switch (this) {
    ActionLancement.analyse => 'launchTicketAnalysis',
    ActionLancement.developpement ||
    ActionLancement.reprise => 'launchTicketDevelopment',
    ActionLancement.livraison => 'launchTicketDelivery',
  };

  /// Arguments de la callable en plus de `ticketId`.
  Map<String, Object?> get arguments => switch (this) {
    ActionLancement.reprise => const {'mode': 'resume'},
    _ => const {},
  };

  /// « Analyse », « Développement »…, en tête de « … en cours ».
  String get nom => switch (this) {
    ActionLancement.analyse => 'Analyse',
    ActionLancement.developpement => 'Développement',
    ActionLancement.livraison => 'Livraison',
    ActionLancement.reprise => 'Correction',
  };

  /// Titre d'une carte de l'historique.
  String get titreHistorique => switch (this) {
    ActionLancement.analyse => 'Analyse lancée',
    ActionLancement.developpement => 'Développement lancé',
    ActionLancement.livraison => 'Livraison lancée',
    ActionLancement.reprise => 'Correction lancée',
  };

  /// Complément des libellés : « Lancer l'analyse », « Relancer le
  /// développement ».
  String get complement => switch (this) {
    ActionLancement.analyse => 'l\'analyse',
    ActionLancement.developpement ||
    ActionLancement.reprise => 'le développement',
    ActionLancement.livraison => 'la livraison',
  };
}

/// Résultat d'un lancement, écrit par le serveur (`state`).
enum EtatLancement {
  launched('launched'),
  failed('failed'),
  unknown('unknown');

  const EtatLancement(this.storedValue);

  final String storedValue;

  /// `null` pour une valeur que cette version ne connaît pas.
  static EtatLancement? fromStored(Object? value) {
    for (final e in values) {
      if (e.storedValue == value) return e;
    }
    return null;
  }
}

/// Une entrée de `tickets/{id}/admin/launches.entries`, écrite par le serveur
/// seul et lue par l'administrateur seul (P41).
@immutable
class TicketLaunch {
  const TicketLaunch({
    required this.action,
    required this.etat,
    this.at,
    this.byUid,
    this.retryAfter,
    this.sessionUrl,
    this.reason,
    this.endedBy,
    this.queued = false,
  });

  /// `null` : action inconnue de cette version.
  final ActionLancement? action;

  /// `null` : état inconnu de cette version.
  final EtatLancement? etat;
  final DateTime? at;

  /// Compte qui a lancé ; jamais affiché tel quel.
  final String? byUid;

  /// Échéance écrite par le serveur : avant elle, le lancement est « en
  /// cours » et le serveur refuse un autre lancement de la même action.
  final DateTime? retryAfter;

  /// Lien de la session ; ouvert seulement après [lienSessionOuvrable].
  final String? sessionUrl;

  /// Raison d'un échec, en français, écrite par le serveur.
  final String? reason;

  /// Fin d'une livraison écrite par le serveur : `blocked` quand un compte
  /// rendu `## Livraison — blocage` a été relevé après son lancement (P45).
  /// Le client choisit son texte d'après ce champ, sans comparer de dates.
  final String? endedBy;

  /// Livraison partie de la file des livraisons (`queued: true`, écrit par
  /// `startQueuedDelivery`) : [byUid] est l'auteur de l'accord.
  final bool queued;

  /// Livraison close par un blocage relevé par le serveur.
  bool get arreteeParBlocage => endedBy == kLivraisonFinBlocage;

  /// En cours : [retryAfter] après [now]. Aucune autre condition (ADR-008 :
  /// le client ne recopie pas la règle du serveur).
  bool enCours(DateTime now) {
    final until = retryAfter;
    return until != null && until.isAfter(now);
  }
}

/// Document `tickets/{id}/admin/launches` (ADR-008, P41).
@immutable
class TicketLaunchesDoc {
  const TicketLaunchesDoc({required this.entries});

  /// Entrées du plus récent au plus ancien (sans date : à la fin), vingt au
  /// plus.
  final List<TicketLaunch> entries;

  /// Lit le document ; lève [DocumentIllisible] pour un champ mal typé. Une
  /// action ou un état inconnu reste lisible. Aucune valeur reçue n'entre
  /// dans l'erreur.
  factory TicketLaunchesDoc.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final entries = [
      for (final e in read.liste('entries'))
        TicketLaunch(
          action: ActionLancement.fromStored(e.data['action']),
          etat: EtatLancement.fromStored(e.data['state']),
          at: e.date('at'),
          byUid: e.texteFacultatif('by_uid'),
          retryAfter: e.date('retry_after'),
          sessionUrl: e.texteFacultatif('session_url'),
          reason: e.texteFacultatif('reason'),
          endedBy: e.texteFacultatif('ended_by'),
          queued: e.boolFacultatif('queued') ?? false,
        ),
    ];
    final far = DateTime.utc(1);
    entries.sort((a, b) => (b.at ?? far).compareTo(a.at ?? far));
    return TicketLaunchesDoc(
      entries: entries.length > kTicketLaunchHistoryMax
          ? entries.sublist(0, kTicketLaunchHistoryMax)
          : entries,
    );
  }

  /// Lancement de [action] en cours, le plus récent ; `null` sinon.
  TicketLaunch? enCours(ActionLancement action, DateTime now) {
    for (final e in entries) {
      if (e.action == action && e.enCours(now)) return e;
    }
    return null;
  }

  /// Dernier lancement de [action] parti ou au résultat inconnu, échéance
  /// passée, après le dernier changement de statut ([statusChangedAt]) : le
  /// bouton devient « Relancer ». `null` sinon.
  TicketLaunch? aRelancer(
    ActionLancement action,
    DateTime now, {
    required DateTime? statusChangedAt,
  }) {
    if (enCours(action, now) != null) return null;
    for (final e in entries) {
      if (e.action != action) continue;
      final at = e.at;
      if (at == null) return null;
      if (e.etat != EtatLancement.launched && e.etat != EtatLancement.unknown) {
        return null;
      }
      if (statusChangedAt != null && at.isBefore(statusChangedAt)) {
        return null;
      }
      return e;
    }
    return null;
  }
}

/// Entrées gardées par le serveur.
const kTicketLaunchHistoryMax = 20;

/// `ended_by` d'une livraison close par un blocage (`DELIVERY_ENDED_BY_BLOCKAGE`
/// du serveur).
const kLivraisonFinBlocage = 'blocked';

/// `ticket_status/launches.delivery_running` (P44) : verrou des livraisons,
/// écrit par le serveur seul. Il tient tant que [retryAfter] n'est pas passé :
/// le serveur le libère dès qu'un blocage est relevé ou que le ticket quitte
/// « En cours » ; le client ne recopie pas cette règle.
@immutable
class VerrouLivraison {
  const VerrouLivraison({
    required this.ticketId,
    this.issueNumber,
    this.launchedAt,
    this.retryAfter,
  });

  final String ticketId;
  final int? issueNumber;
  final DateTime? launchedAt;
  final DateTime? retryAfter;

  /// Échéance future.
  bool tient(DateTime now) {
    final until = retryAfter;
    return until != null && until.isAfter(now);
  }
}

/// Entrée de `ticket_status/launches.delivery_queue` (ADR-008, amendement du
/// 2026-11-22, P44), écrite par le serveur seul. L'e-mail de l'accord
/// (`by_email`) n'est pas lu.
@immutable
class EntreeFileLivraison {
  const EntreeFileLivraison({
    required this.ticketId,
    this.issueNumber,
    this.prNumber,
    this.queuedAt,
    this.byUid,
  });

  final String ticketId;
  final int? issueNumber;
  final int? prNumber;

  /// Heure de l'accord (« Mettre en file »).
  final DateTime? queuedAt;

  /// Compte qui a donné l'accord ; jamais affiché tel quel.
  final String? byUid;
}

/// `ticket_status/launches.delivery_last` : dernière livraison lancée, écrite
/// par le serveur seul. Le serveur pose [reportedAt] au relevé de son compte
/// rendu.
@immutable
class DerniereLivraison {
  const DerniereLivraison({
    required this.ticketId,
    this.issueNumber,
    this.launchedAt,
    this.retryAfter,
    this.reportedAt,
  });

  final String ticketId;
  final int? issueNumber;
  final DateTime? launchedAt;
  final DateTime? retryAfter;
  final DateTime? reportedAt;

  /// Compte rendu attendu : ni [reportedAt], ni [retryAfter] passé. Lecture
  /// des deux champs écrits par le serveur, sans autre règle.
  bool compteRenduAttendu(DateTime now) {
    if (reportedAt != null) return false;
    final until = retryAfter;
    return until != null && until.isAfter(now);
  }
}

/// Position d'un ticket dans la file des livraisons : [position] à partir de
/// 1, sur [total] ; [devant] : l'entrée qui le précède, ou `null` en tête.
typedef PositionFile = ({
  int position,
  int total,
  EntreeFileLivraison entree,
  EntreeFileLivraison? devant,
});

/// Document `ticket_status/launches`, écrit par le serveur seul et lu par
/// l'administrateur seul (P41). Le plafond [perDay] vient du serveur
/// (`LAUNCHES_PER_DAY`) : aucune constante en Dart (P39). Le compte fondateur a
/// son propre compteur ([founderCountDay], [founderPerDay]) : [vuePour] le
/// place dans [countDay] et [perDay] pour l'écran.
@immutable
class EtatLancements {
  const EtatLancements({
    this.day,
    this.countDay,
    this.month,
    this.countMonth,
    this.perDay,
    this.founderCountDay,
    this.founderPerDay,
    this.analysisInvalidSince,
    this.developmentInvalidSince,
    this.deliveryRunning,
    this.ciReadDeniedSince,
    this.deliveryQueue = const [],
    this.deliveryLast,
  });

  /// Jour de Paris du compteur, `AAAAMMJJ`, écrit par le serveur. Le client
  /// ne le compare à aucune date de l'appareil.
  final String? day;
  final int? countDay;

  /// Mois de Paris du compteur, `AAAAMM`.
  final String? month;
  final int? countMonth;
  final int? perDay;

  /// Compteur et plafond du jour du compte fondateur
  /// (`FOUNDER_LAUNCHES_PER_DAY` du serveur), à part de ceux du groupe.
  final int? founderCountDay;
  final int? founderPerDay;

  /// Jeton de la routine refusé depuis cette date.
  final DateTime? analysisInvalidSince;
  final DateTime? developmentInvalidSince;

  /// Verrou des livraisons, ou `null` (absent ou libéré).
  final VerrouLivraison? deliveryRunning;

  /// GitHub refuse au jeton la lecture des runs de la CI (403, permission
  /// « Actions : lecture » absente) depuis cette date ; effacé par le serveur
  /// à la lecture suivante réussie (décision de l'utilisateur du 2026-11-14).
  final DateTime? ciReadDeniedSince;

  /// File des livraisons, dans l'ordre des accords (P44).
  final List<EntreeFileLivraison> deliveryQueue;

  /// Dernière livraison lancée, ou `null`.
  final DerniereLivraison? deliveryLast;

  /// Position de [ticketId] dans la file, ou `null` s'il n'y est pas.
  PositionFile? positionFile(String ticketId) {
    for (var i = 0; i < deliveryQueue.length; i++) {
      if (deliveryQueue[i].ticketId != ticketId) continue;
      return (
        position: i + 1,
        total: deliveryQueue.length,
        entree: deliveryQueue[i],
        devant: i == 0 ? null : deliveryQueue[i - 1],
      );
    }
    return null;
  }

  static final _jour = RegExp(r'^\d{8}$');
  static final _mois = RegExp(r'^\d{6}$');

  /// Lève [DocumentIllisible] pour un champ mal typé.
  factory EtatLancements.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    int? entier(String key) {
      final n = read.nombreFacultatif(key);
      if (n == null) return null;
      if (n != n.truncateToDouble() || n < 0) {
        throw DocumentIllisible(key, 'entier positif attendu');
      }
      return n.toInt();
    }

    String? periode(String key, RegExp forme) {
      final value = read.texteFacultatif(key);
      if (value == null) return null;
      if (!forme.hasMatch(value)) {
        throw DocumentIllisible(key, 'période mal formée');
      }
      return value;
    }

    return EtatLancements(
      day: periode('day', _jour),
      countDay: entier('count_day'),
      month: periode('month', _mois),
      countMonth: entier('count_month'),
      perDay: entier('per_day'),
      founderCountDay: entier('founder_count_day'),
      founderPerDay: entier('founder_per_day'),
      analysisInvalidSince: read.date('analysis_invalid_since'),
      developmentInvalidSince: read.date('development_invalid_since'),
      deliveryRunning: _verrou(read.objetFacultatif('delivery_running')),
      ciReadDeniedSince: read.date('ci_read_denied_since'),
      deliveryQueue: [
        for (final e in read.liste('delivery_queue'))
          if (e.texteFacultatif('ticket_id') case final id? when id.isNotEmpty)
            EntreeFileLivraison(
              ticketId: id,
              issueNumber: _entierPositif(e, 'issue_number'),
              prNumber: _entierPositif(e, 'pr_number'),
              queuedAt: e.date('queued_at'),
              byUid: e.texteFacultatif('by_uid'),
            ),
      ],
      deliveryLast: _derniere(read.objetFacultatif('delivery_last')),
    );
  }

  static int? _entierPositif(LecteurChamps read, String key) {
    final n = read.nombreFacultatif(key);
    return n != null && n == n.truncateToDouble() && n > 0 ? n.toInt() : null;
  }

  static DerniereLivraison? _derniere(LecteurChamps? read) {
    if (read == null) return null;
    final ticketId = read.texteFacultatif('ticket_id');
    if (ticketId == null || ticketId.isEmpty) return null;
    return DerniereLivraison(
      ticketId: ticketId,
      issueNumber: _entierPositif(read, 'issue_number'),
      launchedAt: read.date('launched_at'),
      retryAfter: read.date('retry_after'),
      reportedAt: read.date('reported_at'),
    );
  }

  /// L'état vu par le compte connecté : pour le fondateur, [countDay] et
  /// [perDay] sont ceux de son compteur ; sans eux, inconnus. Les autres
  /// champs, mois compris (les deux compteurs ensemble), restent ceux du
  /// document.
  EtatLancements vuePour({required bool fondateur}) {
    if (!fondateur) return this;
    return EtatLancements(
      day: day,
      countDay: founderCountDay,
      month: month,
      countMonth: countMonth,
      perDay: founderPerDay,
      founderCountDay: founderCountDay,
      founderPerDay: founderPerDay,
      analysisInvalidSince: analysisInvalidSince,
      developmentInvalidSince: developmentInvalidSince,
      deliveryRunning: deliveryRunning,
      ciReadDeniedSince: ciReadDeniedSince,
      deliveryQueue: deliveryQueue,
      deliveryLast: deliveryLast,
    );
  }

  static VerrouLivraison? _verrou(LecteurChamps? read) {
    if (read == null) return null;
    final ticketId = read.texteFacultatif('ticket_id');
    if (ticketId == null || ticketId.isEmpty) return null;
    return VerrouLivraison(
      ticketId: ticketId,
      issueNumber: _entierPositif(read, 'issue_number'),
      launchedAt: read.date('launched_at'),
      retryAfter: read.date('retry_after'),
    );
  }

  /// « 13/11 », d'après [day] ; `null` sans jour.
  String? get jourAffiche {
    final d = day;
    if (d == null) return null;
    return '${d.substring(6, 8)}/${d.substring(4, 6)}';
  }

  /// « novembre 2026 », d'après [month] ; `null` sans mois ou pour un mois
  /// hors de 1 à 12.
  String? get moisAffiche {
    final m = month;
    if (m == null) return null;
    final numero = int.parse(m.substring(4, 6));
    if (numero < 1 || numero > 12) return null;
    return formatMoisAnnee(int.parse(m.substring(0, 4)), numero);
  }

  /// Lancements restants le jour [day] ; `null` s'il manque une valeur.
  int? get restants {
    final limit = perDay;
    final count = countDay;
    if (limit == null || count == null || day == null) return null;
    return count >= limit ? 0 : limit - count;
  }

  /// Plafond atteint le jour [day].
  bool get plafondAtteint => restants == 0;
}

/// Ligne du quota dans la boîte de lancement. Le jour est celui écrit par le
/// serveur : l'application ne recalcule pas le jour de Paris.
String ligneQuota(EtatLancements? etat) {
  final restants = etat?.restants;
  final jour = etat?.jourAffiche;
  final limit = etat?.perDay;
  if (etat == null || restants == null || jour == null || limit == null) {
    return 'Lancements restants : inconnu.';
  }
  if (restants == 0) {
    return 'Plafond atteint le $jour : $limit lancements sur $limit. '
        '$kCompteurApresMinuit';
  }
  return 'Lancements restants le $jour : $restants sur $limit.';
}

/// Fin des lignes du plafond. Le jour affiché est celui écrit par le
/// serveur : entre minuit et la passe de minuit de `syncTickets`, c'est encore
/// la veille, d'où « peu après minuit » plutôt que « demain ».
const kCompteurApresMinuit = 'Le compteur repart à zéro peu après minuit.';

/// Ligne de la barre d'un ticket analysé quand le plafond est atteint le
/// jour [EtatLancements.day] : « Valider » reste possible, le lancement du
/// développement attendra.
String lignePlafondAnalyse(EtatLancements etat) =>
    'Plafond atteint le ${etat.jourAffiche} : ${etat.perDay} lancements sur '
    '${etat.perDay}. Vous pouvez valider. $kCompteurApresMinuit';

/// Ligne du compteur en tête de la liste d'Admin › Tickets.
String ligneCompteur(EtatLancements etat) {
  final parts = <String>[];
  final jour = etat.jourAffiche;
  final countDay = etat.countDay;
  final limit = etat.perDay;
  if (jour != null && countDay != null) {
    parts.add(
      limit == null ? '$countDay le $jour' : '$countDay sur $limit le $jour',
    );
  }
  final mois = etat.moisAffiche;
  final countMonth = etat.countMonth;
  if (mois != null && countMonth != null) parts.add('$countMonth en $mois');
  return parts.isEmpty
      ? 'Lancements de sessions : aucun compté.'
      : 'Lancements de sessions : ${parts.join(' · ')}';
}

/// « Analyse en cours depuis 14:05 », ou « … depuis le 12/11/26 à 14:05 »
/// quand le lancement date d'un autre jour.
String ligneEnCours(ActionLancement action, DateTime since, DateTime now) {
  final s = since.toLocal();
  final n = now.toLocal();
  final memeJour = s.year == n.year && s.month == n.month && s.day == n.day;
  return memeJour
      ? '${action.nom} en cours depuis ${formatHeure(s)}'
      : '${action.nom} en cours depuis le ${formatDateChiffres(s)} à '
            '${formatHeure(s)}';
}

/// « le 13/11/26 à 14:05 ».
String dateLancement(DateTime at) =>
    'le ${formatDateChiffres(at)} à ${formatHeure(at)}';

/// Lien d'une session, s'il est en `https` sur `claude.ai`, sans
/// identifiants ni port ; `null` sinon : il n'est pas ouvert (P41).
Uri? lienSessionOuvrable(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'claude.ai' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return null;
  }
  return uri;
}

/// Issue d'un appel de lancement, rendue par le dépôt après son rapport.
enum IssueLancement {
  /// Session créée.
  lance,

  /// Le serveur a appelé la routine sans savoir si la session existe : le
  /// lancement est compté.
  inconnu,

  /// Refus motivé du serveur : rien n'est parti.
  refuse,

  /// `permission-denied` ou `unauthenticated` : rien n'est parti.
  acces,

  /// Pas de réponse (réseau coupé, délai dépassé, réponse illisible) : la
  /// session est peut-être partie.
  perdu,
}

/// Codes des refus de livraison qui demandent une fusion à la main : la PR
/// touche un fichier protégé, ou sa liste de fichiers est trop longue pour
/// être vérifiée. « Livrer » reste inactif tant que la boîte est ouverte : un
/// nouvel essai donnerait le même refus.
const kRefusFusionALaMain = {
  'delivery_sensitive_files',
  'delivery_files_unreadable',
};

/// Résultat de `launchTicketAnalysis`, `launchTicketDevelopment` ou
/// `launchTicketDelivery`.
@immutable
class ResultatLancement {
  const ResultatLancement(this.issue, {this.motif, this.code});

  final IssueLancement issue;

  /// `details.reason` : texte français du serveur.
  final String? motif;

  /// `details.code` : code stable du serveur, pour le rapport d'erreur seul.
  final String? code;

  /// La boîte reste ouverte et affiche le message : rien n'est parti.
  bool get rienNestParti =>
      issue == IssueLancement.refuse || issue == IssueLancement.acces;

  /// Lit la réponse d'un appel réussi ; une réponse illisible se lit
  /// [IssueLancement.inconnu]. Un résultat inconnu peut porter le message du
  /// serveur (`reason` : « Claude ne répond pas… »).
  factory ResultatLancement.depuisReponse(Object? data) {
    final map = data is Map ? data : const {};
    if (map['outcome'] == 'launched') {
      return const ResultatLancement(IssueLancement.lance);
    }
    return ResultatLancement(
      IssueLancement.inconnu,
      motif: switch (map['reason']) {
        final String r when r.trim().isNotEmpty => r.trim(),
        _ => null,
      },
    );
  }

  /// Lit le code et les `details` d'une `HttpsError`.
  factory ResultatLancement.depuisErreur({
    required String code,
    Object? details,
  }) {
    final map = details is Map ? details : const {};
    final motif = switch (map['reason']) {
      final String r when r.trim().isNotEmpty => r.trim(),
      _ => null,
    };
    final codeServeur = switch (map['code']) {
      final String c when RegExp(r'^[a-z_]{1,40}$').hasMatch(c) => c,
      _ => null,
    };
    final issue = switch (code) {
      'permission-denied' || 'unauthenticated' => IssueLancement.acces,
      // Un délai dépassé ou une coupure : la session est peut-être partie.
      'deadline-exceeded' => IssueLancement.perdu,
      // Panne inattendue du serveur (`details.code` = `internal`) : il ne
      // sait pas si la session est partie.
      _ when codeServeur == 'internal' => IssueLancement.perdu,
      _ when motif != null => IssueLancement.refuse,
      _ => IssueLancement.perdu,
    };
    return ResultatLancement(issue, motif: motif, code: codeServeur);
  }

  /// Message affiché, dans la boîte (refus) ou en bas d'écran.
  String get message => switch (issue) {
    IssueLancement.lance =>
      'Session lancée. Le lien est dans la section Lancements.',
    IssueLancement.inconnu =>
      'Résultat inconnu, compté dans les lancements du jour. '
          '${motif ?? 'Vérifiez sur claude.ai/code avant de relancer.'}',
    IssueLancement.refuse =>
      motif ?? 'Lancement refusé par le serveur. Rien n\'a été lancé.',
    IssueLancement.acces =>
      'Lancement refusé : accès administrateur refusé. Rien n\'a été lancé.',
    IssueLancement.perdu =>
      'Réponse perdue. Regardez la section Lancements avant de relancer.',
  };
}
