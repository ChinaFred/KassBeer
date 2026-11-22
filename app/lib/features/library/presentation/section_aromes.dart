import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/aromes_houblon.dart';
import 'library_providers.dart';

/// Textes de la section « Arômes » de la fiche d'un houblon (ADR-013) ; les
/// états communs servent aussi à la fiche d'une levure (ADR-017).
abstract final class TextesAromes {
  static const titre = 'Arômes';
  static const chargement = 'Chargement des arômes';
  static const confianceFaible = 'Confiance faible';
  static const inconnu = 'Aucune description : houblon trop peu documenté.';
  static const aucunUsageConnu =
      'Mettez l\'application à jour pour lire ces descriptions.';
  static const illisible =
      'Les arômes ne peuvent pas s\'afficher. L\'erreur est signalée à '
      'l\'administrateur.';
  static const panne =
      'Impossible de lire les arômes. L\'erreur est signalée à '
      'l\'administrateur.';
  static const horsLigne =
      'Arômes indisponibles hors ligne. Ils s\'affichent au retour du réseau.';

  /// Mention en tête de la section, sans état de relecture (décision de
  /// l'utilisateur du 2026-11-21).
  static const mention = 'Texte rédigé par une IA (Claude)';

  static String usage(UsageArome usage) => switch (usage) {
    UsageArome.firstWort => 'Premier moût',
    UsageArome.bittering => 'Ébullition longue (amertume)',
    UsageArome.lateBoil => 'Fin d\'ébullition (10 min ou moins)',
    UsageArome.whirlpool => 'Whirlpool',
    UsageArome.dryHop => 'Houblonnage à cru',
  };
}

/// Section « Arômes » de la fiche du houblon [id] : un `get` de
/// `beer_hop_aromas/{id}` à l'ouverture. Document absent : rien ne s'affiche.
/// Le reste de la fiche n'attend pas la lecture.
class SectionAromes extends ConsumerWidget {
  const SectionAromes({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CadreAromes<AromesHoublon>(
      async: ref.watch(aromesHoublonProvider(id)),
      offline: ref.watch(grantedAccessProvider)?.offline ?? false,
      onRetry: () => ref.invalidate(aromesHoublonProvider(id)),
      contenu: _aromes,
    );
  }

  List<Widget> _aromes(BuildContext context, AromesHoublon aromes) {
    final theme = Theme.of(context);
    return switch (aromes) {
      AromesInconnus() => const [
        MentionAromes(),
        TexteAbsent(TextesAromes.inconnu),
      ],
      AromesDecrits() => [
        const MentionAromes(),
        if (aromes.confiance == ConfianceArome.faible)
          const ConfianceFaibleAromes(),
        DescripteursAromes(descripteurs: aromes.descripteurs),
        if (aromes.usages.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: TexteAbsent(TextesAromes.aucunUsageConnu),
          ),
        for (final usage in UsageArome.values)
          if (aromes.usages[usage] case final texte?) ...[
            TitreSection(
              TextesAromes.usage(usage),
              niveau: NiveauTitre.sousSection,
            ),
            Text(texte, style: theme.textTheme.bodyLarge),
          ],
      ],
    };
  }
}

/// Cadre commun aux sections « Arômes » d'un houblon et d'une levure : titre,
/// chargement, panne en ligne avec « Réessayer », indisponible hors ligne,
/// document illisible ; [contenu] pour un document trouvé. Document absent :
/// rien ne s'affiche.
class CadreAromes<T> extends StatelessWidget {
  const CadreAromes({
    super.key,
    required this.async,
    required this.offline,
    required this.onRetry,
    required this.contenu,
  });

  final AsyncValue<RechercheDocument<T>> async;
  final bool offline;
  final VoidCallback onRetry;
  final List<Widget> Function(BuildContext context, T aromes) contenu;

  @override
  Widget build(BuildContext context) {
    final value = async.value;
    final List<Widget> enfants;
    if (value == null) {
      if (!async.hasError) {
        enfants = [
          Semantics(
            liveRegion: true,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: IndicateurBouton(label: TextesAromes.chargement),
            ),
          ),
        ];
      } else if (offline) {
        enfants = const [TexteAbsent(TextesAromes.horsLigne)];
      } else {
        enfants = [_Panne(retrying: async.isLoading, onRetry: onRetry)];
      }
    } else {
      switch (value) {
        case DocumentAbsent():
          return const SizedBox.shrink();
        case DocumentAbsentDuCache():
          enfants = const [TexteAbsent(TextesAromes.horsLigne)];
        case DocumentIllisibleTrouve():
          enfants = const [
            Encadre(
              ton: TonEncadre.erreur,
              icone: Icons.error_outline,
              liveRegion: true,
              child: Text(TextesAromes.illisible),
            ),
          ];
        case DocumentTrouve(value: final aromes):
          enfants = contenu(context, aromes);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const TitreSection(TextesAromes.titre), ...enfants],
    );
  }
}

/// Mention IA, sous le titre « Arômes », avant les descripteurs.
class MentionAromes extends StatelessWidget {
  const MentionAromes({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        TextesAromes.mention,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Étiquette « Confiance faible ».
class ConfianceFaibleAromes extends StatelessWidget {
  const ConfianceFaibleAromes({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Etiquette(
          label: TextesAromes.confianceFaible,
          ton: TonEtiquette.neutre,
          icon: Icons.info_outline,
        ),
      ),
    );
  }
}

/// Descripteurs en étiquettes, lus d'un seul libellé « Descripteurs : … ».
/// Liste vide : rien ne s'affiche.
class DescripteursAromes extends StatelessWidget {
  const DescripteursAromes({super.key, required this.descripteurs});

  final List<DescripteurArome> descripteurs;

  @override
  Widget build(BuildContext context) {
    if (descripteurs.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Descripteurs : ${descripteurs.map((d) => d.label).join(', ')}',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final d in descripteurs)
            ExcludeSemantics(child: Etiquette(label: d.label)),
        ],
      ),
    );
  }
}

/// Panne de lecture en ligne : message et « Réessayer », qui relit.
class _Panne extends StatelessWidget {
  const _Panne({required this.retrying, required this.onRetry});

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
          const Text(TextesAromes.panne),
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
