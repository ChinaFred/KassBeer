import 'package:firebase_core/firebase_core.dart';

/// Configuration Firebase lue à la compilation.
///
/// Les valeurs viennent de `--dart-define-from-file=firebase.env.json` (fichier ignoré
/// par Git ; modèle : `firebase.env.example.json`). Aucune valeur n'est écrite dans le
/// code : sans configuration complète pour la plateforme, l'application affiche
/// « Configuration Firebase absente » au lieu de démarrer avec des valeurs factices.
class FirebaseEnv {
  const FirebaseEnv({
    required this.projectId,
    required this.messagingSenderId,
    required this.webApiKey,
    required this.webAppId,
    required this.authDomain,
    required this.androidApiKey,
    required this.androidAppId,
    required this.googleServerClientId,
  });

  /// Valeurs passées par `--dart-define` ; une clé absente vaut une chaîne vide.
  factory FirebaseEnv.fromEnvironment() => const FirebaseEnv(
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    webApiKey: String.fromEnvironment('FIREBASE_WEB_API_KEY'),
    webAppId: String.fromEnvironment('FIREBASE_WEB_APP_ID'),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    androidApiKey: String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
    androidAppId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
    googleServerClientId: String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
  );

  final String projectId;
  final String messagingSenderId;
  final String webApiKey;
  final String webAppId;
  final String authDomain;
  final String androidApiKey;
  final String androidAppId;

  /// Identifiant OAuth du client web du projet. `google_sign_in` 7 l'exige sur Android
  /// pour rendre un jeton d'identité que Firebase Auth accepte.
  final String googleServerClientId;

  /// Noms des clés vides pour la plateforme [web] (web) ou Android.
  List<String> missingKeys({required bool web}) {
    final required = <String, String>{
      'FIREBASE_PROJECT_ID': projectId,
      'FIREBASE_MESSAGING_SENDER_ID': messagingSenderId,
      if (web) ...{
        'FIREBASE_WEB_API_KEY': webApiKey,
        'FIREBASE_WEB_APP_ID': webAppId,
        'FIREBASE_AUTH_DOMAIN': authDomain,
      } else ...{
        'FIREBASE_ANDROID_API_KEY': androidApiKey,
        'FIREBASE_ANDROID_APP_ID': androidAppId,
        'GOOGLE_SERVER_CLIENT_ID': googleServerClientId,
      },
    };
    return [
      for (final entry in required.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];
  }

  /// Bucket Cloud Storage des captures de tickets (ADR-008, T6) : le bucket par défaut
  /// d'un projet créé depuis 2024 porte le nom `<projet>.firebasestorage.app`. Il est
  /// nommé ici parce que Firebase ne le déclare pas comme bucket par défaut du projet
  /// `kassbeer` (déploiement de la v0.1.41) : sans `storageBucket`, `FirebaseStorage`
  /// n'a aucun bucket.
  String get storageBucket => '$projectId.firebasestorage.app';

  /// Options de la plateforme [web] (web) ou Android. À n'appeler que si
  /// [missingKeys] est vide.
  FirebaseOptions options({required bool web}) {
    final missing = missingKeys(web: web);
    if (missing.isNotEmpty) {
      throw StateError(
        'Configuration Firebase incomplète : ${missing.join(', ')}',
      );
    }
    return web
        ? FirebaseOptions(
            apiKey: webApiKey,
            appId: webAppId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
            authDomain: authDomain,
            storageBucket: storageBucket,
          )
        : FirebaseOptions(
            apiKey: androidApiKey,
            appId: androidAppId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
            storageBucket: storageBucket,
          );
  }
}
