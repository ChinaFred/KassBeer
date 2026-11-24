import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/bandeau_liste_perimee.dart';
import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/feuille_ou_dialogue.dart';
import '../../../core/presentation/ligne_liste.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../library/presentation/couleur_ebc.dart';
import '../domain/filtres_recettes.dart';
import '../domain/recipe.dart';
import 'apercu_recette.dart';
import 'boite_filtres_recettes.dart';
import 'recipes_providers.dart';

/// Recettes du groupe : recherche, origine (« Toutes », « Les miennes »,
/// « Autres ») et filtres (styles, degré, couleur, arômes). Recherche, origine
/// et filtres sont un état de l'écran, jamais écrit en base.
class RecipesListScreen extends ConsumerStatefulWidget {
  const RecipesListScreen({super.key});

  static const loadError = 'Impossible de lire les recettes.';
  static const emptyTitle = 'Aucune recette';
  static const mineEmptyTitle = 'Vous n\'avez pas encore de recette';
  static const othersEmpty = 'Aucune recette d\'un autre membre';

  /// Message des deux états vides, sous [emptyTitle] ou [mineEmptyTitle].
  static const emptyMessage =
      'Appuyez sur Nouvelle recette pour commencer, ou importez un fichier '
      'BeerXML ou BeerJSON.';
  static String noMatch(String text) =>
      'Aucune recette ne correspond à « $text ».';
  static const noFilterMatch = 'Aucune recette ne correspond à ces filtres.';
  static String noFilterMatchWith(String text) =>
      'Aucune recette ne correspond à « $text » avec ces filtres.';
  static const calculImpossible = 'Calcul impossible';
  static String illisiblesFiltrees(int n) => n == 1
      ? '1 recette illisible ne s\'affiche pas avec ces filtres.'
      : '$n recettes illisibles ne s\'affichent pas avec ces filtres.';

  @override
  ConsumerState<RecipesListScreen> createState() => _RecipesListScreenState();
}

class _RecipesListScreenState extends ConsumerState<RecipesListScreen> {
  final _search = TextEditingController();

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

  void _effacerFiltres() => ref
      .read(filtresRecettesProvider.notifier)
      .appliquer(FiltresRecettes.vide);

  bool _accepte(
    FiltresRecettes filtres,
    Recipe r,
    Map<String, ApercuRecette> apercus,
  ) => filtres.accepte(
    style: r.content.style,
    degre: apercus[r.id]?.degre,
    ebc: apercus[r.id]?.ebc,
    description: r.content.aromaDescription,
  );

  /// Bornes des curseurs pour [valeurs] : celles de la boîte ([curseurDe]),
  /// ou les valeurs elles-mêmes quand elles sont toutes égales.
  static Intervalle? _bornesCurseur(List<double?> valeurs, double pas) {
    final bornes = bornesDe(valeurs);
    return curseurDe(bornes, pas)?.bornes ?? bornes;
  }

  /// [filtres] ramenés dans les bornes des recettes [origine] : la boîte et
  /// les puces montrent la même plage, et une plage qui couvre toutes les
  /// bornes ne filtre plus.
  static FiltresRecettes _dansLOrigine(
    FiltresRecettes filtres,
    List<Recipe> origine,
    Map<String, ApercuRecette> apercus,
  ) => filtres.dansLesBornes(
    degres: _bornesCurseur([
      for (final r in origine) apercus[r.id]?.degre,
    ], 0.1),
    couleurs: _bornesCurseur([for (final r in origine) apercus[r.id]?.ebc], 1),
  );

  /// Change d'origine et ramène les plages filtrées dans ses bornes.
  void _choisirOrigine(
    OrigineRecettes origine,
    List<Recipe> all,
    String? readerUid,
    Map<String, ApercuRecette> apercus,
  ) {
    ref.read(origineRecettesProvider.notifier).choisir(origine);
    final notifier = ref.read(filtresRecettesProvider.notifier);
    notifier.appliquer(
      _dansLOrigine(ref.read(filtresRecettesProvider), [
        for (final r in all)
          if (origine.contient(r.ownerUid, readerUid)) r,
      ], apercus),
    );
  }

  Future<void> _ouvrirFiltres({
    required FiltresRecettes filtres,
    required List<Recipe> origine,
    required List<Recipe> cherchees,
    required Map<String, ApercuRecette> apercus,
  }) async {
    // ticket: /recettes/fenetre/filtres
    final choisis = await showFeuilleOuDialogueAPied<FiltresRecettes>(
      context: context,
      builder: (_) => BoiteFiltresRecettes(
        initial: filtres,
        styles: stylesComptes([for (final r in origine) r.content.style]),
        degres: [for (final r in origine) apercus[r.id]?.degre],
        couleurs: [for (final r in origine) apercus[r.id]?.ebc],
        compter: (f) => cherchees.where((r) => _accepte(f, r, apercus)).length,
      ),
    );
    if (choisis == null || !mounted) return;
    ref.read(filtresRecettesProvider.notifier).appliquer(choisis);
  }

