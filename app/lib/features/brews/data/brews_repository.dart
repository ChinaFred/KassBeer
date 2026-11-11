import 'dart:async';

import 'package:brewing/brewing.dart' show StepEventKind;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../costs/data/costs_repository.dart' show brewCostRef;
import '../../equipment/domain/equipment.dart';
import '../../recipes/domain/recipe.dart';
import '../domain/brew.dart';
import '../domain/brew_event.dart';
import '../domain/deroule.dart';
import '../domain/releves.dart';

/// Attente maximale d'une réponse du serveur par « Préparer le brassage ».
const kPrepareWait = Duration(seconds: 15);

/// Déroulé refusé par [erreurDeroule] avant l'écriture : les règles ne lisent
/// pas les journées (ADR-009, P37), l'application ne les écrit qu'à cette
/// condition.
class DerouleInvalide implements Exception {
  const DerouleInvalide(this.message);

  final String message;

  @override
  String toString() => 'DerouleInvalide : $message';
}

/// Écriture d'étape : début, fin ou saut d'une étape.
typedef StepWrite = ({StepEventKind kind, String stepKey});

/// Accès à `brews/` et `brews/{id}/events/`. Les écrans passent par cette
/// interface ; les tests la remplacent par un double sans Firebase.
///
/// Aucune transaction : le jour de brassage écrit hors ligne dans le cache, et la
/// file de Firestore garde l'ordre (CLAUDE.md, P2). Toute écriture sur `brews/{id}`
/// réécrit `owner_name` ou le retire : `ownerNameOk` s'applique à l'état final.
abstract class BrewsRepository {
  /// Tous les brassins du groupe, à chaque changement.
  Stream<ListeLue<Brew>> watchAll();

  /// Saisies du brassin [brewId], à chaque changement (métadonnées comprises, pour
  /// compter les écritures en attente).
  Stream<ListeLue<BrewEvent>> watchEvents(String brewId);

  /// Attend une réponse du serveur pour le brassin et ses saisies, [limite] au
  /// plus : vrai si elle est arrivée. Lecture ordinaire, sans `Source.server` :
  /// n'écrit rien.
  Future<bool> attendreServeur(String brewId, {Duration limite = kPrepareWait});

  /// Crée un brassin : écrit seul, avant tout événement (la règle d'un événement
  /// lit le brassin par `get()`).
  CreationEnCours create({
    required Recipe recipe,
    required Equipment equipment,
    required String name,
    required DateTime? plannedFor,
    required String ownerUid,
    required String? ownerName,
    String? notes,
  });

  /// Modifie nom, date prévue et notes.
  Future<void> update({
    required String id,
    required String name,
    required DateTime? plannedFor,
    required String? notes,
    required String? ownerName,
  });

  /// Écrit le déroulé figé `process` d'un brassin prévu, en entier (ADR-009,
  /// option B') : juste après [create], puis à chaque changement de processus ou
  /// de date avant le départ. [deroule] nul retire le champ : « Chronologie de la
  /// recette seule ». Les règles refusent l'écriture une fois `brewed_at` posé.
  /// Échoue par [DerouleInvalide] si [erreurDeroule] refuse le déroulé : rien
  /// n'est écrit.
  Future<void> setProcess({
    required String brewId,
    required Deroule? deroule,
    required String? ownerName,
  });

  /// Commence le brassage : `status: brewing`, `brewed_at`, et le premier début
  /// d'étape [firstStepKey] (s'il y en a un) dans un même `WriteBatch`.
  Future<void> start({
    required String brewId,
    required String ownerUid,
    required DateTime at,
    required String? firstStepKey,
    required String? ownerName,
  });

  /// Termine le brassage : `status: fermenting`.
  Future<void> finish({required String brewId, required String? ownerName});

  /// Écrit [writes] à l'heure [at] de l'appareil : une écriture simple, ou un
  /// `WriteBatch` s'il y en a plusieurs.
  Future<void> writeSteps({
    required String brewId,
    required String ownerUid,
    required List<StepWrite> writes,
    required DateTime at,
  });

  /// Écrit une mesure ou une note, avec l'identifiant créé par l'appareil.
  CreationEnCours addEvent({
    required String brewId,
    required BrewEventInput input,
  });

