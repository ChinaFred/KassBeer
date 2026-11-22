import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/fiche.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/aromes_houblon.dart';
import 'library_providers.dart';
import 'texte_redige.dart';

/// Textes de la section « Arômes » de la fiche d'un houblon (ADR-013) ; le
/// cadre ([cadre]) sert aussi à la fiche d'une levure (ADR-017). Mention et
/// « Confiance faible » : [TextesRediges].
abstract final class TextesAromes {
  static const titre = 'Arômes';
  static const chargement = 'Chargement des arômes';
  static const inconnu = 'Aucune description : houblon trop peu documenté.';
  static const illisible =
      'Les arômes ne peuvent pas s\'afficher. L\'erreur est signalée à '
      'l\'administrateur.';
  static const panne =
      'Impossible de lire les arômes. L\'erreur est signalée à '
      'l\'administrateur.';
  static const horsLigne =
      'Arômes indisponibles hors ligne. Ils s\'affichent au retour du réseau.';

  /// Titre lu des descripteurs : « Descripteurs : agrumes, résine ».
  static const descripteurs = 'Descripteurs';

  /// Cadre des sections « Arômes » d'un houblon et d'une levure.
  static const cadre = TextesCadre(
    titre: titre,
    chargement: chargement,
    horsLigne: horsLigne,
    illisible: illisible,
    panne: panne,
  );

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
    return CadreTexteRedige<AromesHoublon>(
      textes: TextesAromes.cadre,
      async: ref.watch(aromesHoublonProvider(id)),
      offline: ref.watch(grantedAccessProvider)?.offline ?? false,
      onRetry: () => ref.invalidate(aromesHoublonProvider(id)),
      contenu: _aromes,
    );
  }

  List<Widget> _aromes(BuildContext context, AromesHoublon aromes) {
    final theme = Theme.of(context);
    // Mention sous le titre « Arômes », avant les descripteurs.
    return switch (aromes) {
      AromesInconnus() => const [
        MentionTexteRedige(),
        TexteAbsent(TextesAromes.inconnu),
      ],
      AromesDecrits() => [
        const MentionTexteRedige(),
        if (aromes.confiance == ConfianceArome.faible)
          const EtiquetteConfianceFaible(),
        EtiquettesRedigees(
          titre: TextesAromes.descripteurs,
          libelles: [for (final d in aromes.descripteurs) d.label],
        ),
        if (aromes.usages.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: TexteAbsent(TextesRediges.miseAJour),
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
