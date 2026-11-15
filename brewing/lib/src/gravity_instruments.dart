import 'dart:math' as math;

import 'conversions.dart';
import 'errors.dart';
import 'gravity.dart';

/// Instruments de mesure de la densité et correction de leur lecture.
///
/// Une mesure garde sa lecture brute ; la valeur retenue se calcule à
/// l'affichage par [densiteRetenue], seule fonction qui lit une densité
/// mesurée pour les calculs (rendement, degré, courbes, comparaisons).

/// Instrument de mesure de la densité, en liste fermée.
enum InstrumentDensite {
  /// Densimètre flottant étalonné à 20 °C.
  flottant20('hydrometer_20c', 20),

  /// Densimètre flottant étalonné à 15,6 °C (60 °F).
  flottant15v6('hydrometer_15_6c', 15.6),

  /// Réfractomètre, lecture en °Brix.
  refractometre('refractometer', null),

  /// Densimètre électronique : densité lue, sans correction.
  electronique('digital', null),

  /// Autre instrument : densité lue, sans correction.
  autre('other', null);

  const InstrumentDensite(this.storedValue, this.temperatureEtalonnageC);

  /// Valeur stockée (`gravity_instrument`).
  final String storedValue;

  /// Température d'étalonnage d'un densimètre flottant, `null` sinon.
  final double? temperatureEtalonnageC;

  /// Vrai pour un densimètre flottant : sa lecture se corrige en température.
  bool get flottant => temperatureEtalonnageC != null;

  /// Vrai pour le réfractomètre : lecture en °Brix, facteur du moût.
  bool get lectureBrix => this == InstrumentDensite.refractometre;

  /// Vrai si l'instrument demande une correction ou une conversion.
  bool get corrige => flottant || lectureBrix;

  /// Instrument de [value] ; lève [BrewingInputException] si elle est inconnue.
  static InstrumentDensite fromStored(String value) => enumFromStored(
    InstrumentDensite.values,
    (i) => i.storedValue,
    'gravity_instrument',
    value,
  );
}

/// Température d'échantillon la plus basse d'une correction (°C).
const double kCorrectionTemperatureMinC = 0;

/// Température d'échantillon la plus haute d'une correction sans réserve (°C).
const double kCorrectionExacteMaxC = 40;

/// Température d'échantillon la plus haute d'une correction approchée (°C).
const double kCorrectionApprocheeMaxC = 75;

/// Température d'échantillon saisie la plus haute (°C) ; au-delà de
/// [kCorrectionApprocheeMaxC], elle est gardée sans correction.
const double kTemperatureEchantillonMaxC = 100;

/// Lecture d'un réfractomètre la plus haute (°Brix).
const double kBrixMax = 40;

/// Facteur de correction du moût d'un réfractomètre : bornes de saisie. Aucun
/// facteur par défaut : le brasseur le saisit.
const double kFacteurRefractometreMin = 0.9;

/// Voir [kFacteurRefractometreMin].
const double kFacteurRefractometreMax = 1.2;

/// Masse volumique de l'eau pure (kg/m³) à [celsius], de 0 à 150 °C.
///
/// G. S. Kell, « Density, thermal expansivity, and compressibility of liquid
/// water from 0 to 150 °C », J. Chem. Eng. Data 20 (1), 1975, éq. (16) :
/// ρ = (999,83952 + 16,945176 t − 7,9870401e-3 t² − 46,170461e-6 t³
/// + 105,56302e-9 t⁴ − 280,54253e-12 t⁵) / (1 + 16,879850e-3 t).
double masseVolumiqueEau(double celsius) {
  requireRange('celsius', celsius, 0, 150);
  final t = celsius;
  final numerateur =
      999.83952 +
      16.945176 * t -
      7.9870401e-3 * t * t -
      46.170461e-6 * math.pow(t, 3) +
      105.56302e-9 * math.pow(t, 4) -
      280.54253e-12 * math.pow(t, 5);
  return numerateur / (1 + 16.879850e-3 * t);
}

/// Plage d'une correction en température.
enum PlageCorrection {
  /// De [kCorrectionTemperatureMinC] à [kCorrectionExacteMaxC].
  exacte,

  /// Au-delà de [kCorrectionExacteMaxC], jusqu'à [kCorrectionApprocheeMaxC].
  approchee,

