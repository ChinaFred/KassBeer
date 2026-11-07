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

  /// Nom du compte tel que le porte le jeton d'identité (`claims['name']`), ou
  /// `null` s'il est absent, vide ou plus long que [kOwnerNameMaxLength]. C'est la
  /// valeur que `firestore.rules` compare à `owner_name` (`request.auth.token.name`) ;
  /// `displayName` peut en différer jusqu'au rafraîchissement du jeton.
  ///
  /// Lit le jeton en cache s'il est valide. Hors ligne avec un jeton expiré, la
  /// lecture échoue ou dépasse [kTokenNameWait] : l'erreur est rapportée et le nom
  /// rendu `null`. L'enregistrement part alors sans `owner_name` (l'écran affiche
  /// « Autre brasseur ») au lieu d'attendre le réseau.
  Future<String?> currentTokenName();
}

/// Longueur maximale de `owner_name` (`firestore.rules`, 1 à 80 caractères).
const kOwnerNameMaxLength = 80;

/// Attente maximale de la lecture du jeton avant un enregistrement : au-delà,
/// l'enregistrement part sans `owner_name` plutôt que de rester bloqué hors ligne.
const kTokenNameWait = Duration(seconds: 3);

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
  static const _cancelCodes = {
    'popup-closed-by-user',
    'cancelled-popup-request',
    'web-context-canceled',
  };

  @override
  Stream<SessionUser?> authStateChanges() => _auth
      .authStateChanges()
      .map(
        (user) => user == null
            ? null
            : SessionUser(
                uid: user.uid,
                email: user.email,
                displayName: user.displayName,
                photoUrl: user.photoURL,
              ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'auth.state_changes',
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran Erreur s'affiche.
        Error.throwWithStackTrace(error, stackTrace);
      });

  @override
  Future<SignInOutcome> signInWithGoogle() async {
    try {
      if (_isWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await _auth.signInWithPopup(provider);
        return SignInOutcome.signedIn;
      }
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google n\'a pas rendu de jeton d\'identité');
      }
      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      return SignInOutcome.signedIn;
    } on FirebaseAuthException catch (error, stackTrace) {
      if (_cancelCodes.contains(error.code)) return SignInOutcome.cancelled;
      _errors.reportError(
        feature: 'auth.sign_in',
        error: error,
        stackTrace: stackTrace,
        context: 'firebase ${error.code}',
      );
      throw SignInFailure(
        network: error.code == 'network-request-failed',
        cause: error,
      );
    } on GoogleSignInException catch (error, stackTrace) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return SignInOutcome.cancelled;
      }
      _errors.reportError(
        feature: 'auth.sign_in',
        error: error,
        stackTrace: stackTrace,
        context: 'google_sign_in ${error.code.name}',
      );
      throw SignInFailure(network: false, cause: error);
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'auth.sign_in',
        error: error,
        stackTrace: stackTrace,
      );
      throw SignInFailure(network: false, cause: error);
    }
  }

  @override
  Future<String?> currentTokenName() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final token = await user.getIdTokenResult().timeout(kTokenNameWait);
      final name = token.claims?['name'];
      if (name is! String) return null;
      // Les règles comparent la valeur exacte du jeton : un nom entouré d'espaces
      // n'est pas réécrit, il est écrit tel quel ou pas du tout. Au-delà de
      // kOwnerNameMaxLength caractères, les règles refuseraient toute écriture de
      // ce compte : le nom n'est pas écrit.
      if (name.trim().isEmpty || name.runes.length > kOwnerNameMaxLength) {
        return null;
      }
      return name;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'auth.token_name',
        error: error,
        stackTrace: stackTrace,
        context: 'lecture du jeton avant un enregistrement',
      );
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    // La session Google d'Android se ferme aussi : sans quoi la connexion suivante
    // reprendrait le même compte sans proposer le choix.
    await Future.wait([_auth.signOut(), if (!_isWeb) _googleSignIn.signOut()]);
  }
}
