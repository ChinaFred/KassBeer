import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/formats.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../domain/referentiel.dart';

/// Textes communs à la barre de couleur et à la page « Couleurs EBC ».
abstract final class TextesCouleurEbc {
  static const mention =
      'Teinte indicative : la couleur réelle dépend du verre, de la lumière '
      'et de l\'écran.';
  static const echelle = 'Échelle des couleurs';

  /// Phrase affichée quand une plage dépasse la limite de la table.
  static String auDela() =>
      'Au-delà de ${formatNombre(teinteEbcLimite, decimales: 0)}${nbsp}EBC, '
      'la teinte affichée ne fonce plus.';

  /// Vrai si la plage monte au-delà de [teinteEbcLimite] : borne haute au-delà
  /// de la limite, ou plage ouverte « à partir de ».
  static bool depasseLimite(double? minimum, double? maximum) {
    if (maximum == null) return true;
    final haut = minimum != null && minimum > maximum ? minimum : maximum;
    return haut > teinteEbcLimite;
  }

  /// Libellé lu par un lecteur d'écran pour la barre d'une plage.
  static String plage(double? minimum, double? maximum) {
    if (minimum != null && maximum != null) {
      final bas = minimum <= maximum ? minimum : maximum;
      final haut = minimum <= maximum ? maximum : minimum;
      return 'Couleur de ${formatEbc(bas)} à ${formatEbc(haut)}';
    }
    if (minimum != null) return 'Couleur à partir de ${formatEbc(minimum)}';
    return 'Couleur jusqu\'à ${formatEbc(maximum!)}';
  }
}

/// Couleur Flutter d'une teinte `0xRRGGBB` rendue par `brewing/`.
Color couleurTeinte(int teinte) => Color(0xFF000000 | teinte);

/// Dégradé horizontal de [teintes] (`0xRRGGBB`), 16 px de haut, coins arrondis,
/// bordure `outlineVariant` du thème. Décoratif : l'appelant porte le texte.
class BandeTeintes extends StatelessWidget {
  const BandeTeintes({super.key, required this.teintes});

  final List<int> teintes;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        gradient: LinearGradient(colors: teintes.map(couleurTeinte).toList()),
      ),
    ),
  );
}

/// Barre en dégradé sous la ligne « Couleur » de la fiche d'un style, la
/// mention de teinte indicative et le lien « Échelle des couleurs ».
///
/// Plage « à partir de X » : de X à la limite de la table ; « jusqu'à X » : de
/// 0 à X. Une borne refusée par `brewing/` masque la barre et passe par
/// `reportError`, une fois par fiche affichée.
class BarreCouleurEbc extends ConsumerStatefulWidget {
  const BarreCouleurEbc({super.key, required this.plage});

  final Plage plage;

  @override
  ConsumerState<BarreCouleurEbc> createState() => _BarreCouleurEbcState();
}

class _BarreCouleurEbcState extends ConsumerState<BarreCouleurEbc> {
  bool _signale = false;

  List<int>? _teintes() {
    final p = widget.plage;
    try {
      return degradeEbc(p.minimum ?? 0, p.maximum ?? teinteEbcLimite);
    } on BrewingInputException catch (error, stackTrace) {
      if (!_signale) {
        _signale = true;
        ref
            .read(errorReportServiceProvider)
            .reportError(
              feature: 'library.color_gradient',
              error: error,
              stackTrace: stackTrace,
              context: 'plage de couleur refusée par brewing : ${error.field}',
            );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final teintes = _teintes();
    if (teintes == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final p = widget.plage;
    final auDela = TextesCouleurEbc.depasseLimite(p.minimum, p.maximum);
    final petit = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: auDela
              ? '${TextesCouleurEbc.plage(p.minimum, p.maximum)}. '
                    '${TextesCouleurEbc.auDela()}'
              : TextesCouleurEbc.plage(p.minimum, p.maximum),
          child: BandeTeintes(teintes: teintes),
        ),
        const SizedBox(height: 4),
        if (auDela)
          ExcludeSemantics(
            child: Text(TextesCouleurEbc.auDela(), style: petit),
          ),
        Text(TextesCouleurEbc.mention, style: petit),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(context.push(AppRoutes.libraryColors)),
            icon: const Icon(Icons.palette_outlined),
            label: const Text(TextesCouleurEbc.echelle),
          ),
        ),
      ],
    );
  }
}
