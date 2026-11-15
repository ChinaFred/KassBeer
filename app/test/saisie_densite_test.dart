import 'package:brewing/brewing.dart' show EtatDensite, InstrumentDensite;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/providers.dart';
import 'package:kass_beer/features/brew_day/presentation/chronologie_jour.dart';
import 'package:kass_beer/features/brew_day/presentation/mesure_form.dart';
import 'package:kass_beer/features/brews/domain/brew_event.dart';
import 'package:kass_beer/features/brews/domain/densites.dart';
import 'package:kass_beer/features/brews/domain/mesures_retenues.dart';
import 'package:kass_beer/features/brews/domain/preference_mesure.dart';
import 'package:kass_beer/features/brews/domain/releves.dart';
import 'package:kass_beer/features/brews/presentation/saisie_densite.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

/// Instrument de densité : lecture brute stockée, valeur retenue calculée par
/// `brewing/` à l'affichage.

String lisible(String texte) => texte.replaceAll(nbsp, ' ');

final at = DateTime(2026, 11, 15, 10);

BrewEvent densite(
  String id,
  double? value,
  DetailDensite? detail, {
  bool fermentation = false,
  DateTime? quand,
}) => BrewEvent(
  id: id,
  ownerUid: 'uid-brasseur',
  kind: BrewEventKind.measurement,
  measureType: MeasureType.gravity,
  value: value,
  measuredAt: quand ?? at,
  phase: fermentation ? PhaseEvenement.fermentation : null,
  densite: detail,
);

