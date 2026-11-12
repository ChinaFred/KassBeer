import 'package:flutter/material.dart';

/// Encadré d'un texte de l'administrateur (« Motif du refus », « Commentaire
/// de clôture », « Réponse de l'administrateur »), sur le suivi du membre et la
/// fiche d'Admin ; et carte d'une analyse dans la section « Analyses » de la
/// fiche (ADR-008), par [EncadreReponse.contenu].
class EncadreReponse extends StatelessWidget {
  /// Encadré d'un texte simple, avec l'icône « répondre ».
  const EncadreReponse({super.key, required this.titre, required String texte})
    : icone = Icons.reply,
      accentue = false,
      sousTitre = null,
      _texte = texte,
      _corps = null;

  /// Encadré d'un contenu quelconque (corps Markdown d'une analyse).
  ///
  /// [accentue] : fond `secondaryContainer` (réponse de l'administrateur) ;
  /// sinon `surfaceContainerHigh`. [sousTitre] : ligne lue juste après le
  /// titre (« Non publiée depuis l'application. »).
  const EncadreReponse.contenu({
    super.key,
    required this.titre,
    required this.icone,
    required Widget corps,
    this.accentue = false,
    this.sousTitre,
  }) : _texte = null,
       _corps = corps;

  final String titre;
  final IconData icone;
  final bool accentue;
  final String? sousTitre;
  final String? _texte;
  final Widget? _corps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fond = accentue
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHigh;
    final encre = accentue ? scheme.onSecondaryContainer : scheme.onSurface;
    final texte = _texte;
    final sousTitre = this.sousTitre;
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fond,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Icon(icone, size: 18, color: encre)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        titre,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: encre,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (sousTitre != null) ...[
                const SizedBox(height: 4),
                Text(
                  sousTitre,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accentue ? encre : scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (texte != null)
                Text(
                  texte,
                  style: theme.textTheme.bodyLarge?.copyWith(color: encre),
                )
              else
                ?_corps,
            ],
          ),
        ),
      ),
    );
  }
}
