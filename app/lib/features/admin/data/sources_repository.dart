import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../library/data/library_repository.dart' show CurseurPage;
import '../domain/ingestion.dart';

/// Taille d'une page d'ingrédients non résolus (P22 : pages de 50).
const kTaillePageNonResolus = 50;

/// Dernière exécution de l'ingestion, et provenance de la lecture.
class LectureExecution {
  const LectureExecution({required this.execution, required this.fromCache});

  /// [DocumentAbsent] : aucune exécution sur le serveur ;
  /// [DocumentAbsentDuCache] : aucune dans le cache, hors ligne.
  final RechercheDocument<ExecutionIngestion> execution;

  /// Vrai quand la lecture vient du cache local : elle peut être périmée.
  final bool fromCache;
}

/// Page d'ingrédients non résolus : documents lus, curseur de la page suivante
/// (`null` à la dernière page) et provenance de la lecture.
class PageNonResolus {
  const PageNonResolus({
    required this.documents,
    required this.suite,
    required this.fromCache,
  });

  final List<DocumentLu<IngredientNonResolu>> documents;
  final CurseurPage? suite;
  final bool fromCache;
}

/// Lecture d'Admin › Sources : `ingest_runs/` et `import_unresolved/`, réservés
/// à l'admin par `firestore.rules`. Lecture seule, par `get()` : aucun écouteur.
/// Chaque panne est rapportée puis relancée ; chaque document illisible est
/// rapporté et rendu comme tel.
abstract class SourcesRepository {
  /// Exécution la plus récente (`finished_at` décroissant, une seule).
  Future<LectureExecution> derniereExecution();

  /// Page de [kTaillePageNonResolus] ingrédients non résolus, par `count`
  /// décroissant, après [apres].
  Future<PageNonResolus> pageNonResolus({CurseurPage? apres});
}

/// [SourcesRepository] sur Cloud Firestore.
class FirestoreSourcesRepository implements SourcesRepository {
  FirestoreSourcesRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  @override
  Future<LectureExecution> derniereExecution() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection('ingest_runs')
          .orderBy('finished_at', descending: true)
          .limit(1)
          .get();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'admin.sources_run',
        error: error,
        stackTrace: stackTrace,
        context: 'ingest_runs, dernière exécution',
      );
      rethrow;
    }
    final fromCache = snapshot.metadata.isFromCache;
    if (snapshot.docs.isEmpty) {
      return LectureExecution(
        execution: fromCache
            ? const DocumentAbsentDuCache()
            : const DocumentAbsent(),
        fromCache: fromCache,
      );
    }
    final doc = snapshot.docs.single;
    try {
      return LectureExecution(
        execution: DocumentTrouve(
          ExecutionIngestion.fromFirestore(doc.id, doc.data()),
        ),
        fromCache: fromCache,
      );
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'admin.sources_run_read',
        error: error,
        stackTrace: stackTrace,
        context: 'ingest_runs/${doc.id} illisible',
      );
      return LectureExecution(
        execution: DocumentIllisibleTrouve(error),
        fromCache: fromCache,
      );
    }
  }

  @override
  Future<PageNonResolus> pageNonResolus({CurseurPage? apres}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      var query = _firestore
          .collection('import_unresolved')
          .orderBy('count', descending: true);
      if (apres != null) {
        query = query.startAfterDocument(apres.valeur as DocumentSnapshot);
      }
      snapshot = await query.limit(kTaillePageNonResolus).get();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'admin.sources_unresolved',
        error: error,
        stackTrace: stackTrace,
        context: apres == null ? 'première page' : 'page suivante',
      );
      rethrow;
    }
    final docs = snapshot.docs;
    final documents = <DocumentLu<IngredientNonResolu>>[];
    DocumentIllisible? premiere;
    StackTrace? pile;
    String? premierId;
    var illisibles = 0;
    for (final doc in docs) {
      try {
        documents.add(
          DocumentValide(
            doc.id,
            IngredientNonResolu.fromFirestore(doc.id, doc.data()),
          ),
        );
      } on DocumentIllisible catch (error, stackTrace) {
        documents.add(DocumentInvalide(doc.id, error));
        illisibles++;
        premiere ??= error;
        pile ??= stackTrace;
        premierId ??= doc.id;
      }
    }
    // Un seul rapport par page : 50 documents illisibles ne dépassent pas le
    // plafond de rapports du service d'erreurs.
    if (premiere != null) {
      _errors.reportError(
        feature: 'admin.sources_unresolved_read',
        error: premiere,
        stackTrace: pile,
        context:
            'import_unresolved : $illisibles documents illisibles sur '
            '${docs.length}, dont $premierId',
      );
    }
    return PageNonResolus(
      documents: documents,
      suite: docs.length < kTaillePageNonResolus
          ? null
          : CurseurPage(docs.last),
      fromCache: snapshot.metadata.isFromCache,
    );
  }
}