  Widget _content(
    ListeLue<Recipe> list,
    String? readerUid,
    bool compact,
    AsyncValue<ListeLue<Recipe>> async,
  ) {
    final origine = ref.watch(origineRecettesProvider);
    final apercus = ref.watch(apercusRecettesProvider);
    final large =
        MediaQuery.sizeOf(context).width >= kExpandedMinWidth &&
        MediaQuery.textScalerOf(context).scale(1) < kGrandTexteMinScale;
    final query = _search.text.trim().toLowerCase();
    final all = list.valides..sort(compareRecipes);
    final deLOrigine = [
      for (final r in all)
        if (origine.contient(r.ownerUid, readerUid)) r,
    ];
    final filtres = _dansLOrigine(
      ref.watch(filtresRecettesProvider),
      deLOrigine,
      apercus,
    );
    final cherchees = [
      for (final r in deLOrigine)
        if (correspondRecherche(query, r.name, r.content.style)) r,
    ];
    final shown = [
      for (final r in cherchees)
        if (_accepte(filtres, r, apercus)) r,
    ];
    // Une recette illisible ne passe aucun filtre : elle sort dès qu'un filtre
    // est actif.
    final invalid = origine.montreIllisibles && !filtres.actifs
        ? list.documents.whereType<DocumentInvalide<Recipe>>().toList()
        : const <DocumentInvalide<Recipe>>[];
    final invalidesDeLOrigine = origine.montreIllisibles
        ? list.documents.whereType<DocumentInvalide<Recipe>>().length
        : 0;

    Widget? empty;
    if (deLOrigine.isEmpty && invalidesDeLOrigine == 0) {
      empty = switch (origine) {
        OrigineRecettes.autres => const EtatVide(
          icon: Icons.menu_book_outlined,
          message: RecipesListScreen.othersEmpty,
        ),
        _ => EtatVide(
          icon: Icons.menu_book_outlined,
          titre: origine == OrigineRecettes.miennes
              ? RecipesListScreen.mineEmptyTitle
              : RecipesListScreen.emptyTitle,
          message: RecipesListScreen.emptyMessage,
          action: OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Importer des recettes'),
          ),
        ),
      };
    } else if (shown.isEmpty && invalid.isEmpty) {
      if (filtres.actifs) {
        empty = EtatVide(
          icon: Icons.filter_alt_off,
          message: query.isEmpty
              ? RecipesListScreen.noFilterMatch
              : RecipesListScreen.noFilterMatchWith(_search.text.trim()),
          action: TextButton(
            onPressed: _effacerFiltres,
            child: const Text(TextesFiltresRecettes.effacer),
          ),
        );
      } else if (query.isNotEmpty) {
        empty = EtatVide(
          icon: Icons.search_off,
          message: RecipesListScreen.noMatch(_search.text.trim()),
          action: TextButton(
            onPressed: () => setState(_search.clear),
            child: const Text('Effacer la recherche'),
          ),
        );
      }
    }

