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

/// Dernier accord sur les règles du réseau (`network_rules_ack`, ADR-020),
/// écrit par le serveur seul. Le client ne compare aucune tête : la validité
/// est [TicketDelivery.networkRulesAckValid].
@immutable
class AccordRegles {
  const AccordRegles({required this.headSha, this.at, this.publie = false});

  /// Tête accordée (40 chiffres hexadécimaux).
  final String headSha;
  final DateTime? at;

  /// Commentaire d'accord publié sur l'Issue (`comment_id` posé).
  final bool publie;
}

/// Document `tickets/{id}/admin/delivery` (ADR-008, T5, P45), écrit par le
/// serveur seul et lu par l'administrateur seul. Le client lit `ready`,
/// `relaunch_ready`, les champs des règles du réseau et la validité de
/// l'accord tels quels : il ne recalcule ni l'éligibilité d'une PR, ni l'état
/// de la CI, ni les catégories de fichiers, ni la comparaison des têtes (P39,
/// P46).
@immutable
class TicketDelivery {
  const TicketDelivery({
    this.eligiblePrCount = 0,
    this.prNumber,
    this.prUrl,
    this.headSha,
    this.ciStatus,
    this.ciConclusion,
    this.ciCompletedAt,
    this.ready = false,
    this.relaunchReady = false,
    this.reports = const [],
    this.networkRulesFiles = const [],
    this.networkRulesControls = const [],
    this.networkRulesControlsComplete = true,
    this.sensitiveFile,
    this.filesComplete = true,
    this.networkRulesAck,
    this.networkRulesAckValid = false,
  });

  final int eligiblePrCount;
  final int? prNumber;

  /// Adresse écrite par le serveur ; ouverte après [lienPullRequestOuvrable].
  final String? prUrl;

  /// Tête de la PR retenue, envoyée telle quelle par « Approuver les règles
  /// et livrer ».
  final String? headSha;

  /// Règles du réseau touchées par la PR (`network_rules_files`).
  final List<String> networkRulesFiles;

  /// Numéros des contrôles `Pn` changés dans `CLAUDE.md`.
  final List<int> networkRulesControls;

  /// Faux si GitHub n'a pas rendu le patch de `CLAUDE.md`.
  final bool networkRulesControlsComplete;

  /// Premier fichier protégé de la PR (`sensitive_files`), ou `null`.
  final String? sensitiveFile;

  /// Faux si la liste des fichiers dépasse 1 000 entrées.
  final bool filesComplete;

  /// Dernier accord, ou `null`.
  final AccordRegles? networkRulesAck;

  /// Accord valable pour la tête courante, calculé par le serveur.
  final bool networkRulesAckValid;

  /// La PR change les règles du réseau : « Approuver les règles et livrer »
  /// remplace « Livrer ».
  bool get reglesDuReseau => networkRulesFiles.isNotEmpty;

