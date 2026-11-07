import 'package:flutter/material.dart';

/// États partagés des écrans : chargement, vide, erreur.

/// Chargement en cours : indicateur centré, annoncé aux lecteurs d'écran.
class EtatChargement extends StatelessWidget {
  const EtatChargement({super.key, this.label = 'Chargement'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: label,
        liveRegion: true,
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

/// Rien à afficher : icône et texte, sans bouton.
class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

/// Panne : message et bouton « Réessayer ».
class EtatErreur extends StatelessWidget {
  const EtatErreur({
    super.key,
    required this.message,
    required this.onRetry,
    this.retrying = false,
    this.secondaryAction,
  });

  final String message;
  final VoidCallback onRetry;

  /// Une nouvelle lecture est en cours : le bouton attend.
  final bool retrying;

  /// Action de repli sous le bouton, par exemple « Se déconnecter ».
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: retrying ? null : onRetry,
                child: retrying
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Réessayer'),
              ),
              if (secondaryAction != null) ...[const SizedBox(height: 8), secondaryAction!],
            ],
          ),
        ),
      ),
    );
  }
}
