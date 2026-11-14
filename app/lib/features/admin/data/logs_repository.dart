import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/services/error_report_service.dart';
import '../../tickets/data/tickets_repository.dart'
    show AppelCallable, kCallableTimeout, kFunctionsRegion;
import '../domain/log_entry.dart';

/// Admin › Journaux (ADR-011, J2) : recherche dans la sortie des Cloud
/// Functions par la callable `queryLogs`. Le client ne parle jamais à l'API
/// Cloud Logging.
abstract class LogsRepository {
  /// Une page de journaux pour [filtres], après [suite] (`nextPageToken` de la
  /// page précédente). Lève [EchecJournaux].
  Future<PageJournaux> rechercher(FiltresJournaux filtres, {String? suite});
}

/// [LogsRepository] sur Cloud Functions.
class FunctionsLogsRepository implements LogsRepository {
  FunctionsLogsRepository({
    required ErrorReportService errorReportService,
    AppelCallable? callable,
  }) : _errors = errorReportService,
       _injectedCallable = callable;

  final ErrorReportService _errors;
  final AppelCallable? _injectedCallable;

  /// Client des Cloud Functions, construit au premier appel et mémorisé
  /// (P6) : rien n'est chargé au démarrage.
  FirebaseFunctions? _functions;

  Future<Object?> _call(Map<String, Object?> data) async {
    final injected = _injectedCallable;
    if (injected != null) return injected('queryLogs', data);
    final functions = _functions ??= FirebaseFunctions.instanceFor(
      region: kFunctionsRegion,
    );
    final result = await functions
        .httpsCallable(
          'queryLogs',
          options: HttpsCallableOptions(timeout: kCallableTimeout),
        )
        .call<Object?>(data);
    return result.data;
  }

  @override
  Future<PageJournaux> rechercher(
    FiltresJournaux filtres, {
    String? suite,
  }) async {
    final where = suite == null ? 'première page' : 'page suivante';
    final Object? data;
    try {
      data = await _call({...filtres.versArguments(), 'pageToken': ?suite});
    } on FirebaseFunctionsException catch (error, stackTrace) {
      final echec = EchecJournaux.depuis(
        code: error.code,
        details: error.details,
        message: error.message,
      );
      // Codes seuls : ni filtre, ni texte cherché, ni texte de journal (P13).
      _errors.reportError(
        feature: 'admin.logs',
        error: error,
        stackTrace: stackTrace,
        context:
            '$where code=${error.code} cause=${echec.cause.name}'
            '${echec.champ == null ? '' : ' field=${echec.champ}'}',
      );
      throw echec;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'admin.logs',
        error: error,
        stackTrace: stackTrace,
        context: '$where code=${error.runtimeType}',
      );
      throw const EchecJournaux(CauseEchecJournaux.indisponible);
    }
    try {
      return PageJournaux.depuis(data);
    } on FormatException catch (error, stackTrace) {
      _errors.reportError(
        feature: 'admin.logs',
        error: error,
        stackTrace: stackTrace,
        context: '$where réponse illisible',
      );
      throw const EchecJournaux(CauseEchecJournaux.indisponible);
    }
  }
}
