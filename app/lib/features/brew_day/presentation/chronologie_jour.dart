import 'dart:math' as math;

import 'package:brewing/brewing.dart'
    show
        ActualDayDuration,
        ActualStepDuration,
        BrewingInputException,
        StepEvent,
        StepStatus;
import 'package:flutter/material.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/services/error_report_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../../brews/domain/deroule.dart';
import '../../brews/presentation/libelles_deroule.dart';
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

/// Texte d'un déroulé illisible (`Brew.deroule`), ou `null` s'il est lisible :
/// `process` illisible (ADR-010), ou chronologie figée d'un brassin sans
/// `process` illisible, avec sa raison.
String? messageDerouleIllisible(Deroule deroule) {
  final raison = deroule.probleme;
  if (raison == null) return null;
  return deroule.resolu
      ? kDerouleIllisible
      : 'Chronologie de ce brassin illisible : $raison.';
}

/// Texte du verrou d'écran refusé.
const kVerrouRefuse =
    'Écran : l\'appareil refuse de le garder allumé. Réglez la mise en veille.';

/// Calcule la vue de la journée [journee] de [brew] à [now] (nulle : la journée
/// de brassage). Une anomalie (fin avant le début, étape inconnue) est rapportée
/// une fois ([reported]). Une erreur de `brewing/` rend [PlanImpossible] et est
/// rapportée : l'écran affiche la panne.
PlanEvalue evaluerPlan({
  required Brew brew,
  required List<BrewEvent> events,
  required DateTime now,
  required ErrorReportService errors,
  required Set<String> reported,
  JourneeDeroulee? journee,
}) {
  try {
    final plan = PlanDuJour.calculer(
      brew: brew,
      events: events,
      now: now,
      journee: journee,
    );
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

/// Prévu et réel de la journée [journee] de [brew] et de ses étapes, d'après
/// [plan] (fiche et écran du jour) ; la ligne de durée totale ne s'affiche
/// qu'à partir d'une étape qui a un réel (`dureeJourneeReelle`). Un refus de
/// `brewing/` est rapporté une fois ([reported]) et rend `null` : les lignes
/// gardent leur durée prévue.
ActualDayDuration? evaluerDurees({
  required Brew brew,
  required JourneeDeroulee journee,
  required PlanDuJour plan,
  required ErrorReportService errors,
  required Set<String> reported,
}) {
  try {
    final durees = plan.durees(
      close: journeeClose(brew: brew, journee: journee, plan: plan),
    );
    return durees;
  } on BrewingInputException catch (error, stackTrace) {
    if (reported.add('${brew.id}|durees|${journee.key}|${error.field}')) {
      errors.reportError(
        feature: 'brews.actual_durations',
        error: error,
        stackTrace: stackTrace,
        context: 'brews/${brew.id} : durées réelles refusées ${error.field}',
      );
    }
    return null;
  }
}

/// Prévu et réel de chaque journée de [brew] dont une étape a début et fin, par
/// clé de journée, d'après [plans] (plan de chaque journée, même clé).
Map<String, ActualDayDuration> dureesDesJournees({
  required Brew brew,
  required Map<String, PlanEvalue> plans,
  required ErrorReportService errors,
  required Set<String> reported,
}) => {
  for (final j in brew.deroule.journees)
    if (plans[j.key] case PlanObtenu(:final plan))
      j.key: ?evaluerDurees(
        brew: brew,
        journee: j,
        plan: plan,
        errors: errors,
        reported: reported,
      ),
};

/// Texte de l'état d'une étape, jamais la couleur seule. [nonNotee] : étape
/// sans début d'un brassin importé d'une fiche (« Non notée » au lieu de « Non
/// faite »).
String libelleEtat(StepStatus status, {bool nonNotee = false}) =>
    switch (status) {
      StepStatus.done => 'Terminée',
      StepStatus.running => 'En cours',
      StepStatus.pending => 'À venir',
      StepStatus.skipped => 'Sautée',
      StepStatus.notDone => nonNotee ? 'Non notée' : 'Non faite',
    };

IconData iconeEtat(StepStatus status, {bool nonNotee = false}) =>
    switch (status) {
      StepStatus.done => Icons.check_circle_outline,
      StepStatus.running => Icons.play_circle_outline,
      StepStatus.pending => Icons.schedule,
      StepStatus.skipped => Icons.skip_next,
      StepStatus.notDone =>
        nonNotee ? Icons.help_outline : Icons.remove_circle_outline,
    };

/// Couleur de l'icône d'état : fait en succès, en cours en `primary`, le reste
/// (à venir, sautée, non faite, non notée) en `onSurfaceVariant`. Le libellé
/// ([libelleEtat]) dit l'état, la couleur ne fait que le souligner.
Color couleurEtat(BuildContext context, StepStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    StepStatus.done => CouleursEtat.of(context).succes,
    StepStatus.running => scheme.primary,
    StepStatus.pending ||
    StepStatus.skipped ||
    StepStatus.notDone => scheme.onSurfaceVariant,
  };
}

/// État affiché d'une étape : dans une journée close ([close]), une étape
/// restée en cours est terminée ; sinon l'état de `recomputeSchedule`.
StepStatus statutAffiche(StepStatus status, {required bool close}) =>
    close && status == StepStatus.running ? StepStatus.done : status;

/// Colonne d'heure d'une ligne, affichée et lue :
/// - début noté : « 12:10 → 12:57 » (fin retenue par `brewing/`, ou fin
///   enregistrée), sinon « 12:10 » (« commencée à 12 h 10 ») ;
/// - début estimé à l'import : « vers 13:02 » ;
/// - étape non notée d'un brassin importé ([importe]) : heure théorique dérivée
///   par `brewing/`, jamais écrite, « vers 12:57 » ;
/// - à venir : heure attendue, sans « vers » (vide si les heures sont
///   incohérentes) ; sautée ou non faite : « — ».
TexteDuree heureDeLigne(
  LigneJour ligne,
  PlanDuJour plan, {
  ActualStepDuration? reelle,
  bool importe = false,
}) {
  final record = ligne.record;
  final started = record?.startedAt;
  if (started != null) {
    if (record!.startEstimated) {
      return (
        affiche: 'vers ${formatHeure(started)}',
        lu: 'heure estimée vers ${heureParlee(started)}',
      );
    }
    final ended = reelle?.end ?? record.endedAt;
    return ended == null
        ? (
            affiche: formatHeure(started),
            lu: 'commencée à ${heureParlee(started)}',
          )
        : (
            affiche: '${formatHeure(started)} → ${formatHeure(ended)}',
            lu: 'de ${heureParlee(started)} à ${heureParlee(ended)}',
          );
  }
  final theorique = reelle?.theoreticalStart;
  if (importe && ligne.status == StepStatus.notDone && theorique != null) {
    return (
      affiche: 'vers ${formatHeure(theorique)}',
      lu: 'heure prévue vers ${heureParlee(theorique)}',
    );
  }
  if (ligne.status != StepStatus.pending || !plan.horairesFiables) {
    return (affiche: '—', lu: 'sans heure');
  }
  final attendue = ligne.schedule.expectedStart;
  return (affiche: formatHeure(attendue), lu: heureParlee(attendue));
}

/// Mesure ou note d'une étape, en une ligne : « 12:10 · 67,5 °C · note » ;
/// heure estimée à l'import : « vers 12:10 · 67,5 °C ».
String libelleSaisie(BrewEvent e) {
  final type = e.measureType;
  final value = e.value;
  return [
    e.timeEstimated
        ? 'vers ${formatHeure(e.measuredAt)}'
        : formatHeure(e.measuredAt),
    if (type != null && value != null) libelleMesure(type, value),
    if (e.note != null) e.note!,
  ].join(' · ');
}

/// Marge horizontale d'une ligne d'étape.
const double _kMargeLigne = 8;

/// Largeur de la colonne d'heure pour une chronologie large de [largeur] et une
/// échelle du texte [echelle] : [kChronologieHeureWidth] × [echelle], bornée à
/// [kChronologieHeureMaxFraction] de [largeur], jamais sous
/// [kChronologieHeureWidth].
double largeurColonneHeure(double largeur, double echelle) => math.max(
  kChronologieHeureWidth,
  math.min(
    kChronologieHeureWidth * echelle,
    largeur * kChronologieHeureMaxFraction,
  ),
);

/// Liste des étapes d'un brassin, sur la fiche et l'écran du jour.
class ChronologieJour extends StatelessWidget {
  const ChronologieJour({
    super.key,
    required this.plan,
    this.onTapLigne,
    this.onTapSaisie,
    this.onSupprimerDoublon,
    this.sansEtape = true,
    this.durees,
    this.importe = false,
    this.close = false,
  });

  final PlanDuJour plan;

  /// Prévu et réel de la journée et de ses étapes ([evaluerDurees]) : réel,
  /// écart de durée, écart de début, heure théorique. Nul si le calcul est
  /// refusé : chaque ligne garde sa durée prévue.
  final ActualDayDuration? durees;

  /// Brassin importé d'une fiche Excel (`Brew.importeDUneFiche`) : une étape
  /// sans début est « Non notée », à son heure théorique.
  final bool importe;

  /// Journée close (`journeeClose`) : une étape restée « en cours » s'y affiche
  /// « Terminée », sans fond (règle d'affichage, [statutAffiche]).
  final bool close;

  /// Affiche les mesures « Sans étape ». Faux sur la fiche pour une journée 2 ou
  /// suivante : ces mesures sont des relevés, déjà dans le relevé de
  /// fermentation (ADR-010).
  final bool sansEtape;

  /// `null` en lecture seule.
  final void Function(LigneJour ligne)? onTapLigne;
  final void Function(BrewEvent event)? onTapSaisie;

  /// Supprime un début en double ; `null` pour un autre membre.
  final void Function(StepEvent event)? onSupprimerDoublon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textSize = StylesJourDeBrassage.of(context).chronologie;
    final etapes = durees?.steps;
    final reelles = etapes != null && etapes.length == plan.lignes.length
        ? etapes
        : null;
    final echelle = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) => _colonne(
        theme,
        textSize,
        reelles,
        largeurColonneHeure(constraints.maxWidth, echelle),
        WindowSize.of(constraints.maxWidth) == WindowSize.expanded,
      ),
    );
  }

  Widget _colonne(
    ThemeData theme,
    double textSize,
    List<ActualStepDuration>? reelles,
    double heure,
    bool large,
  ) {
    // Mesures, notes et débuts en double : alignés sur la fin de la colonne
    // d'heure.
    final retrait = _kMargeLigne + heure;
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
        for (final (i, l) in plan.lignes.indexed) ...[
          _Ligne(
            ligne: l,
            heure: heureDeLigne(l, plan, reelle: reelles?[i], importe: importe),
            reelle: reelles?[i],
            statut: statutAffiche(l.status, close: close),
            nonNotee: importe && l.status == StepStatus.notDone,
            large: large,
            textSize: textSize,
            largeurHeure: heure,
            onTap: onTapLigne == null ? null : () => onTapLigne!(l),
          ),
          for (final d in l.doublons)
            _Doublon(
              event: d,
              retrait: retrait,
              onSupprimer: onSupprimerDoublon == null
                  ? null
                  : () => onSupprimerDoublon!(d),
            ),
          for (final s in l.mesures)
            _Saisie(
              event: s,
              retrait: retrait,
              onTap: onTapSaisie == null ? null : () => onTapSaisie!(s),
            ),
        ],
        if (sansEtape && plan.mesuresSansEtape.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text('Sans étape', style: theme.textTheme.titleSmall),
          ),
        if (sansEtape)
          for (final s in plan.mesuresSansEtape)
            _Saisie(
              event: s,
              retrait: retrait,
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
    required this.reelle,
    required this.statut,
    required this.nonNotee,
    required this.large,
    required this.textSize,
    required this.largeurHeure,
    required this.onTap,
  });

  final LigneJour ligne;
  final TexteDuree heure;

  /// Prévu et réel de l'étape, ou nul : durée prévue seule.
  final ActualStepDuration? reelle;

  /// État affiché ([statutAffiche]).
  final StepStatus statut;

  /// Étape sans début d'un brassin importé : « Non notée ».
  final bool nonNotee;

  /// Grand écran : l'écart de début rejoint la deuxième ligne.
  final bool large;
  final double textSize;

  /// Largeur de la colonne d'heure ([largeurColonneHeure]).
  final double largeurHeure;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final running = statut == StepStatus.running;
    final action = ligne.step.durationMin == 0;
    final estimee = ligne.record?.startEstimated ?? false;
    final texte = reelle == null
        ? null
        : dureeEtapeReelle(reelle!, statut, nonNotee: nonNotee);
    final duration =
        texte?.affiche ?? (action ? 'Action' : formatDuree(ligne.duree));
    final durationLue = texte?.lu ?? duration;
    final etat = libelleEtat(statut, nonNotee: nonNotee);
    final debut = ecartDeDebut(reelle?.startDeltaMinutes);
    final details = [
      etat,
      if (estimee) 'heure estimée',
      duration,
      if (large && debut != null) debut.affiche,
    ].join(' · ');
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _kMargeLigne,
          vertical: 8,
        ),
        child: Row(
          children: [
            SizedBox(
              width: largeurHeure,
              child: Text(heure.affiche, style: TextStyle(fontSize: textSize)),
            ),
            Icon(
              iconeEtat(statut, nonNotee: nonNotee),
              size: 24,
              color: couleurEtat(context, statut),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ligne.step.name, style: TextStyle(fontSize: textSize)),
                  Text(details, style: theme.textTheme.bodyMedium),
                  if (!large && debut != null)
                    Text(debut.affiche, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final etatLu = nonNotee ? 'non notée sur la fiche' : etat.toLowerCase();
    return Semantics(
      button: onTap != null,
      label: [
        ligne.step.name,
        etatLu,
        heure.lu,
        durationLue,
        ?debut?.lu,
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      // Fond seulement pour l'étape en cours ; les autres lignes restent sur
      // le fond de la liste (Material transparent, sans couleur).
      child: Material(
        type: running ? MaterialType.canvas : MaterialType.transparency,
        color: running ? scheme.primaryContainer : null,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class _Saisie extends StatelessWidget {
  const _Saisie({
    required this.event,
    required this.retrait,
    required this.onTap,
  });

  final BrewEvent event;

  /// Retrait à gauche : fin de la colonne d'heure.
  final double retrait;
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
            padding: EdgeInsets.fromLTRB(retrait, 4, 8, 4),
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
  const _Doublon({
    required this.event,
    required this.retrait,
    required this.onSupprimer,
  });

  final StepEvent event;

  /// Retrait à gauche : fin de la colonne d'heure.
  final double retrait;
  final VoidCallback? onSupprimer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supprimer = onSupprimer;
    return Padding(
      padding: EdgeInsets.fromLTRB(retrait, 0, 8, 4),
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
