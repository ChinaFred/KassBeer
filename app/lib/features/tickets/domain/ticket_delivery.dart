import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/formats.dart';
import 'ticket.dart';
import 'ticket_launch.dart';

/// Nature d'un compte rendu de livraison, relevé sur l'Issue par le serveur
/// (P45) : `## Livraison — blocage` ou `## Livraison — terminée` du compte
/// 16348852.
enum TypeCompteRendu {
  blocage('blocked'),
  terminee('done');

  const TypeCompteRendu(this.storedValue);

  final String storedValue;

  /// `null` pour une valeur que cette version ne connaît pas.
  static TypeCompteRendu? fromStored(Object? value) {
    for (final t in values) {
      if (t.storedValue == value) return t;
    }
    return null;
  }
}

/// Un compte rendu de `tickets/{id}/admin/delivery.reports`.
@immutable
class CompteRenduLivraison {
  const CompteRenduLivraison({
    required this.type,
    required this.body,
    this.createdAt,
    this.truncated = false,
  });

  final TypeCompteRendu type;

  /// Texte Markdown, ligne de titre comprise : retirée à l'affichage.
  final String body;
  final DateTime? createdAt;

  /// Coupé à 20 000 caractères par le serveur ; la suite reste sur GitHub.
  final bool truncated;
}

/// Document `tickets/{id}/admin/delivery` (ADR-008, T5, P45), écrit par le
/// serveur seul et lu par l'administrateur seul. Le client lit `ready` et
/// `relaunch_ready` tels quels : il ne recalcule ni l'éligibilité d'une PR,
/// ni l'état de la CI (P39, P46).
@immutable
class TicketDelivery {
  const TicketDelivery({
    this.eligiblePrCount = 0,
    this.prNumber,
    this.prUrl,
    this.ciStatus,
    this.ciConclusion,
    this.ciCompletedAt,
    this.ready = false,
    this.relaunchReady = false,
    this.reports = const [],
    this.queueExit,
  });

  final int eligiblePrCount;
  final int? prNumber;

  /// Adresse écrite par le serveur ; ouverte après [lienPullRequestOuvrable].
  final String? prUrl;

  /// `completed` quand tous les derniers runs de la CI sont finis ; sinon
  /// l'état d'un run en cours ; `null` sans run.
  final String? ciStatus;
  final String? ciConclusion;
  final DateTime? ciCompletedAt;

  /// « PR prête » : une seule PR éligible, CI verte.
  final bool ready;

  /// CI rouge : une seule PR éligible, CI terminée en échec.
  final bool relaunchReady;

  /// Comptes rendus, ordre chronologique, dix au plus.
  final List<CompteRenduLivraison> reports;

  /// Dernière sortie de la file des livraisons sans départ (`queue_exit`),
  /// ou `null`.
  final SortieFile? queueExit;

  /// Lit le document ; lève [DocumentIllisible] pour un champ mal typé. Un
  /// compte rendu d'une nature inconnue est écarté. Aucune valeur reçue
  /// n'entre dans l'erreur.
  factory TicketDelivery.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    int? entier(String key) {
      final n = read.nombreFacultatif(key);
      if (n == null) return null;
      if (n != n.truncateToDouble() || n < 0) {
        throw DocumentIllisible(key, 'entier positif attendu');
      }
      return n.toInt();
    }

    final reports = <CompteRenduLivraison>[];
    for (final r in read.liste('reports')) {
      final type = TypeCompteRendu.fromStored(r.data['kind']);
      if (type == null) continue;
      reports.add(
        CompteRenduLivraison(
          type: type,
          body: r.texte('body'),
          createdAt: r.date('created_at'),
          truncated: r.boolFacultatif('truncated') ?? false,
        ),
      );
    }
    return TicketDelivery(
      eligiblePrCount: entier('eligible_pr_count') ?? 0,
      prNumber: entier('pr_number'),
      prUrl: read.texteFacultatif('pr_url'),
      ciStatus: read.texteFacultatif('ci_status'),
      ciConclusion: read.texteFacultatif('ci_conclusion'),
      ciCompletedAt: read.date('ci_completed_at'),
      ready: read.boolFacultatif('ready') ?? false,
      relaunchReady: read.boolFacultatif('relaunch_ready') ?? false,
      reports: reports,
      queueExit: switch (read.objetFacultatif('queue_exit')) {
        final LecteurChamps e => switch (e.texteFacultatif('code')) {
          final String code => SortieFile(code: code, at: e.date('at')),
          null => null,
        },
        null => null,
      },
    );
  }
}

/// `admin/delivery.queue_exit` : sortie de la file sans départ, écrite par le
/// serveur seul (ADR-008, amendement du 2026-11-22, P45).
@immutable
class SortieFile {
  const SortieFile({required this.code, this.at});

