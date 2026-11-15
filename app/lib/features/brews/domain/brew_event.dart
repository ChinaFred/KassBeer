import 'package:brewing/brewing.dart'
    show
        InstrumentDensite,
        StepEvent,
        StepEventKind,
        kBrixMax,
        kFacteurRefractometreMax,
        kFacteurRefractometreMin,
        kTemperatureEchantillonMaxC,
        maxGravity,
        minGravity;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/formats.dart';

/// Longueur maximale d'une note (`firestore.rules`).
const kEventNoteMaxLength = 2000;

/// Nature d'un événement (`brews/{id}/events/{eventId}.kind`).
enum BrewEventKind {
  started,
  ended,
  skipped,
  measurement,
  note;

  /// Valeur stockée ; celles des étapes viennent de `brewing/`.
  String get storedValue => switch (this) {
    started => StepEventKind.started.storedValue,
    ended => StepEventKind.ended.storedValue,
    skipped => StepEventKind.skipped.storedValue,
    measurement => 'measurement',
    note => 'note',
  };

  /// Nature de l'étape dans `brewing/`, ou `null` pour une mesure ou une note.
  StepEventKind? get stepKind => switch (this) {
    started => StepEventKind.started,
    ended => StepEventKind.ended,
    skipped => StepEventKind.skipped,
    measurement || note => null,
  };

  static BrewEventKind fromStored(Object? value) {
    for (final kind in values) {
      if (kind.storedValue == value) return kind;
    }
    throw const DocumentIllisible('kind', 'nature inconnue');
  }
}

/// Type d'une mesure (`measure_type`). Base : °C, SG, L.
enum MeasureType {
  temperature('temperature', 'Température'),
  gravity('gravity', 'Densité'),
  volume('volume', 'Volume'),
  ph('ph', 'pH');

  const MeasureType(this.storedValue, this.label);

  final String storedValue;
  final String label;

  static MeasureType? fromStored(Object? value) {
    if (value == null) return null;
    for (final type in values) {
      if (type.storedValue == value) return type;
    }
    throw const DocumentIllisible('measure_type', 'type inconnu');
  }
}

/// Moment d'un événement ; absent en base pour le jour de brassage.
enum PhaseEvenement {
  fermentation('fermentation');

  const PhaseEvenement(this.storedValue);

  final String storedValue;

  static PhaseEvenement? fromStored(Object? value) {
    if (value == null) return null;
    for (final phase in values) {
      if (phase.storedValue == value) return phase;
    }
    throw const DocumentIllisible('phase', 'phase inconnue');
  }
}

/// Valeur d'une mesure à l'écran : « 67,5 °C », « 1057,9 », « 23,0 L », « pH 5,42 ».
String libelleMesure(MeasureType type, double value) => switch (type) {
  MeasureType.temperature => formatCelsius(value),
  MeasureType.gravity => formatDensite(value),
  MeasureType.volume =>
    '${formatNombre(value, decimales: 1, fixe: true)}${nbsp}L',
  MeasureType.ph => 'pH ${formatPh(value)}',
};

/// Instrument et lecture brute d'une mesure de densité (`gravity_instrument`,
/// `brix`, `sample_temperature`, `refractometer_factor`, `correct`). La valeur
/// corrigée n'est jamais stockée : `brewing/` la calcule à l'affichage
/// (`densiteRetenue`). Absent : mesure sans instrument, lue telle quelle.
@immutable
class DetailDensite {
  const DetailDensite({
    required this.instrument,
    this.brix,
    this.temperatureEchantillon,
    this.facteur,
    this.corriger,
  });

  final InstrumentDensite instrument;

  /// Lecture du réfractomètre (°Brix) ; `value` est alors nulle.
  final double? brix;

  /// Température de l'échantillon d'un densimètre flottant (°C).
  final double? temperatureEchantillon;

  /// Facteur de correction du moût, copié de la préférence du brasseur.
  final double? facteur;

