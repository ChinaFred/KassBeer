import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/features/brew_day/domain/plan_du_jour.dart';
import 'package:kass_beer/features/brew_day/presentation/brew_day_screen.dart';
import 'package:kass_beer/features/brew_day/presentation/courbe_brassage.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/presentation/trace_courbe.dart'
    show axeDroitLisible;
import 'package:kass_beer/features/recipes/domain/chronologie.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

/// Courbe du jour de brassage : données, résumé lu, états et bascule.

const remplissage = BrewStepLine(
  key: 'k-remplissage',
  name: 'Remplissage de la cuve',
  durationMin: 10,
  tempC: 16,
);
const palier68 = BrewStepLine(
  key: 'k-palier',
  name: 'Palier 68',
  durationMin: 45,
  tempC: 68,
);
const sansTemperature = BrewStepLine(
  key: 'k-ebullition',
  name: 'Ébullition',
  durationMin: 60,
);

DateTime h(int heure, int minute) => DateTime(2026, 11, 21, heure, minute);

String lisible(String texte) => texte.replaceAll(nbsp, ' ');

final eventsCommences = <BrewEvent>[
  debut('e1', remplissage.key, h(10, 0)),
  fin('e2', remplissage.key, h(10, 10)),
  debut('e3', palier68.key, h(10, 15)),
  mesure('m1', remplissage.key, MeasureType.temperature, 15.5, h(10, 5)),
  mesure('m2', palier68.key, MeasureType.temperature, 67, h(10, 30)),
  mesure('m3', null, MeasureType.gravity, 1.05, h(10, 40), pending: true),
];

PlanDuJour planDe(Brew brew, List<BrewEvent> events) =>
    PlanDuJour.calculer(brew: brew, events: events, now: h(10, 45));

final brewCommence = unBrassin(
  steps: const [remplissage, palier68, sansTemperature],
  brewedAt: h(10, 0),
);