  /// Sous [kCorrectionTemperatureMinC] : correction impossible, la lecture
  /// brute est retenue.
  tropFroid,

  /// Au-delà de [kCorrectionApprocheeMaxC] : correction impossible, la lecture
  /// brute est retenue.
  tropChaud;

  /// Vrai si la correction est impossible.
  bool get impossible => this == tropFroid || this == tropChaud;
}

/// Plage de la correction d'un échantillon à [celsius].
PlageCorrection plageCorrection(double celsius) {
  if (!celsius.isFinite) {
    throw BrewingInputException('celsius', celsius, 'nombre fini attendu');
  }
  if (celsius < kCorrectionTemperatureMinC) return PlageCorrection.tropFroid;
  if (celsius > kCorrectionApprocheeMaxC) return PlageCorrection.tropChaud;
  return celsius <= kCorrectionExacteMaxC
      ? PlageCorrection.exacte
      : PlageCorrection.approchee;
}

/// Densité corrigée d'un densimètre flottant étalonné à [etalonnageC], lu à
/// [lectureSg] dans un échantillon à [echantillonC] :
/// lecture × ρ(étalonnage) / ρ(échantillon) ([masseVolumiqueEau], Kell 1975).
///
/// Lève [BrewingInputException] si la lecture sort de [minGravity] à
/// [maxGravity] ou si une température sort de 0 à 100 °C. La plage de
/// confiance se lit par [plageCorrection].
double corrigerDensimetre({
  required double lectureSg,
  required double echantillonC,
  required double etalonnageC,
}) {
  requireRange('lectureSg', lectureSg, minGravity, maxGravity);
  requireRange('echantillonC', echantillonC, 0, kTemperatureEchantillonMaxC);
  requireRange('etalonnageC', etalonnageC, 0, kTemperatureEchantillonMaxC);
  return lectureSg *
      masseVolumiqueEau(etalonnageC) /
      masseVolumiqueEau(echantillonC);
}

/// °Brix corrigé du facteur du moût : lecture / facteur.
double brixCorrige({required double brix, required double facteur}) {
  requireRange('brix', brix, 0, kBrixMax);
  requireRange(
    'facteur',
    facteur,
    kFacteurRefractometreMin,
    kFacteurRefractometreMax,
  );
  return brix / facteur;
}

/// Densité finale d'une lecture de réfractomètre en fermentation, corrigée de
/// l'alcool par l'équation cubique de Sean Terrill (« Refractometer FG
/// Results », seanterrill.com, 7 avril 2011) :
/// FG = 1 − 0,0044993 OB + 0,011774 FB + 0,00027581 OB² − 0,0012717 FB²
/// − 0,0000072800 OB³ + 0,000063293 FB³,
/// [brixInitial] (OB) et [brixFinal] (FB) en °Brix corrigés du facteur.
double densiteTerrill({
  required double brixInitial,
  required double brixFinal,
}) {
  requireRange(
    'brixInitial',
    brixInitial,
    0,
    kBrixMax / kFacteurRefractometreMin,
  );
  requireRange('brixFinal', brixFinal, 0, kBrixMax / kFacteurRefractometreMin);
  final ob = brixInitial;
  final fb = brixFinal;
  return 1.0 -
      0.0044993 * ob +
      0.011774 * fb +
      0.00027581 * ob * ob -
      0.0012717 * fb * fb -
      0.0000072800 * ob * ob * ob +
      0.000063293 * fb * fb * fb;
}

/// Lecture brute d'une mesure de densité, telle qu'elle est stockée.
class LectureDensite {
  /// Crée la lecture. [instrument] nul : mesure sans instrument (ancienne, ou
  /// instrument « À choisir »), lue comme une densité sans correction.
  const LectureDensite({
    this.instrument,
    this.sg,
    this.brix,
    this.temperatureEchantillonC,
    this.facteur,
    this.corriger = true,
    this.enFermentation = false,
  });

  /// Instrument, ou `null` pour une mesure sans instrument.
  final InstrumentDensite? instrument;

  /// Densité lue (SG), sauf pour le réfractomètre.
  final double? sg;

  /// Lecture du réfractomètre (°Brix).
  final double? brix;

  /// Température de l'échantillon d'un densimètre flottant (°C).
  final double? temperatureEchantillonC;

  /// Facteur de correction du moût d'un réfractomètre.
  final double? facteur;

