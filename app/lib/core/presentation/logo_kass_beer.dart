import 'package:flutter/material.dart';

/// Médaillon du logo (`assets/images/logo_kass_beer.webp`, 384 px), exclu de la
/// sémantique : le nom de l'application l'accompagne ou le titre de l'écran suffit.
///
/// Jamais sous [tailleMin] : en dessous, le gobelin n'est plus lisible.
class MedaillonKassBeer extends StatelessWidget {
  const MedaillonKassBeer({super.key, this.taille = 176})
    : assert(taille >= tailleMin);

  static const double tailleMin = 48;

  final double taille;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Image.asset(
        'assets/images/logo_kass_beer.webp',
        width: taille,
        height: taille,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Logo de Kass'Beer : médaillon et nom, en tête des écrans de connexion et de
/// chargement.
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
        const Center(child: MedaillonKassBeer()),
        const SizedBox(height: 16),
        Semantics(
          header: headerSemantics,
          child: Text(
            "Kass'Beer",
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
