import 'package:brewing/brewing.dart'
    show
        BrewDayTemperatureSeries,
        BrewingInputException,
        DensiteRetenue,
        TargetTemperaturePoint,
        brewDayTemperatureSeries;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../brews/domain/brew.dart';
import '../../brews/domain/brew_event.dart';
import '../../brews/domain/densites.dart';
import '../../brews/presentation/brews_providers.dart';
import '../../brews/presentation/legende_courbe.dart';
import '../../brews/presentation/saisie_densite.dart';
import '../../brews/presentation/trace_courbe.dart';
import '../domain/plan_du_jour.dart';
import 'chronologie_jour.dart';

/// Courbe du jour de brassage : températures visées (plan de départ et
/// recalculée, calculées par `brewing/`), températures et densités mesurées de
/// la journée 1, densité initiale prévue. Rien n'est lu ni écrit : la courbe se
/// dérive du plan déjà calculé et des événements déjà lus (P2).

/// Hauteur du tracé pour un texte à 100 %.
const double kHauteurCourbeBrassage = 220;

const kCourbeSansVisee = 'Aucune étape n\'a de température visée.';
const kCourbeSansMesure =
    'Aucune température mesurée. Saisissez-en par le bouton Mesure.';
const kCourbeSansMesureFiche = 'Aucune température mesurée.';
const kCourbeVide = 'Aucune température visée ni mesurée.';
const kCourbeChronologieImpossible =
    'Courbe indisponible : la chronologie ne peut pas être calculée.';
const kCourbeValeurRefusee =
    'Courbe indisponible : une valeur enregistrée est refusée.';

/// Mesure de densité et sa valeur retenue, calculée par `brewing/`.
typedef DensiteMesuree = ({BrewEvent event, DensiteRetenue densite});

/// Données de la courbe, dérivées d'un plan de la journée de brassage.
@immutable
class DonneesCourbeBrassage {
  const DonneesCourbeBrassage({
    required this.visees,
    required this.lignes,
    required this.temperatures,
    required this.densites,
    required this.densiteInitialePrevue,
  });

  /// Séries des températures visées, calculées par `brewing/` (P3).
  final BrewDayTemperatureSeries visees;

  /// Étapes de la journée, dans l'ordre de la chronologie.
  final List<LigneJour> lignes;

  /// Températures et densités mesurées de la journée 1, par heure croissante.
  /// Une densité porte sa valeur retenue (`densiteDe`) ; une lecture qui n'en
  /// donne aucune (réfractomètre sans facteur) n'a pas de point.
  final List<BrewEvent> temperatures;
  final List<DensiteMesuree> densites;

  /// Densité initiale prévue (`computeRecipe`), ou nulle si elle manque.
  final double? densiteInitialePrevue;

  bool get aDesVisees =>
      visees.recomputed.isNotEmpty || visees.planned.isNotEmpty;

  bool get aDesTemperatures => temperatures.isNotEmpty;

  /// Nom de l'étape d'une mesure, ou `null` pour une mesure sans étape.
  String? etapeDe(BrewEvent e) {
    for (final l in lignes) {
      if (l.step.key == e.stepKey) return l.step.name;
    }
    return null;
  }
}

/// Données de la courbe pour [plan], le plan de la journée de brassage.
///
/// Lève `BrewingInputException` si `brewing/` refuse une valeur.
DonneesCourbeBrassage donneesCourbeBrassage(
  PlanDuJour plan, {
  required double? densiteInitialePrevue,
}) {
  final visees = brewDayTemperatureSeries(
    steps: [for (final l in plan.lignes) l.step.toPlanned()],
    targetCelsius: [for (final l in plan.lignes) l.step.tempC],
    schedule: [for (final l in plan.lignes) l.schedule],
  );
  final saisies = [
    for (final l in plan.lignes) ...l.mesures,
    ...plan.mesuresSansEtape,
  ]..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  bool mesure(BrewEvent e, MeasureType type) =>
      e.kind == BrewEventKind.measurement &&
      e.measureType == type &&
      e.value != null &&
      !e.isFermentation;
  return DonneesCourbeBrassage(
    visees: visees,
    lignes: plan.lignes,
    temperatures: [
      for (final e in saisies)
        if (mesure(e, MeasureType.temperature)) e,
    ],
    // Jour de brassage : aucune correction de l'alcool, la densité initiale
    // n'est pas lue.
    densites: [
      for (final e in saisies)
        if (e.isGravity && !e.isFermentation) (event: e, densite: densiteDe(e)),
    ].where((d) => d.densite.sg != null).toList(),
    densiteInitialePrevue: densiteInitialePrevue,
  );
}

