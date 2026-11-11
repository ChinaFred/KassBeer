import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Choix par défaut du formulaire « Nouveau brassin »
/// (`users/{uid}/preferences/processes`, ADR-009) : état propre au lecteur, jamais
/// écrit sur le modèle lu par le groupe.

@immutable
class PreferenceProcessus {
  const PreferenceProcessus({required this.defaultTemplateId});

  /// Modèle proposé par défaut, ou `null` : « Chronologie de la recette seule ».
  /// Peut désigner un modèle supprimé depuis.
  final String? defaultTemplateId;

  /// Lève [DocumentIllisible] si `default_template_id` n'est ni une chaîne ni nul.
  factory PreferenceProcessus.fromFirestore(Map<String, dynamic> data) {
    final id = data['default_template_id'];
    if (id != null && (id is! String || id.isEmpty)) {
      throw const DocumentIllisible('default_template_id', 'texte attendu');
    }
    return PreferenceProcessus(defaultTemplateId: id as String?);
  }
}

/// Modèle proposé par défaut selon la lecture [preference] : `null` sans document,
/// pendant la lecture, ou si le document est illisible (déjà rapporté).
String? idModeleParDefaut(RechercheDocument<PreferenceProcessus>? preference) =>
    switch (preference) {
      DocumentTrouve<PreferenceProcessus>(:final value) =>
        value.defaultTemplateId,
      _ => null,
    };
