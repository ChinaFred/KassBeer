/// Échange de recettes de Kass'Beer, en Dart pur (ADR-005).
///
/// Import : [analyserFichier] détecte le format par le contenu, lit chaque
/// recette BeerJSON vers le sous-arbre `recipe` en BeerJSON partiel et rend le
/// compte rendu (recette lue, refusée, modifiée, en double). Export :
/// [exporterBeerJson] écrit le fichier d'une recette, ou la liste de ce qui
/// manque. Le paquet ne fait aucun `catch` et ne lit aucun prix ni stock.
library;

export 'src/analyse.dart';
export 'src/bornes.dart';
export 'src/compte_rendu.dart';
export 'src/ecriture_beerjson.dart';
export 'src/empreinte.dart';
export 'src/lecture_beerjson.dart' show kNomEmpatage;
