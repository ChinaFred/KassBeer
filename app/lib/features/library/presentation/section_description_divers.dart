import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/fiche.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/description_divers.dart';
import 'library_providers.dart';
import 'texte_redige.dart';

/// Textes des sections « Utilisation » et « Goût » de la fiche d'un divers
/// (ADR-018).
abstract final class TextesDescriptionDivers {
  static const titre = 'Utilisation';
  static const titreGout = 'Goût';
  static const chargement = 'Chargement de la description';
  static const inconnu = 'Aucune description : ajout trop peu documenté.';
  static const miseAJourMoments =
      'Mettez l\'application à jour pour lire les moments d\'utilisation.';

  /// `changes_taste` faux (décision de l'utilisateur du 2026-11-21 : la
  /// section « Goût » s'affiche quand même).
  static const sansGout = 'Sans effet notable sur le goût';
  static const illisible =
      'La description ne peut pas s\'afficher. L\'erreur est signalée à '
      'l\'administrateur.';
  static const panne =
      'Impossible de lire la description. L\'erreur est signalée à '
      'l\'administrateur.';
  static const horsLigne =
      'Description indisponible hors ligne. Elle s\'affiche au retour du '
      'réseau.';

  /// Titre lu des rôles : « Rôles : Clarifier, Ajuster le pH ».
  static const titreRoles = 'Rôles';

  static const cadre = TextesCadre(
    titre: titre,
    chargement: chargement,
    horsLigne: horsLigne,
    illisible: illisible,
    panne: panne,
  );
}

/// Sections « Utilisation » et « Goût » de la fiche du divers [id], puis la
/// mention IA : un `get` de `beer_misc_descriptions/{id}` à l'ouverture.
/// Document absent : rien ne s'affiche. Le reste de la fiche n'attend pas la
/// lecture.
class SectionDescriptionDivers extends ConsumerWidget {
  const SectionDescriptionDivers({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CadreTexteRedige<DescriptionDivers>(
      textes: TextesDescriptionDivers.cadre,
      async: ref.watch(descriptionDiversProvider(id)),
      offline: ref.watch(grantedAccessProvider)?.offline ?? false,
      onRetry: () => ref.invalidate(descriptionDiversProvider(id)),
      contenu: _description,
    );
  }

  List<Widget> _description(BuildContext context, DescriptionDivers d) {
    final theme = Theme.of(context);
    const mention = MentionTexteRedige(padding: EdgeInsets.only(top: 16));
    return switch (d) {
      DiversInconnu() => [
        const TexteAbsent(TextesDescriptionDivers.inconnu),
        mention,
      ],
      DiversDecrit() => [
        if (d.confianceFaible) const EtiquetteConfianceFaible(),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(d.resume, style: theme.textTheme.bodyLarge),
        ),
        EtiquettesRedigees(
          titre: TextesDescriptionDivers.titreRoles,
          libelles: [for (final r in d.roles) r.label],
        ),
        if (d.moments.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: TexteAbsent(TextesDescriptionDivers.miseAJourMoments),
          ),
        for (final moment in kClesMoments.keys)
          if (d.moments[moment] case final texte?) ...[
            TitreSection(moment.label, niveau: NiveauTitre.sousSection),
            Text(texte, style: theme.textTheme.bodyLarge),
          ],
        const TitreSection(TextesDescriptionDivers.titreGout),
        if (d.gout case final gout?)
          Text(gout, style: theme.textTheme.bodyLarge)
        else
          const TexteAbsent(TextesDescriptionDivers.sansGout),
        mention,
      ],
    };
  }
}
