import 'package:flutter/foundation.dart';

/// Compte Google connecté, tel que Firebase Auth le décrit.
@immutable
class SessionUser {
  const SessionUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String uid;

  /// Adresse du compte Google, telle que Google la rend. `null` si le compte n'en
  /// a pas : il n'ouvre alors rien.
  final String? email;
  final String? displayName;
  final String? photoUrl;

  /// Identifiant de `members/` : l'adresse en minuscules, comme dans les règles.
  String? get memberKey => email?.trim().toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is SessionUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(uid, email, displayName, photoUrl);
}

/// Issue d'une demande de connexion qui n'a pas levé d'erreur.
enum SignInOutcome {
  /// Le compte est connecté ; l'état de session suit.
  signedIn,

  /// La fenêtre Google a été fermée : retour sans message.
  cancelled,
}

/// Échec de connexion, déjà classé pour l'écran.
class SignInFailure implements Exception {
  const SignInFailure({required this.network, required this.cause});

  /// Vrai quand la cause est le réseau.
  final bool network;
  final Object cause;

  @override
  String toString() => 'SignInFailure(network: $network, cause: $cause)';
}
