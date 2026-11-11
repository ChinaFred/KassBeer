/// Préparation de l'ingestion des référentiels et des recettes publiques de
/// Kass'Beer (ADR-005, D5), en Dart pur : lecture des fichiers DefaultContent
/// 001 à 005 de Brewtarget et des recettes DIY Dog, fusion, résolution des
/// noms, documents et rapport. Bibliothèque distincte de `exchange.dart` :
/// l'application ne l'importe jamais. Elle ne fait aucun `catch` et aucun
/// appel réseau.
library;

export 'src/ingestion/alias.dart';
export 'src/ingestion/cles.dart';
export 'src/ingestion/diydog.dart';
export 'src/ingestion/json_commentaires.dart';
export 'src/ingestion/lecture_sources.dart';
export 'src/ingestion/preparation.dart';
export 'src/ingestion/referentiel.dart';
export 'src/ingestion/resolution.dart';
export 'src/ingestion/sources.dart';
export 'src/ingestion/valeurs.dart';
