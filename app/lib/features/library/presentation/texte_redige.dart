import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';

/// Textes communs aux descriptions rédigées par l'API Claude : arômes d'un
/// houblon (ADR-013) et d'une levure (ADR-017), description d'un divers
/// (ADR-018). Commun aux trois natures depuis ADR-019.
abstract final class TextesRediges {
  static const confianceFaible = 'Confiance faible';

  /// Description sans aucune clé connue de cette version.
  static const miseAJour =
      'Mettez l\'application à jour pour lire ces descriptions.';

  /// Mention de chaque texte rédigé, sans état de relecture (décision de
  /// l'utilisateur du 2026-11-21, ADR-019 décision 4).
  static const mention = 'Texte rédigé par une IA (Claude)';
}

/// Textes du cadre d'une section rédigée : titre de la section et états de la
/// lecture, propres à chaque section (« Arômes », « Utilisation »).
@immutable
class TextesCadre {
  const TextesCadre({
    required this.titre,
    required this.chargement,
    required this.horsLigne,
    required this.illisible,
    required this.panne,
  });

  final String titre;
  final String chargement;
  final String horsLigne;
  final String illisible;
  final String panne;
}

/// Cadre commun aux sections rédigées d'une fiche (arômes d'un houblon ou
/// d'une levure, description d'un divers) : titre, chargement, panne en ligne
/// avec « Réessayer », indisponible hors ligne, document illisible ; [contenu]
/// pour un document trouvé. Document absent : rien ne s'affiche.
class CadreTexteRedige<T> extends StatelessWidget {
  const CadreTexteRedige({
    super.key,
    required this.textes,
    required this.async,
    required this.offline,
    required this.onRetry,
    required this.contenu,
  });

  final TextesCadre textes;
  final AsyncValue<RechercheDocument<T>> async;
  final bool offline;
  final VoidCallback onRetry;
  final List<Widget> Function(BuildContext context, T document) contenu;

  @override
  Widget build(BuildContext context) {
    final value = async.value;
    final List<Widget> enfants;
    if (value == null) {
      if (!async.hasError) {
        enfants = [
          Semantics(
            liveRegion: true,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IndicateurBouton(label: textes.chargement),
            ),
          ),
        ];
      } else if (offline) {
        enfants = [TexteAbsent(textes.horsLigne)];
      } else {
        enfants = [
          PanneTexteRedige(
            message: textes.panne,
            retrying: async.isLoading,
            onRetry: onRetry,
          ),
        ];
      }
    } else {
      switch (value) {
        case DocumentAbsent():
          return const SizedBox.shrink();
        case DocumentAbsentDuCache():
          enfants = [TexteAbsent(textes.horsLigne)];
        case DocumentIllisibleTrouve():
          enfants = [
            Encadre(
              ton: TonEncadre.erreur,
              icone: Icons.error_outline,
              liveRegion: true,
              child: Text(textes.illisible),
            ),
          ];
        case DocumentTrouve(value: final document):
          enfants = contenu(context, document);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [TitreSection(textes.titre), ...enfants],
    );
  }
}

/// Mention « Texte rédigé par une IA (Claude) », en `bodyMedium`, couleur
/// `onSurfaceVariant`.
class MentionTexteRedige extends StatelessWidget {
  const MentionTexteRedige({
    super.key,
    this.padding = const EdgeInsets.only(bottom: 8),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        TextesRediges.mention,
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

/// Libellés d'une liste fermée (descripteurs d'un houblon ou d'une levure,
/// rôles d'un divers) en étiquettes, lus d'un seul nœud « [titre] : a, b ».
/// Liste vide : rien ne s'affiche.
class EtiquettesRedigees extends StatelessWidget {
  const EtiquettesRedigees({
    super.key,
    required this.titre,
    required this.libelles,
  });

  /// « Descripteurs », « Rôles ».
  final String titre;
  final List<String> libelles;

  @override
  Widget build(BuildContext context) {
    if (libelles.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: '$titre : ${libelles.join(', ')}',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final l in libelles)
            ExcludeSemantics(child: Etiquette(label: l)),
        ],
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
