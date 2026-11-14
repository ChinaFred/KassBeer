import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/error_report_service.dart';
import '../domain/error_report.dart';

/// Taille d'une page d'Admin › Rapports d'erreur (ADR-011, J1 ; P50).
const kTaillePageRapports = 50;

/// Position après le dernier rapport d'une page : opaque pour l'écran.
class CurseurRapports {
  const CurseurRapports(this.valeur);

  final Object valeur;
}

/// Page de rapports : du plus récent au plus ancien, curseur de la page
/// suivante (`null` sur une page de moins de [kTaillePageRapports]) et
/// provenance de la lecture.
class PageRapports {
  const PageRapports({
    required this.rapports,
    required this.suite,
    required this.fromCache,
  });

  final List<ErrorReport> rapports;
  final CurseurRapports? suite;

  /// Lue dans le cache de l'appareil, faute de réseau : peut être incomplète.
  final bool fromCache;
}

/// Lecture de `error_reports/` par l'admin. Lecture seule : aucune écriture ni
/// suppression (choix de l'utilisateur, ADR-011).
abstract class ErrorReportsRepository {
  /// Une page de [kTaillePageRapports] rapports au plus, après [apres].
  Future<PageRapports> page({CurseurRapports? apres});
}

/// [ErrorReportsRepository] sur Cloud Firestore : `get()` paginé, aucun
/// écouteur (P50).
class FirestoreErrorReportsRepository implements ErrorReportsRepository {
  FirestoreErrorReportsRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  @override
  Future<PageRapports> page({CurseurRapports? apres}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      var query = _firestore
          .collection('error_reports')
          .orderBy('created_at', descending: true);
      if (apres != null) {
        query = query.startAfterDocument(apres.valeur as DocumentSnapshot);
      }
      snapshot = await query.limit(kTaillePageRapports).get();
    } catch (error, stackTrace) {
      // Aucun texte de rapport dans le contexte (P13).
      _errors.reportError(
        feature: 'admin.error_reports',
        error: error,
        stackTrace: stackTrace,
        context: apres == null ? 'première page' : 'page suivante',
      );
      rethrow;
    }
    final docs = snapshot.docs;
    return PageRapports(
      rapports: [
        for (final doc in docs) ErrorReport.fromFirestore(doc.id, doc.data()),
      ],
      suite: docs.length < kTaillePageRapports
          ? null
          : CurseurRapports(docs.last),
      fromCache: snapshot.metadata.isFromCache,
    );
  }
}
