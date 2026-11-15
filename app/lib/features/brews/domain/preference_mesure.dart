import 'package:brewing/brewing.dart'
    show InstrumentDensite, kFacteurRefractometreMax, kFacteurRefractometreMin;
import 'package:flutter/foundation.dart';

import '../../../core/data/lecture_document.dart';

/// Instrument de densité du brasseur (`users/{uid}/preferences/measurement`) :
/// état propre au lecteur, jamais écrit sur le brassin.
@immutable
class PreferenceMesure {
  const PreferenceMesure({required this.instrument, this.facteur});

  final InstrumentDensite instrument;

  /// Facteur de correction du moût du réfractomètre, saisi par le brasseur ;
  /// gardé quand il change d'instrument. Aucun facteur par défaut.
  final double? facteur;

  /// Lève [DocumentIllisible] sur un instrument inconnu ou un facteur hors
  /// bornes (mêmes bornes que `firestore.rules`).
  factory PreferenceMesure.fromFirestore(Map<String, dynamic> data) {
    final read = LecteurChamps(data);
    final stored = read.texte('gravity_instrument');
    final instrument = InstrumentDensite.values
        .where((i) => i.storedValue == stored)
        .firstOrNull;
    if (instrument == null) {
      throw const DocumentIllisible('gravity_instrument', 'instrument inconnu');
    }
    final facteur = read.nombreFacultatif('refractometer_factor');
    if (facteur != null &&
        (facteur < kFacteurRefractometreMin ||
            facteur > kFacteurRefractometreMax)) {
      throw const DocumentIllisible('refractometer_factor', 'hors bornes');
    }
    return PreferenceMesure(instrument: instrument, facteur: facteur);
  }

  Map<String, Object?> toFirestore() => {
    'gravity_instrument': instrument.storedValue,
    'refractometer_factor': facteur,
  };
}

/// Préférence lue de [recherche] : `null` sans document, pendant la lecture, ou
/// si le document est illisible (déjà rapporté) ; l'écran affiche « À choisir ».
PreferenceMesure? preferenceMesureDe(
  RechercheDocument<PreferenceMesure>? recherche,
) => switch (recherche) {
  DocumentTrouve<PreferenceMesure>(:final value) => value,
  _ => null,
};
