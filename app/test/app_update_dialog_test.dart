import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/app_update_dialog.dart';
import 'package:kass_beer/core/presentation/verification_mise_a_jour.dart';
import 'package:kass_beer/core/services/app_installer.dart';
import 'package:kass_beer/core/services/app_update_service.dart';
import 'package:kass_beer/core/services/app_update_transport.dart';

import 'support/fakes.dart';

/// Fenêtre « Nouvelle version » (ADR-012), vérification au lancement depuis la
/// coquille, et canal `fr.kassbeer/updates` (P17).
void main() {
  const sha =
      'a3b1c2d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f9a';
  final manifesteJson = utf8.encode(
    jsonEncode({
      'version': '0.1.46',
      'build_number': 47,
      'file': 'app-release.apk',
      'size_bytes': 50540134,
      'sha256': sha,
      'built_at': '2026-11-14T10:00:00Z',
    }),
  );

  group('fenêtre', () {
    late RecordingErrorReportService errors;
    late FakeTransportMiseAJour transport;
    late FakeInstallateurApk installateur;
    late AppUpdateService service;
    final manifeste = ManifesteApk.lire(manifesteJson);

    setUp(() {
      errors = RecordingErrorReportService();
      transport = FakeTransportMiseAJour();
      installateur = FakeInstallateurApk();
      service = AppUpdateService(
        errorReportService: errors,
        installateur: installateur,
        buildInstalle: 46,
        versionInstallee: '0.1.45',
        transport: transport,
        estAndroid: () => true,
      );
    });

    Future<void> ouvrir(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppUpdateDialog(
                context,
                miseAJour: MiseAJourDisponible(
                  manifeste: manifeste,
                  versionInstallee: '0.1.45',
                ),
                service: service,
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('offre : versions, taille, Plus tard ferme', (tester) async {
      await ouvrir(tester);
      expect(find.text('Nouvelle version'), findsOneWidget);
      expect(
        find.text('Kass\'Beer 0.1.46 est disponible (vous avez 0.1.45).'),
        findsOneWidget,
      );
      expect(find.text('Téléchargement de 48,2\u00a0Mo.'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsOneWidget);
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle version'), findsNothing);
      expect(transport.telechargements, isEmpty);
    });

    testWidgets('autorisation absente : Ouvrir les réglages, puis relecture au '
        'retour', (tester) async {
      installateur.permis = false;
      transport.transfert = TransfertFini(50540134, sha);
      await ouvrir(tester);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      expect(
        find.text('Autorisez Kass\'Beer à installer des applications'),
        findsOneWidget,
      );
      expect(transport.telechargements, isEmpty);
      await tester.tap(find.text('Ouvrir les réglages'));
      await tester.pumpAndSettle();
      expect(installateur.ouverturesReglages, 1);
      installateur.permis = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(transport.telechargements, hasLength(1));
      expect(installateur.builds, [47]);
      expect(find.text('Nouvelle version'), findsNothing);
    });

    testWidgets('téléchargement : progression puis installateur, fenêtre '
        'fermée', (tester) async {
      transport.progressions = [1048576, 50540134];
      transport.transfert = TransfertFini(50540134, sha);
      await ouvrir(tester);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      expect(installateur.builds, [47]);
      expect(find.text('Nouvelle version'), findsNothing);
      expect(errors.reports, isEmpty);
    });

    testWidgets('coupure de réseau : échec, Réessayer et Plus tard, aucun '
        'rapport', (tester) async {
      transport.transfert = const TransfertInterrompu();
      await ouvrir(tester);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateDialog.echecReseau), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
      expect(errors.reports, isEmpty);
      transport.transfert = TransfertFini(50540134, sha);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(transport.telechargements, hasLength(2));
      expect(find.text('Nouvelle version'), findsNothing);
    });

    testWidgets('Annuler : échec « Téléchargement annulé. », aucun rapport', (
      tester,
    ) async {
      transport.progressions = [1000, 2000];
      transport.transfert = TransfertFini(50540134, sha);
      await ouvrir(tester);
      final attente = Completer<void>();
      transport.attente = attente;
      await tester.tap(find.text('Mettre à jour'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Annuler'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      attente.complete();
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateDialog.echecAnnule), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
      expect(transport.suppressions, hasLength(1));
      expect(errors.reports, isEmpty);
      expect(installateur.builds, isEmpty);
    });

    testWidgets('fichier faux : échec, rapport app_update_download', (
      tester,
    ) async {
      transport.transfert = TransfertFini(50540134, 'b${sha.substring(1)}');
      await ouvrir(tester);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateDialog.echecFichier), findsOneWidget);
      expect(errors.reports.single.feature, 'app_update_download');
    });

    testWidgets('paquet refusé par le Kotlin : échec et rapport', (
      tester,
    ) async {
      transport.transfert = TransfertFini(50540134, sha);
      installateur.installation = Installation.refusee;
      await ouvrir(tester);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateDialog.echecFichier), findsOneWidget);
      expect(errors.reports.single.context, contains('apk_invalid'));
    });

    testWidgets('installateur non ouvert : échec', (tester) async {
      transport.transfert = TransfertFini(50540134, sha);
      installateur.installation = Installation.impossible;
      await ouvrir(tester);
      await tester.tap(find.text('Mettre à jour'));
      await tester.pumpAndSettle();
      expect(find.text(AppUpdateDialog.echecInstallateur), findsOneWidget);
    });
  });

  group('vérification au lancement', () {
    test(
      'écran du jour et journées : aucune fenêtre ; préparation : permise',
      () {
        expect(routeSansMiseAJour('/brassins/b1/jour'), isTrue);
        expect(routeSansMiseAJour('/brassins/b1/jour/embouteillage'), isTrue);
        expect(routeSansMiseAJour('/brassins/b1/jour/j2/preparer'), isFalse);
        expect(routeSansMiseAJour('/brassins/b1/preparer'), isFalse);
        expect(routeSansMiseAJour('/brassins/b1'), isFalse);
        expect(routeSansMiseAJour('/recettes'), isFalse);
      },
    );

    Future<TestApp> connecter(
      WidgetTester tester, {
      bool android = true,
      ReponseManifeste? reponse,
    }) async {
      final app = TestApp(appVersion: '0.1.45')
        ..estAndroid = android
        ..buildInstalle = 46;
      app.transportMiseAJour.manifeste = reponse;
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('membre connecté, build publié supérieur : fenêtre, une fois '
        'par lancement', (tester) async {
      final app = await connecter(
        tester,
        reponse: ReponseManifeste(200, manifesteJson),
      );
      expect(find.text('Nouvelle version'), findsOneWidget);
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Brassins'));
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle version'), findsNothing);
      expect(app.transportMiseAJour.lectures, hasLength(1));
    });

    testWidgets('web : aucune lecture, aucune fenêtre', (tester) async {
      final app = await connecter(
        tester,
        android: false,
        reponse: ReponseManifeste(200, manifesteJson),
      );
      expect(find.text('Nouvelle version'), findsNothing);
      expect(app.transportMiseAJour.lectures, isEmpty);
    });

    testWidgets('échec de réseau : aucune fenêtre, aucun rapport', (
      tester,
    ) async {
      final app = await connecter(tester);
      expect(find.text('Nouvelle version'), findsNothing);
      expect(app.transportMiseAJour.lectures, hasLength(1));
      expect(
        app.errors.reports.where((r) => r.feature.startsWith('app_update')),
        isEmpty,
      );
    });
  });

  group('canal fr.kassbeer/updates', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel(kCanalMisesAJour);
    late RecordingErrorReportService errors;
    late InstallateurApkPlateforme canal;
    final appels = <MethodCall>[];

    setUp(() {
      errors = RecordingErrorReportService();
      canal = InstallateurApkPlateforme(errorReportService: errors);
      appels.clear();
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void repondre(Future<Object?> Function(MethodCall call) handler) =>
        messenger.setMockMethodCallHandler(channel, (call) {
          appels.add(call);
          return handler(call);
        });

    test('noms du canal, des méthodes et du code : ceux de MisesAJour.kt', () {
      expect(kCanalMisesAJour, 'fr.kassbeer/updates');
      expect(kMethodeDossier, 'updatesDir');
      expect(kMethodePeutInstaller, 'canRequestInstall');
      expect(kMethodeReglages, 'openInstallSettings');
      expect(kMethodeInstaller, 'installApk');
      expect(kCodeApkInvalide, 'apk_invalid');
      expect(kNomFichierMiseAJour, 'kass-beer-update.apk');
    });

    test('installApk : seul le build attendu part, aucun chemin', () async {
      repondre((_) async => true);
      expect(await canal.installer(47), Installation.ouverte);
      expect(appels.single.method, 'installApk');
      expect(appels.single.arguments, {'expectedBuild': 47});
      expect(errors.reports, isEmpty);
    });

    test('apk_invalid : refusée, sans rapport du canal', () async {
      repondre((_) async => throw PlatformException(code: 'apk_invalid'));
      expect(await canal.installer(47), Installation.refusee);
      expect(errors.reports, isEmpty);
    });

    test('autre erreur : rapport app_update_install sans le message', () async {
      repondre(
        (_) async => throw PlatformException(
          code: 'install_failed',
          message: '/data/user/0/fr.kassbeer/cache/updates',
        ),
      );
      expect(await canal.installer(47), Installation.impossible);
      final r = errors.reports.single;
      expect(r.feature, 'app_update_install');
      expect('${r.error} ${r.context}', isNot(contains('/data')));
      expect(r.context, contains('install_failed'));
    });

    test('updatesDir, canRequestInstall, openInstallSettings', () async {
      repondre(
        (call) async => switch (call.method) {
          'updatesDir' => '/cache/updates',
          _ => true,
        },
      );
      expect(await canal.dossierMisesAJour(), '/cache/updates');
      expect(await canal.peutInstaller(), isTrue);
      expect(await canal.ouvrirReglages(), isTrue);
      expect(appels.map((c) => c.method), [
        'updatesDir',
        'canRequestInstall',
        'openInstallSettings',
      ]);
    });

    test('updatesDir en échec : null et rapport', () async {
      repondre((_) async => throw PlatformException(code: 'dir_unavailable'));
      expect(await canal.dossierMisesAJour(), isNull);
      expect(errors.reports.single.feature, 'app_update_install');
    });

    test('canal absent : faux et rapport', () async {
      expect(await canal.peutInstaller(), isFalse);
      expect(errors.reports.single.feature, 'app_update_install');
    });
  });
}
