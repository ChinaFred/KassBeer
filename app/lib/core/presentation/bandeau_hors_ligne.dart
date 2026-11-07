import 'package:flutter/material.dart';

/// Bandeau affiché quand le document du membre courant vient du cache local
/// (`snapshot.metadata.isFromCache`) : l'appareil est hors ligne.
class BandeauHorsLigne extends StatelessWidget {
  const BandeauHorsLigne({super.key});

  static const message = 'Hors ligne. Les modifications partiront au retour du réseau.';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message, style: TextStyle(color: scheme.onSecondaryContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