  /// Case « Corriger » : posée pour un flottant et un réfractomètre, nulle sinon.
  final bool? corriger;

  /// Champs à écrire avec la mesure. [creation] faux : un champ sans valeur est
  /// retiré (correction d'une saisie, ME5).
  Map<String, Object?> toFirestore({required bool creation}) => {
    'gravity_instrument': instrument.storedValue,
    ...champFacultatif('brix', brix, creation: creation),
    ...champFacultatif(
      'sample_temperature',
      temperatureEchantillon,
      creation: creation,
    ),
    ...champFacultatif('refractometer_factor', facteur, creation: creation),
    ...champFacultatif('correct', corriger, creation: creation),
  };

  /// Retire les champs d'une mesure sans instrument (correction, ME5).
  static Map<String, Object?> champsRetires() => {
    'gravity_instrument': FieldValue.delete(),
    'brix': FieldValue.delete(),
    'sample_temperature': FieldValue.delete(),
    'refractometer_factor': FieldValue.delete(),
    'correct': FieldValue.delete(),
  };

  /// Lit le détail d'une mesure, bornes identiques à `firestore.rules`. Rend `null`
  /// sans `gravity_instrument`. Lève [DocumentIllisible] sur un champ hors forme,
  /// ou une valeur [value] incompatible avec l'instrument.
  static DetailDensite? lire(
    LecteurChamps read,
    Map<String, dynamic> data, {
    required bool gravity,
    required double? value,
  }) {
    final stored = read.texteFacultatif('gravity_instrument');
    final brix = read.nombreFacultatif('brix');
    final temperature = read.nombreFacultatif('sample_temperature');
    final facteur = read.nombreFacultatif('refractometer_factor');
    final corriger = read.boolFacultatif('correct');
    if (stored == null) {
      if (brix != null ||
          temperature != null ||
          facteur != null ||
          corriger != null) {
        throw const DocumentIllisible(
          'gravity_instrument',
          'lecture sans instrument',
        );
      }
      return null;
    }
    if (!gravity) {
      throw const DocumentIllisible(
        'gravity_instrument',
        'instrument sur une mesure qui n\'est pas une densité',
      );
    }
    final instrument = InstrumentDensite.values
        .where((i) => i.storedValue == stored)
        .firstOrNull;
    if (instrument == null) {
      throw const DocumentIllisible('gravity_instrument', 'instrument inconnu');
    }
    bool dans(double? v, double min, double max) =>
        v == null || (v >= min && v <= max);
    final ok = instrument.lectureBrix
        ? value == null &&
              brix != null &&
              dans(brix, 0, kBrixMax) &&
              dans(
                facteur,
                kFacteurRefractometreMin,
                kFacteurRefractometreMax,
              ) &&
              temperature == null &&
              corriger != null
        : value != null &&
              brix == null &&
              facteur == null &&
              (instrument.flottant
                  ? corriger != null &&
                        dans(temperature, 0, kTemperatureEchantillonMaxC)
                  : temperature == null && corriger == null);
    if (!ok) {
      throw const DocumentIllisible(
        'gravity_instrument',
        'lecture incompatible avec l\'instrument',
      );
    }
    return DetailDensite(
      instrument: instrument,
      brix: brix,
      temperatureEchantillon: temperature,
      facteur: facteur,
      corriger: corriger,
    );
  }
}

/// Densité saisie : lecture en SG (nulle pour un réfractomètre) et détail de
/// l'instrument (nul sans instrument choisi).
@immutable
class DensiteSaisie {
  const DensiteSaisie({this.sg, this.detail});

  final double? sg;
  final DetailDensite? detail;

  /// Champs d'une correction (ME5) : valeur et détail ; sans instrument, les
  /// champs du détail sont retirés.
  Map<String, Object?> champsCorrection() => {
    'value': sg,
    ...?detail?.toFirestore(creation: false),
    if (detail == null) ...DetailDensite.champsRetires(),
  };
}

