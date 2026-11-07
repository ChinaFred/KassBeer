import 'package:flutter/material.dart';

import '../../../core/presentation/etats.dart';

/// Écran à venir : aucun bouton tant que la fonctionnalité n'existe pas.
class BrewsScreen extends StatelessWidget {
  const BrewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EtatVide(
      icon: Icons.science_outlined,
      message: 'Les brassins arriveront dans une prochaine version.',
    );
  }
}