String _plage(List<double> valeurs, String Function(double) format) {
  final tri = [...valeurs]..sort();
  return tri.first == tri.last
      ? format(tri.first)
      : 'de ${format(tri.first)} à ${format(tri.last)}';
}

/// Résumé lu par un lecteur d'écran, équivalent de la courbe (ADR-004).
String resumeCourbeBrassage(DonneesCourbeBrassage d) {
  final phrases = ['Températures du brassage.'];
  final visees = [...d.visees.recomputed, ...d.visees.planned];
  if (visees.isNotEmpty) {
    final valeurs = [
      for (final l in visees)
        for (final p in l) p.celsius,
    ];
    final etapes = {
      for (final l in visees)
        for (final p in l) p.stepIndex,
    }.length;
    phrases.add(
      'Visée ${_plage(valeurs, formatCelsius)} sur ${formatEtapes(etapes)}.',
    );
  }
  final mesurees = [for (final e in d.temperatures) e.value!];
  if (mesurees.isNotEmpty) {
    final n = mesurees.length;
    phrases.add(
      '$n température${n > 1 ? 's' : ''} mesurée${n > 1 ? 's' : ''}, '
      '${_plage(mesurees, formatCelsius)}.',
    );
  }
  final retard = d.visees.delay;
  if (retard != null && retard.inMinutes > 0) {
    phrases.add('Retard de ${formatDuree(retard)} sur le plan de départ.');
  }
  final prevue = d.densiteInitialePrevue;
  final densites = [
    for (final m in d.densites)
      '${valeurDensite(m.event, m.densite)}'
          '${m.densite.estCorrigee ? ' corrigée' : ''}'
          ' à ${formatHeure(m.event.measuredAt)}',
  ];
  if (densites.isNotEmpty) {
    phrases.add(
      'Densité ${densites.join(', ')}'
      '${prevue == null ? '' : ' ; initiale prévue ${formatDensite(prevue)}'}.',
    );
  } else if (prevue != null) {
    phrases.add('Densité initiale prévue ${formatDensite(prevue)}.');
  }
  return phrases.join(' ');
}

/// Courbe du jour de brassage. [plan] : plan de la journée de brassage, nul
/// si `brewing/` en a refusé le calcul. [surFiche] : fiche du brassin, où la
/// courbe ne paraît qu'à partir du premier début d'étape et se masque sans
/// température ; sinon écran du jour.
class CourbeBrassage extends ConsumerWidget {
  const CourbeBrassage({
    super.key,
    required this.brew,
    required this.plan,
    required this.densiteInitialePrevue,
    this.surFiche = false,
  });

  final Brew brew;
  final PlanDuJour? plan;
  final double? densiteInitialePrevue;
  final bool surFiche;

  /// Sous-titre de la courbe sur la fiche.
  static const titreFiche = 'Températures du brassage';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contenu = _contenu(ref);
    if (!surFiche || contenu == null) return contenu ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Semantics(
            header: true,
            child: Text(
              titreFiche,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        contenu,
        const SizedBox(height: 16),
      ],
    );
  }

  /// Courbe ou état ; `null` quand la fiche ne montre rien.
  Widget? _contenu(WidgetRef ref) {
    // Fiche : la chronologie affiche déjà un déroulé illisible ou un calcul
    // refusé ; rien ne paraît avant le premier début d'étape.
    final illisible = messageDerouleIllisible(brew.deroule);
    if (illisible != null) return surFiche ? null : TexteAbsent(illisible);
    final p = plan;
    if (p == null) {
      return surFiche ? null : const TexteAbsent(kCourbeChronologieImpossible);
    }
    if (surFiche && !p.lignes.any((l) => l.record?.startedAt != null)) {
      return null;
    }
    final DonneesCourbeBrassage d;
    try {
      d = donneesCourbeBrassage(
        p,
        densiteInitialePrevue: densiteInitialePrevue,
      );
    } on BrewingInputException catch (error, stackTrace) {
      if (ref
          .read(planReportsProvider)
          .add('courbe|${brew.id}|${error.field}')) {
        ref
            .read(errorReportServiceProvider)
            .reportError(
              feature: 'brew_day.temperature_curve',
              error: error,
              stackTrace: stackTrace,
              context: 'brews/${brew.id} : valeur refusée ${error.field}',
            );
      }
      return const TexteAbsent(kCourbeValeurRefusee);
    }
    if (surFiche && d.visees.origin == null) return null;
    if (!d.aDesVisees && !d.aDesTemperatures) {
      return surFiche ? null : const TexteAbsent(kCourbeVide);
    }
    return _Courbe(donnees: d, surFiche: surFiche);
  }
}