    // Libellés des styles retenus, tirés de toutes les recettes : un filtre
    // garde ses styles d'une origine à l'autre.
    final libellesStyles = {
      for (final s in stylesComptes([for (final r in all) r.content.style]))
        s.cle: s.libelle ?? TextesFiltresRecettes.sansStyle,
    };
    final actifs = filtres.groupesActifs;

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
        // Recherche sur toute la largeur, puis l'origine, puis les actions.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Rechercher une recette',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Semantics(
                button: true,
                label: TextesFiltresRecettes.boutonLu(actifs),
                excludeSemantics: true,
                onTap: () => _ouvrirFiltres(
                  filtres: filtres,
                  origine: deLOrigine,
                  cherchees: cherchees,
                  apercus: apercus,
                ),
                child: IconButton(
                  tooltip: TextesFiltresRecettes.titre,
                  onPressed: () => _ouvrirFiltres(
                    filtres: filtres,
                    origine: deLOrigine,
                    cherchees: cherchees,
                    apercus: apercus,
                  ),
                  icon: Badge(
                    isLabelVisible: actifs > 0,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    textColor: Theme.of(context).colorScheme.onPrimary,
                    label: Text('$actifs'),
                    child: const Icon(Icons.filter_list),
                  ),
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final o in OrigineRecettes.values)
                ChoiceChip(
                  label: Text(o.label),
                  selected: o == origine,
                  onSelected: (_) =>
                      _choisirOrigine(o, all, readerUid, apercus),
                ),
              // Téléphone : le bouton flottant reste « Nouvelle recette ».
              if (!compact)
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add),
                  label: const Text('Nouvelle recette'),
                ),
              _BoutonImporter(onPressed: _import),
            ],
          ),
        ),
        if (filtres.actifs)
          _FiltresActifs(
            filtres: filtres,
            libellesStyles: libellesStyles,
            onChanged: (f) =>
                ref.read(filtresRecettesProvider.notifier).appliquer(f),
            onEffacer: _effacerFiltres,
          ),
        ?empty,
        for (final r in shown)
          _Row(
            recipe: r,
            readerUid: readerUid,
            apercu: apercus[r.id],
            auteur: origine != OrigineRecettes.miennes,
            large: large,
          ),
        for (final d in invalid)
          LigneListe(
            icone: Icons.error_outline,
            erreur: true,
            titre: 'Recette illisible',
            details: const [Text(kDetailLigneIllisible)],
            onTap: () => context.go(AppRoutes.recipe(d.id)),
          ),
        // Les recettes illisibles écartées par les filtres sont comptées.
        if (filtres.actifs && invalidesDeLOrigine > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Text(
              RecipesListScreen.illisiblesFiltrees(invalidesDeLOrigine),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Filtres actifs sous l'origine : une puce supprimable par style, par plage
/// et par mot d'arôme, puis
/// « Effacer les filtres ».
class _FiltresActifs extends StatelessWidget {
  const _FiltresActifs({
    required this.filtres,
    required this.libellesStyles,
    required this.onChanged,
    required this.onEffacer,
  });

  final FiltresRecettes filtres;
  final Map<String, String> libellesStyles;
  final ValueChanged<FiltresRecettes> onChanged;
  final VoidCallback onEffacer;

  @override
  Widget build(BuildContext context) {
    final degre = filtres.degre;
    final ebc = filtres.ebc;
    Widget puce(String label, String retirer, FiltresRecettes sans) =>
        InputChip(
          label: Text(label),
          onDeleted: () => onChanged(sans),
          deleteButtonTooltipMessage: retirer,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final cle in filtres.styles)
            puce(
              'Style : ${libellesStyles[cle] ?? cle}',
              TextesFiltresRecettes.retirerStyle(libellesStyles[cle] ?? cle),
              filtres.avecStyles({...filtres.styles}..remove(cle)),
            ),
          if (degre != null)
            puce(
              TextesFiltresRecettes.plageDegre(degre),
              TextesFiltresRecettes.retirerDegre,
              filtres.avecDegre(null),
            ),
          if (ebc != null)
            puce(
              TextesFiltresRecettes.plageEbc(ebc),
              TextesFiltresRecettes.retirerCouleur,
              filtres.avecEbc(null),
            ),
          for (final mot in filtres.motsSaisis)
            puce(
              'Arôme : $mot',
              TextesFiltresRecettes.retirerMot(mot),
              filtres.sansMot(mot),
            ),
          TextButton(
            onPressed: onEffacer,
            child: const Text(TextesFiltresRecettes.effacer),
          ),
        ],
      ),
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

/// Ligne d'une recette : teinte de sa couleur calculée, nom, style, degré et
/// couleur, description aromatique sur deux lignes, volume et auteur.
class _Row extends StatelessWidget {
  const _Row({
    required this.recipe,
    required this.readerUid,
    required this.apercu,
    required this.auteur,
    required this.large,
  });

  final Recipe recipe;
  final String? readerUid;

  /// Valeurs calculées ; `null` tant qu'elles ne sont pas lues.
  final ApercuRecette? apercu;

  /// Faux dans « Les miennes » : l'auteur n'est pas écrit.
  final bool auteur;

  /// Grand écran, texte de taille normale : degré et couleur à droite.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = recipe.content;
    final volume = c.batchVolumeL;
    final degre = apercu?.degre;
    final ebc = apercu?.ebc;
    final teinte = apercu?.teinte;
    final mesures = [
      if (degre != null) formatDegre(degre),
      if (ebc != null) formatEbc(ebc),
    ];
    final premiere = [?c.style, if (!large) ...mesures].join(' · ');
    final derniere = [
      if (volume != null) formatLitres(volume),
      if (auteur)
        libelleAuteur(
          ownerUid: recipe.ownerUid,
          ownerName: recipe.ownerName,
          readerUid: readerUid,
        ),
    ].join(' · ');
    final description = c.aromaDescription;
    return LigneListe(
      icone: Icons.menu_book_outlined,
      repere: teinte == null ? null : DisqueTeinte(teinte: teinte),
      titre: c.name,
      titreMaxLignes: 2,
      details: [
        if (premiere.isNotEmpty) Text(premiere),
        if (description != null)
          Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (derniere.isNotEmpty) Text(derniere),
      ],
      trailing: large && mesures.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (degre != null)
                  Text(
                    formatDegre(degre),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                if (ebc != null)
                  Text(
                    formatEbc(ebc),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            )
          : null,
      etiquettes: [
        if (recipe.hasPendingWrites)
          const Etiquette(label: 'En attente du réseau'),
        if (apercu?.calculImpossible ?? false)
          const Etiquette(
            label: RecipesListScreen.calculImpossible,
            ton: TonEtiquette.neutre,
          ),
      ],
      onTap: () => context.go(AppRoutes.recipe(recipe.id)),
    );
  }
}
