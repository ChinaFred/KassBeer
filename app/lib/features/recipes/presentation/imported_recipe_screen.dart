import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/page_secondaire.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import 'recipe_detail_screen.dart';

/// Fiche d'une recette ouverte depuis le compte rendu de Recettes › Importer
/// (ticket #60) : page pleine hors de la coquille, ouverte par `push`.
///
/// La fiche de la coquille (`/recettes/:id`) ne peut pas s'ouvrir par `push`
/// depuis l'import quand la coquille est déjà dans la pile, sous l'import :
/// go_router y ajouterait une seconde page de coquille de même clé. Cette page
/// porte elle-même la barre « Recette », le retour (qui ferme la page et
/// ramène au compte rendu) et le bandeau hors ligne.
class ImportedRecipeScreen extends ConsumerWidget {
  const ImportedRecipeScreen({super.key, required this.id});

  final String id;

  static const titre = 'Recette';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    return PageSecondaire(
      titre: titre,
      horsLigne: offline,
      // Adresse ouverte directement (rechargement sur le web) : la fiche de
      // la coquille.
      repli: AppRoutes.recipe(id),
      // Même borne que la coquille : la fiche ne gère pas ses marges.
      largeurMax: null,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: RecipeDetailScreen(id: id),
        ),
      ),
    );
  }
}
