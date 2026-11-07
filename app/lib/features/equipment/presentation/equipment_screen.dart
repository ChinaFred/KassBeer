import 'package:flutter/material.dart';

import '../../../core/presentation/etats.dart';

/// Écran à venir : aucun bouton tant que la fonctionnalité n'existe pas.
class EquipmentScreen extends StatelessWidget {
  const EquipmentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EtatVide(
      icon: Icons.kitchen_outlined,
      message: 'Les équipements arriveront dans une prochaine version.',
    );
  }
}
