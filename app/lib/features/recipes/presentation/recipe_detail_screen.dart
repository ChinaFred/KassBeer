import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_document.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../costs/presentation/bloc_cout.dart';
import '../../equipment/presentation/equipment_providers.dart';
import '../domain/chronologie.dart';
import '../domain/recipe.dart';
import '../../brews/presentation/new_brew_form.dart';
import 'contenu_recette.dart';
import 'recipe_calculations_view.dart';
import 'recipes_providers.dart';

/// Textes des états de la fiche et de l'éditeur d'une recette (R10).
const textesRecette = TextesDocument(
  chargement: 'Chargement de la recette',
  lectureImpossible: 'Impossible de lire les recettes.',
  absent: 'Cette recette n\'existe pas ou a été supprimée.',
  horsLigne: 'Recette indisponible hors ligne.',
  illisible:
      'Cette recette est illisible : une valeur enregistrée est inattendue.',
  retour: 'Revenir aux recettes',
);

/// Fiche d'une recette : calculs, ingrédients, paliers, notes.
class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.id});

  final String id;

  static const saved = 'Recette enregistrée.';
  static const savedOffline =
      'Recette enregistrée sur l\'appareil. Elle partira au retour du réseau.';
  static String saveRejected(String name) =>
      'L\'enregistrement de « $name » a échoué.';
  static const duplicated = 'Recette dupliquée.';
  static const duplicatedOffline =
      'Recette dupliquée sur l\'appareil. Elle partira au retour du réseau.';
  static String duplicateRejected(String name) =>
      'La duplication de « $name » a échoué.';
  static String deleteTitle(String name) => 'Supprimer « $name » ?';
  static const deleteMessage = 'La recette disparaît pour tout le groupe.';
  static const deleted = 'Recette supprimée.';
  static String deleteRejected(String name) =>
      'La suppression de « $name » a échoué.';

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  /// Une duplication attend le nom du jeton : le bouton attend aussi, pour qu'un
  /// double appui ne crée pas deux copies.
  bool _duplicating = false;

  Future<void> _duplicate(Recipe recipe) async {
    if (_duplicating) return;
    final access = ref.read(grantedAccessProvider);
    if (access == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _duplicating = true);
    final ownerName = await ref.read(authRepositoryProvider).currentTokenName();
    // L'écran a pu être quitté pendant l'attente : `ref` n'est plus utilisable.
    if (!mounted) return;
    final created = ref
        .read(recipesRepositoryProvider)
        .duplicate(
          source: recipe,
          ownerUid: access.user.uid,
          ownerName: ownerName,
        );
    suivreEcriture(
      messenger: messenger,
      written: created.written,
      succes: access.offline
          ? RecipeDetailScreen.duplicatedOffline
          : RecipeDetailScreen.duplicated,
      refus: RecipeDetailScreen.duplicateRejected(recipe.name),
    );
    setState(() => _duplicating = false);
    context.go(AppRoutes.recipe(created.id));
  }

  Future<void> _delete(Recipe recipe) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmerSuppression(
      context,
      titre: RecipeDetailScreen.deleteTitle(recipe.name),
      paragraphes: const [RecipeDetailScreen.deleteMessage],
    );
    if (!confirmed || !mounted) return;
    final write = ref.read(recipesRepositoryProvider).delete(recipe.id);
    suivreEcriture(
      messenger: messenger,
      written: write,
      succes: RecipeDetailScreen.deleted,
      refus: RecipeDetailScreen.deleteRejected(recipe.name),
    );
    context.go(AppRoutes.recipes);
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(grantedAccessProvider);
    final equipmentAsync = ref.watch(equipmentListProvider);
    return PageDocument<Recipe>(
      async: ref.watch(recipesListProvider),
      id: widget.id,
      offline: access?.offline ?? false,
      textes: textesRecette,
      onRetry: () => ref.invalidate(recipesListProvider),
      onBack: () => context.go(AppRoutes.recipes),
      builder: (context, recipe) {
        final equipement = equipementDe(
          recipe.content.equipmentId,
          equipmentAsync,
          offline: access?.offline ?? false,
        );
        final mine = recipe.ownerUid == access?.user.uid;
        void edit() => context.push(AppRoutes.editRecipe(recipe.id));
        return _Fiche(
          onNewBrew: () => ouvrirNouveauBrassin(context, recipe),
          onEditSteps: () => context.push(AppRoutes.editBrewSteps(recipe.id)),
          recipe: recipe,
          readerUid: access?.user.uid,
          equipement: equipement,
          calculs: evaluerRecette(
            recipe.content,
            equipement,
            errors: ref.read(errorReportServiceProvider),
            reported: ref.read(calculationReportsProvider),
            recipeKey: recipe.id,
          ),
          onEdit: mine ? edit : null,
          onDelete: mine ? () => _delete(recipe) : null,
          onDuplicate: () => _duplicate(recipe),
          duplicating: _duplicating,
        );
      },
    );
  }
}

