import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Contenu d'une page que « Signaler ou proposer » peut capturer (ADR-008,
/// T6) : le corps du `Scaffold` de la coquille et de chaque page pleine qui
/// porte le menu du compte. Ni la barre du haut, ni la barre de navigation,
/// ni un menu ou une boîte ouverts (dans l'`Overlay`) n'y figurent.
class ZoneCapture extends RepaintBoundary {
  const ZoneCapture({super.key, super.child});
}

/// Plus grand côté d'une capture, en pixels.
const kCaptureMaxSide = 2000.0;

/// Échelle maximale d'une capture, quelle que soit la densité de l'écran.
const kCaptureMaxScale = 2.0;

/// Échelle de rendu d'une zone de [width] × [height] pixels logiques, sur un
/// écran de densité [devicePixelRatio] : au plus [kCaptureMaxScale], et le
/// plus grand côté au plus [kCaptureMaxSide] pixels. `null` pour une zone
/// vide. Pure.
double? echelleCapture({
  required double width,
  required double height,
  required double devicePixelRatio,
}) {
  final longest = math.max(width, height);
  if (!(longest > 0)) return null;
  return math.min(
    math.min(devicePixelRatio, kCaptureMaxScale),
    kCaptureMaxSide / longest,
  );
}

/// La [ZoneCapture] de la page qui porte [context] : la première trouvée sous
/// le `Scaffold` le plus proche, ou `null`.
RenderRepaintBoundary? zoneCaptureDe(BuildContext context) {
  final scaffold = context.findAncestorStateOfType<ScaffoldState>();
  if (scaffold == null || !scaffold.mounted) return null;
  RenderRepaintBoundary? trouvee;
  void visiter(Element element) {
    if (trouvee != null) return;
    if (element.widget is ZoneCapture) {
      final render = element.renderObject;
      if (render is RenderRepaintBoundary) trouvee = render;
      return;
    }
    element.visitChildren(visiter);
  }

  scaffold.context.visitChildElements(visiter);
  return trouvee;
}

/// Image PNG de [zone], en mémoire seulement : `null` si elle dépasse
/// [maxBytes] ou si la zone est vide. Lève si le rendu échoue ; l'appelant
/// rapporte l'erreur.
Future<Uint8List?> rendrePng(
  RenderRepaintBoundary zone, {
  required double devicePixelRatio,
  required int maxBytes,
}) async {
  if (!zone.hasSize) return null;
  final echelle = echelleCapture(
    width: zone.size.width,
    height: zone.size.height,
    devicePixelRatio: devicePixelRatio,
  );
  if (echelle == null) return null;
  final image = await zone.toImage(pixelRatio: echelle);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    return bytes.length > maxBytes ? null : bytes;
  } finally {
    image.dispose();
  }
}