  /// Corrige une saisie : valeur, note et heure seulement (règles).
  Future<void> correct({
    required String brewId,
    required String eventId,
    required double? value,
    required String? note,
    required DateTime measuredAt,
  });

  /// Supprime une saisie.
  Future<void> deleteEvent({required String brewId, required String eventId});

  /// Réécrit une saisie supprimée, avec son identifiant et son heure (« Annuler »).
  Future<void> restoreEvent({required String brewId, required BrewEvent event});

  /// Écrit un relevé de fermentation : un événement par valeur, ou une note seule,
  /// dans un `WriteBatch` (FE4, FE5). Rend les identifiants créés par l'appareil.
  EcritureReleve addReleve({
    required String brewId,
    required String ownerUid,
    required ReleveSaisi releve,
  });

  /// Corrige [avant] selon [releve] : valeurs, note, heure ; une valeur vidée
  /// supprime son événement, une valeur ajoutée le crée à la même heure (FE9).
  Future<void> correctReleve({
    required String brewId,
    required String ownerUid,
    required Releve avant,
    required ReleveSaisi releve,
  });

  /// Supprime plusieurs saisies dans un `WriteBatch`.
  Future<void> deleteEvents({
    required String brewId,
    required List<String> eventIds,
  });

  /// Réécrit plusieurs saisies supprimées, identifiants et heures gardés (FE10).
  Future<void> restoreEvents({
    required String brewId,
    required List<BrewEvent> events,
  });

  /// Change le statut (ST8) : `status`, `owner_name`, `updated_at`, sans transaction.
  Future<void> setStatus({
    required String brewId,
    required BrewStatus status,
    required String? ownerName,
  });

  /// Enregistre l'embouteillage. [nouveauStatut] : `conditioning` à la première
  /// écriture, nul à la modification. [finalGravity] crée un relevé à `bottled_at`
  /// dans le même `WriteBatch` (EM1).
  Future<void> saveBottling({
    required String brewId,
    required String ownerUid,
    required Embouteillage embouteillage,
    required BrewStatus? nouveauStatut,
    double? finalGravity,
    required String? ownerName,
  });

  /// Désigne la mesure retenue [champ], ou revient à la dernière mesure (`null`).
  Future<void> setMesureRetenue({
    required String brewId,
    required MesureRetenueChamp champ,
    required String? eventId,
    required String? ownerName,
  });

  /// Écrit la réponse à « Les sucres étaient-ils dans le moût ? ».
  Future<void> setSugarsInWort({
    required String brewId,
    required bool value,
    required String? ownerName,
  });

  /// Supprime un brassin sans saisie : possible hors ligne. Son coût figé
  /// `users/{ownerUid}/brew_costs/{id}` part dans le même lot (CB19).
  Future<void> delete(String id, {required String ownerUid});

  /// Supprime un brassin et ses saisies : réseau exigé. Par écritures simples,
  /// saisies d'abord : un lot de plus de 20 `get()` de règles peut être refusé.
  /// Le brassin et son coût figé partent ensuite dans un même lot (CB19).
  Future<void> deleteWithEvents(String id, {required String ownerUid});
}

/// Mesure ou note à écrire.
@immutable
class BrewEventInput {
  const BrewEventInput({
    required this.ownerUid,
    required this.kind,
    this.stepKey,
    this.measureType,
    this.value,
    this.note,
    required this.measuredAt,
    this.phase,
  });

  final String ownerUid;
  final BrewEventKind kind;
  final String? stepKey;
  final MeasureType? measureType;
  final double? value;
  final String? note;
  final DateTime measuredAt;

  /// `fermentation` pour une saisie d'une journée 2 ou suivante (ADR-009),
  /// `null` pour le jour de brassage.
  final PhaseEvenement? phase;
}

/// Identifiants créés par l'appareil pour un relevé, et fin de son écriture.
typedef EcritureReleve = ({List<String> ids, Future<void> written});

/// Saisie d'un relevé (FE1). Base : SG, °C.
@immutable
class ReleveSaisi {
  const ReleveSaisi({
    this.gravity,
    this.temperature,
    this.note,
    required this.measuredAt,
  });

  final double? gravity;
  final double? temperature;
  final String? note;
  final DateTime measuredAt;
}

