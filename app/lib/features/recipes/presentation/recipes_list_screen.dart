import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/recipe.dart';
import 'recipes_providers.dart';

/// Recettes du groupe : recherche, filtre « Toutes » / « Les miennes ». Le filtre et
/// la recherche sont un état de l'écran, jamais écrit en base.
class RecipesListScreen extends ConsumerStatefulWidget {
  const RecipesListScreen({super.key});

  static const loadError = 'Impossible de lire les recettes.';
  static const emptyTitle = 'Aucune recette';
  static const mineEmptyTitle = 'Vous n\'avez pas encore de recette';

  /// Message des deux états vides, sous [emptyTitle] ou [mineEmptyTitle].
  static const emptyMessage =
      'Appuyez sur Nouvelle recette pour commencer, ou importez un fichier '
      'BeerXML ou BeerJSON.';
  static String noMatch(String text) =>
      'Aucune recette ne correspond à « $text ».';

  @override
  ConsumerState<RecipesListScreen> createState() => _RecipesListScreenState();
}

class _RecipesListScreenState extends ConsumerState<RecipesListScreen> {
  final _search = TextEditingController();
  bool _mineOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _create() => context.push(AppRoutes.newRecipe);

  void _import() => context.push(AppRoutes.importRecipes);

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(recipesListProvider);
    final readerUid = ref.watch(grantedAccessProvider)?.user.uid;
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    final list = listAsync.value;

    final Widget body = switch (listAsync) {
      AsyncError() when list == null => EtatErreur(
        message: RecipesListScreen.loadError,
        retrying: listAsync.isLoading,
        retryingLabel: 'Lecture en cours',
        onRetry: () => ref.invalidate(recipesListProvider),
      ),
      _ when list == null => const EtatChargement(
        label: 'Chargement des recettes',
      ),
      _ => _content(list, readerUid, compact, listAsync),
    };

    return Scaffold(
      body: body,
      floatingActionButton: compact && list != null
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle recette'),
            )
          : null,
    );
  }

  Widget _content(
    ListeLue<Recipe> list,
    String? readerUid,
    bool compact,
    AsyncValue<ListeLue<Recipe>> async,
  ) {
    final query = _search.text.trim().toLowerCase();
    final all = list.valides..sort(compareRecipes);
    final shown = [
      for (final r in all)
        if ((!_mineOnly || r.ownerUid == readerUid) &&
            (query.isEmpty ||
                r.name.toLowerCase().contains(query) ||
                (r.content.style?.toLowerCase().contains(query) ?? false)))
          r,
    ];
    final invalid = _mineOnly
        ? const <DocumentInvalide<Recipe>>[]
        : list.documents.whereType<DocumentInvalide<Recipe>>().toList();

    Widget? empty;
    if (shown.isEmpty && invalid.isEmpty) {
      if (query.isNotEmpty) {
        empty = EtatVide(
          icon: Icons.search_off,
          message: RecipesListScreen.noMatch(_search.text.trim()),
          action: TextButton(
            onPressed: () => setState(_search.clear),
            child: const Text('Effacer la recherche'),
          ),
        );
      } else {
        empty = EtatVide(
          icon: Icons.menu_book_outlined,
          titre: _mineOnly
              ? RecipesListScreen.mineEmptyTitle
              : RecipesListScreen.emptyTitle,
          message: RecipesListScreen.emptyMessage,
          action: OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Importer des recettes'),
          ),
        );
      }
    }

    return ListView(
      padding: EdgeInsets.only(
        top: 8,
        bottom: compact ? kMargeBoutonFlottant : 24,
      ),
      children: [
        if (async.hasError)
          BandeauListePerimee(
            retrying: async.isLoading,
            onRetry: () => ref.invalidate(recipesListProvider),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!compact) ...[
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle recette'),
                ),
                _BoutonImporter(onPressed: _import),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Rechercher une recette',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Toutes')),
                  ButtonSegment(value: true, label: Text('Les miennes')),
                ],
                selected: {_mineOnly},
                onSelectionChanged: (s) => setState(() => _mineOnly = s.single),
              ),
              // Téléphone : après « Toutes / Les miennes » ; le bouton flottant
              // reste « Nouvelle recette ».
              if (compact) _BoutonImporter(onPressed: _import),
            ],
          ),
        ),
        ?empty,
        for (final r in shown) _Row(recipe: r, readerUid: readerUid),
        for (final d in invalid)
          LigneListe(
            icone: Icons.error_outline,
            erreur: true,
            titre: 'Recette illisible',
            details: const [
              Text(
                'Mettez l\'application à jour, ou prévenez l\'administrateur.',
              ),
            ],
            onTap: () => context.go(AppRoutes.recipe(d.id)),
          ),
      ],
    );
  }
}

/// « Importer » : ouvre Recettes › Importer.
class _BoutonImporter extends StatelessWidget {
  const _BoutonImporter({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.upload_file),
    label: const Text('Importer'),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.recipe, required this.readerUid});

  final Recipe recipe;
  final String? readerUid;

  @override
  Widget build(BuildContext context) {
    final c = recipe.content;
    final volume = c.batchVolumeL;
    final details = [
      ?c.style,
      if (volume != null) formatLitres(volume),
      libelleAuteur(
        ownerUid: recipe.ownerUid,
        ownerName: recipe.ownerName,
        readerUid: readerUid,
      ),
    ].join(' · ');
    return LigneListe(
      icone: Icons.menu_book_outlined,
      titre: c.name,
      details: [Text(details)],
      etiquettes: [
        if (recipe.hasPendingWrites)
          const Etiquette(label: 'En attente du réseau'),
      ],
      onTap: () => context.go(AppRoutes.recipe(recipe.id)),
    );
  }
}
