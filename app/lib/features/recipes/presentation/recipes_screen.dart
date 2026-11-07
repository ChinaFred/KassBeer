import 'package:flutter/material.dart';

import '../../../core/presentation/etats.dart';

/// Écran à venir : aucun bouton tant que la fonctionnalité n'existe pas.
class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EtatVide(
      icon: Icons.menu_book_outlined,
      message: 'Les recettes arriveront dans une prochaine version.',
    );
  }
}