/// Données d'embouteillage. Aucun prix ni coût (EM5).
@immutable
class Embouteillage {
  const Embouteillage({
    required this.bottledAt,
    this.bottlesCount,
    this.packagedVolumeL,
    this.primingSugarG,
    this.primingSugarName,
  });

  final DateTime bottledAt;
  final int? bottlesCount;
  final double? packagedVolumeL;
  final double? primingSugarG;
  final String? primingSugarName;
}

/// [BrewsRepository] sur Cloud Firestore.
class FirestoreBrewsRepository implements BrewsRepository {
  FirestoreBrewsRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _brews =>
      _firestore.collection('brews');

  CollectionReference<Map<String, dynamic>> _events(String brewId) =>
      _brews.doc(brewId).collection('events');

  @override
  Stream<ListeLue<Brew>> watchAll() => _brews
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ListeLue<Brew>(
          documents: [
            for (final doc in snapshot.docs)
              _readBrew(doc.id, doc.data(), doc.metadata.hasPendingWrites),
          ],
          fromCache: snapshot.metadata.isFromCache,
        ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'brews.watch_all',
          error: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      });

  DocumentLu<Brew> _readBrew(
    String id,
    Map<String, dynamic> data,
    bool hasPendingWrites,
  ) {
    try {
      final brew = Brew.fromFirestore(
        id,
        data,
        hasPendingWrites: hasPendingWrites,
      );
      // Déroulé illisible (process, ou chronologie de la recette figée) : le
      // brassin reste lisible, l'écran affiche la panne (ADR-009).
      final deroule = brew.deroule;
      final problem = deroule.probleme;
      if (problem != null) {
        _errors.reportError(
          feature: deroule.resolu ? 'brews.process' : 'brews.brew_steps',
          error: DocumentIllisible(
            deroule.resolu ? 'process' : 'brew_steps',
            problem,
          ),
          context:
              'brews/$id : ${deroule.resolu ? 'déroulé' : 'chronologie'} '
              'illisible',
        );
      }
      return DocumentValide(id, brew);
    } on DocumentIllisible catch (error, stackTrace) {
      // Valeur stockée inconnue, dans le brassin ou dans sa recette figée :
      // la lecture de la copie (RecipeContent.fromFirestore) ne lève que
      // DocumentIllisible depuis la v0.1.17.
      return _invalidBrew(id, error, stackTrace);
    }
  }

  DocumentLu<Brew> _invalidBrew(String id, Object error, StackTrace stack) {
    _errors.reportError(
      feature: 'brews.read',
      error: error,
      stackTrace: stack,
      context: 'brews/$id illisible',
    );
    return DocumentInvalide(id, error);
  }

  @override
  Stream<ListeLue<BrewEvent>> watchEvents(String brewId) => _events(brewId)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ListeLue<BrewEvent>(
          documents: [
            for (final doc in snapshot.docs)
              _readEvent(
                brewId,
                doc.id,
                doc.data(),
                doc.metadata.hasPendingWrites,
              ),
          ],
          fromCache: snapshot.metadata.isFromCache,
        ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'brews.watch_events',
          error: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      });

  DocumentLu<BrewEvent> _readEvent(
    String brewId,
    String id,
    Map<String, dynamic> data,
    bool hasPendingWrites,
  ) {
    try {
      return DocumentValide(
        id,
        BrewEvent.fromFirestore(id, data, hasPendingWrites: hasPendingWrites),
      );
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'brews.event_read',
        error: error,
        stackTrace: stackTrace,
        context: 'brews/$brewId/events/$id illisible',
      );
      return DocumentInvalide(id, error);
    }
  }

  @override
  Future<bool> attendreServeur(
    String brewId, {
    Duration limite = kPrepareWait,
  }) async {
    final results = await Future.wait([
      _reponseServeur(
        _brews
            .doc(brewId)
            .snapshots(includeMetadataChanges: true)
            .map((s) => s.metadata.isFromCache),
        limite,
      ),
      _reponseServeur(
        _events(brewId)
            .snapshots(includeMetadataChanges: true)
            .map((s) => s.metadata.isFromCache),
        limite,
      ),
    ]);
    return results.every((ok) => ok);
  }

  /// Premier événement non issu du cache de [fromCache], [limite] au plus.
  Future<bool> _reponseServeur(Stream<bool> fromCache, Duration limite) {
    final done = Completer<bool>();
    late final StreamSubscription<bool> subscription;
    void finish(bool result) {
      if (done.isCompleted) return;
      done.complete(result);
      unawaited(subscription.cancel());
    }

    final timer = Timer(limite, () => finish(false));
    subscription = fromCache.listen(
      (cached) {
        if (cached) return;
        timer.cancel();
        finish(true);
      },
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        _errors.reportError(
          feature: 'brews.prepare',
          error: error,
          stackTrace: stackTrace,
        );
        finish(false);
      },
    );
    return done.future;
  }

  @override
  CreationEnCours create({
    required Recipe recipe,
    required Equipment equipment,
    required String name,
    required DateTime? plannedFor,
    required String ownerUid,
    required String? ownerName,
    String? notes,
  }) {
    final ref = _brews.doc();
    final written = _guard(
      'brews.create',
      () => ref.set({
        'owner_uid': ownerUid,
        'owner_name': ?ownerName,
        'recipe_id': recipe.id,
        'name': name.trim(),
        'status': BrewStatus.planned.storedValue,
        if (plannedFor != null) 'planned_for': Timestamp.fromDate(plannedFor),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'recipe_snapshot': recipeSnapshot(recipe),
        'equipment_snapshot': equipmentSnapshot(equipment),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }),
    );
    return (id: ref.id, written: written);
  }

  @override
  Future<void> update({
    required String id,
    required String name,
    required DateTime? plannedFor,
    required String? notes,
    required String? ownerName,
  }) => _guard(
    'brews.update',
    () => _brews.doc(id).update({
      'name': name.trim(),
      ...champFacultatif(
        'planned_for',
        plannedFor == null ? null : Timestamp.fromDate(plannedFor),
        creation: false,
      ),
      ...champFacultatif(
        'notes',
        notes == null || notes.trim().isEmpty ? null : notes.trim(),
        creation: false,
      ),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> setProcess({
    required String brewId,
    required Deroule? deroule,
    required String? ownerName,
  }) => _guard('brews.process_write', () {
    if (deroule != null) {
      final erreur = erreurDeroule(deroule);
      if (erreur != null) throw DerouleInvalide(erreur);
    }
    return _brews.doc(brewId).update({
      ...champFacultatif('process', deroule?.toFirestore(), creation: false),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    });
  });

  @override
  Future<void> start({
    required String brewId,
    required String ownerUid,
    required DateTime at,
    required String? firstStepKey,
    required String? ownerName,
  }) {
    final batch = _firestore.batch();
    batch.update(_brews.doc(brewId), {
      'status': BrewStatus.brewing.storedValue,
      'brewed_at': Timestamp.fromDate(at),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    });
    final eventRef = firstStepKey == null ? null : _events(brewId).doc();
    if (eventRef != null) {
      batch.set(
        eventRef,
        _stepEvent(
          ownerUid: ownerUid,
          kind: StepEventKind.started,
          stepKey: firstStepKey!,
          at: at,
        ),
      );
    }
    return _guardCreation(
      refs: [?eventRef],
      kinds: const ['step_started'],
      write: batch.commit,
    );
  }

  @override
  Future<void> finish({required String brewId, required String? ownerName}) =>
      _writeStatus('brews.finish', brewId, BrewStatus.fermenting, ownerName);

  Future<void> _writeStatus(
    String feature,
    String brewId,
    BrewStatus status,
    String? ownerName,
  ) => _guard(
    feature,
    () => _brews.doc(brewId).update({
      'status': status.storedValue,
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    }),
  );

  Map<String, Object?> _stepEvent({
    required String ownerUid,
    required StepEventKind kind,
    required String stepKey,
    required DateTime at,
  }) => {
    'owner_uid': ownerUid,
    'kind': kind.storedValue,
    'step_key': stepKey,
    'measure_type': null,
    'value': null,
    'measured_at': Timestamp.fromDate(at),
    'created_at': FieldValue.serverTimestamp(),
  };

  @override
  Future<void> writeSteps({
    required String brewId,
    required String ownerUid,
    required List<StepWrite> writes,
    required DateTime at,
  }) {
    final refs = [for (final _ in writes) _events(brewId).doc()];
    final kinds = [for (final w in writes) w.kind.storedValue];
    Future<void> commit() {
      if (writes.length == 1) {
        final w = writes.single;
        return refs.single.set(
          _stepEvent(
            ownerUid: ownerUid,
            kind: w.kind,
            stepKey: w.stepKey,
            at: at,
          ),
        );
      }
      final batch = _firestore.batch();
      for (final (i, w) in writes.indexed) {
        batch.set(
          refs[i],
          _stepEvent(
            ownerUid: ownerUid,
            kind: w.kind,
            stepKey: w.stepKey,
            at: at,
          ),
        );
      }
      return batch.commit();
    }

    return _guardCreation(refs: refs, kinds: kinds, write: commit);
  }

  @override
  CreationEnCours addEvent({
    required String brewId,
    required BrewEventInput input,
  }) {
    final ref = _events(brewId).doc();
    final event = BrewEvent(
      id: ref.id,
      ownerUid: input.ownerUid,
      kind: input.kind,
      stepKey: input.stepKey,
      measureType: input.measureType,
      value: input.value,
      note: input.note,
      measuredAt: input.measuredAt,
      phase: input.phase,
    );
    final written = _guardCreation(
      refs: [ref],
      kinds: [
        '${event.kind.storedValue}'
            '${event.measureType == null ? '' : ':${event.measureType!.storedValue}'}',
      ],
      write: () => ref.set(event.toFirestore()),
    );
    return (id: ref.id, written: written);
  }

  @override
  Future<void> correct({
    required String brewId,
    required String eventId,
    required double? value,
    required String? note,
    required DateTime measuredAt,
  }) => _guard(
    'brews.event_correct',
    () => _events(brewId).doc(eventId).update({
      'value': value,
      'note': note == null || note.trim().isEmpty ? null : note.trim(),
      'measured_at': Timestamp.fromDate(measuredAt),
    }),
  );

  @override
  Future<void> deleteEvent({required String brewId, required String eventId}) =>
      _guard('brews.event_delete', () => _events(brewId).doc(eventId).delete());

  @override
  Future<void> restoreEvent({
    required String brewId,
    required BrewEvent event,
  }) => _guardCreation(
    refs: [_events(brewId).doc(event.id)],
    kinds: [event.kind.storedValue],
    write: () => _events(brewId).doc(event.id).set(event.toFirestore()),
  );

  Map<String, Object?> _releveEvent({
    required String ownerUid,
    required BrewEventKind kind,
    MeasureType? type,
    double? value,
    String? note,
    required DateTime at,
  }) => BrewEvent(
    id: '',
    ownerUid: ownerUid,
    kind: kind,
    measureType: type,
    value: value,
    note: note,
    measuredAt: at,
    phase: PhaseEvenement.fermentation,
  ).toFirestore();

  String? _texteNote(String? note) {
    final text = note?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  @override
  EcritureReleve addReleve({
    required String brewId,
    required String ownerUid,
    required ReleveSaisi releve,
  }) {
    final note = _texteNote(releve.note);
    final batch = _firestore.batch();
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    final kinds = <String>[];
    void add(Map<String, Object?> event, String kind) {
      final ref = _events(brewId).doc();
      batch.set(ref, event);
      refs.add(ref);
      kinds.add(kind);
    }

    if (releve.gravity != null) {
      add(
        _releveEvent(
          ownerUid: ownerUid,
          kind: BrewEventKind.measurement,
          type: MeasureType.gravity,
          value: releve.gravity,
          note: note,
          at: releve.measuredAt,
        ),
        'measurement:gravity',
      );
    }
    if (releve.temperature != null) {
      add(
        _releveEvent(
          ownerUid: ownerUid,
          kind: BrewEventKind.measurement,
          type: MeasureType.temperature,
          value: releve.temperature,
          // FE5 : la note va sur le premier événement.
          note: releve.gravity == null ? note : null,
          at: releve.measuredAt,
        ),
        'measurement:temperature',
      );
    }
    if (refs.isEmpty) {
      add(
        _releveEvent(
          ownerUid: ownerUid,
          kind: BrewEventKind.note,
          note: note,
          at: releve.measuredAt,
        ),
        'note',
      );
    }
    return (
      ids: [for (final ref in refs) ref.id],
      written: _guardCreation(refs: refs, kinds: kinds, write: batch.commit),
    );
  }

  @override
  Future<void> correctReleve({
    required String brewId,
    required String ownerUid,
    required Releve avant,
    required ReleveSaisi releve,
  }) {
    final note = _texteNote(releve.note);
    final at = Timestamp.fromDate(releve.measuredAt);
    final batch = _firestore.batch();
    final refs = <DocumentReference<Map<String, dynamic>>>[];
    final kinds = <String>[];

    void slot(
      BrewEvent? existant,
      MeasureType type,
      double? value,
      String? noteDeSlot,
    ) {
      if (existant == null) {
        if (value == null) return;
        final ref = _events(brewId).doc();
        batch.set(
          ref,
          _releveEvent(
            ownerUid: ownerUid,
            kind: BrewEventKind.measurement,
            type: type,
            value: value,
            note: noteDeSlot,
            at: releve.measuredAt,
          ),
        );
        refs.add(ref);
        kinds.add('measurement:${type.storedValue}');
      } else if (value == null) {
        batch.delete(_events(brewId).doc(existant.id));
      } else {
        batch.update(_events(brewId).doc(existant.id), {
          'value': value,
          'note': noteDeSlot,
          'measured_at': at,
        });
      }
    }

    slot(avant.gravity, MeasureType.gravity, releve.gravity, note);
    slot(
      avant.temperature,
      MeasureType.temperature,
      releve.temperature,
      releve.gravity == null ? note : null,
    );

    final aDesValeurs = releve.gravity != null || releve.temperature != null;
    final noteEvent = avant.noteEvent;
    if (noteEvent != null && aDesValeurs) {
      batch.delete(_events(brewId).doc(noteEvent.id));
    } else if (noteEvent != null) {
      batch.update(_events(brewId).doc(noteEvent.id), {
        'note': note,
        'measured_at': at,
      });
    } else if (!aDesValeurs && note != null) {
      final ref = _events(brewId).doc();
      batch.set(
        ref,
        _releveEvent(
          ownerUid: ownerUid,
          kind: BrewEventKind.note,
          note: note,
          at: releve.measuredAt,
        ),
      );
      refs.add(ref);
      kinds.add('note');
    }
    return _guardCreation(refs: refs, kinds: kinds, write: batch.commit);
  }

  @override
  Future<void> deleteEvents({
    required String brewId,
    required List<String> eventIds,
  }) => _guard('brews.events_delete', () {
    final batch = _firestore.batch();
    for (final id in eventIds) {
      batch.delete(_events(brewId).doc(id));
    }
    return batch.commit();
  });

  @override
  Future<void> restoreEvents({
    required String brewId,
    required List<BrewEvent> events,
  }) {
    final refs = [for (final e in events) _events(brewId).doc(e.id)];
    return _guardCreation(
      refs: refs,
      kinds: [for (final e in events) e.kind.storedValue],
      write: () {
        final batch = _firestore.batch();
        for (final (i, e) in events.indexed) {
          batch.set(refs[i], e.toFirestore());
        }
        return batch.commit();
      },
    );
  }

  @override
  Future<void> setStatus({
    required String brewId,
    required BrewStatus status,
    required String? ownerName,
  }) => _writeStatus('brews.status', brewId, status, ownerName);

  @override
  Future<void> saveBottling({
    required String brewId,
    required String ownerUid,
    required Embouteillage embouteillage,
    required BrewStatus? nouveauStatut,
    double? finalGravity,
    required String? ownerName,
  }) {
    final fields = <String, Object?>{
      'bottled_at': Timestamp.fromDate(embouteillage.bottledAt),
      ...champFacultatif(
        'bottles_count',
        embouteillage.bottlesCount,
        creation: false,
      ),
      ...champFacultatif(
        'packaged_volume_l',
        embouteillage.packagedVolumeL,
        creation: false,
      ),
      ...champFacultatif(
        'priming_sugar_g',
        embouteillage.primingSugarG,
        creation: false,
      ),
      ...champFacultatif(
        'priming_sugar_name',
        embouteillage.primingSugarName,
        creation: false,
      ),
      ...champFacultatif('owner_name', ownerName, creation: false),
      if (nouveauStatut != null) 'status': nouveauStatut.storedValue,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (finalGravity == null) {
      return _guard('brews.bottling', () => _brews.doc(brewId).update(fields));
    }
    final batch = _firestore.batch();
    batch.update(_brews.doc(brewId), fields);
    final eventRef = _events(brewId).doc();
    // Le relevé est posé à bottled_at : il reste dans la densité finale (VR2).
    batch.set(
      eventRef,
      _releveEvent(
        ownerUid: ownerUid,
        kind: BrewEventKind.measurement,
        type: MeasureType.gravity,
        value: finalGravity,
        at: embouteillage.bottledAt,
      ),
    );
    return _guardCreation(
      refs: [eventRef],
      kinds: const ['measurement:gravity'],
      write: batch.commit,
    );
  }

  @override
  Future<void> setMesureRetenue({
    required String brewId,
    required MesureRetenueChamp champ,
    required String? eventId,
    required String? ownerName,
  }) => _guard(
    'brews.retained_measure',
    () => _brews.doc(brewId).update({
      ...champFacultatif(champ.storedField, eventId, creation: false),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> setSugarsInWort({
    required String brewId,
    required bool value,
    required String? ownerName,
  }) => _guard(
    'brews.sugars_in_wort',
    () => _brews.doc(brewId).update({
      'sugars_in_wort': value,
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> delete(String id, {required String ownerUid}) =>
      _guard('brews.delete', () => _deleteBrewAndCost(id, ownerUid));

  @override
  Future<void> deleteWithEvents(String id, {required String ownerUid}) =>
      _guard('brews.delete_with_events', () async {
        // Réponse du serveur exigée : hors ligne, cette lecture échoue et rien
        // n'est supprimé. Cette suppression n'est pas sur l'écran du jour (P2).
        final events = await _events(
          id,
        ).get(const GetOptions(source: Source.server));
        for (final doc in events.docs) {
          await doc.reference.delete();
        }
        await _deleteBrewAndCost(id, ownerUid);
      });

  /// Le brassin et son coût figé dans un lot : un refus sur le brassin ne retire
  /// pas son coût, et aucun coût ne reste sans brassin (CB19). Supprimer un coût
  /// absent passe les règles.
  Future<void> _deleteBrewAndCost(String id, String ownerUid) {
    final batch = _firestore.batch();
    batch.delete(_brews.doc(id));
    batch.delete(brewCostRef(_firestore, uid: ownerUid, brewId: id));
    return batch.commit();
  }

  /// Lance [write] : l'écriture locale est faite avant le retour ; une erreur est
  /// rapportée puis relancée pour l'écran.
  Future<void> _guard(String feature, Future<void> Function() write) async {
    try {
      await write();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: feature,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Écrit des événements nouveaux ([refs]).
  Future<void> _guardCreation({
    required List<DocumentReference<Map<String, dynamic>>> refs,
    required List<String> kinds,
    required Future<void> Function() write,
  }) => creationSuivie(refs: refs, kinds: kinds, write: write);

  /// Lance [write]. HS7 : un refus du serveur n'est annoncé que si l'événement n'y
  /// est pas. Un accusé perdu fait rejouer le `set`, refusé (`created_at` change),
  /// alors que l'événement est déjà enregistré : le refus est alors ignoré.
  @visibleForTesting
  Future<void> creationSuivie({
    required List<DocumentReference<Map<String, dynamic>>> refs,
    required List<String> kinds,
    required Future<void> Function() write,
  }) async {
    try {
      await write();
    } catch (error, stackTrace) {
      final context =
          'kinds=${kinds.join(',')} '
          'code=${error is FirebaseException ? error.code : error.runtimeType}';
      if (refs.isNotEmpty && await _presentSurServeur(refs)) {
        // Rejeu après un accusé perdu : journalisé (aucun catch silencieux),
        // jamais annoncé à l'utilisateur (HS7).
        _errors.reportError(
          feature: 'brews.event_replayed',
          error: error,
          stackTrace: stackTrace,
          context: context,
        );
        return;
      }
      _errors.reportError(
        feature: 'brews.event_rejected',
        error: error,
        stackTrace: stackTrace,
        context: context,
      );
      rethrow;
    }
  }

  /// Vrai si chaque document existe sans écriture locale en attente. Lecture
  /// ordinaire (cache puis serveur), jamais `Source.server` (P2).
  Future<bool> _presentSurServeur(
    List<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    try {
      for (final ref in refs) {
        final snapshot = await ref.get();
        if (!snapshot.exists || snapshot.metadata.hasPendingWrites) {
          return false;
        }
      }
      return true;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'brews.event_check',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}
