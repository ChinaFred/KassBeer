import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'breakpoints.dart';

/// Ligne d'une liste : repère à gauche, titre, détails, étiquettes dessous,
/// élément à droite. Hauteur d'au moins [kLigneListeMinHeight], lue d'un bloc
/// par les lecteurs d'écran.
///
/// [icone] : repère dans un disque de 40 px (`secondaryContainer`, ou
/// `errorContainer` pour un document illisible quand [erreur] est vrai).
/// [details] : lignes sous le titre ; un `Text` sans style y prend
/// `bodyMedium` en `onSurfaceVariant`. [etiquettes] : `Etiquette` ou pastilles
/// rangées sous les détails. [trailing] : élément passif à droite, lu avec la
/// ligne. [action] : bouton à droite, hors de la zone d'appui, lu à part.
class LigneListe extends StatelessWidget {
  const LigneListe({
    super.key,
    required this.titre,
    this.details = const [],
    this.etiquettes = const [],
    this.icone,
    this.iconeLabel,
    this.erreur = false,
    this.trailing,
    this.chevron = false,
    this.action,
    this.onTap,
    this.selected = false,
    this.titreMaxLignes,
    this.semanticsLabel,
  });

  final String titre;
  final List<Widget> details;
  final List<Widget> etiquettes;
  final IconData? icone;

  /// Lecture du repère quand il porte une information (type d'un ticket) ;
  /// `null` : le repère est décoratif et n'est pas lu.
  final String? iconeLabel;

  /// Document illisible : repère en ton d'erreur.
  final bool erreur;
  final Widget? trailing;

  /// Flèche « ouvrir » à droite, décorative.
  final bool chevron;
  final Widget? action;
  final VoidCallback? onTap;

  /// Ligne affichée à côté de la liste (fiche ouverte en grand écran).
  final bool selected;

  /// Lignes du titre au plus, coupé par « … » ; `null` : sans limite.
  final int? titreMaxLignes;

  /// Lecture de la ligne entière, à la place de ses textes : un seul nœud qui
  /// porte l'appui. `null` : les textes de la ligne, fusionnés.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titreCouleur = selected ? scheme.onSecondaryContainer : null;
    final detailCouleur = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final forme = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.rayonChamp),
    );
    final icone = this.icone;
    final trailing = this.trailing;
    final action = this.action;

    Widget? repere;
    if (icone != null) {
      final (fond, avant) = erreur
          ? (scheme.errorContainer, scheme.onErrorContainer)
          : selected
          ? (scheme.secondary, scheme.onSecondary)
          : (scheme.secondaryContainer, scheme.onSecondaryContainer);
      final disque = SizedBox.square(
        dimension: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
          child: Icon(icone, size: 24, color: avant),
        ),
      );
      final label = iconeLabel;
      repere = label == null
          ? ExcludeSemantics(child: disque)
          : Semantics(
              label: label,
              child: ExcludeSemantics(child: disque),
            );
    }

    final contenu = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kLigneListeMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            if (repere != null) ...[repere, const SizedBox(width: 16)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titre,
                    maxLines: titreMaxLignes,
                    overflow: titreMaxLignes == null
                        ? null
                        : TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: titreCouleur,
                    ),
                  ),
                  if (details.isNotEmpty)
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: detailCouleur,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: details,
                      ),
                    ),
                  if (etiquettes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: etiquettes,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            if (chevron) ...[
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: Icon(Icons.chevron_right, color: detailCouleur),
              ),
            ],
          ],
        ),
      ),
    );

    final tap = onTap;
    final zone = tap == null
        ? contenu
        : InkWell(onTap: tap, customBorder: forme, child: contenu);
    final label = semanticsLabel;
    // `selected` nul hors sélection : une ligne ordinaire n'est pas lue « non
    // sélectionnée ».
    final lue = label == null
        ? MergeSemantics(
            child: Semantics(
              button: tap != null,
              selected: selected ? true : null,
              child: zone,
            ),
          )
        : Semantics(
            button: tap != null,
            selected: selected ? true : null,
            label: label,
            onTap: tap,
            excludeSemantics: true,
            child: zone,
          );

    // Material propre : l'encre se peint sur lui, et non sous le fond d'une
    // transition de page posé au-dessus du Material de la page.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        type: selected ? MaterialType.canvas : MaterialType.transparency,
        color: selected ? scheme.secondaryContainer : null,
        shape: forme,
        clipBehavior: Clip.antiAlias,
        child: action == null
            ? lue
            : Row(
                children: [
                  Expanded(child: lue),
                  action,
                  const SizedBox(width: 8),
                ],
              ),
      ),
    );
  }
}