/// Document `brews/{id}/events/{eventId}`. Un document par mesure, début ou fin
/// d'étape, identifiant créé par l'appareil (CLAUDE.md, « hors ligne »).
@immutable
class BrewEvent {
  const BrewEvent({
    required this.id,
    required this.ownerUid,
    required this.kind,
    this.stepKey,
    this.measureType,
    this.value,
    this.note,
    required this.measuredAt,
    this.phase,
    this.densite,
    this.hasPendingWrites = false,
  });

  final String id;
  final String ownerUid;
  final BrewEventKind kind;

  /// Étape concernée, nulle pour une mesure sans étape.
  final String? stepKey;
  final MeasureType? measureType;
  final double? value;
  final String? note;

  /// Heure de l'appareil, source de toute durée.
  final DateTime measuredAt;

  /// Relevé de fermentation, ou `null` pour le jour de brassage (FE4).
  final PhaseEvenement? phase;

  /// Instrument et lecture brute d'une densité ; `null` pour une mesure sans
  /// instrument.
  final DetailDensite? densite;

  /// Écriture locale pas encore reçue par le serveur.
  final bool hasPendingWrites;

  factory BrewEvent.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    bool hasPendingWrites = false,
  }) {
    final read = LecteurChamps(data);
    final measuredAt = read.date('measured_at');
    if (measuredAt == null) {
      throw const DocumentIllisible('measured_at', 'heure absente');
    }
    final kind = BrewEventKind.fromStored(data['kind']);
    final stepKey = read.texteFacultatif('step_key');
    if (kind.stepKind != null && stepKey == null) {
      throw const DocumentIllisible('step_key', 'clé d\'étape absente');
    }
    final measureType = MeasureType.fromStored(data['measure_type']);
    final value = read.nombreFacultatif('value');
    final gravity =
        kind == BrewEventKind.measurement && measureType == MeasureType.gravity;
    final densite = DetailDensite.lire(
      read,
      data,
      gravity: gravity,
      value: value,
    );
    if (kind == BrewEventKind.measurement &&
        value == null &&
        densite?.instrument.lectureBrix != true) {
      throw const DocumentIllisible('value', 'valeur de la mesure absente');
    }
    if (gravity &&
        value != null &&
        (value < minGravity || value > maxGravity)) {
      throw const DocumentIllisible('value', 'densité hors bornes');
    }
    return BrewEvent(
      id: id,
      ownerUid: read.texte('owner_uid'),
      kind: kind,
      stepKey: stepKey,
      measureType: measureType,
      value: value,
      note: read.texteFacultatif('note'),
      measuredAt: measuredAt,
      phase: PhaseEvenement.fromStored(data['phase']),
      densite: densite,
      hasPendingWrites: hasPendingWrites,
    );
  }

  /// Forme attendue par `stepRecordsFromEvents`, ou `null` pour une mesure ou une
  /// note.
  StepEvent? toStepEvent() {
    final step = kind.stepKind;
    final key = stepKey;
    if (step == null || key == null) return null;
    return StepEvent(id: id, kind: step, stepKey: key, measuredAt: measuredAt);
  }

  /// Champs à écrire. `created_at` est posée par le serveur (audit seul).
  Map<String, Object?> toFirestore() => {
    'owner_uid': ownerUid,
    'kind': kind.storedValue,
    'step_key': stepKey,
    'measure_type': measureType?.storedValue,
    'value': value,
    if (note != null) 'note': note,
    'measured_at': Timestamp.fromDate(measuredAt),
    if (phase != null) 'phase': phase!.storedValue,
    ...?densite?.toFirestore(creation: true),
    'created_at': FieldValue.serverTimestamp(),
  };

  bool get isMeasureOrNote =>
      kind == BrewEventKind.measurement || kind == BrewEventKind.note;

  bool get isFermentation => phase == PhaseEvenement.fermentation;

  bool get isGravity =>
      kind == BrewEventKind.measurement && measureType == MeasureType.gravity;

  bool get isVolume =>
      kind == BrewEventKind.measurement && measureType == MeasureType.volume;
}
