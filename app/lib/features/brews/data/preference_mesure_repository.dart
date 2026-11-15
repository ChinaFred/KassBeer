import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/preference_mesure.dart';

/// Accès à `users/{uid}/preferences/measurement`, privé à son propriétaire.
/// Aucune transaction ; l'écriture est faite dans le cache dès l'appel et part
/// au retour du réseau (jour de brassage hors ligne, P2).
abstract class PreferenceMesureRepository {
  /// Instrument de [uid] : trouvé, illisible (rapporté), absent, ou absent du
  /// cache seul.
  Stream<RechercheDocument<PreferenceMesure>> watch(String uid);

  /// Écrit l'instrument choisi par le brasseur.
  Future<void> save({
    required String uid,
    required PreferenceMesure preference,
  });
}

/// [PreferenceMesureRepository] sur Cloud Firestore.
class FirestorePreferenceMesureRepository
    implements PreferenceMesureRepository {
  FirestorePreferenceMesureRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('preferences')
      .doc('measurement');

  @override
  Stream<RechercheDocument<PreferenceMesure>> watch(String uid) => _ref(uid)
      .snapshots(includeMetadataChanges: true)
      .map<RechercheDocument<PreferenceMesure>>((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return snapshot.metadata.isFromCache
              ? DocumentAbsentDuCache<PreferenceMesure>()
              : DocumentAbsent<PreferenceMesure>();
        }
        try {
          return DocumentTrouve(PreferenceMesure.fromFirestore(data));
        } on DocumentIllisible catch (error, stackTrace) {
          _errors.reportError(
            feature: 'brews.measurement_preference_read',
            error: error,
            stackTrace: stackTrace,
            context: 'preferences/measurement illisible : ${error.field}',
          );
          return DocumentIllisibleTrouve<PreferenceMesure>(error);
        }
      })
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'brews.measurement_preference_watch',
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran garde « À choisir ».
        Error.throwWithStackTrace(error, stackTrace);
      });

  @override
  Future<void> save({
    required String uid,
    required PreferenceMesure preference,
  }) async {
    try {
      await _ref(uid).set({
        ...preference.toFirestore(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'brews.measurement_preference_write',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
