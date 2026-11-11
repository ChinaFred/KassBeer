import '../../library/domain/referentiel.dart';
import '../../library/presentation/library_providers.dart';
import '../domain/ingestion.dart';

/// Libellés d'Admin › Sources. Une valeur inconnue s'affiche telle quelle.

/// Nature d'ingrédient stockée (`import_unresolved.nature`, clés de
/// `unresolved`) → référentiel de la Bibliothèque.
const _natures = {
  'fermentable': NatureReferentiel.fermentables,
  'hop': NatureReferentiel.hops,
  'culture': NatureReferentiel.cultures,
  'misc': NatureReferentiel.miscs,
};

SegmentBibliotheque? _segmentDe(NatureReferentiel? nature) {
  for (final s in SegmentBibliotheque.values) {
    if (s.nature != null && s.nature == nature) return s;
  }
  return null;
}

/// Collections de l'ingestion, dans l'ordre de l'écran (celui des segments de
/// la Bibliothèque), avec leur nom lisible.
final Map<String, String> _collections = {
  for (final s in SegmentBibliotheque.values)
    s.nature?.collection ?? 'public_recipes': s.label,
  'beer_index': 'Index de la bibliothèque',
  'import_unresolved': 'Noms non reconnus',
};

/// « Malts et sucres » pour `beer_fermentables`.
String libelleCollection(String collection) =>
    _collections[collection] ?? collection;

/// « Houblons » pour `hop` : libellé du segment de la Bibliothèque.
String libelleNatures(String nature) =>
    _segmentDe(_natures[nature])?.label ?? nature;

/// « Houblon » pour `hop` : titre de la fiche de la Bibliothèque.
String libelleNature(String nature) =>
    _segmentDe(_natures[nature])?.titreFiche ?? nature;

/// Cible d'une exécution.
String libelleCible(String target) => switch (target) {
  'production' => 'Production',
  'emulator' => 'Émulateur',
  _ => target,
};

/// Origine d'un nom non reconnu.
String libelleOrigine(String source) => switch (source) {
  'diydog' => 'recettes DIY Dog',
  'import' => 'import d\'un membre',
  _ => source,
};

/// Source d'une exécution : « Brewtarget, fichier 001 », « DIY Dog ».
String libelleSourceExecution(String source) {
  final fichier = RegExp(r'^brewtarget-(\d{3})$').firstMatch(source);
  if (fichier != null) return 'Brewtarget, fichier ${fichier.group(1)}';
  if (source == 'diydog') return 'DIY Dog';
  return source;
}

/// Comptes d'une collection : « 412 écrits · 3 inchangés · 0 refusé ».
String ligneComptes(ComptesCollection c) => [
  _accord(c.written, 'écrit'),
  _accord(c.unchanged, 'inchangé'),
  _accord(c.refused, 'refusé'),
].join(' · ');

/// « 1 nom », « 12 noms ».
String libelleNoms(int count) => _accord(count, 'nom');

/// « 1 fois », « 12 fois ».
String libelleFois(int count) => '$count fois';

String _accord(int n, String mot) => n <= 1 ? '$n $mot' : '$n ${mot}s';

/// Comptes dans l'ordre de l'écran ; une collection inconnue vient après, par
/// ordre alphabétique.
List<ComptesCollection> comptesOrdonnes(List<ComptesCollection> counts) =>
    _ordonner(counts, (c) => c.collection, _collections.keys.toList());

/// Non-résolus dans l'ordre des natures ; une nature inconnue vient après.
List<NonResolusNature> nonResolusOrdonnes(List<NonResolusNature> unresolved) =>
    _ordonner(unresolved, (n) => n.nature, _natures.keys.toList());

List<T> _ordonner<T>(
  List<T> items,
  String Function(T) cle,
  List<String> ordre,
) {
  int rang(T item) {
    final i = ordre.indexOf(cle(item));
    return i < 0 ? ordre.length : i;
  }

  return [...items]..sort((a, b) {
    final r = rang(a).compareTo(rang(b));
    return r != 0 ? r : cle(a).compareTo(cle(b));
  });
}
