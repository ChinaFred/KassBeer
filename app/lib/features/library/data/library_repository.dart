import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/recette_publique.dart';
import '../domain/referentiel.dart';

/// Borne haute d'une recherche par préfixe : U+F8FF, dernier point de code de
/// la zone privée, trié après toute lettre ou chiffre.
final kFinDePrefixe = String.fromCharCode(0xF8FF);

/// Taille d'une page de recettes publiques (ADR-005 : pages de 50).
const kTaillePageRecettes = 50;

/// Position après la dernière recette d'une page. Opaque pour l'écran : le dépôt
/// de données Firestore y range le dernier document lu.
class CurseurPage {
  const CurseurPage(this.valeur);

  final Object valeur;
}

/// Page de recettes publiques : documents lus, curseur de la page suivante
/// (`null` à la dernière page) et provenance de la lecture.
class PageRecettesPubliques {
  const PageRecettesPubliques({
    required this.documents,
    required this.suite,
    required this.fromCache,
  });

  final List<DocumentLu<RecettePublique>> documents;
  final CurseurPage? suite;

  /// Vrai quand la page vient du cache local : elle peut être incomplète.
  final bool fromCache;
}

/// Lecture de la Bibliothèque : `beer_index/`, `beer_*/`, `public_recipes/`.
/// Lecture seule, par `get()` : jamais d'écouteur sur ces collections (P22).
/// Chaque panne est rapportée puis relancée ; chaque document illisible est
/// rapporté et rendu comme tel.
abstract class LibraryRepository {
  /// Index compact de [nature]. Lu une fois par session depuis le serveur, puis
  /// rendu de mémoire.
  Future<RechercheDocument<IndexReferentiel>> lireIndex(
    NatureReferentiel nature,
  );

  /// Fiche [id] de [nature].
  Future<RechercheDocument<FicheReferentiel>> lireFiche(
    NatureReferentiel nature,
    String id,
  );

  /// Page de [kTaillePageRecettes] recettes publiques ordonnées par
  /// `search_name`, après [apres] ; [prefixe] : début du nom, normalisé comme
  /// `search_name` (`normaliserNomRecherche`) ; vide après normalisation, aucun
  /// filtre.
  Future<PageRecettesPubliques> pageRecettesPubliques({
    String prefixe = '',
    CurseurPage? apres,
  });

  /// Recette publique [id].
  Future<RechercheDocument<RecettePublique>> lireRecettePublique(String id);
}

/// [LibraryRepository] sur Cloud Firestore.
class FirestoreLibraryRepository implements LibraryRepository {
  FirestoreLibraryRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  /// Index lus du serveur pendant la session, un document par nature.
  final _index = <NatureReferentiel, DocumentTrouve<IndexReferentiel>>{};

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  @override
  Future<RechercheDocument<IndexReferentiel>> lireIndex(
    NatureReferentiel nature,
  ) async {
    final memo = _index[nature];
    if (memo != null) return memo;
    final path = 'beer_index/${nature.indexId}';
    final snapshot = await _get('library.index', path);
    final data = snapshot.data();
    if (data == null) return _absent(snapshot);
    final IndexReferentiel index;
    try {
      index = IndexReferentiel.fromFirestore(nature, data);
    } on DocumentIllisible catch (error, stackTrace) {
      return _illisible('library.index', path, error, stackTrace);
    }
    final premiere = index.premiereErreur;
    if (premiere != null) {
      _errors.reportError(
        feature: 'library.index_entries',
        error: premiere,
        context:
            '$path : ${index.illisibles} entrées illisibles sur '
            '${index.illisibles + index.entrees.length}',
      );
    }
    final found = DocumentTrouve(index);
    // Une lecture du cache (hors ligne) n'est pas gardée : la suivante, en ligne,
    // ira au serveur.
    if (!snapshot.metadata.isFromCache) _index[nature] = found;
    return found;
  }

  @override
  Future<RechercheDocument<FicheReferentiel>> lireFiche(
    NatureReferentiel nature,
    String id,
  ) async {
    final path = '${nature.collection}/$id';
    final snapshot = await _get('library.entry', path);
    final data = snapshot.data();
    if (data == null) return _absent(snapshot);
    try {
      return DocumentTrouve(FicheReferentiel.fromFirestore(nature, id, data));
    } on DocumentIllisible catch (error, stackTrace) {
      return _illisible('library.entry', path, error, stackTrace);
    }
  }

  @override
  Future<PageRecettesPubliques> pageRecettesPubliques({
    String prefixe = '',
    CurseurPage? apres,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('public_recipes')
        .orderBy('search_name');
    final debut = normaliserNomRecherche(prefixe);
    if (debut.isNotEmpty) {
      query = query
          .where('search_name', isGreaterThanOrEqualTo: debut)
          .where('search_name', isLessThan: '$debut$kFinDePrefixe');
    }
    final QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      if (apres != null) {
        query = query.startAfterDocument(apres.valeur as DocumentSnapshot);
      }
      snapshot = await query.limit(kTaillePageRecettes).get();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: 'library.public_recipes',
        error: error,
        stackTrace: stackTrace,
        context: apres == null ? 'première page' : 'page suivante',
      );
      rethrow;
    }
    final docs = snapshot.docs;
    return PageRecettesPubliques(
      documents: [for (final doc in docs) _recette(doc.id, doc.data())],
      suite: docs.length < kTaillePageRecettes ? null : CurseurPage(docs.last),
      fromCache: snapshot.metadata.isFromCache,
    );
  }

  @override
  Future<RechercheDocument<RecettePublique>> lireRecettePublique(
    String id,
  ) async {
    final snapshot = await _get('library.public_recipe', 'public_recipes/$id');
    final data = snapshot.data();
    if (data == null) return _absent(snapshot);
    return switch (_recette(id, data)) {
      DocumentValide(:final value) => DocumentTrouve(value),
      DocumentInvalide(:final error) => DocumentIllisibleTrouve(error),
    };
  }

  DocumentLu<RecettePublique> _recette(String id, Map<String, dynamic> data) {
    try {
      return DocumentValide(id, RecettePublique.fromFirestore(id, data));
    } on DocumentIllisible catch (error, stackTrace) {
      _errors.reportError(
        feature: 'library.public_recipe_read',
        error: error,
        stackTrace: stackTrace,
        context: 'public_recipes/$id illisible',
      );
      return DocumentInvalide(id, error);
    }
  }

  /// `get()` ordinaire (cache puis serveur) ; une panne est rapportée puis
  /// relancée pour l'écran.
  Future<DocumentSnapshot<Map<String, dynamic>>> _get(
    String feature,
    String path,
  ) async {
    try {
      return await _firestore.doc(path).get();
    } catch (error, stackTrace) {
      _errors.reportError(
        feature: feature,
        error: error,
        stackTrace: stackTrace,
        context: path,
      );
      rethrow;
    }
  }

  /// Document absent : du serveur (pas encore écrit), ou du cache seul (hors
  /// ligne), jamais annoncé absent dans ce cas.
  RechercheDocument<T> _absent<T>(DocumentSnapshot<Object?> snapshot) =>
      snapshot.metadata.isFromCache
      ? DocumentAbsentDuCache<T>()
      : DocumentAbsent<T>();

  RechercheDocument<T> _illisible<T>(
    String feature,
    String path,
    DocumentIllisible error,
    StackTrace stackTrace,
  ) {
    _errors.reportError(
      feature: feature,
      error: error,
      stackTrace: stackTrace,
      context: '$path illisible',
    );
    return DocumentIllisibleTrouve<T>(error);
  }
}