  /// Code stable du serveur ; un code inconnu reste lisible.
  final String code;
  final DateTime? at;
}

/// Code de « Retirer de la file ».
const kSortieRetrait = 'delivery_queue_removed';

/// Phrase de chaque code de sortie connu, après « Sortie de la file le … : ».
const kPhrasesSortieFile = <String, String>{
  'delivery_queue_cleared_after_blockage':
      'une livraison s\'est bloquée et la file a été vidée. Remettez ce ticket '
      'en file si vous le voulez.',
  'delivery_queue_head_changed':
      'le code de la PR a changé depuis votre accord.',
  'delivery_ci_not_green': 'la CI de la PR n\'était pas verte au départ.',
  'delivery_no_pr': 'aucune pull request prête au départ.',
  'delivery_multiple_prs': 'plusieurs pull requests ferment l\'Issue.',
  'delivery_sensitive_files':
      'la PR modifie un fichier protégé. Fusionnez-la vous-même après '
      'relecture.',
  'delivery_files_unreadable':
      'la liste des fichiers de la PR est trop longue pour être vérifiée. '
      'Fusionnez-la vous-même après relecture.',
  'delivery_queue_not_admin':
      'le compte qui avait donné l\'accord n\'est plus administrateur.',
  'reprise_running': 'une correction de la PR était en cours.',
  'delivery_queue_relaunched': 'le développement a été relancé.',
  'delivery_queue_refused': 'le ticket a été refusé.',
  'delivery_queue_closed': 'le ticket a été clos.',
  'delivery_queue_left_in_progress': 'le ticket a quitté « En cours ».',
  'not_allowed': 'le ticket ne permettait plus la livraison.',
  'issue_not_found': 'l\'Issue n\'existe plus sur GitHub.',
};

/// Ligne de sortie de file : texte et ton d'erreur (tout code sauf
/// [kSortieRetrait]).
({String texte, bool erreur}) ligneSortieFile(SortieFile sortie) {
  final at = sortie.at;
  final quand = at == null ? '' : ' le ${_du(at)}';
  if (sortie.code == kSortieRetrait) {
    return (texte: 'Retiré de la file$quand.', erreur: false);
  }
  final phrase = kPhrasesSortieFile[sortie.code];
  return (
    texte: phrase == null
        ? 'Sortie de la file$quand. Mettez l\'application à jour pour lire '
              'la raison.'
        : 'Sortie de la file$quand : $phrase',
    erreur: true,
  );
}

/// Adresse d'une PR, seulement `https://github.com/ChinaFred/KassBeer/pull/<n>`
/// relue par `Uri.tryParse` ; `null` sinon : rien n'est ouvert (P39).
Uri? lienPullRequestOuvrable(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final s = uri.pathSegments;
  final ok =
      s.length == 4 &&
      s[0] == 'ChinaFred' &&
      s[1] == 'KassBeer' &&
      s[2] == 'pull' &&
      RegExp(r'^[1-9][0-9]{0,6}$').hasMatch(s[3]);
  return ok ? uri : null;
}

/// Texte d'un compte rendu sans sa ligne de titre (`## Livraison — …`), que
/// le titre de la carte remplace (P33).
String corpsCompteRendu(String body) {
  final text = body.replaceAll('\r\n', '\n').trimLeft();
  if (!text.startsWith('## Livraison')) return text;
  final newline = text.indexOf('\n');
  return newline < 0 ? '' : text.substring(newline + 1).trim();
}

/// Ton de la ligne de livraison d'un ticket En cours.
enum TonLivraison {
  /// Barre de progression ([LigneLivraison.progression]).
  progression,

  /// Un lancement en cours.
  enCours,

  /// Information, sans erreur.
  info,

  /// PR prête : icône de validation.
  prete,

  /// Échec ou panne.
  erreur,

  /// Plafond atteint.
  plafond,
}

/// Ligne de la barre d'un ticket En cours (ADR-008, T5), et bouton offert.
///
/// [action] : `livraison` (« Livrer », ou « Relancer la livraison » avec
/// [relanceDe]) ou `reprise` (« Relancer le développement ») ; `null` : aucun
/// bouton. [actif] : le bouton est appuyable (en ligne, aucun appel, plafond
/// non atteint). [reessayer] : la lecture de `admin/delivery` est en panne.
/// [verrouTicketId] : « Ouvrir le ticket #N » (livraison d'un autre ticket).
/// [masquerRefuserClore] : livraison de ce ticket en cours (P39, P44).
@immutable
class LigneLivraison {
  const LigneLivraison({
    required this.ton,
    required this.texte,
    this.progression,
    this.action,
    this.actif = false,
    this.relanceDe,
    this.reessayer = false,
    this.verrouTicketId,
    this.verrouIssue,
    this.masquerRefuserClore = false,
    this.mode,
    this.ligneAccord,
    this.ligneDetail,
    this.detailErreur = false,
    this.sortie,
    this.repriseAussi = false,
  });

