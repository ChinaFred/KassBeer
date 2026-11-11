import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/breakpoints.dart';
import 'package:kass_beer/core/presentation/fiche.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/admin/data/sources_repository.dart';
import 'package:kass_beer/features/admin/domain/ingestion.dart';
import 'package:kass_beer/features/admin/presentation/admin_screen.dart';
import 'package:kass_beer/features/admin/presentation/admin_sources_screen.dart';
import 'package:kass_beer/features/admin/presentation/libelles_sources.dart';
import 'package:kass_beer/features/library/presentation/data_sources_screen.dart';

import 'support/fakes.dart';

Map<String, Object?> _comptes(int written, int unchanged, int refused) => {
  'written': written,
  'unchanged': unchanged,
  'refused': refused,
};

/// Document `ingest_runs/{id}` tel que l'écrit `ingest/lib/execution.mjs`.
Map<String, dynamic> runDoc({DateTime? finishedAt}) => {
  'started_at': Timestamp.fromDate(DateTime(2026, 11, 11, 13, 48)),
  'finished_at': Timestamp.fromDate(
    finishedAt ?? DateTime(2026, 11, 11, 13, 49),
  ),
  'target': 'production',
  'counts': <String, Object?>{
    'beer_fermentables': _comptes(412, 3, 0),
    'beer_hops': _comptes(1, 0, 2),
    'beer_styles': _comptes(110, 0, 0),
    'public_recipes': _comptes(415, 0, 0),
  },
  'sources': <Object?>[
    <String, Object?>{'source': 'brewtarget-001', 'version': 'v5.2.3 ea10908'},
    <String, Object?>{'source': 'diydog', 'version': 'e6c12ab'},
  ],
  'unresolved': <String, Object?>{
    'fermentable': 30,
    'hop': 50,
    'culture': 12,
    'misc': 8,
  },
  'report_sha256': 'a' * 64,
};

Map<String, dynamic> unresolvedDoc({
  String nature = 'hop',
  String name = 'Houblon inventé',
  String source = 'diydog',
  Object count = 3,
}) => {
  'nature': nature,
  'name': name,
  'source': source,
  'count': count,
  'updated_at': Timestamp.fromDate(DateTime(2026, 11, 11, 13, 49)),
};

IngredientNonResolu unIngredient(
  String id, {
  String name = 'Houblon inventé',
  String source = 'diydog',
  int count = 3,
}) => IngredientNonResolu.fromFirestore(
  id,
  unresolvedDoc(name: name, source: source, count: count),
);

Future<TestApp> openSources(
  WidgetTester tester, {
  bool offline = false,
  double height = 1600,
  void Function(TestApp app)? before,
}) async {
  final app = TestApp();
  before?.call(app);
  await app.pump(tester, height: height);
  app.signIn(adminUser, member: adminMember, fromCache: offline);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(AppRoutes.adminSources);
  await tester.pumpAndSettle();
  return app;
}

/// Défilement de la page d'Admin › Sources.
Finder get _liste => find
    .descendant(
      of: find.byType(AdminSourcesScreen),
      matching: find.byType(Scrollable),
    )
    .first;

String location(TestApp app) => app.container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .path;

