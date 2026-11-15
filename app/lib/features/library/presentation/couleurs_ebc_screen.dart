import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';

import '../../../core/presentation/breakpoints.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/presentation/page_secondaire.dart';
import '../../../core/router/routes.dart';
import 'couleur_ebc.dart';

/// Pas de l'échelle affichée, en EBC (choix de l'administrateur, ticket #48).
const int kPasEchelleEbc = 4;

/// Une valeur de l'échelle : libellé et teinte `0xRRGGBB`.
typedef ValeurEchelle = ({String libelle, int teinte});

/// Page « Couleurs EBC » : la teinte indicative de 0 EBC à la limite de la
/// table, tous les [kPasEchelleEbc] EBC, puis « 79 EBC et plus ». Ouverte par
/// `push` depuis la Bibliothèque et la fiche d'un style. Page statique : elle
/// ne lit rien dans Firestore et s'affiche hors ligne.
class CouleursEbcScreen extends StatelessWidget {
  const CouleursEbcScreen({super.key});

  static const title = 'Couleurs EBC';

  /// Libellé de la dernière valeur : la limite de la table, arrondie.
  static String libelleLimite() =>
      '${formatNombre(teinteEbcLimite, decimales: 0)}${nbsp}EBC et plus';

  /// Valeurs de l'échelle. Les entrées sont des constantes valides : `brewing/`
  /// ne les refuse pas, d'où l'absence d'état d'erreur sur cette page.
  static List<ValeurEchelle> valeurs() => [
    for (var ebc = 0; ebc < teinteEbcLimite; ebc += kPasEchelleEbc)
      (libelle: formatEbc(ebc.toDouble()), teinte: teinteEbc(ebc * 1.0)),
    (libelle: libelleLimite(), teinte: teinteEbc(teinteEbcLimite)),
  ];

  @override
  Widget build(BuildContext context) => PageSecondaire(
    titre: title,
    repli: AppRoutes.library,
    body: _Echelle(
      valeurs: valeurs(),
      degrade: degradeEbc(0, teinteEbcLimite, points: 40),
    ),
  );
}

class _Echelle extends StatelessWidget {
  const _Echelle({required this.valeurs, required this.degrade});

  final List<ValeurEchelle> valeurs;
  final List<int> degrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    // Largeur d'une case de la grille, suivie par l'échelle du texte.
    final largeurCase = MediaQuery.textScalerOf(context).scale(168);
    final mention = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        TextesCouleurEbc.mention,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final marges = PageSecondaire.marges(
      context,
      const EdgeInsets.fromLTRB(16, 16, 16, 32),
    );
    if (compact) {
      return ListView(
        padding: marges,
        children: [
          mention,
          for (final v in valeurs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _LigneTeinte(valeur: v),
            ),
        ],
      );
    }
    return ListView(
      padding: marges,
      children: [
        mention,
        Semantics(
          container: true,
          label: 'Dégradé de 0 à ${CouleursEbcScreen.libelleLimite()}',
          child: BandeTeintes(teintes: degrade),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            for (final v in valeurs)
              SizedBox(
                width: largeurCase,
                child: _LigneTeinte(valeur: v),
              ),
          ],
        ),
      ],
    );
  }
}

/// Pastille de 40 × 40 px bordée par `outlineVariant`, puis le libellé.
class _LigneTeinte extends StatelessWidget {
  const _LigneTeinte({required this.valeur});

  final ValeurEchelle valeur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            key: ValueKey('pastille ${valeur.libelle}'),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: couleurTeinte(valeur.teinte),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(valeur.libelle, style: theme.textTheme.bodyLarge)),
      ],
    );
  }
}