Future<RecordingErrorReportService> monter(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
  ThemeData? theme,
}) async {
  final errors = RecordingErrorReportService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [errorReportServiceProvider.overrideWithValue(errors)],
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: ListView(children: [child]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return errors;
}

void main() {
  group('données et résumé', () {
    test('visées de brewing/, mesures de la journée 1, résumé lu', () {
      final d = donneesCourbeBrassage(
        planDe(brewCommence, eventsCommences),
        densiteInitialePrevue: 1.063,
      );
      expect(d.visees.origin, h(10, 0));
      expect(d.visees.planned, hasLength(1));
      expect(d.visees.recomputed, hasLength(1));
      expect(d.temperatures.map((e) => e.id), ['m1', 'm2']);
      expect(d.densites.map((e) => e.id), ['m3']);
      expect(d.etapeDe(d.temperatures.first), 'Remplissage de la cuve');
      expect(
        lisible(resumeCourbeBrassage(d)),
        'Températures du brassage. Visée de 16 °C à 68 °C sur 2 étapes. '
        '2 températures mesurées, de 15,5 °C à 67 °C. '
        'Retard de 5 min sur le plan de départ. '
        'Densité 1050,0 à 10:40 ; initiale prévue 1063,0.',
      );
    });

    test('relevé de fermentation exclu, densité prévue absente', () {
      final events = [
        ...eventsCommences.take(3),
        releve('r1', MeasureType.temperature, 20, h(10, 20)),
      ];
      final d = donneesCourbeBrassage(
        planDe(brewCommence, events),
        densiteInitialePrevue: null,
      );
      expect(d.temperatures, isEmpty);
      expect(d.densiteInitialePrevue, isNull);
      expect(resumeCourbeBrassage(d), isNot(contains('prévue')));
    });
  });

  group('écran du jour', () {
    testWidgets('courbe, légende écrite et résumé pour le lecteur d\'écran', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final plan = planDe(brewCommence, eventsCommences);
      await monter(
        tester,
        CourbeBrassage(
          brew: brewCommence,
          plan: plan,
          densiteInitialePrevue: 1.063,
        ),
      );
      final d = donneesCourbeBrassage(plan, densiteInitialePrevue: 1.063);
      expect(find.bySemanticsLabel(resumeCourbeBrassage(d)), findsOneWidget);
      for (final legende in [
        'Visée (recalculée)',
        'Visée (plan de départ)',
        'Température mesurée',
        'Densité mesurée',
        'Densité initiale prévue 1063,0',
      ]) {
        expect(find.text(legende), findsOneWidget, reason: legende);
      }
      expect(find.text(kCourbeSansMesure), findsNothing);
      semantics.dispose();
    });

    testWidgets('ni visée ni mesure : « Aucune température visée ni '
        'mesurée. »', (tester) async {
      final brew = unBrassin(steps: const [sansTemperature], brewedAt: h(9, 0));
      await monter(
        tester,
        CourbeBrassage(
          brew: brew,
          plan: planDe(brew, const []),
          densiteInitialePrevue: 1.063,
        ),
      );
      expect(find.text(kCourbeVide), findsOneWidget);
    });

    testWidgets('visées seules : invite à saisir une température', (
      tester,
    ) async {
      await monter(
        tester,
        CourbeBrassage(
          brew: brewCommence,
          plan: planDe(brewCommence, eventsCommences.take(3).toList()),
          densiteInitialePrevue: null,
        ),
      );
      expect(find.text(kCourbeSansMesure), findsOneWidget);
      expect(find.textContaining('Densité initiale prévue'), findsNothing);
    });

    testWidgets('mesures seules : aucune étape n\'a de température visée', (
      tester,
    ) async {
      final brew = unBrassin(steps: const [sansTemperature], brewedAt: h(9, 0));
      await monter(
        tester,
        CourbeBrassage(
          brew: brew,
          plan: planDe(brew, [
            mesure('m1', null, MeasureType.temperature, 64, h(9, 10)),
          ]),
          densiteInitialePrevue: null,
        ),
      );
      expect(find.text(kCourbeSansVisee), findsOneWidget);
      expect(find.text('Température mesurée'), findsOneWidget);
    });

    testWidgets('chronologie refusée : courbe indisponible', (tester) async {
      await monter(
        tester,
        CourbeBrassage(
          brew: brewCommence,
          plan: null,
          densiteInitialePrevue: null,
        ),
      );
      expect(find.text(kCourbeChronologieImpossible), findsOneWidget);
    });

    testWidgets('valeur refusée par brewing/ : panne affichée et rapportée', (
      tester,
    ) async {
      final brew = unBrassin(
        steps: const [
          BrewStepLine(
            key: 'k-nan',
            name: 'Température illisible',
            durationMin: 10,
            tempC: double.nan,
          ),
        ],
        brewedAt: h(9, 0),
      );
      final errors = await monter(
        tester,
        CourbeBrassage(
          brew: brew,
          plan: planDe(brew, const []),
          densiteInitialePrevue: null,
        ),
      );
      expect(find.text(kCourbeValeurRefusee), findsOneWidget);
      expect(errors.reports.single.feature, 'brew_day.temperature_curve');
    });

    testWidgets('thème sombre et texte à 200 % : aucune exception', (
      tester,
    ) async {
      await monter(
        tester,
        CourbeBrassage(
          brew: brewCommence,
          plan: planDe(brewCommence, eventsCommences),
          densiteInitialePrevue: 1.063,
        ),
        textScale: 2,
        theme: ThemeData(brightness: Brightness.dark),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('fiche du brassin', () {
    testWidgets('chronologie refusée ou déroulé illisible : rien, la '
        'chronologie dit la panne', (tester) async {
      await monter(
        tester,
        CourbeBrassage(
          brew: brewCommence,
          plan: null,
          densiteInitialePrevue: 1.063,
          surFiche: true,
        ),
      );
      expect(find.text(CourbeBrassage.titreFiche), findsNothing);
      expect(find.text(kCourbeChronologieImpossible), findsNothing);
    });

    testWidgets('valeur refusée avant le premier début : rien', (tester) async {
      final brew = unBrassin(
        steps: const [
          BrewStepLine(
            key: 'k-nan',
            name: 'Température illisible',
            durationMin: 10,
            tempC: double.nan,
          ),
        ],
        status: BrewStatus.planned,
        plannedFor: h(9, 0),
      );
      final errors = await monter(
        tester,
        CourbeBrassage(
          brew: brew,
          plan: planDe(brew, const []),
          densiteInitialePrevue: null,
          surFiche: true,
        ),
      );
      expect(find.text(kCourbeValeurRefusee), findsNothing);
      expect(errors.reports, isEmpty);
    });

    testWidgets('avant le premier début : rien', (tester) async {
      final brew = unBrassin(
        steps: const [remplissage, palier68],
        status: BrewStatus.planned,
        plannedFor: h(9, 0),
      );
      await monter(
        tester,
        CourbeBrassage(
          brew: brew,
          plan: planDe(brew, const []),
          densiteInitialePrevue: 1.063,
          surFiche: true,
        ),
      );
      expect(find.text(CourbeBrassage.titreFiche), findsNothing);
      expect(find.text('Visée (recalculée)'), findsNothing);
    });

    testWidgets('commencé : sous-titre, courbe, message sans invite', (
      tester,
    ) async {
      await monter(
        tester,
        CourbeBrassage(
          brew: brewCommence,
          plan: planDe(brewCommence, eventsCommences.take(3).toList()),
          densiteInitialePrevue: null,
          surFiche: true,
        ),
      );
      expect(find.text(CourbeBrassage.titreFiche), findsOneWidget);
      expect(find.text(kCourbeSansMesureFiche), findsOneWidget);
      expect(find.text(kCourbeSansMesure), findsNothing);
    });

    testWidgets('commencé sans température : courbe masquée', (tester) async {
      final brew = unBrassin(steps: const [sansTemperature], brewedAt: h(9, 0));
      await monter(
        tester,
        CourbeBrassage(
          brew: brew,
          plan: planDe(brew, [debut('e1', sansTemperature.key, h(9, 0))]),
          densiteInitialePrevue: 1.063,
          surFiche: true,
        ),
      );
      expect(find.text(CourbeBrassage.titreFiche), findsNothing);
      expect(find.text(kCourbeVide), findsNothing);
    });
  });

  group('bascule de l\'écran du jour', () {
    testWidgets('« Étapes » à l\'ouverture, « Courbe » à l\'appui', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ZoneChronologieCourbe(
              etapes: Text('liste des étapes'),
              courbe: Text('tracé'),
            ),
          ),
        ),
      );
      expect(find.text('liste des étapes'), findsOneWidget);
      expect(find.text('tracé'), findsNothing);
      await tester.tap(find.text(ZoneChronologieCourbe.libelleCourbe));
      await tester.pumpAndSettle();
      expect(find.text('tracé'), findsOneWidget);
      expect(find.text('liste des étapes'), findsNothing);
    });
  });

  testWidgets('axe des densités : libellés distincts pour 1062,0 mesurée et '
      '1063,0 prévue', (tester) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final brew = unBrassin(steps: const [palier68], brewedAt: h(10, 0));
    await monter(
      tester,
      CourbeBrassage(
        brew: brew,
        plan: planDe(brew, [
          debut('e1', palier68.key, h(10, 0)),
          mesure('m1', palier68.key, MeasureType.gravity, 1.062, h(10, 20)),
        ]),
        densiteInitialePrevue: 1.063,
      ),
    );
    final densites = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null && RegExp(r'^1\d{3},\d$').hasMatch(t.data!)) t.data!,
    ];
    expect(densites, isNotEmpty);
    expect(densites.toSet(), hasLength(densites.length), reason: '$densites');
  });

  group('texte à 200 %', () {
    test('axe de droite sans libellés sous la largeur seuil', () {
      expect(axeDroitLisible(360, 2), isFalse);
      expect(axeDroitLisible(700, 2), isTrue);
      expect(axeDroitLisible(360, 1), isTrue);
    });

    for (final largeur in [360.0, 700.0]) {
      testWidgets('vue « Courbe » sur $largeur px : aucun débordement', (
        tester,
      ) async {
        tester.view.physicalSize = Size(largeur, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final errors = RecordingErrorReportService();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [errorReportServiceProvider.overrideWithValue(errors)],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(largeur, 900),
                  textScaler: const TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: ZoneChronologieCourbe(
                    etapes: const Text('liste des étapes'),
                    courbe: CourbeBrassage(
                      brew: brewCommence,
                      plan: planDe(brewCommence, eventsCommences),
                      densiteInitialePrevue: 1.063,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text(ZoneChronologieCourbe.libelleCourbe));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Visée (recalculée)'), findsOneWidget);
      });
    }
  });
}
