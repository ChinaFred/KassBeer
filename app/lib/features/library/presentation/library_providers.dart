import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/aromes_houblon.dart';
import '../domain/recette_publique.dart';
import '../domain/referentiel.dart';

/// Suite du message d'un segment vide d'ingrédients ou de styles.
const _remplie =
    " dans la bibliothèque pour l'instant. L'administrateur la remplit.";

/// Segment de la Bibliothèque : chemin, libellé, libellé court (puce sous
/// 600 px ou avec un texte agrandi), icône de la puce, titre de la fiche, message quand il est vide,
/// et nature du référentiel lu (`null` pour les recettes publiques).
enum SegmentBibliotheque {
  styles(
    'styles',
    'Styles',
    'Styles',
    Icons.style_outlined,
    'Style',
    'Aucun style$_remplie',
    NatureReferentiel.styles,
  ),
  fermentables(
    'malts',
    'Malts et sucres',
    'Malts',
    Icons.grain,
    'Malt ou sucre',
    'Aucun malt ni sucre$_remplie',
    NatureReferentiel.fermentables,
  ),
  hops(
    'houblons',
    'Houblons',
    'Houblons',
    Icons.eco_outlined,
    'Houblon',
    'Aucun houblon$_remplie',
    NatureReferentiel.hops,
  ),
  cultures(
    'levures',
    'Levures',
    'Levures',
    Icons.bubble_chart_outlined,
    'Levure',
    'Aucune levure$_remplie',
    NatureReferentiel.cultures,
  ),
  miscs(
    'divers',
    'Divers',
    'Divers',
    Icons.category_outlined,
    'Ajout divers',
    'Aucun ajout divers$_remplie',
    NatureReferentiel.miscs,
  ),
  recettes(
    'recettes',
    'Recettes publiques',
    'Recettes',
    Icons.menu_book_outlined,
    'Recette publique',
    "Aucune recette publique pour l'instant.",
    null,
  );

  const SegmentBibliotheque(
    this.slug,
    this.label,
    this.labelCourt,
    this.icone,
    this.titreFiche,
    this.vide,
    this.nature,
  );

  /// Segment du chemin (`/bibliotheque/houblons`).
  final String slug;
  final String label;

  /// Libellé de la puce sous 600 px, ou avec un texte agrandi à partir de
  /// `kGrandTexteMinScale` ; [label] reste lu par le lecteur d'écran.
  final String labelCourt;
  final IconData icone;
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

/// Description aromatique d'un houblon, lue par `get()` à l'ouverture de sa fiche
/// (ADR-013). Relue au passage hors ligne ou au retour du réseau.
final aromesHoublonProvider = FutureProvider.autoDispose
    .family<RechercheDocument<AromesHoublon>, String>((ref, id) {
      ref.watch(grantedAccessProvider.select((a) => a?.offline));
      return ref.watch(libraryRepositoryProvider).lireAromesHoublon(id);
    }, retry: _sansNouvelEssai);
