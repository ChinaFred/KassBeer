import 'package:brewing/brewing.dart'
    show BrewingInputException, StepEvent, StepStatus;
import 'package:flutter/material.dart';

import '../../../core/presentation/formats.dart';
import '../../../core/services/error_report_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../domain/plan_du_jour.dart';

/// Résultat du calcul de la chronologie d'un brassin.
sealed class PlanEvalue {
  const PlanEvalue();
}

class PlanObtenu extends PlanEvalue {
  const PlanObtenu(this.plan);

  final PlanDuJour plan;
}

/// `brewing/` a refusé le calcul (PR3).
class PlanImpossible extends PlanEvalue {
  const PlanImpossible();
}

/// Texte d'un calcul refusé : aucun nom technique à l'écran.
const kCalculChronologieImpossible =
    'Une heure ou une durée enregistrée est invalide.';

/// Texte d'un déroulé illisible (`Brew.deroule`, `probleme`).
String messageChronologieIllisible(String raison) =>
    'Chronologie de ce brassin illisible : $raison.';

/// Texte du verrou d'écran refusé.
const kVerrouRefuse =
    'Écran : l\'appareil refuse de le garder allumé. Réglez la mise en veille.';

/// Calcule la vue de [brew] à [now]. Une anomalie (fin avant le début, étape
/// inconnue) est rapportée une fois ([reported]). Une erreur de `brewing/` rend
/// [PlanImpossible] et est rapportée : l'écran affiche la panne.
PlanEvalue evaluerPlan({
  required Brew brew,
  required List<BrewEvent> events,
  required DateTime now,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  try {
    final plan = PlanDuJour.calculer(brew: brew, events: events, now: now);
    for (final anomaly in plan.anomalies) {
      if (!reported.add('${brew.id}|${anomaly.event.id}')) continue;
      errors.reportError(
        feature: 'brew_day.schedule',
        error: StateError('événement non retenu : ${anomaly.kind.name}'),
        context: 'brews/${brew.id} : ${anomaly.kind.name}',
      );
    }
    return PlanObtenu(plan);
  } on BrewingInputException catch (error, stackTrace) {
    if (reported.add('${brew.id}|${error.field}')) {
      errors.reportError(
        feature: 'brew_day.schedule',
        error: error,
        stackTrace: stackTrace,
        context: 'brews/${brew.id} : calcul refusé ${error.field}',
      );
    }
    return const PlanImpossible();
  }
}

/// Texte de l'état d'une étape, jamais la couleur seule.
String libelleEtat(StepStatus status) => switch (status) {
  StepStatus.done => 'Terminée',
  StepStatus.running => 'En cours',
  StepStatus.pending => 'À venir',
  StepStatus.skipped => 'Sautée',
  StepStatus.notDone => 'Non faite',
};

IconData iconeEtat(StepStatus status) => switch (status) {
  StepStatus.done => Icons.check_circle_outline,
  StepStatus.running => Icons.play_circle_outline,
  StepStatus.pending => Icons.schedule,
  StepStatus.skipped => Icons.skip_next,
  StepStatus.notDone => Icons.remove_circle_outline,
};

/// Colonne d'heure d'une ligne : heure réelle pour une étape faite ou en cours,
/// heure attendue pour une étape à venir (vide si les heures sont incohérentes).
String heureDeLigne(LigneJour ligne, PlanDuJour plan) {
  final record = ligne.record;
  final started = record?.startedAt;
  if (started != null) {
    final ended = record?.endedAt;
    return ended == null
        ? formatHeure(started)
        : '${formatHeure(started)} → ${formatHeure(ended)}';
  }
  if (ligne.status != StepStatus.pending || !plan.horairesFiables) return '—';
  return formatHeure(ligne.schedule.expectedStart);
}

/// Mesure ou note d'une étape, en une ligne : « 12:10 · 67,5 °C · note ».
String libelleSaisie(BrewEvent e) {
  final type = e.measureType;
  final value = e.value;
  return [
    formatHeure(e.measuredAt),
    if (type != null && value != null) libelleMesure(type, value),
    if (e.note != null) e.note!,
  ].join(' · ');
}

/// Liste des étapes d'un brassin, sur la fiche et l'écran du jour.
class ChronologieJour extends StatelessWidget {
  const ChronologieJour({
    super.key,
    required this.plan,
    this.onTapLigne,
    this.onTapSaisie,
    this.onSupprimerDoublon,
  });

  final PlanDuJour plan;

  /// `null` en lecture seule.
  final void Function(LigneJour ligne)? onTapLigne;
  final void Function(BrewEvent event)? onTapSaisie;

  /// Supprime un début en double ; `null` pour un autre membre.
  final void Function(StepEvent event)? onSupprimerDoublon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textSize = StylesJourDeBrassage.of(context).chronologie;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.etapeIncoherente != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'La chronologie ne peut pas être calculée : l\'étape '
              '« ${plan.etapeIncoherente} » finit avant de commencer. Corrigez '
              'son heure.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        for (final l in plan.lignes) ...[
          _Ligne(
            ligne: l,
            heure: heureDeLigne(l, plan),
            textSize: textSize,
            onTap: onTapLigne == null ? null : () => onTapLigne!(l),
          ),
          for (final d in l.doublons)
            _Doublon(
              event: d,
              onSupprimer: onSupprimerDoublon == null
                  ? null
                  : () => onSupprimerDoublon!(d),
            ),
          for (final s in l.mesures)
            _Saisie(
              event: s,
              onTap: onTapSaisie == null ? null : () => onTapSaisie!(s),
            ),
        ],
        if (plan.mesuresSansEtape.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text('Sans étape', style: theme.textTheme.titleSmall),
          ),
        for (final s in plan.mesuresSansEtape)
          _Saisie(
            event: s,
            onTap: onTapSaisie == null ? null : () => onTapSaisie!(s),
          ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.ligne,
    required this.heure,
    required this.textSize,
    required this.onTap,
  });

  final LigneJour ligne;
  final String heure;
  final double textSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = ligne.status == StepStatus.running;
    final duration = ligne.step.durationMin == 0
        ? 'Action'
        : formatDuree(ligne.duree);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Text(heure, style: TextStyle(fontSize: textSize)),
            ),
            Icon(iconeEtat(ligne.status), size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ligne.step.name, style: TextStyle(fontSize: textSize)),
                  Text(
                    '${libelleEtat(ligne.status)} · $duration',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label:
          '${ligne.step.name}, ${libelleEtat(ligne.status)}, $heure, $duration',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: running ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class _Saisie extends StatelessWidget {
  const _Saisie({required this.event, required this.onTap});

  final BrewEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(112, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    libelleSaisie(event),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (event.hasPendingWrites)
                  Tooltip(
                    message: 'En attente du réseau',
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      size: 20,
                      semanticLabel: 'En attente du réseau',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Doublon extends StatelessWidget {
  const _Doublon({required this.event, required this.onSupprimer});

  final StepEvent event;
  final VoidCallback? onSupprimer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supprimer = onSupprimer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(112, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Début en double · ${formatHeure(event.measuredAt)}',
              style: TextStyle(color: theme.colorScheme.tertiary),
            ),
          ),
          if (supprimer != null)
            TextButton(onPressed: supprimer, child: const Text('Supprimer')),
        ],
      ),
    );
  }
}
