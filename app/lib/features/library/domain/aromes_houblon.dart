import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import 'relecture.dart';

/// Collection des descriptions aromatiques des houblons (ADR-013), écrite par
/// l'ingestion seule, lue par `get` à l'ouverture de la fiche d'un houblon.
const kCollectionAromesHoublons = 'beer_hop_aromas';

/// Usage d'un houblon décrit par `uses`, dans l'ordre d'affichage de la fiche.
enum UsageArome {
  firstWort('first_wort'),
  bittering('bittering'),
  lateBoil('late_boil'),
  whirlpool('whirlpool'),
  dryHop('dry_hop');

  const UsageArome(this.cle);

  /// Clé de la map `uses`.
  final String cle;
}

/// Confiance déclarée par la génération. La fiche n'affiche que [faible] ; le
/// filtre de la liste des houblons les propose toutes ([IndexAromes]).
enum ConfianceArome { haute, moyenne, faible }

const _confiances = {
  'high': ConfianceArome.haute,
  'medium': ConfianceArome.moyenne,
  'low': ConfianceArome.faible,
};

/// Descripteur d'arôme : `label` est affiché tel quel. La liste fermée des clés
/// vit dans `ingest/` seul : aucune copie en Dart (ADR-013).
@immutable
class DescripteurArome {
  const DescripteurArome({required this.key, required this.label});

  final String key;
  final String label;
}

/// Description aromatique d'un houblon, `beer_hop_aromas/{id}` (ADR-013,
/// section 4). Lecture stricte : un champ attendu absent ou mal typé lève
/// [DocumentIllisible], dont la raison ne recopie aucun texte du document. Une
/// clé de `uses` inconnue est ignorée.
@immutable
sealed class AromesHoublon {
  const AromesHoublon({required this.relu, required this.reluLe});

  /// `reviewed` : texte relu par l'administrateur.
  final bool relu;

  /// `reviewed_at`, posé quand [relu] est vrai.
  final DateTime? reluLe;

  static AromesHoublon fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final (:relu, :reluLe) = lireRelecture(read);
    final status = data['status'];
    switch (status) {
      case 'unknown':
        return AromesInconnus(relu: relu, reluLe: reluLe);
      case 'described':
        final confidence = data['confidence'];
        final confiance = _confiances[confidence];
        if (confiance == null) {
          throw const DocumentIllisible(
            'confidence',
            'high, medium ou low attendu',
          );
        }
        final descripteurs = [
          for (final d in read.liste('descriptors'))
            DescripteurArome(key: d.texte('key'), label: d.texte('label')),
        ];
        final uses = read.objet('uses');
        final usages = <UsageArome, String>{};
        for (final usage in UsageArome.values) {
          final u = uses.objetFacultatif(usage.cle);
          if (u != null) usages[usage] = u.texte('text');
        }
        return AromesDecrits(
          relu: relu,
          reluLe: reluLe,
          confiance: confiance,
          descripteurs: List.unmodifiable(descripteurs),
          usages: Map.unmodifiable(usages),
        );
      default:
        throw const DocumentIllisible('status', 'described ou unknown attendu');
    }
  }
}

/// `status: described`.
class AromesDecrits extends AromesHoublon {
  const AromesDecrits({
    required super.relu,
    required super.reluLe,
    required this.confiance,
    required this.descripteurs,
    required this.usages,
  });

  final ConfianceArome confiance;

  /// Dans l'ordre du document.
  final List<DescripteurArome> descripteurs;

  /// Texte de chaque usage présent ; une clé inconnue n'y est pas.
  final Map<UsageArome, String> usages;
}

/// `status: unknown` : houblon trop peu documenté.
class AromesInconnus extends AromesHoublon {
  const AromesInconnus({required super.relu, required super.reluLe});
}

/// Document de `beer_index/` qui résume les descriptions aromatiques (ADR-013,
/// note du 2026-11-21) : écrit par l'ingestion seule, lu par un `get` à
/// l'ouverture du segment Houblons (P22).
const kIndexAromesId = 'hop_aromas';

/// Confiance d'un houblon dans le filtre de la liste : celle de sa
/// description, ou [sansDescription] pour une entrée `unknown` et pour un
/// houblon absent de l'index.
enum ConfianceIndex { elevee, moyenne, faible, sansDescription }

const _confiancesIndex = {
  'high': ConfianceIndex.elevee,
  'medium': ConfianceIndex.moyenne,
  'low': ConfianceIndex.faible,
  'unknown': ConfianceIndex.sansDescription,
};

/// `beer_index/hop_aromas` : confiance de chaque houblon décrit, sans aucun
/// texte ni état de relecture. Lecture stricte : une entrée mal formée rend
/// tout l'index illisible ([DocumentIllisible], sans valeur du document dans
/// la raison) ; l'écran n'affiche alors ni filtre ni étiquette.
@immutable
class IndexAromes {
  const IndexAromes(this._parHoublon);

  final Map<String, ConfianceIndex> _parHoublon;

  /// Confiance du houblon [id] ; absent de l'index : [ConfianceIndex.sansDescription].
  ConfianceIndex confianceDe(String id) =>
      _parHoublon[id] ?? ConfianceIndex.sansDescription;

  factory IndexAromes.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    if (data['entries'] is! List) {
      throw const DocumentIllisible('entries', 'liste attendue');
    }
    final parHoublon = <String, ConfianceIndex>{};
    for (final e in read.liste('entries')) {
      final id = e.texte('id');
      final confiance = _confiancesIndex[e.data['confidence']];
      if (confiance == null) {
        throw DocumentIllisible(
          '${e.prefix}confidence',
          'high, medium, low ou unknown attendu',
        );
      }
      parHoublon[id] = confiance;
    }
    return IndexAromes(Map.unmodifiable(parHoublon));
  }
}
