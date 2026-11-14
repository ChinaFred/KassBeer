import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/bandeau_liste_perimee.dart';
import 'package:kass_beer/core/presentation/etats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/admin/data/error_reports_repository.dart';
import 'package:kass_beer/features/admin/domain/error_report.dart';
import 'package:kass_beer/features/admin/presentation/admin_screen.dart';
import 'package:kass_beer/features/admin/presentation/error_reports_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/fakes.dart';

ErrorReport _rapport(
  int n, {
  String? platform = 'android',
  String error = 'StateError: panne',
}) => ErrorReport(
  id: 'er-$n',
  error: '$error $n\n#0 suite du message',
  createdAt: DateTime(2026, 11, 14, 10, 30),
  uid: 'uid-$n',
  feature: 'recipes.watch',
  context: 'première page',
  stackTrace: '#0 main (file.dart:1)',
  appVersion: '0.1.39+40',
  platform: PlateformeRapport.fromValue(platform),
);

Future<TestApp> _ouvrir(
  WidgetTester tester, {
  List<ErrorReport> rapports = const [],
  void Function(TestApp app)? avant,
  double width = 400,
}) async {
  final app = TestApp();
  app.errorReports.rapports.addAll(rapports);
  avant?.call(app);
  await app.pump(tester, width: width);
  app.signIn(adminUser, member: adminMember);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(AppRoutes.adminErrorReports);
  await tester.pumpAndSettle();
  return app;
}

