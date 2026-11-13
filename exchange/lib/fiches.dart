/// Fiches Excel préparées pour Admin › Import de Kass'Beer (v0.6), en Dart
/// pur : lecture typée et bornée du format `kassbeer_fiches` v1.
///
/// Les recettes du fichier sont lues par `analyserFichier`, comme dans
/// Recettes › Importer ; le reste (chronologie, mesures, relevés,
/// embouteillage, prix et frais des fiches, écarts) par [lireFichierFiches].
/// Bibliothèque distincte de `exchange.dart` : seuls Admin › Import et
/// `bin/verifier_fiches.dart` la lisent, et eux seuls lisent des prix (P9).
/// Elle ne fait aucun `catch`, n'écrit rien et ne lit rien de Firestore.
library;

export 'src/fiches/lecture.dart';
export 'src/fiches/modele.dart';
