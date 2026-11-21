import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'breakpoints.dart';
import 'etiquette.dart';

/// Détail de la ligne d'un document illisible (recette, brassin, équipement,
/// processus, ticket).
const kDetailLigneIllisible =
    'Mettez l\'application à jour, ou prévenez l\'administrateur.';

/// Repère d'une ligne : icône de 24 px dans un disque de 40 px, en
/// `secondaryContainer`, en `secondary` sur une ligne choisie ([choisi]), en
/// `errorContainer` pour un document illisible ([erreur]). Décoratif sans
/// [label] ; lu [label] sinon (type d'un ticket).
///
/// Employé par [LigneListe], et par les lignes qui n'en sont pas (Admin ›
/// Membres, Admin › Rapports d'erreur) pour aligner leur texte sur les siennes.
class RepereDisque extends StatelessWidget {
  const RepereDisque({
    super.key,
    required this.icone,
    this.erreur = false,
    this.choisi = false,
    this.label,
  });

  final IconData icone;
  final bool erreur;
  final bool choisi;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (fond, avant) = erreur
        ? (scheme.errorContainer, scheme.onErrorContainer)
        : choisi
        ? (scheme.secondary, scheme.onSecondary)
        : (scheme.secondaryContainer, scheme.onSecondaryContainer);
    final disque = ExcludeSemantics(
      child: SizedBox.square(
        dimension: 40,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
          child: Icon(icone, size: 24, color: avant),
        ),
      ),
    );
    final label = this.label;
    return label == null ? disque : Semantics(label: label, child: disque);
  }
}

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
    this.focusNode,
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

  /// Nœud de focus de la zone d'appui, pour y rendre le focus (fiche fermée
  /// à côté de la liste) ; `null` : celui de l'`InkWell`.
  final FocusNode? focusNode;

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

    final repere = icone == null
        ? null
        : RepereDisque(
            icone: icone,
            erreur: erreur,
            choisi: selected,
            label: iconeLabel,
          );

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

    // Ligne choisie : une étiquette de ton normal, de la couleur du fond, y
    // prend un contour.
    final pose = selected ? SurLigneChoisie(child: contenu) : contenu;
    final tap = onTap;
    final zone = tap == null
        ? pose
        : InkWell(
            onTap: tap,
            focusNode: focusNode,
            customBorder: forme,
            child: pose,
          );
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
