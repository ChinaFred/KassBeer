import 'package:flutter/material.dart';

/// Logo de Kass'Beer : icône et nom. L'icône `sports_bar` tient la place du fichier
/// du logo, qui n'existe pas encore.
class LogoKassBeer extends StatelessWidget {
  const LogoKassBeer({super.key, this.headerSemantics = false});

  /// Le nom est le titre de l'écran pour les lecteurs d'écran.
  final bool headerSemantics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.sports_bar,
            size: 72,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: headerSemantics,
          child: Text(
            "Kass'Beer",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineLarge,
          ),
        ),
      ],
    );
  }
}
