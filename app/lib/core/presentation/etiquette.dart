import 'package:flutter/material.dart';

/// Étiquette non interactive (« Vous », « En attente du réseau », rôle).
class Etiquette extends StatelessWidget {
  const Etiquette({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
