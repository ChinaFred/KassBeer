import 'package:flutter/foundation.dart';

import '../../../core/presentation/formats.dart';

/// Gravité d'une entrée de journal, lue dans `severity` (vocabulaire de Cloud
/// Logging). Une gravité hors de ces quatre familles est [autre].
enum GraviteJournal {
  erreur('Erreur'),
  avertissement('Avertissement'),
  information('Information'),
  debogage('Débogage'),
  autre('Gravité inconnue');

  const GraviteJournal(this.mot);

  /// Mot lu par un lecteur d'écran.
  final String mot;

  static GraviteJournal depuis(String severity) => switch (severity) {
    'ERROR' || 'CRITICAL' || 'ALERT' || 'EMERGENCY' => erreur,
    'WARNING' => avertissement,
    'INFO' || 'NOTICE' => information,
    'DEBUG' => debogage,
    _ => autre,
  };
}

/// Filtre « Gravité » d'Admin › Journaux : valeur `severity` de `queryLogs`.
enum FiltreGravite {
  infoEtPlus('INFO', 'Info et plus'),
  avertissementsEtPlus('WARNING', 'Avertissements et plus'),
  erreurs('ERROR', 'Erreurs'),
  debogageSeul('DEBUG', 'Débogage seul');

  const FiltreGravite(this.severity, this.libelle);

  final String severity;
  final String libelle;
}

/// Filtre « Période » d'Admin › Journaux : `periodMinutes` de `queryLogs`.
enum FiltrePeriode {
  uneHeure(60, '1 h'),
  unJour(1440, '24 h'),
  septJours(10080, '7 jours');

  const FiltrePeriode(this.minutes, this.libelle);

  final int minutes;
  final String libelle;
}

/// Filtres d'une recherche. Le serveur contrôle chaque valeur (P48) : le
/// client ne recopie ni la forme d'un identifiant de ticket ni la borne du
/// texte.
@immutable
class FiltresJournaux {
  const FiltresJournaux({
    this.gravite = FiltreGravite.infoEtPlus,
    this.periode = FiltrePeriode.uneHeure,
    this.fonction,
    this.ticket = '',
    this.texte = '',
  });

  static const toutesLesFonctions = 'Toutes les fonctions';

  final FiltreGravite gravite;
  final FiltrePeriode periode;

  /// Nom d'une fonction de la liste rendue par le serveur, ou `null` (toutes).
  final String? fonction;
  final String ticket;
  final String texte;

  String get _ticket => ticket.trim();

  FiltresJournaux copyWith({
    FiltreGravite? gravite,
    FiltrePeriode? periode,
    String? Function()? fonction,
    String? ticket,
    String? texte,
  }) => FiltresJournaux(
    gravite: gravite ?? this.gravite,
    periode: periode ?? this.periode,
    fonction: fonction == null ? this.fonction : fonction(),
    ticket: ticket ?? this.ticket,
    texte: texte ?? this.texte,
  );

  /// Arguments de `queryLogs`, sans la page suivante.
  Map<String, Object?> versArguments() => {
    'severity': gravite.severity,
    'periodMinutes': periode.minutes,
    if (fonction != null) 'functionName': fonction,
    if (_ticket.isNotEmpty) 'ticketId': _ticket,
    if (texte.isNotEmpty) 'freeText': texte,
  };

  /// « Info et plus · 1 h · Toutes les fonctions ».
  String get resume => [
    gravite.libelle,
    periode.libelle,
    fonction ?? toutesLesFonctions,
    if (_ticket.isNotEmpty) 'Ticket $_ticket',
    if (texte.isNotEmpty) '« $texte »',
  ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is FiltresJournaux &&
      other.gravite == gravite &&
      other.periode == periode &&
      other.fonction == fonction &&
      other._ticket == _ticket &&
      other.texte == texte;

  @override
  int get hashCode => Object.hash(gravite, periode, fonction, _ticket, texte);
}

/// Entrée rendue par `queryLogs` (ADR-011, J2). Textes déjà passés par
/// `redactSecrets` au serveur ; les adresses e-mail restent visibles.
@immutable
class EntreeJournal {
  const EntreeJournal({
    required this.horodatage,
    required this.severity,
    required this.fonction,
    required this.message,
    required this.insertId,
    required this.payload,
    required this.payloadCoupe,
    this.messageCoupe = false,
    required this.caracteresGardes,
  });

