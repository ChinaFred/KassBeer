import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/etat_jeton_github.dart';
import '../domain/ticket.dart';
import '../domain/ticket_analysis.dart';
import '../domain/ticket_launch.dart';

/// Accès à `tickets/`, `ticket_status/github` et `ticket_status/launches`
/// (ADR-006, P23, P41), et aux callables `answerTicketAnalysis`,
/// `launchTicketAnalysis` et `launchTicketDevelopment` (ADR-008). Les écrans
/// passent par cette interface ; les tests la remplacent par un double.
///
/// Lectures ordinaires avec le cache hors ligne ; aucune `runTransaction`,
/// aucun `Source.server`. Les callables sont réservées à l'administrateur.
/// Aucun rapport d'erreur ne porte le titre, la description, l'e-mail d'un
/// ticket, le texte d'une analyse ou d'une réponse, ni un lien de session
/// (P13, P33, P41).
abstract class TicketsRepository {
  /// Identifiant d'un ticket, créé par l'appareil à l'ouverture du formulaire :
  /// un double appui écrit le même document.
  String newTicketId();

  /// Crée `tickets/{id}` : écrit dans le cache dès l'appel, la `Future` se
  /// termine quand le serveur l'a accepté. Un refus est rapporté puis relancé.
  Future<void> create({
    required String id,
    required TicketBrouillon brouillon,
    required String authorUid,
    required String authorEmail,
    required String? appVersion,
    required String platform,
  });

  /// Tickets de [uid], à chaque changement ; un ticket illisible est rapporté
  /// et rendu comme tel.
  Stream<ListeLue<Ticket>> watchMine(String uid);

  /// Note que l'auteur a lu le suivi de [id] (`seen_by_author_at`, heure du
  /// serveur comme l'exigent les règles). Marche hors ligne. Un échec est
  /// rapporté ; la pastille reste allumée.
  Future<void> markSeen(String id);

  /// `ticket_status/github`, pour l'administrateur.
  Stream<RechercheDocument<EtatJetonGithub>> watchGithubStatus();

  /// Tous les tickets, pour l'administrateur (Admin › Tickets, compteur du
  /// menu, bandeau).
  Stream<ListeLue<Ticket>> watchAll();

  /// Décisions du ticket [ticketId], pour l'administrateur.
  Stream<ListeLue<TicketDecision>> watchDecisions(String ticketId);

  /// Identifiant d'une décision, créé par l'appareil.
  String newDecisionId(String ticketId);

  /// Crée `tickets/{ticketId}/decisions/{id}` (`state: pending`,
  /// `requested_at` à l'heure du serveur). Écrit dans le cache dès l'appel ;
  /// la `Future` rend vrai quand le serveur l'a acceptée, faux s'il l'a
  /// refusée. Un refus est rapporté ici, sans le texte (P13) : l'écran
  /// n'attrape rien, il annonce le refus.
  Future<bool> createDecision({
    required String ticketId,
    required String id,
    required TicketDecisionAction action,
    required String? text,
    required String requestedByUid,
  });

  /// Demande un nouvel essai de publication d'un ticket `send_failed`
  /// (`retry_requested_at`). Même déroulé que [createDecision].
  Future<bool> retrySend(String ticketId);

  /// Demande la reprise d'une décision `failed` (`retry_requested_at`). Même
  /// déroulé que [createDecision].
  Future<bool> retryDecision({
    required String ticketId,
    required String decisionId,
  });

  /// `tickets/{ticketId}/admin/analysis`, pour l'administrateur seul.
  Stream<RechercheDocument<TicketAnalysisDoc>> watchAnalysis(String ticketId);

  /// Publie [answer] sur l'Issue de [ticketId] (callable
  /// `answerTicketAnalysis`). Rend `null` si le serveur l'a publiée ; sinon
  /// l'échec, déjà rapporté sans le texte (P13).
  Future<EchecReponse?> answer({
    required String ticketId,
    required String answer,
  });

  /// `tickets/{ticketId}/admin/launches`, pour l'administrateur seul (P41).
  Stream<RechercheDocument<TicketLaunchesDoc>> watchLaunches(String ticketId);

  /// `ticket_status/launches` : compteurs, plafond et jetons des routines,
  /// pour l'administrateur seul (P41).
  Stream<RechercheDocument<EtatLancements>> watchLaunchStatus();

  /// Lance [action] sur [ticketId] (callable `launchTicketAnalysis` ou
  /// `launchTicketDevelopment`). Un seul appel, jamais rejoué. Tout échec est
  /// rapporté ici, puis rendu.
  Future<ResultatLancement> launch({
    required String ticketId,
    required ActionLancement action,
  });
}