  /// État de l'accord affiché dans la section « Livraison », ou `null`.
  /// « annulé » : un accord publié existe et le serveur le dit invalide, donc
  /// donné pour une autre tête. [livraisonEnCours] : une livraison de ce
  /// ticket tourne (verrou ou historique lus par la fiche) ; son commit de
  /// fusion change la tête sans annuler l'accord qui l'a lancée.
  String? etatAccord({bool livraisonEnCours = false}) {
    final ack = networkRulesAck;
    if (ack == null || !ack.publie) return null;
    final court = ack.headSha.length < 7
        ? ack.headSha
        : ack.headSha.substring(0, 7);
    if (livraisonEnCours) {
      return 'Accord donné pour la tête $court. Livraison en cours.';
    }
    if (networkRulesAckValid) return 'Accord donné pour la tête $court.';
    return 'Accord annulé par un nouveau commit.';
  }

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
    final files = <String>[];
    final rawFiles = data['network_rules_files'];
    if (rawFiles != null) {
      if (rawFiles is! List) {
        throw const DocumentIllisible('network_rules_files', 'liste attendue');
      }
      for (final f in rawFiles) {
        if (f is! String) {
          throw const DocumentIllisible('network_rules_files', 'texte attendu');
        }
        files.add(f);
      }
    }
    final controls = <int>[];
    final rawControls = data['network_rules_controls'];
    if (rawControls != null) {
      if (rawControls is! List) {
        throw const DocumentIllisible(
          'network_rules_controls',
          'liste attendue',
        );
      }
      for (final c in rawControls) {
        if (c is! num || c != c.truncateToDouble() || c < 0) {
          throw const DocumentIllisible(
            'network_rules_controls',
            'entier positif attendu',
          );
        }
        controls.add(c.toInt());
      }
    }
    AccordRegles? ack;
    final rawAck = read.objetFacultatif('network_rules_ack');
    if (rawAck != null) {
      final sha = rawAck.texteFacultatif('head_sha');
      if (sha != null) {
        ack = AccordRegles(
          headSha: sha,
          at: rawAck.date('at'),
          publie: rawAck.nombreFacultatif('comment_id') != null,
        );
      }
    }
    return TicketDelivery(
      eligiblePrCount: entier('eligible_pr_count') ?? 0,
      prNumber: entier('pr_number'),
      prUrl: read.texteFacultatif('pr_url'),
      headSha: read.texteFacultatif('head_sha'),
      networkRulesFiles: List.unmodifiable(files),
      networkRulesControls: List.unmodifiable(controls),
      networkRulesControlsComplete:
          read.boolFacultatif('network_rules_controls_complete') ?? true,
      sensitiveFile: read.texteFacultatif('sensitive_files'),
      filesComplete: read.boolFacultatif('files_complete') ?? true,
      networkRulesAck: ack,
      networkRulesAckValid:
          read.boolFacultatif('network_rules_ack_valid') ?? false,
      ciStatus: read.texteFacultatif('ci_status'),
      ciConclusion: read.texteFacultatif('ci_conclusion'),
      ciCompletedAt: read.date('ci_completed_at'),
      ready: read.boolFacultatif('ready') ?? false,
      relaunchReady: read.boolFacultatif('relaunch_ready') ?? false,
      reports: reports,
    );
  }
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

/// Adresse du diff d'une PR, `https://github.com/ChinaFred/KassBeer/pull/<n>/files`
/// relue par `Uri.tryParse` ; `null` sinon : rien n'est ouvert (P39, ADR-020).
Uri? lienDiffPullRequest(int? prNumber) {
  if (prNumber == null) return null;
  final uri = Uri.tryParse(
    'https://github.com/ChinaFred/KassBeer/pull/$prNumber/files',
  );
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
      s.length == 5 &&
      s[0] == 'ChinaFred' &&
      s[1] == 'KassBeer' &&
      s[2] == 'pull' &&
      RegExp(r'^[1-9][0-9]{0,6}$').hasMatch(s[3]) &&
      s[4] == 'files';
  return ok ? uri : null;
}

/// « P10, P65 », ou « aucun ».
String listeControles(List<int> controls) =>
    controls.isEmpty ? 'aucun' : controls.map((c) => 'P$c').join(', ');

/// Libellé du bouton qui remplace « Livrer » pour une PR de règles.
const kApprouverRegles = 'Approuver les règles et livrer';

/// Étiquette d'une PR qui change les règles du réseau (liste et fiche).
const kReglesModifiees = 'Règles du réseau modifiées';

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
    this.reglesDuReseau = false,
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

  /// La PR change les règles du réseau : le bouton de [action] `livraison`
  /// est « Approuver les règles et livrer » (ADR-020).
  final bool reglesDuReseau;
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

