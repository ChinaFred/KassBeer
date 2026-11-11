import 'package:brewing/brewing.dart' show HopUse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/brews/domain/assemblage_deroule.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/deroule.dart';
import 'package:kass_beer/features/brews/presentation/brew_detail_screen.dart';
import 'package:kass_beer/features/brews/presentation/brews_screen.dart';
import 'package:kass_beer/features/brews/presentation/choix_processus.dart';
import 'package:kass_beer/features/brews/presentation/libelles_deroule.dart';
import 'package:kass_beer/features/brews/presentation/new_brew_form.dart';
import 'package:kass_beer/features/brews/presentation/section_deroule.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/processes/domain/modele_exemple.dart';
import 'package:kass_beer/features/processes/domain/modele_processus.dart';
import 'package:kass_beer/features/recipes/domain/chronologie.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

/// Lot D3 d'ADR-009 : assemblage du déroulé, « Nouveau brassin », fiche, liste,
/// « Préparer le brassage » et écran du jour avec un processus.

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

ModeleProcessus exemple({String id = 'p1', String owner = 'uid-brasseur'}) =>
    ModeleProcessus(
      id: id,
      ownerUid: owner,
      ownerName: 'Bruno Brasseur',
      content: modeleExemple(cles(id)),
    );

Deroule derouleExemple([RecipeContent recipe = recetteAvecCru]) =>
    assemblerDeroule(
      templateId: 'p1',
      modele: exemple().content,
      recipe: recipe,
      nouvelleCle: cles('d'),
    ).deroule;

