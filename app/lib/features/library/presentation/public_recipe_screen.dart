import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/ecriture.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../recipes/domain/beerjson.dart';
import '../../recipes/presentation/contenu_recette.dart';
import '../../recipes/presentation/recipe_calculations_view.dart';
import '../../recipes/presentation/recipes_providers.dart';
import '../domain/recette_publique.dart';
import 'libelles_bibliotheque.dart';
import 'library_providers.dart';
import 'reference_entry_screen.dart';

/// Fiche d'une recette publique : valeurs annoncées par la source, calculs par
/// `brewing/` quand c'est possible, ingrédients, paliers, moments d'origine,
/// provenance. « Dupliquer » la copie dans les recettes du lecteur et ouvre
/// l'éditeur.
class PublicRecipeScreen extends ConsumerStatefulWidget {
  const PublicRecipeScreen({super.key, required this.id});

  final String id;

  // Mêmes mots que la fiche d'une recette (`RecipeDetailScreen`).
  static const duplicated = 'Recette dupliquée dans vos recettes.';
  static const duplicatedOffline =
      'Recette dupliquée sur l\'appareil. Elle partira au retour du réseau.';
  static String duplicateRejected(String name) =>
      'La duplication de « $name » a échoué.';
  static const announcedTitle = 'Annoncé par la source';
  static const announcedNote =
      'Valeurs données par la recette d\'origine. Kass\'Beer ne les a pas '
      'calculées.';

  /// Remplace la liste « À compléter » : la fiche est en lecture seule.
  static const missingNote =
      'Ces valeurs manquent à la recette d\'origine (équipement, durées, '
      'forme des houblons) : dupliquez-la pour les compléter.';

  @override
  ConsumerState<PublicRecipeScreen> createState() => _PublicRecipeScreenState();
}

class _PublicRecipeScreenState extends ConsumerState<PublicRecipeScreen> {
  /// La duplication attend le nom du jeton : le bouton attend aussi, pour qu'un
  /// double appui ne crée pas deux copies.
  bool _duplicating = false;

  Future<void> _duplicate(RecettePublique recette) async {
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
        .create(
          content: recette.copie,
          ownerUid: access.user.uid,
          ownerName: ownerName,
        );
    suivreEcriture(
      messenger: messenger,
      written: created.written,
      succes: access.offline
          ? PublicRecipeScreen.duplicatedOffline
          : PublicRecipeScreen.duplicated,
      refus: PublicRecipeScreen.duplicateRejected(recette.name),
    );
    setState(() => _duplicating = false);
    unawaited(context.push(AppRoutes.editRecipe(created.id)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recettePubliqueProvider(widget.id));
    final etat = etatFiche(
      async: async,
      offline: ref.watch(grantedAccessProvider)?.offline ?? false,
      onRetry: () => ref.invalidate(recettePubliqueProvider(widget.id)),
      onBack: () => context.go(
        AppRoutes.librarySegment(SegmentBibliotheque.recettes.slug),
      ),
      retour: 'Revenir aux recettes publiques',
    );
    if (etat != null) return etat;
    final recette = (async.value! as DocumentTrouve<RecettePublique>).value;
    final calculs = evaluerRecette(
      recette.content,
      const SansEquipement(),
      errors: ref.read(errorReportServiceProvider),
      reported: ref.read(calculationReportsProvider),
      recipeKey: 'public_recipes/${recette.id}',
    );
    return _Fiche(
      recette: recette,
      calculs: calculs,
      duplicating: _duplicating,
      onDuplicate: () => _duplicate(recette),
    );
  }
}

class _Fiche extends StatelessWidget {
  const _Fiche({
    required this.recette,
    required this.calculs,
    required this.duplicating,
    required this.onDuplicate,
  });

  final RecettePublique recette;
  final CalculsRecette calculs;
  final bool duplicating;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = recette.content;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final volume = c.batchVolumeL;
    final boil = c.boilTimeMin;
    final hopIbu = <int, double>{
      if (calculs case CalculsObtenus(:final calculation))
        for (final h in calculation.hopBitterness) h.hop.index: h.ibu,
    };
    final a = recette.annonce;
    final source = recette.ownerName;
    final styleId = recette.styleId;
    // Material transparent : « Détail des calculs » (ExpansionTile) garde son
    // encre quand une fiche s'ouvre par-dessus dans la coquille.
    final liste = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Semantics(
          header: true,
          child: Text(c.name, style: theme.textTheme.headlineSmall),
        ),
        if (c.style != null) Text(c.style!, style: muted),
        if (source != null) Text('Recette publique · $source', style: muted),
        // Style résolu par l'ingestion : sa fiche donne les plages du style.
        if (styleId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(
                context.push(
                  AppRoutes.libraryEntry(
                    SegmentBibliotheque.styles.slug,
                    styleId,
                  ),
                ),
              ),
              icon: const Icon(Icons.style_outlined),
              label: const Text('Voir le style'),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: duplicating
              ? const FilledButton(
                  onPressed: null,
                  child: IndicateurBouton(label: 'Duplication'),
                )
              : FilledButton.icon(
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Dupliquer'),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          'Dupliquer copie la recette dans vos recettes, pour la modifier et '
          'la brasser.',
          style: muted,
        ),
        const TitreSection(PublicRecipeScreen.announcedTitle),
        if (a.vide)
          const TexteAbsent('Aucune valeur annoncée.')
        else ...[
          Text(PublicRecipeScreen.announcedNote, style: muted),
          if (a.originalGravity != null)
            LigneFiche(
              label: 'Densité initiale',
              value: formatDensite(a.originalGravity!),
            ),
          if (a.finalGravity != null)
            LigneFiche(
              label: 'Densité finale',
              value: formatDensite(a.finalGravity!),
            ),
          if (a.alcoholByVolume != null)
            LigneFiche(label: 'Degré', value: formatDegre(a.alcoholByVolume!)),
          if (a.ibu != null)
            LigneFiche(label: 'Amertume', value: formatIbu(a.ibu!)),
          if (a.colorEbc != null)
            LigneFiche(label: 'Couleur', value: formatEbc(a.colorEbc!)),
        ],
        const TitreSection('Calculs'),
        BlocCalculs(
          calculs: calculs,
          content: c,
          equipement: const SansEquipement(),
          messageManques: PublicRecipeScreen.missingNote,
        ),
        const TitreSection('Général'),
        LigneFiche(
          label: 'Type de recette',
          value: c.type == null ? null : typesRecette.libelle(c.type!),
        ),
        LigneFiche(label: 'Auteur', value: c.author),
        LigneFiche(
          label: 'Volume en fermenteur',
          value: volume == null ? null : formatLitres(volume),
        ),
        LigneFiche(
          label: 'Durée d\'ébullition',
          value: boil == null ? null : formatMinutes(boil),
        ),
        ContenuRecette(
          content: c,
          hopIbu: hopIbu,
          momentsOrigine: {
            for (final MapEntry(:key, :value) in recette.momentsOrigine.entries)
              key: libelleMomentOrigine(value),
          },
        ),
        SectionProvenance(provenance: recette.provenance),
      ],
    );
    return Material(type: MaterialType.transparency, child: liste);
  }
}
