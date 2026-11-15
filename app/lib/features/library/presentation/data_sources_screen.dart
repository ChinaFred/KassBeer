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
      'normalisées, origines ramenées à une liste de pays, doublons fusionnés '
      'et renommés.';
  static const fabricants =
      'Levures et bactéries : noms, type, forme, atténuation et températures '
      'recopiés des fiches techniques que chaque fabricant publie en accès '
      'libre. Ces valeurs remplacent celles de Brewtarget pour les mêmes '
      'levures. Les textes des fiches ne sont pas repris.';

  /// Une ligne par fabricant, dans l'ordre alphabétique : date du relevé et
  /// floculation.
  static const fabricantsLignes = [
    'Fermentis : fiches relevées le 14 novembre 2026, sans floculation.',
    'Mangrove Jack\'s : fiches relevées le 15 novembre 2026, floculation '
        'comprise.',
  ];
  static const diyDog =
      'Recettes publiques : recettes DIY Dog publiées par BrewDog, reprises '
      'pour un usage privé (version e6c12ab de leur transcription).';
  static const srm2hex =
      'Teintes de la page « Échelle des couleurs » et de la barre de couleur d\'un '
      'style : 400 teintes reprises de la bibliothèque libre srm2hex, version '
      '1.0.2, sous licence MIT. Seule la table des teintes est reprise. La '
      'bibliothèque ne porte aucune mention de copyright ; voici le texte de '
      'sa licence.';

  /// Texte d'autorisation de la licence MIT de srm2hex, reproduit dans
  /// l'application livrée comme la licence l'exige (« included in all
  /// copies »). Le paquet n'a pas de ligne de copyright.
  static const licenceMit =
      'Permission is hereby granted, free of charge, to any person obtaining '
      'a copy of this software and associated documentation files (the '
      '"Software"), to deal in the Software without restriction, including '
      'without limitation the rights to use, copy, modify, merge, publish, '
      'distribute, sublicense, and/or sell copies of the Software, and to '
      'permit persons to whom the Software is furnished to do so, subject to '
      'the following conditions:\n\n'
      'The above copyright notice and this permission notice shall be '
      'included in all copies or substantial portions of the Software.\n\n'
      'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS '
      'OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF '
      'MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. '
      'IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY '
      'CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, '
      'TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE '
      'SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.';

  static const aromesHoublons =
      'Arômes des houblons : textes rédigés pour Kass\'Beer par une IA (Claude, '
      'd\'Anthropic), à partir du nom, des autres noms, de l\'origine, des '
      'acides et de l\'usage de chaque houblon. Ils ne sont copiés d\'aucune '
      'source. L\'administrateur relit ceux des houblons utilisés dans les '
      'recettes du groupe ; les autres sont marqués « non relu ». Un texte peut '
      'contenir des erreurs.';
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
        child: Builder(
          builder: (context) => ListView(
            padding: PageSecondaire.marges(
              context,
              const EdgeInsets.fromLTRB(16, 8, 16, 32),
            ),
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
              for (final ligne in fabricantsLignes) paragraphe(ligne),
              const TitreSection('DIY Dog'),
              paragraphe(diyDog),
              const TitreSection('srm2hex'),
              paragraphe(srm2hex),
              paragraphe(licenceMit),
              const TitreSection('Descriptions aromatiques'),
              paragraphe(aromesHoublons),
            ],
          ),
        ),
      ),
    );
  }
}
