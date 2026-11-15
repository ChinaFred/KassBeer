import 'dart:math' as math;

import 'package:brewing/brewing.dart' show FermentationPoint;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Motif du trait de la température : la série se distingue sans la couleur.
const kMotifTemperature = [6, 4];

/// Motif d'une valeur prévue (densités prévues) : pointillés.
const kMotifPrevu = [2, 3];

/// Motif de la visée du plan de départ (courbe du jour de brassage).
const kMotifPlanDeDepart = [8, 4];

/// Ligne horizontale d'une valeur prévue, et son info-bulle.
class LignePrevue {
  const LignePrevue({required this.valeur, required this.infoBulle});

  /// Densité en SG décimal.
  final double valeur;
  final String infoBulle;
}

/// Seul fichier qui importe `fl_chart` (ADR-004, P18). Aucun type du paquet ne sort de
/// ce fichier : abandonner le paquet ne change que lui.
class TraceCourbe extends StatelessWidget {
  const TraceCourbe({
    super.key,
    required this.points,
    required this.libelleDate,
    required this.libelleDensite,
    required this.libelleTemperature,
    this.densitesPrevues = const [],
    this.plageTemperature,
  });

  /// Points de la série, triés par heure de mesure.
  final List<FermentationPoint> points;

  /// Plage de température de la levure, en °C : aplat `tertiary` à 12 %.
  final PlageTrace? plageTemperature;

  /// Densités prévues (initiale, finale) : une ligne horizontale pointillée
  /// chacune, sur toute la largeur du tracé.
  final List<LignePrevue> densitesPrevues;

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
    final bornes = _Bornes.de([
      for (final p in densites) p.gravity! * 1000,
      for (final l in densitesPrevues) l.valeur * 1000,
    ]);
    final plage = plageTemperature;
    final valeursT = [
      for (final p in temperatures) p.temperature!,
      if (plage != null) ...[plage.min, plage.max],
    ];
    final recalage = valeursT.isEmpty ? null : _Recalage(valeursT, bornes);
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

