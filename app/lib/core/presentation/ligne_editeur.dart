import 'package:flutter/material.dart';

/// Ligne d'ingrédient ou de palier : un appui ouvre son formulaire ; ⋮ propose
/// « Monter », « Descendre », « Dupliquer », « Retirer ».
class LigneEditeur extends StatelessWidget {
  const LigneEditeur({
    super.key,
    required this.title,
    required this.details,
    required this.onTap,
    required this.onRemove,
    this.warning,
    this.onDuplicate,
    this.onMoveUp,
    this.onMoveDown,
  });

  final String title;
  final List<String> details;
  final String? warning;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onDuplicate;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = details.join(' · ');
    final w = warning;
    return Row(
      children: [
        Expanded(
          // Un seul nœud qui porte l'action : le double appui du lecteur d'écran
          // ouvre le formulaire de la ligne.
          child: Semantics(
            button: true,
            label:
                '$title, ${details.join(', ')}${w == null ? '' : '. $w'}. '
                'Modifier.',
            onTap: onTap,
            excludeSemantics: true,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
              ),
            ),
          ),
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Actions sur « $title »',
          constraints: const BoxConstraints(minWidth: 160),
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            if (onMoveUp != null)
              PopupMenuItem(value: onMoveUp, child: const Text('Monter')),
            if (onMoveDown != null)
              PopupMenuItem(value: onMoveDown, child: const Text('Descendre')),
            if (onDuplicate != null)
              PopupMenuItem(value: onDuplicate, child: const Text('Dupliquer')),
            PopupMenuItem(value: onRemove, child: const Text('Retirer')),
          ],
        ),
      ],
    );
  }
}
