import 'package:brewing/brewing.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

double _nombre(Object? value) => value == 'NaN' ? double.nan : number(value);

void main() {
  final hydrometer = loadFixture('hydrometer');
  final refractometer = loadFixture('refractometer');

  group('densimètre flottant', () {
    test('plages de la fixture', () {
      final ranges = hydrometer['ranges'] as Map<String, Object?>;
      expect(kCorrectionTemperatureMinC, number(ranges['min_c']));
      expect(kCorrectionExacteMaxC, number(ranges['exact_max_c']));
      expect(kCorrectionApprocheeMaxC, number(ranges['approximate_max_c']));
    });

    test('masse volumique de l\'eau (Kell 1975)', () {
      for (final c in objects(hydrometer['water_density'])) {
        expectCase(c, masseVolumiqueEau(number(c['celsius'])));
      }
    });

    test('correction et plage', () {
      for (final c in objects(hydrometer['correction'])) {
        final instrument = InstrumentDensite.fromStored(
          c['instrument'] as String,
        );
        final sample = number(c['sample_c']);
        expectCase(
          c,
          corrigerDensimetre(
            lectureSg: number(c['reading']),
            echantillonC: sample,
            etalonnageC: instrument.temperatureEtalonnageC!,
          ),
        );
        final retenue = densiteRetenue(
          LectureDensite(
            instrument: instrument,
            sg: number(c['reading']),
            temperatureEchantillonC: sample,
          ),
        );
        expectCase(c, retenue.sg!);
        expect(
          retenue.etat,
          c['range'] == 'exact' ? EtatDensite.corrigee : EtatDensite.approchee,
          reason: label(c),
        );
        expect(
          plageCorrection(sample),
          c['range'] == 'exact'
              ? PlageCorrection.exacte
              : PlageCorrection.approchee,
          reason: label(c),
        );
      }
    });

    test('correction impossible : lecture brute retenue', () {
      for (final c in objects(hydrometer['impossible'])) {
        final lecture = number(c['reading']);
        final sample = number(c['sample_c']);
        final plage = c['range'] == 'too_cold'
            ? PlageCorrection.tropFroid
            : PlageCorrection.tropChaud;
        expect(plageCorrection(sample), plage, reason: label(c));
        expect(plage.impossible, isTrue);
        final retenue = densiteRetenue(
          LectureDensite(
            instrument: InstrumentDensite.fromStored(c['instrument'] as String),
            sg: lecture,
            temperatureEchantillonC: sample,
          ),
        );
        expect(retenue.sg, lecture, reason: label(c));
        expect(retenue.etat, EtatDensite.horsPlage, reason: label(c));
        expect(retenue.plage, plage, reason: label(c));
        expect(retenue.corrigee, isNull, reason: label(c));
      }
    });

    test('entrées invalides', () {
      for (final c in objects(hydrometer['invalid'])) {
        expectInvalid(
          () => corrigerDensimetre(
            lectureSg: _nombre(c['reading']),
            echantillonC: _nombre(c['sample_c']),
            etalonnageC: 20,
          ),
          label(c),
        );
      }
      expectInvalid(() => plageCorrection(double.nan), 'NaN');
    });

    test('case décochée : lecture brute, correction proposée', () {
      final retenue = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.flottant20,
          sg: 1.05,
          temperatureEchantillonC: 68,
          corriger: false,
        ),
      );
      expect(retenue.sg, 1.05);
      expect(retenue.etat, EtatDensite.nonCorrigee);
      expect(retenue.corrigee, closeTo(1.070706, 1e-6));
      expect(retenue.estCorrigee, isFalse);
      expect(retenue.correctionApprochee, isTrue);
    });

    test('sans température : lecture brute', () {
      final retenue = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.flottant20,
          sg: 1.05,
        ),
      );
      expect(retenue.sg, 1.05);
      expect(retenue.etat, EtatDensite.sansTemperature);
    });

    test('correction hors de 0,980 à 1,200 : lecture brute', () {
      final retenue = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.flottant20,
          sg: 1.19,
          temperatureEchantillonC: 70,
        ),
      );
      expect(retenue.sg, 1.19);
      expect(retenue.etat, EtatDensite.horsBornes);
    });
  });

  group('sans correction', () {
    test('mesure ancienne, électronique, autre : densité lue', () {
      for (final instrument in [
        null,
        InstrumentDensite.electronique,
        InstrumentDensite.autre,
      ]) {
        final retenue = densiteRetenue(
          LectureDensite(
            instrument: instrument,
            sg: 1.05,
            temperatureEchantillonC: 68,
            enFermentation: true,
          ),
          densiteInitialeSg: 1.06,
        );
        expect(retenue.sg, 1.05, reason: '$instrument');
        expect(retenue.etat, EtatDensite.lue, reason: '$instrument');
      }
    });

    test('densité absente : refusée', () {
      expectInvalid(
        () => densiteRetenue(
          const LectureDensite(instrument: InstrumentDensite.electronique),
        ),
        'électronique sans SG',
      );
      expectInvalid(
        () => densiteRetenue(const LectureDensite(sg: double.nan)),
        'NaN',
      );
      // Hors bornes : retenue telle quelle, le calcul qui la lit la refuse.
      expect(densiteRetenue(const LectureDensite(sg: 1.25)).sg, 1.25);
      final flottant = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.flottant20,
          sg: 5,
          temperatureEchantillonC: 20,
        ),
      );
      expect(flottant.sg, 5);
      expect(flottant.etat, EtatDensite.horsBornes);
    });

    test('valeurs stockées', () {
      expect(
        [for (final i in InstrumentDensite.values) i.storedValue],
        [
          'hydrometer_20c',
          'hydrometer_15_6c',
          'refractometer',
          'digital',
          'other',
        ],
      );
      expectInvalid(() => InstrumentDensite.fromStored('rapt'), 'inconnu');
    });
  });

  group('réfractomètre', () {
    test('°Brix → SG avec le facteur', () {
      for (final c in objects(refractometer['brix_to_sg'])) {
        final brix = number(c['brix']);
        final facteur = number(c['factor']);
        expectCase(c, brixVersSg(brix: brix, facteur: facteur));
        final retenue = densiteRetenue(
          LectureDensite(
            instrument: InstrumentDensite.refractometre,
            brix: brix,
            facteur: facteur,
          ),
        );
        expectCase(c, retenue.sg!);
        expect(retenue.etat, EtatDensite.convertie, reason: label(c));
      }
    });

    test('Terrill 2011, équation cubique', () {
      for (final c in objects(refractometer['terrill'])) {
        expectCase(
          c,
          densiteTerrill(
            brixInitial: number(c['original_brix']),
            brixFinal: number(c['final_brix']),
          ),
        );
      }
    });

    test('en fermentation : correction de l\'alcool', () {
      for (final c in objects(refractometer['fermentation'])) {
        final lecture = LectureDensite(
          instrument: InstrumentDensite.refractometre,
          brix: number(c['brix']),
          facteur: number(c['factor']),
          enFermentation: true,
        );
        final retenue = densiteRetenue(
          lecture,
          densiteInitialeSg: number(c['original_gravity']),
        );
        expectCase(c, retenue.sg!);
        expect(retenue.etat, EtatDensite.corrigee, reason: label(c));
      }
    });

    test('sans facteur : aucune densité', () {
      final retenue = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 12.4,
        ),
      );
      expect(retenue.sg, isNull);
      expect(retenue.etat, EtatDensite.facteurManquant);
    });

    test('en fermentation sans densité initiale : conversion seule', () {
      final retenue = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 6.3,
          facteur: 1.0,
          enFermentation: true,
        ),
      );
      expect(retenue.etat, EtatDensite.densiteInitialeManquante);
      expect(retenue.sg, closeTo(brixVersSg(brix: 6.3, facteur: 1), 1e-12));
    });

    test('densité initiale sous 1,000 : traitée comme absente', () {
      final retenue = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 6.3,
          facteur: 1.0,
          enFermentation: true,
        ),
        densiteInitialeSg: 0.995,
      );
      expect(retenue.etat, EtatDensite.densiteInitialeManquante);
    });

    test('case décochée en fermentation : conversion sans correction', () {
      final retenue = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 6.5,
          facteur: 1.04,
          enFermentation: true,
          corriger: false,
        ),
        densiteInitialeSg: 1.05,
      );
      expect(retenue.etat, EtatDensite.nonCorrigee);
      expect(retenue.sg, closeTo(brixVersSg(brix: 6.5, facteur: 1.04), 1e-12));
      expect(retenue.corrigee, closeTo(1.0121137, 1e-6));
    });

    test('entrées invalides', () {
      for (final c in objects(refractometer['invalid'])) {
        expectInvalid(
          () =>
              brixVersSg(brix: number(c['brix']), facteur: number(c['factor'])),
          label(c),
        );
      }
      expectInvalid(
        () => densiteRetenue(
          const LectureDensite(instrument: InstrumentDensite.refractometre),
        ),
        'réfractomètre sans °Brix',
      );
      final horsBornes = densiteRetenue(
        const LectureDensite(
          instrument: InstrumentDensite.refractometre,
          brix: 45,
          facteur: 1.04,
        ),
      );
      expect(horsBornes.sg, isNull);
      expect(horsBornes.etat, EtatDensite.horsBornes);
    });
  });
}
