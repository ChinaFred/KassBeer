import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/core/preferences/preferences_appareil.dart';
import 'package:kass_beer/core/preferences/theme_mode_provider.dart';
import 'package:kass_beer/core/presentation/preferences_screen.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

ThemeMode modeAffiche(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

Future<TestApp> ouvrirPreferences(WidgetTester tester) async {
  final app = TestApp();
  await app.pump(tester);
  app.signIn(brewerUser, member: brewerMember);
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Mon compte'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Préférences'));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(kCanalPreferences);

  group('canal fr.kassbeer/prefs', () {
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('nom du canal, des méthodes et des valeurs : ceux de '
        'PreferencesAppareil.kt', () {
      expect(kCanalPreferences, 'fr.kassbeer/prefs');
      expect(kMethodeLireTheme, 'getTheme');
      expect(kMethodeEcrireTheme, 'setTheme');
      expect(kArgumentValeur, 'value');
      expect(kValeursTheme.values, ['light', 'dark', 'system']);
    });

    test('lecture et écriture passent par le canal', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'getTheme' ? 'dark' : null;
      });
      final preferences = PreferencesAppareilPlateforme();
      expect(await preferences.lireValeurTheme(), 'dark');
      await preferences.ecrireTheme(ThemeMode.light);
      expect(calls.map((c) => c.method), ['getTheme', 'setTheme']);
      expect(calls.last.arguments, {'value': 'light'});
    });

    test('trois écritures rapides : un appel en vol au plus, la dernière '
        'valeur écrite en dernier', () async {
      final ecrites = <String>[];
      final reponses = <Completer<void>>[];
      var enVol = 0;
      var maxEnVol = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        enVol++;
        maxEnVol = enVol > maxEnVol ? enVol : maxEnVol;
        final reponse = Completer<void>();
        reponses.add(reponse);
        await reponse.future;
        ecrites.add((call.arguments as Map)['value'] as String);
        enVol--;
        return null;
      });
      final preferences = PreferencesAppareilPlateforme();
      final premier = preferences.ecrireTheme(ThemeMode.dark);
      final deuxieme = preferences.ecrireTheme(ThemeMode.light);
      final troisieme = preferences.ecrireTheme(ThemeMode.system);
      await pumpEventQueue();
      expect(reponses.length, 1);
      // Le deuxième choix est remplacé par le troisième avant d'être envoyé.
      await deuxieme;

      reponses[0].complete();
      await premier;
      await pumpEventQueue();
      expect(reponses.length, 2);
      reponses[1].complete();
      await troisieme;

      expect(maxEnVol, 1);
      expect(ecrites, ['dark', 'system']);
    });

    test(
      'échec de la première écriture : le dernier choix part quand même',
      () async {
        final ecrites = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          final valeur = (call.arguments as Map)['value'] as String;
          if (valeur == 'dark') {
            throw PlatformException(code: 'PREFS_FAILED');
          }
          ecrites.add(valeur);
          return null;
        });
        final preferences = PreferencesAppareilPlateforme();
        final premier = preferences.ecrireTheme(ThemeMode.dark);
        final second = preferences.ecrireTheme(ThemeMode.light);
        await expectLater(premier, throwsA(isA<PlatformException>()));
        await second;
        expect(ecrites, ['light']);
      },
    );

    test('réponse BUSY du canal : rapportée par choisir', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'BUSY',
          message: 'un appel de préférence est déjà en cours',
        );
      });
      final errors = RecordingErrorReportService();
      final container = ProviderContainer(
        overrides: [
          errorReportServiceProvider.overrideWithValue(errors),
          preferencesAppareilProvider.overrideWithValue(
            PreferencesAppareilPlateforme(),
          ),
          themeModeInitialProvider.overrideWithValue(ThemeMode.system),
        ],
      );
      addTearDown(container.dispose);
      final ok = await container
          .read(themeModeProvider.notifier)
          .choisir(ThemeMode.dark);
      expect(ok, isFalse);
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(errors.reports.single.feature, 'theme_mode.save');
      expect(errors.reports.single.context, 'code : BUSY');
    });

    test('échec du canal : lireTheme rend system et garde l\'erreur', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'PREFS_FAILED', message: 'Exception');
      });
      final lecture = await lireTheme(PreferencesAppareilPlateforme());
      expect(lecture.mode, ThemeMode.system);
      expect(lecture.erreur, isA<PlatformException>());
      expect(lecture.contexte, 'code : PREFS_FAILED');
      final errors = RecordingErrorReportService();
      lecture.rapporter(errors);
      expect(errors.reports.single.feature, 'theme_mode.load');
      expect(errors.reports.single.context, 'code : PREFS_FAILED');
    });
  });

  group('lireTheme', () {
    test('valeur absente : system, aucun rapport', () async {
      final lecture = await lireTheme(FakePreferencesAppareil());
      expect(lecture.mode, ThemeMode.system);
      final errors = RecordingErrorReportService();
      lecture.rapporter(errors);
      expect(errors.reports, isEmpty);
    });

    test('les trois valeurs connues', () async {
      for (final entry in kValeursTheme.entries) {
        final lecture = await lireTheme(
          FakePreferencesAppareil()..valeur = entry.value,
        );
        expect(lecture.mode, entry.key);
        expect(lecture.erreur, isNull);
      }
    });

    test(
      'valeur inconnue : system et rapport avec sa seule longueur',
      () async {
        final lecture = await lireTheme(
          FakePreferencesAppareil()..valeur = 'bleu',
        );
        expect(lecture.mode, ThemeMode.system);
        final errors = RecordingErrorReportService();
        lecture.rapporter(errors);
        expect(errors.reports.single.feature, 'theme_mode.load');
        expect(errors.reports.single.context, 'valeur inconnue (longueur 4)');

        const adresse = 'prenom.nom.tres.long.exemple@exemple.fr';
        final piegee = await lireTheme(
          FakePreferencesAppareil()..valeur = adresse,
        );
        final rapports = RecordingErrorReportService();
        piegee.rapporter(rapports);
        final rapport = rapports.reports.single;
        expect(rapport.context, 'valeur inconnue (longueur ${adresse.length})');
        expect(rapport.context, isNot(contains('@')));
        expect(rapport.error.toString(), isNot(contains('@')));
      },
    );

    test('stockage refusé : system, erreur gardée sans contexte', () async {
      final lecture = await lireTheme(
        FakePreferencesAppareil()..erreurLecture = StateError('SecurityError'),
      );
      expect(lecture.mode, ThemeMode.system);
      expect(lecture.erreur, isA<StateError>());
      expect(lecture.contexte, isNull);
    });
  });

  group('themeModeProvider', () {
    test('part du thème lu au démarrage, enregistre un choix', () async {
      final app = TestApp(themeMode: ThemeMode.dark);
      addTearDown(app.container.dispose);
      expect(app.container.read(themeModeProvider), ThemeMode.dark);
      final ok = await app.container
          .read(themeModeProvider.notifier)
          .choisir(ThemeMode.light);
      expect(ok, isTrue);
      expect(app.container.read(themeModeProvider), ThemeMode.light);
      expect(app.preferences.valeur, 'light');
      expect(app.errors.reports, isEmpty);
    });

    test('échec d\'enregistrement : thème gardé, rapport', () async {
      final app = TestApp();
      addTearDown(app.container.dispose);
      app.preferences.erreurEcriture = PlatformException(code: 'PREFS_FAILED');
      final ok = await app.container
          .read(themeModeProvider.notifier)
          .choisir(ThemeMode.dark);
      expect(ok, isFalse);
      expect(app.container.read(themeModeProvider), ThemeMode.dark);
      expect(app.errors.reports.single.feature, 'theme_mode.save');
      expect(app.errors.reports.single.context, 'code : PREFS_FAILED');
    });

    test(
      'Sombre échoue, puis Clair et Sombre : rapporté, sans échec annoncé',
      () async {
        final app = TestApp();
        addTearDown(app.container.dispose);
        final ecriture = Completer<void>();
        app.preferences.attenteEcriture = ecriture.future;
        app.preferences.erreursEcritures.addAll([
          PlatformException(code: 'PREFS_FAILED'),
          null,
          null,
        ]);
        final notifier = app.container.read(themeModeProvider.notifier);
        // Trois choix pendant la première écriture.
        final sombre = notifier.choisir(ThemeMode.dark);
        final clair = notifier.choisir(ThemeMode.light);
        final sombreEncore = notifier.choisir(ThemeMode.dark);
        ecriture.complete();
        expect(await sombre, isTrue);
        expect(await clair, isTrue);
        expect(await sombreEncore, isTrue);
        expect(app.container.read(themeModeProvider), ThemeMode.dark);
        expect(app.preferences.valeur, 'dark');
        expect(app.errors.reports.single.feature, 'theme_mode.save');
      },
    );
  });

  group('page Préférences', () {
    testWidgets('menu du compte → Préférences : « Comme l\'appareil » choisi', (
      tester,
    ) async {
      final app = await ouvrirPreferences(tester);
      expect(find.text(PreferencesScreen.titre), findsWidgets);
      expect(find.text(PreferencesScreen.apparence), findsOneWidget);
      expect(find.text(PreferencesScreen.commeAppareil), findsOneWidget);
      expect(find.text(PreferencesScreen.commeAppareilAide), findsOneWidget);
      expect(find.text(PreferencesScreen.clair), findsOneWidget);
      expect(find.text(PreferencesScreen.sombre), findsOneWidget);
      expect(find.text(PreferencesScreen.noteAppareil), findsOneWidget);
      final groupe = tester.widget<RadioGroup<ThemeMode>>(
        find.byType(RadioGroup<ThemeMode>),
      );
      expect(groupe.groupValue, ThemeMode.system);
      expect(modeAffiche(tester), ThemeMode.system);
      expect(app.preferences.ecritures, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Sombre » : thème changé aussitôt et enregistré', (
      tester,
    ) async {
      final app = await ouvrirPreferences(tester);
      await tester.tap(find.text(PreferencesScreen.sombre));
      await tester.pumpAndSettle();
      expect(modeAffiche(tester), ThemeMode.dark);
      expect(app.preferences.ecritures, [ThemeMode.dark]);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(PreferencesScreen.clair));
      await tester.pumpAndSettle();
      expect(modeAffiche(tester), ThemeMode.light);
      expect(app.preferences.valeur, 'light');
    });

    testWidgets('échec d\'enregistrement : thème gardé, message, rapport', (
      tester,
    ) async {
      final app = await ouvrirPreferences(tester);
      app.preferences.erreurEcriture = StateError('QuotaExceededError');
      await tester.tap(find.text(PreferencesScreen.sombre));
      await tester.pumpAndSettle();
      expect(modeAffiche(tester), ThemeMode.dark);
      expect(find.text(PreferencesScreen.echecEnregistrement), findsOneWidget);
      expect(app.errors.reports.single.feature, 'theme_mode.save');
    });

    testWidgets('trois échecs de suite : un seul message, aucun en attente', (
      tester,
    ) async {
      final app = await ouvrirPreferences(tester);
      app.preferences.erreurEcriture = StateError('QuotaExceededError');
      for (final choix in [
        PreferencesScreen.sombre,
        PreferencesScreen.clair,
        PreferencesScreen.sombre,
      ]) {
        await tester.tap(find.text(choix));
        await tester.pumpAndSettle();
      }
      expect(app.errors.reports.length, 3);
      expect(find.byType(SnackBar), findsOneWidget);
      // Le message affiché s'efface après sa durée : aucun autre ne le suit.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('retour : écran précédent', (tester) async {
      await ouvrirPreferences(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(PreferencesScreen.titre), findsNothing);
    });
  });

  group('thème sombre lu au démarrage', () {
    Future<TestApp> monter(WidgetTester tester) async {
      final app = TestApp(themeMode: ThemeMode.dark);
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      app.recipes.publish([
        Recipe(
          id: 'm',
          ownerUid: 'uid-brasseur',
          ownerName: 'Bruno Brasseur',
          content: const RecipeContent(name: 'Blonde', batchVolumeL: 20),
        ),
      ]);
      app.brews.publish([unBrassin(id: 'b1', brewedAt: DateTime(2026, 11, 8))]);
      app.brews.publishEvents('b1', const []);
      await tester.pumpAndSettle();
      return app;
    }

    const ecrans = {
      '/recettes': RecipesListScreen,
      '/recettes/m': RecipeDetailScreen,
      '/brassins/b1/jour': BrewDayScreen,
    };
    for (final MapEntry(key: path, value: ecran) in ecrans.entries) {
      testWidgets('$path s\'affiche en sombre, sans exception', (tester) async {
        final app = await monter(tester);
        app.container.read(routerProvider).go(path);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ecran), findsOneWidget);
        expect(modeAffiche(tester), ThemeMode.dark);
        final contexte = tester.element(find.byType(Scaffold).last);
        expect(Theme.of(contexte).brightness, Brightness.dark);
        expect(app.errors.reports, isEmpty);
      });
    }
  });
}