  final TonLivraison ton;
  final String texte;

  /// Libellé lu de la barre de progression.
  final String? progression;
  final ActionLancement? action;
  final bool actif;
  final DateTime? relanceDe;
  final bool reessayer;
  final String? verrouTicketId;
  final int? verrouIssue;
  final bool masquerRefuserClore;

  /// Bouton de livraison : « Livrer » ([ModeLivraison.livrer] ou `null`),
  /// « Mettre en file » ou « Retirer de la file ».
  final ModeLivraison? mode;

  /// Seconde ligne d'un ticket en file : « Accord du … pour la PR #34. ».
  final String? ligneAccord;

  /// Ligne d'un ticket en file dont la PR n'est plus prête (CI rouge…).
  final String? ligneDetail;

  /// [ligneDetail] en ton d'erreur (tout sauf « CI en cours »).
  final bool detailErreur;

  /// Ligne de sortie de la file (`queue_exit`), sous la ligne principale.
  final ({String texte, bool erreur})? sortie;

  /// Ticket en file à CI rouge : « Relancer le développement » à côté de
  /// « Retirer de la file ».
  final bool repriseAussi;

  LigneLivraison _avecSortie(({String texte, bool erreur})? s) => s == null
      ? this
      : LigneLivraison(
          ton: ton,
          texte: texte,
          progression: progression,
          action: action,
          actif: actif,
          relanceDe: relanceDe,
          reessayer: reessayer,
          verrouTicketId: verrouTicketId,
          verrouIssue: verrouIssue,
          masquerRefuserClore: masquerRefuserClore,
          mode: mode,
          ligneAccord: ligneAccord,
          ligneDetail: ligneDetail,
          detailErreur: detailErreur,
          sortie: s,
          repriseAussi: repriseAussi,
        );
}

/// « le 13/11/26 à 14:05 », ou « 14:05 » le même jour que [now].
String _depuis(DateTime at, DateTime now) {
  final a = at.toLocal();
  final n = now.toLocal();
  final memeJour = a.year == n.year && a.month == n.month && a.day == n.day;
  return memeJour
      ? formatHeure(a)
      : 'le ${formatDateChiffres(a)} à ${formatHeure(a)}';
}

/// « 13/11/26 à 14:05 », après « du ».
String _du(DateTime at) {
  final a = at.toLocal();
  return '${formatDateChiffres(a)} à ${formatHeure(a)}';
}

/// Ligne d'un ticket En cours quand GitHub refuse au jeton la lecture de la
/// CI (`ticket_status/launches.ci_read_denied_since`, P25), affichée
/// seulement si `admin/delivery` porte une seule PR éligible : le serveur ne
/// relit les runs, et n'efface le champ, que pour elle.
const kCiLectureRefusee =
    'Le jeton GitHub ne peut pas lire la CI : sur GitHub, donnez-lui le droit '
    '« Actions : lecture ».';

/// Ligne d'un `admin/delivery` illisible : une version plus récente l'a écrit.
const kEtatPrIllisible =
    'État de la pull request illisible. Mettez l\'application à jour.';

/// Ligne d'un `admin/delivery` en panne de lecture, avec « Réessayer ».
const kEtatPrEnPanne = 'État de la pull request illisible.';

/// « PR #34 » ou « la pull request ».
String _pr(int? n) => n == null ? 'la pull request' : 'la PR #$n';