  static const sansMessage = 'Entrée sans message';
  static const dateIllisible = 'Date illisible';

  /// Heure de l'entrée, en heure locale ; `null` si illisible.
  final DateTime? horodatage;
  final String severity;
  final String fonction;
  final String message;
  final String insertId;

  /// `jsonPayload` sans `message`, en JSON indenté ; vide s'il n'y a rien.
  final String payload;

  /// Le serveur a coupé [payload] (`payloadTruncated`).
  final bool payloadCoupe;

  /// Le serveur a coupé [message] (`messageTruncated`).
  final bool messageCoupe;

  /// Caractères gardés par le serveur (`maxChars` de la réponse) : le
  /// client n'en écrit aucune valeur.
  final int caracteresGardes;

  GraviteJournal get gravite => GraviteJournal.depuis(severity);

  /// Lit une entrée de la réponse ; lève [FormatException] si elle n'a pas la
  /// forme attendue.
  factory EntreeJournal.depuis(Object? brut, {required int caracteresGardes}) {
    if (brut is! Map) throw const FormatException('entrée non objet');
    String texte(String cle) => switch (brut[cle]) {
      final String s => s,
      null => '',
      _ => throw FormatException('champ $cle non texte'),
    };
    final coupe = brut['payloadTruncated'];
    if (coupe is! bool) throw const FormatException('payloadTruncated');
    final messageCoupe = brut['messageTruncated'];
    if (messageCoupe is! bool) {
      throw const FormatException('messageTruncated');
    }
    return EntreeJournal(
      horodatage: DateTime.tryParse(texte('timestamp'))?.toLocal(),
      severity: texte('severity'),
      fonction: texte('functionName'),
      message: texte('message'),
      insertId: texte('insertId'),
      payload: texte('payload'),
      payloadCoupe: coupe,
      messageCoupe: messageCoupe,
      caracteresGardes: caracteresGardes,
    );
  }

  /// Message entier, ou [sansMessage].
  String get messageComplet =>
      message.trim().isEmpty ? sansMessage : message.trim();

  /// Première ligne du message (une pile d'appels suit pour un `ERROR`).
  String get titre => messageComplet.split('\n').first.trim();

  /// Le message tient sur plusieurs lignes : il s'affiche en chasse fixe.
  bool get messageMultiligne => messageComplet.contains('\n');

  String get date => switch (horodatage) {
    final h? => formatJourCourtHeureSecondes(h),
    null => dateIllisible,
  };

  /// « 15 nov. 18:30:42 · synctickets ».
  String get resume => [date, if (fonction.isNotEmpty) fonction].join(' · ');

  /// Texte de « Copier l'entrée ».
  String get texteCopie => [
    '$date · $severity${fonction.isEmpty ? '' : ' · $fonction'}',
    '',
    'Message',
    messageComplet,
    if (payload.isNotEmpty) ...['', 'Données', payload],
  ].join('\n');
}

/// Une page de la recherche, du plus récent au plus ancien.
@immutable
class PageJournaux {
  const PageJournaux({
    required this.entrees,
    required this.suite,
    required this.fonctions,
  });

  final List<EntreeJournal> entrees;

  /// Jeton opaque de la page suivante ; `null` : fin des journaux.
  final String? suite;

  /// Noms filtrables rendus par le serveur, menu « Fonction ».
  final List<String> fonctions;

