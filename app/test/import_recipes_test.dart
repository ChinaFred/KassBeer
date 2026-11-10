import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:exchange/exchange.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/fichiers/echange_fichiers.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/recipes/domain/import_recettes.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/libelles_echange.dart';
import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

Uint8List fixture(String chemin) =>
    File('../exchange/test/fixtures/$chemin').readAsBytesSync();

const grainfather = Equipment(
  id: 'e1',
  ownerUid: 'uid-brasseur',
  ownerName: 'Bruno Brasseur',
  content: equipementTest,
);

Future<TestApp> open(
  WidgetTester tester, {
  void Function(TestApp app)? before,
  bool offline = false,
}) async {
  final app = TestApp();
  // Fenêtre haute : toutes les lignes de l'aperçu sont construites.
  await app.pump(tester, height: 4000);
  app.signIn(brewerUser, member: brewerMember, fromCache: offline);
  before?.call(app);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go('/recettes/importer');
  await tester.pumpAndSettle();
  return app;
}

Future<void> choisir(
  WidgetTester tester,
  TestApp app,
  ResultatChoix choix,
) async {
  app.fichiers.choix = choix;
  await tester.tap(find.text(TextesImport.choisir));
  await tester.pumpAndSettle();
}

void main() {
  group('préparation de l\'aperçu', () {
    FichierLu lu(String chemin) =>
        analyserFichier(fixture(chemin)) as FichierLu;

    test('I9 : chaque recette lue se relit et se récrit à l\'identique', () {
      for (final chemin in [
        'lecture/brewtarget-201.json',
        'lecture/v1-metrique.json',
      ]) {
        final fichier = lu(chemin);
        final recettes = preparerImport(
          fichier,
          miennes: const [],
          errors: RecordingErrorReportService(),
        );
        for (final (i, r) in recettes.indexed) {
          final source = fichier.recettes[i].resultat;
          if (source is! RecetteLue) continue;
          final ecrit = r.content!.toFirestore(creation: true);
          expect(
            jsonDecode(jsonEncode(ecrit['recipe'])),
            jsonDecode(jsonEncode(source.recipe)),
            reason: '$chemin, recette ${i + 1}',
          );
          expect(ecrit['imported_from'], startsWith('BeerJSON · sha256:'));
        }
      }
    });

    test(
      'déjà importée : même empreinte chez l\'importateur, date de création',
      () {
        final fichier = lu('lecture/brewtarget-201.json');
        final premiere = preparerImport(
          fichier,
          miennes: const [],
          errors: RecordingErrorReportService(),
        ).first;
        final mienne = Recipe(
          id: 'r1',
          ownerUid: 'uid-brasseur',
          content: premiere.content!,
          createdAt: DateTime(2026, 11, 9),
        );
        final r = preparerImport(
          fichier,
          miennes: [mienne],
          errors: RecordingErrorReportService(),
        );
        expect(r.first.dejaImportee, isTrue);
        expect(r.first.importeeLe, DateTime(2026, 11, 9));
        expect(r.first.cocheeParDefaut, isFalse);
        // Le même nom seul ne fait pas un doublon.
        final homonyme = Recipe(
          id: 'r2',
          ownerUid: 'uid-brasseur',
          content: RecipeContent(name: premiere.nom),
        );
        expect(
          preparerImport(
            fichier,
            miennes: [homonyme],
            errors: RecordingErrorReportService(),
          ).first.dejaImportee,
          isFalse,
        );
      },
    );
  });

  group('Recettes › Importer', () {
    testWidgets(
      'I1 : « Importer » dans la liste ouvre l\'écran, rien n\'est lu avant le choix',
      (tester) async {
        final app = TestApp();
        await app.pump(tester);
        app.signIn(brewerUser, member: brewerMember);
        await tester.pumpAndSettle();
        expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
        await tester.tap(find.widgetWithText(OutlinedButton, 'Importer'));
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.titre), findsOneWidget);
        expect(find.text(TextesImport.aide), findsOneWidget);
        expect(app.fichiers.choixDemandes, 0);
      },
    );

    testWidgets('choix annulé : retour sans message', (tester) async {
      final app = await open(tester);
      await choisir(tester, app, const ChoixAnnule());
      expect(app.fichiers.maxOctetsDemande, 10 * 1024 * 1024);
      expect(find.text(TextesImport.aide), findsOneWidget);
      expect(app.errors.reports, isEmpty);
    });

    testWidgets('fichier trop gros : taille en Mo, borne de 10 Mo', (
      tester,
    ) async {
      final app = await open(tester);
      await choisir(tester, app, const FichierTropGros(13002342));
      expect(
        find.text(
          'Fichier trop gros : 12,4 Mo. Kass\'Beer lit les fichiers de 10 Mo au plus.',
        ),
        findsOneWidget,
      );
      expect(find.text(TextesImport.choisirAutre), findsOneWidget);
    });

    testWidgets('ouverture impossible : « Réessayer »', (tester) async {
      final app = await open(tester);
      await choisir(tester, app, const ChoixImpossible());
      expect(find.text(TextesImport.ouvertureImpossible), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('JSON mal formé : illisible, rapporté sans nom ni contenu', (
      tester,
    ) async {
      final app = await open(tester);
      await choisir(
        tester,
        app,
        FichierChoisi(
          'recette-secrete.json',
          Uint8List.fromList(
            utf8.encode(
              '{"beerjson": {"version": 2.01, "recipes": [{"name": "Privée"',
            ),
          ),
        ),
      );
      expect(
        find.text(fichierIllisible('recette-secrete.json')),
        findsOneWidget,
      );
      final report = app.errors.reports.single;
      expect(report.feature, 'exchange.read');
      expect('${report.error} ${report.context}', isNot(contains('secrete')));
      expect('${report.error} ${report.context}', isNot(contains('Privée')));
    });

    testWidgets('JSON qui n\'est pas du BeerJSON : message, aucun rapport', (
      tester,
    ) async {
      final app = await open(tester);
      await choisir(
        tester,
        app,
        FichierChoisi(
          'a.json',
          Uint8List.fromList(utf8.encode('{"recettes": []}')),
        ),
      );
      expect(
        find.text(
          libelleFichierRefuse(
            const FichierRefuse(RaisonFichier.jsonNonBeerJson),
            'a.json',
          ),
        ),
        findsOneWidget,
      );
      expect(app.errors.reports, isEmpty);
    });

    testWidgets(
      'aperçu : statuts écrits en toutes lettres, refus et doublon décochés',
      (tester) async {
        final app = await open(tester);
        await choisir(
          tester,
          app,
          FichierChoisi(
            'brewtarget.json',
            fixture('lecture/brewtarget-201.json'),
          ),
        );
        expect(
          find.text('1 incomplète · 4 refusées · 1 en double'),
          findsOneWidget,
        );
        expect(find.text(TextesImport.sansPrix), findsOneWidget);
        expect(
          find.textContaining(
            'Refusée : Unité inconnue pour la quantité de Pastille clarifiante : « each ».',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Refusée : Plus de 50 houblons (51).'),
          findsOneWidget,
        );
        expect(find.textContaining('Refusée : Nom absent.'), findsOneWidget);
        expect(
          find.textContaining(
            'Refusée : Valeur hors limites : quantité de Pils.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('En double dans le fichier'),
          findsOneWidget,
        );
        // Une case par recette lisible, plus « Toutes les recettes ».
        expect(find.byType(CheckboxListTile), findsNWidgets(3));
        expect(find.text(TextesImport.importer(1)), findsOneWidget);
      },
    );

    testWidgets('détails : à compléter et modifié à l\'import', (tester) async {
      final app = await open(tester);
      await choisir(
        tester,
        app,
        FichierChoisi(
          'brewtarget.json',
          fixture('lecture/brewtarget-201.json'),
        ),
      );
      await tester.tap(find.textContaining('Détails (').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Quantité de levure non renseignée : Levure américaine.'),
        findsOneWidget,
      );
      expect(
        find.text('Style : seul le nom « American IPA » est gardé.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Unités converties (gallons, heures, °F, livres, Lovibond, onces, SRM, densité potentielle, jours, cuillères à café).',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'I4 : import sous le compte de l\'importateur, équipement présélectionné',
      (tester) async {
        final app = await open(
          tester,
          before: (app) => app.equipment.publish([grainfather]),
        );
        await choisir(
          tester,
          app,
          FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
        );
        expect(find.textContaining('· Prête'), findsOneWidget);
        await tester.tap(find.text(TextesImport.importer(1)));
        await tester.pumpAndSettle();
        final write = app.recipes.writes.single;
        expect(write.kind, 'create');
        expect(write.ownerUid, 'uid-brasseur');
        expect(write.ownerName, 'Bruno Brasseur');
        expect(write.content!.equipmentId, 'e1');
        expect(write.content!.importedFrom, startsWith('BeerJSON · sha256:'));
        expect(write.content!.author, 'Brasseur Exemple');
        expect(find.text(TextesImport.termine), findsOneWidget);
        expect(find.text('1 créée · 0 ignorée · 0 en erreur'), findsOneWidget);
        expect(find.text(TextesImport.enAttente), findsOneWidget);
      },
    );

    testWidgets('sans équipement : la recette devient incomplète', (
      tester,
    ) async {
      final app = await open(tester);
      await choisir(
        tester,
        app,
        FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
      );
      expect(find.textContaining('· Incomplète'), findsOneWidget);
    });

    testWidgets(
      '« Tout cocher » et zéro case : bouton inactif avec sa raison',
      (tester) async {
        final app = await open(tester);
        await choisir(
          tester,
          app,
          FichierChoisi(
            'brewtarget.json',
            fixture('lecture/brewtarget-201.json'),
          ),
        );
        await tester.tap(find.text(TextesImport.toutes(2)));
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.importer(2)), findsOneWidget);
        await tester.tap(find.text(TextesImport.toutes(2)));
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.aucuneCochee), findsOneWidget);
        final bouton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, TextesImport.importer(0)),
        );
        expect(bouton.onPressed, isNull);
      },
    );

    testWidgets('filtre par statut', (tester) async {
      final app = await open(tester);
      await choisir(
        tester,
        app,
        FichierChoisi(
          'brewtarget.json',
          fixture('lecture/brewtarget-201.json'),
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Refusées (4)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refusée :'), findsNWidgets(4));
      expect(find.textContaining('· Incomplète'), findsNothing);
    });

    testWidgets('déjà importée : décochée, « Déjà importée le … »', (
      tester,
    ) async {
      final fichier =
          analyserFichier(fixture('export/blonde-essai.json')) as FichierLu;
      final content = preparerImport(
        fichier,
        miennes: const [],
        errors: RecordingErrorReportService(),
      ).single.content!;
      final app = await open(
        tester,
        before: (app) => app.recipes.publish([
          Recipe(
            id: 'r1',
            ownerUid: 'uid-brasseur',
            content: content,
            createdAt: DateTime(2026, 11, 9),
          ),
        ]),
      );
      await choisir(
        tester,
        app,
        FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
      );
      expect(
        find.textContaining('Déjà importée le 9 nov. 2026'),
        findsOneWidget,
      );
      expect(find.text(TextesImport.importer(0)), findsOneWidget);
    });

    testWidgets(
      'hors ligne : créées sur l\'appareil ; refus du serveur en erreur',
      (tester) async {
        final app = await open(
          tester,
          offline: true,
          before: (app) => app.equipment.publish([grainfather]),
        );
        final refus = Completer<void>();
        app.recipes.serverAnswer = () => refus.future;
        await choisir(
          tester,
          app,
          FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
        );
        await tester.tap(find.text(TextesImport.importer(1)));
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.horsLigne(1)), findsOneWidget);
        refus.completeError(StateError('permission-denied'));
        await tester.pumpAndSettle();
        expect(
          find.text(TextesImport.refusServeur('Blonde d\'essai')),
          findsOneWidget,
        );
        expect(find.text('0 créée · 0 ignorée · 1 en erreur'), findsOneWidget);
      },
    );

    testWidgets('refus après la sortie de l\'écran : un seul message groupé', (
      tester,
    ) async {
      final app = await open(
        tester,
        before: (app) => app.equipment.publish([grainfather]),
      );
      final refus = Completer<void>();
      app.recipes.serverAnswer = () => refus.future;
      await choisir(
        tester,
        app,
        FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
      );
      await tester.tap(find.text(TextesImport.importer(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TextesImport.revenir));
      await tester.pumpAndSettle();
      refus.completeError(StateError('permission-denied'));
      await tester.pumpAndSettle();
      expect(
        find.text(TextesImport.refusGroupe(['Blonde d\'essai'])),
        findsOneWidget,
      );
    });

    group('relectures de la v0.1.19', () {
      testWidgets('16 : ouverture impossible, un seul bouton « Réessayer »', (
        tester,
      ) async {
        final app = await open(tester);
        await choisir(tester, app, const ChoixImpossible());
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Réessayer'), findsOneWidget);
        expect(find.text(TextesImport.choisirAutre), findsNothing);
      });

      testWidgets('16 : fichier refusé, « Choisir un autre fichier » plein', (
        tester,
      ) async {
        final app = await open(tester);
        await choisir(tester, app, const FichierTropGros(null));
        expect(
          find.widgetWithText(FilledButton, TextesImport.choisirAutre),
          findsOneWidget,
        );
      });

      testWidgets('1 : panne inattendue de l\'analyse : illisible, rapportée', (
        tester,
      ) async {
        final app = await open(tester);
        app.analyseur = (_) => throw StateError('contenu privé');
        await choisir(
          tester,
          app,
          FichierChoisi('mon-fichier.json', Uint8List.fromList([0x7B])),
        );
        expect(find.text(fichierIllisible('mon-fichier.json')), findsOneWidget);
        final report = app.errors.reports.single;
        expect(report.feature, 'exchange.read');
        expect(report.context, 'taille 1 octets, erreur StateError');
        expect('${report.error}', isNot(contains('privé')));
      });

      testWidgets('17, 18, 19, 21 : filtres comptés, libellés, ignorées', (
        tester,
      ) async {
        final app = await open(tester);
        await choisir(
          tester,
          app,
          FichierChoisi(
            'brewtarget.json',
            fixture('lecture/brewtarget-201.json'),
          ),
        );
        for (final f in [
          'Toutes (6)',
          'Prêtes (0)',
          'Incomplètes (1)',
          'Déjà importées ou en double (1)',
          'Refusées (4)',
        ]) {
          expect(find.widgetWithText(ChoiceChip, f), findsOneWidget, reason: f);
        }
        final semantics = tester.ensureSemantics();
        expect(
          find.bySemanticsLabel(RegExp(r'^Détails de IPA de test \(')),
          findsWidgets,
        );
        semantics.dispose();
        await tester.tap(find.widgetWithText(ChoiceChip, 'Incomplètes (1)'));
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.toutesAffichees(1)), findsOneWidget);
        await tester.tap(find.text(TextesImport.importer(1)));
        await tester.pumpAndSettle();
        expect(find.text('IPA de test — Non cochée'), findsOneWidget);
        expect(
          find.text(
            'Saison refusée — Refusée : Unité inconnue pour la quantité de '
            'Pastille clarifiante : « each ».',
          ),
          findsOneWidget,
        );
      });

      testWidgets('11 : la fiche s\'ouvre par-dessus le compte rendu', (
        tester,
      ) async {
        final app = await open(
          tester,
          before: (app) => app.equipment.publish([grainfather]),
        );
        await choisir(
          tester,
          app,
          FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
        );
        await tester.tap(find.text(TextesImport.importer(1)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Blonde d\'essai'));
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.termine), findsNothing);
        app.container.read(routerProvider).pop();
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.termine), findsOneWidget);
      });

      testWidgets('20 : « Import terminé » annoncé une fois ; refus annoncé', (
        tester,
      ) async {
        final app = await open(
          tester,
          before: (app) => app.equipment.publish([grainfather]),
        );
        final refus = Completer<void>();
        app.recipes.serverAnswer = () => refus.future;
        await choisir(
          tester,
          app,
          FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
        );
        tester.takeAnnouncements();
        await tester.tap(find.text(TextesImport.importer(1)));
        await tester.pumpAndSettle();
        final annonces = [
          for (final a in tester.takeAnnouncements()) a.message,
        ];
        // Une seule annonce de fin, avec le bilan.
        expect(annonces.where((m) => m.startsWith(TextesImport.termine)), [
          'Import terminé. 1 créée · 0 ignorée · 0 en erreur',
        ]);
        refus.completeError(StateError('permission-denied'));
        await tester.pumpAndSettle();
        expect([
          for (final a in tester.takeAnnouncements()) a.message,
        ], contains(TextesImport.refusServeur('Blonde d\'essai')));
      });

      testWidgets(
        '9 : refus reçu pendant l\'écriture : compté dans l\'annonce de fin',
        (tester) async {
          final app = await open(
            tester,
            before: (app) => app.equipment.publish([grainfather]),
          );
          // Le serveur refuse aussitôt, pendant « Import en cours ».
          app.recipes.serverAnswer = () =>
              Future<void>.error(StateError('permission-denied'));
          await choisir(
            tester,
            app,
            FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
          );
          tester.takeAnnouncements();
          await tester.tap(find.text(TextesImport.importer(1)));
          await tester.pumpAndSettle();
          expect([
            for (final a in tester.takeAnnouncements()) a.message,
          ], contains('Import terminé. 0 créée · 0 ignorée · 1 en erreur'));
        },
      );

      testWidgets('6 : « Choisir un fichier » inactif pendant le choix', (
        tester,
      ) async {
        final app = await open(tester);
        final attente = Completer<ResultatChoix>();
        app.fichiers.attente = attente;
        await tester.tap(find.text(TextesImport.choisir));
        await tester.pump();
        final bouton = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text(TextesImport.choisir),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          ),
        );
        expect(bouton.onPressed, isNull);
        await tester.tap(find.text(TextesImport.choisir));
        await tester.pump();
        expect(app.fichiers.choixDemandes, 1);
        attente.complete(const ChoixAnnule());
        await tester.pumpAndSettle();
        final apres = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text(TextesImport.choisir),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          ),
        );
        expect(apres.onPressed, isNotNull);
      });

      testWidgets('8 : « Prête » suit le nom du jeton, pas le nom du compte', (
        tester,
      ) async {
        final app = await open(
          tester,
          before: (app) => app.equipment.publish([grainfather]),
        );
        // Recette sans auteur : l'export prendrait le nom du jeton, absent ici.
        final document =
            jsonDecode(utf8.decode(fixture('export/blonde-essai.json')))
                as Map<String, Object?>;
        final recette =
            ((document['beerjson'] as Map)['recipes'] as List).single as Map;
        recette.remove('author');
        app.auth.tokenName = null;
        await choisir(
          tester,
          app,
          FichierChoisi(
            'blonde.json',
            Uint8List.fromList(utf8.encode(jsonEncode(document))),
          ),
        );
        expect(find.textContaining('· Incomplète'), findsOneWidget);
      });

      testWidgets('10 : « Aucune recette pour ce filtre. »', (tester) async {
        final app = await open(tester);
        await choisir(
          tester,
          app,
          FichierChoisi(
            'brewtarget.json',
            fixture('lecture/brewtarget-201.json'),
          ),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Prêtes (0)'));
        await tester.pumpAndSettle();
        expect(find.text(TextesImport.aucunePourFiltre), findsOneWidget);
      });

      testWidgets('7 : « Importer un autre fichier », refus groupé ensuite', (
        tester,
      ) async {
        final app = await open(
          tester,
          before: (app) => app.equipment.publish([grainfather]),
        );
        final refus = Completer<void>();
        app.recipes.serverAnswer = () => refus.future;
        await choisir(
          tester,
          app,
          FichierChoisi('blonde.json', fixture('export/blonde-essai.json')),
        );
        await tester.tap(find.text(TextesImport.importer(1)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(TextesImport.autreFichier));
        await tester.pumpAndSettle();
        refus.completeError(StateError('permission-denied'));
        await tester.pumpAndSettle();
        expect(
          find.text(TextesImport.refusGroupe(['Blonde d\'essai'])),
          findsOneWidget,
        );
      });

      testWidgets('22 : appui sur une case avec 500 recettes (mesure)', (
        tester,
      ) async {
        final app = await open(tester);
        final recette =
            jsonDecode(utf8.decode(fixture('export/blonde-essai.json')))
                as Map<String, Object?>;
        final source =
            ((recette['beerjson'] as Map)['recipes'] as List).single as Map;
        final recettes = [
          for (var i = 0; i < 500; i++) {...source, 'name': 'Recette $i'},
        ];
        final octets = utf8.encode(
          jsonEncode({
            'beerjson': {'version': 2.01, 'recipes': recettes},
          }),
        );
        await choisir(
          tester,
          app,
          FichierChoisi('cinq-cents.json', Uint8List.fromList(octets)),
        );
        expect(find.text(TextesImport.importer(500)), findsOneWidget);
        final chrono = Stopwatch()..start();
        await tester.tap(find.widgetWithText(CheckboxListTile, 'Recette 0'));
        await tester.pump();
        chrono.stop();
        expect(find.text(TextesImport.importer(499)), findsOneWidget);
        // Mesure en mode test (VM, JIT, débogage) : majorant du temps sur l'APK.
        // ignore: avoid_print
        print(
          'Appui sur une case, 500 recettes : '
          '${chrono.elapsedMilliseconds} ms',
        );
        expect(chrono.elapsedMilliseconds, lessThan(1000));
      });
    });
  });
}
