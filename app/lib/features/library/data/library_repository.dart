import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:exchange/exchange.dart' show NomNonResolu;

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/recette_publique.dart';
import '../domain/referentiel.dart';

/// Borne haute d'une recherche par préfixe : U+F8FF, dernier point de code de
/// la zone privée, trié après toute lettre ou chiffre.
final kFinDePrefixe = String.fromCharCode(0xF8FF);

/// Collection des noms non résolus d'un import ou de l'ingestion.
const kNonResolus = 'import_unresolved';

/// Noms signalés par lot (`WriteBatch`) : chaque `set` fusionné lit le document
/// pour les règles, et un lot est limité à 20 lectures en production.
const kLotSignalements = 10;

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

/// Lecture de la Bibliothèque : `beer_index/`, `beer_*/`, `public_recipes/`,
/// par `get()` : jamais d'écouteur sur ces collections (P22). Chaque panne
/// est rapportée puis relancée ; chaque document illisible est rapporté et rendu
/// comme tel. Seule écriture : le signalement des noms non résolus d'un import
/// (`import_unresolved/`, ADR-005, E6).
abstract class LibraryRepository {
  /// Index compact de [nature]. Lu une fois par session depuis le serveur, puis
  /// rendu de mémoire. [cacheSeul] (hors ligne) : lu dans le cache seul, sans
  /// attente du réseau ; absent du cache, il rend [DocumentAbsentDuCache] sans
  /// rapport.
  Future<RechercheDocument<IndexReferentiel>> lireIndex(
    NatureReferentiel nature, {
    bool cacheSeul = false,
  });

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

  /// Signale [noms], non résolus par un import (200 au plus, plafond tenu par
  /// l'appelant) : crée ou met à jour `import_unresolved/{empreinte}`
  /// (`count` + 1), par lots de [kLotSignalements]. Écriture simple, mise en
  /// attente hors ligne. Ne lève jamais : chaque échec est rapporté, et
  /// n'empêche ni l'import ni les autres lots.
  Future<void> signalerNonResolus(List<NomNonResolu> noms);
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
    NatureReferentiel nature, {
    bool cacheSeul = false,
  }) async {
    final memo = _index[nature];
    if (memo != null) return memo;
    final path = 'beer_index/${nature.indexId}';
    final DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .doc(path)
          .get(cacheSeul ? const GetOptions(source: Source.cache) : null);
    } on FirebaseException catch (error, stackTrace) {
      // Cache seul : `unavailable` dit que le document n'est pas dans le cache
      // (aucun réseau n'est demandé). Ce n'est pas une panne : rien n'est
      // rapporté, l'appelant affiche « indisponible ».
      if (cacheSeul && error.code == 'unavailable') {
        return DocumentAbsentDuCache<IndexReferentiel>();
      }
      _rapporterIndex(error, stackTrace, path);
      rethrow;
    } catch (error, stackTrace) {
      _rapporterIndex(error, stackTrace, path);
      rethrow;
    }
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

  void _rapporterIndex(Object error, StackTrace stackTrace, String path) =>
      _errors.reportError(
        feature: 'library.index',
        error: error,
        stackTrace: stackTrace,
        context: path,
      );

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

  /// Un lot par tranche de [kLotSignalements] noms, chacun envoyé par un
  /// `WriteBatch` : une seule écriture en file d'attente par lot, hors ligne
  /// compris. Un lot refusé est rapporté ; les autres partent.
  @override
  Future<void> signalerNonResolus(List<NomNonResolu> noms) {
    final lots = <Future<void>>[];
    for (var i = 0; i < noms.length; i += kLotSignalements) {
      final fin = i + kLotSignalements < noms.length
          ? i + kLotSignalements
          : noms.length;
      lots.add(_signalerLot(noms.sublist(i, fin)));
    }
    return Future.wait(lots);
  }

  /// Crée ou met à jour `import_unresolved/{empreinte}` de chaque nom de [lot]
  /// par un `set` fusionné : `key` (nom normalisé, dont les règles vérifient
  /// le SHA-256 dans l'identifiant), `count` + 1, `name` à la graphie de ce
  /// fichier. L'empreinte d'un import ne croise jamais un document de
  /// l'ingestion (préfixe `import|`). Un échec est rapporté et rien d'autre
  /// n'est tenté.
  Future<void> _signalerLot(List<NomNonResolu> lot) async {
    final batch = _firestore.batch();
    for (final n in lot) {
      batch.set(
        _firestore.collection(kNonResolus).doc(n.empreinte),
        {
          'nature': n.nature,
          'key': n.cle,
          'name': n.nom,
          'source': 'import',
          'count': FieldValue.increment(1),
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    try {
      await batch.commit();
    } catch (error, stackTrace) {
      // Ni les noms ni le fichier dans le rapport : la taille du lot et les
      // natures.
      _errors.reportError(
        feature: 'library.unresolved',
        error: error,
        stackTrace: stackTrace,
        context:
            '$kNonResolus : lot de ${lot.length} noms '
            '(${{for (final n in lot) n.nature}.join(', ')}) : signalement '
            'impossible',
      );
    }
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