void main() {
  group('ErrorReport', () {
    test('lecture d\'un document : champs, plateforme, première ligne', () {
      final r = ErrorReport.fromFirestore('er-1', {
        'uid': 'u1',
        'feature': 'brew_day',
        'error': '\n  StateError: boom  \nligne 2',
        'context': 'step=mash-1',
        'stack_trace': '#0 main',
        'app_version': '0.1.39+40',
        'platform': 'web',
        'created_at': Timestamp.fromDate(DateTime(2026, 11, 14, 9, 5)),
      });
      expect(r.premiereLigne, 'StateError: boom');
      expect(r.libellePlateforme, 'Web');
      expect(r.resume, '14 nov. 09:05 · brew_day · v0.1.39+40');
      expect(r.texteCopie, contains('Pile d\'appels\n#0 main'));
      expect(r.texteCopie, contains('Compte\nu1'));
    });

    test('champs absents : omis du résumé, plateforme inconnue', () {
      final r = ErrorReport.fromFirestore('er-2', {
        'uid': 'u1',
        'feature': 'x',
        'error': '',
        'platform': 'ios',
      });
      expect(r.premiereLigne, ErrorReport.erreurSansMessage);
      expect(r.resume, 'x');
      expect(r.platform, isNull);
      expect(r.libellePlateforme, ErrorReport.plateformeInconnue);
      expect(r.texteCopie, isNot(contains('Contexte')));
      expect(r.texteCopie, isNot(contains('Pile d\'appels')));
    });
  });

  group('FirestoreErrorReportsRepository', () {
    late FakeFirebaseFirestore firestore;
    late RecordingErrorReportService errors;
    late FirestoreErrorReportsRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      errors = RecordingErrorReportService();
      repository = FirestoreErrorReportsRepository(
        errorReportService: errors,
        firestore: firestore,
      );
    });

    test('pages de 50, du plus récent au plus ancien, suite, fin', () async {
      final debut = DateTime.utc(2026, 11, 1);
      for (var i = 1; i <= 120; i++) {
        await firestore.doc('error_reports/er-$i').set({
          'uid': 'u',
          'feature': 'f',
          'error': 'e$i',
          'created_at': Timestamp.fromDate(debut.add(Duration(minutes: i))),
        });
      }
      final first = await repository.page();
      expect(first.rapports, hasLength(kTaillePageRapports));
      expect(first.rapports.first.id, 'er-120');
      expect(first.suite, isNotNull);
      expect(first.fromCache, isFalse);
      final second = await repository.page(apres: first.suite);
      expect(second.rapports.first.id, 'er-70');
      final third = await repository.page(apres: second.suite);
      expect(third.rapports, hasLength(20));
      expect(third.rapports.last.id, 'er-1');
      expect(third.suite, isNull);
      expect(errors.reports, isEmpty);
    });

    test(
      'panne de lecture : rapportée sans texte de rapport, relancée',
      () async {
        final enPanne = FirestoreErrorReportsRepository(
          errorReportService: errors,
          firestore: _FirestoreEnPanne(),
        );
        await expectLater(enPanne.page(), throwsA(isA<FirebaseException>()));
        expect(errors.reports.single.feature, 'admin.error_reports');
        expect(errors.reports.single.context, 'première page');
      },
    );
  });

  group('Admin › Rapports d\'erreur', () {
    testWidgets('tuile de l\'administration, après « Import »', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.admin);
      await tester.pumpAndSettle();
      final import = tester.getTopLeft(find.text('Import'));
      final rapports = tester.getTopLeft(find.text(ErrorReportsScreen.titre));
      expect(rapports.dy, greaterThan(import.dy));
      expect(find.text(ErrorReportsScreen.sousTitre), findsOneWidget);
      await tester.tap(find.text(ErrorReportsScreen.titre));
      await tester.pumpAndSettle();
      expect(find.text(ErrorReportsScreen.vide), findsOneWidget);
      expect(find.byType(AdminScreen), findsNothing);
    });

    testWidgets('un brasseur n\'ouvre pas l\'écran', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminErrorReports);
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
      expect(app.errorReports.demandes, isEmpty);
    });

    testWidgets(
      'liste : compte, ligne repliée, plateformes, aucune suppression',
      (tester) async {
        await _ouvrir(
          tester,
          rapports: [
            _rapport(1),
            _rapport(2, platform: 'web'),
            _rapport(3, platform: null),
          ],
        );
        expect(find.text('3 rapports affichés'), findsOneWidget);
        expect(find.text('StateError: panne 1'), findsOneWidget);
        expect(find.text('#0 suite du message'), findsNothing);
        expect(
          find.text('14 nov. 10:30 · recipes.watch · v0.1.39+40'),
          findsNWidgets(3),
        );
        expect(find.text('Android'), findsOneWidget);
        expect(find.text('Web'), findsOneWidget);
        expect(find.text(ErrorReport.plateformeInconnue), findsOneWidget);
        expect(find.text(ErrorReportsScreen.fin), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        expect(find.byIcon(Icons.delete), findsNothing);
        expect(find.textContaining('Supprimer'), findsNothing);
        final refresh = tester.getSize(find.byTooltip('Actualiser'));
        expect(refresh.width, greaterThanOrEqualTo(48));
        expect(refresh.height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets('un rapport : singulier', (tester) async {
      await _ouvrir(tester, rapports: [_rapport(1)]);
      expect(find.text('1 rapport affiché'), findsOneWidget);
    });

    testWidgets('déplié : sections, copie du rapport', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _ouvrir(tester, rapports: [_rapport(1)]);
      await tester.tap(find.text('StateError: panne 1'));
      await tester.pumpAndSettle();
      for (final titre in ['Erreur', 'Contexte', 'Pile d\'appels', 'Compte']) {
        expect(find.text(titre), findsOneWidget, reason: titre);
      }
      expect(find.text('uid-1'), findsOneWidget);
      expect(find.byType(SelectableText), findsNWidgets(4));
      final bouton = find.ancestor(
        of: find.text(ErrorReportsScreen.copier),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.getSize(bouton).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text(ErrorReportsScreen.copier));
      await tester.pump();
      expect(find.text(ErrorReportsScreen.copie), findsOneWidget);
      expect(copied, startsWith('Rapport d\'erreur er-1\n'));
      expect(copied, contains('Android'));
      expect(copied, contains('Compte\nuid-1'));
    });

    testWidgets('pagination : « Charger la suite », puis fin', (tester) async {
      final app = await _ouvrir(
        tester,
        rapports: [for (var i = 1; i <= 60; i++) _rapport(i)],
      );
      expect(find.text('50 rapports affichés'), findsOneWidget);
      expect(find.text(ErrorReportsScreen.fin), findsNothing);
      await tester.scrollUntilVisible(
        find.text(ErrorReportsScreen.chargerSuite),
        500,
      );
      await tester.tap(find.text(ErrorReportsScreen.chargerSuite));
      await tester.pumpAndSettle();
      expect(app.errorReports.demandes, hasLength(2));
      expect(app.errorReports.demandes.last?.valeur, 50);
      await tester.scrollUntilVisible(find.text(ErrorReportsScreen.fin), 500);
      expect(find.text(ErrorReportsScreen.fin), findsOneWidget);
      await tester.scrollUntilVisible(find.text('60 rapports affichés'), -2000);
      expect(find.text('60 rapports affichés'), findsOneWidget);
    });

    testWidgets('vide', (tester) async {
      await _ouvrir(tester);
      expect(find.text(ErrorReportsScreen.vide), findsOneWidget);
      expect(find.byIcon(Icons.task_alt), findsOneWidget);
    });

    testWidgets('panne de la première page, puis « Réessayer »', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        rapports: [_rapport(1)],
        avant: (app) => app.errorReports.pageError = StateError('panne'),
      );
      expect(find.text(ErrorReportsScreen.erreurLecture), findsOneWidget);
      expect(find.byType(EtatErreur), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text('StateError: panne 1'), findsOneWidget);
      expect(app.errorReports.demandes, hasLength(2));
    });

    testWidgets('panne de la suite : liste gardée sous le bandeau', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        rapports: [for (var i = 1; i <= 60; i++) _rapport(i)],
      );
      app.errorReports.pageError = StateError('panne');
      await tester.scrollUntilVisible(
        find.text(ErrorReportsScreen.chargerSuite),
        500,
      );
      await tester.tap(find.text(ErrorReportsScreen.chargerSuite));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(ErrorReportsScreen.erreurListe),
        -2000,
      );
      expect(find.text('50 rapports affichés'), findsOneWidget);
      expect(find.text('StateError: panne 1'), findsOneWidget);
      // « Réessayer » rejoue la suite.
      await tester.tap(
        find.descendant(
          of: find.byType(BandeauListePerimee),
          matching: find.text('Réessayer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.errorReports.demandes.last?.valeur, 50);
      expect(find.text('60 rapports affichés'), findsOneWidget);
      expect(find.text(ErrorReportsScreen.erreurListe), findsNothing);
    });

    testWidgets('« Actualiser » relit la première page', (tester) async {
      final app = await _ouvrir(tester, rapports: [_rapport(1)]);
      app.errorReports.rapports.insert(0, _rapport(9));
      await tester.tap(find.byTooltip('Actualiser'));
      await tester.pumpAndSettle();
      expect(app.errorReports.demandes, [null, null]);
      expect(find.text('2 rapports affichés'), findsOneWidget);
    });

    testWidgets('« Actualiser » en cours : indicateur, suite en attente', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        rapports: [for (var i = 1; i <= 60; i++) _rapport(i)],
      );
      final attente = Completer<void>();
      app.errorReports.attente = attente;
      await tester.tap(find.byTooltip('Actualiser'));
      await tester.pump();
      expect(find.byTooltip('Actualiser'), findsNothing);
      final indicateur = find.bySemanticsLabel(
        ErrorReportsScreen.lectureEnCours,
      );
      expect(indicateur, findsOneWidget);
      final taille = tester.getSize(indicateur);
      expect(taille.width, greaterThanOrEqualTo(48));
      expect(taille.height, greaterThanOrEqualTo(48));
      await tester.scrollUntilVisible(
        find.text(ErrorReportsScreen.chargerSuite),
        500,
      );
      final suite = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(ErrorReportsScreen.chargerSuite),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(suite.onPressed, isNull);
      expect(find.byType(IndicateurBouton), findsNothing);
      app.errorReports.attente = null;
      attente.complete();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byTooltip('Actualiser'), -2000);
      expect(find.byTooltip('Actualiser'), findsOneWidget);
    });

    testWidgets('« Actualiser » en échec : liste gardée sous le bandeau', (
      tester,
    ) async {
      final app = await _ouvrir(tester, rapports: [_rapport(1)]);
      app.errorReports.pageError = StateError('panne');
      await tester.tap(find.byTooltip('Actualiser'));
      await tester.pumpAndSettle();
      expect(find.text(ErrorReportsScreen.erreurListe), findsOneWidget);
      expect(find.text('StateError: panne 1'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(BandeauListePerimee),
          matching: find.text('Réessayer'),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.errorReports.demandes, [null, null, null]);
      expect(find.text(ErrorReportsScreen.erreurListe), findsNothing);
    });

    testWidgets(
      '« Réessayer » du bandeau : un seul indicateur, dans le bandeau',
      (tester) async {
        final app = await _ouvrir(tester, rapports: [_rapport(1)]);
        app.errorReports.pageError = StateError('panne');
        await tester.tap(find.byTooltip('Actualiser'));
        await tester.pumpAndSettle();
        final attente = Completer<void>();
        app.errorReports.attente = attente;
        await tester.tap(
          find.descendant(
            of: find.byType(BandeauListePerimee),
            matching: find.text('Réessayer'),
          ),
        );
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(BandeauListePerimee),
            matching: find.byType(IndicateurBouton),
          ),
          findsOneWidget,
        );
        // L'en-tête garde son bouton, désactivé, sans indicateur.
        final actualiser = tester.widget<IconButton>(
          find.ancestor(
            of: find.byTooltip('Actualiser'),
            matching: find.byType(IconButton),
          ),
        );
        expect(actualiser.onPressed, isNull);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        app.errorReports.attente = null;
        attente.complete();
        await tester.pumpAndSettle();
        expect(find.text(ErrorReportsScreen.erreurListe), findsNothing);
      },
    );

    testWidgets(
      '« Actualiser » sous un bandeau de panne : indicateur en tête seul',
      (tester) async {
        final app = await _ouvrir(tester, rapports: [_rapport(1)]);
        app.errorReports.pageError = StateError('panne');
        await tester.tap(find.byTooltip('Actualiser'));
        await tester.pumpAndSettle();
        final attente = Completer<void>();
        app.errorReports.attente = attente;
        await tester.tap(find.byTooltip('Actualiser'));
        await tester.pump();
        expect(
          find.bySemanticsLabel(ErrorReportsScreen.lectureEnCours),
          findsOneWidget,
        );
        expect(find.byType(IndicateurBouton), findsNothing);
        final reessayer = tester.widget<TextButton>(
          find.descendant(
            of: find.byType(BandeauListePerimee),
            matching: find.byType(TextButton),
          ),
        );
        expect(reessayer.onPressed, isNull);
        app.errorReports.attente = null;
        attente.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('liste vide, « Actualiser » en échec : panne seule', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        avant: (app) => app.errorReports.fromCache = true,
      );
      app.errorReports.pageError = StateError('panne');
      await tester.tap(find.byTooltip('Actualiser'));
      await tester.pumpAndSettle();
      expect(find.byType(EtatErreur), findsOneWidget);
      expect(find.text(ErrorReportsScreen.erreurLecture), findsOneWidget);
      expect(find.byType(BandeauListePerimee), findsNothing);
      expect(find.byType(EtatVide), findsNothing);
      expect(find.text('Réessayer'), findsOneWidget);
      final attente = app.errorReports.attente = Completer<void>();
      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      // Pendant la relecture : la panne reste, en attente, sans état vide.
      expect(find.byType(EtatErreur), findsOneWidget);
      expect(find.text(ErrorReportsScreen.lectureEnCours), findsOneWidget);
      expect(find.byType(EtatVide), findsNothing);
      attente.complete();
      app.errorReports.attente = null;
      await tester.pumpAndSettle();
      expect(app.errorReports.demandes, [null, null, null]);
      expect(find.byType(EtatErreur), findsNothing);
      expect(find.text(ErrorReportsScreen.videHorsLigne), findsOneWidget);
    });

    testWidgets('hors ligne sans rapport : état vide seul, « Réessayer »', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        avant: (app) => app.errorReports.fromCache = true,
      );
      expect(find.text(ErrorReportsScreen.videHorsLigne), findsOneWidget);
      expect(find.text(ErrorReportsScreen.horsLigne), findsNothing);
      expect(find.byType(BandeauListePerimee), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Réessayer'));
      await tester.pumpAndSettle();
      expect(app.errorReports.demandes, [null, null]);
    });

    testWidgets('hors ligne sans rapport : attente dans « Réessayer » seul', (
      tester,
    ) async {
      final app = await _ouvrir(
        tester,
        avant: (app) => app.errorReports.fromCache = true,
      );
      final attente = Completer<void>();
      app.errorReports.attente = attente;
      await tester.tap(find.widgetWithText(TextButton, 'Réessayer'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(EtatVide),
          matching: find.byType(IndicateurBouton),
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Actualiser'), findsOneWidget);
      app.errorReports.attente = null;
      attente.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('tirer pour actualiser : seul l\'indicateur du geste', (
      tester,
    ) async {
      final app = await _ouvrir(tester, rapports: [_rapport(1)]);
      final attente = Completer<void>();
      app.errorReports.attente = attente;
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(app.errorReports.demandes, [null, null]);
      expect(find.byTooltip('Actualiser'), findsOneWidget);
      expect(
        find.bySemanticsLabel(ErrorReportsScreen.lectureEnCours),
        findsNothing,
      );
      expect(find.byType(IndicateurBouton), findsNothing);
      app.errorReports.attente = null;
      attente.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('hors ligne : bandeau au-dessus de la liste', (tester) async {
      await _ouvrir(
        tester,
        rapports: [_rapport(1)],
        avant: (app) => app.errorReports.fromCache = true,
      );
      expect(find.text(ErrorReportsScreen.horsLigne), findsOneWidget);
      expect(find.text('StateError: panne 1'), findsOneWidget);
    });

    testWidgets('texte à 200 % : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _ouvrir(
        tester,
        rapports: [_rapport(1), _rapport(2, platform: null)],
        width: 360,
      );
      expect(find.text(ErrorReport.plateformeInconnue), findsOneWidget);
      await tester.tap(find.text('StateError: panne 1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(ErrorReportsScreen.copier), findsOneWidget);
    });

    testWidgets('ligne large : étiquette à droite du titre', (tester) async {
      await _ouvrir(tester, rapports: [_rapport(1)], width: 1200);
      final titre = tester.getRect(find.text('StateError: panne 1'));
      final etiquette = tester.getRect(find.text('Android'));
      expect(etiquette.left, greaterThan(titre.right));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Firestore de test dont toute lecture de collection échoue.
class _FirestoreEnPanne extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
}