/// Ligne de la barre d'un ticket En cours, lue dans les documents du serveur
/// seuls (P39, P46) : `admin/delivery` ([livraison]), `admin/launches`
/// ([historique], `retry_after`), `ticket_status/launches` ([quota], dont
/// `delivery_running`). Aucune règle du serveur n'est recopiée : le client
/// compare l'heure de l'appareil aux échéances écrites par le serveur et lit
/// `ready`, `relaunch_ready` et `allowed_decisions`. `null` pour un ticket qui
/// n'est pas En cours ou sans Issue.
///
/// File des livraisons (amendement du 2026-11-22) : le bouton (« Livrer »,
/// « Mettre en file », « Retirer de la file ») se choisit d'après
/// `delivery_running`, `delivery_last` et `delivery_queue` lus, sans
/// condition de départ ni éligibilité recopiée (P39). [modeEnCours] : mode de
/// l'appel en cours ; [uid] : compte connecté (ligne du plafond de la tête de
/// file, seulement pour son propre accord).
LigneLivraison? ligneLivraison({
  required Ticket ticket,
  required RechercheDocument<TicketDelivery>? livraison,
  required bool livraisonEnPanne,
  required TicketLaunchesDoc? historique,
  required EtatLancements? quota,
  required DateTime now,
  required bool offline,
  required bool appelEnCours,
  ModeLivraison? modeEnCours,
  String? uid,
}) {
  if (ticket.status != TicketStatus.inProgress || ticket.issueNumber == null) {
    return null;
  }
  final verrou = quota?.deliveryRunning;
  final verrouIci =
      verrou != null && verrou.ticketId == ticket.id && verrou.tient(now);
  final livraisonEnCours = historique?.enCours(ActionLancement.livraison, now);
  // 1. Livraison de ce ticket en cours : verrou ou entrée de l'historique.
  if (verrouIci || livraisonEnCours != null) {
    final since = livraisonEnCours?.at ?? verrou?.launchedAt;
    final file = (livraisonEnCours?.queued ?? false)
        ? ', partie de la file'
        : '';
    return LigneLivraison(
      ton: TonLivraison.enCours,
      texte: since == null
          ? 'Livraison en cours$file.'
          : 'Livraison en cours depuis ${_depuis(since, now)}$file.',
      masquerRefuserClore: true,
    );
  }
  // 2. Correction de la PR en cours.
  final repriseEnCours = historique?.enCours(ActionLancement.reprise, now);
  final doc = switch (livraison) {
    DocumentTrouve(:final value) => value,
    DocumentAbsent() => const TicketDelivery(),
    _ => null,
  };
  if (repriseEnCours != null) {
    final since = repriseEnCours.at;
    return LigneLivraison(
      ton: TonLivraison.enCours,
      texte: since == null
          ? 'Correction de ${_pr(doc?.prNumber)} en cours.'
          : 'Correction de ${_pr(doc?.prNumber)} en cours depuis '
                '${_depuis(since, now)}.',
    );
  }
  // 2 bis. Lecture de la CI refusée au jeton : l'état de la PR n'est plus
  // relu par le serveur. Seulement avec une PR éligible : sans elle, le
  // serveur ne lit aucun run et ne peut pas effacer un champ périmé.
  if (quota?.ciReadDeniedSince != null && doc?.eligiblePrCount == 1) {
    return const LigneLivraison(
      ton: TonLivraison.erreur,
      texte: kCiLectureRefusee,
    );
  }
  // 3. État de la PR : lecture, panne, absent du cache.
  if (doc == null) {
    if (livraison is DocumentIllisibleTrouve) {
      return const LigneLivraison(
        ton: TonLivraison.erreur,
        texte: kEtatPrIllisible,
      );
    }
    if (livraisonEnPanne) {
      return const LigneLivraison(
        ton: TonLivraison.erreur,
        texte: kEtatPrEnPanne,
        reessayer: true,
      );
    }
    if (livraison is DocumentAbsentDuCache && offline) {
      return const LigneLivraison(
        ton: TonLivraison.info,
        texte: 'État de la pull request non disponible hors ligne.',
      );
    }
    return const LigneLivraison(
      ton: TonLivraison.progression,
      texte: 'Lecture de la pull request.',
      progression: 'Lecture de la pull request',
    );
  }
  final file = quota?.positionFile(ticket.id);
  if (file != null) {
    return _ligneDansFile(
      ticket: ticket,
      doc: doc,
      file: file,
      historique: historique,
      quota: quota!,
      now: now,
      offline: offline,
      appelEnCours: appelEnCours,
      modeEnCours: modeEnCours,
      uid: uid,
    );
  }
  return _ligneHorsFile(
    ticket: ticket,
    doc: doc,
    historique: historique,
    quota: quota,
    now: now,
    offline: offline,
    appelEnCours: appelEnCours,
    modeEnCours: modeEnCours,
  )._avecSortie(_sortieAffichee(doc.queueExit, historique));
}

/// Ligne de sortie de file, seulement si aucune entrée `livraison` de
/// l'historique n'est postérieure à la sortie (un départ réussi n'écrit pas
/// `queue_exit`).
({String texte, bool erreur})? _sortieAffichee(
  SortieFile? sortie,
  TicketLaunchesDoc? historique,
) {
  if (sortie == null) return null;
  final at = sortie.at;
  if (at != null && historique != null) {
    for (final e in historique.entries) {
      final eAt = e.at;
      if (e.action == ActionLancement.livraison &&
          eAt != null &&
          eAt.isAfter(at)) {
        return null;
      }
    }
  }
  return ligneSortieFile(sortie);
}

/// « 2 tickets attendent déjà » ou « 1 ticket attend déjà ».
String _attendent(int n, String quoi) =>
    n == 1 ? '1 $quoi attend' : '$n ${quoi}s attendent';

