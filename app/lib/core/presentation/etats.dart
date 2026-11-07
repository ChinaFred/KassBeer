import 'package:flutter/material.dart';

import 'breakpoints.dart';

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

/// Rien à afficher : icône, texte, et au besoin une action.
class EtatVide extends StatelessWidget {
  const EtatVide({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;

  /// Bouton facultatif sous le message.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// Contenu d'un bouton pendant une action : indicateur et libellé visibles, lus par
/// les lecteurs d'écran.
class IndicateurBouton extends StatelessWidget {
  const IndicateurBouton({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: retrying ? null : onRetry,
                child: retrying
                    ? const IndicateurBouton(label: 'Vérification en cours')
                    : const Text('Réessayer'),
              ),
              if (secondaryAction != null) ...[
                const SizedBox(height: 8),
                secondaryAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
