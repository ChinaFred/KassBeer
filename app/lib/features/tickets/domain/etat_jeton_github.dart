import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Délai avant l'échéance du jeton à partir duquel Admin l'annonce.
const kTokenExpiryWarning = Duration(days: 14);

/// Document `ticket_status/github`, écrit par le serveur, lu par
/// l'administrateur seul (P23).
@immutable
class EtatJetonGithub {
  const EtatJetonGithub({this.tokenInvalidSince, this.tokenExpiresAt});

  /// Jeton refusé ou expiré depuis cette date ; `null` s'il est accepté.
  final DateTime? tokenInvalidSince;

  /// Échéance lue dans l'en-tête `github-authentication-token-expiration` ;
  /// `null` si GitHub ne l'a pas donnée.
  final DateTime? tokenExpiresAt;

  /// Lève [DocumentIllisible] pour un champ mal typé.
  factory EtatJetonGithub.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    return EtatJetonGithub(
      tokenInvalidSince: read.date('token_invalid_since'),
      tokenExpiresAt: read.date('token_expires_at'),
    );
  }
}