class _Courbe extends StatelessWidget {
  const _Courbe({required this.donnees, required this.surFiche});

  final DonneesCourbeBrassage donnees;
  final bool surFiche;

  String _nomEtape(int index) => donnees.lignes[index].step.name;

  List<PointCourbe> _points(
    List<TargetTemperaturePoint> l, {
    required bool plan,
  }) {
    final debuts = donnees.visees.plannedStarts;
    return [
      for (final p in l)
        PointCourbe(
          at: p.at,
          valeur: p.celsius,
          infoBulle: [
            '${formatHeure(p.at)} · ${_nomEtape(p.stepIndex)}',
            plan
                ? 'Visée ${formatCelsius(p.celsius)} · plan de départ'
                : debuts == null
                ? 'Visée ${formatCelsius(p.celsius)}'
                : 'Visée ${formatCelsius(p.celsius)} · prévue à '
                      '${formatHeure(debuts[p.stepIndex])}',
          ].join('\n'),
        ),
    ];
  }

  String _infoMesure(BrewEvent e, String valeur) => [
    '${formatHeure(e.measuredAt)} · ${donnees.etapeDe(e) ?? 'Sans étape'}',
    valeur,
    if (e.hasPendingWrites) 'En attente du réseau',
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final echelle = MediaQuery.textScalerOf(context).scale(1);
    final d = donnees;
    final prevue = d.densiteInitialePrevue;
    final texteVide = !d.aDesVisees
        ? kCourbeSansVisee
        : !d.aDesTemperatures
        ? (surFiche ? kCourbeSansMesureFiche : kCourbeSansMesure)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          label: resumeCourbeBrassage(d),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (d.visees.recomputed.isNotEmpty)
                      LegendeCourbe(
                        texte: 'Visée (recalculée)',
                        couleur: scheme.primary,
                        style: muted,
                      ),
                    if (d.visees.planned.isNotEmpty)
                      LegendeCourbe(
                        texte: 'Visée (plan de départ)',
                        couleur: scheme.onSurfaceVariant,
                        motif: kMotifPlanDeDepart,
                        style: muted,
                      ),
                    if (d.aDesTemperatures)
                      LegendeCourbe(
                        texte: 'Température mesurée',
                        couleur: scheme.tertiary,
                        echantillon: EchantillonLegende.disque,
                        style: muted,
                      ),
                    if (d.densites.isNotEmpty)
                      LegendeCourbe(
                        texte: 'Densité mesurée',
                        couleur: scheme.secondary,
                        echantillon: EchantillonLegende.losange,
                        style: muted,
                      ),
                    if (prevue != null)
                      LegendeCourbe(
                        texte:
                            'Densité initiale prévue ${formatDensite(prevue)}',
                        couleur: scheme.secondary,
                        motif: kMotifPrevu,
                        style: muted,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: kHauteurCourbeBrassage * (echelle < 1 ? 1 : echelle),
                  child: TraceCourbeBrassage(
                    viseeRecalculee: [
                      for (final l in d.visees.recomputed)
                        _points(l, plan: false),
                    ],
                    viseePlan: [
                      for (final l in d.visees.planned) _points(l, plan: true),
                    ],
                    temperatures: [
                      for (final e in d.temperatures)
                        PointCourbe(
                          at: e.measuredAt,
                          valeur: e.value!,
                          infoBulle: _infoMesure(
                            e,
                            'Mesurée ${formatCelsius(e.value!)}',
                          ),
                        ),
                    ],
                    densites: [
                      for (final m in d.densites)
                        PointCourbe(
                          at: m.event.measuredAt,
                          valeur: m.densite.sg!,
                          infoBulle: _infoMesure(
                            m.event,
                            [
                              'Densité ${valeurDensite(m.event, m.densite)}',
                              ?complementDensite(m.event, m.densite),
                              if (prevue != null)
                                'initiale prévue ${formatDensite(prevue)}',
                            ].join(' · '),
                          ),
                        ),
                    ],
                    densitePrevue: prevue == null
                        ? null
                        : LignePrevue(
                            valeur: prevue,
                            infoBulle:
                                'Densité initiale prévue ${formatDensite(prevue)}',
                          ),
                    libelleHeure: formatHeure,
                    libelleTemperature: (c) => formatCelsius(c.roundToDouble()),
                    libelleDensite: formatDensite,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (texteVide != null) ...[
          const SizedBox(height: 8),
          TexteAbsent(texteVide),
        ],
      ],
    );
  }
}
