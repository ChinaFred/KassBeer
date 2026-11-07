import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Rapport d'erreur prêt à écrire dans `error_reports/` (P13).
///
/// Les champs et leurs bornes suivent `firestore.rules` : `uid`, `feature` (1 à 100),
/// `error` (2 000), `stack_trace` (8 000), `context` (2 000), `app_version` (40),
/// `platform` (`android` ou `web`), `created_at` (`serverTimestamp()`). Un champ trop
/// long est coupé ici, jamais refusé par les règles.
@immutable
class ErrorReportFields {
  const ErrorReportFields._(this.data);

  static const maxFeature = 100;
  static const maxError = 2000;
  static const maxStackTrace = 8000;
  static const maxContext = 2000;
  static const maxAppVersion = 40;

  /// Remplace une adresse e-mail dans un texte de rapport. Les règles ne lisent pas
  /// le contenu : c'est ici que l'e-mail est retiré (P13).
  static const emailPlaceholder = '<e-mail>';

  /// Remplace une URL (`schéma://…`) : une URL peut porter un jeton, un identifiant
  /// ou l'adresse d'une photo de compte Google.
  static const urlPlaceholder = '<url>';

  static final RegExp _url = RegExp(r'\b[a-zA-Z][a-zA-Z0-9+.-]*://[^\s<>"]+');

  static final RegExp _email = RegExp(
    r'[^\s@<>()"]+@[^\s@<>()"]+\.[^\s@<>()"]+',
  );

  /// Les champs à écrire. `created_at` vaut `FieldValue.serverTimestamp()`.
  final Map<String, Object?> data;