/// PR de règles sans tête ou sans numéro dans `admin/delivery` : rien ne
/// s'approuve sans eux.
const kEtatPrIncomplet =
    'État de la PR incomplet : rouvrez la fiche dans un instant.';

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
LigneLivraison? ligneLivraison({
  required Ticket ticket,
  required RechercheDocument<TicketDelivery>? livraison,
  required bool livraisonEnPanne,
  required TicketLaunchesDoc? historique,
  required EtatLancements? quota,
  required DateTime now,
  required bool offline,
  required bool appelEnCours,
}) {
  if (ticket.status != TicketStatus.inProgress || ticket.issueNumber == null) {
    return null;
  }
  final issue = ticket.issueNumber;
  final verrou = quota?.deliveryRunning;
  final verrouIci =
      verrou != null && verrou.ticketId == ticket.id && verrou.tient(now);
  final livraisonEnCours = historique?.enCours(ActionLancement.livraison, now);
  // 1. Livraison de ce ticket en cours : verrou ou entrée de l'historique.
  if (verrouIci || livraisonEnCours != null) {
    final since = livraisonEnCours?.at ?? verrou?.launchedAt;
    return LigneLivraison(
      ton: TonLivraison.enCours,
      texte: since == null
          ? 'Livraison en cours.'
          : 'Livraison en cours depuis ${_depuis(since, now)}.',
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
    final bouton = doc.reglesDuReseau ? kApprouverRegles : 'Livrer';
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'CI de la PR #$pr en cours. « $bouton » sera proposé quand elle sera '
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
  // 7 bis. PR qui change les règles du réseau mais ne peut pas être approuvée
  // depuis l'application (ADR-020) : champs écrits par le serveur.
  final regles = doc.reglesDuReseau;
  if (regles && doc.sensitiveFile != null) {
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'PR #$pr prête. Elle change les règles du réseau et un fichier '
          'protégé (${doc.sensitiveFile}) : fusionnez-la vous-même après '
          'relecture.',
    );
  }
  if (regles && !doc.filesComplete) {
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'La liste des fichiers de la PR #$pr est trop longue pour être '
          'vérifiée. Fusionnez-la vous-même après relecture.',
    );
  }
  if (regles && !doc.networkRulesControlsComplete) {
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'PR #$pr prête. Les contrôles changés ne peuvent pas être lus : '
          'fusionnez-la vous-même après relecture.',
    );
  }
  if (regles && doc.headSha == null) {
    return const LigneLivraison(
      ton: TonLivraison.info,
      texte: kEtatPrIncomplet,
    );
  }
  // 8. PR prête.
  if (verrou != null && verrou.ticketId != ticket.id && verrou.tient(now)) {
    final at = verrou.launchedAt;
    final numero = verrou.issueNumber;
    return LigneLivraison(
      ton: TonLivraison.info,
      texte:
          'Livraison du ticket ${numero == null ? '' : '#$numero '}en cours'
          '${at == null ? '' : ' depuis ${_depuis(at, now)}'}. Une seule '
          'livraison à la fois.',
      verrouTicketId: verrou.ticketId,
      verrouIssue: numero,
    );
  }
  if (!ticket.canLaunch(ActionLancement.livraison)) {
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
    return LigneLivraison(
      ton: TonLivraison.progression,
      texte: 'Lancement de la livraison en cours.',
      progression: 'Lancement en cours',
      action: ActionLancement.livraison,
      reglesDuReseau: regles,
    );
  }
  if (plafond) {
    return LigneLivraison(
      ton: TonLivraison.plafond,
      texte: ligneQuota(quota),
      action: ActionLancement.livraison,
      reglesDuReseau: regles,
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
      reglesDuReseau: regles,
    );
  }
  final verte = doc.ciCompletedAt;
  final ciVerte = verte == null
      ? 'PR #$pr prête : CI verte.'
      : 'PR #$pr prête : CI verte ${dateLancement(verte.toLocal())}.';
  return LigneLivraison(
    ton: TonLivraison.prete,
    texte: regles
        ? '$ciVerte Elle change les règles du réseau : lisez le diff avant '
              'd\'approuver.'
        : ciVerte,
    action: ActionLancement.livraison,
    actif: actif(),
    reglesDuReseau: regles,
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
  prPrete,
}

/// La pastille d'un ticket En cours : livraison en cours (verrou ou
/// historique), correction (reprise) en cours, CI en cours, CI en échec
/// (`relaunch_ready` écrit par le serveur, sans développement en cours), PR
/// prête ; une seule, dans cet ordre (UX T5, ticket #63). Ni « CI en
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
  if (livraison == null || quota?.ciReadDeniedSince != null) return null;
  final ci = livraison.ciStatus;
  if (livraison.prNumber != null && ci != null && ci != 'completed') {
    return PastilleLivraisonType.ciEnCours;
  }
  if (livraison.relaunchReady) {
    return historique?.enCours(ActionLancement.developpement, now) == null
        ? PastilleLivraisonType.ciRouge
        : null;
  }
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
