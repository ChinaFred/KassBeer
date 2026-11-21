import 'dart:async';

import 'package:exchange/exchange.dart' show IndexBibliotheque;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../../recipes/domain/import_recettes.dart' show indexBibliotheque;
import '../../recipes/presentation/contenu_recette.dart';
import '../domain/referentiel.dart';
import 'library_providers.dart';

// Liens d'une ligne de recette vers sa fiche de la Bibliothèque (ADR-018,
// lot D4) : houblons et autres ajouts de la fiche d'une recette, de la recette
// figée d'un brassin et d'une recette publique. L'écran du jour et les
// journées n'importent pas ce fichier (P2) : `ContenuRecette` y reste sans
// `ligneVersBibliotheque`.

/// Indice lu par le lecteur d'écran sur une ligne liée.
const kIndiceLienBibliotheque = 'Ouvre la fiche dans la Bibliothèque';

Duration? _sansNouvelEssai(int retryCount, Object error) => null;

/// Index de résolution de [cle.nature] (houblons ou ajouts), tiré de
/// `beer_index/{nature}` lu par `get()` (P22) et gardé par le dépôt pour la
/// session. [cle.cacheSeul] (hors ligne) : cache seul. `null` quand l'index est
/// absent, absent du cache ou illisible ; une panne, rapportée par le dépôt,
/// rend une erreur. Dans ces trois cas, aucune ligne n'est liée.
final indexLiensProvider = FutureProvider.autoDispose
    .family<IndexBibliotheque?, ({NatureReferentiel nature, bool cacheSeul})>((
      ref,
      cle,
    ) async {
      final index = await ref
          .watch(libraryRepositoryProvider)
          .lireIndex(cle.nature, cacheSeul: cle.cacheSeul);
      return switch (index) {
        DocumentTrouve(:final value) => indexBibliotheque(value),
        DocumentAbsent() ||
        DocumentAbsentDuCache() ||
        DocumentIllisibleTrouve() => null,
      };
    }, retry: _sansNouvelEssai);

/// [LigneIngredient] des trois écrans qui lient leurs lignes à la
/// Bibliothèque.
Widget ligneVersBibliotheque(
  IngredientLie nature,
  String nom,
  List<String> details,
) => LigneVersBibliotheque(nature: nature, nom: nom, details: details);

/// Ligne d'un houblon ou d'un autre ajout. Résolue dans l'index par son nom
/// (`IndexBibliotheque.resoudre` : nom ou alias exact après normalisation),
/// elle ouvre la fiche de la Bibliothèque ; sinon, et tant que l'index se lit,
/// elle reste une [LigneDeuxNiveaux], sans chevron ni mention.
class LigneVersBibliotheque extends ConsumerWidget {
  const LigneVersBibliotheque({
    super.key,
    required this.nature,
    required this.nom,
    required this.details,
  });

  final IngredientLie nature;
  final String nom;
  final List<String> details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ligne = LigneDeuxNiveaux(title: nom, details: details);
    final offline = ref.watch(
      grantedAccessProvider.select((a) => a?.offline ?? false),
    );
    final (referentiel, segment) = switch (nature) {
      IngredientLie.houblon => (
        NatureReferentiel.hops,
        SegmentBibliotheque.hops,
      ),
      IngredientLie.divers => (
        NatureReferentiel.miscs,
        SegmentBibliotheque.miscs,
      ),
    };
    final index = ref
        .watch(indexLiensProvider((nature: referentiel, cacheSeul: offline)))
        .value;
    final entree = index?.resoudre(nom);
    if (entree == null) return ligne;
    void ouvrir() => unawaited(
      context.push(
        AppRoutes.libraryEntry(segment.slug, entree.id),
        extra: AppRoutes.retourParPop,
      ),
    );
    final theme = Theme.of(context);
    // Un seul nœud : le libellé de la ligne, l'appui et le focus de l'InkWell
    // fusionnés ; les textes et le chevron ne sont pas lus à part.
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: '$nom, ${details.join(', ')}. $kIndiceLienBibliotheque.',
        child: InkWell(
          onTap: ouvrir,
          borderRadius: BorderRadius.circular(8),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: Row(
                children: [
                  Expanded(child: ligne),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
