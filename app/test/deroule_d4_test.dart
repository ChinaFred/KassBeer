import 'dart:io';

import 'package:brewing/brewing.dart' show HopUse, StepStatus;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/brew_day/domain/plan_du_jour.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/brew_day/presentation/mesure_form.dart';
import 'package:kass_beer/features/brews/domain/assemblage_deroule.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/deroule.dart';
import 'package:kass_beer/features/brews/domain/mesures_retenues.dart';
import 'package:kass_beer/features/brews/domain/releves.dart';
import 'package:kass_beer/features/brews/presentation/brew_detail_screen.dart';
import 'package:kass_beer/features/brews/presentation/brews_providers.dart';
import 'package:kass_beer/features/brews/presentation/section_deroule.dart';
import 'package:kass_beer/features/brews/presentation/releve_fermentation.dart';
import 'package:kass_beer/features/costs/domain/brew_cost.dart';
import 'package:kass_beer/features/processes/domain/modele_exemple.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

/// Lot D4 d'ADR-010 : journées 2 et suivantes (« Préparer la journée », écran
/// de la journée, « Terminer la journée », embouteillage, mesures en
/// `phase: 'fermentation'`, fiche).

String Function() cles(String prefixe) {
  var n = 0;
  return () => '$prefixe-${n++}';
}

const cascade = HopLine(
  name: 'Cascade',
  amount: Quantite.grammes(20),
  use: HopUse.dryHop,
  form: 'pellet',
);

const recetteAvecCru = RecipeContent(
  name: 'Blonde',
  brewSteps: [palier, ebullition],
  hops: [cascade],
);

/// Brassage (J+0), Houblonnage à cru (J+4), Embouteillage (J+14).
Deroule derouleExemple() => assemblerDeroule(
  templateId: 'p1',
  modele: modeleExemple(cles('p1')),
  recipe: recetteAvecCru,
  nouvelleCle: cles('d'),
).deroule;

final deroule = derouleExemple();
final cru = deroule.journees[1];
final embout = deroule.journees[2];

/// Brassé le 4 nov. à 10:00 : le houblonnage tombe le 8 nov., jour de l'horloge
/// de [TestApp] (12:10).
final brasse = DateTime(2026, 11, 4, 10);

Brew enFermentation({
  BrewStatus status = BrewStatus.fermenting,
  DateTime? bottledAt,
  String owner = 'uid-brasseur',
}) => unBrassin(
  status: status,
  owner: owner,
  brewedAt: brasse,
  bottledAt: bottledAt,
  recipe: recetteAvecCru,
  process: deroule,
);

BrewEvent mesureJournee(
  String id,
  String? stepKey,
  MeasureType type,
  double value,
  DateTime at,
) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.measurement,
  stepKey: stepKey,
  measureType: type,
  value: value,
  measuredAt: at,
  phase: PhaseEvenement.fermentation,
);

