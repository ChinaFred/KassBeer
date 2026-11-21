import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/presentation/encadre.dart';
import '../../../core/presentation/etats.dart';
import '../../../core/presentation/etiquette.dart';
import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/aromes_houblon.dart';
import 'library_providers.dart';

/// Textes de la section « Arômes » de la fiche d'un houblon (ADR-013).
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
  static const nonRelu = 'Texte rédigé par une IA (Claude), non relu';

  static String relu(DateTime le) =>
      'Texte rédigé par une IA (Claude), relu le ${formatDateLongue(le)}';

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
    final async = ref.watch(aromesHoublonProvider(id));
    final offline = ref.watch(grantedAccessProvider)?.offline ?? false;
    final value = async.value;
    final List<Widget> contenu;
    if (value == null) {
      if (!async.hasError) {
        contenu = [
          Semantics(
            liveRegion: true,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: IndicateurBouton(label: TextesAromes.chargement),
            ),
          ),
        ];
      } else if (offline) {
        contenu = const [TexteAbsent(TextesAromes.horsLigne)];
      } else {
        contenu = [
          _Panne(
            retrying: async.isLoading,
            onRetry: () => ref.invalidate(aromesHoublonProvider(id)),
          ),
        ];
      }
    } else {
      switch (value) {
        case DocumentAbsent():
          return const SizedBox.shrink();
        case DocumentAbsentDuCache():
          contenu = const [TexteAbsent(TextesAromes.horsLigne)];
        case DocumentIllisibleTrouve():
          contenu = const [
            Encadre(
              ton: TonEncadre.erreur,
              icone: Icons.error_outline,
              liveRegion: true,
              child: Text(TextesAromes.illisible),
            ),
          ];
        case DocumentTrouve(value: final aromes):
          contenu = _aromes(context, aromes);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const TitreSection(TextesAromes.titre), ...contenu],
    );
  }

  List<Widget> _aromes(BuildContext context, AromesHoublon aromes) {
    final theme = Theme.of(context);
    // Mention sous le titre « Arômes », avant les descripteurs.
    final mention = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        switch (aromes.reluLe) {
          final le? when aromes.relu => TextesAromes.relu(le),
          _ => TextesAromes.nonRelu,
        },
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return switch (aromes) {
      AromesInconnus() => [mention, const TexteAbsent(TextesAromes.inconnu)],
      AromesDecrits() => [
        mention,
        if (aromes.confiance == ConfianceArome.faible)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Etiquette(
                label: TextesAromes.confianceFaible,
                ton: TonEtiquette.neutre,
                icon: Icons.info_outline,
              ),
            ),
          ),
        if (aromes.descripteurs.isNotEmpty)
          Semantics(
            container: true,
            label:
                'Descripteurs : '
                '${aromes.descripteurs.map((d) => d.label).join(', ')}',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in aromes.descripteurs)
                  ExcludeSemantics(child: Etiquette(label: d.label)),
              ],
            ),
          ),
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
