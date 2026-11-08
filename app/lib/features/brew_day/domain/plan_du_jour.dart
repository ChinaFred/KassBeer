import 'package:brewing/brewing.dart';
import 'package:flutter/foundation.dart';

import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../../recipes/domain/chronologie.dart';

/// Une étape de la chronologie d'un brassin, à l'instant du calcul.
@immutable
class LigneJour {
  const LigneJour({
    required this.index,
    required this.step,
    required this.schedule,
    required this.record,
    required this.mesures,
    required this.doublons,
  });

  final int index;
  final BrewStepLine step;
  final ScheduledStep schedule;
  final StepRecord? record;

  /// Mesures et notes rattachées à l'étape, par heure croissante.
  final List<BrewEvent> mesures;

  /// Débuts en double (deux appareils hors ligne) : le plus ancien compte.
  final List<StepEvent> doublons;

  StepStatus get status => schedule.status;
  Duration get duree => Duration(seconds: (step.durationMin * 60).round());
}

/// Vue dérivée d'un brassin à l'instant du calcul : chronologie, mesures, fin
/// prévue. Heures calculées par `brewing/` (P3), jamais écrites (P2).
@immutable
class PlanDuJour {
  const PlanDuJour({
    required this.lignes,
    required this.mesuresSansEtape,
    required this.anomalies,
    required this.etapeIncoherente,
    required this.finPrevue,
    required this.retard,
  });

  final List<LigneJour> lignes;
  final List<BrewEvent> mesuresSansEtape;

  /// Événements non retenus, à rapporter : étape inconnue, fin avant le début.
  final List<StepEventIssue> anomalies;

  /// Nom de l'étape qui finit avant de commencer, ou `null`.
  final String? etapeIncoherente;

  /// Fin de la dernière étape, ou `null` sans chronologie ou heures incohérentes.
  final DateTime? finPrevue;

  /// Écart de la fin prévue avec le plan depuis le premier début.
  final Duration retard;

  bool get horairesFiables => etapeIncoherente == null;

  LigneJour? get enCours {
    for (final l in lignes) {
      if (l.status == StepStatus.running) return l;
    }
    return null;
  }

  LigneJour? get prochaine {
    for (final l in lignes) {
      if (l.status == StepStatus.pending) return l;
    }
    return null;
  }

  /// La chronologie existe, et rien n'est en cours ni à venir.
  bool get termine => lignes.isNotEmpty && enCours == null && prochaine == null;

  /// Étape à venir après [ligne], ou `null`.
  LigneJour? suivanteDe(LigneJour ligne) {
    for (final l in lignes) {
      if (l.index > ligne.index && l.status == StepStatus.pending) return l;
    }
    return null;
  }

  /// Étapes à venir, non commencées, avant [ligne] : à sauter pour la commencer.
  List<LigneJour> nonFaitesAvant(LigneJour ligne) => [
    for (final l in lignes)
      if (l.index < ligne.index && l.status == StepStatus.pending) l,
  ];

  /// Calcule la vue de [brew] à [now] à partir de [events].
  ///
  /// Lève [BrewingInputException] si la chronologie ou les événements sont refusés
  /// par `brewing/` : l'appelant le rapporte et affiche la panne.
  factory PlanDuJour.calculer({
    required Brew brew,
    required List<BrewEvent> events,
    required DateTime now,
  }) {
    final steps = brew.recipe.brewSteps;
    final planned = [for (final s in steps) s.toPlanned()];
    final stepEvents = [
      for (final e in events)
        if (e.toStepEvent() != null) e.toStepEvent()!,
    ];
    final reduction = stepRecordsFromEvents(steps: planned, events: stepEvents);
    final plannedStart = brew.brewedAt ?? brew.plannedFor ?? now;
    final schedule = recomputeSchedule(
      steps: planned,
      plannedStart: plannedStart,
      records: reduction.records,
      now: now,
    );
    final recordByStep = {for (final r in reduction.records) r.stepId: r};
    final saisies = events.where((e) => e.isMeasureOrNote).toList()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    final doublons = <String, List<StepEvent>>{};
    final anomalies = <StepEventIssue>[];
    String? incoherente;
    for (final issue in reduction.issues) {
      switch (issue.kind) {
        case StepEventIssueKind.duplicateStart:
          (doublons[issue.event.stepKey] ??= []).add(issue.event);
        case StepEventIssueKind.endBeforeStart:
          anomalies.add(issue);
          incoherente ??= _nomEtape(steps, issue.event.stepKey);
        case StepEventIssueKind.unknownStep:
        case StepEventIssueKind.endWithoutStart:
          anomalies.add(issue);
        case StepEventIssueKind.duplicateEnd:
          break;
      }
    }

    final lignes = [
      for (final (i, s) in steps.indexed)
        LigneJour(
          index: i,
          step: s,
          schedule: schedule[i],
          record: recordByStep[s.key],
          mesures: [
            for (final e in saisies)
              if (e.stepKey == s.key) e,
          ],
          doublons: List.unmodifiable(doublons[s.key] ?? const <StepEvent>[]),
        ),
    ];
    final keys = {for (final s in steps) s.key};
    DateTime? finPrevue;
    var retard = Duration.zero;
    if (schedule.isNotEmpty && incoherente == null) {
      finPrevue = schedule.last.end;
      // Plan de référence : la même chronologie depuis le premier début.
      final reference = recomputeSchedule(
        steps: planned,
        plannedStart: plannedStart,
        records: const [],
        now: plannedStart,
      );
      final ecart = finPrevue.difference(reference.last.end);
      if (ecart > Duration.zero) retard = ecart;
    }
    return PlanDuJour(
      lignes: List.unmodifiable(lignes),
      mesuresSansEtape: List.unmodifiable([
        for (final e in saisies)
          if (e.stepKey == null || !keys.contains(e.stepKey)) e,
      ]),
      anomalies: List.unmodifiable(anomalies),
      etapeIncoherente: incoherente,
      finPrevue: finPrevue,
      retard: retard,
    );
  }
}

String _nomEtape(List<BrewStepLine> steps, String key) {
  for (final s in steps) {
    if (s.key == key) return s.name;
  }
  return key;
}
