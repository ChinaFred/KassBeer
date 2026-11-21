import 'package:flutter/material.dart';

import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/formats.dart';

/// Textes communs aux descriptions rédigées par l'API Claude : arômes d'un
/// houblon (ADR-013) et description d'un divers (ADR-017).
abstract final class TextesRediges {
  static const confianceFaible = 'Confiance faible';

  /// Description sans aucune clé connue de cette version.
  static const miseAJour =
      'Mettez l\'application à jour pour lire ces descriptions.';
  static const nonRelu = 'Texte rédigé par une IA (Claude), non relu';

  static String relu(DateTime le) =>
      'Texte rédigé par une IA (Claude), relu le ${formatDateLongue(le)}';
}

/// Mention « Texte rédigé par une IA (Claude), relu le `date` » ou « …, non
/// relu », en `bodyMedium`, couleur `onSurfaceVariant`.
class MentionTexteRedige extends StatelessWidget {
  const MentionTexteRedige({
    super.key,
    required this.relu,
    required this.reluLe,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  final bool relu;

  /// Date de relecture ; sans elle, le texte est dit « non relu ».
  final DateTime? reluLe;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        switch (reluLe) {
          final le? when relu => TextesRediges.relu(le),
          _ => TextesRediges.nonRelu,
        },
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Étiquette neutre « Confiance faible », alignée à gauche.
class EtiquetteConfianceFaible extends StatelessWidget {
  const EtiquetteConfianceFaible({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Etiquette(
          label: TextesRediges.confianceFaible,
          ton: TonEtiquette.neutre,
          icon: Icons.info_outline,
        ),
      ),
    );
  }
}

/// Panne de lecture en ligne : [message] et « Réessayer », qui relit ;
/// « Lecture en cours » pendant la relecture.
class PanneTexteRedige extends StatelessWidget {
  const PanneTexteRedige({
    super.key,
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Encadre(
      ton: TonEncadre.erreur,
      icone: Icons.error_outline,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: retrying ? null : onRetry,
            child: retrying
                ? const IndicateurBouton(label: 'Lecture en cours')
                : const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