/// Fait défiler la fiche jusqu'à [finder], puis l'amène à l'écran.
Future<void> voir(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('assemblage', () {
    test('clés uniques, clés de la recette gardées, libellés', () {
      final assemble = assemblerDeroule(
        templateId: 'p1',
        modele: exemple().content,
        recipe: recetteAvecCru,
        nouvelleCle: cles('d'),
      );
      final d = assemble.deroule;
      expect(erreurDeroule(d), isNull);
      expect(d.templateId, 'p1');
      expect(d.templateName, kNomModeleExemple);
      expect(
        [for (final j in d.journees) j.name],
        ['Brassage', 'Houblonnage à cru', 'Embouteillage'],
      );
      expect([for (final j in d.journees) j.offsetDays], [0, 4, 14]);
      expect(
        [for (final j in d.journees) j.role],
        [RoleJournee.brassage, RoleJournee.autre, RoleJournee.embouteillage],
      );
      final toutes = [for (final l in d.lignes) l.key];
      expect(toutes.toSet().length, toutes.length);
      final brassage = d.brassage!;
      expect(brassage.lignes.map((l) => l.key), containsAll(['k-palier']));
      final recette = [
        for (final e in brassage.etapes)
          if (e.origine == OrigineEtape.chronologieRecette) e.ligne,
      ];
      expect(recette, [palier, ebullition]);
      final premiere = brassage.etapes.first;
      expect(premiere.ligne.name, 'Mise en place du matériel');
      expect(premiere.origine, OrigineEtape.modele);
      expect(premiere.cleEtapeModele, isNotNull);
      final cru = d.journees[1].etapes.where(
        (e) => e.origine == OrigineEtape.houblonsACru,
      );
      expect(cru.single.ligne.name, 'Ajouter Cascade 20${nbsp}g');
      expect(cru.single.ligne.durationMin, 0);
      expect(d.journees[1].cleJourneeModele, isNotNull);
      expect(assemble.annonces, isEmpty);
      // Relu tel qu'écrit : aucune perte.
      final relu = lireDeroule(d.toFirestore());
      expect(relu.probleme, isNull);
      expect(relu.lignes.length, d.lignes.length);
    });

    test('recette sans houblon à cru : journée retirée, annoncée', () {
      final assemble = assemblerDeroule(
        templateId: 'p1',
        modele: exemple().content,
        recipe: const RecipeContent(name: 'Blonde', brewSteps: [palier]),
        nouvelleCle: cles('d'),
      );
      expect(assemble.deroule.journees.length, 2);
      expect(assemble.annonces, [
        'Recette sans houblon à cru : pas de journée « Houblonnage à cru ».',
      ]);
    });

    test('chronologie vide : préremplissage nommé et annoncé', () {
      final assemble = assemblerDeroule(
        templateId: 'p1',
        modele: exemple().content,
        recipe: const RecipeContent(
          name: 'Blonde',
          boilTimeMin: 60,
          mashSteps: [MashStep(name: 'Empâtage', tempC: 67, durationMin: 60)],
        ),
        nouvelleCle: cles('d'),
      );
      final noms = assemble.deroule.brassage!.lignes.map((l) => l.name);
      expect(noms, containsAllInOrder(['Empâtage', 'Ébullition']));
      expect(
        assemble.annonces.first,
        'Chronologie de la recette vide : paliers et ébullition préremplis.',
      );
    });

    test('jours de la recette : deux journées numérotées, source recette', () {
      final d = derouleExemple(
        const RecipeContent(
          name: 'Blonde',
          hops: [
            HopLine(
              name: 'Citra',
              amount: Quantite.grammes(30),
              use: HopUse.dryHop,
              form: 'pellet',
              dayMin: 3 * 1440,
            ),
            HopLine(
              name: 'Mosaic',
              amount: Quantite.grammes(25),
              use: HopUse.dryHop,
              form: 'pellet',
              dayMin: 6 * 1440,
            ),
          ],
        ),
      );
      final cru = d.journees.where((j) => j.name.startsWith('Houblonnage'));
      expect(cru.map((j) => j.name), [
        'Houblonnage à cru 1',
        'Houblonnage à cru 2',
      ]);
      expect(cru.map((j) => j.offsetDays), [3, 6]);
      expect(cru.map((j) => j.sourceEcart), everyElement(SourceEcart.recette));
    });

    test('chronologie de la recette illisible : refusée, sans repli', () {
      expect(
        () => assemblerDeroule(
          templateId: 'p1',
          modele: exemple().content,
          recipe: const RecipeContent(
            name: 'Blonde',
            brewStepsProblem: 'clé absente (0)',
          ),
          nouvelleCle: cles('d'),
        ),
        throwsA(isA<AssemblageImpossible>()),
      );
    });

    test('date changée : tri par écart, brassage en tête, rétablissable', () {
      final d = derouleExemple();
      final cru = d.journees[1];
      final change = d.avecEcart(cru.key, 20, SourceEcart.brasseur);
      expect(
        [for (final j in change.journees) j.name],
        ['Brassage', 'Embouteillage', 'Houblonnage à cru'],
      );
      expect(change.journees.last.sourceEcart, SourceEcart.brasseur);
      expect(erreurDeroule(change), isNull);
      expect(
        () => d.avecEcart(d.brassage!.key, 3, SourceEcart.brasseur),
        throwsStateError,
      );
      final retour = ecartDuProcessus(change.journees.last, derouleExemple());
      expect(retour, (offset: 4, source: SourceEcart.modele));
    });

    test('prochaine journée d\'après les dates seules', () {
      final d = derouleExemple();
      final brassin = unBrassin(
        status: BrewStatus.fermenting,
        brewedAt: DateTime(2026, 11, 4, 9),
        process: d,
      );
      expect(
        prochaineJourneePrevue(
          brassin,
          DateTime(2026, 11, 8, 12),
        )?.journee.name,
        'Houblonnage à cru',
      );
      expect(
        prochaineJourneePrevue(brassin, DateTime(2026, 11, 9, 8))?.journee.name,
        'Embouteillage',
      );
      final embouteille = unBrassin(
        status: BrewStatus.conditioning,
        brewedAt: DateTime(2026, 11, 4, 9),
        bottledAt: DateTime(2026, 11, 10),
        process: d,
      );
      expect(
        prochaineJourneePrevue(embouteille, DateTime(2026, 11, 10)),
        isNull,
      );
      expect(
        prochaineJourneePrevue(
          unBrassin(status: BrewStatus.fermenting),
          DateTime(2026, 11, 8),
        ),
        isNull,
      );
    });
  });

  group('Nouveau brassin', () {
    const equipment = Equipment(
      id: 'e1',
      ownerUid: 'uid-brasseur',
      content: equipementTest,
    );
    final recette = Recipe(
      id: 'r1',
      ownerUid: 'uid-brasseur',
      content: const RecipeContent(
        name: 'Blonde',
        equipmentId: 'e1',
        brewSteps: [palier, ebullition],
        hops: [cascade],
      ),
    );

    Future<TestApp> ouvrir(
      WidgetTester tester, {
      bool offline = false,
      void Function(TestApp app)? before,
    }) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember, fromCache: offline);
      app.recipes.publish([recette]);
      app.equipment.publish([equipment]);
      before?.call(app);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/recettes/r1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nouveau brassin'));
      await tester.pumpAndSettle();
      return app;
    }

    Future<void> creer(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Créer le brassin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer le brassin'));
      await tester.pumpAndSettle();
    }

    testWidgets('présélection par la préférence : création puis déroulé', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        before: (app) {
          app.processes.publish([
            exemple(),
            exemple(id: 'g1', owner: 'uid-zoe'),
          ]);
          app.preferences.publishDefault('uid-brasseur', 'p1');
        },
      );
      expect(find.text(kNomModeleExemple), findsOneWidget);
      // Date prévue par défaut : aujourd'hui, dim. 8 nov.
      expect(
        find.text('Brassage · dim. 8 nov. · 11 étapes · 6${nbsp}h${nbsp}00'),
        findsOneWidget,
      );
      expect(
        find.text('Houblonnage à cru · jeu. 12 nov. (J+4) · 4 étapes'),
        findsOneWidget,
      );
      expect(
        find.text('Embouteillage · dim. 22 nov. (J+14) · 6 étapes'),
        findsOneWidget,
      );
      await creer(tester);
      expect(app.brews.writes.map((w) => w.kind), ['create', 'process']);
      final ecrit = app.brews.writes[1];
      expect(ecrit.brewId, app.brews.writes[0].brewId);
      final deroule = ecrit.detail['deroule']! as Deroule;
      expect(deroule.templateId, 'p1');
      expect(erreurDeroule(deroule), isNull);
      // Clés définitives : celles du dépôt, jamais celles de l'aperçu.
      expect(deroule.lignes.every((l) => !l.key.startsWith('apercu-')), isTrue);
      expect(find.text(FormulaireNouveauBrassin.created), findsOneWidget);
    });

    testWidgets('sans préférence : chronologie seule, une écriture', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        before: (app) => app.processes.publish([exemple()]),
      );
      expect(find.text(kChronologieSeule), findsOneWidget);
      expect(find.textContaining('Chronologie : 2 étapes ·'), findsOneWidget);
      await creer(tester);
      expect(app.brews.writes.single.kind, 'create');
    });

    testWidgets('lecteur d\'écran : lignes lisibles, synthèse en région live', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await ouvrir(
        tester,
        before: (app) {
          app.processes.publish([exemple()]);
          app.preferences.publishDefault('uid-brasseur', 'p1');
        },
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Houblonnage à cru · jeu\\. 12 nov\\. \\(J\\+4\\)'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            'Déroulé prévu : $kNomModeleExemple, 3 journées.',
          ),
        ),
        matchesSemantics(
          label: 'Déroulé prévu : $kNomModeleExemple, 3 journées.',
          isLiveRegion: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('région live : le nom distingue deux processus de 3 journées', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await ouvrir(
        tester,
        before: (app) {
          app.processes.publish([
            exemple(),
            ModeleProcessus(
              id: 'p2',
              ownerUid: 'uid-brasseur',
              content: ContenuModele(
                name: 'Autre',
                journees: modeleExemple(cles('p2')).journees,
              ),
            ),
          ]);
          app.preferences.publishDefault('uid-brasseur', 'p1');
        },
      );
      await tester.tap(find.text(kNomModeleExemple).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Autre').last);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Déroulé prévu : Autre, 3 journées.'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('modèle d\'un autre membre : jamais proposé', (tester) async {
      await ouvrir(
        tester,
        before: (app) {
          app.processes.publish([exemple(id: 'g1', owner: 'uid-zoe')]);
          app.preferences.publishDefault('uid-brasseur', 'g1');
        },
      );
      expect(find.text(TextesChoixProcessus.aucun), findsOneWidget);
      expect(find.text('Créer un processus'), findsOneWidget);
      expect(find.text(TextesChoixProcessus.defautSupprime), findsOneWidget);
    });

    testWidgets('hors ligne sans modèle lu : message, chronologie seule', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        offline: true,
        before: (app) => app.processes.publish(const [], fromCache: true),
      );
      expect(find.text(TextesChoixProcessus.horsLigne), findsOneWidget);
      await creer(tester);
      expect(app.brews.writes.single.kind, 'create');
      expect(
        find.text(FormulaireNouveauBrassin.createdOffline),
        findsOneWidget,
      );
    });

    testWidgets('lecture en échec : message et Réessayer', (tester) async {
      await ouvrir(
        tester,
        before: (app) => app.processes.all.addError(Exception('refus')),
      );
      expect(find.text(TextesChoixProcessus.erreur), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('déroulé seul refusé : message de la spécification', (
      tester,
    ) async {
      await ouvrir(
        tester,
        before: (app) {
          app.brews.serverAnswer = () async {};
          app.brews.processAnswer = () async => throw Exception('refus');
          app.processes.publish([exemple()]);
          app.preferences.publishDefault('uid-brasseur', 'p1');
        },
      );
      await creer(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(FormulaireNouveauBrassin.processRejected('Blonde')),
        findsOneWidget,
      );
    });

    testWidgets('création refusée : seul le refus de la création s\'annonce', (
      tester,
    ) async {
      await ouvrir(
        tester,
        before: (app) {
          app.brews.serverAnswer = () async => throw Exception('refus');
          app.processes.publish([exemple()]);
          app.preferences.publishDefault('uid-brasseur', 'p1');
        },
      );
      await creer(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(FormulaireNouveauBrassin.rejected('Blonde')),
        findsOneWidget,
      );
      expect(
        find.text(FormulaireNouveauBrassin.processRejected('Blonde')),
        findsNothing,
      );
    });
  });

  group('fiche', () {
    Future<TestApp> fiche(
      WidgetTester tester,
      Brew brew, {
      List<ModeleProcessus>? modeles,
      bool publier = true,
      bool offline = false,
      bool cache = false,
    }) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember, fromCache: offline);
      app.brews.publish([brew]);
      app.brews.publishEvents(brew.id, const []);
      if (publier) {
        app.processes.publish(modeles ?? [exemple()], fromCache: cache);
      }
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/${brew.id}');
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('prévu : processus, journées datées, Changer de processus', (
      tester,
    ) async {
      await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          plannedFor: DateTime(2026, 11, 21),
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
      );
      await voir(tester, find.text('Embouteillage · sam. 5 déc. (J+14)'));
      expect(find.text('Processus : $kNomModeleExemple'), findsOneWidget);
      expect(find.text('Brassage · sam. 21 nov.'), findsOneWidget);
      expect(
        find.text('Houblonnage à cru · mer. 25 nov. (J+4)'),
        findsOneWidget,
      );
      expect(find.text(TextesDeroule.changerProcessus), findsOneWidget);
      expect(find.text(TextesDeroule.fige), findsNothing);
      expect(find.text('Chronologie'), findsNothing);
    });

    testWidgets('changer la date : process réécrit, journée annoncée', (
      tester,
    ) async {
      final deroule = derouleExemple();
      final app = await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          plannedFor: DateTime(2026, 11, 21),
          recipe: recetteAvecCru,
          process: deroule,
        ),
      );
      final menu = find.byTooltip('Actions de la journée Houblonnage à cru');
      await voir(tester, menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text(TextesDeroule.retablirDate), findsNothing);
      await tester.tap(find.text(TextesDeroule.changerDate));
      await tester.pumpAndSettle();
      await tester.tap(find.text('27'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final write = app.brews.writes.single;
      expect(write.kind, 'process');
      final change = write.detail['deroule']! as Deroule;
      final cru = change.journees.firstWhere(
        (j) => j.key == deroule.journees[1].key,
      );
      expect(cru.offsetDays, 6);
      expect(cru.sourceEcart, SourceEcart.brasseur);
      expect(
        find.text('« Houblonnage à cru » prévu le ven. 27 nov.'),
        findsOneWidget,
      );
    });

    testWidgets('date changée : Rétablir la date du processus', (tester) async {
      final deroule = derouleExemple();
      final change = deroule.avecEcart(
        deroule.journees[1].key,
        6,
        SourceEcart.brasseur,
      );
      final app = await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          plannedFor: DateTime(2026, 11, 21),
          recipe: recetteAvecCru,
          process: change,
        ),
      );
      final menu = find.byTooltip('Actions de la journée Houblonnage à cru');
      await voir(tester, menu);
      expect(
        find.text('Houblonnage à cru · ven. 27 nov. (J+6, date changée)'),
        findsOneWidget,
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextesDeroule.retablirDate));
      await tester.pumpAndSettle();
      final ecrit = app.brews.writes.single.detail['deroule']! as Deroule;
      expect(ecrit.journees[1].offsetDays, 4);
      expect(ecrit.journees[1].sourceEcart, SourceEcart.modele);
    });

    testWidgets('après le départ : figé, aucun bouton', (tester) async {
      await fiche(
        tester,
        unBrassin(
          status: BrewStatus.fermenting,
          brewedAt: DateTime(2026, 11, 4, 9),
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
      );
      await voir(tester, find.text(TextesDeroule.titre));
      expect(find.text('3 journées'), findsOneWidget);
      await tester.tap(find.text(TextesDeroule.titre));
      await tester.pumpAndSettle();
      await voir(tester, find.text(TextesDeroule.fige));
      expect(find.text(TextesDeroule.changerProcessus), findsNothing);
      expect(
        find.byTooltip('Actions de la journée Houblonnage à cru'),
        findsNothing,
      );
    });

    testWidgets('brassin sans process : chronologie de la recette seule', (
      tester,
    ) async {
      await fiche(tester, unBrassin(status: BrewStatus.planned));
      await voir(tester, find.text(kChronologieSeule));
      expect(find.text('Palier 68'), findsWidgets);
      expect(find.text(TextesDeroule.changerProcessus), findsOneWidget);
    });

    testWidgets('déroulé illisible : panne affichée, rapportée par le dépôt', (
      tester,
    ) async {
      await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          process: lireDeroule({'format_version': 2}),
        ),
      );
      await voir(tester, find.text(kDerouleIllisible));
      expect(find.text('Palier 68'), findsNothing);
    });

    testWidgets('Recréer depuis la recette : processus résolu de nouveau', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      final brew = Brew(
        id: 'b1',
        ownerUid: 'uid-brasseur',
        name: 'Blonde du jour',
        status: BrewStatus.planned,
        recipeId: 'r1',
        recipe: recetteAvecCru,
        recipeUpdatedAt: DateTime(2026, 11, 1),
        equipment: equipementTest,
        process: derouleExemple(),
      );
      app.brews.publish([brew]);
      app.brews.publishEvents('b1', const []);
      app.processes.publish([exemple()]);
      app.recipes.publish([
        Recipe(
          id: 'r1',
          ownerUid: 'uid-brasseur',
          updatedAt: DateTime(2026, 11, 5),
          content: const RecipeContent(name: 'Blonde', brewSteps: [palier]),
        ),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1');
      await tester.pumpAndSettle();
      await voir(tester, find.text('Recréer depuis la recette'));
      await tester.tap(find.text('Recréer depuis la recette'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Son processus est appliqué de nouveau à la recette actuelle.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Recréer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.map((w) => w.kind), [
        'create',
        'delete',
        'process',
      ]);
      final ecrit = app.brews.writes.last;
      expect(ecrit.brewId, app.brews.writes.first.brewId);
      final deroule = ecrit.detail['deroule']! as Deroule;
      // Nouvelle recette sans houblon à cru : la journée de houblonnage part.
      expect(deroule.journees.length, 2);
      expect(deroule.brassage!.lignes.map((l) => l.key), contains('k-palier'));
      expect(
        deroule.brassage!.lignes.map((l) => l.key),
        isNot(contains('k-ebullition')),
      );
    });

    testWidgets('changer de processus : Appliquer réécrit process', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unBrassin(status: BrewStatus.planned, recipe: recetteAvecCru),
      );
      await voir(tester, find.text(TextesDeroule.changerProcessus));
      await tester.tap(find.text(TextesDeroule.changerProcessus));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kChronologieSeule).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(kNomModeleExemple).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Appliquer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      final ecrit = app.brews.writes.single;
      expect(ecrit.kind, 'process');
      expect((ecrit.detail['deroule']! as Deroule).journees.length, 3);
      expect(find.text(TextesDeroule.change), findsOneWidget);
    });

    Finder appliquer() => find.widgetWithText(FilledButton, 'Appliquer');

    Future<void> ouvrirFeuille(
      WidgetTester tester, {
      bool settle = true,
    }) async {
      await voir(tester, find.text(TextesDeroule.changerProcessus));
      await tester.tap(find.text(TextesDeroule.changerProcessus));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 500));
      }
    }

    testWidgets('modèle supprimé : « (actuel) » présélectionné, rien effacé', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
        modeles: const [],
      );
      await ouvrirFeuille(tester);
      expect(find.text('$kNomModeleExemple (actuel)'), findsOneWidget);
      expect(find.text(TextesDeroule.choisirAutre), findsOneWidget);
      expect(tester.widget<FilledButton>(appliquer()).onPressed, isNull);
      // L'aperçu est le déroulé actuel du brassin.
      expect(find.text('Houblonnage à cru · J+4 · 4 étapes'), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('liste non touchée ou même processus : Appliquer inactif', (
      tester,
    ) async {
      final deroule = derouleExemple();
      final app = await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          recipe: recetteAvecCru,
          process: deroule.avecEcart(
            deroule.journees[1].key,
            6,
            SourceEcart.brasseur,
          ),
        ),
      );
      await ouvrirFeuille(tester);
      expect(tester.widget<FilledButton>(appliquer()).onPressed, isNull);
      await tester.tap(find.text(kNomModeleExemple).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(kNomModeleExemple).last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(appliquer()).onPressed, isNull);
      expect(find.text(TextesDeroule.choisirAutre), findsOneWidget);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('liste en lecture : seule la chronologie seule s\'applique', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
        publier: false,
      );
      await ouvrirFeuille(tester, settle: false);
      expect(find.text(TextesChoixProcessus.lecture), findsOneWidget);
      expect(find.text('$kNomModeleExemple (actuel)'), findsOneWidget);
      expect(tester.widget<FilledButton>(appliquer()).onPressed, isNull);
      await tester.ensureVisible(find.text('$kNomModeleExemple (actuel)'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('$kNomModeleExemple (actuel)').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text(kChronologieSeule).last);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<FilledButton>(appliquer()).onPressed, isNotNull);
      await tester.ensureVisible(appliquer());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(appliquer());
      await tester.pump(const Duration(milliseconds: 500));
      final ecrit = app.brews.writes.single;
      expect(ecrit.kind, 'process');
      expect(ecrit.detail['deroule'], isNull);
    });

    testWidgets('feuille hors ligne : texte propre à un brassin existant', (
      tester,
    ) async {
      await fiche(
        tester,
        unBrassin(status: BrewStatus.planned, recipe: recetteAvecCru),
        modeles: const [],
        offline: true,
        cache: true,
      );
      await ouvrirFeuille(tester);
      expect(find.text(TextesChoixProcessus.horsLigneFiche), findsOneWidget);
      expect(find.text(TextesChoixProcessus.horsLigne), findsNothing);
    });

    testWidgets('feuille : aucun rappel du processus par défaut supprimé', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unBrassin(status: BrewStatus.planned, recipe: recetteAvecCru),
        modeles: const [],
      );
      app.preferences.publishDefault('uid-brasseur', 'supprime');
      await tester.pumpAndSettle();
      await ouvrirFeuille(tester);
      expect(find.text(TextesChoixProcessus.aucun), findsOneWidget);
      expect(find.text(TextesChoixProcessus.defautSupprime), findsNothing);
    });

    testWidgets('changer la date hors ligne : annoncé sur l\'appareil', (
      tester,
    ) async {
      final app = await fiche(
        tester,
        unBrassin(
          status: BrewStatus.planned,
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
        offline: true,
      );
      final menu = find.byTooltip('Actions de la journée Houblonnage à cru');
      await voir(tester, menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextesDeroule.changerDate));
      await tester.pumpAndSettle();
      // Sans date prévue : écart en jours.
      await tester.enterText(find.byType(TextFormField).last, '6');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'process');
      expect(
        find.text(TextesDeroule.ecartHorsLigne('Houblonnage à cru')),
        findsOneWidget,
      );
    });

    testWidgets('Recréer, modèle supprimé : la confirmation le dit', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([
        Brew(
          id: 'b1',
          ownerUid: 'uid-brasseur',
          name: 'Blonde du jour',
          status: BrewStatus.planned,
          recipeId: 'r1',
          recipe: recetteAvecCru,
          recipeUpdatedAt: DateTime(2026, 11, 1),
          equipment: equipementTest,
          process: derouleExemple(),
        ),
      ]);
      app.brews.publishEvents('b1', const []);
      app.processes.publish(const []);
      app.recipes.publish([
        Recipe(
          id: 'r1',
          ownerUid: 'uid-brasseur',
          updatedAt: DateTime(2026, 11, 5),
          content: const RecipeContent(name: 'Blonde', brewSteps: [palier]),
        ),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1');
      await tester.pumpAndSettle();
      await voir(tester, find.text('Recréer depuis la recette'));
      await tester.tap(find.text('Recréer depuis la recette'));
      await tester.pumpAndSettle();
      expect(
        find.text(BrewDetailScreen.recreateProcessDeleted),
        findsOneWidget,
      );
      expect(find.text(BrewDetailScreen.recreateProcessKept), findsNothing);
      await tester.tap(find.text('Recréer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.map((w) => w.kind), ['create', 'delete']);
    });
  });

  group('causes d\'un processus inapplicable', () {
    ContenuModele unJour(int etapes) => ContenuModele(
      name: 'Long',
      journees: [
        JourneeModele(
          key: 'j',
          name: 'Brassage',
          offsetDays: 0,
          elements: [
            for (var i = 0; i < etapes; i++)
              ElementModele.etape(key: 'e$i', name: 'Étape $i', durationMin: 5),
            const ElementModele.bloc(
              key: 'b',
              nature: NatureElement.chronologieRecette,
            ),
          ],
        ),
      ],
    );

    test('chronologie illisible, plus de 120 étapes', () {
      final illisible = evaluerAssemblage(
        modele: exemple(),
        recipe: const RecipeContent(
          name: 'Blonde',
          brewStepsProblem: 'clé absente (0)',
        ),
        nouvelleCle: cles('a'),
        errors: RecordingErrorReportService(),
        reported: {},
      );
      expect(
        (illisible as AssemblageRefuse).cause,
        'La chronologie de cette recette est illisible.',
      );
      final errors = RecordingErrorReportService();
      final long = evaluerAssemblage(
        modele: ModeleProcessus(
          id: 'p2',
          ownerUid: 'uid-brasseur',
          content: unJour(59),
        ),
        recipe: RecipeContent(
          name: 'Blonde',
          brewSteps: [
            for (var i = 0; i < 62; i++)
              BrewStepLine(key: 'r$i', name: 'Palier $i', durationMin: 1),
          ],
        ),
        nouvelleCle: cles('a'),
        errors: errors,
        reported: {},
      );
      expect(
        (long as AssemblageRefuse).cause,
        'Ce processus donne plus de 120 étapes dans la journée « Brassage ». '
        'Retirez des étapes du processus.',
      );
      expect(errors.reports.single.feature, 'brews.process_assembly');
    });
  });

  group('liste', () {
    testWidgets('Prochaine journée : nom et date, aujourd\'hui', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([
        unBrassin(
          id: 'a',
          status: BrewStatus.fermenting,
          brewedAt: DateTime(2026, 11, 4, 9),
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
        unBrassin(
          id: 'b',
          status: BrewStatus.fermenting,
          brewedAt: DateTime(2026, 11, 1, 9),
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins');
      await tester.pumpAndSettle();
      expect(
        find.text('Prochaine journée : Houblonnage à cru, aujourd\'hui'),
        findsOneWidget,
      );
      expect(
        find.text('Prochaine journée : Embouteillage, dim. 15 nov.'),
        findsOneWidget,
      );
      expect(
        ligneDateBrassin(
          unBrassin(
            status: BrewStatus.fermenting,
            brewedAt: DateTime(2026, 11, 4),
          ),
          DateTime(2026, 11, 8),
        ),
        'Brassé le 4 nov. 2026',
      );
    });
  });

  group('journée de brassage', () {
    testWidgets('Préparer : ligne Brassage et Ensuite', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([
        unBrassin(
          status: BrewStatus.planned,
          plannedFor: DateTime(2026, 11, 21),
          recipe: recetteAvecCru,
          process: derouleExemple(),
        ),
      ]);
      app.brews.publishEvents('b1', const []);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1/preparer');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Brassage : 11 étapes · 6${nbsp}h${nbsp}00'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Ensuite : Houblonnage à cru le mer. 25 nov., Embouteillage le '
          'sam. 5 déc.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Commencer le brassage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer le brassage'));
      await tester.pumpAndSettle();
      final start = app.brews.writes.single;
      expect(start.kind, 'start');
      // Première étape du déroulé : celle du processus.
      expect(
        start.detail['first'],
        derouleExemple().brassage!.lignes.first.key,
      );
    });

    testWidgets('Préparer : déroulé illisible, Commencer bloqué', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      app.brews.publish([
        unBrassin(
          status: BrewStatus.planned,
          process: lireDeroule({'format_version': 2}),
        ),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1/preparer');
      await tester.pumpAndSettle();
      expect(find.text(kDerouleIllisible), findsOneWidget);
      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Commencer le brassage'),
      );
      expect(bouton.onPressed, isNull);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('écran du jour : barre « Brassage · 12:10 »', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      final deroule = derouleExemple();
      app.brews.publish([
        unBrassin(
          brewedAt: DateTime(2026, 11, 8, 10),
          recipe: recetteAvecCru,
          process: deroule,
        ),
      ]);
      app.brews.publishEvents('b1', [
        debut(
          'e1',
          deroule.brassage!.lignes.first.key,
          DateTime(2026, 11, 8, 10),
        ),
      ]);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go('/brassins/b1/jour');
      await tester.pump();
      await tester.pump();
      expect(find.text('Brassage · 12:10'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Journée Brassage, heure actuelle 12:10')),
        findsOneWidget,
      );
      // Le plan porte sur la journée de brassage : 12 étapes.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').toLowerCase().contains('sur 11'),
        ),
        findsWidgets,
      );
      semantics.dispose();
    });
  });
}
