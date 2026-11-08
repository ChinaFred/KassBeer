import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/features/brews/presentation/courbe_fermentation.dart';

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
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: ListView(children: [CourbeFermentation(points: points)]),
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
    expect(find.text('Densité'), findsOneWidget);
    expect(find.text('Température (°C)'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('une seule densité : pas de courbe', (tester) async {
    final points = serie([
      (at: DateTime(2026, 11, 9, 8), gravity: 1.058, temperature: 20),
      (at: DateTime(2026, 11, 10, 8), gravity: null, temperature: 19),
    ]);
    await monter(tester, points);
    await tester.pumpAndSettle();
    expect(find.text('Densité'), findsNothing);
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
    expect(find.text('Température (°C)'), findsNothing);
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
}