/// Ticket en file (P44) : position, raison de l'attente en tête, accord, et
/// « Retirer de la file ».
LigneLivraison _ligneDansFile({
  required Ticket ticket,
  required TicketDelivery doc,
  required PositionFile file,
  required TicketLaunchesDoc? historique,
  required EtatLancements quota,
  required DateTime now,
  required bool offline,
  required bool appelEnCours,
  required ModeLivraison? modeEnCours,
  required String? uid,
}) {
  if (appelEnCours) {
    return LigneLivraison(
      ton: TonLivraison.progression,
      texte: modeEnCours == ModeLivraison.retirer
          ? 'Retrait de la file en cours.'
          : 'Lancement en cours.',
      progression: modeEnCours == ModeLivraison.retirer
          ? 'Retrait de la file en cours'
          : 'Lancement en cours',
      action: ActionLancement.livraison,
      mode: ModeLivraison.retirer,
    );
  }
  final position = 'Dans la file (position ${file.position} sur ${file.total})';
  final entree = file.entree;
  final accordAt = entree.queuedAt;
  final accord =
      'Accord${accordAt == null ? '' : ' du ${_du(accordAt)}'} pour '
      '${_pr(entree.prNumber ?? doc.prNumber)}.';
  final verrou = quota.deliveryRunning;
  final verrouAutre =
      verrou != null && verrou.ticketId != ticket.id && verrou.tient(now);
  final derniere = quota.deliveryLast;
  var ton = TonLivraison.info;
  String texte;
  String? autreId;
  int? autreIssue;
  final devant = file.devant;
  if (devant != null) {
    texte =
        '$position, derrière le ticket'
        '${devant.issueNumber == null ? '' : ' #${devant.issueNumber}'}.';
    autreId = devant.ticketId;
    autreIssue = devant.issueNumber;
  } else if (quota.developmentInvalidSince case final depuis?) {
    ton = TonLivraison.erreur;
    texte =
        '$position : la file attend, le jeton de la routine de développement '
        'est refusé depuis le ${formatDateChiffres(depuis.toLocal())}.';
  } else if (quota.deliveryQueueHalted case final arret?) {
    // Routine en pause ou appel refusé au départ (décision de l'utilisateur
    // du 2026-11-22) : la file attend le prochain lancement réussi.
    ton = TonLivraison.erreur;
    final depuis = arret.at;
    final quand = depuis == null
        ? ''
        : ' depuis le ${formatDateChiffres(depuis.toLocal())}';
    texte = switch (arret.code) {
      'routine_paused' =>
        '$position : la file attend, la routine de développement est en '
            'pause$quand. Réactivez-la sur claude.ai.',
      _ =>
        '$position : la file attend, la routine de développement a refusé le '
            'lancement$quand.',
    };
  } else if (verrouAutre) {
    final n = verrou.issueNumber;
    texte =
        '$position : partira après la livraison du ticket'
        '${n == null ? '' : ' #$n'}.';
  } else if (derniere != null &&
      derniere.ticketId != ticket.id &&
      derniere.compteRenduAttendu(now)) {
    final n = derniere.issueNumber;
    final fin = derniere.retryAfter!;
    texte =
        '$position : partira après le compte rendu de la livraison du ticket'
        '${n == null ? '' : ' #$n'}, à ${formatHeure(fin.toLocal())} au plus '
        'tard.';
  } else if (quota.plafondAtteint && uid != null && entree.byUid == uid) {
    ton = TonLivraison.plafond;
    texte =
        '$position : plafond atteint le ${quota.jourAffiche} '
        '(${quota.perDay} sur ${quota.perDay}). Elle partira quand le '
        'compteur repartira à zéro, peu après minuit.';
  } else {
    texte = '$position : départ dans 5 minutes au plus.';
  }
  // La PR n'est plus prête : la sortie au départ est annoncée. Aucune phrase
  // sur la CI tant que GitHub refuse au jeton sa lecture.
  final pr = doc.prNumber;
  final ciLisible = quota.ciReadDeniedSince == null;
  String? detail;
  var detailErreur = true;
  var reprise = false;
  if (doc.relaunchReady && ciLisible) {
    detail =
        'CI de ${_pr(pr)} en échec : la livraison sortira de la file au '
        'départ.';
    reprise =
        ticket.canLaunch(ActionLancement.reprise) &&
        historique?.enCours(ActionLancement.developpement, now) == null &&
        historique?.enCours(ActionLancement.reprise, now) == null;
  } else if (doc.eligiblePrCount > 1) {
    detail =
        '${doc.eligiblePrCount} pull requests ferment l\'Issue : la livraison '
        'sortira de la file au départ.';
  } else if (pr == null) {
    detail =
        'Aucune pull request prête : la livraison sortira de la file au '
        'départ.';
  } else if (!doc.ready && ciLisible) {
    final ci = doc.ciStatus;
    if (ci != null && ci != 'completed') {
      detailErreur = false;
      detail =
          'CI de la PR #$pr en cours : si elle n\'est pas verte au départ, la '
          'livraison sortira de la file.';
    } else {
      detail =
          'CI de la PR #$pr pas verte : la livraison sortira de la file au '
          'départ.';
    }
  }
  return LigneLivraison(
    ton: ton,
    texte: texte,
    action: ActionLancement.livraison,
    mode: ModeLivraison.retirer,
    actif: !offline && historique != null,
    verrouTicketId: autreId,
    verrouIssue: autreIssue,
    ligneAccord: accord,
    ligneDetail: detail,
    detailErreur: detailErreur,
    repriseAussi: reprise,
  );
}

