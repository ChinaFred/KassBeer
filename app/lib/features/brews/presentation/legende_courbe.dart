import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Échantillon d'une entrée de légende : trait (plein ou à motif), marqueur ou
/// aplat, dessiné comme la série qu'il nomme.
enum EchantillonLegende { trait, disque, losange, aplat }

/// Une entrée de la légende d'une courbe : échantillon et texte. La légende
/// s'écrit dans un `Wrap`, qui passe à la ligne avec un texte agrandi.
class LegendeCourbe extends StatelessWidget {
  const LegendeCourbe({
    super.key,
    required this.texte,
    required this.couleur,
    required this.style,
    this.motif,
    this.echantillon = EchantillonLegende.trait,
    this.contour,
  });

  final String texte;
  final Color couleur;
  final TextStyle? style;

  /// Longueurs alternées trait, blanc ; nul pour un trait plein.
  final List<int>? motif;
  final EchantillonLegende echantillon;

  /// Contour de 1 px d'un aplat, ou nul.
  final Color? contour;

  @override
  Widget build(BuildContext context) {
    final echelle = MediaQuery.textScalerOf(context).scale(1);
    final hauteur = switch (echantillon) {
      EchantillonLegende.trait => 2 * echelle,
      _ => 10 * echelle,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(24 * echelle, hauteur),
          painter: _Echantillon(couleur, motif, echelle, echantillon, contour),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(texte, style: style)),
      ],
    );
  }
}

/// Dessine l'échantillon avec la couleur et la forme de la série.
class _Echantillon extends CustomPainter {
  const _Echantillon(
    this.couleur,
    this.motif,
    this.echelle,
    this.forme,
    this.contour,
  );

  final Color couleur;
  final List<int>? motif;
  final double echelle;
  final EchantillonLegende forme;
  final Color? contour;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final plein = Paint()..color = couleur;
    switch (forme) {
      case EchantillonLegende.disque:
        canvas.drawCircle(centre, 4 * echelle, plein);
        return;
      case EchantillonLegende.losange:
        final r = 5 * echelle;
        canvas.drawPath(
          Path()
            ..moveTo(centre.dx, centre.dy - r)
            ..lineTo(centre.dx + r, centre.dy)
            ..lineTo(centre.dx, centre.dy + r)
            ..lineTo(centre.dx - r, centre.dy)
            ..close(),
          plein,
        );
        return;
      case EchantillonLegende.aplat:
        canvas.drawRect(Offset.zero & size, plein);
        if (contour != null) {
          canvas.drawRect(
            (Offset.zero & size).deflate(0.5),
            Paint()
              ..color = contour!
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
        return;
      case EchantillonLegende.trait:
        break;
    }
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
  bool shouldRepaint(_Echantillon old) =>
      old.couleur != couleur ||
      old.motif != motif ||
      old.echelle != echelle ||
      old.forme != forme ||
      old.contour != contour;
}
