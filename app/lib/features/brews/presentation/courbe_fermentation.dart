import 'dart:math' as math;

import 'package:brewing/brewing.dart' show FermentationPoint;
import 'package:flutter/material.dart';

import '../../../core/presentation/formats.dart';
import 'trace_courbe.dart';

/// Nombre minimal de densités pour afficher la courbe.
const kCourbeDensitesMin = 2;

/// Hauteur du tracé pour un texte à 100 %.
const double _hauteurTrace = 180;

/// Résumé lu par un lecteur d'écran, équivalent de la courbe (ADR-004, condition 4) :
/// « Densité de 1058,0 à 1014,0 en 12 jours. », puis la température si elle existe.
String resumeCourbe(List<FermentationPoint> points) {
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
  return phrases.join(' ');
}

/// Une entrée de la légende : échantillon de trait et texte.
class _Legende extends StatelessWidget {
  const _Legende({
    required this.texte,
    required this.couleur,
    required this.style,
    this.motif,
  });

  final String texte;
  final Color couleur;
  final TextStyle? style;

  /// Longueurs alternées trait, blanc ; nul pour un trait plein.
  final List<int>? motif;

  @override
  Widget build(BuildContext context) {
    final echelle = MediaQuery.textScalerOf(context).scale(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(24 * echelle, 2 * echelle),
          painter: _EchantillonTrait(couleur, motif, echelle),
        ),
        const SizedBox(width: 6),
        Text(texte, style: style),
      ],
    );
  }
}

/// Dessine l'échantillon avec la couleur et le motif de la courbe.
class _EchantillonTrait extends CustomPainter {
  const _EchantillonTrait(this.couleur, this.motif, this.echelle);

  final Color couleur;
  final List<int>? motif;
  final double echelle;

  @override
  void paint(Canvas canvas, Size size) {
    final trait = Paint()
      ..color = couleur
      ..strokeWidth = size.height;
    final y = size.height / 2;
    final m = motif;
    if (m == null) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), trait);
      return;
    }
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final longueur = m[i % m.length] * echelle;
      if (i.isEven) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + longueur, size.width), y),
          trait,
        );
      }
      x += longueur;
      i++;
    }
  }

  @override
  bool shouldRepaint(_EchantillonTrait old) =>
      old.couleur != couleur || old.motif != motif || old.echelle != echelle;
}

/// Courbe du relevé : affichée à partir de deux densités (FE7 pour l'abscisse).
///
/// La légende est écrite ; la liste sous le tracé reste l'équivalent complet pour un
/// lecteur d'écran.
class CourbeFermentation extends StatelessWidget {
  const CourbeFermentation({super.key, required this.points});

  /// Points de `fermentationSeries`, triés par heure de mesure.
  final List<FermentationPoint> points;

  @override
  Widget build(BuildContext context) {
    final densites = points.where((p) => p.gravity != null).length;
    if (densites < kCourbeDensitesMin) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hasTemperature = points.any((p) => p.temperature != null);
    final echelle = MediaQuery.textScalerOf(context).scale(1);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        container: true,
        label: resumeCourbe(points),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                children: [
                  _Legende(
                    texte: 'Densité',
                    couleur: theme.colorScheme.primary,
                    style: muted,
                  ),
                  if (hasTemperature)
                    _Legende(
                      texte: 'Température (°C)',
                      couleur: theme.colorScheme.tertiary,
                      motif: kMotifTemperature,
                      style: muted,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: _hauteurTrace * (echelle < 1 ? 1 : echelle),
                child: TraceCourbe(
                  points: points,
                  libelleDate: (p) => formatJourHeure(p.measuredAt),
                  libelleDensite: formatDensite,
                  libelleTemperature: formatCelsius,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