/// Appel d'une callable : nom, données ; rend `data` de la réponse. Remplacé
/// dans les tests.
typedef AppelCallable =
    Future<Object?> Function(String name, Map<String, Object?> data);

/// Région des Cloud Functions (ADR-006) : une callable appelée ailleurs
/// répond 404.
const kFunctionsRegion = 'europe-west1';

/// Délai d'une callable côté client, au-delà des 60 s du serveur (ADR-008) :
/// le serveur conclut avant que l'appareil abandonne.
const kCallableTimeout = Duration(seconds: 70);

/// Délai d'une callable de lancement côté client, au-delà des 120 s du
/// serveur (ADR-008) : le serveur conclut avant que l'appareil abandonne.
const kLaunchCallableTimeout = Duration(seconds: 130);

/// [TicketsRepository] sur Cloud Firestore.
class FirestoreTicketsRepository implements TicketsRepository {
  FirestoreTicketsRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
    DateTime Function()? clock,
    AppelCallable? callable,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore,
       _clock = clock ?? DateTime.now,
       _injectedCallable = callable;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;
  final DateTime Function() _clock;
  final AppelCallable? _injectedCallable;

  /// Client des Cloud Functions, construit au premier appel d'une callable
  /// et mémorisé (P6) : rien n'est chargé au démarrage.
  FirebaseFunctions? _functions;

  Future<Object?> _call(
    String name,
    Map<String, Object?> data, {
    Duration timeout = kCallableTimeout,
  }) async {
    final injected = _injectedCallable;
    if (injected != null) return injected(name, data);
    final functions = _functions ??= FirebaseFunctions.instanceFor(
      region: kFunctionsRegion,
    );
    final result = await functions
        .httpsCallable(name, options: HttpsCallableOptions(timeout: timeout))
        .call<Object?>(data);
    return result.data;
  }

  /// Heure de l'appareil des tickets créés dans cette session : affichée tant
  /// que `created_at` attend le serveur.
  final Map<String, DateTime> _createdOnDevice = {};

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _firestore.collection('tickets');

  @override
  String newTicketId() => _tickets.doc().id;

