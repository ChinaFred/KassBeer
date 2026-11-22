import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

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

/// Confiance lue dans `confidence` ; une autre valeur rend le document
/// illisible. Commune aux houblons et aux levures (ADR-017).
ConfianceArome lireConfianceArome(Map<String, dynamic> data) =>
    _confiances[data['confidence']] ??
    (throw const DocumentIllisible(
      'confidence',
      'high, medium ou low attendu',
    ));

/// Nombre de descripteurs au plus, borne de l'écrivain (`DESCRIPTEURS_MAX` de
/// `ingest/lib/aromes/validation.mjs`).
const kDescripteursAromeMax = 8;

/// Descripteurs `{key, label}` de `descriptors`, dans l'ordre du document ;
/// au-delà de [kDescripteursAromeMax], le document est illisible. Communs aux
/// houblons et aux levures (ADR-017).
List<DescripteurArome> lireDescripteursArome(LecteurChamps read) {
  final descripteurs = read.liste('descriptors');
  if (descripteurs.length > kDescripteursAromeMax) {
    throw const DocumentIllisible('descriptors', '8 descripteurs au plus');
  }
  return List.unmodifiable([
    for (final d in descripteurs)
      DescripteurArome(key: d.texte('key'), label: d.texte('label')),
  ]);
}

/// Description aromatique d'un houblon, `beer_hop_aromas/{id}` (ADR-013,
/// section 4). Lecture stricte : un champ attendu absent ou mal typé lève
/// [DocumentIllisible], dont la raison ne recopie aucun texte du document. Une
/// clé de `uses` inconnue est ignorée. `reviewed` et `reviewed_at` servent à
/// l'ingestion seule : l'application ne les lit pas (décision de l'utilisateur
/// du 2026-11-21).
@immutable
sealed class AromesHoublon {
  const AromesHoublon();

  static AromesHoublon fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final status = data['status'];
    switch (status) {
      case 'unknown':
        return const AromesInconnus();
      case 'described':
        final confiance = lireConfianceArome(data);
        final descripteurs = lireDescripteursArome(read);
        final uses = read.objet('uses');
        final usages = <UsageArome, String>{};
        for (final usage in UsageArome.values) {
          final u = uses.objetFacultatif(usage.cle);
          if (u != null) usages[usage] = u.texte('text');
        }
        return AromesDecrits(
          confiance: confiance,
          descripteurs: descripteurs,
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
  const AromesInconnus();
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