void main() {
  group('domaine', () {
    test('exécution : champs lus, champ inconnu ignoré', () {
      final run = ExecutionIngestion.fromFirestore('20261111T124912Z', {
        ...runDoc(),
        'champ_futur': {'x': 1},
      });
      expect(run.id, '20261111T124912Z');
      expect(run.finishedAt, DateTime(2026, 11, 11, 13, 49));
      expect(run.target, 'production');
      final hops = run.counts.singleWhere((c) => c.collection == 'beer_hops');
      expect((hops.written, hops.unchanged, hops.refused), (1, 0, 2));
      expect(run.sources.map((s) => s.source), ['brewtarget-001', 'diydog']);
      expect(run.sources.first.version, 'v5.2.3 ea10908');
      expect(
        {for (final n in run.unresolved) n.nature: n.count},
        {'fermentable': 30, 'hop': 50, 'culture': 12, 'misc': 8},
      );
    });

    test('exécution : entier rendu en double accepté', () {
      final doc = runDoc();
      doc['unresolved'] = {'hop': 50.0};
      final run = ExecutionIngestion.fromFirestore('id', doc);
      expect(run.unresolved.single.count, 50);
    });

    for (final (champ, modifier)
        in <(String, void Function(Map<String, dynamic>))>[
          ('finished_at', (d) => d.remove('finished_at')),
          ('finished_at', (d) => d['finished_at'] = '2026-11-11'),
          ('target', (d) => d['target'] = 3),
          ('counts', (d) => d.remove('counts')),
          ('counts.beer_hops', (d) => d['counts']['beer_hops'] = 5),
          (
            'counts.beer_hops.refused',
            (d) => d['counts']['beer_hops'].remove('refused'),
          ),
          (
            'counts.beer_hops.written',
            (d) => d['counts']['beer_hops']['written'] = 1.5,
          ),
          ('sources', (d) => d.remove('sources')),
          ('sources[0].version', (d) => d['sources'][0].remove('version')),
          ('unresolved', (d) => d['unresolved'] = []),
          ('unresolved.hop', (d) => d['unresolved']['hop'] = -1),
        ]) {
      test('exécution illisible : $champ', () {
        final doc = runDoc();
        modifier(doc);
        expect(
          () => ExecutionIngestion.fromFirestore('id', doc),
          throwsA(
            isA<DocumentIllisible>().having((e) => e.field, 'field', champ),
          ),
        );
      });
    }

    test('non résolu : champs lus, date facultative', () {
      final i = IngredientNonResolu.fromFirestore('h', {
        ...unresolvedDoc(),
        'inconnu': true,
      });
      expect(
        (i.nature, i.name, i.source, i.count),
        ('hop', 'Houblon inventé', 'diydog', 3),
      );
      expect(i.updatedAt, DateTime(2026, 11, 11, 13, 49));
      final sansDate = IngredientNonResolu.fromFirestore(
        'h',
        unresolvedDoc()..remove('updated_at'),
      );
      expect(sansDate.updatedAt, isNull);
    });

    test('non résolu illisible : nom absent, compte mal typé', () {
      expect(
        () => IngredientNonResolu.fromFirestore(
          'h',
          unresolvedDoc()..remove('name'),
        ),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(
        () => IngredientNonResolu.fromFirestore(
          'h',
          unresolvedDoc(count: 'trois'),
        ),
        throwsA(
          isA<DocumentIllisible>().having((e) => e.field, 'field', 'count'),
        ),
      );
    });
  });

  group('libellés', () {
    test('collections, natures, cible, origine, source', () {
      expect(libelleCollection('beer_fermentables'), 'Malts et sucres');
      expect(libelleCollection('public_recipes'), 'Recettes publiques');
      expect(libelleCollection('beer_styles'), 'Styles');
      expect(libelleCollection('import_unresolved'), 'Noms non reconnus');
      expect(libelleCollection('style_stats'), 'style_stats');
      expect(libelleNatures('culture'), 'Levures');
      expect(libelleNature('misc'), 'Ajout divers');
      expect(libelleNature('inconnue'), 'inconnue');
      expect(libelleNatures('hop'), 'Houblons');
      expect(libelleNature('fermentable'), 'Malt ou sucre');
      expect(libelleCible('production'), 'Production');
      expect(libelleCible('emulator'), 'Émulateur');
      expect(libelleOrigine('diydog'), 'recettes DIY Dog');
      expect(libelleOrigine('import'), 'import d\'un membre');
      expect(
        libelleSourceExecution('brewtarget-005'),
        'Brewtarget, fichier 005',
      );
      expect(libelleSourceExecution('diydog'), 'DIY Dog');
      expect(libelleSourceExecution('kaggle'), 'kaggle');
    });

    test('comptes accordés', () {
      expect(
        ligneComptes(
          const ComptesCollection(
            collection: 'beer_hops',
            written: 412,
            unchanged: 1,
            refused: 0,
          ),
        ),
        '412 écrits · 1 inchangé · 0 refusé',
      );
      expect(libelleFois(1), '1 fois');
      expect(libelleNoms(1), '1 nom');
      expect(libelleNoms(12), '12 noms');
    });

    test('ordre de l\'écran, inconnues à la fin', () {
      ComptesCollection c(String n) => ComptesCollection(
        collection: n,
        written: 0,
        unchanged: 0,
        refused: 0,
      );
      expect(
        comptesOrdonnes([
          c('zeta'),
          c('import_unresolved'),
          c('beer_hops'),
          c('alpha'),
          c('beer_styles'),
        ]).map((x) => x.collection),
        ['beer_styles', 'beer_hops', 'import_unresolved', 'alpha', 'zeta'],
      );
      expect(
        nonResolusOrdonnes(const [
          NonResolusNature(nature: 'misc', count: 1),
          NonResolusNature(nature: 'fermentable', count: 2),
        ]).map((n) => n.nature),
        ['fermentable', 'misc'],
      );
    });
  });

  group('dépôt de données', () {
    late FakeFirebaseFirestore firestore;
    late RecordingErrorReportService errors;
    late FirestoreSourcesRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      errors = RecordingErrorReportService();
      repository = FirestoreSourcesRepository(
        errorReportService: errors,
        firestore: firestore,
      );
    });

    test('aucune exécution : DocumentAbsent', () async {
      final read = await repository.derniereExecution();
      expect(read.execution, isA<DocumentAbsent<ExecutionIngestion>>());
      expect(errors.reports, isEmpty);
    });

    test('dernière exécution par finished_at décroissant', () async {
      await firestore
          .doc('ingest_runs/20261110T080000Z')
          .set(runDoc(finishedAt: DateTime(2026, 11, 10, 8)));
      await firestore.doc('ingest_runs/20261111T124912Z').set(runDoc());
      await firestore
          .doc('ingest_runs/20261109T080000Z')
          .set(runDoc(finishedAt: DateTime(2026, 11, 9, 8)));
      final read = await repository.derniereExecution();
      final run = (read.execution as DocumentTrouve<ExecutionIngestion>).value;
      expect(run.id, '20261111T124912Z');
      expect(read.fromCache, isFalse);
    });

    test('exécution illisible : rapportée, rendue comme telle', () async {
      await firestore
          .doc('ingest_runs/20261111T124912Z')
          .set(runDoc()..['target'] = 7);
      final read = await repository.derniereExecution();
      expect(
        read.execution,
        isA<DocumentIllisibleTrouve<ExecutionIngestion>>(),
      );
      expect(errors.reports.single.feature, 'admin.sources_run_read');
      expect(
        errors.reports.single.context,
        'ingest_runs/20261111T124912Z illisible',
      );
    });

    test('non résolus : pages de 50 par count décroissant', () async {
      for (var i = 0; i < 60; i++) {
        await firestore
            .doc('import_unresolved/${i.toString().padLeft(64, '0')}')
            .set(unresolvedDoc(name: 'Nom $i', count: i + 1));
      }
      final first = await repository.pageNonResolus();
      expect(first.documents, hasLength(kTaillePageNonResolus));
      final counts = [
        for (final d in first.documents)
          (d as DocumentValide<IngredientNonResolu>).value.count,
      ];
      expect(counts.first, 60);
      expect(counts.last, 11);
      expect(first.suite, isNotNull);
      final second = await repository.pageNonResolus(apres: first.suite);
      expect(second.documents, hasLength(10));
      expect(
        (second.documents.first as DocumentValide<IngredientNonResolu>)
            .value
            .count,
        10,
      );
      expect(second.suite, isNull);
      expect(errors.reports, isEmpty);
    });

    test('non résolus illisibles : un seul rapport pour la page', () async {
      await firestore.doc('import_unresolved/${'a' * 64}').set(unresolvedDoc());
      await firestore
          .doc('import_unresolved/${'b' * 64}')
          .set(unresolvedDoc(count: 2)..remove('name'));
      await firestore
          .doc('import_unresolved/${'c' * 64}')
          .set(unresolvedDoc(count: 1)..['nature'] = 4);
      final page = await repository.pageNonResolus();
      expect(page.documents.map((d) => d.runtimeType.toString()), [
        'DocumentValide<IngredientNonResolu>',
        'DocumentInvalide<IngredientNonResolu>',
        'DocumentInvalide<IngredientNonResolu>',
      ]);
      expect(errors.reports, hasLength(1));
      expect(errors.reports.single.feature, 'admin.sources_unresolved_read');
      expect(
        errors.reports.single.context,
        'import_unresolved : 2 documents illisibles sur 3, dont ${'b' * 64}',
      );
    });
  });

  group('écran', () {
    testWidgets('entrée Sources dans Admin, entre Tickets et Import', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.admin);
      await tester.pumpAndSettle();
      final titres = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.title! as Text).data)
          .toList();
      expect(titres, ['Membres', 'Tickets des membres', 'Sources', 'Import']);
      expect(find.text(AdminScreen.sourcesSubtitle), findsOneWidget);
      await tester.tap(find.text('Sources'));
      await tester.pumpAndSettle();
      expect(location(app), AppRoutes.adminSources);
      expect(find.text(AdminSourcesScreen.emptyRun), findsOneWidget);
      expect(find.text(AdminSourcesScreen.emptyUnresolved), findsOneWidget);
    });

    testWidgets('un brasseur n\'ouvre pas Admin › Sources', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminSources);
      await tester.pumpAndSettle();
      expect(location(app), isNot(AppRoutes.adminSources));
      expect(app.sources.executionReads, 0);
      expect(app.sources.pages, isEmpty);
    });

    testWidgets('dernière exécution : date, cible, comptes, sources', (
      tester,
    ) async {
      await openSources(
        tester,
        before: (app) => app.sources.execution = LectureExecution(
          execution: DocumentTrouve(
            ExecutionIngestion.fromFirestore('20261111T124912Z', runDoc()),
          ),
          fromCache: false,
        ),
      );
      expect(find.text('11 novembre 2026 à 13:49'), findsOneWidget);
      expect(find.text('Production'), findsOneWidget);
      expect(
        find.text('import/ingest/rapports/20261111T124912Z.json'),
        findsOneWidget,
      );
      expect(find.text(AdminSourcesScreen.intro), findsOneWidget);
      expect(find.text('Noms non reconnus (cette exécution)'), findsOneWidget);
      expect(find.text('Malts et sucres'), findsNWidgets(2));
      expect(find.text('412 écrits · 3 inchangés · 0 refusé'), findsOneWidget);
      expect(find.text('1 écrit · 0 inchangé · 2 refusés'), findsOneWidget);
      expect(find.text('Recettes publiques'), findsOneWidget);
      expect(
        find.text('2 documents refusés. Le détail est dans le rapport local.'),
        findsOneWidget,
      );
      expect(find.text('Brewtarget, fichier 001'), findsOneWidget);
      expect(find.text('v5.2.3 ea10908'), findsOneWidget);
      expect(find.text('DIY Dog'), findsOneWidget);
      expect(find.text('50 noms'), findsOneWidget);
      expect(find.text('12 noms'), findsOneWidget);
      // Ordre des comptes : celui des segments de la Bibliothèque.
      final styles = tester.getTopLeft(find.text('Styles')).dy;
      final malts = tester.getTopLeft(find.text('Malts et sucres').first).dy;
      expect(styles, lessThan(malts));
    });

    testWidgets('lien vers Sources des données', (tester) async {
      await openSources(tester);
      await tester.tap(find.text(AdminSourcesScreen.sourcesLabel));
      await tester.pumpAndSettle();
      expect(find.byType(DataSourcesScreen), findsOneWidget);
    });

    testWidgets('panne de lecture : message et Réessayer', (tester) async {
      final app = await openSources(
        tester,
        before: (app) {
          app.sources.executionError = Exception('refus');
          app.sources.pageError = Exception('refus');
        },
      );
      expect(find.text(AdminSourcesScreen.runError), findsOneWidget);
      expect(find.text(AdminSourcesScreen.unresolvedError), findsOneWidget);
      app.sources.executionError = null;
      await tester.tap(find.text('Réessayer').first);
      await tester.pumpAndSettle();
      expect(find.text(AdminSourcesScreen.emptyRun), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text(AdminSourcesScreen.emptyUnresolved), findsOneWidget);
      expect(app.sources.executionReads, 2);
      expect(app.sources.pages, hasLength(2));
    });

    testWidgets('Relire : dernière exécution et première page', (tester) async {
      final app = await openSources(tester);
      expect(app.sources.executionReads, 1);
      expect(app.sources.pages, [null]);
      app.sources.execution = LectureExecution(
        execution: DocumentTrouve(
          ExecutionIngestion.fromFirestore('20261111T124912Z', runDoc()),
        ),
        fromCache: false,
      );
      app.sources.nonResolus.add(DocumentValide('a', unIngredient('a')));
      await tester.tap(find.text(AdminSourcesScreen.reload));
      await tester.pumpAndSettle();
      expect(app.sources.executionReads, 2);
      expect(app.sources.pages, [null, null]);
      expect(find.text('Production'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Houblon inventé'),
        300,
        scrollable: _liste,
      );
      expect(find.text('Houblon inventé'), findsOneWidget);
    });

    testWidgets('grand écran : compte rendu borné', (tester) async {
      final app = TestApp();
      app.sources.execution = LectureExecution(
        execution: DocumentTrouve(
          ExecutionIngestion.fromFirestore('20261111T124912Z', runDoc()),
        ),
        fromCache: false,
      );
      await app.pump(tester, width: 1400);
      app.signIn(adminUser, member: adminMember);
      await tester.pumpAndSettle();
      app.container.read(routerProvider).go(AppRoutes.adminSources);
      await tester.pumpAndSettle();
      final ligne = find.ancestor(
        of: find.text('Production'),
        matching: find.byType(LigneFiche),
      );
      expect(tester.getSize(ligne).width, lessThanOrEqualTo(kDialogMaxWidth));
    });

    testWidgets('exécution illisible', (tester) async {
      await openSources(
        tester,
        before: (app) => app.sources.execution = const LectureExecution(
          execution: DocumentIllisibleTrouve(
            DocumentIllisible('target', 'texte obligatoire absent'),
          ),
          fromCache: false,
        ),
      );
      expect(find.text(AdminSourcesScreen.runUnreadable), findsOneWidget);
    });

    testWidgets('hors ligne : panne et cache vide annoncés hors ligne', (
      tester,
    ) async {
      await openSources(
        tester,
        offline: true,
        before: (app) {
          app.sources.executionError = Exception('unavailable');
          app.sources.pagesFromCache = true;
        },
      );
      expect(find.text(AdminSourcesScreen.runOffline), findsOneWidget);
      expect(find.text(AdminSourcesScreen.unresolvedOffline), findsOneWidget);
      expect(find.text(AdminSourcesScreen.runError), findsNothing);
    });

    testWidgets('hors ligne : lecture du cache signalée', (tester) async {
      await openSources(
        tester,
        offline: true,
        height: 2400,
        before: (app) {
          app.sources.execution = LectureExecution(
            execution: DocumentTrouve(
              ExecutionIngestion.fromFirestore('20261111T124912Z', runDoc()),
            ),
            fromCache: true,
          );
          app.sources.pagesFromCache = true;
          app.sources.nonResolus.add(DocumentValide('a', unIngredient('a')));
        },
      );
      expect(find.text(AdminSourcesScreen.runFromCache), findsOneWidget);
      expect(find.text(AdminSourcesScreen.unresolvedFromCache), findsOneWidget);
    });

    testWidgets('non résolus : ligne, origine, illisible, page suivante', (
      tester,
    ) async {
      final app = await openSources(
        tester,
        before: (app) {
          app.sources.nonResolus
            ..add(
              DocumentValide(
                'a',
                unIngredient('a', name: 'Pilsner inventé', count: 12),
              ),
            )
            ..add(
              DocumentValide(
                'b',
                unIngredient('b', name: 'Saaz inventé', source: 'import'),
              ),
            )
            ..add(
              const DocumentInvalide(
                'c',
                DocumentIllisible('name', 'texte obligatoire absent'),
              ),
            );
          for (var i = 0; i < 50; i++) {
            app.sources.nonResolus.add(
              DocumentValide('n$i', unIngredient('n$i', name: 'Nom $i')),
            );
          }
        },
      );
      expect(find.text('Pilsner inventé'), findsOneWidget);
      expect(
        find.text('Houblon · recettes DIY Dog · 12 fois · le 11 nov. 2026'),
        findsOneWidget,
      );
      expect(
        find.text('Houblon · import d\'un membre · 3 fois · le 11 nov. 2026'),
        findsOneWidget,
      );
      expect(find.text(AdminSourcesScreen.rowUnreadable), findsOneWidget);
      expect(find.text(AdminSourcesScreen.rowUnreadableDetail), findsOneWidget);
      final more = find.text(AdminSourcesScreen.showMore);
      await tester.scrollUntilVisible(more, 300, scrollable: _liste);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(app.sources.pages, hasLength(2));
      expect(app.sources.pages.last?.valeur, 50);
      expect(find.text(AdminSourcesScreen.showMore), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Nom 49'),
        300,
        scrollable: _liste,
      );
      expect(find.text('Nom 49'), findsOneWidget);
    });

    testWidgets('page suivante en panne : bandeau, liste gardée', (
      tester,
    ) async {
      final app = await openSources(
        tester,
        before: (app) {
          for (var i = 0; i < 50; i++) {
            app.sources.nonResolus.add(
              DocumentValide('n$i', unIngredient('n$i', name: 'Nom $i')),
            );
          }
        },
      );
      app.sources.pageError = Exception('refus');
      final more = find.text(AdminSourcesScreen.showMore);
      await tester.scrollUntilVisible(more, 300, scrollable: _liste);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text(AdminSourcesScreen.nextPageError), findsOneWidget);
      expect(app.sources.pages, hasLength(2));
      expect(find.text('Nom 49'), findsOneWidget);
    });
  });
}
