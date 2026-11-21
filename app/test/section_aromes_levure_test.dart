import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/etiquette.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/library/domain/aromes_levure.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/data_sources_screen.dart';
import 'package:kass_beer/features/library/presentation/library_providers.dart';
import 'package:kass_beer/features/library/presentation/reference_entry_screen.dart';
import 'package:kass_beer/features/library/presentation/section_aromes.dart';
import 'package:kass_beer/features/library/presentation/section_aromes_levure.dart';

import 'support/fakes.dart';
import 'support/library_fixtures.dart';

const _id = 'culture-levure-fictive';
const _chemin = '/bibliotheque/levures/$_id';

/// Ouvre la fiche de la levure fictive ; [aromes] : document de
/// `beer_culture_aromas/culture-levure-fictive` lu, absent par défaut ;
/// [fiche] : document de `beer_cultures/`.
Future<TestApp> ouvrir(
  WidgetTester tester, {
  Map<String, dynamic>? aromes,
  Map<String, dynamic>? fiche,
  bool offline = false,
  void Function(TestApp app)? before,
}) async {
  final app = TestApp();
  app.library.fiches[_id] = DocumentTrouve(
    FicheReferentiel.fromFirestore(
      NatureReferentiel.cultures,
      _id,
      fiche ?? cultureDoc(),
    ),
  );
  if (aromes != null) {
    app.library.aromesLevures[_id] = DocumentTrouve(
      AromesLevure.fromFirestore(aromes),
    );
  }
  before?.call(app);
  await app.pump(tester, height: 2400);
  app.signIn(brewerUser, member: brewerMember, fromCache: offline);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(_chemin);
  await tester.pumpAndSettle();
  return app;
}

double _haut(WidgetTester tester, String texte) =>
    tester.getTopLeft(find.text(texte)).dy;

