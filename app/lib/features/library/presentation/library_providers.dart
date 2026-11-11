import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../domain/recette_publique.dart';
import '../domain/referentiel.dart';

/// Suite du message d'un segment vide d'ingrédients ou de styles.
const _remplie =
    " dans la bibliothèque pour l'instant. L'administrateur la remplit.";

/// Segment de la Bibliothèque : chemin, libellé, titre de la fiche, message
/// quand il est vide, et nature du référentiel lu (`null` pour les recettes
/// publiques).
enum SegmentBibliotheque {
  styles(
    'styles',
    'Styles',
    'Style',
    'Aucun style$_remplie',
    NatureReferentiel.styles,
  ),
  fermentables(
    'malts',
    'Malts et sucres',
    'Malt ou sucre',
    'Aucun malt ni sucre$_remplie',
    NatureReferentiel.fermentables,
  ),
  hops(
    'houblons',
    'Houblons',
    'Houblon',
    'Aucun houblon$_remplie',
    NatureReferentiel.hops,
  ),
  cultures(
    'levures',
    'Levures',
    'Levure',
    'Aucune levure$_remplie',
    NatureReferentiel.cultures,
  ),
  miscs(
    'divers',
    'Divers',
    'Ajout divers',
    'Aucun ajout divers$_remplie',
    NatureReferentiel.miscs,
  ),
  recettes(
    'recettes',
    'Recettes publiques',
    'Recette publique',
    "Aucune recette publique pour l'instant.",
    null,
  );

  const SegmentBibliotheque(
    this.slug,
    this.label,
    this.titreFiche,
    this.vide,
    this.nature,
  );

  /// Segment du chemin (`/bibliotheque/houblons`).
  final String slug;
  final String label;
  final String titreFiche;

  /// Message du segment sans aucune entrée.
  final String vide;
  final NatureReferentiel? nature;
}

Duration? _sansNouvelEssai(int retryCount, Object error) => null;

/// Index de [NatureReferentiel], lu par `get()` ; le dépôt de données le garde
/// pour la session. Une panne s'affiche ; « Réessayer » relance la lecture.
final indexReferentielProvider = FutureProvider.autoDispose
    .family<RechercheDocument<IndexReferentiel>, NatureReferentiel>(
      (ref, nature) => ref.watch(libraryRepositoryProvider).lireIndex(nature),
      retry: _sansNouvelEssai,
    );

/// Fiche d'un référentiel, lue par `get()` à chaque ouverture.
final ficheReferentielProvider = FutureProvider.autoDispose
    .family<
      RechercheDocument<FicheReferentiel>,
      ({NatureReferentiel nature, String id})
    >(
      (ref, cle) =>
          ref.watch(libraryRepositoryProvider).lireFiche(cle.nature, cle.id),
      retry: _sansNouvelEssai,
    );

/// Recette publique, lue par `get()` à chaque ouverture.
final recettePubliqueProvider = FutureProvider.autoDispose
    .family<RechercheDocument<RecettePublique>, String>(
      (ref, id) => ref.watch(libraryRepositoryProvider).lireRecettePublique(id),
      retry: _sansNouvelEssai,
    );
