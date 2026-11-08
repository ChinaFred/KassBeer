import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/presentation/brew_detail_screen.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

final _h = DateTime(2026, 11, 8);
DateTime hm(int h, int m, [int s = 0]) =>
    DateTime(_h.year, _h.month, _h.day, h, m, s);

const _brassinId = 'b1';

Future<TestApp> ouvrir(
  WidgetTester tester, {
  required DateTime now,
  Brew? brew,
  List<BrewEvent> events = const [],
  bool signedInOwner = true,
  double width = 400,
  double height = 900,
}) async {
  final app = TestApp()..now = now;
  await app.pump(tester, width: width, height: height);
  app.signIn(
    signedInOwner ? brewerUser : adminUser,
    member: signedInOwner ? brewerMember : adminMember,
  );
  app.brews.publish([brew ?? unBrassin(id: _brassinId, brewedAt: hm(11, 45))]);
  app.brews.publishEvents(_brassinId, events);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go('/brassins/$_brassinId/jour');
  await tester.pumpAndSettle();
  return app;
}

Finder minuteur() => find.byKey(const ValueKey('minuteur'));

void main() {
  testWidgets('MH2 : tuée puis relancée à 12:10 → 20:00 restantes', (
    tester,
  ) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    expect(tester.widget<Text>(minuteur()).data, '20:00');
    expect(find.text('Terminer l\'étape'), findsOneWidget);
  });

  testWidgets('le minuteur suit l\'horloge, pas un compteur', (tester) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    app.now = hm(12, 20);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(minuteur()).data, '10:00');
  });

  testWidgets('double appui : un seul événement', (tester) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.tap(find.text('Terminer l\'étape'));
    await tester.tap(find.text('Terminer l\'étape'));
    await tester.pump();
    final steps = app.brews.writes.where((w) => w.kind == 'steps').toList();
    expect(steps.length, 1);
    expect(steps.single.detail['writes'], ['step_ended:k-palier']);
    expect(steps.single.detail['at'], hm(12, 10));
  });

  testWidgets(
    'commencer une étape pendant qu\'une autre tourne : lot fin + début',
    (tester) async {
      final app = await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      await tester.tap(find.text('Ébullition').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer cette étape'));
      await tester.pumpAndSettle();
      expect(find.text('« Palier 68 » est en cours.'), findsOneWidget);
      await tester.tap(find.text('Terminer et commencer'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.where((w) => w.kind == 'steps').single;
      expect(write.detail['writes'], [
        'step_ended:k-palier',
        'step_started:k-ebullition',
      ]);
    },
  );

  testWidgets('étape sautée : ligne Sautée, Commencer reste possible', (
    tester,
  ) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      brew: unBrassin(
        id: _brassinId,
        brewedAt: hm(10, 0),
        steps: const [palier, ebullition],
      ),
      events: [saut('e1', 'k-palier', hm(11, 45))],
    );
    expect(find.textContaining('Sautée'), findsWidgets);
    await tester.tap(find.text('Palier 68').last);
    await tester.pumpAndSettle();
    expect(find.text('Ne plus sauter'), findsOneWidget);
    expect(find.text('Commencer cette étape'), findsOneWidget);
  });

  testWidgets('début en double : affiché et supprimable', (tester) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [
        debut('e1', 'k-palier', hm(11, 45)),
        debut('e2', 'k-palier', hm(11, 47)),
      ],
    );
    expect(find.textContaining('Début en double'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pump();
    expect(
      app.brews.writes
          .singleWhere((w) => w.kind == 'delete_event')
          .detail['id'],
      'e2',
    );
  });

  testWidgets(
    'mesure de densité « 1057,9 » : écrite en SG, à l\'heure de l\'appareil',
    (tester) async {
      final app = await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      await tester.tap(find.text('Mesure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Densité'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1057,9',
      );
      await tester.pump();
      expect(find.text('= 1057,9'), findsOneWidget);
      await tester.tap(find.text('Enregistrer la mesure'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.singleWhere((w) => w.kind == 'event');
      expect(write.detail['type'], 'gravity');
      expect(write.detail['value'], closeTo(1.0579, 1e-9));
      expect(write.detail['at'], hm(12, 10));
      expect(find.text('Mesure enregistrée.'), findsOneWidget);
      expect(app.errors.reports, isEmpty);
    },
  );

  testWidgets('densité « 1.058 » : acceptée', (tester) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.tap(find.text('Mesure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Densité'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Densité'),
      '1.058',
    );
    await tester.tap(find.text('Enregistrer la mesure'));
    await tester.pumpAndSettle();
    expect(
      app.brews.writes.singleWhere((w) => w.kind == 'event').detail['value'],
      closeTo(1.058, 1e-9),
    );
  });

  testWidgets(
    'densité illisible : erreur à l\'écran, aucun rapport, rien d\'écrit',
    (tester) async {
      final app = await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      await tester.tap(find.text('Mesure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Densité'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        'abc',
      );
      await tester.tap(find.text('Enregistrer la mesure'));
      await tester.pumpAndSettle();
      expect(
        find.text('Densité illisible. Écrivez 1057,9 ou 1.058.'),
        findsOneWidget,
      );
      expect(app.brews.writes, isEmpty);
      expect(app.errors.reports, isEmpty);
    },
  );

  group('alerte de fin de minuteur', () {
    testWidgets('une seule alerte au passage de la durée', (tester) async {
      final app = await ouvrir(
        tester,
        now: hm(12, 29, 58),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      expect(app.alerte.triggered, 0);
      app.now = hm(12, 30, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(app.alerte.triggered, 1);
      app.now = hm(12, 30, 3);
      await tester.pump(const Duration(seconds: 1));
      expect(app.alerte.triggered, 1);
      expect(tester.widget<Text>(minuteur()).data, startsWith('+'));
    });

    testWidgets('écran rouvert longtemps après : aucune alerte', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        now: hm(13, 0),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      await tester.pump(const Duration(seconds: 1));
      expect(app.alerte.triggered, 0);
    });
  });

  testWidgets('verrou d\'écran : pris à l\'ouverture, relâché en quittant', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    expect(app.wakelockCalls, [true]);
    app.container.read(routerProvider).go('/recettes');
    await tester.pumpAndSettle();
    expect(app.wakelockCalls, [true, false]);
  });

  testWidgets('reprise au lancement : écran du jour rouvert, annonce unique', (
    tester,
  ) async {
    final app = TestApp()..now = hm(12, 10);
    await app.pump(tester, height: 900);
    app.signIn(brewerUser, member: brewerMember);
    app.brews.publish([unBrassin(id: _brassinId, brewedAt: hm(11, 45))]);
    app.brews.publishEvents(_brassinId, [debut('e1', 'k-palier', hm(11, 45))]);
    await tester.pumpAndSettle();
    expect(find.text(BrewDayScreen.reprised), findsOneWidget);
    expect(tester.widget<Text>(minuteur()).data, '20:00');
  });

  testWidgets('R6 : Les sauter et commencer, écritures simples une par une', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      brew: unBrassin(
        id: _brassinId,
        brewedAt: hm(11, 0),
        steps: const [palier, ebullition, ajout],
      ),
    );
    await tester.tap(find.text('Ajouter Cascade').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commencer cette étape'));
    await tester.pumpAndSettle();
    expect(
      find.text('2 étapes avant celle-ci ne sont pas faites'),
      findsOneWidget,
    );
    await tester.tap(find.text('Les sauter et commencer'));
    await tester.pumpAndSettle();
    final writes = app.brews.writes.where((w) => w.kind == 'steps').toList();
    expect(writes.map((w) => w.detail['writes']), [
      ['step_skipped:k-palier'],
      ['step_skipped:k-ebullition'],
      ['step_started:k-ajout', 'step_ended:k-ajout'],
    ]);
  });

  testWidgets('B1, B2 : paysage, minuteur 72 sp et boutons visibles', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      width: 844,
      height: 390,
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    expect(tester.widget<Text>(minuteur()).style?.fontSize, 72);
    await tester.tap(find.text('Terminer l\'étape'));
    await tester.pump();
    expect(app.brews.writes.where((w) => w.kind == 'steps'), hasLength(1));
  });

  testWidgets('B3 : la SnackBar de la mesure disparaît après 10 s', (
    tester,
  ) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.tap(find.text('Mesure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Densité'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Densité'),
      '1050',
    );
    await tester.tap(find.text('Enregistrer la mesure'));
    await tester.pumpAndSettle();
    expect(find.text('Mesure enregistrée.'), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Mesure enregistrée.'), findsNothing);
  });

  testWidgets('B4 : un appui hors de la feuille ne perd pas la saisie', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.tap(find.text('Mesure'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer la mesure'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Enregistrer la mesure'), findsNothing);
    expect(app.brews.writes, isEmpty);
  });

  testWidgets('R7 : heure de l\'appareil affichée, redessinée', (tester) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    final heure = find.byKey(const ValueKey('heure-appareil'));
    expect(tester.widget<Text>(heure).data, '12:10');
    app.now = hm(12, 11);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(heure).data, '12:11');
  });

  testWidgets('R4 : chronologie figée illisible, raison affichée', (
    tester,
  ) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      brew: Brew(
        id: _brassinId,
        ownerUid: 'uid-brasseur',
        name: 'Blonde',
        status: BrewStatus.brewing,
        recipe: const RecipeContent(
          name: 'Blonde',
          brewStepsProblem: 'clé en double (1)',
        ),
        equipment: equipementTest,
        brewedAt: hm(11, 0),
      ),
    );
    expect(
      find.text('Chronologie de ce brassin illisible : clé en double (1).'),
      findsOneWidget,
    );
    expect(find.text('Aucune étape. Saisissez vos mesures.'), findsNothing);
  });

  testWidgets('C1 : retour Android, ramène à la fiche', (tester) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BrewDetailScreen), findsOneWidget);
    expect(find.byType(BrewDayScreen), findsNothing);
  });

  testWidgets('C1 : retour Android pendant le chargement des saisies', (
    tester,
  ) async {
    final app = TestApp()..now = hm(12, 10);
    await app.pump(tester, height: 900);
    app.signIn(brewerUser, member: brewerMember);
    app.brews.publish([unBrassin(id: _brassinId, brewedAt: hm(11, 45))]);
    await tester.pump();
    app.container.read(routerProvider).go('/brassins/$_brassinId/jour');
    // Indicateur de chargement animé : pas de pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BrewDayScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BrewDetailScreen), findsOneWidget);
    expect(find.byType(BrewDayScreen), findsNothing);
  });

  testWidgets('autre membre : réservé au brasseur', (tester) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      signedInOwner: false,
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    expect(find.text(BrewDayScreen.notOwner), findsOneWidget);
    expect(find.text('Terminer l\'étape'), findsNothing);
  });

  testWidgets('saisies en attente : pastille Hors ligne · n', (tester) async {
    final app = TestApp()..now = hm(12, 10);
    await app.pump(tester, height: 900);
    app.signIn(brewerUser, member: brewerMember, fromCache: true);
    app.brews.publish([unBrassin(id: _brassinId, brewedAt: hm(11, 45))]);
    app.brews.publishEvents(_brassinId, [
      debut('e1', 'k-palier', hm(11, 45)),
      mesure(
        'm1',
        'k-palier',
        MeasureType.gravity,
        1.05,
        hm(12, 0),
        pending: true,
      ),
    ]);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/brassins/$_brassinId/jour');
    await tester.pumpAndSettle();
    expect(find.text('Hors ligne · 1'), findsOneWidget);
  });

  testWidgets('saisie refusée par le serveur : pastille « 1 refusée »', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    final refus = Completer<void>();
    app.brews.serverAnswer = () => refus.future;
    await tester.tap(find.text('Terminer l\'étape'));
    await tester.pump();
    refus.completeError(Exception('permission-denied'));
    await tester.pump();
    expect(find.text('1 refusée'), findsOneWidget);
  });

  testWidgets('Terminer le brassage réutilise le nom lu à l\'ouverture', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    expect(app.auth.tokenReads, greaterThanOrEqualTo(1));
    final lectures = app.auth.tokenReads;
    await tester.tap(find.byTooltip('Plus d\'actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminer le brassage'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer le brassage'));
    await tester.pumpAndSettle();
    final write = app.brews.writes.singleWhere((w) => w.kind == 'finish');
    expect(write.detail['owner_name'], 'Bruno Brasseur');
    expect(app.auth.tokenReads, lectures);
  });
}
