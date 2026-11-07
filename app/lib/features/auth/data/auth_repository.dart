import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/services/error_report_service.dart';
import '../domain/session_user.dart';

/// Session Google de l'application. Les écrans passent par cette interface ; les
/// tests la remplacent par un double sans Firebase.
abstract class AuthRepository {
  /// Compte connecté, à chaque changement ; `null` sans session.
  Stream<SessionUser?> authStateChanges();

  /// Connexion Google : fenêtre surgissante sur le web, `google_sign_in` 7 sur Android.
  ///
  /// Rend [SignInOutcome.cancelled] quand la fenêtre est fermée. Lève [SignInFailure]
  /// pour toute autre erreur, déjà rapportée.
  Future<SignInOutcome> signInWithGoogle();

  Future<void> signOut();
}

/// [AuthRepository] sur Firebase Auth.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required ErrorReportService errorReportService,
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    bool? isWeb,
  }) : _errors = errorReportService,
       _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _isWeb = isWeb ?? kIsWeb;

  final ErrorReportService _errors;
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final bool _isWeb;

  /// Codes Firebase Auth d'une fenêtre Google fermée par l'utilisateur.
  static const _cancelCodes = {'popup-closed-by-user', 'cancelled-popup-request', 'web-context-canceled'};

  @override
  Stream<SessionUser?> authStateChanges() => _auth.authStateChanges().map(
    (user) => user == null
        ? null
        : SessionUser(
            uid: user.uid,
            email: user.email,
            displayName: user.displayName,
            photoUrl: user.photoURL,
          ),
  );

  @override
  Future<SignInOutcome> signInWithGoogle() async {
    try {
      if (_isWeb) {
        final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
        await _auth.signInWithPopup(provider);
        return SignInOutcome.signedIn;
      }
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google n\'a pas rendu de jeton d\'identité');
      }
      await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return SignInOutcome.signedIn;
    } on FirebaseAuthException catch (error, stackTrace) {
      if (_cancelCodes.contains(error.code)) return SignInOutcome.cancelled;
      _errors.reportError(
        feature: 'auth.sign_in',
        error: error,
        stackTrace: stackTrace,
        context: 'firebase ${error.code}',
      );
      throw SignInFailure(network: error.code == 'network-request-failed', cause: error);
    } on GoogleSignInException catch (error, stackTrace) {
      if (error.code == GoogleSignInExceptionCode.canceled) return SignInOutcome.cancelled;
      _errors.reportError(
        feature: 'auth.sign_in',
        error: error,
        stackTrace: stackTrace,
        context: 'google_sign_in ${error.code.name}',
      );
      throw SignInFailure(network: false, cause: error);
    } catch (error, stackTrace) {
      _errors.reportError(feature: 'auth.sign_in', error: error, stackTrace: stackTrace);
      throw SignInFailure(network: false, cause: error);
    }
  }

  @override
  Future<void> signOut() async {
    // La session Google d'Android se ferme aussi : sans quoi la connexion suivante
    // reprendrait le même compte sans proposer le choix.
    await Future.wait([_auth.signOut(), if (!_isWeb) _googleSignIn.signOut()]);
  }
}
