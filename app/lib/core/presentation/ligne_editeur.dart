import 'package:flutter/material.dart';

/// Ligne d'ingrédient, de palier ou d'étape : un appui ouvre son formulaire ; ⋮
/// propose « Monter », « Descendre », « Dupliquer », « Retirer ».
///
/// Sans [onTap], la ligne n'a pas de formulaire (bloc tiré de la recette dans un
/// processus) : elle n'est pas un bouton. Sans [onRemove], elle ne se retire pas ;
/// sans aucune action, ⋮ disparaît.
class LigneEditeur extends StatelessWidget {
  const LigneEditeur({
    super.key,
    required this.title,
    required this.details,
    this.onTap,
    this.onRemove,
    this.warning,
    this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
    this.icone,
    this.semanticsLabel,
  });

  final String title;
  final List<String> details;
  final String? warning;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  /// Icône en tête, sur fond `secondaryContainer` (bloc de la recette).
  final IconData? icone;

  /// Texte lu par le lecteur d'écran à la place du titre et des détails.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = details.join(' · ');
    final w = warning;
    final tap = onTap;
    final icon = icone;
    final description =
        semanticsLabel ??
        '$title, ${details.join(', ')}${w == null ? '' : '. $w'}';
    final actions = [
      if (onMoveUp case final up?)
        PopupMenuItem(value: up, child: const Text('Monter')),
      if (onMoveDown case final down?)
        PopupMenuItem(value: down, child: const Text('Descendre')),
      if (onDuplicate case final duplicate?)
        PopupMenuItem(value: duplicate, child: const Text('Dupliquer')),
      if (onRemove case final remove?)
        PopupMenuItem(value: remove, child: const Text('Retirer')),
    ];
    final Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (text.isNotEmpty)
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (w != null)
                    Text(
                      w,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        Expanded(
          // Un seul nœud par ligne. Avec un formulaire, il porte l'action : le
          // double appui du lecteur d'écran l'ouvre.
          child: tap == null
              ? Semantics(
                  label: '$description.',
                  excludeSemantics: true,
                  child: content,
                )
              : Semantics(
                  button: true,
                  label: '$description. Modifier.',
                  onTap: tap,
                  excludeSemantics: true,
                  child: InkWell(onTap: tap, child: content),
                ),
        ),
        if (actions.isNotEmpty)
          // ticket: /recettes/nouvelle/menu/ligne, /recettes/:id/modifier/menu/ligne, /recettes/:id/chronologie/menu/ligne, /processus/nouveau/menu/ligne, /processus/:id/modifier/menu/ligne
          PopupMenuButton<VoidCallback>(
            tooltip: 'Actions sur « $title »',
            constraints: const BoxConstraints(minWidth: 160),
            onSelected: (action) => action(),
            itemBuilder: (_) => actions,
          ),
      ],
    );
  }
}
