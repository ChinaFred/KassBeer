import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/services/error_report_service.dart';
import '../../tickets/data/tickets_repository.dart'
    show AppelCallable, kFunctionsRegion, kLaunchCallableTimeout;
import '../domain/assistant_recette.dart';

/// Assistant de recette (ADR-015) : callable `recipeAssistantTurn`, un seul
/// appel par appui sur « Envoyer » ou « Résumer et continuer », jamais rejoué.
/// Aucun rapport d'erreur ne porte le texte de la personne, du modèle ni de
/// la recette : la raison, le code et des longueurs seulement (P13, P59).
/// L'écran du jour et les journées n'importent pas ce fichier (P2, P60).
abstract class AssistantRepository {
  /// Envoie [arguments] (`argumentsAssistant`). Lève [EchecAssistant], déjà
  /// rapporté.
  Future<ReponseAssistant> envoyer(Map<String, Object?> arguments);
}

/// Longueurs envoyées, pour un rapport d'erreur : jamais un texte.
String longueursAssistant(Map<String, Object?> arguments) {
  final history = arguments['history'];
  final message = arguments['message'];
  return [
    'mode=${arguments['mode'] ?? 'turn'}',
    'history=${history is List ? history.length : 0}',
    if (message is String) 'message=${message.length}',
  ].join(' ');
}

/// [AssistantRepository] sur Cloud Functions.
class FunctionsAssistantRepository implements AssistantRepository {
  FunctionsAssistantRepository({
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
    if (injected != null) return injected('recipeAssistantTurn', data);
    final functions = _functions ??= FirebaseFunctions.instanceFor(
      region: kFunctionsRegion,
    );
    // Au-delà des 120 s du serveur : il conclut avant que l'appareil
    // abandonne.
    final result = await functions
        .httpsCallable(
          'recipeAssistantTurn',
          options: HttpsCallableOptions(timeout: kLaunchCallableTimeout),
        )
        .call<Object?>(data);
    return result.data;
  }

  @override
  Future<ReponseAssistant> envoyer(Map<String, Object?> arguments) async {
    final longueurs = longueursAssistant(arguments);
    final Object? data;
    try {
      data = await _call(arguments);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      final echec = EchecAssistant.depuis(
        code: error.code,
        details: error.details,
        message: error.message,
      );
      _errors.reportError(
        feature: 'recipes.assistant',
        error: error,
        stackTrace: stackTrace,
        context:
            'code=${error.code} cause=${echec.cause.name}'
            '${echec.raison == null ? '' : ' reason=${echec.raison}'}'
            '${echec.champ == null ? '' : ' field=${echec.champ}'} $longueurs',
      );
      throw echec;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'recipes.assistant',
        error: error,
        stackTrace: stackTrace,
        context: 'code=${error.runtimeType} $longueurs',
      );
      throw const EchecAssistant(CauseEchecAssistant.resultatInconnu);
    }
    try {
      return ReponseAssistant.lire(data);
    } on FormatException catch (error, stackTrace) {
      _errors.reportError(
        feature: 'recipes.assistant',
        error: error,
        stackTrace: stackTrace,
        context: 'réponse illisible $longueurs',
      );
      throw const EchecAssistant(CauseEchecAssistant.reponseIllisible);
    }
  }
}