    return LayoutBuilder(
      builder: (context, contraintes) {
        final axeDroit = axeDroitLisible(contraintes.maxWidth, echelle);
        return LineChart(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          LineChartData(
            minX: bas,
            maxX: haut,
            minY: bornes.min,
            maxY: bornes.max,
            rangeAnnotations: plage == null || recalage == null
                ? const RangeAnnotations()
                : RangeAnnotations(
                    horizontalRangeAnnotations: [
                      HorizontalRangeAnnotation(
                        y1: recalage.densite(plage.min),
                        y2: recalage.densite(plage.max),
                        color: scheme.tertiary.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
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
              rightTitles: recalage == null || !axeDroit
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
              for (final l in densitesPrevues)
                LineChartBarData(
                  spots: [
                    FlSpot(bas, l.valeur * 1000),
                    FlSpot(haut, l.valeur * 1000),
                  ],
                  color: scheme.onSurfaceVariant,
                  barWidth: 1,
                  dashArray: kMotifPrevu,
                  dotData: const FlDotData(show: false),
                ),
              LineChartBarData(
                spots: [
                  for (final p in densites)
                    FlSpot(p.dayOffset, p.gravity! * 1000),
                ],
                color: scheme.primary,
                barWidth: 2,
                dotData: FlDotData(
                  getDotPainter: (_, _, _, _) => point(scheme.primary),
                ),
              ),
              if (recalage != null && temperatures.isNotEmpty)
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
              distanceCalculator: distanceTouche,
              touchSpotThreshold: kSeuilToucher * echelle,
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
                getTooltipItems: (touches) => _infoBullesReunies([
                  for (final t in touches)
                    _infoBulle(t.barIndex, t.spotIndex, densites, temperatures),
                ], TextStyle(color: scheme.onInverseSurface)),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Texte de l'info-bulle d'un point : ligne prévue, ou date, densité,
  /// température.
  String _infoBulle(
    int barre,
    int point,
    List<FermentationPoint> densites,
    List<FermentationPoint> temperatures,
  ) {
    final prevues = densitesPrevues.length;
    if (barre < prevues) return densitesPrevues[barre].infoBulle;
    final p = barre == prevues ? densites[point] : temperatures[point];
    final gravity = p.gravity;
    final temperature = p.temperature;
    return [
      libelleDate(p),
      if (gravity != null) 'Densité ${libelleDensite(gravity)}',
      if (temperature != null) 'Température ${libelleTemperature(temperature)}',
    ].join('\n');
  }
}

/// Plage de température tracée en aplat, en °C.
class PlageTrace {
  const PlageTrace({required this.min, required this.max});

  final double min;
  final double max;
}

/// Largeur du tracé sous laquelle l'axe de droite perd ses libellés : la
/// valeur reste dans l'info-bulle et le résumé lu.
const double kLargeurTraceAxeDroit = 200;

/// Vrai si l'axe de droite garde ses libellés dans [largeur], à [echelle] du
/// texte : le tracé garde au moins [kLargeurTraceAxeDroit] pixels.
bool axeDroitLisible(double largeur, double echelle) =>
    largeur - 2 * 52 * echelle >= kLargeurTraceAxeDroit;

/// Distance d'un appui à un point qui le touche, pour un texte à 100 %.
const double kSeuilToucher = 24;

/// Distance d'un appui à un point : verticale comprise, pour que l'info-bulle
/// donne la série touchée et non la première série à cette heure.
double distanceTouche(Offset appui, Offset point) => (appui - point).distance;

/// Une seule info-bulle qui réunit, sans doublon, les textes des séries
/// touchées ; `fl_chart` attend un élément par point touché.
List<LineTooltipItem?> _infoBullesReunies(
  List<String> textes,
  TextStyle style,
) {
  final uniques = <String>[];
  for (final t in textes) {
    if (!uniques.contains(t)) uniques.add(t);
  }
  return [
    for (final (i, _) in textes.indexed)
      i == 0
          ? LineTooltipItem(
              uniques.join('\n\n'),
              style,
              textAlign: TextAlign.left,
            )
          : null,
  ];
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

  /// Bornes des [valeurs], densités en échelle × 1000.
  factory _Bornes.de(List<double> valeurs) {
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
  _Recalage(List<double> valeurs, this.bornes) {
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

/// Point de la courbe du jour de brassage : heure, valeur (°C ou SG décimal) et
/// texte de son info-bulle.
class PointCourbe {
  const PointCourbe({
    required this.at,
    required this.valeur,
    required this.infoBulle,
  });

  final DateTime at;
  final double valeur;
  final String infoBulle;
}

/// Tracé de la courbe du jour de brassage : températures sur l'axe de gauche,
/// densités sur l'axe de droite. Les séries se distinguent sans la couleur
/// seule : visée recalculée en trait plein, visée du plan de départ en tirets,
/// températures mesurées en disques, densités mesurées en losanges, densité
/// initiale prévue en pointillés.
class TraceCourbeBrassage extends StatelessWidget {
  const TraceCourbeBrassage({
    super.key,
    required this.viseeRecalculee,
    required this.viseePlan,
    required this.temperatures,
    required this.densites,
    required this.densitePrevue,
    required this.libelleHeure,
    required this.libelleTemperature,
    required this.libelleDensite,
  });

  /// Tracés continus de la visée recalculée, en °C.
  final List<List<PointCourbe>> viseeRecalculee;

  /// Tracés continus de la visée du plan de départ, en °C.
  final List<List<PointCourbe>> viseePlan;

  /// Températures mesurées, en °C.
  final List<PointCourbe> temperatures;

  /// Densités mesurées, en SG décimal.
  final List<PointCourbe> densites;

  /// Densité initiale prévue, ou nulle.
  final LignePrevue? densitePrevue;

  final String Function(DateTime) libelleHeure;
  final String Function(double celsius) libelleTemperature;
  final String Function(double sg) libelleDensite;

  static double _minutes(DateTime at) =>
      at.millisecondsSinceEpoch / Duration.millisecondsPerMinute;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styleAxe = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final echelle = MediaQuery.textScalerOf(context).scale(1);

    final celsius = [
      for (final l in [...viseeRecalculee, ...viseePlan])
        for (final p in l) p.valeur,
      for (final p in temperatures) p.valeur,
    ];
    final prevue = densitePrevue;
    final axes = _AxesBrassage.de(celsius, [
      for (final p in densites) p.valeur * 1000,
      if (prevue != null) prevue.valeur * 1000,
    ]);

    final instants = [
      for (final l in [...viseeRecalculee, ...viseePlan])
        for (final p in l) _minutes(p.at),
      for (final p in [...temperatures, ...densites]) _minutes(p.at),
    ];
    final minX = instants.reduce(math.min);
    final maxX = instants.reduce(math.max);
    final etenduX = maxX - minX;
    final margeX = etenduX < 30 ? 15.0 : etenduX * 0.04;
    final bas = minX - margeX;
    final haut = maxX + margeX;
    final pasX = _pasMinutes(haut - bas);

    FlDotPainter disque(Color couleur, double rayon) => FlDotCirclePainter(
      color: couleur,
      radius: rayon,
      strokeColor: couleur,
      strokeWidth: 0,
    );

    // Une barre par tracé, et la liste des points qui renseigne l'info-bulle.
    final barres = <LineChartBarData>[];
    final infos = <List<String>>[];
    void ligne(
      List<PointCourbe> points,
      Color couleur,
      double largeur,
      List<int>? motif,
    ) {
      barres.add(
        LineChartBarData(
          spots: [for (final p in points) FlSpot(_minutes(p.at), p.valeur)],
          color: couleur,
          barWidth: largeur,
          dashArray: motif,
          dotData: FlDotData(
            // Un tracé d'un seul point (étape de 0 min) se voit par son point.
            show: points.length == 1,
            getDotPainter: (_, _, _, _) => disque(couleur, largeur * 1.5),
          ),
        ),
      );
      infos.add([for (final p in points) p.infoBulle]);
    }

    for (final l in viseePlan) {
      ligne(l, scheme.onSurfaceVariant, 1.5, kMotifPlanDeDepart);
    }
    for (final l in viseeRecalculee) {
      ligne(l, scheme.primary, 2, null);
    }
    if (prevue != null) {
      final y = axes.versT(prevue.valeur * 1000);
      barres.add(
        LineChartBarData(
          spots: [FlSpot(bas, y), FlSpot(haut, y)],
          color: scheme.secondary,
          barWidth: 1.5,
          dashArray: kMotifPrevu,
          dotData: const FlDotData(show: false),
        ),
      );
      infos.add([prevue.infoBulle, prevue.infoBulle]);
    }
    if (temperatures.isNotEmpty) {
      barres.add(
        LineChartBarData(
          spots: [
            for (final p in temperatures) FlSpot(_minutes(p.at), p.valeur),
          ],
          // Marqueurs sans ligne : le trait est transparent.
          color: scheme.tertiary.withValues(alpha: 0),
          barWidth: 1,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => disque(scheme.tertiary, 4),
          ),
        ),
      );
      infos.add([for (final p in temperatures) p.infoBulle]);
    }
    if (densites.isNotEmpty) {
      barres.add(
        LineChartBarData(
          spots: [
            for (final p in densites)
              FlSpot(_minutes(p.at), axes.versT(p.valeur * 1000)),
          ],
          color: scheme.secondary.withValues(alpha: 0),
          barWidth: 1,
          dotData: FlDotData(
            getDotPainter: (_, _, _, _) => _Losange(scheme.secondary, 5),
          ),
        ),
      );
      infos.add([for (final p in densites) p.infoBulle]);
    }

    return LayoutBuilder(
      builder: (context, contraintes) {
        final axeDroit =
            axes.densites && axeDroitLisible(contraintes.maxWidth, echelle);
        return LineChart(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          LineChartData(
            minX: bas,
            maxX: haut,
            minY: axes.min,
            maxY: axes.max,
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: scheme.outline),
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: axes.pas,
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
                    child: Text(
                      libelleHeure(
                        DateTime.fromMillisecondsSinceEpoch(
                          (value * Duration.millisecondsPerMinute).round(),
                        ),
                      ),
                      style: styleAxe,
                    ),
                  ),
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: axes.pas,
                  minIncluded: false,
                  maxIncluded: false,
                  reservedSize: 52 * echelle,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(libelleTemperature(value), style: styleAxe),
                  ),
                ),
              ),
              // Une graduation de densité ronde sur chaque ligne de la
              // grille ; sous la largeur seuil, l'axe n'a plus de libellés.
              rightTitles: !axeDroit
                  ? const AxisTitles()
                  : AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: axes.pas,
                        minIncluded: false,
                        maxIncluded: false,
                        reservedSize: 52 * echelle,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(
                            libelleDensite(axes.densiteRonde(value) / 1000),
                            style: styleAxe,
                          ),
                        ),
                      ),
                    ),
            ),
            lineBarsData: barres,
            lineTouchData: LineTouchData(
              distanceCalculator: distanceTouche,
              touchSpotThreshold: kSeuilToucher * echelle,
              getTouchedSpotIndicator: (barre, indices) => [
                for (final _ in indices)
                  TouchedSpotIndicatorData(
                    FlLine(color: scheme.outline, strokeWidth: 1),
                    FlDotData(
                      getDotPainter: (_, _, _, _) =>
                          disque(scheme.onSurface, 3),
                    ),
                  ),
              ],
              touchTooltipData: LineTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                maxContentWidth: 240,
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (touches) => _infoBullesReunies([
                  for (final t in touches) infos[t.barIndex][t.spotIndex],
                ], TextStyle(color: scheme.onInverseSurface)),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Pas de l'axe des heures, en minutes : cinq libellés au plus.
double _pasMinutes(double etendu) {
  const pas = [5, 10, 15, 30, 60, 120, 180, 240, 360, 480, 720, 1440];
  for (final p in pas) {
    if (etendu / p <= 5) return p.toDouble();
  }
  return pas.last.toDouble();
}

/// Axes de la courbe du jour de brassage : températures à gauche, densités
/// (× 1000) à droite. Chaque ligne de la grille porte une température ronde et
/// une densité ronde : le pas des densités (1, 2 ou 5 × 10^n points) occupe
/// le pas des températures. Affichage seul : aucune valeur recalée n'est
/// stockée.
class _AxesBrassage {
  _AxesBrassage(
    this.min,
    this.max,
    this.pas,
    this._a,
    this._b,
    this.densites,
    this._pasD,
  );

  factory _AxesBrassage.de(List<double> celsius, List<double> densites) {
    // Sans température, l'axe garde une étendue lisible ; la courbe ne
    // s'affiche alors que pour ses densités.
    var bas = celsius.isEmpty ? 0.0 : celsius.reduce(math.min);
    var haut = celsius.isEmpty ? 100.0 : celsius.reduce(math.max);
    final etendu = haut - bas;
    final marge = etendu < 4 ? 2.0 : etendu * 0.1;
    final pas = _pas((etendu + marge * 2) / 4);
    bas = ((bas - marge) / pas).floorToDouble() * pas;
    haut = ((haut + marge) / pas).ceilToDouble() * pas;
    if (densites.isEmpty) {
      return _AxesBrassage(bas, haut, pas, 1, 0, false, 1);
    }
    final dBas = densites.reduce(math.min);
    final dHaut = densites.reduce(math.max);
    final lignes = math.max(1, ((haut - bas) / pas).round() - 1);
    // Un point au moins entre deux graduations : deux lignes de la grille ne
    // portent jamais la même densité.
    final pasD = math.max(1.0, _pas(math.max(1, dHaut - dBas) / lignes));
    // La densité ronde sous la plus basse tombe sur la ligne de grille qui
    // suit le bas de l'axe ; le haut s'étend si les densités le demandent.
    final d0 = (dBas / pasD).floorToDouble() * pasD;
    final y0 = bas + pas;
    final a = pas / pasD;
    final b = y0 - a * d0;
    final yHaut = a * dHaut + b;
    if (yHaut > haut - pas / 2) {
      haut = ((yHaut + pas / 2) / pas).ceilToDouble() * pas;
    }
    return _AxesBrassage(bas, haut, pas, a, b, true, pasD);
  }

  final double min;
  final double max;
  final double pas;
  final double _a;
  final double _b;
  final double _pasD;

  /// Vrai si l'axe de droite porte des densités.
  final bool densites;

  /// Position, sur l'échelle des températures, d'une densité × 1000.
  double versT(double densite) => _a * densite + _b;

  /// Densité × 1000 d'une position de l'échelle des températures.
  double versD(double t) => (t - _b) / _a;

  /// Densité × 1000 de la graduation à [t], au multiple du pas des densités.
  double densiteRonde(double t) => (versD(t) / _pasD).round() * _pasD;
}

/// Losange plein : marqueur d'une densité mesurée.
class _Losange extends FlDotPainter {
  const _Losange(this.couleur, this.rayon);

  final Color couleur;
  final double rayon;

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final c = offsetInCanvas;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - rayon)
        ..lineTo(c.dx + rayon, c.dy)
        ..lineTo(c.dx, c.dy + rayon)
        ..lineTo(c.dx - rayon, c.dy)
        ..close(),
      Paint()..color = couleur,
    );
  }

  @override
  Size getSize(FlSpot spot) => Size.square(rayon * 2);

  @override
  Color get mainColor => couleur;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [couleur, rayon];
}
