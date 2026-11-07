import 'package:flutter/material.dart';

/// Ligne « libellé : valeur » d'une fiche ; valeur absente = « Non renseigné ».
class LigneFiche extends StatelessWidget {
  const LigneFiche({super.key, required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(
          spacing: 16,
          runSpacing: 2,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              v ?? 'Non renseigné',
              style: v == null
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    )
                  : theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Titre de section, déclaré comme en-tête aux lecteurs d'écran.
class TitreSection extends StatelessWidget {
  const TitreSection(this.text, {super.key, this.trailing});

  final String text;

  /// Texte d'appoint à droite du titre (« 7 · 5,2 kg »).
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = trailing;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Semantics(
        header: true,
        child: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(text, style: theme.textTheme.titleMedium),
            if (t != null)
              Text(
                t,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
