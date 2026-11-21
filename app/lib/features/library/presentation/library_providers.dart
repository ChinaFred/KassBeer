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
    'style',
    'styles',
  ),
  fermentables(
    'malts',
    'Malts et sucres',
    'Malts',
    Icons.grain,
    'Malt ou sucre',
    'Aucun malt ni sucre$_remplie',
    NatureReferentiel.fermentables,
    'malt ou sucre',
    'malts et sucres',
  ),
  hops(
    'houblons',
    'Houblons',
    'Houblons',
    Icons.eco_outlined,
    'Houblon',
    'Aucun houblon$_remplie',
    NatureReferentiel.hops,
    'houblon',
    'houblons',
  ),
  cultures(
    'levures',
    'Levures',
    'Levures',
    Icons.bubble_chart_outlined,
    'Levure',
    'Aucune levure$_remplie',
    NatureReferentiel.cultures,
    'levure',
    'levures',
  ),
  miscs(
    'divers',
    'Divers',
    'Divers',
    Icons.category_outlined,
    'Ajout divers',
    'Aucun ajout divers$_remplie',
    NatureReferentiel.miscs,
    'ajout divers',
    'ajouts divers',
  ),
  recettes(
    'recettes',
    'Recettes publiques',
    'Recettes',
    Icons.menu_book_outlined,
    'Recette publique',
    "Aucune recette publique pour l'instant.",
    null,
    'recette publique',
    'recettes publiques',
  );

  const SegmentBibliotheque(
    this.slug,
    this.label,
    this.labelCourt,
    this.icone,
    this.titreFiche,
    this.vide,
    this.nature,
    this.singulier,
    this.pluriel,
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

  /// Nom d'une entrée du segment, au singulier et au pluriel (« houblon »,
  /// « houblons »), pour le compte de la liste.
  final String singulier;
  final String pluriel;

  /// « 1 houblon », « 442 houblons ».
  String compte(int n) => n == 1 ? '1 $singulier' : '$n $pluriel';
}

Duration? _sansNouvelEssai(int retryCount, Object error) => null;

/// Index de [NatureReferentiel], lu par `get()` ; le dépôt de données le garde
/// pour la session. Une panne s'affiche ; « Réessayer » relance la lecture.
final indexReferentielProvider = FutureProvider.autoDispose
    .family<RechercheDocument<IndexReferentiel>, NatureReferentiel>(
      (ref, nature) => ref.watch(libraryRepositoryProvider).lireIndex(nature),
      retry: _sansNouvelEssai,
    );

/// Index des arômes (`beer_index/hop_aromas`), lu par `get()` à l'ouverture du
/// segment Houblons seulement ; le dépôt de données le garde pour la session.
/// Absent, illisible ou en panne : la liste s'affiche sans filtre de confiance.
final indexAromesProvider =
    FutureProvider.autoDispose<RechercheDocument<IndexAromes>>(
      (ref) => ref.watch(libraryRepositoryProvider).lireIndexAromes(),
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

/// Filtre de confiance des arômes (segment Houblons) : choix unique, jamais
/// écrit en base ; « Sans description » regroupe les entrées `unknown` et les
/// houblons absents de l'index.
enum FiltreConfiance {
  toutes('Toutes', null, ''),
  elevee('Élevée', ConfianceIndex.elevee, 'avec une confiance élevée'),
  moyenne('Moyenne', ConfianceIndex.moyenne, 'avec une confiance moyenne'),
  faible('Faible', ConfianceIndex.faible, 'avec une confiance faible'),
  sansDescription(
    'Sans description',
    ConfianceIndex.sansDescription,
    'sans description',
  );

  const FiltreConfiance(this.libelle, this.confiance, this.suite);

  final String libelle;

  /// Confiance retenue ; `null` : toutes.
  final ConfianceIndex? confiance;

  /// Fin du message d'une liste vide (« avec une confiance faible »).
  final String suite;

  bool retient(ConfianceIndex c) => confiance == null || confiance == c;
}

/// Recherche et filtre d'un segment de la Bibliothèque. [texte] : le texte du
/// champ ; [prefixe] : la recherche validée des recettes publiques (la frappe
/// seule ne lit rien) ; [filtre] : le filtre de confiance des houblons.
@immutable
class RechercheBibliotheque {
  const RechercheBibliotheque({
    this.texte = '',
    this.prefixe = '',
    this.filtre = FiltreConfiance.toutes,
  });

  final String texte;
  final String prefixe;
  final FiltreConfiance filtre;

  RechercheBibliotheque copyWith({
    String? texte,
    String? prefixe,
    FiltreConfiance? filtre,
  }) => RechercheBibliotheque(
    texte: texte ?? this.texte,
    prefixe: prefixe ?? this.prefixe,
    filtre: filtre ?? this.filtre,
  );
}

class RechercheBibliothequeNotifier extends Notifier<RechercheBibliotheque> {
  RechercheBibliothequeNotifier(this.segment);

  final SegmentBibliotheque segment;

  @override
  RechercheBibliotheque build() => const RechercheBibliotheque();

  void saisir(String texte) => state = state.copyWith(texte: texte);

  /// Recettes publiques : valide le texte du champ comme préfixe.
  void valider() => state = state.copyWith(prefixe: state.texte.trim());

  void effacer() => state = state.copyWith(texte: '', prefixe: '');

  void filtrer(FiltreConfiance filtre) =>
      state = state.copyWith(filtre: filtre);
}

/// Recherche et filtre d'un segment, en mémoire seulement (jamais écrits en
/// base). Gardés tant que la liste du segment est ouverte : au retour d'une
/// fiche, au choix d'une autre fiche et au passage d'une à deux colonnes ;
/// perdus au changement de segment.
final rechercheBibliothequeProvider = NotifierProvider.autoDispose
    .family<
      RechercheBibliothequeNotifier,
      RechercheBibliotheque,
      SegmentBibliotheque
    >(RechercheBibliothequeNotifier.new);