  factory ErrorReportFields.build({
    required String uid,
    required String feature,
    required Object error,
    StackTrace? stackTrace,
    String? context,
    String? appVersion,
    required String platform,
  }) {
    final cleanFeature = truncate(
      feature.trim().isEmpty ? 'inconnu' : feature.trim(),
      maxFeature,
    );
    final stack = stackTrace?.toString();
    return ErrorReportFields._({
      'uid': uid,
      'feature': cleanFeature,
      'error': truncate(sanitize('${error.runtimeType}: $error'), maxError),
      if (stack != null && stack.isNotEmpty)
        'stack_trace': truncate(sanitize(stack), maxStackTrace),
      if (context != null && context.isNotEmpty)
        'context': truncate(sanitize(context), maxContext),
      if (appVersion != null && appVersion.isNotEmpty)
        'app_version': truncate(appVersion, maxAppVersion),
      'platform': platform,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// [text] sans ses URL ni ses adresses e-mail.
  static String sanitize(String text) => text
      .replaceAll(_url, urlPlaceholder)
      .replaceAll(_email, emailPlaceholder);

  /// [value] coupé à [max] unités UTF-16, sans couper un caractère en deux, terminé
  /// par « … » quand il a été coupé. Les règles comptent en caractères : une chaîne
  /// coupée en unités UTF-16 ne les dépasse jamais.
  static String truncate(String value, int max) {
    if (value.length <= max) return value;
    var end = max - 1;
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
    return '${value.substring(0, end)}…';
  }
}

/// Journal d'erreurs de l'application : chaque erreur attrapée passe par
/// [reportError] (CLAUDE.md, « Règles de code »).
///
/// Injecté par constructeur dans les dépôts de données et les écrans. Firestore et
/// Firebase Auth sont résolus à l'usage : le service se construit sans application
/// Firebase initialisée, donc dans les tests.
///
/// Écritures bornées : un rapport identique (même `feature`, même type d'erreur, même
/// premier cadre de pile) n'est écrit qu'une fois par session ; au plus
/// [maxPerMinute] écritures par minute et [maxPerSession] par session. Le surplus part
/// sur la console, avec le compte des rapports écartés.
class ErrorReportService {
  ErrorReportService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.appVersion,
    String? Function()? currentUid,
    DateTime Function()? clock,
  }) : _injectedFirestore = firestore,
       _injectedAuth = auth,
       _currentUid = currentUid,
       _clock = clock ?? DateTime.now;

  static const maxPerMinute = 20;
  static const maxPerSession = 200;

  final FirebaseFirestore? _injectedFirestore;
  final FirebaseAuth? _injectedAuth;
  final String? Function()? _currentUid;
  final DateTime Function() _clock;

  /// Version installée, lue au démarrage ; `null` si la lecture a échoué.
  final String? appVersion;

  final Set<String> _written = {};
  final List<DateTime> _recentWrites = [];
  int _sessionWrites = 0;

  /// Rapports non écrits (doublons et plafonds) depuis le début de la session.
  int get skippedCount => _skipped;
  int _skipped = 0;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  /// Écrit un rapport dans `error_reports/`, sans attendre le serveur.
  ///
  /// Hors ligne, l'écriture attend le retour du réseau dans le cache ; l'appelant
  /// n'est jamais bloqué. [context] est un texte libre : ni prix, ni stock, ni coût, ni
  /// e-mail (P13). Les URL et les adresses e-mail sont retirées de tous les champs.
  ///
  /// Sans compte connecté, les règles refusent l'écriture : le rapport part sur la
  /// console. Un compte connecté mais non invité voit aussi son écriture refusée ; le
  /// refus part sur la console, sans nouveau rapport.
  void reportError({
    required String feature,
    required Object error,
    StackTrace? stackTrace,
    String? context,
  }) {
    final String? uid;
    try {
      uid = _currentUid != null ? _currentUid() : _auth.currentUser?.uid;
    } catch (authError, authStack) {
      _toConsole('lecture du compte impossible', authError, authStack);
      _toConsole(feature, error, stackTrace);
      return;
    }
    if (uid == null) {
      _toConsole(feature, error, stackTrace);
      return;
    }
    final skipReason = _admit(feature, error, stackTrace);
    if (skipReason != null) {
      _skipped++;
      _toConsole(
        '$feature ($skipReason, $_skipped rapport(s) écarté(s))',
        error,
        null,
      );
      return;
    }
    final fields = ErrorReportFields.build(
      uid: uid,
      feature: feature,
      error: error,
      stackTrace: stackTrace,
      context: context,
      appVersion: appVersion,
      platform: kIsWeb ? 'web' : 'android',
    );
    try {
      unawaited(
        _firestore.collection('error_reports').doc().set(fields.data).catchError(
          (Object writeError, StackTrace writeStack) {
            // Écrire dans la collection en panne ne peut pas passer par ce même
            // service : la console est le dernier recours.
            _toConsole('écriture du rapport refusée', writeError, writeStack);
            _toConsole(feature, error, stackTrace);
          },
        ),
      );
    } catch (writeError, writeStack) {
      _toConsole('écriture du rapport impossible', writeError, writeStack);
      _toConsole(feature, error, stackTrace);
    }
  }

  /// `null` si le rapport peut être écrit (et le compte), sinon la raison du refus.
  String? _admit(String feature, Object error, StackTrace? stackTrace) {
    final fingerprint =
        '$feature|${error.runtimeType}|${_firstFrame(stackTrace)}';
    if (_written.contains(fingerprint)) return 'doublon';
    if (_sessionWrites >= maxPerSession) return 'plafond de la session';
    final now = _clock();
    _recentWrites.removeWhere(
      (t) => now.difference(t) >= const Duration(minutes: 1),
    );
    if (_recentWrites.length >= maxPerMinute) return 'plafond par minute';
    _written.add(fingerprint);
    _recentWrites.add(now);
    _sessionWrites++;
    return null;
  }

  static String _firstFrame(StackTrace? stackTrace) {
    if (stackTrace == null) return '';
    for (final line in stackTrace.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  void _toConsole(String feature, Object error, StackTrace? stackTrace) {
    debugPrint(
      '[ErrorReportService] $feature : '
      '${ErrorReportFields.sanitize(error.toString())}'
      '${stackTrace == null ? '' : '\n$stackTrace'}',
    );
  }
}
