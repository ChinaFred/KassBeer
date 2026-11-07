import 'package:flutter/material.dart';

import 'etats.dart';

/// Panne après une première liste lue : la liste reste affichée sous ce bandeau.
class BandeauListePerimee extends StatelessWidget {
  const BandeauListePerimee({
    super.key,
    this.message = defaultMessage,
    required this.retrying,
    required this.onRetry,
  });

  static const defaultMessage =
      'Mise à jour de la liste impossible. Elle peut ne plus être à jour.';

  final String message;

  /// Une nouvelle lecture est en cours : le bouton attend.
  final bool retrying;
  final VoidCallback onRetry;

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
              TextButton(
                onPressed: retrying ? null : onRetry,
                child: retrying
                    ? const IndicateurBouton(label: 'Lecture en cours')
                    : const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