Future<TestApp> ouvrir(
  WidgetTester tester,
  String path, {
  Brew? brew,
  List<BrewEvent> events = const [],
  bool owner = true,
  bool server = true,
}) async {
  final app = TestApp();
  app.brews.serverReachable = server;
  await app.pump(tester);
  app.signIn(
    owner ? brewerUser : adminUser,
    member: owner ? brewerMember : adminMember,
  );
  app.brews.publish([brew ?? enFermentation()]);
  app.brews.publishEvents('b1', events);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

/// Prix, frais et coût figé (absent) du brasseur, lus par l'appareil.
void publierCouts(TestApp app) {
  app.costs.publishPrices('uid-brasseur', const []);
  app.costs.publishFees('uid-brasseur', const []);
  app.costs
      .brewCostOf('uid-brasseur', 'b1')
      .add(const DocumentAbsent<BrewCost>());
}

void main() {
  group('PlanDuJour par journée', () {
    final now = DateTime(2026, 11, 8, 12, 10);
    final premiere = cru.lignes.first;

    test('journée 2 commencée : brassage intact, départ au premier début', () {
      final events = [debut('e1', premiere.key, DateTime(2026, 11, 8, 12))];
      final brew = enFermentation();
      final brassage = PlanDuJour.calculer(
        brew: brew,
        events: events,
        now: now,
      );
      // Un début de la journée 2 ne rend aucune étape du brassage « Non faite ».
      expect(
        brassage.lignes.map((l) => l.status),
        everyElement(StepStatus.pending),
      );
      expect(brassage.anomalies, isEmpty);
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: events,
        now: now,
        journee: cru,
      );
      expect(plan.lignes.length, cru.lignes.length);
      expect(plan.enCours?.step.key, premiere.key);
      expect(plan.anomalies, isEmpty);
      expect(plan.commencee, isTrue);
      // Désinfection 10 min depuis 12:00, puis mesure 5, ajout 0, nettoyage 10.
      expect(plan.finPrevue, DateTime(2026, 11, 8, 12, 25));
    });

    test(
      'journée 2 pas commencée : départ prévu à l\'heure de l\'appareil',
      () {
        final plan = PlanDuJour.calculer(
          brew: enFermentation(),
          events: const [],
          now: now,
          journee: cru,
        );
        expect(plan.commencee, isFalse);
        expect(plan.lignes.first.schedule.expectedStart, now);
        expect(plan.finPrevue, now.add(const Duration(minutes: 25)));
      },
    );

    test('mesures : sous l\'étape de la journée, jamais dans le brassage', () {
      final mesureCle = cru.lignes[1].key;
      final events = [
        mesureJournee(
          'm1',
          mesureCle,
          MeasureType.gravity,
          1.012,
          DateTime(2026, 11, 8, 9, 20),
        ),
        // Relevé sans étape du jour : « Sans étape » de la journée.
        releve('r1', MeasureType.temperature, 18, DateTime(2026, 11, 8, 8)),
        // Relevé de la veille : hors de la journée.
        releve('r2', MeasureType.gravity, 1.020, DateTime(2026, 11, 7, 8)),
      ];
      final brew = enFermentation();
      final plan = PlanDuJour.calculer(
        brew: brew,
        events: events,
        now: now,
        journee: cru,
      );
      expect(plan.lignes[1].mesures.map((e) => e.id), ['m1']);
      expect(plan.mesuresSansEtape.map((e) => e.id), ['r1']);
      final brassage = PlanDuJour.calculer(
        brew: brew,
        events: events,
        now: now,
      );
      expect(brassage.lignes.expand((l) => l.mesures), isEmpty);
      expect(brassage.mesuresSansEtape, isEmpty);
    });

    test(
      'journée terminée : embouteillage par la date, autre par les étapes',
      () {
        final brew = enFermentation();
        final events = [
          for (final (i, l) in cru.lignes.indexed)
            saut('s$i', l.key, DateTime(2026, 11, 8, 12)),
        ];
        final plan = PlanDuJour.calculer(
          brew: brew,
          events: events,
          now: now,
          journee: cru,
        );
        expect(journeeTerminee(brew: brew, journee: cru, plan: plan), isTrue);
        expect(journeeTerminee(brew: brew, journee: cru, plan: null), isFalse);
        expect(
          journeeTerminee(brew: brew, journee: embout, plan: plan),
          isFalse,
        );
        expect(
          journeeTerminee(
            brew: enFermentation(bottledAt: DateTime(2026, 11, 18)),
            journee: embout,
            plan: null,
          ),
          isTrue,
        );
      },
    );

    test('densité d\'une journée 2 : densité finale, jamais initiale', () {
      final brew = enFermentation();
      final retenues = MesuresRetenues.de(brew, [
        mesure('og', 'k-palier', MeasureType.gravity, 1.050, brasse),
        mesureJournee(
          'j2',
          cru.lignes[1].key,
          MeasureType.gravity,
          1.012,
          DateTime(2026, 11, 8, 9),
        ),
      ]);
      expect(retenues.densiteInitiale?.event.id, 'og');
      expect(retenues.densiteFinale?.event.id, 'j2');
      final seule = MesuresRetenues.de(brew, [
        mesureJournee(
          'j2',
          cru.lignes[1].key,
          MeasureType.gravity,
          1.012,
          DateTime(2026, 11, 8, 9),
        ),
      ]);
      expect(seule.densiteInitiale, isNull);
    });

    test('Deroule.etape et journee : recherche par clé', () {
      final trouvee = deroule.etape(cru.lignes[1].key);
      expect(trouvee?.journee.key, cru.key);
      expect(trouvee?.ligne.name, 'Mesure de densité');
      expect(deroule.etape('inconnue'), isNull);
      expect(deroule.journee(embout.key)?.role, RoleJournee.embouteillage);
      expect(deroule.embouteillage?.key, embout.key);
    });
  });

  group('Préparer la journée', () {
    String chemin(String key) => '/brassins/b1/jour/$key/preparer';

    Future<void> refus(
      WidgetTester tester,
      String message, {
      Brew? brew,
      String? key,
      bool owner = true,
    }) async {
      final app = await ouvrir(
        tester,
        chemin(key ?? cru.key),
        brew: brew,
        owner: owner,
      );
      expect(find.text(message), findsOneWidget);
      expect(find.text('Voir le brassin'), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    }

    testWidgets('autre membre : refusé', (tester) async {
      await refus(tester, TextesJournee.notOwner, owner: false);
    });

    testWidgets('brassage pas fini : refusé', (tester) async {
      await refus(
        tester,
        TextesJournee.apresBrassage,
        brew: enFermentation(status: BrewStatus.brewing),
      );
    });

    testWidgets('embouteillage fait : refusé', (tester) async {
      await refus(
        tester,
        TextesJournee.terminee,
        key: embout.key,
        brew: enFermentation(
          status: BrewStatus.conditioning,
          bottledAt: DateTime(2026, 11, 8),
        ),
      );
    });

    testWidgets('brassin terminé : refusé', (tester) async {
      await refus(
        tester,
        TextesJournee.brassinTermine,
        brew: enFermentation(status: BrewStatus.done),
      );
    });

    testWidgets('brassin abandonné : refusé', (tester) async {
      await refus(
        tester,
        TextesJournee.brassinAbandonne,
        brew: enFermentation(status: BrewStatus.abandoned),
      );
    });

    testWidgets('clé inconnue : refusée', (tester) async {
      await refus(tester, TextesJournee.inconnue, key: 'inconnue');
    });

    testWidgets('Commencer la journée : premier début seul, aucun statut', (
      tester,
    ) async {
      final app = await ouvrir(tester, chemin(cru.key));
      expect(
        find.text('Blonde du jour · Houblonnage à cru · prévue aujourd\'hui'),
        findsOneWidget,
      );
      expect(find.text('Brassin et déroulé figé'), findsOneWidget);
      expect(
        find.text('4 étapes · 25${nbsp}min · fin vers 12:35'),
        findsOneWidget,
      );
      expect(
        find.text('Tout est prêt. Vous pouvez couper le réseau.'),
        findsOneWidget,
      );
      expect(find.text('Prix et frais'), findsNothing);
      await tester.ensureVisible(find.text(TextesJournee.commencer));
      await tester.tap(find.text(TextesJournee.commencer));
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'steps');
      expect(write.detail['writes'], ['step_started:${cru.lignes.first.key}']);
      expect(app.alerte.prepared, 1);
      expect(find.text('Houblonnage à cru · 12:10'), findsOneWidget);
    });

    testWidgets('journée commencée : Reprendre, rien d\'écrit', (tester) async {
      final app = await ouvrir(
        tester,
        chemin(cru.key),
        events: [debut('e1', cru.lignes.first.key, DateTime(2026, 11, 8, 12))],
      );
      await tester.ensureVisible(find.text(TextesJournee.reprendre));
      await tester.tap(find.text(TextesJournee.reprendre));
      await tester.pumpAndSettle();
      expect(app.brews.writes, isEmpty);
      expect(find.text('Houblonnage à cru · 12:10'), findsOneWidget);
    });

    testWidgets('sans réseau : préparation impossible, date prévue rappelée', (
      tester,
    ) async {
      await ouvrir(tester, chemin(embout.key), server: false);
      expect(
        find.textContaining('Préparation impossible sans réseau.'),
        findsOneWidget,
      );
      // Embouteillage à J+14, le 18 nov. ; houblonnage du jour pas terminé.
      expect(
        find.text(TextesJournee.prevueLe(DateTime(2026, 11, 18))),
        findsOneWidget,
      );
      expect(
        find.text(TextesJournee.nonTerminee('Houblonnage à cru')),
        findsOneWidget,
      );
      expect(find.text(TextesJournee.prixIndisponibles), findsOneWidget);
    });

    testWidgets('embouteillage : prix et frais lus sur l\'appareil', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      publierCouts(app);
      app.brews.publish([enFermentation()]);
      app.brews.publishEvents('b1', const []);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(chemin(embout.key));
      await tester.pumpAndSettle();
      expect(find.text(TextesJournee.prixLus), findsOneWidget);
    });
  });

  group('écran de la journée', () {
    String chemin(String key) => '/brassins/b1/jour/$key';
    final debutCru = DateTime(2026, 11, 8, 12);

    testWidgets('Terminer la journée : un lot de fins et de sauts', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        chemin(cru.key),
        events: [debut('e1', cru.lignes.first.key, debutCru)],
      );
      expect(find.text('Houblonnage à cru · 12:10'), findsOneWidget);
      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      expect(find.text('Terminer le brassage'), findsNothing);
      await tester.tap(find.text(TextesJournee.terminer));
      await tester.pumpAndSettle();
      expect(
        find.text(TextesJournee.terminerTitre('Houblonnage à cru')),
        findsOneWidget,
      );
      expect(find.text(TextesJournee.continuer), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, TextesJournee.terminer),
      );
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'steps');
      expect(write.detail['writes'], [
        'step_ended:${cru.lignes[0].key}',
        for (final l in cru.lignes.skip(1)) 'step_skipped:${l.key}',
      ]);
      expect(app.brews.writes.where((w) => w.kind == 'status'), isEmpty);
      expect(
        find.text(TextesJournee.journeeTerminee('Houblonnage à cru')),
        findsOneWidget,
      );
      expect(find.byType(BrewDetailScreen), findsOneWidget);
    });

    testWidgets(
      'toutes les étapes faites : journée terminée, sans confirmation',
      (tester) async {
        await ouvrir(
          tester,
          chemin(cru.key),
          events: [
            for (final (i, l) in cru.lignes.indexed)
              saut('s$i', l.key, debutCru),
          ],
        );
        expect(find.text(TextesJournee.toutFait), findsOneWidget);
        await tester.tap(find.text(TextesJournee.revenir));
        await tester.pumpAndSettle();
        expect(find.byType(BrewDetailScreen), findsOneWidget);
      },
    );

    testWidgets('dernière étape en cours : Terminer la journée en bas, sans '
        'confirmation', (tester) async {
      final derniere = cru.lignes.last;
      final app = await ouvrir(
        tester,
        chemin(cru.key),
        events: [
          for (final (i, l) in cru.lignes.indexed)
            if (l.key != derniere.key) saut('s$i', l.key, debutCru),
          debut('e1', derniere.key, debutCru),
        ],
      );
      await tester.tap(
        find.widgetWithText(FilledButton, TextesJournee.terminer),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(TextesJournee.terminerTitre('Houblonnage à cru')),
        findsNothing,
      );
      expect(app.brews.writes.single.detail['writes'], [
        'step_ended:${derniere.key}',
      ]);
      expect(find.byType(BrewDetailScreen), findsOneWidget);
    });

    testWidgets('embouteillage, tout fait : Embouteiller en bas, sans '
        'confirmation', (tester) async {
      await ouvrir(
        tester,
        chemin(embout.key),
        events: [
          for (final (i, l) in embout.lignes.indexed)
            saut('s$i', l.key, debutCru),
        ],
      );
      expect(find.text('Toutes les étapes sont faites.'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, TextesJournee.embouteiller),
      );
      await tester.pumpAndSettle();
      expect(find.text(TextesJournee.embouteillerTitre), findsNothing);
      expect(find.text("Enregistrer l'embouteillage"), findsOneWidget);
    });

    testWidgets('mesure : phase fermentation, étapes de la journée, aide', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        chemin(cru.key),
        events: [debut('e1', cru.lignes.first.key, debutCru)],
      );
      await tester.tap(find.text('Mesure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Densité'));
      await tester.pumpAndSettle();
      expect(find.text(kMesureComptee), findsOneWidget);
      // Liste « Étape » : les seules étapes de la journée.
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      expect(find.text('Mesure de densité'), findsWidgets);
      expect(find.text('Palier 68'), findsNothing);
      await tester.tap(find.text('Mesure de densité').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1012',
      );
      await tester.tap(find.text('Enregistrer la mesure'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.singleWhere((w) => w.kind == 'event');
      expect(write.detail['phase'], 'fermentation');
      expect(write.detail['step'], cru.lignes[1].key);
      expect(find.text('Mesure enregistrée.'), findsOneWidget);
    });

    testWidgets('mesure du jour de brassage : sans phase', (tester) async {
      final app = await ouvrir(
        tester,
        '/brassins/b1/jour',
        brew: unBrassin(
          brewedAt: DateTime(2026, 11, 8, 11),
          recipe: recetteAvecCru,
          process: deroule,
        ),
      );
      await tester.tap(find.text('Mesure'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Densité'));
      await tester.pumpAndSettle();
      expect(find.text(kMesureComptee), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1050',
      );
      await tester.tap(find.text('Enregistrer la mesure'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.singleWhere((w) => w.kind == 'event');
      expect(write.detail['phase'], isNull);
    });

    testWidgets(
      'hors ligne : début d\'étape écrit sur l\'appareil, rien d\'attendu',
      (tester) async {
        final app = TestApp();
        await app.pump(tester);
        app.signIn(brewerUser, member: brewerMember, fromCache: true);
        app.brews.publish([enFermentation()], fromCache: true);
        app.brews.publishEvents('b1', const [], fromCache: true);
        await tester.pumpAndSettle();
        app.container.read(routerProvider).go(chemin(cru.key));
        await tester.pumpAndSettle();
        expect(find.text('Houblonnage à cru · 12:10'), findsOneWidget);
        await tester.tap(find.text('Commencer l\'étape'));
        await tester.pumpAndSettle();
        final write = app.brews.writes.single;
        expect(write.detail['writes'], [
          'step_started:${cru.lignes.first.key}',
        ]);
        expect(app.brews.prepareCalls, 0);
      },
    );

    testWidgets(
      'Embouteiller : confirmation, formulaire, retour sur la fiche',
      (tester) async {
        final app = TestApp();
        await app.pump(tester);
        app.signIn(brewerUser, member: brewerMember);
        publierCouts(app);
        app.brews.publish([enFermentation()]);
        app.brews.publishEvents('b1', const []);
        await tester.pumpAndSettle();
        app.container.read(routerProvider).go(chemin(embout.key));
        await tester.pumpAndSettle();
        expect(find.text('Embouteillage · 12:10'), findsOneWidget);
        await tester.tap(find.byTooltip('Plus d\'actions'));
        await tester.pumpAndSettle();
        expect(find.text(TextesJournee.terminer), findsNothing);
        await tester.tap(find.text(TextesJournee.embouteiller).last);
        await tester.pumpAndSettle();
        expect(find.text(TextesJournee.embouteillerTitre), findsOneWidget);
        await tester.tap(
          find.widgetWithText(FilledButton, TextesJournee.embouteiller),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Le brassin passera En conditionnement.'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text("Enregistrer l'embouteillage"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("Enregistrer l'embouteillage"));
        await tester.pumpAndSettle();
        final write = app.brews.writes.singleWhere((w) => w.kind == 'bottling');
        expect(write.detail['status'], BrewStatus.conditioning);
        // Aucune écriture d'étape : les étapes restent non faites.
        expect(app.brews.writes.where((w) => w.kind == 'steps'), isEmpty);
        expect(find.byType(BrewDetailScreen), findsOneWidget);
        expect(
          find.textContaining(BrewDetailScreen.embouteillageEnregistre),
          findsOneWidget,
        );
        // Annonce faite après l'affichage de la fiche : la mémoire est vide.
        expect(app.container.read(embouteillagesAAnnoncerProvider), isEmpty);
      },
    );

    testWidgets('Embouteiller pendant une étape : l\'étape se termine', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      publierCouts(app);
      app.brews.publish([enFermentation()]);
      final enCours = embout.lignes.first;
      app.brews.publishEvents('b1', [
        debut('e1', enCours.key, DateTime(2026, 11, 8, 12)),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(chemin(embout.key));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextesJournee.embouteiller).last);
      await tester.pumpAndSettle();
      expect(
        find.text(TextesJournee.embouteillerEnCoursMessage),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, TextesJournee.embouteiller),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text("Enregistrer l'embouteillage"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Enregistrer l'embouteillage"));
      await tester.pumpAndSettle();
      final steps = app.brews.writes.singleWhere((w) => w.kind == 'steps');
      expect(steps.detail['writes'], ['step_ended:${enCours.key}']);
      expect(app.brews.writes.where((w) => w.kind == 'bottling'), hasLength(1));
      expect(find.byType(BrewDetailScreen), findsOneWidget);
    });

    testWidgets('autre membre : lecture seule', (tester) async {
      await ouvrir(tester, chemin(cru.key), owner: false);
      expect(find.text(TextesJournee.notOwner), findsOneWidget);
    });
  });

  group('fiche', () {
    testWidgets('prochaine journée : Préparer, date, Embouteiller dans ⋮', (
      tester,
    ) async {
      await ouvrir(tester, '/brassins/b1');
      expect(find.text(BrewDetailScreen.prevueAujourdhui), findsOneWidget);
      expect(
        find.text(TextesJournee.preparer('Houblonnage à cru')),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Embouteiller'), findsNothing);
      await tester.tap(find.byTooltip('Plus d\'actions'));
      await tester.pumpAndSettle();
      expect(
        find.text(BrewDetailScreen.embouteillerSansJournee),
        findsOneWidget,
      );
      // « Embouteiller sans suivre la journée » ouvre le formulaire de la fiche.
      await tester.tap(find.text(BrewDetailScreen.embouteillerSansJournee));
      await tester.pumpAndSettle();
      expect(find.text("Enregistrer l'embouteillage"), findsOneWidget);
    });

    testWidgets('événements du cache sans document : aucune journée proposée', (
      tester,
    ) async {
      final app = await ouvrir(tester, '/brassins/b1');
      app.brews.publishEvents('b1', const [], fromCache: true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Préparer la journée'), findsNothing);
      app.brews.publishEvents('b1', const []);
      await tester.pumpAndSettle();
      expect(
        find.text(TextesJournee.preparer('Houblonnage à cru')),
        findsOneWidget,
      );
    });

    testWidgets('embouteillé : journée placée après, Marquer secondaire', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/brassins/b1',
        brew: unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brasse,
          bottledAt: DateTime(2026, 11, 7),
          recipe: recetteAvecCru,
          process: deroule.avecEcart(cru.key, 20, SourceEcart.brasseur),
        ),
      );
      expect(
        find.text(TextesJournee.preparer('Houblonnage à cru')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Marquer comme terminé'),
        findsOneWidget,
      );
    });

    testWidgets('embouteillé sans journée après : rien proposé', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/brassins/b1',
        brew: enFermentation(
          status: BrewStatus.conditioning,
          bottledAt: DateTime(2026, 11, 7),
        ),
      );
      expect(find.textContaining('Préparer la journée'), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Marquer comme terminé'),
        findsOneWidget,
      );
    });

    testWidgets('Préparer la journée depuis la fiche', (tester) async {
      await ouvrir(tester, '/brassins/b1');
      await tester.tap(find.text(TextesJournee.preparer('Houblonnage à cru')));
      await tester.pumpAndSettle();
      expect(find.text(TextesJournee.commencer), findsOneWidget);
    });

    testWidgets('journée commencée : Reprendre, chronologie sous la journée', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/brassins/b1',
        events: [
          debut('e1', cru.lignes.first.key, DateTime(2026, 11, 8, 12)),
          mesureJournee(
            'm1',
            cru.lignes[1].key,
            MeasureType.gravity,
            1.012,
            DateTime(2026, 11, 8, 9, 20),
          ),
        ],
      );
      expect(
        find.text(TextesJournee.reprendreNom('Houblonnage à cru')),
        findsOneWidget,
      );
      // Relevé : « … · J+4 · Houblonnage à cru : Mesure de densité ».
      expect(
        find.textContaining('J+4 · Houblonnage à cru : Mesure de densité'),
        findsOneWidget,
      );
    });

    testWidgets('houblonnage terminé : Préparer l\'embouteillage', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/brassins/b1',
        events: [
          for (final (i, l) in cru.lignes.indexed)
            saut('s$i', l.key, DateTime(2026, 11, 8, 12)),
        ],
      );
      expect(
        find.text(TextesJournee.preparer('Embouteillage')),
        findsOneWidget,
      );
      expect(
        find.text(BrewDetailScreen.prevueLe(DateTime(2026, 11, 18))),
        findsOneWidget,
      );
    });

    /// Ouvre le pli « Déroulé » de la fiche d'un brassin après le brassage.
    Future<void> ouvrirDeroule(WidgetTester tester) async {
      final pli = find.text(TextesDeroule.titre);
      await tester.scrollUntilVisible(
        pli,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(pli.first);
      await tester.pumpAndSettle();
      await tester.tap(pli.first);
      await tester.pumpAndSettle();
    }

    testWidgets('Passer la journée : sauts en un lot, annonce, pas pour '
        'l\'embouteillage', (tester) async {
      final app = await ouvrir(tester, '/brassins/b1');
      await ouvrirDeroule(tester);
      expect(
        find.byTooltip('Actions de la journée Embouteillage'),
        findsNothing,
      );
      final menu = find.byTooltip('Actions de la journée Houblonnage à cru');
      // Au milieu de l'écran : le bouton flottant couvre le bas de la fiche.
      await Scrollable.ensureVisible(tester.element(menu), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextesDeroule.passer));
      await tester.pumpAndSettle();
      expect(
        find.text(TextesDeroule.passerTitre('Houblonnage à cru')),
        findsOneWidget,
      );
      expect(find.text(TextesDeroule.passerMessage), findsOneWidget);
      expect(find.text(TextesDeroule.garder), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, TextesDeroule.passer));
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'steps');
      expect(write.detail['writes'], [
        for (final l in cru.lignes) 'step_skipped:${l.key}',
      ]);
      expect(
        find.text(TextesDeroule.passee('Houblonnage à cru')),
        findsOneWidget,
      );
    });

    testWidgets('journée terminée : résumé « Terminée · … », plus de Passer', (
      tester,
    ) async {
      final premiere = cru.lignes.first;
      await ouvrir(
        tester,
        '/brassins/b1',
        events: [
          debut('e0', premiere.key, DateTime(2026, 11, 8, 11)),
          fin('f0', premiere.key, DateTime(2026, 11, 8, 11, 10)),
          for (final (i, l) in cru.lignes.indexed)
            if (l.key != premiere.key)
              saut('s$i', l.key, DateTime(2026, 11, 8, 12)),
        ],
      );
      await ouvrirDeroule(tester);
      expect(find.text('Terminée · 1 faite, 3 sautées'), findsOneWidget);
      expect(
        find.byTooltip('Actions de la journée Houblonnage à cru'),
        findsNothing,
      );
    });

    testWidgets('autre membre : aucun bouton de journée', (tester) async {
      await ouvrir(tester, '/brassins/b1', owner: false);
      expect(
        find.text(TextesJournee.preparer('Houblonnage à cru')),
        findsNothing,
      );
    });
  });

  test(
    'relevé : la journée et l\'étape d\'un relevé saisi pendant une journée',
    () {
      final brew = enFermentation();
      final avecEtape = relevesDe([
        mesureJournee(
          'm1',
          cru.lignes[1].key,
          MeasureType.gravity,
          1.012,
          DateTime(2026, 11, 8, 9, 20),
        ),
      ]).single;
      expect(
        etapeDuReleve(brew, avecEtape),
        'Houblonnage à cru : Mesure de densité',
      );
      final sansEtape = relevesDe([
        releve('r1', MeasureType.gravity, 1.012, DateTime(2026, 11, 8)),
      ]).single;
      expect(etapeDuReleve(brew, sansEtape), isNull);
    },
  );

  test('résumé d\'une journée terminée : comptes réels, « Terminée » seul', () {
    final brew = enFermentation(bottledAt: DateTime(2026, 11, 18));
    final now = DateTime(2026, 11, 18, 12);
    final rien = PlanDuJour.calculer(
      brew: brew,
      events: const [],
      now: now,
      journee: embout,
    );
    expect(resumeJourneeTerminee(rien), 'Terminée · 6 non faites');
    expect(resumeJourneeTerminee(null), 'Terminée');
    final sautees = PlanDuJour.calculer(
      brew: brew,
      events: [
        for (final (i, l) in cru.lignes.indexed) saut('s$i', l.key, now),
      ],
      now: now,
      journee: cru,
    );
    expect(resumeJourneeTerminee(sautees), 'Terminée · 4 sautées');
  });

  test('P2 : aucune transaction, lecture du serveur ni requête HTTP dans ce '
      'qu\'appellent les journées', () {
    final fichiers = [
      'lib/features/brew_day/domain/plan_du_jour.dart',
      'lib/features/brew_day/presentation/brew_day_screen.dart',
      'lib/features/brew_day/presentation/prepare_brew_screen.dart',
      'lib/features/brew_day/presentation/chronologie_jour.dart',
      'lib/features/brew_day/presentation/mesure_form.dart',
      'lib/features/brew_day/presentation/indicateur_envoi.dart',
      'lib/features/brews/presentation/embouteillage.dart',
      'lib/features/costs/data/figeage_embouteillage.dart',
    ];
    final offenders = <String>[];
    for (final f in fichiers) {
      final code = File(f).readAsLinesSync().map((l) => l.split('//').first);
      for (final line in code) {
        if (RegExp(
          r'runTransaction|Source\.server|package:http|HttpClient|httpsCallable|arrayUnion',
        ).hasMatch(line)) {
          offenders.add('$f : $line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
