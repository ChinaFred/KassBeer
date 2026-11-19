import 'package:brewing/brewing.dart'
    show DensiteRetenue, LectureDensite, densiteRetenue;

import 'brew_event.dart';

/// Lecture brute stockée par la mesure de densité [e], telle que `brewing/` la
/// lit (`LectureDensite`).
LectureDensite lectureDe(BrewEvent e) {
  final detail = e.densite;
  return LectureDensite(
    instrument: detail?.instrument,
    sg: e.value,
    brix: detail?.brix,
    temperatureEchantillonC: detail?.temperatureEchantillon,
    facteur: detail?.facteur,
    corriger: detail?.corriger ?? true,
    enFermentation: e.isFermentation,
  );
}

/// Valeur retenue de la mesure de densité [e], calculée par `brewing/` (P3) :
/// seule lecture d'une densité mesurée pour l'affichage et les calculs.
/// [densiteInitiale] : densité initiale retenue du brassin, pour la correction
/// de l'alcool d'un réfractomètre en fermentation.
///
/// Lève `BrewingInputException` sur une lecture hors forme ; un événement lu
/// par `BrewEvent.fromFirestore` a déjà été contrôlé.
DensiteRetenue densiteDe(BrewEvent e, {double? densiteInitiale}) =>
    densiteRetenue(lectureDe(e), densiteInitialeSg: densiteInitiale);
