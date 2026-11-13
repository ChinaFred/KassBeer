import 'package:flutter/material.dart';

/// Encadré à icône des fenêtres d'Admin › Tickets : « Publié sur un site
/// public… » (Refuser, Clore, Répondre), avertissement de relance et coût de la
/// boîte de lancement. Couleurs lues dans `colorScheme` ; l'icône est exclue
/// de la lecture, le texte est lu.
class EncadreAvertissement extends StatelessWidget {
  const EncadreAvertissement({
    super.key,
    required this.icone,
    required this.texte,
  });

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icone, color: scheme.onSurface)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                texte,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
