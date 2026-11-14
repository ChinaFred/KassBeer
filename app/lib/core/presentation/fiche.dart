import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

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

/// En-tête d'une fiche (recette, brassin, équipement, processus, recette
/// publique, ticket) : nom en `headlineSmall` déclaré comme en-tête, une ligne
/// de sous-titre facultative en `onSurfaceVariant` (style, auteur, date), des
/// étiquettes facultatives (statut, « En attente du réseau ») et une action
/// facultative à droite du nom (menu ⋮).
class EnTeteFiche extends StatelessWidget {
  const EnTeteFiche({
    super.key,
    required this.titre,
    this.sousTitre,
    this.etiquettes = const [],
    this.action,
  });

  final String titre;

  /// Ligne sous le nom ; `null` ou vide : aucune ligne.
  final String? sousTitre;

  /// `Etiquette` rangées sous le sous-titre.
  final List<Widget> etiquettes;

  /// Bouton à droite du nom, aligné sur sa première ligne.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sousTitre = this.sousTitre;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // Nœud propre : l'en-tête n'emporte ni le sous-titre ni les
              // étiquettes, lus à la suite.
              child: Semantics(
                header: true,
                container: true,
                child: Text(titre, style: theme.textTheme.headlineSmall),
              ),
            ),
            ?action,
          ],
        ),
        if (sousTitre != null && sousTitre.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              sousTitre,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (etiquettes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: etiquettes,
            ),
          ),
      ],
    );
  }
}

/// Section d'une fiche dans une carte (`cardTheme` : `surfaceContainerLow`,
/// rayon `AppTheme.rayon`, bord `outlineVariant`), précédée d'un espace de 16 :
/// deux cartes qui se suivent sont espacées de 16.
///
/// Marge intérieure de 16 sur les côtés et en bas. Sous [kCompactMaxWidth], la
/// carte déborde de [kDebordCarteCompact] de chaque côté de sa colonne et sa
/// marge latérale tombe à 8 : son contenu reste aligné sur l'en-tête de la
/// fiche et garde, à 200 %, la largeur qu'il avait sans carte.
///
/// En haut, la marge de 24 du [TitreSection] qui ouvre la carte : le [titre]
/// de la carte, ou, sans [titre], celui du bloc qui en est le premier enfant
/// (« Coût avec vos prix », « Relevé de fermentation »). Une carte [repliable]
/// ne contient qu'une [SectionRepliable] : sans marge basse, son titre est
/// centré dans sa ligne.
class CarteSection extends StatelessWidget {
  const CarteSection({
    super.key,
    this.titre,
    this.trailing,
    this.repliable = false,
    required this.children,
  });

  /// Titre de section en tête de la carte ; `null` : le premier enfant porte
  /// le sien.
  final String? titre;

  /// Texte d'appoint à droite du titre (« 7 · 5,2 kg »).
  final String? trailing;

  /// Vrai : la carte ne contient qu'une [SectionRepliable].
  final bool repliable;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final titre = this.titre;
    final compact = MediaQuery.sizeOf(context).width < kCompactMaxWidth;
    final debord = compact ? kDebordCarteCompact : 0.0;
    final cote = compact ? 16 - kDebordCarteCompact : 16.0;
    // Chaque enfant garde son propre nœud de lecture : la carte ne réunit pas
    // ses textes en un seul.
    final carte = Card(
      semanticContainer: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(cote, 0, cote, repliable ? 0 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titre != null) TitreSection(titre, trailing: trailing),
            ...children,
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: debord == 0
          ? carte
          : LayoutBuilder(
              // Plus large que la colonne, centrée : le débord se peint sur la
              // marge de la fiche, sans rien qui s'y touche.
              builder: (context, constraints) => OverflowBox(
                fit: OverflowBoxFit.deferToChild,
                minWidth: constraints.maxWidth + 2 * debord,
                maxWidth: constraints.maxWidth + 2 * debord,
                child: carte,
              ),
            ),
    );
  }
}

/// Section repliable d'une fiche : titre déclaré comme en-tête, résumé à droite.
///
/// [storageKey] (identifiant unique de la section dans la page) garde l'état ouvert
/// quand un `ListView` détruit le bloc hors de l'écran. [ouvert] : état initial.
/// [margeHorizontale] : retrait du titre et de la flèche, quand la section est
/// posée dans une liste sans marge dont les lignes portent la leur (Mes prix).
class SectionRepliable extends StatelessWidget {
  const SectionRepliable({
    super.key,
    required this.titre,
    required this.storageKey,
    required this.children,
    this.resume,
    this.ouvert = false,
    this.niveau = NiveauTitre.section,
    this.margeHorizontale = 0,
  });

  final String titre;
  final String storageKey;
  final String? resume;
  final bool ouvert;
  final List<Widget> children;

  /// [NiveauTitre.sousSection] sous un autre titre de section.
  final NiveauTitre niveau;
  final double margeHorizontale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = resume;
    return ExpansionTile(
      key: PageStorageKey<String>(storageKey),
      initiallyExpanded: ouvert,
      tilePadding: EdgeInsets.symmetric(horizontal: margeHorizontale),
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
