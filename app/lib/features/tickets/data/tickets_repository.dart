import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/etat_jeton_github.dart';
import '../domain/ticket.dart';

/// Accès à `tickets/` et `ticket_status/github` (ADR-006, P23). Les écrans
/// passent par cette interface ; les tests la remplacent par un double.
///
/// Lectures ordinaires avec le cache hors ligne ; aucune callable, aucune
/// `runTransaction`, aucun `Source.server`. Aucun rapport d'erreur ne porte le
/// titre, la description ni l'e-mail d'un ticket (P13).
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

  /// Tickets `pending` ou `send_failed`, pour l'administrateur.
  Stream<ListeLue<Ticket>> watchNotSent();

  /// Tickets dont l'Issue a disparu (`issue_missing_since`), pour
  /// l'administrateur.
  Stream<ListeLue<Ticket>> watchIssueMissing();
}

/// [TicketsRepository] sur Cloud Firestore.
class FirestoreTicketsRepository implements TicketsRepository {
  FirestoreTicketsRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
    DateTime Function()? clock,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore,
       _clock = clock ?? DateTime.now;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;
  final DateTime Function() _clock;

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
  Stream<ListeLue<Ticket>> watchNotSent() => _watch(
    _tickets.where(
      'status',
      whereIn: [
        TicketStatus.pending.storedValue,
        TicketStatus.sendFailed.storedValue,
      ],
    ),
    'tickets.watch_not_sent',
  );

  @override
  Stream<ListeLue<Ticket>> watchIssueMissing() => _watch(
    _tickets.where('issue_missing_since', isNull: false),
    'tickets.watch_issue_missing',
  );

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
}
