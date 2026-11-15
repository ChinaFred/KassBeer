import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/encadre.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/theme/app_theme.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/brew_day/presentation/chronologie_jour.dart';
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
    expect(find.text(libelleEtapeSuivante), findsOneWidget);
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
    await tester.tap(find.text(libelleEtapeSuivante));
    await tester.tap(find.text(libelleEtapeSuivante));
    await tester.pump();
    final steps = app.brews.writes.where((w) => w.kind == 'steps').toList();
    expect(steps.length, 1);
    expect(steps.single.detail['writes'], [
      'step_ended:k-palier',
      'step_started:k-ebullition',
    ]);
    expect(steps.single.detail['at'], hm(12, 10));
  });

  testWidgets('dernière étape en cours : Terminer l\'étape, fin seule', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      brew: unBrassin(
        id: _brassinId,
        brewedAt: hm(11, 45),
        steps: const [palier],
      ),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    expect(find.text(libelleEtapeSuivante), findsNothing);
    await tester.tap(find.text('Terminer l\'étape'));
    await tester.pump();
    final write = app.brews.writes.where((w) => w.kind == 'steps').single;
    expect(write.detail['writes'], ['step_ended:k-palier']);
  });

  testWidgets('Étape suivante : message, Annuler supprime fin et début', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.tap(find.text(libelleEtapeSuivante));
    await tester.pump();
    expect(find.text(texteEtapeCommencee('Ébullition')), findsOneWidget);
    app.brews.publishEvents(_brassinId, [
      debut('e1', 'k-palier', hm(11, 45)),
      fin('e2', 'k-palier', hm(12, 10)),
      debut('e3', 'k-ebullition', hm(12, 10)),
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Annuler'));
    await tester.pump();
    final suppr = app.brews.writes
        .where((w) => w.kind == 'delete_events')
        .single;
    expect(suppr.detail['ids'], ['e3', 'e2']);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(texteEtapeReprise('Palier 68')), findsOneWidget);
  });

  testWidgets('Annuler après la fin de l\'étape commencée : rien supprimé', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.tap(find.text(libelleEtapeSuivante));
    await tester.pump();
    app.brews.publishEvents(_brassinId, [
      debut('e1', 'k-palier', hm(11, 45)),
      fin('e2', 'k-palier', hm(12, 10)),
      debut('e3', 'k-ebullition', hm(12, 10)),
      fin('e4', 'k-ebullition', hm(12, 10)),
    ]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Annuler'));
    await tester.pump();
    expect(app.brews.writes.where((w) => w.kind == 'delete_events'), isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(texteAnnulationImpossible('Ébullition')), findsOneWidget);
  });

  testWidgets('suivante de 0 minute : Terminer l\'étape, puis Fait', (
    tester,
  ) async {
    final app = await ouvrir(
      tester,
      now: hm(12, 10),
      brew: unBrassin(
        id: _brassinId,
        brewedAt: hm(11, 45),
        steps: const [palier, ajout, ebullition],
      ),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    expect(find.text(libelleEtapeSuivante), findsNothing);
    await tester.tap(find.text('Terminer l\'étape'));
    await tester.pump();
    final write = app.brews.writes.where((w) => w.kind == 'steps').single;
    expect(write.detail['writes'], ['step_ended:k-palier']);
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
    await tester.ensureVisible(find.text('Supprimer'));
    await tester.pump();
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
    // Encadré sous la carte de l'étape, jamais un SnackBar posé sur la
    // chronologie.
    expect(
      find.descendant(
        of: find.byType(Encadre),
        matching: find.text(BrewDayScreen.reprised),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.widget<Text>(minuteur()).data, '20:00');
    final fermer = find.widgetWithText(TextButton, 'Fermer');
    await tester.ensureVisible(fermer);
    await tester.pumpAndSettle();
    await tester.tap(fermer);
    await tester.pumpAndSettle();
    expect(find.text(BrewDayScreen.reprised), findsNothing);
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
    await tester.tap(find.text(libelleEtapeSuivante));
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
    expect(find.text(libelleEtapeSuivante), findsNothing);
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
    await tester.tap(find.text(libelleEtapeSuivante));
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
    int? lecturesAuFinish;
    app.brews.serverAnswer = () {
      lecturesAuFinish = app.auth.tokenReads;
      return Completer<void>().future;
    };
    await tester.tap(find.byTooltip('Plus d\'actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminer le brassage'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer le brassage'));
    await tester.pumpAndSettle();
    final write = app.brews.writes.singleWhere((w) => w.kind == 'finish');
    expect(write.detail['owner_name'], 'Bruno Brasseur');
    // La fiche ouverte après la fin lit le jeton pour ses propres actions (R1) ;
    // « Terminer » n'en a provoqué aucune lecture avant d'écrire.
    expect(lecturesAuFinish, lectures);
    expect(app.auth.tokenReads, lectures + 1);
  });

  group('carte de l\'étape en cours', () {
    Finder carte() => find.byKey(const ValueKey('carte-etape'));
    Finder progression() => find.byKey(const ValueKey('progression-etape'));
    RoundedRectangleBorder forme(WidgetTester tester) =>
        tester.widget<Material>(carte()).shape! as RoundedRectangleBorder;

    testWidgets('en cours puis dépassé : couleurs, bord, icône, même marge', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      final scheme = Theme.of(tester.element(carte())).colorScheme;
      expect(tester.widget<Material>(carte()).color, scheme.primaryContainer);
      expect(forme(tester).side.width, 2);
      expect(forme(tester).side.color, scheme.primaryContainer);
      expect(find.text('ÉTAPE 1 SUR 2 · EN COURS'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('icone-etat-etape')))
            .icon,
        Icons.timer_outlined,
      );
      final haut = tester.getTopLeft(carte());
      final nom = tester.getTopLeft(find.text('Palier 68').first) - haut;
      final chrono = tester.getTopLeft(minuteur()) - haut;

      // 12:35 : la durée de 45 min est dépassée de 5 min.
      app.now = hm(12, 35);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Material>(carte()).color, scheme.tertiaryContainer);
      expect(forme(tester).side.width, 2);
      expect(forme(tester).side.color, scheme.tertiary);
      expect(find.text('ÉTAPE 1 SUR 2 · DÉPASSÉ'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('icone-etat-etape')))
            .icon,
        Icons.alarm,
      );
      // Même place pour la carte et son contenu : rien ne saute.
      expect(tester.getTopLeft(carte()), haut);
      expect(tester.getTopLeft(find.text('Palier 68').first) - haut, nom);
      expect(tester.getTopLeft(minuteur()) - haut, chrono);
    });

    testWidgets('barre : part écoulée de brewing, exclue de la lecture', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      LinearProgressIndicator barre() =>
          tester.widget<LinearProgressIndicator>(progression());
      // 25 min écoulées sur 45.
      expect(barre().value, closeTo(25 / 45, 1e-9));
      expect(
        find.ancestor(
          of: progression(),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      expect(find.semantics.byValue('56'), findsNothing);
      expect(
        find.bySemanticsLabel('20 minutes 0 seconde restantes'),
        findsOneWidget,
      );

      app.now = hm(12, 20);
      await tester.pump(const Duration(seconds: 1));
      expect(barre().value, closeTo(35 / 45, 1e-9));

      app.now = hm(12, 35);
      await tester.pump(const Duration(seconds: 1));
      expect(barre().value, 1);
      final scheme = Theme.of(tester.element(carte())).colorScheme;
      expect(barre().color, scheme.tertiary);
      semantics.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('contraste et cibles, thème ${brightness.name}', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final app = await ouvrir(
          tester,
          now: hm(12, 10),
          events: [debut('e1', 'k-palier', hm(11, 45))],
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        app.now = hm(12, 35);
        await tester.pump(const Duration(seconds: 1));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      });
    }

    for (final (nom, largeur, hauteur) in [
      ('portrait', 400.0, 900.0),
      ('paysage', 844.0, 390.0),
    ]) {
      testWidgets('texte à 200 %, $nom : aucun débordement', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        // Aucune erreur écartée : l'annonce « Brassage repris » est un encadré
        // du panneau, plus un SnackBar flottant.
        final erreurs = <FlutterErrorDetails>[];
        final original = FlutterError.onError;
        FlutterError.onError = erreurs.add;
        try {
          final app = await ouvrir(
            tester,
            now: hm(12, 10),
            width: largeur,
            height: hauteur,
            events: [debut('e1', 'k-palier', hm(11, 45))],
          );
          expect(carte(), findsOneWidget);
          expect(find.text(BrewDayScreen.reprised), findsOneWidget);
          // L'encadré suit la carte de l'étape : il ne repousse pas le
          // minuteur vers le bas.
          expect(
            tester.getRect(find.text(BrewDayScreen.reprised)).top,
            greaterThan(tester.getRect(carte()).bottom),
          );
          app.now = hm(12, 35);
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('ÉTAPE 1 SUR 2 · DÉPASSÉ'), findsOneWidget);
          expect(find.text(libelleEtapeSuivante), findsOneWidget);
        } finally {
          FlutterError.onError = original;
        }
        expect(erreurs.map((e) => e.exceptionAsString()), isEmpty);
      });
    }
  });

  testWidgets('chronologie : icône d\'état colorée selon l\'état', (
    tester,
  ) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      brew: unBrassin(
        id: _brassinId,
        brewedAt: hm(11, 0),
        steps: const [palier, ajout, ebullition],
      ),
      events: [
        debut('e1', 'k-palier', hm(11, 0)),
        fin('e2', 'k-palier', hm(11, 45)),
        saut('e3', 'k-ajout', hm(11, 46)),
        debut('e4', 'k-ebullition', hm(11, 50)),
      ],
    );
    final chronologie = find.byType(ChronologieJour);
    Color? couleur(IconData icone) => tester
        .widget<Icon>(
          find.descendant(of: chronologie, matching: find.byIcon(icone)),
        )
        .color;
    final context = tester.element(chronologie);
    final scheme = Theme.of(context).colorScheme;
    expect(
      couleur(Icons.check_circle_outline),
      CouleursEtat.of(context).succes,
    );
    expect(couleur(Icons.play_circle_outline), scheme.primary);
    expect(couleur(Icons.skip_next), scheme.onSurfaceVariant);
  });

  testWidgets('feuille Recette : nom de la recette en en-tête', (tester) async {
    await ouvrir(
      tester,
      now: hm(12, 10),
      events: [debut('e1', 'k-palier', hm(11, 45))],
    );
    await tester.tap(find.byTooltip('Plus d\'actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir la recette'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.header ?? false) &&
              w.child is Text &&
              (w.child! as Text).data == 'Blonde',
        ),
      ),
      findsOneWidget,
    );
  });

  group('courbe du jour de brassage', () {
    testWidgets('sous 840 px : bascule « Étapes » | « Courbe », minuteur '
        'toujours affiché, rien n\'est écrit', (tester) async {
      final app = await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
      );
      expect(find.text(ZoneChronologieCourbe.libelleEtapes), findsOneWidget);
      expect(find.text('Visée (recalculée)'), findsNothing);
      await tester.tap(find.text(ZoneChronologieCourbe.libelleCourbe));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Visée (recalculée)'), findsOneWidget);
      expect(minuteur(), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('à partir de 840 px : courbe sous le panneau, sans bascule', (
      tester,
    ) async {
      await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
        width: 1200,
      );
      expect(find.text(ZoneChronologieCourbe.libelleCourbe), findsNothing);
      expect(find.text('Visée (recalculée)'), findsOneWidget);
      expect(minuteur(), findsOneWidget);
    });

    testWidgets('paysage bas, même large : bascule, panneau et minuteur '
        'visibles', (tester) async {
      await ouvrir(
        tester,
        now: hm(12, 10),
        events: [debut('e1', 'k-palier', hm(11, 45))],
        width: 900,
        height: 400,
      );
      expect(find.text(ZoneChronologieCourbe.libelleCourbe), findsOneWidget);
      expect(minuteur(), findsOneWidget);
    });
  });
}
