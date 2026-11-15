import 'package:brewing/brewing.dart' show DensiteRetenue;
import 'package:flutter/foundation.dart';

import 'brew.dart';
import 'brew_event.dart';
import 'densites.dart';

/// Une mesure retenue et la façon dont elle l'a été.
@immutable
class MesureRetenue {
  const MesureRetenue(this.event, {required this.choisie, this.densite});

  final BrewEvent event;

  /// Vrai si le brasseur l'a désignée (« Changer »), faux pour la dernière mesure.
  final bool choisie;

  /// Valeur retenue d'une densité (`densiteDe`), `null` pour un volume.
  final DensiteRetenue? densite;

  /// Valeur lue par les calculs : densité retenue (corrigée ou brute), ou volume.
  /// `null` pour une densité qui n'en donne aucune (réfractomètre sans facteur).
  double? get value => densite == null ? event.value : densite!.sg;
}

/// Mesures retenues d'un brassin : aucune valeur n'est stockée, seuls les identifiants
/// choisis le sont sur `brews/{id}` (VR4).
@immutable
class MesuresRetenues {
  const MesuresRetenues({
    required this.densiteInitiale,
    required this.densiteFinale,
    required this.volumeFermenteur,
  });

  final MesureRetenue? densiteInitiale;
  final MesureRetenue? densiteFinale;
  final MesureRetenue? volumeFermenteur;

  /// Densité initiale retenue (SG), lue pour la correction de l'alcool d'un
  /// réfractomètre en fermentation.
  double? get densiteInitialeSg => densiteInitiale?.value;

  /// Valeur retenue de la mesure de densité [e] dans ce brassin (`densiteDe`).
  DensiteRetenue densite(BrewEvent e) =>
      densiteDe(e, densiteInitiale: densiteInitialeSg);

  /// Calcule les mesures retenues de [brew] parmi [events]. Une densité qui ne
  /// donne aucune valeur (réfractomètre sans facteur) n'est retenue que si le
  /// brasseur l'a choisie.
  ///
  /// Lève `BrewingInputException` sur une lecture hors forme (`densiteDe`).
  factory MesuresRetenues.de(Brew brew, List<BrewEvent> events) {
    // La densité initiale se calcule sans densité initiale : une lecture de
    // réfractomètre en fermentation choisie comme initiale reste sans correction.
    final initiale = _retenir(
      choisi: _chercher(events, brew.ogEventId, (e) => e.isGravity),
      candidats: events.where((e) => e.isGravity && !e.isFermentation),
      densite: densiteDe,
    );
    final og = initiale?.value;
    DensiteRetenue densiteAvecInitiale(BrewEvent e) =>
        densiteDe(e, densiteInitiale: og);
    final bottled = brew.bottledAt;
    final limite = brew.status != BrewStatus.fermenting ? bottled : null;
    final finale = _retenir(
      choisi: _chercher(
        events,
        brew.fgEventId,
        (e) => e.isGravity && e.isFermentation,
      ),
      candidats: events.where(
        (e) =>
            e.isGravity &&
            e.isFermentation &&
            e.id != initiale?.event.id &&
            (limite == null || !_jourApres(e.measuredAt, limite)),
      ),
      densite: densiteAvecInitiale,
    );
    final volume = _retenir(
      choisi: _chercher(events, brew.fermenterVolumeEventId, (e) => e.isVolume),
      candidats: events.where((e) => e.isVolume && !e.isFermentation),
    );
    return MesuresRetenues(
      densiteInitiale: initiale,
      densiteFinale: finale,
      volumeFermenteur: volume,
    );
  }
}

MesureRetenue? _retenir({
  required BrewEvent? choisi,
  required Iterable<BrewEvent> candidats,
  DensiteRetenue Function(BrewEvent)? densite,
}) {
  if (choisi != null) {
    return MesureRetenue(choisi, choisie: true, densite: densite?.call(choisi));
  }
  MesureRetenue? derniere;
  for (final e in candidats) {
    if (derniere != null && !e.measuredAt.isAfter(derniere.event.measuredAt)) {
      continue;
    }
    final valeur = densite?.call(e);
    if (densite != null && valeur?.sg == null) continue;
    derniere = MesureRetenue(e, choisie: false, densite: valeur);
  }
  return derniere;
}

BrewEvent? _chercher(
  List<BrewEvent> events,
  String? id,
  bool Function(BrewEvent) valide,
) {
  if (id == null) return null;
  for (final e in events) {
    if (e.id == id && valide(e)) return e;
  }
  return null;
}

/// Vrai si le jour calendaire de [a] est postérieur à celui de [b].
bool _jourApres(DateTime a, DateTime b) =>
    DateTime(a.year, a.month, a.day).isAfter(DateTime(b.year, b.month, b.day));

/// Mesures proposées par « Changer » pour [champ], la plus récente en tête (VR4).
List<BrewEvent> candidatsRetenus(
  MesureRetenueChamp champ,
  List<BrewEvent> events,
) {
  final candidats = [
    for (final e in events)
      if (switch (champ) {
        MesureRetenueChamp.densiteInitiale => e.isGravity,
        MesureRetenueChamp.densiteFinale => e.isGravity && e.isFermentation,
        MesureRetenueChamp.volumeFermenteur => e.isVolume && !e.isFermentation,
      })
        e,
  ];
  return candidats..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
}
