import 'package:flutter/foundation.dart';

import 'brew_event.dart';

/// Une ligne du relevé de fermentation : une densité, une température ou les deux à
/// la même heure, ou une note seule (FE6).
@immutable
class Releve {
  const Releve({this.gravity, this.temperature, this.noteEvent});

  final BrewEvent? gravity;
  final BrewEvent? temperature;

  /// Événement `note`, présent quand le relevé n'a aucune valeur.
  final BrewEvent? noteEvent;

  /// Événements du relevé, jamais vide.
  List<BrewEvent> get events => [?gravity, ?temperature, ?noteEvent];

  DateTime get measuredAt => events.first.measuredAt;

  double? get gravityValue => gravity?.value;
  double? get temperatureValue => temperature?.value;

  /// Vrai pour une ligne qui porte une valeur (la courbe et les écarts ne lisent
  /// qu'elles).
  bool get aDesValeurs => gravity != null || temperature != null;

  /// La note du relevé : portée par le premier événement (FE5).
  String? get note => events.first.note;

  bool get hasPendingWrites => events.any((e) => e.hasPendingWrites);

  /// Identité stable pour l'interface.
  String get cle => events.first.id;
}

/// Relevés de fermentation de [events], du plus récent au plus ancien. Un couple
/// densité et température de même `measured_at` forme une ligne ; deux densités à la
/// même heure en forment deux.
List<Releve> relevesDe(List<BrewEvent> events) {
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
      releves.add(Releve(gravity: e, temperature: couple));
    }
  }
  for (final t in temperatures) {
    if (!utilisees.contains(t.id)) releves.add(Releve(temperature: t));
  }
  return releves..sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
}
