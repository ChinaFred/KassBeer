import 'package:brewing/brewing.dart' show FermentationPoint;
import 'package:flutter/material.dart';

import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import 'legende_courbe.dart';
import 'plage_levure.dart';
import 'trace_courbe.dart';

/// Nombre minimal de densités pour afficher la courbe, densité initiale du
/// jour de brassage comprise.
const kCourbeDensitesMin = 2;

/// Aucune densité prévue : le calcul de la recette ne les donne pas.
const kDensitesPrevuesIndisponibles =
    'Densités prévues indisponibles : le calcul de la recette est impossible.';

/// Une seule des deux densités prévues manque.
const kDensiteInitialePrevueIndisponible =
    'Densité initiale prévue indisponible : le calcul de la recette ne la '
    'donne pas.';
const kDensiteFinalePrevueIndisponible =
    'Densité finale prévue indisponible : le calcul de la recette ne la '
    'donne pas.';

/// La levure [nom] ne se résout à aucune entrée de la Bibliothèque.
String levureAbsenteBibliotheque(String nom) =>
    'Levure « ${nom.trim()} » absente de la Bibliothèque : pas de température '
    'visée.';

/// L'entrée de la levure [nom] n'a pas de plage de température complète.
String levureSansPlage(String nom) =>
    'Levure « ${nom.trim()} » sans plage de température dans la '
    'Bibliothèque : pas de température visée.';

/// « Plage de la levure (18 à 22 °C) ».
String libellePlageLevure(PlageLevureConnue p) =>
    'Plage de la levure (${formatNombre(p.minimum, decimales: 1)} à '
    '${formatCelsius(p.maximum)})';

/// Hauteur du tracé pour un texte à 100 %.
const double _hauteurTrace = 180;

/// Résumé lu par un lecteur d'écran, équivalent de la courbe (ADR-004, condition 4) :
/// « Densité de 1058,0 à 1014,0 en 12 jours. », puis la température si elle existe.
///
/// [initiale] et [finale] : densités prévues, ajoutées au résumé
/// (« Initiale prévue 1063,0, finale prévue 1012,0. »).
String resumeCourbe(
  List<FermentationPoint> points, {
  double? initiale,
  double? finale,
  PlageLevureConnue? plage,
}) {
  final densites = [
    for (final p in points)
      if (p.gravity != null) p,
  ];
  final premier = densites.first;
  final dernier = densites.last;
  final jours = dernier.dayNumber - premier.dayNumber;
  final phrases = [
    'Densité de ${formatDensite(premier.gravity!)} à '
        '${formatDensite(dernier.gravity!)} en $jours '
        '${jours > 1 ? 'jours' : 'jour'}.',
  ];
  final temperatures = [
    for (final p in points)
      if (p.temperature != null) p.temperature!,
  ];
  if (temperatures.isNotEmpty) {
    temperatures.sort();
    phrases.add(
      temperatures.first == temperatures.last
          ? 'Température ${formatCelsius(temperatures.first)}.'
          : 'Température entre ${formatCelsius(temperatures.first)} et '
                '${formatCelsius(temperatures.last)}.',
    );
  }
  final prevues = [
    if (initiale != null) 'initiale prévue ${formatDensite(initiale)}',
    if (finale != null) 'finale prévue ${formatDensite(finale)}',
  ];
  if (prevues.isNotEmpty) {
    final texte = prevues.join(', ');
    phrases.add('${texte[0].toUpperCase()}${texte.substring(1)}.');
  }
  if (plage != null) {
    phrases.add(
      'Plage de la levure ${formatNombre(plage.minimum, decimales: 1)} à '
      '${formatCelsius(plage.maximum)}.',
    );
  }
  return phrases.join(' ');
}

/// « Finale prévue 1012,0 · écart +8,0 pts » : [ecart] en points, calculé par
/// `brewing/` (`gravityGapPoints`) ; sans écart, le libellé et la valeur.
String infoBullePrevue(String libelle, double prevue, double? ecart) {
  final texte = '$libelle ${formatDensite(prevue)}';
  if (ecart == null) return texte;
  return '$texte · écart ${formatEcart(ecart)}';
}

/// Courbe du relevé : affichée à partir de deux densités (FE7 pour l'abscisse).
///
/// La légende est écrite ; la liste sous le tracé reste l'équivalent complet pour un
/// lecteur d'écran.
class CourbeFermentation extends StatelessWidget {
  const CourbeFermentation({
    super.key,
    required this.points,
    this.densiteInitialePrevue,
    this.densiteFinalePrevue,
    this.ecartInitiale,
    this.ecartFinale,
    this.plageLevure,
    this.libelleDate = formatJourHeure,
  });