/// Ticket hors file, PR relue : cas 4 à 8 (T5), avec « Mettre en file » quand
/// une autre livraison tient le verrou, n'a pas publié son compte rendu, ou
/// quand la file n'est pas vide.
LigneLivraison _ligneHorsFile({
  required Ticket ticket,
  required TicketDelivery doc,
  required TicketLaunchesDoc? historique,
  required EtatLancements? quota,
  required DateTime now,
  required bool offline,
  required bool appelEnCours,
  required ModeLivraison? modeEnCours,
}) {
  final issue = ticket.issueNumber;
  final verrou = quota?.deliveryRunning;
  final pr = doc.prNumber;
  final plafond = quota?.plafondAtteint ?? false;
  final developpementEnCours = historique?.enCours(
    ActionLancement.developpement,
    now,
  );
  bool actif() => !offline && !appelEnCours && !plafond && historique != null;
  // 4. Plusieurs PR.
  if (doc.eligiblePrCount > 1) {
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          '${doc.eligiblePrCount} pull requests ferment l\'Issue #$issue : '
          'fermez sur GitHub celles à abandonner.',
    );
  }
  // 5. CI rouge : « Relancer le développement » si le serveur l'offre.
  if (doc.relaunchReady) {
    if (!ticket.canLaunch(ActionLancement.reprise)) {
      return LigneLivraison(
        ton: TonLivraison.erreur,
        texte: 'CI de ${_pr(pr)} en échec. Ouvrez la PR pour voir l\'erreur.',
      );
    }
    final dev = developpementEnCours;
    final devAt = dev?.at;
    final devFin = dev?.retryAfter;
    if (dev != null && devAt != null && devFin != null) {
      return LigneLivraison(
        ton: TonLivraison.erreur,
        texte:
            'CI de ${_pr(pr)} en échec. Développement lancé '
            '${dateLancement(devAt)} : relance possible après '
            '${_depuis(devFin, now)}.',
      );
    }
    if (appelEnCours) {
      return const LigneLivraison(
        ton: TonLivraison.progression,
        texte: 'Lancement de la correction en cours.',
        progression: 'Lancement en cours',
        action: ActionLancement.reprise,
      );
    }
    return LigneLivraison(
      ton: plafond ? TonLivraison.plafond : TonLivraison.erreur,
      texte: plafond
          ? ligneQuota(quota)
          : 'CI de ${_pr(pr)} en échec. Une session peut la corriger sur la '
                'même branche.',
      action: ActionLancement.reprise,
      actif: actif(),
    );
  }
  // 6. Aucune PR retenue.
  if (pr == null) {
    final since = developpementEnCours?.at;
    if (since != null) {
      return LigneLivraison(
        ton: TonLivraison.info,
        texte:
            'Développement en cours depuis ${_depuis(since, now)}. La pull '
            'request n\'est pas encore prête.',
      );
    }
    return LigneLivraison(
      ton: TonLivraison.info,
      texte: 'Aucune pull request prête pour l\'Issue #$issue.',
    );
  }
  // 7. CI en cours.
  final ci = doc.ciStatus;
  if (ci != null && ci != 'completed') {
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'CI de la PR #$pr en cours. « Livrer » sera proposé quand elle sera '
          'verte.',
    );
  }
  if (!doc.ready) {
    return LigneLivraison(
      ton: TonLivraison.info,
      texte: ci == null
          ? 'CI de la PR #$pr pas encore lancée. Ouvrez la PR pour la suivre '
                'sur GitHub.'
          : 'CI de la PR #$pr terminée sans succès. Ouvrez la PR pour la '
                'suivre sur GitHub.',
    );
  }
  // 8. PR prête.
  final verrouAutre =
      verrou != null && verrou.ticketId != ticket.id && verrou.tient(now);
  final enFile = quota?.deliveryQueue.length ?? 0;
  final peutLivrer = ticket.canLaunch(ActionLancement.livraison);
  // « Mettre en file » reste actif au plafond : l'entrée attendra.
  bool actifFile() => !offline && !appelEnCours && historique != null;
  // Appel « Mettre en file » en cours : avant les lignes de la file, qui le
  // proposent.
  if (peutLivrer && appelEnCours && modeEnCours == ModeLivraison.mettreEnFile) {
    return const LigneLivraison(
      ton: TonLivraison.progression,
      texte: 'Mise en file en cours.',
      progression: 'Mise en file en cours',
      action: ActionLancement.livraison,
      mode: ModeLivraison.mettreEnFile,
    );
  }
  if (verrouAutre) {
    final at = verrou.launchedAt;
    final numero = verrou.issueNumber;
    final attente = enFile == 0 ? '' : ' ${_attendent(enFile, 'ticket')} déjà.';
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'Livraison du ticket ${numero == null ? '' : '#$numero '}en cours'
          '${at == null ? '' : ' depuis ${_depuis(at, now)}'}. Une seule '
          'livraison à la fois.$attente',
      verrouTicketId: verrou.ticketId,
      verrouIssue: numero,
      action: peutLivrer ? ActionLancement.livraison : null,
      mode: peutLivrer ? ModeLivraison.mettreEnFile : null,
      actif: peutLivrer && actifFile(),
    );
  }
  final derniere = quota?.deliveryLast;
  if (peutLivrer &&
      derniere != null &&
      derniere.ticketId != ticket.id &&
      derniere.compteRenduAttendu(now)) {
    final numero = derniere.issueNumber;
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'La livraison du ticket ${numero == null ? '' : '#$numero '}n\'a '
          'pas encore publié son compte rendu. Une seule livraison à la fois.',
      verrouTicketId: derniere.ticketId,
      verrouIssue: numero,
      action: ActionLancement.livraison,
      mode: ModeLivraison.mettreEnFile,
      actif: actifFile(),
    );
  }
  if (peutLivrer && enFile > 0) {
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          '${_attendent(enFile, 'livraison')} dans la file. La prochaine part '
          'dans 5 minutes au plus.',
      action: ActionLancement.livraison,
      mode: ModeLivraison.mettreEnFile,
      actif: actifFile(),
    );
  }
  if (!peutLivrer) {
    final valider =
        ticket.allowedDecisions?.contains(TicketDecisionAction.validate) ??
        false;
    return LigneLivraison(
      ton: TonLivraison.info,
      texte: valider
          ? 'PR #$pr prête. Ce ticket a été validé sur GitHub : fusionnez la '
                'PR sur GitHub, ou validez-le depuis l\'application pour la '
                'livrer d\'ici.'
          : 'PR #$pr prête. Ce ticket a été validé sur GitHub : fusionnez la '
                'PR sur GitHub.',
    );
  }
  if (appelEnCours) {
    return const LigneLivraison(
      ton: TonLivraison.progression,
      texte: 'Lancement de la livraison en cours.',
      progression: 'Lancement en cours',
      action: ActionLancement.livraison,
    );
  }
  if (plafond) {
    return LigneLivraison(
      ton: TonLivraison.plafond,
      texte: ligneQuota(quota),
      action: ActionLancement.livraison,
    );
  }
  final precedente = historique?.aRelancer(
    ActionLancement.livraison,
    now,
    statusChangedAt: ticket.statusChangedAt,
  );
  final precedenteAt = precedente?.at;
  if (precedente != null && precedenteAt != null) {
    // Texte choisi d'après `ended_by`, écrit par le serveur (P46).
    final bloquee = precedente.arreteeParBlocage;
    return LigneLivraison(
      ton: bloquee ? TonLivraison.erreur : TonLivraison.info,
      texte: bloquee
          ? 'La livraison du ${_du(precedenteAt)} s\'est arrêtée. '
                'Lisez le blocage dans la section Livraison.'
          : ligneLivraisonSansFusion(precedenteAt),
      action: ActionLancement.livraison,
      actif: actif(),
      relanceDe: precedenteAt,
    );
  }
  final verte = doc.ciCompletedAt;
  return LigneLivraison(
    ton: TonLivraison.prete,
    texte: verte == null
        ? 'PR #$pr prête : CI verte.'
        : 'PR #$pr prête : CI verte ${dateLancement(verte.toLocal())}.',
    action: ActionLancement.livraison,
    actif: actif(),
  );
}

