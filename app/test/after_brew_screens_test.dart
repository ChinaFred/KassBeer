import 'dart:async';

import 'package:brewing/brewing.dart' show FermentableKind, alcoholByVolume;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/releves.dart';
import 'package:kass_beer/features/brews/presentation/releve_fermentation.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

const blonde = RecipeContent(
  name: 'Blonde',
  batchVolumeL: 20,
  fermentables: [
    FermentableLine(
      name: 'Pils',
      kind: FermentableKind.malt,
      weightG: 5000,
      ebc: 3.9,
      yieldPct: 80,
    ),
  ],
  yeasts: [YeastLine(name: 'US-05', attenuationPct: 78)],
  brewSteps: [palier, ebullition],
);

const blondeSucree = RecipeContent(
  name: 'Blonde',
  batchVolumeL: 20,
  fermentables: [
    FermentableLine(
      name: 'Pils',
      kind: FermentableKind.malt,
      weightG: 5000,
      ebc: 3.9,
      yieldPct: 80,
    ),
    FermentableLine(
      name: 'Candi',
      kind: FermentableKind.sugar,
      weightG: 500,
      ebc: 2,
      yieldPct: 100,
    ),
  ],
  yeasts: [YeastLine(name: 'US-05', attenuationPct: 78)],
  brewSteps: [palier, ebullition],
);

final brewedAt = DateTime(2026, 11, 8, 15, 20);
final jour5 = DateTime(2026, 11, 13, 18, 30);

BrewEvent og([double value = 1.0579]) =>
    mesure('og', 'k-palier', MeasureType.gravity, value, brewedAt);
BrewEvent volume() =>
    mesure('vol', 'k-palier', MeasureType.volume, 21, brewedAt);
BrewEvent fg([double value = 1.012]) =>
    releve('fg', MeasureType.gravity, value, jour5);

Brew fermentation({
  String owner = 'uid-brasseur',
  RecipeContent recipe = blonde,
  bool? sugars,
}) => unBrassin(
  owner: owner,
  status: BrewStatus.fermenting,
  brewedAt: brewedAt,
  recipe: recipe,
  sugarsInWort: sugars,
);

Future<TestApp> fiche(
  WidgetTester tester, {
  required Brew brew,
  List<BrewEvent> events = const [],
  bool offline = false,
  double width = 400,
  double height = 1400,
}) async {
  final app = TestApp();
  await app.pump(tester, width: width, height: height);
  app.signIn(brewerUser, member: brewerMember, fromCache: offline);
  app.now = DateTime(2026, 11, 20, 12);
  app.brews.publish([brew]);
  app.brews.publishEvents('b1', events, fromCache: offline);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go('/brassins/b1');
  await tester.pumpAndSettle();
  return app;
}

Future<void> ouvrirMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Plus d\'actions'));
  await tester.pumpAndSettle();
}

