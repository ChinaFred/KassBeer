import 'package:flutter/foundation.dart';

import 'brew.dart';
import 'brew_event.dart';

/// Une mesure retenue et la façon dont elle l'a été.
@immutable
class MesureRetenue {
  const MesureRetenue(this.event, {required this.choisie});

  final BrewEvent event;

  /// Vrai si le brasseur l'a désignée (« Changer »), faux pour la dernière mesure.
  final bool choisie;

  double get value => event.value!;
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

  /// Calcule les mesures retenues de [brew] parmi [events].
  factory MesuresRetenues.de(Brew brew, List<BrewEvent> events) {
    final initiale = _retenir(
      choisi: _chercher(events, brew.ogEventId, (e) => e.isGravity),
      candidats: events.where((e) => e.isGravity && !e.isFermentation),
    );
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
}) {
  if (choisi != null) return MesureRetenue(choisi, choisie: true);
  BrewEvent? derniere;
  for (final e in candidats) {
    if (derniere == null || e.measuredAt.isAfter(derniere.measuredAt)) {
      derniere = e;
    }
  }
  return derniere == null ? null : MesureRetenue(derniere, choisie: false);
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