  /// Lit `data` de `queryLogs` ; lève [FormatException] sinon.
  factory PageJournaux.depuis(Object? data) {
    if (data is! Map) throw const FormatException('réponse non objet');
    final entries = data['entries'];
    final functions = data['functions'];
    final next = data['nextPageToken'];
    final gardes = data['maxChars'];
    if (entries is! List || functions is! List) {
      throw const FormatException('entries ou functions absents');
    }
    if (gardes is! int || gardes <= 0) {
      throw const FormatException('maxChars');
    }
    if (next != null && next is! String) {
      throw const FormatException('nextPageToken');
    }
    return PageJournaux(
      entrees: [
        for (final e in entries)
          EntreeJournal.depuis(e, caracteresGardes: gardes),
      ],
      suite: (next as String?)?.isEmpty ?? true ? null : next,
      fonctions: [
        for (final f in functions)
          if (f is String) f else throw const FormatException('functions'),
      ],
    );
  }
}

/// Cause d'un échec de `queryLogs`, lue dans le code et `details.reason`. Les
/// libellés sont ceux de l'écran ; aucune borne du serveur n'y est recopiée.
enum CauseEchecJournaux {
  quota('Quota de lecture des journaux atteint, réessayez dans une minute.'),
  iam(
    'Lecture des journaux non autorisée : rôle IAM manquant.',
    reessayable: false,
  ),
  emulateur('Journaux non disponibles dans l\'émulateur.', reessayable: false),
  indisponible('Journaux indisponibles pour l\'instant.'),
  acces('Réservé à l\'administrateur.', reessayable: false),
  horsLigne('Hors ligne. La recherche des journaux demande le réseau.'),

  /// Argument refusé, posé sous son champ ([EchecJournaux.champ]) avec le
  /// message du serveur ([EchecJournaux.motif]).
  champ('Valeur refusée par le serveur.', reessayable: false),

  /// Page suivante refusée (`field` `pageToken` : trop ancienne ou
  /// illisible) : « Réessayer » relance la première page.
  refuse('Page suivante refusée par le serveur. Relancez la recherche.'),

  /// Autre argument refusé (gravité, fonction, période…) : la même recherche
  /// échouerait encore, aucun « Réessayer ».
  rejete('Recherche refusée par le serveur.', reessayable: false);

  const CauseEchecJournaux(this.message, {this.reessayable = true});

  final String message;

  /// « Réessayer » est proposé.
  final bool reessayable;
}

/// Échec de `queryLogs`, levé par le dépôt de données après son rapport.
class EchecJournaux implements Exception {
  const EchecJournaux(this.cause, {this.champ, this.motif});

  /// Champs qu'un refus `invalid-argument` peut viser à l'écran.
  static const champTicket = 'ticketId';
  static const champTexte = 'freeText';
  static const champPage = 'pageToken';

  final CauseEchecJournaux cause;

  /// `details.field` d'un refus [CauseEchecJournaux.champ].
  final String? champ;

  /// Message de la `HttpsError` d'un refus de champ, affiché sous le champ.
  final String? motif;

  /// Lit le code et les `details` d'une `HttpsError`.
  factory EchecJournaux.depuis({
    required String code,
    Object? details,
    String? message,
  }) {
    final map = details is Map ? details : const {};
    final reason = map['reason'];
    final field = map['field'];
    return switch (code) {
      'resource-exhausted' => const EchecJournaux(CauseEchecJournaux.quota),
      'failed-precondition' when reason == 'emulator' => const EchecJournaux(
        CauseEchecJournaux.emulateur,
      ),
      'failed-precondition' when reason == 'iam' => const EchecJournaux(
        CauseEchecJournaux.iam,
      ),
      'permission-denied' ||
      'unauthenticated' => const EchecJournaux(CauseEchecJournaux.acces),
      'invalid-argument' when field == champTicket || field == champTexte =>
        EchecJournaux(
          CauseEchecJournaux.champ,
          champ: field as String,
          motif: (message ?? '').trim().isEmpty ? null : message!.trim(),
        ),
      'invalid-argument' when field == champPage => const EchecJournaux(
        CauseEchecJournaux.refuse,
      ),
      'invalid-argument' => const EchecJournaux(CauseEchecJournaux.rejete),
      // `unavailable` sans motif : l'appel n'a pas atteint le serveur.
      'unavailable' when reason == null => const EchecJournaux(
        CauseEchecJournaux.horsLigne,
      ),
      _ => const EchecJournaux(CauseEchecJournaux.indisponible),
    };
  }

  @override
  String toString() => 'EchecJournaux(${cause.name}, champ: $champ)';
}
