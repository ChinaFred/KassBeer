import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../recipes/domain/beerjson.dart';
import '../../recipes/domain/recipe.dart';
import 'referentiel.dart';

/// Recette publique `public_recipes/{id}` (ADR-005, DIY Dog) : même enveloppe que
/// `recipes/`, écrite par le script d'ingestion seul. `recipe` se lit par
/// [RecipeContent.fromFirestore], comme une recette du groupe, pour que les
/// calculs (`computeRecipe`) et « Dupliquer » partent du même type. Les champs
/// propres aux recettes publiques ont leur lecture ici : `announced`,
/// `source_hop_timing`, `provenance`, `style_id`, `search_name`.
/// `ingredient_refs` n'est pas lu à cette étape.
@immutable
class RecettePublique {
  const RecettePublique({
    required this.id,
    required this.content,
    this.ownerName,
    this.searchName,
    this.styleId,
    this.momentsOrigine = const {},
    this.annonce = const ValeursAnnoncees(),
    this.provenance = const [],
  });

  final String id;

  /// Contenu lu par [RecipeContent.fromFirestore] ; `importedFrom` porte
  /// `DIY Dog · diydog-{id}`.
  final RecipeContent content;

  /// `owner_name` (`DIY Dog`).
  final String? ownerName;

  /// Nom normalisé du tri et de la recherche par préfixe
  /// (`normaliserNomRecherche`), écrit par l'ingestion.
  final String? searchName;

  /// Style résolu dans `beer_styles`, s'il existe.
  final String? styleId;

  /// Libellé d'origine du moment d'un houblon dont la durée n'est pas connue
  /// (`start`, `middle`, `Whirlpool`…), par rang dans `hop_additions`.
  final Map<int, String> momentsOrigine;

  /// Valeurs annoncées par la source, jamais calculées.
  final ValeursAnnoncees annonce;
  final List<Provenance> provenance;

  String get name => content.name;

  /// Contenu écrit par « Dupliquer » dans `recipes/` : `recipe` et
  /// `imported_from` seulement, sans `equipment_id` ni `brew_steps`, même si le
  /// document en portait. `RecipeContent.toFirestore` n'écrit que les clés des
  /// règles de `recipes/` : ni `style_id`, ni `ingredient_refs`, ni
  /// `source_hop_timing`, ni `announced`, ni `provenance`, ni `search_name`.
  RecipeContent get copie => RecipeContent(
    name: content.name,
    type: content.type,
    author: content.author,
    style: content.style,
    notes: content.notes,
    batchVolumeL: content.batchVolumeL,
    boilTimeMin: content.boilTimeMin,
    grainTempC: content.grainTempC,
    fermentables: content.fermentables,
    hops: content.hops,
    others: content.others,
    yeasts: content.yeasts,
    mashSteps: content.mashSteps,
    importedFrom: content.importedFrom,
  );

  /// Lit le document ; lève [DocumentIllisible] (version de format, unité ou
  /// valeur hors du schéma, rang de houblon hors de la liste).
  factory RecettePublique.fromFirestore(String id, Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final content = RecipeContent.fromFirestore(data);
    final moments = <int, String>{};
    for (final m in read.liste('source_hop_timing')) {
      final index = m.data['hop_index'];
      if (index is! int || index < 0 || index >= content.hops.length) {
        throw DocumentIllisible('${m.prefix}hop_index', 'rang de houblon');
      }
      moments[index] = m.texte('label');
    }
    final announced = read.objetFacultatif('announced');
    return RecettePublique(
      id: id,
      content: content,
      ownerName: read.texteFacultatif('owner_name'),
      searchName: read.texteFacultatif('search_name'),
      styleId: read.texteFacultatif('style_id'),
      momentsOrigine: Map.unmodifiable(moments),
      annonce: announced == null
          ? const ValeursAnnoncees()
          : ValeursAnnoncees.fromFirestore(announced),
      provenance: lireProvenance(read),
    );
  }
}

/// `announced` : valeurs données par la recette d'origine.
@immutable
class ValeursAnnoncees {
  const ValeursAnnoncees({
    this.originalGravity,
    this.finalGravity,
    this.alcoholByVolume,
    this.ibu,
    this.colorEbc,
  });

  /// Densités en SG décimal.
  final double? originalGravity;
  final double? finalGravity;

  /// Degré en %.
  final double? alcoholByVolume;
  final double? ibu;
  final double? colorEbc;

  bool get vide =>
      originalGravity == null &&
      finalGravity == null &&
      alcoholByVolume == null &&
      ibu == null &&
      colorEbc == null;

  factory ValeursAnnoncees.fromFirestore(LecteurChamps read) =>
      ValeursAnnoncees(
        originalGravity: read.mesure('original_gravity', kUniteDensite),
        finalGravity: read.mesure('final_gravity', kUniteDensite),
        alcoholByVolume: read.mesure(
          'alcohol_by_volume',
          UniteBeerJson.pourcent,
        ),
        ibu: read.mesure('ibu_estimate', kUniteIbu),
        colorEbc: read.mesure('color_estimate', UniteBeerJson.ebc),
      );
}
