import 'dart:math' as math;

import 'package:brewing/brewing.dart' show FermentationPoint;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Motif du trait de la température : la série se distingue sans la couleur.
const kMotifTemperature = [6, 4];

/// Seul fichier qui importe `fl_chart` (ADR-004, P18). Aucun type du paquet ne sort de
/// ce fichier : abandonner le paquet ne change que lui.
class TraceCourbe extends StatelessWidget {
  const TraceCourbe({
    super.key,
    required this.points,
    required this.libelleDate,
    required this.libelleDensite,
    required this.libelleTemperature,
  });

  /// Points de la série, triés par heure de mesure.
  final List<FermentationPoint> points;

  final String Function(FermentationPoint) libelleDate;
  final String Function(double sg) libelleDensite;
  final String Function(double celsius) libelleTemperature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styleAxe = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final echelle = MediaQuery.textScalerOf(context).scale(1);

    final densites = [
      for (final p in points)
        if (p.gravity != null) p,
    ];
    final temperatures = [
      for (final p in points)
        if (p.temperature != null) p,
    ];
    final bornes = _Bornes.de(densites);
    final recalage = temperatures.isEmpty
        ? null
        : _Recalage(temperatures, bornes);
    final minX = points.map((p) => p.dayOffset).reduce(math.min);
    final maxX = points.map((p) => p.dayOffset).reduce(math.max);
    final etenduX = maxX - minX;
    final margeX = etenduX < 1 ? 0.5 : etenduX * 0.04;
    final bas = minX - margeX;
    final haut = maxX + margeX;
    // Au moins un jour entre deux libellés : chaque jour paraît une seule fois.
    final pasX = math.max(1.0, _pas((haut - bas) / 4));

    FlDotPainter point(Color couleur) => FlDotCirclePainter(
      color: couleur,
      radius: 3,
      strokeColor: couleur,
      strokeWidth: 0,
    );

    return LineChart(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      LineChartData(
        minX: bas,
        maxX: haut,
        minY: bornes.min,
        maxY: bornes.max,
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: scheme.outline),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outlineVariant, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: pasX,
              minIncluded: false,
              maxIncluded: false,
              reservedSize: 28 * echelle,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text('J+${value.floor()}', style: styleAxe),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: bornes.pas,
              minIncluded: false,
              maxIncluded: false,
              reservedSize: 52 * echelle,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(libelleDensite(value / 1000), style: styleAxe),
              ),
            ),
          ),
          rightTitles: recalage == null
              ? const AxisTitles()
              : AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: bornes.pas,
                    minIncluded: false,
                    maxIncluded: false,
                    reservedSize: 52 * echelle,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        libelleTemperature(recalage.temperature(value)),
                        style: styleAxe,
                      ),
                    ),
                  ),
                ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final p in densites) FlSpot(p.dayOffset, p.gravity! * 1000),
            ],
            color: scheme.primary,
            barWidth: 2,
            dotData: FlDotData(
              getDotPainter: (_, _, _, _) => point(scheme.primary),
            ),
          ),
          if (recalage != null)
            LineChartBarData(
              spots: [
                for (final p in temperatures)
                  FlSpot(p.dayOffset, recalage.densite(p.temperature!)),
              ],
              color: scheme.tertiary,
              barWidth: 2,
              dashArray: kMotifTemperature,
              dotData: FlDotData(
                getDotPainter: (_, _, _, _) => point(scheme.tertiary),
              ),
            ),
        ],
        lineTouchData: LineTouchData(
          getTouchedSpotIndicator: (barre, indices) => [
            for (final _ in indices)
              TouchedSpotIndicatorData(
                FlLine(color: scheme.outline, strokeWidth: 1),
                FlDotData(
                  getDotPainter: (_, _, _, _) => point(scheme.onSurface),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 220,
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (touches) => [
              for (final (i, touche) in touches.indexed)
                i == 0
                    ? _infoBulle(
                        touche.barIndex == 0
                            ? densites[touche.spotIndex]
                            : temperatures[touche.spotIndex],
                        TextStyle(color: scheme.onInverseSurface),
                      )
                    : null,
            ],
          ),
        ),
      ),
    );
  }

  /// Une info-bulle par touche : date, densité, température.
  LineTooltipItem _infoBulle(FermentationPoint p, TextStyle style) {
    final gravity = p.gravity;
    final temperature = p.temperature;
    return LineTooltipItem(
      [
        libelleDate(p),
        if (gravity != null) 'Densité ${libelleDensite(gravity)}',
        if (temperature != null)
          'Température ${libelleTemperature(temperature)}',
      ].join('\n'),
      style,
      textAlign: TextAlign.left,
    );
  }
}

/// Pas d'axe rond proche de [brut] : 1, 2 ou 5 × 10^n.
double _pas(double brut) {
  final borne = brut <= 0 ? 1.0 : brut;
  final puissance = math
      .pow(10, (math.log(borne) / math.ln10).floor())
      .toDouble();
  final reduit = borne / puissance;
  final multiple = reduit <= 1
      ? 1.0
      : reduit <= 2
      ? 2.0
      : reduit <= 5
      ? 5.0
      : 10.0;
  return multiple * puissance;
}

/// Bornes de l'axe des densités, en échelle × 1000.
class _Bornes {
  const _Bornes(this.min, this.max, this.pas);

  factory _Bornes.de(List<FermentationPoint> densites) {
    final valeurs = densites.map((p) => p.gravity! * 1000).toList();
    final bas = valeurs.reduce(math.min);
    final haut = valeurs.reduce(math.max);
    final etendu = haut - bas;
    final marge = etendu < 2 ? 2.0 : etendu * 0.15;
    final pas = _pas((etendu + marge * 2) / 4);
    return _Bornes(bas - marge, haut + marge, pas);
  }

  final double min;
  final double max;
  final double pas;
}

/// Recale la température sur l'échelle des densités. Affichage seul : aucune valeur
/// recalée n'est stockée (ADR-004).
class _Recalage {
  _Recalage(List<FermentationPoint> temperatures, this.bornes) {
    final valeurs = temperatures.map((p) => p.temperature!).toList();
    final bas = valeurs.reduce(math.min);
    final haut = valeurs.reduce(math.max);
    final etendu = haut - bas;
    final marge = etendu < 2 ? 1.0 : etendu * 0.15;
    _min = bas - marge;
    _max = haut + marge;
  }

  final _Bornes bornes;
  late final double _min;
  late final double _max;

  double densite(double temperature) =>
      bornes.min +
      (temperature - _min) / (_max - _min) * (bornes.max - bornes.min);

  double temperature(double densite) =>
      _min + (densite - bornes.min) / (bornes.max - bornes.min) * (_max - _min);
}
