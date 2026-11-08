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

/// Section repliable d'une fiche : titre déclaré comme en-tête, résumé à droite.
///
/// [storageKey] (identifiant unique de la section dans la page) garde l'état ouvert
/// quand un `ListView` détruit le bloc hors de l'écran. [ouvert] : état initial.
class SectionRepliable extends StatelessWidget {
  const SectionRepliable({
    super.key,
    required this.titre,
    required this.storageKey,
    required this.children,
    this.resume,
    this.ouvert = false,
  });

  final String titre;
  final String storageKey;
  final String? resume;
  final bool ouvert;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = resume;
    return ExpansionTile(
      key: PageStorageKey<String>(storageKey),
      initiallyExpanded: ouvert,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Semantics(
            header: true,
            child: Text(titre, style: theme.textTheme.titleMedium),
          ),
          if (r != null)
            Text(
              r,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      children: children,
    );
  }
}

/// Texte en italique quand une section est vide (« Aucun houblon. »).
class TexteAbsent extends StatelessWidget {
  const TexteAbsent(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

/// Ligne sur deux niveaux, lue d'un bloc par les lecteurs d'écran.
class LigneDeuxNiveaux extends StatelessWidget {
  const LigneDeuxNiveaux({
    super.key,
    required this.title,
    required this.details,
  });

  final String title;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(
              details.join(' · '),
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
