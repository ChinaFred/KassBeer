import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/equipment.dart';

/// Accès à `equipment/`. Les écrans passent par cette interface ; les tests la
/// remplacent par un double sans Firebase.
abstract class EquipmentRepository {
  /// Tous les équipements du groupe, à chaque changement, avec la provenance de la
  /// lecture (cache ou serveur). Un document illisible est rapporté et rendu comme
  /// tel.
  Stream<ListeLue<Equipment>> watchAll();

  /// Crée un équipement de [ownerUid]. L'écriture locale est faite dès l'appel ;
  /// `written` se termine quand le serveur l'a acceptée. [ownerName] : nom du
  /// jeton de l'auteur, `null` s'il n'en a pas (champ absent).
  CreationEnCours create({
    required EquipmentContent content,
    required String ownerUid,
    required String? ownerName,
  });

  /// Modifie l'équipement [id] : `owner_uid` et `created_at` ne sont pas écrits,
  /// `updated_at` est posée par le serveur, `owner_name` est réécrit ou retiré.
  /// Même déroulé que [create].
  Future<void> update({
    required String id,
    required EquipmentContent content,
    required String? ownerName,
  });

  /// Supprime l'équipement [id]. Les recettes qui le citent ne sont pas écrites.
  Future<void> delete(String id);
}

/// [EquipmentRepository] sur Cloud Firestore.
class FirestoreEquipmentRepository implements EquipmentRepository {
  FirestoreEquipmentRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _equipment =>
      _firestore.collection('equipment');

  @override
  Stream<ListeLue<Equipment>> watchAll() => _equipment
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ListeLue<Equipment>(
          documents: [
            for (final doc in snapshot.docs)
              _read(doc.id, doc.data(), doc.metadata.hasPendingWrites),
          ],
          fromCache: snapshot.metadata.isFromCache,
        ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'equipment.watch_all',
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran affiche la panne.
        Error.throwWithStackTrace(error, stackTrace);
      });

  DocumentLu<Equipment> _read(
    String id,
    Map<String, dynamic> data,
    bool hasPendingWrites,
  ) {
    try {
      return DocumentValide(
        id,
        Equipment.fromFirestore(id, data, hasPendingWrites: hasPendingWrites),
      );
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'equipment.read',
        error: error,
        stackTrace: stackTrace,
        context: 'equipment/$id illisible',
      );
      return DocumentInvalide(id, error);
    }
  }

  @override
  CreationEnCours create({
    required EquipmentContent content,
    required String ownerUid,
    required String? ownerName,
  }) {
    final ref = _equipment.doc();
    final written = _guard(
      'equipment.create',
      () => ref.set({
        ...content.toFirestore(creation: true),
        'owner_uid': ownerUid,
        ...champFacultatif('owner_name', ownerName, creation: true),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }),
    );
    return (id: ref.id, written: written);
  }

  @override
  Future<void> update({
    required String id,
    required EquipmentContent content,
    required String? ownerName,
  }) => _guard(
    'equipment.update',
    () => _equipment.doc(id).update({
      ...content.toFirestore(creation: false),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> delete(String id) =>
      _guard('equipment.delete', () => _equipment.doc(id).delete());

  /// Lance [write] tout de suite (l'écriture locale est faite avant le retour) ;
  /// une erreur, levée en construisant le document ou rendue par le serveur, est
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
}
