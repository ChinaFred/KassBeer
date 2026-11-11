import '../../../core/data/lecture_document.dart';

/// Comptes d'une collection dans une exécution de l'ingestion (`counts`).
class ComptesCollection {
  const ComptesCollection({
    required this.collection,
    required this.written,
    required this.unchanged,
    required this.refused,
  });

  /// Nom de la collection (`beer_hops`, `public_recipes`…).
  final String collection;
  final int written;
  final int unchanged;
  final int refused;
}

/// Source lue par une exécution (`sources[]`).
class SourceExecution {
  const SourceExecution({required this.source, required this.version});

  /// `brewtarget-001` à `brewtarget-005`, `diydog`.
  final String source;

  /// `v5.2.3 ea10908`, `e6c12ab`.
  final String version;
}

/// Noms non résolus d'une nature (`unresolved`).
class NonResolusNature {
  const NonResolusNature({required this.nature, required this.count});

  /// `fermentable`, `hop`, `culture`, `misc`.
  final String nature;
  final int count;
}

/// Compte rendu d'une exécution de l'écrivain, `ingest_runs/{id}` (ADR-005).
/// Écrit par `ingest/lib/execution.mjs`, lu par l'admin. Lecture tolérante : un
/// champ inconnu est ignoré ; un champ lu absent ou mal typé lève
/// [DocumentIllisible].
class ExecutionIngestion {
  const ExecutionIngestion({
    required this.id,
    required this.finishedAt,
    required this.target,
    required this.counts,
    required this.sources,
    required this.unresolved,
  });

  /// Horodatage ISO compact (`20261111T124912Z`), nom du rapport local.
  final String id;
  final DateTime finishedAt;

  /// `emulator` ou `production`.
  final String target;

  /// Une entrée par collection, dans l'ordre des clés du document.
  final List<ComptesCollection> counts;
  final List<SourceExecution> sources;
  final List<NonResolusNature> unresolved;

  factory ExecutionIngestion.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final l = LecteurChamps(data);
    final finishedAt =
        l.date('finished_at') ??
        (throw const DocumentIllisible(
          'finished_at',
          'date obligatoire absente',
        ));
    final counts = l.objet('counts');
    if (data['sources'] is! List) {
      throw const DocumentIllisible('sources', 'liste obligatoire absente');
    }
    final unresolved = l.objet('unresolved');
    return ExecutionIngestion(
      id: id,
      finishedAt: finishedAt,
      target: l.texte('target'),
      counts: [
        for (final collection in counts.data.keys)
          _comptes(collection, counts.objet(collection)),
      ],
      sources: [
        for (final s in l.liste('sources'))
          SourceExecution(
            source: s.texte('source'),
            version: s.texte('version'),
          ),
      ],
      unresolved: [
        for (final nature in unresolved.data.keys)
          NonResolusNature(nature: nature, count: entier(unresolved, nature)),
      ],
    );
  }

  static ComptesCollection _comptes(String collection, LecteurChamps c) =>
      ComptesCollection(
        collection: collection,
        written: entier(c, 'written'),
        unchanged: entier(c, 'unchanged'),
        refused: entier(c, 'refused'),
      );
}

/// Nom d'ingrédient que l'ingestion ou un import n'a pas rattaché au
/// référentiel, `import_unresolved/{empreinte}` (ADR-005, D6).
class IngredientNonResolu {
  const IngredientNonResolu({
    required this.id,
    required this.nature,
    required this.name,
    required this.source,
    required this.count,
    required this.updatedAt,
  });

  /// SHA-256 de `nature|nom normalisé`.
  final String id;

  /// `fermentable`, `hop`, `culture`, `misc`.
  final String nature;

  /// Nom tel que la source l'écrit.
  final String name;

  /// `diydog` (écrit par l'ingestion) ou `import` (import d'un membre).
  final String source;

  /// Nombre de fois où le nom a été rencontré.
  final int count;

  /// Dernière écriture ; `null` tant qu'une écriture locale attend le serveur.
  final DateTime? updatedAt;

  factory IngredientNonResolu.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final l = LecteurChamps(data);
    return IngredientNonResolu(
      id: id,
      nature: l.texte('nature'),
      name: l.texte('name'),
      source: l.texte('source'),
      count: entier(l, 'count'),
      updatedAt: l.date('updated_at'),
    );
  }
}

/// Entier positif ou nul obligatoire. Firestore peut rendre un entier écrit par
/// l'Admin SDK sous la forme d'un `double` entier : il est accepté.
int entier(LecteurChamps l, String key) {
  final value = l.data[key];
  if (value is num && value.isFinite && value >= 0 && value == value.floor()) {
    return value.toInt();
  }
  throw DocumentIllisible('${l.prefix}$key', 'entier positif ou nul attendu');
}