/// Livraison dont l'échéance est passée sans fusion ni blocage relevé.
String ligneLivraisonSansFusion(DateTime at) =>
    'La livraison du ${_du(at)} n\'a rien fusionné en trois heures. '
    'Vérifiez sur claude.ai/code qu\'aucune session ne tourne encore.';

/// Pastille de la liste d'Admin › Tickets pour un ticket En cours, ou `null`.
enum PastilleLivraisonType {
  livraisonEnCours,
  correctionEnCours,
  ciEnCours,
  ciRouge,

  /// Dans la file des livraisons : « En file 2/3 ».
  enFile,
  prPrete,
}

/// La pastille d'un ticket En cours : livraison en cours (verrou ou
/// historique), correction (reprise) en cours, CI en cours, CI en échec
/// (`relaunch_ready` écrit par le serveur, sans développement en cours), PR
/// prête ; une seule, dans l'ordre : livraison en cours, correction en cours,
/// CI en échec, en file (ticket #104), CI en cours, PR prête (UX T5, ticket
/// #63). Ni « CI en
/// cours », ni « CI en échec », ni « PR prête » tant que
/// `ticket_status/launches.ci_read_denied_since` est posé : l'état de la CI
/// n'est plus relu par le serveur.
PastilleLivraisonType? pastilleLivraison({
  required Ticket ticket,
  required TicketDelivery? livraison,
  required TicketLaunchesDoc? historique,
  required EtatLancements? quota,
  required DateTime now,
}) {
  if (ticket.status != TicketStatus.inProgress) return null;
  final verrou = quota?.deliveryRunning;
  if ((verrou != null && verrou.ticketId == ticket.id && verrou.tient(now)) ||
      historique?.enCours(ActionLancement.livraison, now) != null) {
    return PastilleLivraisonType.livraisonEnCours;
  }
  if (historique?.enCours(ActionLancement.reprise, now) != null) {
    return PastilleLivraisonType.correctionEnCours;
  }
  final lisible = livraison != null && quota?.ciReadDeniedSince == null;
  final developpement = historique?.enCours(ActionLancement.developpement, now);
  if (lisible && livraison.relaunchReady && developpement == null) {
    return PastilleLivraisonType.ciRouge;
  }
  if (quota?.positionFile(ticket.id) != null) {
    return PastilleLivraisonType.enFile;
  }
  if (!lisible) return null;
  final ci = livraison.ciStatus;
  if (livraison.prNumber != null && ci != null && ci != 'completed') {
    return PastilleLivraisonType.ciEnCours;
  }
  if (livraison.relaunchReady) return null;
  if (livraison.ready) return PastilleLivraisonType.prPrete;
  return null;
}