Future<void> voir(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('statuts et actions (ST1)', () {
    testWidgets('En fermentation : J+N, FAB, Embouteiller, menu complet', (
      tester,
    ) async {
      await fiche(tester, brew: fermentation());
      expect(find.text('En fermentation · J+12'), findsOneWidget);
      expect(
        find.widgetWithText(FloatingActionButton, 'Ajouter un relevé'),
        findsOneWidget,
      );
      expect(find.text('Embouteiller'), findsOneWidget);
      await ouvrirMenu(tester);
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Revenir à En cours'), findsOneWidget);
      expect(find.text('Abandonner ce brassin'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
    });

    testWidgets('fenêtre large : aucun FAB, boutons côte à côte', (
      tester,
    ) async {
      await fiche(tester, brew: fermentation(), width: 1000, height: 1400);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Ajouter un relevé'),
        findsOneWidget,
      );
    });

    testWidgets('autre membre : aucune action, chiffres en lecture seule', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: fermentation(owner: 'uid-zoe'),
        events: [og(), volume(), fg()],
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('Plus d\'actions'), findsNothing);
      expect(find.text('Changer'), findsNothing);
      expect(find.text('Embouteiller'), findsNothing);
      await voir(tester, find.text('Rendement'));
      expect(find.text('Saisir le volume en fermenteur'), findsNothing);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('En conditionnement : Marquer comme terminé, Annuler', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
          recipe: blonde,
        ),
      );
      expect(
        find.text('En conditionnement · Embouteillé le 15 nov. 2026'),
        findsOneWidget,
      );
      await tester.tap(find.text('Marquer comme terminé'));
      await tester.pumpAndSettle();
      expect(find.text('Brassin terminé.'), findsOneWidget);
      expect(app.brews.writes.single.detail['status'], BrewStatus.done);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.last.detail['status'], BrewStatus.conditioning);
    });

    testWidgets('Revenir : confirmation, écran du jour rouvert en En cours', (
      tester,
    ) async {
      final app = await fiche(tester, brew: fermentation());
      await ouvrirMenu(tester);
      await tester.tap(find.text('Revenir à En cours'));
      await tester.pumpAndSettle();
      expect(find.text('Revenir à « En cours » ?'), findsOneWidget);
      expect(find.textContaining('Reprendre le brassage'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Revenir'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.detail['status'], BrewStatus.brewing);
      expect(find.text('Brassin revenu à En cours.'), findsOneWidget);
    });

    testWidgets('Abandonner : dialogue ST4, statut abandonné', (tester) async {
      final app = await fiche(tester, brew: fermentation());
      await ouvrirMenu(tester);
      await tester.tap(find.text('Abandonner ce brassin'));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner « Blonde du jour » ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Abandonner'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.detail['status'], BrewStatus.abandoned);
    });

    testWidgets('Reprendre après abandon : En conditionnement si embouteillé', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.abandoned,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
          recipe: blonde,
        ),
      );
      await tester.tap(find.text('Reprendre ce brassin'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.detail['status'], BrewStatus.conditioning);
      expect(find.text('Brassin repris : En conditionnement.'), findsOneWidget);
    });

    testWidgets('constat 5 : hors ligne, le refus précède la confirmation', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: fermentation(),
        events: [og()],
        offline: true,
      );
      await ouvrirMenu(tester);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Supprimer'), findsNothing);
      expect(
        find.text(
          'Suppression impossible hors ligne : ce brassin a des saisies.',
        ),
        findsOneWidget,
      );
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('Modifier est dans le menu ; Prévu garde ses boutons', (
      tester,
    ) async {
      await fiche(
        tester,
        brew: unBrassin(status: BrewStatus.planned, recipe: blonde),
      );
      expect(find.byTooltip('Plus d\'actions'), findsNothing);
      expect(find.text('Modifier'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
    });
  });

  group('relevé de fermentation', () {
    testWidgets('liste : ligne complète, FE11 : pas dans la chronologie', (
      tester,
    ) async {
      await fiche(
        tester,
        brew: fermentation(),
        events: [
          og(),
          releve('r1', MeasureType.gravity, 1.02, jour5),
          releve('r2', MeasureType.temperature, 18.5, jour5),
          releve('r3', MeasureType.gravity, 1.023, DateTime(2026, 11, 11, 9)),
        ],
      );
      await voir(tester, find.text('ven. 13 nov. 18:30 · J+5'));
      expect(find.text('1020,0'), findsWidgets);
      expect(find.text('18,5$nbsp°C'), findsOneWidget);
      expect(find.text('−3,0${nbsp}pts'), findsOneWidget);
      expect(find.text('ven. 13 nov. 18:30 · J+5'), findsOneWidget);
    });

    testWidgets('FE1 : formulaire vide refusé, rien n\'est écrit', (
      tester,
    ) async {
      final app = await fiche(tester, brew: fermentation());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer le relevé'));
      await tester.pumpAndSettle();
      expect(
        find.text('Saisissez une densité, une température ou une note.'),
        findsOneWidget,
      );
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('ajout : écrit densité et température, Annuler supprime', (
      tester,
    ) async {
      final app = await fiche(tester, brew: fermentation());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1,020',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Température (°C)'),
        '18,5',
      );
      await tester.tap(find.text('Enregistrer le relevé'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'releve');
      expect(write.detail['gravity'], 1.02);
      expect(write.detail['temperature'], 18.5);
      expect(find.text('Relevé enregistré.'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.last.kind, 'delete_events');
    });

    testWidgets('FE2 : température hors bornes refusée', (tester) async {
      final app = await fiche(tester, brew: fermentation());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Température (°C)'),
        '150',
      );
      await tester.tap(find.text('Enregistrer le relevé'));
      await tester.pumpAndSettle();
      expect(find.text('Entre 0 et 110.'), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('correction et suppression, FE10 : Annuler restaure', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: fermentation(),
        events: [
          og(),
          releve('r1', MeasureType.gravity, 1.02, jour5),
          releve('r2', MeasureType.temperature, 18.5, jour5),
        ],
      );
      await voir(tester, find.text('ven. 13 nov. 18:30 · J+5'));
      await tester.tap(find.text('ven. 13 nov. 18:30 · J+5'));
      await tester.pumpAndSettle();
      expect(find.text('Corriger le relevé'), findsOneWidget);
      expect(find.text('1020,0'), findsWidgets);
      await tester.tap(find.text('Supprimer le relevé'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'delete_events');
      expect(find.text('Relevé supprimé.'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      final restore = app.brews.writes.last;
      expect(restore.kind, 'restore_events');
      expect(restore.detail['ids'], unorderedEquals(['r1', 'r2']));
    });

    testWidgets('FE12 : vide, propriétaire et autres statuts', (tester) async {
      await fiche(tester, brew: fermentation());
      await voir(tester, find.text('Relevé de fermentation'));
      expect(
        find.text('Aucun relevé. Appuyez sur Ajouter un relevé.'),
        findsOneWidget,
      );
    });

    testWidgets('FE13 : relevé existant, En cours : section visible', (
      tester,
    ) async {
      await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.brewing,
          brewedAt: brewedAt,
          recipe: blonde,
        ),
        events: [releve('r1', MeasureType.gravity, 1.02, jour5)],
      );
      await voir(tester, find.text('Relevé de fermentation'));
      expect(find.text('Relevé de fermentation'), findsOneWidget);
    });

    testWidgets('FE11 : Relevés absents de la chronologie, section ailleurs', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: fermentation(),
        events: [
          releve('r1', MeasureType.gravity, 1.02, jour5),
          mesure('m1', null, MeasureType.volume, 21, brewedAt),
        ],
      );
      await voir(tester, find.text('Chronologie'));
      await tester.tap(find.text('Chronologie'));
      await tester.pumpAndSettle();
      await voir(tester, find.text('Sans étape'));
      expect(find.textContaining(' · 1020,0'), findsNothing);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('HS6 : hors ligne, cache vide : indisponible', (tester) async {
      await fiche(tester, brew: fermentation(), offline: true);
      await voir(
        tester,
        find.text('Relevés indisponibles sur cet appareil hors ligne.'),
      );
    });

    testWidgets('hors ligne : message d\'attente du réseau', (tester) async {
      await fiche(tester, brew: fermentation(), events: [og()], offline: true);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1,020',
      );
      await tester.tap(find.text('Enregistrer le relevé'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Relevé enregistré sur l\'appareil. Il partira au retour du réseau.',
        ),
        findsOneWidget,
      );
    });
  });

  group('prévu et mesuré', () {
    testWidgets('VR10 : aucune mesure : mesuré indisponible, prévu affiché', (
      tester,
    ) async {
      await fiche(tester, brew: fermentation());
      await voir(tester, find.text('Prévu et mesuré'));
      expect(find.text('Indisponible'), findsNWidgets(5));
      expect(
        find.text('Aucune densité mesurée le jour du brassage.'),
        findsOneWidget,
      );
      expect(
        find.text('Aucune densité mesurée en fermentation.'),
        findsOneWidget,
      );
      expect(find.text('Dépend des deux densités.'), findsOneWidget);
      expect(find.text('Saisir la densité initiale'), findsWidgets);
      expect(find.text('Saisir le volume en fermenteur'), findsWidgets);
    });

    testWidgets('valeurs retenues, origine, provisoire', (tester) async {
      await fiche(tester, brew: fermentation(), events: [og(), volume(), fg()]);
      await voir(tester, find.text('Prévu et mesuré'));
      expect(find.text('1057,9'), findsOneWidget);
      expect(find.text('1012,0'), findsWidgets);
      expect(find.text('Densité finale (dernière mesure)'), findsOneWidget);
      expect(find.text('provisoire'), findsOneWidget);
      expect(
        find.text('Palier 68 · 8 nov. 15:20 · Dernière mesure'),
        findsNWidgets(2),
      );
      expect(find.text('Relevé J+5 · 13 nov. 18:30'), findsOneWidget);
    });

    testWidgets('VR5 : corriger la densité recalcule, rien n\'est écrit', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: fermentation(),
        events: [og(), fg()],
      );
      await voir(tester, find.text('Prévu et mesuré'));
      final avant = alcoholByVolume(
        originalGravity: 1.0579,
        finalGravity: 1.012,
      );
      expect(find.text(formatDegre(avant)), findsWidgets);
      app.brews.publishEvents('b1', [og(1.06), fg()]);
      await tester.pumpAndSettle();
      final apres = alcoholByVolume(originalGravity: 1.06, finalGravity: 1.012);
      expect(find.text(formatDegre(apres)), findsWidgets);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('VR4 : Changer écrit l\'identifiant et ferme', (tester) async {
      final app = await fiche(
        tester,
        brew: fermentation(),
        events: [
          og(),
          mesure(
            'og2',
            'k-palier',
            MeasureType.gravity,
            1.05,
            brewedAt.add(const Duration(minutes: 30)),
          ),
          fg(),
        ],
      );
      await voir(tester, find.text('Changer').first);
      await tester.tap(find.text('Changer').first);
      await tester.pumpAndSettle();
      expect(find.text('Densité initiale retenue'), findsOneWidget);
      expect(find.text('Dernière mesure (automatique)'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, '1050,0'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'retained');
      expect(write.detail['field'], 'og_event_id');
      expect(write.detail['id'], 'og2');
    });

    testWidgets('RR3 : question des sucres, réponse écrite', (tester) async {
      final app = await fiche(
        tester,
        brew: fermentation(recipe: blondeSucree),
        events: [og(), volume()],
      );
      await voir(
        tester,
        find.text('Les sucres étaient-ils dans le moût à cette mesure ?'),
      );
      expect(
        find.text(
          'Indiquez si les sucres étaient dans le moût à cette mesure.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Oui'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'sugars');
      expect(app.brews.writes.single.detail['value'], isTrue);
    });

    testWidgets('RR3 : recette sans sucre, question absente', (tester) async {
      await fiche(tester, brew: fermentation(), events: [og(), volume()]);
      await voir(tester, find.text('Prévu et mesuré'));
      expect(
        find.text('Les sucres étaient-ils dans le moût à cette mesure ?'),
        findsNothing,
      );
    });

    testWidgets('VR12 : densité finale supérieure, calcul impossible', (
      tester,
    ) async {
      await fiche(tester, brew: fermentation(), events: [og(1.01), fg(1.02)]);
      await voir(tester, find.textContaining('Vérifiez les mesures retenues'));
      expect(find.text('Calcul impossible'), findsOneWidget);
    });

    testWidgets('EM5 : aucun degré après bouteille', (tester) async {
      await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
          recipe: blonde,
        ),
        events: [og(), volume()],
      );
      await voir(tester, find.text('Embouteillage'));
      expect(find.textContaining('après bouteille'), findsNothing);
    });

    testWidgets('contraste du texte, thème clair et sombre', (tester) async {
      await fiche(
        tester,
        brew: fermentation(),
        events: [og(), volume(), fg()],
        height: 2400,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });

    testWidgets('texte à 200 % : aucun débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await fiche(
        tester,
        brew: fermentation(),
        events: [og(), volume(), fg()],
        width: 360,
        height: 1600,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('embouteillage', () {
    testWidgets('EM1 : statut et données, densité finale créée en un lot', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: fermentation(),
        events: [og(), volume()],
      );
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le brassin passera En conditionnement.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('le degré restera indisponible'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité finale (facultatif)'),
        '1,012',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('le degré restera indisponible'),
        findsNothing,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de bouteilles (facultatif)'),
        '60',
      );
      await tester.tap(find.text('Enregistrer l\'embouteillage'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'bottling');
      expect(write.detail['status'], BrewStatus.conditioning);
      expect(write.detail['final_gravity'], 1.012);
      expect(write.detail['bottles_count'], 60);
      // Prix non lus : le coût ne se fige pas (CB8), l'annonce le dit (CB9).
      expect(
        find.text(
          'Embouteillage enregistré. Brassin en conditionnement. '
          'Coût non figé.',
        ),
        findsOneWidget,
      );
      expect(app.costs.writes, isEmpty);
    });

    testWidgets('modification : pas de densité finale, statut inchangé', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
          bottlesCount: 60,
          recipe: blonde,
        ),
      );
      await voir(tester, find.text('Modifier l\'embouteillage'));
      await tester.tap(find.text('Modifier l\'embouteillage'));
      await tester.pumpAndSettle();
      expect(find.text('Densité finale (facultatif)'), findsNothing);
      expect(find.text('60'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.detail['status'], isNull);
      expect(app.brews.writes.single.detail['final_gravity'], isNull);
    });

    testWidgets('EM2 : bouteilles décimales refusées', (tester) async {
      final app = await fiche(tester, brew: fermentation());
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de bouteilles (facultatif)'),
        '1,5',
      );
      await tester.tap(find.text('Enregistrer l\'embouteillage'));
      await tester.pumpAndSettle();
      expect(find.text('Nombre entier attendu.'), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('Annuler avec saisie : confirmation', (tester) async {
      await fiche(tester, brew: fermentation());
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de bouteilles (facultatif)'),
        '60',
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(
        find.text('La saisie de cet embouteillage ne sera pas enregistrée.'),
        findsOneWidget,
      );
    });

    testWidgets('section Embouteillage : champ vide « Non renseigné »', (
      tester,
    ) async {
      await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
          recipe: blonde,
        ),
      );
      await voir(tester, find.text('Embouteillage'));
      expect(find.text('Non renseigné'), findsWidgets);
    });

    testWidgets('liste : En conditionnement, date d\'embouteillage', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([
        unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
        ),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins');
      await tester.pumpAndSettle();
      expect(find.text('Embouteillé le 15 nov. 2026'), findsOneWidget);
    });
  });

  group('corrections de relecture', () {
    testWidgets('R1 : second appui ignoré pendant une action', (tester) async {
      final jeton = Completer<void>();
      final app = TestApp();
      app.auth.tokenGate = jeton;
      await app.pump(tester, height: 1400);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([
        unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
          recipe: blonde,
        ),
      ]);
      app.brews.publishEvents('b1', const []);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marquer comme terminé'));
      await tester.pump();
      await tester.tap(find.text('Marquer comme terminé'));
      await tester.pump();
      expect(app.brews.writes, isEmpty);
      jeton.complete();
      await tester.pumpAndSettle();
      expect(app.brews.writes.length, 1);
    });

    testWidgets('R2 : Changer dès qu\'une mesure peut être retenue', (
      tester,
    ) async {
      await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 10),
          recipe: blonde,
        ),
        // Relevé postérieur à l'embouteillage : aucune densité finale retenue.
        events: [og(), fg()],
      );
      await voir(tester, find.text('Prévu et mesuré'));
      expect(
        find.text('Aucune densité mesurée en fermentation.'),
        findsOneWidget,
      );
      expect(find.text('Changer'), findsNWidgets(2));
    });

    testWidgets('U9 : identifiant supprimé, Dernière mesure retenue', (
      tester,
    ) async {
      await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: brewedAt,
          ogEventId: 'disparu',
          recipe: blonde,
        ),
        events: [og(), fg()],
      );
      await voir(tester, find.text('Changer').first);
      await tester.tap(find.text('Changer').first);
      await tester.pumpAndSettle();
      expect(find.text('Retenue'), findsOneWidget);
      final tuile = find.ancestor(
        of: find.text('Retenue'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: tuile,
          matching: find.text('Dernière mesure (automatique)'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'feuille Changer : seulement des relevés, aucune ligne automatique',
      (tester) async {
        await fiche(tester, brew: fermentation(), events: [fg()]);
        await voir(tester, find.text('Changer').first);
        await tester.tap(find.text('Changer').first);
        await tester.pumpAndSettle();
        expect(find.text('Densité initiale retenue'), findsOneWidget);
        expect(find.text('Dernière mesure (automatique)'), findsNothing);
        expect(find.text('Retenue'), findsNothing);
        expect(find.widgetWithText(ListTile, '1012,0'), findsOneWidget);
      },
    );

    testWidgets('sur téléphone aussi, la ligne dit « non renseigné »', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: brewedAt,
          recipe: const RecipeContent(name: 'Blonde'),
        ),
      );
      await voir(tester, find.text('Prévu et mesuré'));
      expect(
        find.bySemanticsLabel(
          'Densité initiale. Prévu non renseigné. Mesuré indisponible. '
          'Écart non renseigné.',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('un autre membre ne lit pas le jeton', (tester) async {
      final app = await fiche(tester, brew: fermentation(owner: 'uid-zoe'));
      expect(app.auth.tokenReads, 0);
    });

    testWidgets('Modifier réutilise le nom lu au premier affichage', (
      tester,
    ) async {
      final app = await fiche(tester, brew: fermentation());
      expect(app.auth.tokenReads, 1);
      await ouvrirMenu(tester);
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.detail['owner_name'], 'Bruno Brasseur');
      expect(app.auth.tokenReads, 1);
    });

    testWidgets('U1 : avertissement à chaque frappe', (tester) async {
      await fiche(tester, brew: fermentation());
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      final champ = find.widgetWithText(
        TextFormField,
        'Nombre de bouteilles (facultatif)',
      );
      final avertissement = find.textContaining('Nombre inhabituel');
      await tester.enterText(champ, '2');
      await tester.pump();
      expect(avertissement, findsNothing);
      await tester.enterText(champ, '24');
      await tester.pump();
      expect(avertissement, findsNothing);
      await tester.enterText(champ, '240');
      await tester.pump();
      expect(avertissement, findsOneWidget);
      await tester.enterText(champ, '24');
      await tester.pump();
      expect(avertissement, findsNothing);
    });

    testWidgets('U6 : à partir de 600 dp, la ligne nomme ses colonnes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await fiche(tester, brew: fermentation(), width: 1000, height: 2000);
      await voir(tester, find.text('Prévu et mesuré'));
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Densité initiale\. Prévu .*\. Mesuré indisponible\. Écart non renseigné\.$',
          ),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    test('U7 : relevé en attente, annoncé', () {
      final releveEnAttente = Releve(
        gravity: releve('r', MeasureType.gravity, 1.02, jour5, pending: true),
      );
      expect(
        releveParle(releve: releveEnAttente, jour: 5, ecart: null),
        endsWith('en attente du réseau'),
      );
    });

    testWidgets('U8 : Modifier, Annuler confirme si le formulaire a changé', (
      tester,
    ) async {
      await fiche(tester, brew: fermentation());
      await ouvrirMenu(tester);
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom du brassin'),
        'Autre nom',
      );
      await tester.pump();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Les modifications de ce brassin ne seront pas enregistrées.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('U12 : relevé, Annuler confirme si une saisie existe', (
      tester,
    ) async {
      await fiche(tester, brew: fermentation());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer le relevé'), findsNothing);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1,020',
      );
      await tester.pump();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(
        find.text('La saisie de ce relevé ne sera pas enregistrée.'),
        findsOneWidget,
      );
    });

    testWidgets('U14 : valeur refusée, courbe indisponible, liste lisible', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        brew: fermentation(),
        events: [
          releve('r1', MeasureType.gravity, 1.02, jour5),
          releve('r2', MeasureType.gravity, 5, DateTime(2026, 11, 14)),
        ],
      );
      await voir(
        tester,
        find.text('Courbe indisponible : une valeur enregistrée est refusée.'),
      );
      expect(find.text('ven. 13 nov. 18:30 · J+5'), findsOneWidget);
      expect(
        app.errors.reports.where(
          (r) => r.feature == 'brews.fermentation_series',
        ),
        hasLength(1),
      );
    });

    testWidgets('U11 : question des sucres annoncée', (tester) async {
      final semantics = tester.ensureSemantics();
      await fiche(
        tester,
        brew: fermentation(recipe: blondeSucree),
        events: [og(), volume()],
      );
      await voir(tester, find.text('Oui'));
      expect(
        find.bySemanticsLabel(
          RegExp('Les sucres étaient-ils dans le moût à cette mesure ?'),
        ),
        findsWidgets,
      );
      semantics.dispose();
    });

    testWidgets('U15 : date d\'embouteillage nommée', (tester) async {
      final semantics = tester.ensureSemantics();
      await fiche(tester, brew: fermentation());
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('Date d\'embouteillage')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('plis', () {
    testWidgets('téléphone : Recette et calculs prévus fermé', (tester) async {
      await fiche(tester, brew: fermentation());
      await voir(tester, find.text('Recette et calculs prévus'));
      expect(find.text('Calculs'), findsNothing);
      expect(find.text('Amertume'), findsNothing);
    });

    testWidgets(
      'large : Recette et calculs prévus ouvert, Chronologie fermée',
      (tester) async {
        await fiche(tester, brew: fermentation(), width: 1000, height: 1800);
        await voir(tester, find.text('Recette et calculs prévus'));
        expect(find.text('Amertume'), findsWidgets);
      },
    );

    testWidgets('Terminé : invitation à noter pour le propriétaire', (
      tester,
    ) async {
      await fiche(
        tester,
        brew: unBrassin(
          status: BrewStatus.done,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 15),
          recipe: blonde,
        ),
      );
      await voir(tester, find.text('Modifier les notes'));
      expect(
        find.text('Aucune note. Ajoutez votre avis sur cette bière.'),
        findsOneWidget,
      );
    });
  });
}