  /// Case « Corriger » : faux, la lecture est retenue sans correction.
  final bool corriger;

  /// Mesure prise après le début de la fermentation : une lecture de
  /// réfractomètre se corrige alors de l'alcool.
  final bool enFermentation;
}

/// État de la valeur retenue d'une mesure de densité.
enum EtatDensite {
  /// Lue telle quelle : mesure sans instrument, densimètre électronique ou autre.
  lue,

  /// Corrigée : en température (flottant de 0 à 40 °C) ou de l'alcool
  /// (réfractomètre en fermentation).
  corrigee,

  /// Corrigée en température de façon approchée (flottant au-delà de 40 °C).
  approchee,

  /// Réfractomètre avant fermentation : °Brix converti en densité.
  convertie,

  /// Case « Corriger » décochée : lecture brute (flottant) ou conversion sans
  /// correction de l'alcool (réfractomètre en fermentation).
  nonCorrigee,

  /// Flottant sans température d'échantillon : lecture brute.
  sansTemperature,

  /// Flottant hors de la plage de correction : lecture brute.
  horsPlage,

  /// Réfractomètre sans facteur : aucune densité.
  facteurManquant,

  /// Réfractomètre en fermentation sans densité initiale retenue : conversion
  /// sans correction de l'alcool.
  densiteInitialeManquante,

  /// Résultat hors de [minGravity]–[maxGravity] : lecture brute (flottant) ou
  /// aucune densité (réfractomètre).
  horsBornes,
}

/// Valeur retenue d'une mesure de densité, et ce qui l'explique.
class DensiteRetenue {
  /// Crée le résultat.
  const DensiteRetenue({
    required this.sg,
    required this.etat,
    this.corrigee,
    this.lueSg,
    this.correctionApprochee = false,
    this.plage,
  });

  /// Densité retenue pour l'affichage et les calculs (SG), ou `null` si la
  /// mesure n'en donne aucune (réfractomètre sans facteur, résultat hors bornes).
  final double? sg;

  /// Raison de [sg].
  final EtatDensite etat;

  /// Densité corrigée calculable, même case « Corriger » décochée ; `null` si
  /// aucune correction n'est possible.
  final double? corrigee;

  /// Lecture en SG sans correction : lecture d'un densimètre, ou conversion du
  /// °Brix sans correction de l'alcool.
  final double? lueSg;

  /// Vrai si [corrigee] est une correction en température approchée (flottant
  /// au-delà de [kCorrectionExacteMaxC]), case cochée ou non.
  final bool correctionApprochee;

  /// Plage de la température d'échantillon d'un densimètre flottant, `null`
  /// sans température ou pour un autre instrument. Dit, pour
  /// [EtatDensite.horsPlage], si l'échantillon est trop froid ou trop chaud.
  final PlageCorrection? plage;

  /// Vrai si [sg] porte une correction (température ou alcool).
  bool get estCorrigee =>
      etat == EtatDensite.corrigee || etat == EtatDensite.approchee;
}

/// Valeur retenue de [lecture] : corrigée si la case « Corriger » est cochée
/// et la correction possible, sinon la lecture brute. [densiteInitialeSg] :
/// densité initiale retenue du brassin, lue pour la correction de l'alcool d'un
/// réfractomètre en fermentation.
///
/// Lève [BrewingInputException] sur une lecture incomplète (flottant ou
/// électronique sans SG, réfractomètre sans °Brix) ou hors de ses bornes de
/// saisie.
DensiteRetenue densiteRetenue(
  LectureDensite lecture, {
  double? densiteInitialeSg,
}) {
  final instrument = lecture.instrument;
  if (instrument == null || !instrument.corrige) {
    final sg = _lectureSg(lecture);
    return DensiteRetenue(sg: sg, etat: EtatDensite.lue, lueSg: sg);
  }
  if (instrument.flottant) return _flottant(lecture, instrument);
  return _refractometre(lecture, densiteInitialeSg);
}

double _lectureSg(LectureDensite lecture) {
  final sg = lecture.sg;
  if (sg == null || !sg.isFinite) {
    throw BrewingInputException('sg', sg, 'densité lue absente ou non finie');
  }
  return sg;
}

bool _dansLesBornes(double sg) =>
    sg.isFinite && sg >= minGravity && sg <= maxGravity;