  /// Points de `fermentationSeries`, triés par heure de mesure : densité
  /// initiale du jour de brassage, puis relevés.
  final List<FermentationPoint> points;

  /// Densités prévues par `computeRecipe`, ou nulles : aucune pente inventée,
  /// une ligne horizontale chacune.
  final double? densiteInitialePrevue;
  final double? densiteFinalePrevue;

  /// Écarts en points de `brewing/` : densité initiale retenue du jour sur
  /// l'initiale prévue, dernière densité mesurée sur la finale prévue.
  final double? ecartInitiale;
  final double? ecartFinale;

  /// Plage de la levure lue dans la Bibliothèque ; `null` : rien à dire
  /// (recette sans levure, lecture en cours, hors ligne sans copie).
  final EtatPlageLevure? plageLevure;

  /// Date d'un point dans l'info-bulle : « sam. 15 nov. 18:30 », ou la date
  /// d'un relevé importé sans heure ou sans date (`dateDeReleve`).
  final String Function(DateTime) libelleDate;

  @override
  Widget build(BuildContext context) {
    final densites = [
      for (final p in points)
        if (p.gravity != null) p.gravity!,
    ];
    if (densites.length < kCourbeDensitesMin) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasTemperature = points.any((p) => p.temperature != null);
    final echelle = MediaQuery.textScalerOf(context).scale(1);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final initiale = densiteInitialePrevue;
    final finale = densiteFinalePrevue;
    final prevues = [
      if (initiale != null)
        LignePrevue(
          valeur: initiale,
          infoBulle: infoBullePrevue(
            'Initiale prévue',
            initiale,
            ecartInitiale,
          ),
        ),
      if (finale != null)
        LignePrevue(
          valeur: finale,
          infoBulle: infoBullePrevue('Finale prévue', finale, ecartFinale),
        ),
    ];
    final etatPlage = plageLevure;
    final plage = etatPlage is PlageLevureConnue ? etatPlage : null;
    final manque = initiale == null && finale == null
        ? kDensitesPrevuesIndisponibles
        : initiale == null
        ? kDensiteInitialePrevueIndisponible
        : finale == null
        ? kDensiteFinalePrevueIndisponible
        : null;
    final levure = switch (etatPlage) {
      LevureAbsenteDeLaBibliotheque(:final nom) => levureAbsenteBibliotheque(
        nom,
      ),
      LevureSansPlage(:final nom) => levureSansPlage(nom),
      PlageLevureConnue() || null => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: resumeCourbe(
              points,
              initiale: initiale,
              finale: finale,
              plage: plage,
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      LegendeCourbe(
                        texte: 'Densité mesurée',
                        couleur: scheme.primary,
                        style: muted,
                      ),
                      if (hasTemperature)
                        LegendeCourbe(
                          texte: 'Température mesurée (°C)',
                          couleur: scheme.tertiary,
                          motif: kMotifTemperature,
                          style: muted,
                        ),
                      if (initiale != null)
                        LegendeCourbe(
                          texte: 'Initiale prévue ${formatDensite(initiale)}',
                          couleur: scheme.onSurfaceVariant,
                          motif: kMotifPrevu,
                          style: muted,
                        ),
                      if (finale != null)
                        LegendeCourbe(
                          texte: 'Finale prévue ${formatDensite(finale)}',
                          couleur: scheme.onSurfaceVariant,
                          motif: kMotifPrevu,
                          style: muted,
                        ),
                      if (plage != null)
                        LegendeCourbe(
                          texte: libellePlageLevure(plage),
                          couleur: scheme.tertiary.withValues(alpha: 0.12),
                          echantillon: EchantillonLegende.aplat,
                          contour: scheme.tertiary,
                          style: muted,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: _hauteurTrace * (echelle < 1 ? 1 : echelle),
                    child: TraceCourbe(
                      points: points,
                      densitesPrevues: prevues,
                      plageTemperature: plage == null
                          ? null
                          : PlageTrace(min: plage.minimum, max: plage.maximum),
                      libelleDate: (p) => libelleDate(p.measuredAt),
                      libelleDensite: formatDensite,
                      libelleTemperature: formatCelsius,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (manque != null) ...[
            const SizedBox(height: 8),
            TexteAbsent(manque),
          ],
          if (levure != null) ...[
            const SizedBox(height: 8),
            TexteAbsent(levure),
          ],
        ],
      ),
    );
  }
}
