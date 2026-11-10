import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Boutons segmentés qui passent l'un sous l'autre quand leurs libellés ne
/// tiennent pas sur la largeur, à l'échelle de texte courante : choix d'un
/// formulaire de recette, unité d'un prix.

/// Largeur d'un segment hors libellé : marges (12 et 16), coche (18) et son
/// écart (8), bordure (1), comme `SegmentedButton` de Material 3.
const double kSegmentHorsLibelle = 55;

/// Vrai si des segments de libellés [labels] tiennent côte à côte dans
/// [maxWidth] : `SegmentedButton` donne à chaque segment la largeur du plus
/// large, libellé mesuré avec le style [style] et l'échelle de texte [scaler].
bool segmentsTiennent({
  required List<String> labels,
  required TextStyle? style,
  required TextScaler scaler,
  required TextDirection textDirection,
  required double maxWidth,
}) {
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: textDirection,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return labels.length * (widest + kSegmentHorsLibelle) <= maxWidth;
}

/// `SegmentedButton` de [values], côte à côte s'ils tiennent
/// ([segmentsTiennent]), sinon en colonne. [semanticsOf] : libellé lu par un
/// lecteur d'écran, s'il diffère du libellé affiché.
class BoutonsSegmentes<T> extends StatelessWidget {
  const BoutonsSegmentes({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onSelectionChanged,
    this.semanticsOf,
    this.emptySelectionAllowed = false,
  });

  final List<T> values;
  final String Function(T) labelOf;
  final String Function(T)? semanticsOf;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;
  final bool emptySelectionAllowed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = segmentsTiennent(
        labels: [for (final v in values) labelOf(v)],
        style: Theme.of(context).textTheme.labelLarge,
        scaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
        maxWidth: constraints.maxWidth,
      );
      return SegmentedButton<T>(
        direction: horizontal ? Axis.horizontal : Axis.vertical,
        emptySelectionAllowed: emptySelectionAllowed,
        segments: [
          for (final v in values)
            ButtonSegment(
              value: v,
              label: Text(labelOf(v), semanticsLabel: semanticsOf?.call(v)),
            ),
        ],
        selected: selected,
        onSelectionChanged: onSelectionChanged,
      );
    },
  );
}