void main() {
  final bas = TextesAromesLevure.basDePlage(15);
  final haut = TextesAromesLevure.hautDePlage(20);

  test('sous-titres : borne présente au format de « Valeurs », sinon sans '
      'parenthèses', () {
    expect(bas, 'En bas de plage (${formatCelsius(15)})');
    expect(haut, 'En haut de plage (${formatCelsius(20)})');
    expect(bas, 'En bas de plage (15 °C)');
    expect(TextesAromesLevure.basDePlage(null), 'En bas de plage');
    expect(TextesAromesLevure.hautDePlage(null), 'En haut de plage');
  });

  testWidgets('décrit : ordre de la section, entre Valeurs et Provenance', (
    tester,
  ) async {
    final app = await ouvrir(tester, aromes: cultureAromaDoc());
    expect(find.bySemanticsLabel('Descripteurs : poire, sec'), findsOneWidget);
    expect(find.text(kTexteProfil), findsOneWidget);
    expect(find.text(kTexteBas), findsOneWidget);
    expect(find.text(kTexteHaut), findsOneWidget);
    expect(find.textContaining('relu'), findsNothing);
    expect(find.text(TextesAromes.confianceFaible), findsNothing);
    expect(find.text('bjcp2021-21a'), findsNothing);
    final ordre = [
      'Valeurs',
      TextesAromes.titre,
      TextesAromes.mention,
      'poire',
      TextesAromesLevure.profil,
      kTexteProfil,
      bas,
      kTexteBas,
      haut,
      kTexteHaut,
      TextesAromesLevure.stylesConseilles,
      'American IPA',
      'American Pale Ale',
      'Provenance',
    ];
    final positions = [for (final t in ordre) _haut(tester, t)];
    expect(positions, [...positions]..sort());
    expect(app.library.aromesLevuresReads, [_id]);
    expect(app.library.aromesReads, isEmpty);
  });

  testWidgets('borne absente : sous-titre sans parenthèses', (tester) async {
    await ouvrir(
      tester,
      aromes: cultureAromaDoc(),
      fiche: cultureDoc(
        temperature: const {
          'minimum': {'value': 15, 'unit': 'C'},
        },
      ),
    );
    expect(find.text(bas), findsOneWidget);
    expect(find.text('En haut de plage'), findsOneWidget);
  });

  testWidgets('plage absente : sous-titres sans parenthèses', (tester) async {
    await ouvrir(
      tester,
      aromes: cultureAromaDoc(),
      fiche: cultureDoc(temperature: null),
    );
    expect(find.text('En bas de plage'), findsOneWidget);
    expect(find.text('En haut de plage'), findsOneWidget);
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('cool, warm et styles absents : rien pour eux', (tester) async {
    await ouvrir(
      tester,
      aromes: cultureAromaDoc(
        texts: {
          'profile': {'text': kTexteProfil},
        },
        extra: {'styles': <Object>[]},
      ),
    );
    expect(find.text(kTexteProfil), findsOneWidget);
    expect(find.textContaining('de plage'), findsNothing);
    expect(find.text(TextesAromesLevure.stylesConseilles), findsNothing);
  });

  testWidgets('style : l\'appui ouvre sa fiche, cible de 48 px', (
    tester,
  ) async {
    final app = await ouvrir(tester, aromes: cultureAromaDoc());
    final bouton = find.ancestor(
      of: find.text('American IPA'),
      matching: find.byType(TextButton),
    );
    expect(tester.getSize(bouton).height, greaterThanOrEqualTo(48));
    await tester.tap(find.text('American IPA'));
    await tester.pumpAndSettle();
    // Adresse AppRoutes.libraryEntry('styles', code), ouverte par-dessus.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is ReferenceEntryScreen &&
            w.segment == SegmentBibliotheque.styles &&
            w.id == 'bjcp2021-21a',
      ),
      findsOneWidget,
    );
    expect(app.library.ficheReads, contains('bjcp2021-21a'));
  });

  testWidgets('nom de style long : passe à la ligne sans déborder', (
    tester,
  ) async {
    final long = 'Style au nom très long ' * 8;
    await ouvrir(
      tester,
      aromes: cultureAromaDoc(
        extra: {
          'styles': [
            {'code': 'bjcp2021-21a', 'name': long},
          ],
        },
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text(long)).height, greaterThan(30));
  });

  testWidgets('confiance faible : étiquette', (tester) async {
    await ouvrir(tester, aromes: cultureAromaDoc(extra: {'confidence': 'low'}));
    expect(
      find.widgetWithText(Etiquette, TextesAromes.confianceFaible),
      findsOneWidget,
    );
  });

  testWidgets('unknown : mention, aucune description', (tester) async {
    await ouvrir(tester, aromes: cultureAromaUnknownDoc());
    expect(find.text(TextesAromes.mention), findsOneWidget);
    expect(find.text(TextesAromesLevure.inconnu), findsOneWidget);
    expect(find.text(TextesAromesLevure.profil), findsNothing);
  });

  testWidgets('document absent : ni titre ni rapport', (tester) async {
    final app = await ouvrir(tester);
    expect(find.text('Température de fermentation'), findsOneWidget);
    expect(find.text(TextesAromes.titre), findsNothing);
    expect(app.errors.reports, isEmpty);
    expect(app.library.aromesLevuresReads, [_id]);
  });

  testWidgets('illisible : panne affichée, sans bouton', (tester) async {
    await ouvrir(
      tester,
      before: (app) => app.library.aromesLevures[_id] =
          const DocumentIllisibleTrouve(DocumentIllisible('status', 'x')),
    );
    expect(find.text(TextesAromes.illisible), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('chargement puis contenu', (tester) async {
    final attente = Completer<void>();
    final app = TestApp();
    app.library.fiches[_id] = DocumentTrouve(
      FicheReferentiel.fromFirestore(
        NatureReferentiel.cultures,
        _id,
        cultureDoc(),
      ),
    );
    app.library.aromesLevuresAttente[_id] = attente;
    app.library.aromesLevures[_id] = DocumentTrouve(
      AromesLevure.fromFirestore(cultureAromaDoc()),
    );
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go(_chemin);
    await tester.pump();
    await tester.pump();
    expect(find.text('Température de fermentation'), findsOneWidget);
    expect(find.text(TextesAromes.chargement), findsOneWidget);
    attente.complete();
    await tester.pumpAndSettle();
    expect(find.text(TextesAromes.chargement), findsNothing);
    expect(find.text(kTexteProfil), findsOneWidget);
  });

  testWidgets('panne en ligne : Réessayer relit', (tester) async {
    final app = await ouvrir(
      tester,
      before: (app) =>
          app.library.aromesLevuresErrors[_id] = Exception('refus'),
    );
    expect(find.text(TextesAromes.panne), findsOneWidget);
    app.library.aromesLevuresErrors.clear();
    app.library.aromesLevures[_id] = DocumentTrouve(
      AromesLevure.fromFirestore(cultureAromaDoc()),
    );
    final attente = Completer<void>();
    app.library.aromesLevuresAttente[_id] = attente;
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Lecture en cours'), findsOneWidget);
    attente.complete();
    await tester.pumpAndSettle();
    expect(find.text(TextesAromes.panne), findsNothing);
    expect(find.text(kTexteProfil), findsOneWidget);
    expect(app.library.aromesLevuresReads, [_id, _id]);
  });

  testWidgets('hors ligne, lecture en échec : indisponible, sans bouton', (
    tester,
  ) async {
    await ouvrir(
      tester,
      offline: true,
      before: (app) =>
          app.library.aromesLevuresErrors[_id] = Exception('hors ligne'),
    );
    expect(find.text(TextesAromes.horsLigne), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('hors ligne, absent du cache : indisponible', (tester) async {
    await ouvrir(
      tester,
      offline: true,
      before: (app) =>
          app.library.aromesLevures[_id] = const DocumentAbsentDuCache(),
    );
    expect(find.text(TextesAromes.horsLigne), findsOneWidget);
  });

  testWidgets('Sources des données : arômes des levures', (tester) async {
    final app = TestApp();
    await app.pump(tester, height: 2400);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/sources-des-donnees');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(DataSourcesScreen.aromesLevures),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(DataSourcesScreen.aromesLevures), findsOneWidget);
    expect(
      _haut(tester, DataSourcesScreen.aromesHoublons) <
          _haut(tester, DataSourcesScreen.aromesLevures),
      isTrue,
    );
    expect(DataSourcesScreen.aromesLevures, isNot(contains('relu')));
    expect(DataSourcesScreen.aromesHoublons, isNot(contains('relu')));
  });
}