class _Fiche extends StatelessWidget {
  const _Fiche({
    required this.onNewBrew,
    required this.onEditSteps,
    required this.recipe,
    required this.readerUid,
    required this.equipement,
    required this.calculs,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.duplicating,
  });

  final Recipe recipe;
  final String? readerUid;
  final EquipementRecette equipement;
  final CalculsRecette calculs;
  final VoidCallback onNewBrew;
  final VoidCallback onEditSteps;

  /// `null` pour un autre brasseur (lecture seule).
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onDuplicate;

  /// Duplication en cours : le bouton attend.
  final bool duplicating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = recipe.content;
    final edit = onEdit;
    final delete = onDelete;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final volume = c.batchVolumeL;
    final boil = c.boilTimeMin;
    final hopIbu = <int, double>{
      if (calculs case CalculsObtenus(:final calculation))
        for (final h in calculation.hopBitterness) h.hop.index: h.ibu,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Semantics(
          header: true,
          child: Text(c.name, style: theme.textTheme.headlineSmall),
        ),
        if (c.style != null) Text(c.style!, style: muted),
        if (edit == null)
          Text(
            'Recette de ${libelleAuteur(ownerUid: recipe.ownerUid, ownerName: recipe.ownerName, readerUid: readerUid)}',
            style: muted,
          ),
        if (recipe.hasPendingWrites) ...[
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Etiquette(label: 'En attente du réseau'),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onNewBrew,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Nouveau brassin'),
            ),
            if (edit != null)
              FilledButton.tonalIcon(
                onPressed: edit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Modifier'),
              ),
            if (duplicating)
              const OutlinedButton(
                onPressed: null,
                child: IndicateurBouton(label: 'Duplication'),
              )
            else
              OutlinedButton.icon(
                onPressed: onDuplicate,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Dupliquer'),
              ),
            if (delete != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Supprimer'),
              ),
          ],
        ),
        const TitreSection('Calculs'),
        BlocCalculs(
          calculs: calculs,
          content: c,
          equipement: equipement,
          onComplete: edit,
        ),
        // « Coût avec vos prix » : avec les prix du lecteur, auteur ou non
        // (CR7). Le bloc porte son titre.
        BlocCoutRecette(recipe: recipe, onCompleter: edit),
        const TitreSection('Général'),
        LigneFiche(
          label: 'Volume en fermenteur',
          value: volume == null ? null : formatLitres(volume),
        ),
        LigneFiche(
          label: 'Durée d\'ébullition',
          value: boil == null ? null : formatMinutes(boil),
        ),
        LigneFiche(label: 'Équipement', value: libelleEquipement(equipement)),
        ContenuRecette(
          content: c,
          hopIbu: hopIbu,
          chronologie: _Chronologie(
            content: c,
            onEdit: edit == null ? null : onEditSteps,
          ),
        ),
      ],
    );
  }
}

/// Section « Chronologie du jour » de la fiche : lecture, et bouton de l'auteur.
class _Chronologie extends StatelessWidget {
  const _Chronologie({required this.content, required this.onEdit});

  final RecipeContent content;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final edit = onEdit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TitreSection(
          'Chronologie du jour',
          trailing: content.brewSteps.isEmpty
              ? null
              : '${formatEtapes(content.brewSteps.length)} · ${formatDuree(dureeChronologie(content.brewSteps))}',
        ),
        if (content.brewStepsProblem != null)
          const TexteAbsent('Chronologie illisible')
        else if (content.brewSteps.isEmpty)
          const TexteAbsent('Aucune étape.')
        else
          ...listeEtapes(content.brewSteps),
        if (edit != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: edit,
              icon: const Icon(Icons.schedule),
              label: const Text('Modifier la chronologie'),
            ),
          ),
      ],
    );
  }
}
