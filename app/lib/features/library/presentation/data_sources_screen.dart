import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/fiche.dart';
import '../../../core/presentation/page_secondaire.dart';
import '../../../core/providers.dart';
import '../../../core/router/routes.dart';
import '../../tickets/presentation/tickets_providers.dart';

/// Adresse de la licence CC BY-SA 4.0, seule adresse que cet écran ouvre.
final kLicenceCcBySa = Uri.parse(
  'https://creativecommons.org/licenses/by-sa/4.0/',
);

/// Écran « Sources des données » (ADR-005, attribution ; P20) : auteurs,
/// licences et modifications des données de la Bibliothèque. Ouvert depuis la
/// Bibliothèque et le menu du compte, pour tout membre. Texte livré avec
/// l'application : il s'affiche sans réseau.
class DataSourcesScreen extends ConsumerWidget {
  const DataSourcesScreen({super.key});

  static const title = 'Sources des données';
  static const intro =
      'La Bibliothèque reprend des données publiées par d\'autres. Voici leurs '
      'auteurs, leurs licences et ce que Kass\'Beer en a changé. Chaque fiche '
      'indique sa source et sa licence.';
  static const brewtarget =
      'Malts, sucres, houblons, levures et ajouts divers : noms et valeurs '
      'techniques tirés des fichiers 001 à 005 de Brewtarget v5.2.3 (commit '
      'ea10908). Licence GPL-3.0. Les notes et descriptions ne sont pas '
      'reprises.';
  static const bjcp =
      'Styles : noms, codes, catégories et plages chiffrées du guide BJCP 2021, '
      'lus dans le fichier 002 de Brewtarget. Les descriptions ne sont pas '
      'reprises.';
  static const beerAnalytics =
      'Une partie des ingrédients du fichier 005 de Brewtarget vient de '
      'beer-analytics.com, sous licence CC BY-SA 4.0. Modifications : unités '
      'normalisées, doublons fusionnés.';
  static const fabricants =
      'Levures de Fermentis : noms, type, forme, atténuation et températures '
      'recopiés des fiches techniques publiées par le fabricant, relevées le '
      '14 novembre 2026. Ces valeurs remplacent celles de Brewtarget pour les '
      'mêmes levures. Les textes des fiches ne sont pas repris.';
  static const diyDog =
      'Recettes publiques : recettes DIY Dog publiées par BrewDog, reprises '
      'pour un usage privé (version e6c12ab de leur transcription).';
  static const openFailure =
      'Impossible d\'ouvrir le lien. Il reste sélectionnable sur cette page.';

  Future<void> _ouvrirLicence(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ref.read(errorReportServiceProvider);
    Object? error;
    StackTrace? stackTrace;
    var opened = false;
    try {
      opened = await ref.read(ouvrirLienProvider)(kLicenceCcBySa);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
    if (opened) return;
    errors.reportError(
      feature: 'library.open_licence',
      error: error ?? StateError('ouverture refusée par le système'),
      stackTrace: stackTrace ?? StackTrace.current,
      context: 'lien de la licence CC BY-SA 4.0',
    );
    messenger.showSnackBar(const SnackBar(content: Text(openFailure)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget paragraphe(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: theme.textTheme.bodyLarge),
    );
    return PageSecondaire(
      titre: title,
      repli: AppRoutes.library,
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            paragraphe(intro),
            const TitreSection('Brewtarget'),
            paragraphe(brewtarget),
            const TitreSection('BJCP 2021'),
            paragraphe(bjcp),
            const TitreSection('beer-analytics.com'),
            paragraphe(beerAnalytics),
            paragraphe('Licence : $kLicenceCcBySa'),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _ouvrirLicence(context, ref),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Lire la licence CC BY-SA 4.0'),
              ),
            ),
            const TitreSection('Fiches des fabricants'),
            paragraphe(fabricants),
            const TitreSection('DIY Dog'),
            paragraphe(diyDog),
          ],
        ),
      ),
    );
  }
}
