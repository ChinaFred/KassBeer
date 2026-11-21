import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../../tickets/data/tickets_repository.dart'
    show AppelCallable, kCallableTimeout, kFunctionsRegion;
import '../domain/comptes_ia.dart';
import '../domain/reglages_ia.dart';

/// Nombre de comptes du mois lus par Admin › Coûts de l'IA (règle `list` de
/// `ai_usage/`, `limit <= 50`).
const kComptesMoisParPage = 50;

/// Document lu par `get()`, et provenance de la lecture.
class LectureIa<T> {
  const LectureIa(this.document, {required this.fromCache});

  final RechercheDocument<T> document;

  /// Vrai quand la lecture vient du cache local : elle peut être périmée.
  final bool fromCache;
}

/// Comptes d'un mois, pour l'administrateur.
class ComptesDuMois {
  const ComptesDuMois({
    required this.comptes,
    required this.fromCache,
    required this.tronque,
  });

  final List<DocumentLu<CompteMoisIa>> comptes;
  final bool fromCache;

  /// [kComptesMoisParPage] documents reçus : d'autres peuvent exister.
  final bool tronque;
}

/// Cause d'un refus de `saveAiSettings`.
enum CauseEchecReglagesIa {
  /// `invalid-argument` avec `details.field` : le champ est en faute.
  champ,

  /// Pas de réseau, ou pas de réponse : rien n'est sûr.
  reseau,

  /// Autre refus.
  refus,
}

/// Refus de `saveAiSettings`, déjà rapporté.
class EchecReglagesIa implements Exception {
  const EchecReglagesIa(this.cause, {this.champ, this.message});

  final CauseEchecReglagesIa cause;

  /// `details.field` : chemin du champ en faute (`features.<poste>.model`).
  final String? champ;

  /// Message du serveur, écrit en français par `settings.ts` ou
  /// `saveAiSettings.ts`, affiché sous [champ] ou en tête du formulaire.
  final String? message;
}

/// Réglages et comptes de l'IA (ADR-016) : `ai_config/policy`,
/// `ai_config/pricing`, `ai_quotas/{uid}`, `ai_usage/`, lus par `get()` seul
/// (aucun écouteur, P60), et la callable `saveAiSettings`. Aucun rapport
/// d'erreur ne porte un montant, un e-mail ni un texte de la personne (P13).
abstract class AiRepository {
  /// `ai_config/policy`, lisible par tout membre.
  Future<LectureIa<PolitiqueIa>> lirePolitique();

  /// `ai_config/pricing`, réservé à l'administrateur.
  Future<LectureIa<GrilleTarifaire>> lireGrille();

  /// `ai_quotas/{uid}` du compte connecté.
  Future<LectureIa<QuotasIa>> lireQuotas(String uid);

  /// `ai_usage/{mois}_{uid}` du compte connecté.
  Future<LectureIa<CompteMoisIa>> lireCompteMois(String mois, String uid);

  /// Comptes du mois [mois] de tous les membres, [kComptesMoisParPage] au
  /// plus, pour l'administrateur.
  Future<ComptesDuMois> listerComptesMois(String mois);

  /// `saveAiSettings` (`kind: "policy"` ou `"pricing"`). Lève
  /// [EchecReglagesIa], déjà rapporté.
  Future<void> enregistrer({required String kind, required Object value});
}

/// [AiRepository] sur Cloud Firestore et Cloud Functions.
class FirestoreAiRepository implements AiRepository {
  FirestoreAiRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
    AppelCallable? callable,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore,
       _injectedCallable = callable;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;
  final AppelCallable? _injectedCallable;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  /// Client des Cloud Functions, construit au premier appel et mémorisé
  /// (P6) : rien n'est chargé au démarrage.
  FirebaseFunctions? _functions;

