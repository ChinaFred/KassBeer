import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/formats.dart';
import '../../../core/router/routes.dart';
import '../../auth/presentation/access_providers.dart';
import '../domain/aromes_houblon.dart';
import '../domain/aromes_levure.dart';
import '../domain/referentiel.dart';
import 'library_providers.dart';
import 'section_aromes.dart';

/// Textes propres à la section « Arômes » de la fiche d'une levure (ADR-017) ;
/// les autres sont ceux de [TextesAromes].
abstract final class TextesAromesLevure {
  static const inconnu = 'Aucune description : levure trop peu documentée.';
  static const profil = 'Profil';
  static const stylesConseilles = 'Styles conseillés';

  /// « En bas de plage (15 °C) » ; sans borne, sans parenthèses.
  static String basDePlage(double? celsius) =>
      _avecTemperature('En bas de plage', celsius);

  /// « En haut de plage (20 °C) » ; sans borne, sans parenthèses.
  static String hautDePlage(double? celsius) =>
      _avecTemperature('En haut de plage', celsius);

  static String _avecTemperature(String libelle, double? celsius) =>
      celsius == null ? libelle : '$libelle (${formatCelsius(celsius)})';
}

/// Section « Arômes » de la fiche d'une levure : un `get` de
/// `beer_culture_aromas/{id}` à l'ouverture (P22). Document absent : rien ne
/// s'affiche. Les sous-titres des textes de bas et de haut de plage portent les
/// bornes de [temperature], la plage de la fiche.
class SectionAromesLevure extends ConsumerWidget {
  const SectionAromesLevure({
    super.key,
    required this.id,
    required this.temperature,
  });

  final String id;
  final Plage? temperature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CadreAromes<AromesLevure>(
      async: ref.watch(aromesLevureProvider(id)),
      offline: ref.watch(grantedAccessProvider)?.offline ?? false,
      onRetry: () => ref.invalidate(aromesLevureProvider(id)),
      contenu: _aromes,
    );
  }

  List<Widget> _aromes(BuildContext context, AromesLevure aromes) {
    final theme = Theme.of(context);
    Widget texte(String titre, String contenu) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TitreSection(titre, niveau: NiveauTitre.sousSection),
        Text(contenu, style: theme.textTheme.bodyLarge),
      ],
    );
    return switch (aromes) {
      AromesLevureInconnus() => const [
        MentionAromes(),
        TexteAbsent(TextesAromesLevure.inconnu),
      ],
      AromesLevureDecrits() => [
        const MentionAromes(),
        if (aromes.confiance == ConfianceArome.faible)
          const ConfianceFaibleAromes(),
        DescripteursAromes(descripteurs: aromes.descripteurs),
        texte(TextesAromesLevure.profil, aromes.profil),
        if (aromes.basDePlage case final bas?)
          texte(TextesAromesLevure.basDePlage(temperature?.minimum), bas),
        if (aromes.hautDePlage case final haut?)
          texte(TextesAromesLevure.hautDePlage(temperature?.maximum), haut),
        if (aromes.styles.isNotEmpty) ...[
          const TitreSection(
            TextesAromesLevure.stylesConseilles,
            niveau: NiveauTitre.sousSection,
          ),
          for (final style in aromes.styles) _BoutonStyle(style: style),
        ],
      ],
    };
  }
}

/// Un style conseillé : son nom, qui ouvre sa fiche dans la Bibliothèque.
class _BoutonStyle extends StatelessWidget {
  const _BoutonStyle({required this.style});

  final StyleConseille style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          alignment: Alignment.centerLeft,
        ),
        onPressed: () => unawaited(
          context.push(
            AppRoutes.libraryEntry(SegmentBibliotheque.styles.slug, style.code),
          ),
        ),
        child: Text(style.name, softWrap: true),
      ),
    );
  }
}
