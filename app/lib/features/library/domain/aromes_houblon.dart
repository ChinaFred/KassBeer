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

/// Confiance déclarée par la génération ; seule [faible] s'affiche.
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
    final relu = read.boolFacultatif('reviewed');
    if (relu == null) {
      throw const DocumentIllisible('reviewed', 'booléen obligatoire absent');
    }
    final reluLe = relu ? _dateRelecture(read) : null;
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

  /// `reviewed_at` en `AAAA-MM-JJ`, date du calendrier ; sinon illisible.
  static DateTime _dateRelecture(LecteurChamps read) {
    final value = read.texteFacultatif('reviewed_at');
    final match = value == null
        ? null
        : RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match != null) {
      final annee = int.parse(match.group(1)!);
      final mois = int.parse(match.group(2)!);
      final jour = int.parse(match.group(3)!);
      final date = DateTime(annee, mois, jour);
      if (date.year == annee && date.month == mois && date.day == jour) {
        return date;
      }
    }
    throw const DocumentIllisible(
      'reviewed_at',
      'date AAAA-MM-JJ attendue quand reviewed est vrai',
    );
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
