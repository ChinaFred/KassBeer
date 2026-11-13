import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/preference_processus.dart';

/// Accès à `users/{uid}/preferences/processes` (ADR-010), privé à son
/// propriétaire. Les écrans passent par cette interface ; les tests la
/// remplacent par un double sans Firebase. Aucune transaction ; l'écriture est
/// faite dans le cache dès l'appel.
abstract class PreferencesProcessusRepository {
  /// Choix par défaut de [uid] : trouvé, illisible (rapporté), absent, ou absent
  /// du cache seul.
  Stream<RechercheDocument<PreferenceProcessus>> watch(String uid);

  /// Écrit le modèle proposé par défaut ; `null` : « Chronologie de la recette
  /// seule ».
  Future<void> saveDefault({required String uid, required String? templateId});
}

/// [PreferencesProcessusRepository] sur Cloud Firestore.
class FirestorePreferencesProcessusRepository
    implements PreferencesProcessusRepository {
  FirestorePreferencesProcessusRepository({
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
      .doc('processes');

  @override
  Stream<RechercheDocument<PreferenceProcessus>> watch(String uid) => _ref(uid)
      .snapshots(includeMetadataChanges: true)
      .map<RechercheDocument<PreferenceProcessus>>((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return snapshot.metadata.isFromCache
              ? DocumentAbsentDuCache<PreferenceProcessus>()
              : DocumentAbsent<PreferenceProcessus>();
        }
        try {
          return DocumentTrouve(PreferenceProcessus.fromFirestore(data));
        } on DocumentIllisible catch (error, stackTrace) {
          _errors.reportError(
            feature: 'processes.preference_read',
            error: error,
            stackTrace: stackTrace,
            context: 'preferences/processes illisible',
          );
          return DocumentIllisibleTrouve<PreferenceProcessus>(error);
        }
      })
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'processes.preference_watch',
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran affiche la panne.
        Error.throwWithStackTrace(error, stackTrace);
      });

  @override
  Future<void> saveDefault({
    required String uid,
    required String? templateId,
  }) async {
    try {
      await _ref(uid).set({
        'default_template_id': templateId,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'processes.preference_write',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
