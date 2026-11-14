import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ton d'un [Encadre].
enum TonEncadre {
  /// `secondaryContainer` : information.
  information,

  /// `tertiaryContainer` : avertissement, temps dépassé.
  avertissement,

  /// `CouleursEtat.conteneurSucces` : tout est prêt.
  succes,

  /// `errorContainer` : calcul impossible, fichier refusé.
  erreur,
}

/// Bloc coloré qui met un message à part : fond du [ton], rayon
/// [AppTheme.rayon], marge intérieure de 16, icône facultative exclue de la
/// lecture (le texte suffit). Les textes et les icônes de [child] sans couleur
/// propre prennent la couleur du texte du ton.
class Encadre extends StatelessWidget {
  const Encadre({
    super.key,
    required this.child,
    this.ton = TonEncadre.information,
    this.icone,
    this.liveRegion = false,
  });

  final Widget child;
  final TonEncadre ton;
  final IconData? icone;

  /// Vrai : le contenu est annoncé quand il paraît (panne, refus).
  final bool liveRegion;

  /// Couleurs de fond et de texte de [ton].
  static (Color, Color) _couleurs(BuildContext context, TonEncadre ton) {
    final scheme = Theme.of(context).colorScheme;
    return switch (ton) {
      TonEncadre.information => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      TonEncadre.avertissement => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      TonEncadre.succes => (
        CouleursEtat.of(context).conteneurSucces,
        CouleursEtat.of(context).surConteneurSucces,
      ),
      TonEncadre.erreur => (scheme.errorContainer, scheme.onErrorContainer),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (fond, texte) = _couleurs(context, ton);
    final icone = this.icone;
    final contenu = DefaultTextStyle.merge(
      style: theme.textTheme.bodyMedium?.copyWith(color: texte),
      child: IconTheme.merge(
        data: IconThemeData(color: texte),
        child: child,
      ),
    );
    final Widget encadre = Material(
      color: fond,
      borderRadius: BorderRadius.circular(AppTheme.rayon),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: icone == null
            ? contenu
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Icon(icone, color: texte)),
                  const SizedBox(width: 12),
                  Expanded(child: contenu),
                ],
              ),
      ),
    );
    return liveRegion ? Semantics(liveRegion: true, child: encadre) : encadre;
  }
}
