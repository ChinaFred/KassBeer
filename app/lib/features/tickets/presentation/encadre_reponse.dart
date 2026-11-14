import 'package:flutter/material.dart';

/// Encadré d'un texte de l'administrateur (« Motif du refus », « Commentaire
/// de clôture », « Réponse de l'administrateur »), sur le suivi du membre et la
/// fiche d'Admin ; et carte d'une analyse ou d'un compte rendu de livraison
/// dans les sections « Analyses » et « Livraison » de la fiche (ADR-008), par
/// [EncadreReponse.contenu].
class EncadreReponse extends StatelessWidget {
  /// Encadré d'un texte simple, avec l'icône « répondre ».
  const EncadreReponse({super.key, required this.titre, required String texte})
    : icone = Icons.reply,
      accentue = false,
      erreur = false,
      couleurIcone = null,
      sousTitre = null,
      _texte = texte,
      _corps = null;

  /// Encadré d'un contenu quelconque (corps Markdown d'une analyse).
  ///
  /// [accentue] : fond `secondaryContainer` (réponse de l'administrateur) ;
  /// [erreur] : fond `errorContainer` (blocage d'une livraison) ; sinon
  /// `surfaceContainerHigh`. [couleurIcone] remplace la couleur du texte pour
  /// l'icône (livraison terminée en `primary`). [sousTitre] : ligne lue juste
  /// après le titre (« Non publiée depuis l'application. »). Le corps reçoit
  /// sa couleur de texte de l'appelant ([encreDe]).
  const EncadreReponse.contenu({
    super.key,
    required this.titre,
    required this.icone,
    required Widget corps,
    this.accentue = false,
    this.erreur = false,
    this.couleurIcone,
    this.sousTitre,
  }) : _texte = null,
       _corps = corps;

  /// Couleur du texte d'un encadré de ce ton, pour un corps fourni par
  /// l'appelant.
  static Color encreDe(
    ColorScheme scheme, {
    bool accentue = false,
    bool erreur = false,
  }) => erreur
      ? scheme.onErrorContainer
      : accentue
      ? scheme.onSecondaryContainer
      : scheme.onSurface;

  final String titre;
  final IconData icone;
  final bool accentue;
  final bool erreur;
  final Color? couleurIcone;
  final String? sousTitre;
  final String? _texte;
  final Widget? _corps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fond = erreur
        ? scheme.errorContainer
        : accentue
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHigh;
    final encre = encreDe(scheme, accentue: accentue, erreur: erreur);
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
                  ExcludeSemantics(
                    child: Icon(icone, size: 18, color: couleurIcone ?? encre),
                  ),
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
                    color: accentue || erreur ? encre : scheme.onSurfaceVariant,
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
