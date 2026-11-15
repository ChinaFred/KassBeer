import 'package:brewing/brewing.dart' show DensiteRetenue;
import 'package:flutter/foundation.dart';

import 'brew_event.dart';
import 'densites.dart';

/// Une ligne du relevé de fermentation : une densité, une température ou les deux à
/// la même heure, ou une note seule (FE6).
@immutable
class Releve {
  const Releve({this.gravity, this.temperature, this.noteEvent, this.densite});

  final BrewEvent? gravity;

  /// Valeur retenue de [gravity] (`densiteDe`), calculée par [relevesDe].
  final DensiteRetenue? densite;
  final BrewEvent? temperature;

  /// Événement `note`, présent quand le relevé n'a aucune valeur.
  final BrewEvent? noteEvent;

  /// Événements du relevé, jamais vide.
  List<BrewEvent> get events => [?gravity, ?temperature, ?noteEvent];

  DateTime get measuredAt => events.first.measuredAt;

  /// Densité retenue (corrigée ou brute), `null` sans densité ou si la mesure
  /// n'en donne aucune (réfractomètre sans facteur).
  double? get gravityValue => densite?.sg;
  double? get temperatureValue => temperature?.value;

  /// Vrai pour une ligne qui porte une valeur (la courbe et les écarts ne lisent
  /// qu'elles).
  bool get aDesValeurs => gravityValue != null || temperature != null;

  /// La note du relevé : portée par le premier événement (FE5).
  String? get note => events.first.note;

  bool get hasPendingWrites => events.any((e) => e.hasPendingWrites);

  /// Identité stable pour l'interface.
  String get cle => events.first.id;
}

/// Relevés de fermentation de [events], du plus récent au plus ancien. Un couple
/// densité et température de même `measured_at` forme une ligne ; deux densités à la
/// même heure en forment deux. [densiteInitiale] : densité initiale retenue du
/// brassin, pour la correction de l'alcool d'un réfractomètre.
///
/// Lève `BrewingInputException` sur une lecture hors forme (`densiteDe`).
List<Releve> relevesDe(List<BrewEvent> events, {double? densiteInitiale}) {
  final mesures = [
    for (final e in events)
      if (e.isFermentation) e,
  ]..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
  final temperatures = [
    for (final e in mesures)
      if (e.measureType == MeasureType.temperature) e,
  ];
  final releves = <Releve>[];
  final utilisees = <String>{};
  for (final e in mesures) {
    if (e.kind == BrewEventKind.note) {
      releves.add(Releve(noteEvent: e));
    } else if (e.isGravity) {
      BrewEvent? couple;
      for (final t in temperatures) {
        if (!utilisees.contains(t.id) && t.measuredAt == e.measuredAt) {
          couple = t;
          utilisees.add(t.id);
          break;
        }
      }
      releves.add(
        Releve(
          gravity: e,
          temperature: couple,
          densite: densiteDe(e, densiteInitiale: densiteInitiale),
        ),
      );
    }
  }
  for (final t in temperatures) {
    if (!utilisees.contains(t.id)) releves.add(Releve(temperature: t));
  }
  return releves..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
}
