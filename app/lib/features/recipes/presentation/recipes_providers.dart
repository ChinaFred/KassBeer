import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../domain/recipe.dart';

/// Recettes du groupe, lues par tous les membres.
final recipesListProvider = StreamProvider.autoDispose<ListeLue<Recipe>>(
  (ref) => ref.watch(recipesRepositoryProvider).watchAll(),
  // Une panne s'affiche ; « Réessayer » relance la lecture.
  retry: (retryCount, error) => null,
);

/// Calculs refusés par `brewing/` déjà rapportés, par recette et par champ
/// (`evaluerRecette`) : un rapport par session, pas un par frappe ni par lecture.
final calculationReportsProvider = Provider<Set<String>>((ref) => <String>{});
