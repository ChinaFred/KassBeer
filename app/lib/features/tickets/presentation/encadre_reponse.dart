import 'package:flutter/material.dart';

/// Encadré d'un texte de l'administrateur (« Motif du refus », « Commentaire
/// de clôture », « Réponse de l'administrateur »), sur le suivi du membre et la
/// fiche d'Admin.
class EncadreReponse extends StatelessWidget {
  const EncadreReponse({super.key, required this.titre, required this.texte});

  final String titre;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.reply, size: 18, color: scheme.onSurface),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        titre,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                texte,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
