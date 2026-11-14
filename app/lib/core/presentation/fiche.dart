import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Niveau d'un titre de section : [section] (titre de la page, `titleLarge`) ou
/// [sousSection] (titre rangé sous un autre, `titleMedium`), comme les sections
/// de la recette figée sous le titre « Recette » d'un brassin.
enum NiveauTitre { section, sousSection }

TextStyle? _styleTitre(ThemeData theme, NiveauTitre niveau) => switch (niveau) {
  NiveauTitre.section => theme.textTheme.titleLarge,
  NiveauTitre.sousSection => theme.textTheme.titleMedium,
};

/// Ligne « libellé : valeur » d'une fiche ; valeur absente = « Non renseigné ».
///
/// Sous [kCompactMaxWidth] de large, libellé et valeur se suivent et passent
/// l'un sous l'autre quand la place manque. À partir de [kCompactMaxWidth], le
/// libellé occupe une colonne de [kLibelleFicheFraction] de la largeur et la
/// valeur suit, alignée à gauche.
class LigneFiche extends StatelessWidget {
  const LigneFiche({super.key, required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    final libelle = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final valeur = Text(
      v ?? 'Non renseigné',
      style: v == null
          ? theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            )
          : theme.textTheme.bodyLarge,
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeur = constraints.maxWidth;
            if (largeur.isFinite && largeur >= kCompactMaxWidth) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: largeur * kLibelleFicheFraction,
                    child: libelle,
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: valeur),
                ],
              );
            }
            return Wrap(
              spacing: 16,
              runSpacing: 2,
              alignment: WrapAlignment.spaceBetween,
              children: [libelle, valeur],
            );
          },
        ),
      ),
    );
  }
}

/// Titre de section, déclaré comme en-tête aux lecteurs d'écran.
class TitreSection extends StatelessWidget {
  const TitreSection(
    this.text, {
    super.key,
    this.trailing,
    this.niveau = NiveauTitre.section,
  });

  final String text;

  /// Texte d'appoint à droite du titre (« 7 · 5,2 kg »).
  final String? trailing;

  /// [NiveauTitre.sousSection] sous un autre titre de section.
  final NiveauTitre niveau;

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
            Text(text, style: _styleTitre(theme, niveau)),
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
    this.niveau = NiveauTitre.section,
  });

  final String titre;
  final String storageKey;
  final String? resume;
  final bool ouvert;
  final List<Widget> children;

  /// [NiveauTitre.sousSection] sous un autre titre de section.
  final NiveauTitre niveau;

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
            child: Text(titre, style: _styleTitre(theme, niveau)),
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
