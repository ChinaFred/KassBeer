import 'package:flutter/material.dart';

import '../../../core/presentation/etats.dart';

/// Affiché tant que la session et `members/{email}` ne sont pas lus.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.sports_bar,
                size: 72,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text("Kass'Beer", style: theme.textTheme.headlineMedium),
            const SizedBox(height: 32),
            const SizedBox(
              height: 48,
              child: EtatChargement(label: 'Vérification de l\'accès'),
            ),
          ],
        ),
      ),
    );
  }
}
