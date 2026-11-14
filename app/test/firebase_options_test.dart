import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/app.dart';
import 'package:kass_beer/firebase_options.dart';

const _empty = FirebaseEnv(
  projectId: '',
  messagingSenderId: '',
  webApiKey: '',
  webAppId: '',
  authDomain: '',
  androidApiKey: '',
  androidAppId: '',
  googleServerClientId: '',
);

void main() {
  test('sans valeurs : toutes les clés de la plateforme manquent', () {
    expect(_empty.missingKeys(web: true), [
      'FIREBASE_PROJECT_ID',
      'FIREBASE_MESSAGING_SENDER_ID',
      'FIREBASE_WEB_API_KEY',
      'FIREBASE_WEB_APP_ID',
      'FIREBASE_AUTH_DOMAIN',
    ]);
    expect(_empty.missingKeys(web: false), [
      'FIREBASE_PROJECT_ID',
      'FIREBASE_MESSAGING_SENDER_ID',
      'FIREBASE_ANDROID_API_KEY',
      'FIREBASE_ANDROID_APP_ID',
      'GOOGLE_SERVER_CLIENT_ID',
    ]);
    expect(() => _empty.options(web: true), throwsStateError);
  });

  test('bucket des captures nommé sur les deux plateformes', () {
    const env = FirebaseEnv(
      projectId: 'demo-kassbeer',
      messagingSenderId: '1',
      webApiKey: 'k',
      webAppId: 'w',
      authDomain: 'demo-kassbeer.firebaseapp.com',
      androidApiKey: 'a',
      androidAppId: 'b',
      googleServerClientId: 'c',
    );
    expect(
      env.options(web: true).storageBucket,
      'demo-kassbeer.firebasestorage.app',
    );
    expect(
      env.options(web: false).storageBucket,
      'demo-kassbeer.firebasestorage.app',
    );
  });

  test('les tests compilent sans --dart-define : configuration absente', () {
    expect(FirebaseEnv.fromEnvironment().missingKeys(web: true), isNotEmpty);
  });

  testWidgets('écran « Configuration Firebase absente » et clés manquantes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MissingConfigurationApp(missingKeys: _empty.missingKeys(web: true)),
    );
    expect(find.text('Configuration Firebase absente'), findsOneWidget);
    expect(find.text('FIREBASE_WEB_API_KEY'), findsOneWidget);
  });
}