Future<List<SaisieMesure>> monterFormulaire(
  WidgetTester tester, {
  DensiteSaisie? initialDensite,
}) async {
  final soumis = <SaisieMesure>[];
  final errors = RecordingErrorReportService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [errorReportServiceProvider.overrideWithValue(errors)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FormulaireMesure(
              steps: const [],
              initialStepKey: null,
              initialType: MeasureType.gravity,
              initialDensite: initialDensite,
              now: () => at,
              onSubmit: soumis.add,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return soumis;
}

DensiteSaisie instrument(InstrumentDensite i, {double? facteur}) =>
    DensiteSaisie(
      detail: DetailDensite(
        instrument: i,
        facteur: facteur,
        corriger: i.corrige ? true : null,
      ),
    );

Future<void> enregistrer(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Enregistrer la mesure'));
  await tester.tap(find.text('Enregistrer la mesure'));
  await tester.pumpAndSettle();
}

void main() {
  group('formulaire de mesure', () {
    testWidgets('sans préférence : « À choisir », densité simple', (
      tester,
    ) async {
      final soumis = await monterFormulaire(tester);
      expect(find.text('Densimètre : À choisir'), findsOneWidget);
      expect(
        find.widgetWithText(
          TextFormField,
          'Température de l\'échantillon (°C)',
        ),
        findsNothing,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1050',
      );
      await enregistrer(tester);
      expect(soumis.single.value, 1.05);
      expect(soumis.single.densite, isNull);
    });

    testWidgets('flottant à 20 °C : correction proposée, case Corriger', (
      tester,
    ) async {
      final soumis = await monterFormulaire(
        tester,
        initialDensite: instrument(InstrumentDensite.flottant20),
      );
      expect(
        find.text('Densimètre : Densimètre flottant, étalonné à 20$nbsp°C'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité lue'),
        '1050',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Température de l\'échantillon (°C)',
        ),
        '68',
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Densité corrigée à 20$nbsp°C : ≈${nbsp}1070,7 (+20,7${nbsp}pts)',
        ),
        findsOneWidget,
      );
      expect(find.text(kCorrectionApprochee), findsOneWidget);
      expect(find.text('Valeur retenue : 1070,7, corrigée'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        find.text('Valeur retenue : 1050,0, lue à 68$nbsp°C'),
        findsOneWidget,
      );
      await enregistrer(tester);
      final s = soumis.single;
      expect(s.value, 1.05, reason: 'la lecture brute est stockée');
      expect(s.densite!.instrument, InstrumentDensite.flottant20);
      expect(s.densite!.temperatureEchantillon, 68);
      expect(s.densite!.corriger, isFalse);
    });

    testWidgets('flottant hors plage : correction impossible, sans case', (
      tester,
    ) async {
      await monterFormulaire(
        tester,
        initialDensite: instrument(InstrumentDensite.flottant20),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité lue'),
        '1050',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Température de l\'échantillon (°C)',
        ),
        '80',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Correction impossible au-delà de 75$nbsp°C.'),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);
      expect(
        find.text('Valeur retenue : 1050,0, lue à 80$nbsp°C'),
        findsOneWidget,
      );
    });

    testWidgets('électronique : densité seule, aucune correction', (
      tester,
    ) async {
      final soumis = await monterFormulaire(
        tester,
        initialDensite: instrument(InstrumentDensite.electronique),
      );
      expect(
        find.widgetWithText(
          TextFormField,
          'Température de l\'échantillon (°C)',
        ),
        findsNothing,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Densité'),
        '1050',
      );
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      await enregistrer(tester);
      expect(soumis.single.value, 1.05);
      expect(soumis.single.densite!.instrument, InstrumentDensite.electronique);
      expect(soumis.single.densite!.corriger, isNull);
    });

    testWidgets('réfractomètre sans facteur : °Brix stocké, aucune densité', (
      tester,
    ) async {
      final soumis = await monterFormulaire(
        tester,
        initialDensite: instrument(InstrumentDensite.refractometre),
      );
      expect(find.text(kFacteurARenseigner), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lecture (°Brix)'),
        '12,4',
      );
      await enregistrer(tester);
      final s = soumis.single;
      expect(s.value, isNull);
      expect(s.densite!.brix, 12.4);
      expect(s.densite!.facteur, isNull);
    });

    testWidgets('feuille Densimètre : « Choisissez un instrument. »', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await monterFormulaire(tester);
      expect(find.bySemanticsLabel('Changer le densimètre'), findsOneWidget);
      await tester.tap(find.text('Changer'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text(kChoisirInstrument), findsOneWidget);
      handle.dispose();
    });

    testWidgets('réfractomètre avec facteur : conversion affichée', (
      tester,
    ) async {
      await monterFormulaire(
        tester,
        initialDensite: instrument(
          InstrumentDensite.refractometre,
          facteur: 1.04,
        ),
      );
      expect(
        find.text('Densimètre : Réfractomètre, facteur 1,04'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lecture (°Brix)'),
        '12,4',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Valeur retenue : 1048,1, lue 12,4$nbsp°Brix'),
        findsOneWidget,
      );
    });
  });

  group('lecture et écriture des événements', () {
    test('détail écrit puis relu', () {
      final e = densite(
        'd1',
        1.05,
        const DetailDensite(
          instrument: InstrumentDensite.flottant20,
          temperatureEchantillon: 68,
          corriger: true,
        ),
      );
      final data = Map<String, dynamic>.from(e.toFirestore())
        ..['created_at'] = Timestamp.fromDate(at);
      expect(data['gravity_instrument'], 'hydrometer_20c');
      expect(data['sample_temperature'], 68);
      expect(data['correct'], true);
      expect(data.containsKey('brix'), isFalse);
      final relu = BrewEvent.fromFirestore('d1', data);
      expect(relu.value, 1.05);
      expect(relu.densite!.temperatureEchantillon, 68);
    });

    test('mesure sans instrument : aucun champ ajouté', () {
      final data = densite('d1', 1.05, null).toFirestore();
      expect(data.containsKey('gravity_instrument'), isFalse);
    });

    test('formes refusées à la lecture', () {
      Map<String, dynamic> base(Map<String, dynamic> extra) => {
        'owner_uid': 'u',
        'kind': 'measurement',
        'measure_type': 'gravity',
        'measured_at': Timestamp.fromDate(at),
        ...extra,
      };
      for (final cas in [
        {'value': 1.05, 'gravity_instrument': 'rapt', 'correct': true},
        {
          'value': 1.05,
          'gravity_instrument': 'refractometer',
          'brix': 12,
          'correct': true,
        },
        {'gravity_instrument': 'refractometer', 'brix': 41, 'correct': true},
        {'value': 1.05, 'gravity_instrument': 'digital', 'correct': true},
        {'value': 1.05, 'brix': 12},
        {'gravity_instrument': 'hydrometer_20c', 'correct': true},
      ]) {
        expect(
          () => BrewEvent.fromFirestore('x', base(cas)),
          throwsA(isA<DocumentIllisible>()),
          reason: '$cas',
        );
      }
      final temperature = {
        'owner_uid': 'u',
        'kind': 'measurement',
        'measure_type': 'temperature',
        'value': 20,
        'gravity_instrument': 'digital',
        'measured_at': Timestamp.fromDate(at),
      };
      expect(
        () => BrewEvent.fromFirestore('x', temperature),
        throwsA(isA<DocumentIllisible>()),
      );
    });

    test('préférence : lue, instrument inconnu refusé', () {
      final p = PreferenceMesure.fromFirestore({
        'gravity_instrument': 'refractometer',
        'refractometer_factor': 1.04,
      });
      expect(p.instrument, InstrumentDensite.refractometre);
      expect(p.facteur, 1.04);
      expect(
        () => PreferenceMesure.fromFirestore({'gravity_instrument': 'rapt'}),
        throwsA(isA<DocumentIllisible>()),
      );
      expect(
        () => PreferenceMesure.fromFirestore({
          'gravity_instrument': 'refractometer',
          'refractometer_factor': 2,
        }),
        throwsA(isA<DocumentIllisible>()),
      );
    });
  });

  group('valeur retenue dans les calculs', () {
    test('densité initiale corrigée, finale au réfractomètre corrigée', () {
      final brew = unBrassin(brewedAt: at);
      final og = densite(
        'og',
        1.05,
        const DetailDensite(
          instrument: InstrumentDensite.flottant20,
          temperatureEchantillon: 68,
          corriger: true,
        ),
      );
      final fg = densite(
        'fg',
        null,
        const DetailDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 6.5,
          facteur: 1.04,
          corriger: true,
        ),
        fermentation: true,
        quand: at.add(const Duration(days: 7)),
      );
      final r = MesuresRetenues.de(brew, [og, fg]);
      expect(r.densiteInitiale!.value, closeTo(1.070706, 1e-6));
      expect(r.densiteInitiale!.densite!.estCorrigee, isTrue);
      // Terrill avec le °Brix initial tiré de 1.0707 : plus bas qu'une
      // conversion simple.
      final finale = r.densiteFinale!.value!;
      expect(finale, lessThan(densiteDe(fg).sg!));
      expect(r.densite(fg).etat, EtatDensite.corrigee);
      final releve = relevesDe([fg], densiteInitiale: r.densiteInitialeSg);
      expect(releve.single.gravityValue, closeTo(finale, 1e-12));
    });

    test('réfractomètre sans facteur : jamais retenu automatiquement', () {
      final brew = unBrassin(brewedAt: at);
      final brix = densite(
        'b',
        null,
        const DetailDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 12.4,
          corriger: true,
        ),
        quand: at.add(const Duration(hours: 1)),
      );
      final lue = densite('l', 1.048, null);
      expect(
        MesuresRetenues.de(brew, [lue, brix]).densiteInitiale!.event.id,
        'l',
      );
    });

    test('libellés de la chronologie', () {
      final corrigee = densite(
        'c',
        1.05,
        const DetailDensite(
          instrument: InstrumentDensite.flottant20,
          temperatureEchantillon: 68,
          corriger: true,
        ),
      );
      expect(
        lisible(libelleSaisie(corrigee)),
        '10:00 · Densité ≈ 1070,7 · corrigée, lue 1050,0 à 68 °C',
      );
      final brute = densite(
        'n',
        1.05,
        const DetailDensite(
          instrument: InstrumentDensite.flottant20,
          temperatureEchantillon: 30,
          corriger: false,
        ),
      );
      expect(
        lisible(libelleSaisie(brute)),
        '10:00 · Densité 1050,0 · lue à 30 °C, sans correction',
      );
      expect(
        lisible(libelleSaisie(densite('a', 1.05, null))),
        '10:00 · 1050,0',
      );
      final sansFacteur = densite(
        'r',
        null,
        const DetailDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 12.4,
          corriger: true,
        ),
      );
      expect(
        lisible(libelleSaisie(sansFacteur)),
        '10:00 · Densité 12,4 °Brix · facteur à renseigner',
      );
    });
  });
}