DensiteRetenue _flottant(LectureDensite lecture, InstrumentDensite instrument) {
  final lue = _lectureSg(lecture);
  // Lecture hors bornes : retenue telle quelle, sans correction ; le calcul
  // qui la lit la refuse et l'appelant rapporte la panne.
  if (!_dansLesBornes(lue)) {
    return DensiteRetenue(sg: lue, etat: EtatDensite.horsBornes, lueSg: lue);
  }
  final temperature = lecture.temperatureEchantillonC;
  if (temperature == null) {
    return DensiteRetenue(
      sg: lue,
      etat: EtatDensite.sansTemperature,
      lueSg: lue,
    );
  }
  final plage = plageCorrection(temperature);
  if (plage.impossible) {
    return DensiteRetenue(
      sg: lue,
      etat: EtatDensite.horsPlage,
      lueSg: lue,
      plage: plage,
    );
  }
  final corrigee = corrigerDensimetre(
    lectureSg: lue,
    echantillonC: temperature,
    etalonnageC: instrument.temperatureEtalonnageC!,
  );
  if (!_dansLesBornes(corrigee)) {
    return DensiteRetenue(sg: lue, etat: EtatDensite.horsBornes, lueSg: lue);
  }
  if (!lecture.corriger) {
    return DensiteRetenue(
      sg: lue,
      etat: EtatDensite.nonCorrigee,
      corrigee: corrigee,
      lueSg: lue,
      correctionApprochee: plage == PlageCorrection.approchee,
      plage: plage,
    );
  }
  return DensiteRetenue(
    sg: corrigee,
    etat: plage == PlageCorrection.exacte
        ? EtatDensite.corrigee
        : EtatDensite.approchee,
    corrigee: corrigee,
    lueSg: lue,
    correctionApprochee: plage == PlageCorrection.approchee,
    plage: plage,
  );
}

DensiteRetenue _refractometre(
  LectureDensite lecture,
  double? densiteInitialeSg,
) {
  final brix = lecture.brix;
  if (brix == null) {
    throw const BrewingInputException('brix', null, 'lecture en °Brix absente');
  }
  if (!brix.isFinite) {
    throw BrewingInputException('brix', brix, 'nombre fini attendu');
  }
  final facteur = lecture.facteur;
  if (facteur == null) {
    return const DensiteRetenue(sg: null, etat: EtatDensite.facteurManquant);
  }
  // Lecture ou facteur hors des bornes de saisie : aucune densité.
  if (brix < 0 ||
      brix > kBrixMax ||
      facteur < kFacteurRefractometreMin ||
      facteur > kFacteurRefractometreMax) {
    return const DensiteRetenue(sg: null, etat: EtatDensite.horsBornes);
  }
  final finalCorrige = brixCorrige(brix: brix, facteur: facteur);
  final convertie = platoVersSgSansBornes(finalCorrige);
  if (!_dansLesBornes(convertie)) {
    return const DensiteRetenue(sg: null, etat: EtatDensite.horsBornes);
  }
  if (!lecture.enFermentation) {
    return DensiteRetenue(
      sg: convertie,
      etat: EtatDensite.convertie,
      lueSg: convertie,
    );
  }
  // Une densité initiale sous 1,000 ne donne aucun °Brix initial : traitée
  // comme absente.
  final brixInitial = densiteInitialeSg == null
      ? null
      : sgToPlato(densiteInitialeSg);
  if (brixInitial == null ||
      brixInitial <= 0 ||
      brixInitial > kBrixMax / kFacteurRefractometreMin) {
    return DensiteRetenue(
      sg: convertie,
      etat: EtatDensite.densiteInitialeManquante,
      lueSg: convertie,
    );
  }
  final corrigee = densiteTerrill(
    brixInitial: brixInitial,
    brixFinal: finalCorrige,
  );
  if (!_dansLesBornes(corrigee)) {
    return DensiteRetenue(
      sg: null,
      etat: EtatDensite.horsBornes,
      lueSg: convertie,
    );
  }
  if (!lecture.corriger) {
    return DensiteRetenue(
      sg: convertie,
      etat: EtatDensite.nonCorrigee,
      corrigee: corrigee,
      lueSg: convertie,
    );
  }
  return DensiteRetenue(
    sg: corrigee,
    etat: EtatDensite.corrigee,
    corrigee: corrigee,
    lueSg: convertie,
  );
}
