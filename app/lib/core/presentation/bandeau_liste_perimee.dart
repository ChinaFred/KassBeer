import 'package:flutter/material.dart';

import 'etats.dart';

/// Panne après une première liste lue : la liste reste affichée sous ce bandeau.
/// Sans [onRetry], le bandeau n'a pas de bouton « Réessayer ».
class BandeauListePerimee extends StatelessWidget {
  const BandeauListePerimee({
    super.key,
    this.message = defaultMessage,
    required this.retrying,
    required this.onRetry,
    this.retryEnabled = true,
    this.retryingLabel = 'Lecture en cours',
  });

  static const defaultMessage =
      'Mise à jour de la liste impossible. Elle peut ne plus être à jour.';

  final String message;

  /// Une nouvelle lecture est en cours : le bouton attend.
  final bool retrying;
  final VoidCallback? onRetry;

  /// Faux : le bouton est désactivé sans indicateur (un autre appel est en
  /// cours).
  final bool retryEnabled;

  /// Libellé du bouton pendant la nouvelle lecture.
  final String retryingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(message, style: TextStyle(color: scheme.onErrorContainer)),
              if (onRetry != null)
                TextButton(
                  onPressed: retrying || !retryEnabled ? null : onRetry,
                  child: retrying
                      ? IndicateurBouton(label: retryingLabel)
                      : const Text('Réessayer'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
