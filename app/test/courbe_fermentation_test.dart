import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/releves.dart';
import 'package:kass_beer/features/brews/presentation/courbe_fermentation.dart';
import 'package:kass_beer/features/brews/presentation/plage_levure.dart';
import 'package:kass_beer/features/brews/presentation/releve_fermentation.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

List<FermentationPoint> serie(
  List<({DateTime at, double? gravity, double? temperature})> lignes,
) => fermentationSeries(
  brewedAt: DateTime(2026, 11, 8, 15, 20),
  readings: [
    for (final l in lignes)
      FermentationReading(
        measuredAt: l.at,
        gravity: l.gravity,
        temperature: l.temperature,
      ),
  ],
);

Future<void> monter(
  WidgetTester tester,
  List<FermentationPoint> points, {
  double textScale = 1,
  ThemeData? theme,
  double? initiale,
  double? finale,
  EtatPlageLevure? plage,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: ListView(
          children: [
            CourbeFermentation(
              points: points,
              densiteInitialePrevue: initiale,
              densiteFinalePrevue: finale,
              plageLevure: plage,
            ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  final complet = serie([
    (at: DateTime(2026, 11, 9, 8), gravity: 1.058, temperature: 20.0),
    (at: DateTime(2026, 11, 12, 18), gravity: 1.03, temperature: null),
    (at: DateTime(2026, 11, 20, 8), gravity: 1.014, temperature: 18.5),
  ]);

  test('résumé : densité sur les jours calendaires, température encadrée', () {
    expect(
      resumeCourbe(complet),
      'Densité de 1058,0 à 1014,0 en 11 jours. '
      'Température entre 18,5$nbsp°C et 20$nbsp°C.',
    );
  });

  test('résumé : sans température, la densité seule', () {
    final points = serie([
      (at: DateTime(2026, 11, 9, 8), gravity: 1.058, temperature: null),
      (at: DateTime(2026, 11, 10, 8), gravity: 1.05, temperature: null),
    ]);
    expect(resumeCourbe(points), 'Densité de 1058,0 à 1050,0 en 1 jour.');
  });

  testWidgets('deux densités : courbe et résumé pour les lecteurs d\'écran', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await monter(tester, complet);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(resumeCourbe(complet)), findsOneWidget);
    expect(find.text('Densité mesurée'), findsOneWidget);
    expect(find.text('Température mesurée (°C)'), findsOneWidget);
    // Sans calcul de la recette : la panne, les mesures toujours tracées.
    expect(find.text(kDensitesPrevuesIndisponibles), findsOneWidget);
    // Sans levure lue : aucun message sur la plage.
    expect(find.textContaining('Levure «'), findsNothing);
    semantics.dispose();
  });

  testWidgets('une seule densité : pas de courbe', (tester) async {
    final points = serie([
      (at: DateTime(2026, 11, 9, 8), gravity: 1.058, temperature: 20),
      (at: DateTime(2026, 11, 10, 8), gravity: null, temperature: 19),
    ]);
    await monter(tester, points);
    await tester.pumpAndSettle();
    expect(find.text('Densité mesurée'), findsNothing);
  });

  testWidgets('température absente sur certains points : densité tracée', (
    tester,
  ) async {
    final points = serie([
      (at: DateTime(2026, 11, 9, 8), gravity: 1.058, temperature: null),
      (at: DateTime(2026, 11, 12, 8), gravity: 1.03, temperature: null),
    ]);
    await monter(tester, points);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Température mesurée (°C)'), findsNothing);
  });

  testWidgets('thème sombre et texte à 200 % : aucune exception', (
    tester,
  ) async {
    await monter(
      tester,
      complet,
      textScale: 2,
      theme: ThemeData(brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dans la fiche, une même heure ne casse pas le tracé', (
    tester,
  ) async {
    final at = DateTime(2026, 11, 12, 8);
    final points = serie([
      (at: at, gravity: 1.05, temperature: 20),
      (at: at, gravity: 1.048, temperature: 19),
    ]);
    await monter(tester, points);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('résumé : densités prévues ajoutées', () {
    expect(
      resumeCourbe(complet, initiale: 1.063, finale: 1.012),
      'Densité de 1058,0 à 1014,0 en 11 jours. '
      'Température entre 18,5$nbsp°C et 20$nbsp°C. '
      'Initiale prévue 1063,0, finale prévue 1012,0.',
    );
    expect(
      resumeCourbe(complet, finale: 1.012),
      endsWith('Finale prévue 1012,0.'),
    );
  });

  test('info-bulle d\'une densité prévue : écart en points', () {
    expect(
      infoBullePrevue('Finale prévue', 1.012, 8),
      'Finale prévue 1012,0 · écart +8,0${nbsp}pts',
    );
    expect(
      infoBullePrevue('Initiale prévue', 1.063, null),
      'Initiale prévue 1063,0',
    );
  });

  testWidgets('densités prévues : deux lignes nommées, aucune panne', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await monter(tester, complet, initiale: 1.063, finale: 1.012);
    await tester.pumpAndSettle();
    expect(find.text('Initiale prévue 1063,0'), findsOneWidget);
    expect(find.text('Finale prévue 1012,0'), findsOneWidget);
    expect(find.text(kDensitesPrevuesIndisponibles), findsNothing);
    expect(
      find.bySemanticsLabel(
        resumeCourbe(complet, initiale: 1.063, finale: 1.012),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test('densité initiale du jour : premier point de la courbe seule', () {
    final brew = unBrassin(brewedAt: DateTime(2026, 11, 8, 10));
    final og = mesure(
      'og',
      null,
      MeasureType.gravity,
      1.063,
      DateTime(2026, 11, 8, 15, 50),
    );
    final ascendants = relevesDe([
      releve('r1', MeasureType.gravity, 1.02, DateTime(2026, 11, 12, 8)),
    ]);
    final errors = RecordingErrorReportService();
    final liste = serieDesReleves(
      brew: brew,
      ascendants: ascendants,
      errors: errors,
      reported: {},
    )!;
    final courbe = serieDesReleves(
      brew: brew,
      ascendants: ascendants,
      initiale: og,
      errors: errors,
      reported: {},
    )!;
    // Liste : le relevé seul, sans écart ; courbe : deux densités, le seuil
    // est atteint avec un seul relevé.
    expect(liste, hasLength(1));
    expect(liste.single.gravityChangePoints, isNull);
    expect(courbe, hasLength(2));
    expect(courbe.first.gravity, 1.063);
    expect(courbe.first.measuredAt, og.measuredAt);
    expect(
      courbe.where((p) => p.gravity != null).length,
      greaterThanOrEqualTo(kCourbeDensitesMin),
    );
    expect(errors.reports, isEmpty);
  });

  testWidgets('une seule densité prévue : le manque est dit', (tester) async {
    await monter(tester, complet, initiale: 1.063);
    await tester.pumpAndSettle();
    expect(find.text(kDensiteFinalePrevueIndisponible), findsOneWidget);
    expect(find.text(kDensitesPrevuesIndisponibles), findsNothing);
    await monter(tester, complet, finale: 1.012);
    await tester.pumpAndSettle();
    expect(find.text(kDensiteInitialePrevueIndisponible), findsOneWidget);
  });

  testWidgets('plage de la levure : aplat nommé, résumé ; sinon un message '
      'court', (tester) async {
    final semantics = tester.ensureSemantics();
    const plage = PlageLevureConnue(18, 22);
    await monter(tester, complet, initiale: 1.063, finale: 1.012, plage: plage);
    await tester.pumpAndSettle();
    expect(find.text('Plage de la levure (18 à 22$nbsp°C)'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        resumeCourbe(complet, initiale: 1.063, finale: 1.012, plage: plage),
      ),
      findsOneWidget,
    );
    expect(
      resumeCourbe(complet, plage: plage),
      endsWith('Plage de la levure 18 à 22$nbsp°C.'),
    );
    await monter(
      tester,
      complet,
      initiale: 1.063,
      finale: 1.012,
      plage: const LevureSansPlage('SafAle US-05'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Levure « SafAle US-05 » sans plage de température dans la '
        'Bibliothèque : pas de température visée.',
      ),
      findsOneWidget,
    );
    await monter(
      tester,
      complet,
      initiale: 1.063,
      finale: 1.012,
      plage: const LevureAbsenteDeLaBibliotheque('Levure de la maison'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Levure « Levure de la maison » absente de la Bibliothèque : pas de '
        'température visée.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('plage sans température mesurée, texte à 200 % sur 360 px : '
      'aucune exception', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final points = serie([
      (at: DateTime(2026, 11, 9, 8), gravity: 1.058, temperature: null),
      (at: DateTime(2026, 11, 12, 8), gravity: 1.03, temperature: null),
    ]);
    await monter(
      tester,
      points,
      textScale: 2,
      plage: const PlageLevureConnue(18, 22),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