  Future<LectureIa<T>> _lire<T>(
    DocumentReference<Map<String, dynamic>> ref,
    T Function(Map<String, dynamic> data) lire, {
    required String feature,
    required String quoi,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await ref.get();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: feature,
        error: error,
        stackTrace: stackTrace,
        context: '$quoi : lecture impossible',
      );
      rethrow;
    }
    final fromCache = snapshot.metadata.isFromCache;
    final data = snapshot.data();
    if (data == null) {
      return LectureIa(
        fromCache ? DocumentAbsentDuCache<T>() : DocumentAbsent<T>(),
        fromCache: fromCache,
      );
    }
    try {
      return LectureIa(DocumentTrouve(lire(data)), fromCache: fromCache);
    } on DocumentIllisible catch (error, stackTrace) {
      // Le chemin du champ seul : ni montant, ni e-mail (P13).
      _errors.reportError(
        feature: feature,
        error: error,
        stackTrace: stackTrace,
        context: '$quoi illisible : ${error.field}',
      );
      return LectureIa(DocumentIllisibleTrouve<T>(error), fromCache: fromCache);
    }
  }

  @override
  Future<LectureIa<PolitiqueIa>> lirePolitique() => _lire(
    _firestore.collection('ai_config').doc('policy'),
    PolitiqueIa.fromFirestore,
    feature: 'ai.policy',
    quoi: 'ai_config/policy',
  );

  @override
  Future<LectureIa<GrilleTarifaire>> lireGrille() => _lire(
    _firestore.collection('ai_config').doc('pricing'),
    GrilleTarifaire.fromFirestore,
    feature: 'ai.pricing',
    quoi: 'ai_config/pricing',
  );

  @override
  Future<LectureIa<QuotasIa>> lireQuotas(String uid) => _lire(
    _firestore.collection('ai_quotas').doc(uid),
    QuotasIa.fromFirestore,
    feature: 'ai.quota',
    quoi: 'ai_quotas du compte',
  );

  @override
  Future<LectureIa<CompteMoisIa>> lireCompteMois(String mois, String uid) {
    final id = idCompteMois(mois, uid);
    return _lire(
      _firestore.collection('ai_usage').doc(id),
      (data) => CompteMoisIa.fromFirestore(id, data),
      feature: 'ai.usage',
      quoi: 'ai_usage du compte, $mois',
    );
  }

  @override
  Future<ComptesDuMois> listerComptesMois(String mois) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection('ai_usage')
          .where('month', isEqualTo: mois)
          .limit(kComptesMoisParPage)
          .get();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'ai.usage_list',
        error: error,
        stackTrace: stackTrace,
        context: 'ai_usage, mois $mois',
      );
      rethrow;
    }
    final comptes = <DocumentLu<CompteMoisIa>>[];
    for (final doc in snapshot.docs) {
      try {
        comptes.add(
          DocumentValide(
            doc.id,
            CompteMoisIa.fromFirestore(doc.id, doc.data()),
          ),
        );
      } on DocumentIllisible catch (error, stackTrace) {
        _errors.reportError(
          feature: 'ai.usage_list',
          error: error,
          stackTrace: stackTrace,
          context: 'ai_usage illisible : ${error.field}',
        );
        comptes.add(DocumentInvalide(doc.id, error));
      }
    }
    return ComptesDuMois(
      comptes: comptes,
      fromCache: snapshot.metadata.isFromCache,
      tronque: snapshot.docs.length >= kComptesMoisParPage,
    );
  }

  Future<Object?> _call(Map<String, Object?> data) async {
    final injected = _injectedCallable;
    if (injected != null) return injected('saveAiSettings', data);
    final functions = _functions ??= FirebaseFunctions.instanceFor(
      region: kFunctionsRegion,
    );
    final result = await functions
        .httpsCallable(
          'saveAiSettings',
          options: HttpsCallableOptions(timeout: kCallableTimeout),
        )
        .call<Object?>(data);
    return result.data;
  }

  @override
  Future<void> enregistrer({
    required String kind,
    required Object value,
  }) async {
    try {
      await _call({'kind': kind, 'value': value});
    } on FirebaseFunctionsException catch (error, stackTrace) {
      final details = error.details;
      final champ = details is Map && details['field'] is String
          ? details['field'] as String
          : null;
      final raison = details is Map && details['reason'] is String
          ? details['reason'] as String
          : null;
      final cause = switch (error.code) {
        'invalid-argument' when champ != null && champ.isNotEmpty =>
          CauseEchecReglagesIa.champ,
        'unavailable' || 'deadline-exceeded' => CauseEchecReglagesIa.reseau,
        _ => CauseEchecReglagesIa.refus,
      };
      // Code et champ seuls : aucune valeur saisie (P13).
      _errors.reportError(
        feature: 'ai.save_settings',
        error: error,
        stackTrace: stackTrace,
        context:
            '$kind code=${error.code}${champ == null ? '' : ' field=$champ'}',
      );
      // `invalid-argument` : `details.reason` porte le texte affiché sous le
      // champ ; un autre refus (grille absente) porte son texte dans le
      // message.
      throw EchecReglagesIa(
        cause,
        champ: champ,
        message: switch (error.code) {
          'invalid-argument' => raison ?? error.message,
          'failed-precondition' => error.message,
          _ => null,
        },
      );
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'ai.save_settings',
        error: error,
        stackTrace: stackTrace,
        context: '$kind code=${error.runtimeType}',
      );
      throw const EchecReglagesIa(CauseEchecReglagesIa.reseau);
    }
  }
}