  @override
  Future<void> create({
    required String id,
    required TicketBrouillon brouillon,
    required String authorUid,
    required String authorEmail,
    required String? appVersion,
    required String platform,
  }) async {
    _createdOnDevice[id] = _clock();
    try {
      await _tickets.doc(id).set({
        'type': brouillon.type.storedValue,
        'title': brouillon.title,
        'description': brouillon.description,
        'screen': brouillon.screen,
        'app_version': ?appVersion,
        'platform': platform,
        'author_uid': authorUid,
        'author_email': authorEmail.trim().toLowerCase(),
        'created_at': FieldValue.serverTimestamp(),
        'status': TicketStatus.pending.storedValue,
      });
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'tickets.create',
        error: error,
        stackTrace: stackTrace,
        // Ni le titre, ni la description, ni l'e-mail (P13).
        context:
            'tickets/$id '
            'code=${error is FirebaseException ? error.code : error.runtimeType}',
      );
      rethrow;
    }
  }

  @override
  Stream<ListeLue<Ticket>> watchMine(String uid) => _watch(
    _tickets.where('author_uid', isEqualTo: uid),
    'tickets.watch_mine',
  );

  @override
  Stream<ListeLue<Ticket>> watchAll() => _watch(_tickets, 'tickets.watch_all');

  CollectionReference<Map<String, dynamic>> _decisions(String ticketId) =>
      _tickets.doc(ticketId).collection('decisions');

  @override
  Stream<ListeLue<TicketDecision>> watchDecisions(String ticketId) =>
      _decisions(ticketId)
          .snapshots(includeMetadataChanges: true)
          .map(
            (snapshot) => ListeLue<TicketDecision>(
              documents: [
                for (final doc in snapshot.docs) _readDecision(ticketId, doc),
              ],
              fromCache: snapshot.metadata.isFromCache,
            ),
          )
          .handleError((Object error, StackTrace stackTrace) {
            _errors.reportError(
              feature: 'tickets.watch_decisions',
              error: error,
              stackTrace: stackTrace,
              context: 'tickets/$ticketId/decisions',
            );
            Error.throwWithStackTrace(error, stackTrace);
          });

  DocumentLu<TicketDecision> _readDecision(
    String ticketId,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    try {
      return DocumentValide(
        doc.id,
        TicketDecision.fromFirestore(
          doc.id,
          doc.data(),
          hasPendingWrites: doc.metadata.hasPendingWrites,
        ),
      );
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'tickets.read_decision',
        error: error,
        stackTrace: stackTrace,
        context: 'tickets/$ticketId/decisions/${doc.id} illisible',
      );
      return DocumentInvalide(doc.id, error);
    }
  }

  @override
  String newDecisionId(String ticketId) => _decisions(ticketId).doc().id;

  @override
  Future<bool> createDecision({
    required String ticketId,
    required String id,
    required TicketDecisionAction action,
    required String? text,
    required String requestedByUid,
  }) => _write(
    'tickets.create_decision',
    'tickets/$ticketId/decisions/$id action=${action.storedValue}',
    () => _decisions(ticketId).doc(id).set({
      'action': action.storedValue,
      'text': ?text,
      'state': TicketDecisionState.pending.storedValue,
      'requested_by_uid': requestedByUid,
      'requested_at': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<bool> retrySend(String ticketId) => _write(
    'tickets.retry_send',
    'tickets/$ticketId',
    () => _tickets.doc(ticketId).update({
      'retry_requested_at': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<bool> retryDecision({
    required String ticketId,
    required String decisionId,
  }) => _write(
    'tickets.retry_decision',
    'tickets/$ticketId/decisions/$decisionId',
    () => _decisions(ticketId).doc(decisionId).update({
      'retry_requested_at': FieldValue.serverTimestamp(),
    }),
  );

  /// Écriture d'administration : vrai si le serveur l'accepte. Un refus est
  /// rapporté avec [where] (chemin et action, jamais le texte : P13) et rend
  /// faux.
  Future<bool> _write(
    String feature,
    String where,
    Future<void> Function() write,
  ) async {
    try {
      await write();
      return true;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: feature,
        error: error,
        stackTrace: stackTrace,
        context:
            '$where '
            'code=${error is FirebaseException ? error.code : error.runtimeType}',
      );
      return false;
    }
  }

  Stream<ListeLue<Ticket>> _watch(
    Query<Map<String, dynamic>> query,
    String feature,
  ) => query
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ListeLue<Ticket>(
          documents: [for (final doc in snapshot.docs) _read(doc)],
          fromCache: snapshot.metadata.isFromCache,
        ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: feature,
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran affiche la panne.
        Error.throwWithStackTrace(error, stackTrace);
      });

  DocumentLu<Ticket> _read(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return DocumentValide(
        doc.id,
        Ticket.fromFirestore(
          doc.id,
          doc.data(),
          hasPendingWrites: doc.metadata.hasPendingWrites,
          createdOnDevice: _createdOnDevice[doc.id],
        ),
      );
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'tickets.read',
        error: error,
        stackTrace: stackTrace,
        context: 'tickets/${doc.id} illisible',
      );
      return DocumentInvalide(doc.id, error);
    }
  }

  @override
  Future<void> markSeen(String id) async {
    try {
      await _tickets.doc(id).update({
        'seen_by_author_at': FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'tickets.mark_seen',
        error: error,
        stackTrace: stackTrace,
        context: 'tickets/$id',
      );
    }
  }

  @override
  Stream<RechercheDocument<TicketAnalysisDoc>> watchAnalysis(String ticketId) =>
      _tickets
          .doc(ticketId)
          .collection('admin')
          .doc('analysis')
          .snapshots(includeMetadataChanges: true)
          .map<RechercheDocument<TicketAnalysisDoc>>((snapshot) {
            final data = snapshot.data();
            if (!snapshot.exists || data == null) {
              return snapshot.metadata.isFromCache
                  ? DocumentAbsentDuCache<TicketAnalysisDoc>()
                  : DocumentAbsent<TicketAnalysisDoc>();
            }
            try {
              return DocumentTrouve(TicketAnalysisDoc.fromFirestore(data));
            } on DocumentIllisible catch (error, stackTrace) {
              _errors.reportError(
                feature: 'tickets.read_analysis',
                error: error,
                stackTrace: stackTrace,
                context: 'tickets/$ticketId/admin/analysis illisible',
              );
              return DocumentIllisibleTrouve<TicketAnalysisDoc>(error);
            }
          })
          .handleError((Object error, StackTrace stackTrace) {
            _errors.reportError(
              feature: 'tickets.watch_analysis',
              error: error,
              stackTrace: stackTrace,
              context: 'tickets/$ticketId/admin/analysis',
            );
            Error.throwWithStackTrace(error, stackTrace);
          });

  @override
  Future<EchecReponse?> answer({
    required String ticketId,
    required String answer,
  }) async {
    try {
      await _call('answerTicketAnalysis', {
        'ticketId': ticketId,
        'answer': answer,
      });
      return null;
    } on FirebaseFunctionsException catch (error, stackTrace) {
      final echec = EchecReponse.depuis(
        code: error.code,
        details: error.details,
      );
      _errors.reportError(
        feature: 'tickets.answer',
        // Le message vient du serveur, jamais du texte saisi ; le contexte ne
        // porte ni la réponse ni le motif (P13).
        error: error,
        stackTrace: stackTrace,
        context:
            'tickets/$ticketId code=${error.code}'
            '${echec.codeServeur == null ? '' : ' reason_code=${echec.codeServeur}'}'
            '${echec.champ == null ? '' : ' field=${echec.champ}'}'
            '${echec.partiel ? ' partial' : ''}',
      );
      return echec;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'tickets.answer',
        error: error,
        stackTrace: stackTrace,
        context: 'tickets/$ticketId code=${error.runtimeType}',
      );
      return const EchecReponse(CauseEchecReponse.autre);
    }
  }

  @override
  Stream<RechercheDocument<EtatJetonGithub>> watchGithubStatus() => _firestore
      .collection('ticket_status')
      .doc('github')
      .snapshots(includeMetadataChanges: true)
      .map<RechercheDocument<EtatJetonGithub>>((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return snapshot.metadata.isFromCache
              ? DocumentAbsentDuCache<EtatJetonGithub>()
              : DocumentAbsent<EtatJetonGithub>();
        }
        try {
          return DocumentTrouve(EtatJetonGithub.fromFirestore(data));
        } on DocumentIllisible catch (error, stackTrace) {
          _errors.reportError(
            feature: 'tickets.read_github_status',
            error: error,
            stackTrace: stackTrace,
            context: 'ticket_status/github illisible',
          );
          return DocumentIllisibleTrouve<EtatJetonGithub>(error);
        }
      })
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'tickets.watch_github_status',
          error: error,
          stackTrace: stackTrace,
        );
        Error.throwWithStackTrace(error, stackTrace);
      });

  @override
  Stream<RechercheDocument<TicketLaunchesDoc>> watchLaunches(String ticketId) =>
      _watchDocument(
        _tickets.doc(ticketId).collection('admin').doc('launches'),
        TicketLaunchesDoc.fromFirestore,
        readFeature: 'tickets.read_launches',
        watchFeature: 'tickets.watch_launches',
        path: 'tickets/$ticketId/admin/launches',
      );

  @override
  Stream<RechercheDocument<EtatLancements>> watchLaunchStatus() =>
      _watchDocument(
        _firestore.collection('ticket_status').doc('launches'),
        EtatLancements.fromFirestore,
        readFeature: 'tickets.read_launch_status',
        watchFeature: 'tickets.watch_launch_status',
        path: 'ticket_status/launches',
      );

  /// Lecture d'un document écrit par le serveur : absent (du cache ou du
  /// serveur), trouvé ou illisible. Un document illisible ou une panne est
  /// rapporté avec [path] seul.
  Stream<RechercheDocument<T>> _watchDocument<T>(
    DocumentReference<Map<String, dynamic>> ref,
    T Function(Map<String, dynamic> data) parse, {
    required String readFeature,
    required String watchFeature,
    required String path,
  }) => ref
      .snapshots(includeMetadataChanges: true)
      .map<RechercheDocument<T>>((snapshot) {
        final data = snapshot.data();
        if (!snapshot.exists || data == null) {
          return snapshot.metadata.isFromCache
              ? DocumentAbsentDuCache<T>()
              : DocumentAbsent<T>();
        }
        try {
          return DocumentTrouve(parse(data));
        } on DocumentIllisible catch (error, stackTrace) {
          _errors.reportError(
            feature: readFeature,
            error: error,
            stackTrace: stackTrace,
            context: '$path illisible',
          );
          return DocumentIllisibleTrouve<T>(error);
        }
      })
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: watchFeature,
          error: error,
          stackTrace: stackTrace,
          context: path,
        );
        Error.throwWithStackTrace(error, stackTrace);
      });

  @override
  Future<ResultatLancement> launch({
    required String ticketId,
    required ActionLancement action,
  }) async {
    final where = 'tickets/$ticketId action=${action.storedValue}';
    try {
      final data = await _call(action.callable, {
        'ticketId': ticketId,
      }, timeout: kLaunchCallableTimeout);
      return ResultatLancement.depuisReponse(data);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      final resultat = ResultatLancement.depuisErreur(
        code: error.code,
        details: error.details,
      );
      _errors.reportError(
        feature: 'tickets.launch',
        error: error,
        stackTrace: stackTrace,
        // Codes seuls : ni le motif, ni un lien de session (P41).
        context:
            '$where code=${error.code}'
            '${resultat.code == null ? '' : ' reason_code=${resultat.code}'}',
      );
      return resultat;
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'tickets.launch',
        error: error,
        stackTrace: stackTrace,
        context: '$where code=${error.runtimeType}',
      );
      // Sans réponse, la session est peut-être partie.
      return const ResultatLancement(IssueLancement.perdu);
    }
  }
}