/// Filtre « À traiter » de la liste d'Admin › Tickets (ticket #63) : le
/// serveur permet une action qui fait avancer le ticket, et aucune session ne
/// tourne déjà pour elle. Lu dans les documents du serveur seuls
/// (`allowed_decisions`, `admin/launches` [historique], `admin/delivery`
/// [livraison], `ticket_status/launches` [quota]) : aucune précondition
/// recopiée (P39, P42, P46).
///
/// - envoi impossible (`send_failed`) ;
/// - `validate` permis (Analysé, ou Validé sur GitHub seul) ;
/// - `launch_analysis` ou `launch_development` permis, sans lancement de
///   cette action en cours ;
/// - PR prête (pastille « PR prête », règle d'avant le ticket #63) ;
/// - `relaunch_development` permis et pastille « CI en échec » (`ciRouge`).
///
/// Un ticket dans la file des livraisons n'est pas à traiter : l'accord est
/// donné (ticket #104).
///
/// [historique] ou [livraison] absent, illisible ou en panne : aucun
/// lancement n'est tenu pour en cours ; un ticket permis par
/// `allowed_decisions` reste à traiter plutôt que caché.
bool ticketATraiter({
  required Ticket ticket,
  required TicketLaunchesDoc? historique,
  required TicketDelivery? livraison,
  required EtatLancements? quota,
  required DateTime now,
}) {
  if (ticket.status == TicketStatus.sendFailed) return true;
  if (quota?.positionFile(ticket.id) != null) return false;
  if (ticket.allowedDecisions?.contains(TicketDecisionAction.validate) ??
      false) {
    return true;
  }
  for (final action in [
    ActionLancement.analyse,
    ActionLancement.developpement,
  ]) {
    if (ticket.canLaunch(action) && historique?.enCours(action, now) == null) {
      return true;
    }
  }
  final pastille = pastilleLivraison(
    ticket: ticket,
    livraison: livraison,
    historique: historique,
    quota: quota,
    now: now,
  );
  return pastille == PastilleLivraisonType.prPrete ||
      (pastille == PastilleLivraisonType.ciRouge &&
          ticket.canLaunch(ActionLancement.reprise));
}
