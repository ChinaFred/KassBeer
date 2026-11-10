import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/services/error_report_service.dart';
import '../domain/chronologie.dart';
import '../domain/recipe.dart';

/// Accès à `recipes/`. Les écrans passent par cette interface ; les tests la
/// remplacent par un double sans Firebase.
abstract class RecipesRepository {
  /// Toutes les recettes du groupe, à chaque changement, avec la provenance de la
  /// lecture. Un document illisible est rapporté et rendu comme tel.
  Stream<ListeLue<Recipe>> watchAll();

  /// Crée une recette de [ownerUid]. L'écriture locale est faite dès l'appel ;
  /// `written` se termine quand le serveur l'a acceptée. [ownerName] : nom du
  /// jeton de l'auteur, `null` s'il n'en a pas (champ absent).
  CreationEnCours create({
    required RecipeContent content,
    required String ownerUid,
    required String? ownerName,
  });

  /// Modifie la recette [id] : `owner_uid` et `created_at` ne sont pas écrits,
  /// `updated_at` est posée par le serveur, `owner_name` est réécrit ou retiré.
  Future<void> update({
    required String id,
    required RecipeContent content,
    required String? ownerName,
  });

  /// Copie [source] au nom de [ownerUid] (R7). La source n'est pas écrite.
  CreationEnCours duplicate({
    required Recipe source,
    required String ownerUid,
    required String? ownerName,
  });

  /// Supprime la recette [id].
  Future<void> delete(String id);

  /// Clé d'une étape nouvelle, créée par l'appareil.
  String newStepKey();

  /// Remplace la chronologie de la recette [id], seul champ écrit avec
  /// `owner_name` et `updated_at`. Lève [ArgumentError] si elle sort des bornes.
  Future<void> updateBrewSteps({
    required String id,
    required List<BrewStepLine> steps,
    required String? ownerName,
  });
}

/// [RecipesRepository] sur Cloud Firestore.
class FirestoreRecipesRepository implements RecipesRepository {
  FirestoreRecipesRepository({
    required ErrorReportService errorReportService,
    FirebaseFirestore? firestore,
  }) : _errors = errorReportService,
       _injectedFirestore = firestore;

  final ErrorReportService _errors;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _recipes =>
      _firestore.collection('recipes');

  @override
  Stream<ListeLue<Recipe>> watchAll() => _recipes
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => ListeLue<Recipe>(
          documents: [
            for (final doc in snapshot.docs)
              _read(doc.id, doc.data(), doc.metadata.hasPendingWrites),
          ],
          fromCache: snapshot.metadata.isFromCache,
        ),
      )
      .handleError((Object error, StackTrace stackTrace) {
        _errors.reportError(
          feature: 'recipes.watch_all',
          error: error,
          stackTrace: stackTrace,
        );
        // Relancée : l'écran affiche la panne.
        Error.throwWithStackTrace(error, stackTrace);
      });

  DocumentLu<Recipe> _read(
    String id,
    Map<String, dynamic> data,
    bool hasPendingWrites,
  ) {
    try {
      final recipe = Recipe.fromFirestore(
        id,
        data,
        hasPendingWrites: hasPendingWrites,
      );
      final problem = recipe.content.brewStepsProblem;
      if (problem != null) _reportBrewSteps(id, problem);
      return DocumentValide(id, recipe);
    } on DocumentIllisible catch (error, stackTrace) {
      // Depuis la v0.1.17, aucune lecture ne passe par brewing/ : un type de malt
      // ou une forme de houblon hors du schéma lève DocumentIllisible.
      return _invalid(id, error, stackTrace);
    }
  }

  void _reportBrewSteps(String id, String problem) => _errors.reportError(
    feature: 'recipes.brew_steps',
    error: DocumentIllisible('brew_steps', problem),
    context: 'recipes/$id : chronologie illisible',
  );

  DocumentLu<Recipe> _invalid(String id, Object error, StackTrace stackTrace) {
    _errors.reportError(
      feature: 'recipes.read',
      error: error,
      stackTrace: stackTrace,
      context: 'recipes/$id illisible',
    );
    return DocumentInvalide(id, error);
  }

  @override
  CreationEnCours create({
    required RecipeContent content,
    required String ownerUid,
    required String? ownerName,
  }) => _create('recipes.create', content, ownerUid, ownerName);

  @override
  CreationEnCours duplicate({
    required Recipe source,
    required String ownerUid,
    required String? ownerName,
  }) => _create(
    'recipes.duplicate',
    source.content.duplicate(),
    ownerUid,
    ownerName,
  );

  CreationEnCours _create(
    String feature,
    RecipeContent content,
    String ownerUid,
    String? ownerName,
  ) {
    final ref = _recipes.doc();
    final written = _guard(
      feature,
      () => ref.set({
        ...content.toFirestore(creation: true),
        'owner_uid': ownerUid,
        ...champFacultatif('owner_name', ownerName, creation: true),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }),
    );
    return (id: ref.id, written: written);
  }

  @override
  Future<void> update({
    required String id,
    required RecipeContent content,
    required String? ownerName,
  }) => _guard(
    'recipes.update',
    () => _recipes.doc(id).update({
      ...content.toFirestore(creation: false),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> delete(String id) =>
      _guard('recipes.delete', () => _recipes.doc(id).delete());

  @override
  String newStepKey() => _recipes.doc().id;

  @override
  Future<void> updateBrewSteps({
    required String id,
    required List<BrewStepLine> steps,
    required String? ownerName,
  }) => _guard('recipes.brew_steps_update', () async {
    final problem = erreurChronologie(steps);
    if (problem != null) throw ArgumentError(problem);
    await _recipes.doc(id).update({
      ...champFacultatif(
        'brew_steps',
        steps.isEmpty ? null : [for (final s in steps) s.toFirestore()],
        creation: false,
      ),
      ...champFacultatif('owner_name', ownerName, creation: false),
      'updated_at': FieldValue.serverTimestamp(),
    });
  });

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
