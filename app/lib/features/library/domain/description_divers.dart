import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';
import '../../recipes/domain/recipe.dart' show OtherUse;
import 'relecture.dart';

/// Collection des descriptions des divers (ADR-017), écrite par l'ingestion
/// seule, lue par `get` à l'ouverture de la fiche d'un divers.
const kCollectionDescriptionsDivers = 'beer_misc_descriptions';

/// Clé de la map `moments` pour chaque moment de l'éditeur de recette, dans
/// l'ordre d'affichage de la fiche (ADR-017, section 3). Le libellé affiché est
/// [OtherUse.label] : aucun libellé recopié.
const kClesMoments = {
  OtherUse.mash: 'mash',
  OtherUse.boil: 'boil',
  OtherUse.afterBoil: 'after_boil',
  OtherUse.fermentation: 'fermentation',
  OtherUse.bottling: 'bottling',
};

const _confiances = {'high', 'medium', 'low'};

/// Rôle d'un divers : `label` est affiché tel quel. La liste fermée des clés
/// vit dans `ingest/` seul : aucune copie en Dart (ADR-017).
@immutable
class RoleDivers {
  const RoleDivers({required this.key, required this.label});

  final String key;
  final String label;
}

/// Description d'un divers, `beer_misc_descriptions/{id}` (ADR-017, section 3).
/// Lecture stricte : un champ attendu absent ou mal typé lève
/// [DocumentIllisible], dont la raison ne recopie aucun texte du document. Une
/// clé de `moments` inconnue est ignorée.
@immutable
sealed class DescriptionDivers {
  const DescriptionDivers({required this.relu, required this.reluLe});

  /// `reviewed` : texte relu par l'administrateur.
  final bool relu;

  /// `reviewed_at`, posé quand [relu] est vrai.
  final DateTime? reluLe;

  static DescriptionDivers fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final (:relu, :reluLe) = lireRelecture(read);
    switch (data['status']) {
      case 'unknown':
        return DiversInconnu(relu: relu, reluLe: reluLe);
      case 'described':
        final confidence = data['confidence'];
        if (!_confiances.contains(confidence)) {
          throw const DocumentIllisible(
            'confidence',
            'high, medium ou low attendu',
          );
        }
        final resume = read.texte('summary');
        if (data['roles'] is! List) {
          throw const DocumentIllisible('roles', 'liste attendue');
        }
        final roles = [
          for (final r in read.liste('roles'))
            RoleDivers(key: r.texte('key'), label: r.texte('label')),
        ];
        final moments = read.objet('moments');
        final textes = <OtherUse, String>{};
        for (final MapEntry(key: moment, value: cle) in kClesMoments.entries) {
          final m = moments.objetFacultatif(cle);
          if (m != null) textes[moment] = m.texte('text');
        }
        final changeGout = read.boolFacultatif('changes_taste');
        if (changeGout == null) {
          throw const DocumentIllisible(
            'changes_taste',
            'booléen obligatoire absent',
          );
        }
        final taste = read.objetFacultatif('taste');
        if (taste != null && !changeGout) {
          throw const DocumentIllisible(
            'taste',
            'absent attendu quand changes_taste est faux',
          );
        }
        if (taste == null && changeGout) {
          throw const DocumentIllisible(
            'taste',
            'obligatoire quand changes_taste est vrai',
          );
        }
        return DiversDecrit(
          relu: relu,
          reluLe: reluLe,
          confianceFaible: confidence == 'low',
          resume: resume,
          roles: List.unmodifiable(roles),
          moments: Map.unmodifiable(textes),
          gout: taste?.texte('text'),
        );
      default:
        throw const DocumentIllisible('status', 'described ou unknown attendu');
    }
  }
}

/// `status: described`.
class DiversDecrit extends DescriptionDivers {
  const DiversDecrit({
    required super.relu,
    required super.reluLe,
    required this.confianceFaible,
    required this.resume,
    required this.roles,
    required this.moments,
    required this.gout,
  });

  /// `confidence` vaut `low`.
  final bool confianceFaible;

  /// `summary`.
  final String resume;

  /// Dans l'ordre du document.
  final List<RoleDivers> roles;

  /// Texte de chaque moment présent ; une clé inconnue n'y est pas.
  final Map<OtherUse, String> moments;

  /// `taste.text`, présent si et seulement si `changes_taste` est vrai ;
  /// `null` : sans effet notable sur le goût.
  final String? gout;
}

/// `status: unknown` : ajout trop peu documenté.
class DiversInconnu extends DescriptionDivers {
  const DiversInconnu({required super.relu, required super.reluLe});
}
