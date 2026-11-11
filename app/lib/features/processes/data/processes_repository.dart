import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/modele_processus.dart';

/// Modèle refusé par [erreurModele] avant l'écriture : les règles ne lisent pas
/// les journées (ADR-009), l'application ne les écrit qu'à cette condition.
class ModeleInvalide implements Exception {
  const ModeleInvalide(this.message);

  final String message;

  @override
  String toString() => 'ModeleInvalide : $message';
}

/// Accès à `process_templates/` (ADR-009). Les écrans passent par cette
/// interface ; les tests la remplacent par un double sans Firebase.
///
/// Lectures ordinaires avec le cache hors ligne, aucune transaction : chaque
/// écriture est faite dans le cache dès l'appel, et sa `Future` se termine quand
/// le serveur l'a acceptée.
abstract class ProcessesRepository {
  /// Tous les modèles du groupe, à chaque changement, avec la provenance de la
  /// lecture. Un document illisible est rapporté et rendu comme tel : il ne vide
  /// pas la liste.
  Stream<ListeLue<ModeleProcessus>> watchAll();

  /// Clé neuve d'une journée ou d'un élément (`doc().id`).
  String newKey();

  /// Crée un modèle de [ownerUid]. [ownerName] : nom du jeton de l'auteur, `null`
  /// s'il n'en a pas (champ absent). `written` échoue par [ModeleInvalide] si
  /// [erreurModele] refuse le contenu : rien n'est écrit.
  CreationEnCours create({
    required ContenuModele content,
    required String ownerUid,
    required String? ownerName,
  });

  /// Modifie le modèle [id] : `owner_uid` et `created_at` ne sont pas écrits,
  /// `updated_at` est posée par le serveur, `owner_name` est réécrit ou retiré.
  Future<void> update({
    required String id,
    required ContenuModele content,
    required String? ownerName,
  });

  /// « Copier dans mes processus » : nouveau document au nom de [ownerUid], même
  /// nom, clés de journées et d'étapes neuves.
  CreationEnCours copy({
    required ModeleProcessus source,
    required String ownerUid,
    required String? ownerName,
  });

  /// « Dupliquer » : comme [copy], nommé « {nom} (copie) ».
  CreationEnCours duplicate({
    required ModeleProcessus source,
    required String ownerUid,
    required String? ownerName,
  });

  /// Supprime le modèle [id]. Aucun brassin n'est écrit : chacun garde son
  /// déroulé.
  Future<void> delete(String id);
}

/// Nom d'une duplication.
String nomDuplication(String name) => '${name.trim()} (copie)';

/// [ProcessesRepository] sur Cloud Firestore.
class FirestoreProcessesRepository implements ProcessesRepository {
  FirestoreProcessesRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _templates =>
      _firestore.collection('process_templates');

  @override
  Stream<ListeLue<ModeleProcessus>> watchAll() => _templates
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ListeLue<ModeleProcessus>(
          documents: [
            for (final doc in snapshot.docs)
              _read(doc.id, doc.data(), doc.metadata.hasPendingWrites),
          ],
          fromCache: snapshot.metadata.isFromCache,
        ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'processes.watch_all',
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran affiche la panne.
        Error.throwWithStackTrace(error, stackTrace);
      });

  DocumentLu<ModeleProcessus> _read(
    String id,
    Map<String, dynamic> data,
    bool hasPendingWrites,
  ) {
    try {
      return DocumentValide(
        id,
        ModeleProcessus.fromFirestore(
          id,
          data,
          hasPendingWrites: hasPendingWrites,
        ),
      );
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'processes.read',
        error: error,
        stackTrace: stackTrace,
        context: 'process_templates/$id illisible',
      );
      return DocumentInvalide(id, error);
    }
  }

  @override
  String newKey() => _templates.doc().id;

  @override
  CreationEnCours create({
    required ContenuModele content,
    required String ownerUid,
    required String? ownerName,
  }) {
    final ref = _templates.doc();
    final written = _guard('processes.create', () {
      _verifier(content);
      return ref.set({
        ...content.toFirestore(),
        'owner_uid': ownerUid,
        ...champFacultatif('owner_name', ownerName, creation: true),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
    return (id: ref.id, written: written);
  }

  @override
  Future<void> update({
    required String id,
    required ContenuModele content,
    required String? ownerName,
  }) => _guard('processes.update', () {
    _verifier(content);
    return _templates.doc(id).update({
      ...content.toFirestore(),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    });
  });

  @override
  CreationEnCours copy({
    required ModeleProcessus source,
    required String ownerUid,
    required String? ownerName,
  }) => create(
    content: copieModele(source.content, newKey),
    ownerUid: ownerUid,
    ownerName: ownerName,
  );

  @override
  CreationEnCours duplicate({
    required ModeleProcessus source,
    required String ownerUid,
    required String? ownerName,
  }) => create(
    content: copieModele(
      source.content,
      newKey,
      name: nomDuplication(source.content.name),
    ),
    ownerUid: ownerUid,
    ownerName: ownerName,
  );

  @override
  Future<void> delete(String id) =>
      _guard('processes.delete', () => _templates.doc(id).delete());

  void _verifier(ContenuModele content) {
    final erreur = erreurModele(content);
    if (erreur != null) throw ModeleInvalide(erreur);
  }

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
