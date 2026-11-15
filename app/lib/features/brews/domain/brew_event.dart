import 'package:brewing/brewing.dart' show StepEvent, StepEventKind;
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

/// Nature de l'heure d'une saisie, lue dans `time_estimated`,
/// `date_estimated` et `phase` : jamais déduite de l'heure elle-même.
enum NatureHeure {
  /// Heure notée (sur l'appareil, ou dans la fiche importée).
  notee,

  /// Saisie du jour de brassage d'une fiche importée, citée sans heure : heure
  /// estimée d'après la chronologie.
  estimee,

  /// Relevé d'une fiche importée noté sans heure : date gardée, heure posée à
  /// 12:00 par la préparation.
  nonNotee,

  /// Relevé de l'en-tête d'une fiche importée, sans date : jour du brassage
  /// + 28 jours.
  dateEstimee,
}

/// Valeur d'une mesure à l'écran : « 67,5 °C », « 1057,9 », « 23,0 L », « pH 5,42 ».
String libelleMesure(MeasureType type, double value) => switch (type) {
  MeasureType.temperature => formatCelsius(value),
  MeasureType.gravity => formatDensite(value),
  MeasureType.volume =>
    '${formatNombre(value, decimales: 1, fixe: true)}${nbsp}L',
  MeasureType.ph => 'pH ${formatPh(value)}',
};

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
    this.timeEstimated = false,
    this.dateEstimated = false,
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

  /// Heure estimée à l'import d'une fiche (`time_estimated: true`) : l'heure
  /// n'a pas été notée. Elle date l'événement, sans réel ni écart. Retirée
  /// quand une correction change l'heure.
  final bool timeEstimated;

  /// Date elle-même estimée (`date_estimated: true`) : relevé de l'en-tête
  /// daté du jour du brassage + 28 jours par la préparation. Toujours avec
  /// [timeEstimated].
  final bool dateEstimated;

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
    final timeEstimated = read.boolFacultatif('time_estimated') ?? false;
    final dateEstimated = read.boolFacultatif('date_estimated') ?? false;
    final stepKey = read.texteFacultatif('step_key');
    if (kind.stepKind != null && stepKey == null) {
      throw const DocumentIllisible('step_key', 'clé d\'étape absente');
    }
    return BrewEvent(
      id: id,
      ownerUid: read.texte('owner_uid'),
      kind: kind,
      stepKey: stepKey,
      measureType: MeasureType.fromStored(data['measure_type']),
      value: read.nombreFacultatif('value'),
      note: read.texteFacultatif('note'),
      measuredAt: measuredAt,
      phase: PhaseEvenement.fromStored(data['phase']),
      timeEstimated: timeEstimated || dateEstimated,
      dateEstimated: dateEstimated,
      hasPendingWrites: hasPendingWrites,
    );
  }

  /// Forme attendue par `stepRecordsFromEvents`, ou `null` pour une mesure ou une
  /// note.
  StepEvent? toStepEvent() {
    final step = kind.stepKind;
    final key = stepKey;
    if (step == null || key == null) return null;
    return StepEvent(
      id: id,
      kind: step,
      stepKey: key,
      measuredAt: measuredAt,
      estimated: timeEstimated,
    );
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
    if (timeEstimated || dateEstimated) 'time_estimated': true,
    if (dateEstimated) 'date_estimated': true,
    'created_at': FieldValue.serverTimestamp(),
  };

  bool get isMeasureOrNote =>
      kind == BrewEventKind.measurement || kind == BrewEventKind.note;

  bool get isFermentation => phase == PhaseEvenement.fermentation;

  /// Nature de [measuredAt] ([NatureHeure]).
  NatureHeure get natureHeure => dateEstimated
      ? NatureHeure.dateEstimee
      : !timeEstimated
      ? NatureHeure.notee
      : isFermentation
      ? NatureHeure.nonNotee
      : NatureHeure.estimee;

  bool get isGravity =>
      kind == BrewEventKind.measurement && measureType == MeasureType.gravity;

  bool get isVolume =>
      kind == BrewEventKind.measurement && measureType == MeasureType.volume;
}
