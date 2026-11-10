import 'package:flutter/material.dart';

/// Ton d'une [Etiquette].
enum TonEtiquette {
  /// `secondaryContainer` : information.
  normal,

  /// `errorContainer` : envoi impossible, limite atteinte.
  erreur,
}

/// Étiquette non interactive (« Vous », « En attente du réseau », rôle, statut
/// d'un ticket).
class Etiquette extends StatelessWidget {
  const Etiquette({
    super.key,
    required this.label,
    this.icon,
    this.ton = TonEtiquette.normal,
  });

  final String label;

  /// Icône avant le texte, exclue de la sémantique : le texte suffit.
  final IconData? icon;
  final TonEtiquette ton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (ton) {
      TonEtiquette.normal => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      TonEtiquette.erreur => (scheme.errorContainer, scheme.onErrorContainer),
    };
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: foreground);
    final text = Text(label, style: style);
    final icon = this.icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: icon == null
            ? text
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Icon(icon, size: 16, color: foreground),
                  ),
                  const SizedBox(width: 4),
                  Flexible(child: text),
                ],
              ),
      ),
    );
  }
}
