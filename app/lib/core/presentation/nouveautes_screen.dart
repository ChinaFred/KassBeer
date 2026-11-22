import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/tickets/presentation/tickets_providers.dart'
    show ouvrirLienProvider;
import '../data/nouveautes.dart';
import '../providers.dart';
import '../router/routes.dart';
import 'etats.dart';
import 'etiquette.dart';
import 'formats.dart';
import 'page_secondaire.dart';

/// Écran « Nouveautés », ouvert depuis le menu du compte : les dernières versions
/// qui ont une entrée « fonctionnel » au CHANGELOG, livrées avec l'application.
class NouveautesScreen extends ConsumerWidget {
  const NouveautesScreen({super.key});

  static const errorMessage = "Impossible d'afficher les nouveautés.";
  static const emptyMessage = 'Aucune nouveauté à afficher.';
  static const voirDetail = 'Voir le détail';
  static const masquerDetail = 'Masquer le détail';
  static const journalComplet =
      'Journal complet sur GitHub, versions plus récentes comprises';
  static const lienEchec = "Le lien n'a pas pu s'ouvrir.";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(nouveautesProvider);
    // `package_info_plus` rend « 0.1.13 » ; un éventuel « +14 » est retiré.
    final installed = ref.watch(appVersionProvider)?.split('+').first;

    final Widget body;
    final versions = async.value;
    if (versions != null) {
      body = versions.isEmpty
          ? EtatVide(
              icon: Icons.new_releases_outlined,
              message: emptyMessage,
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text("Revenir à l'accueil"),
              ),
            )
          : _ListeNouveautes(versions: versions, installed: installed);
    } else if (async.hasError) {
      body = EtatErreur(
        message: errorMessage,
        retrying: async.isLoading,
        retryingLabel: 'Lecture en cours',
        onRetry: () => ref.invalidate(nouveautesProvider),
      );
    } else {
      body = const EtatChargement(label: 'Chargement des nouveautés');
    }
    return PageSecondaire(titre: 'Nouveautés', body: body);
  }
}

class _ListeNouveautes extends ConsumerWidget {
  const _ListeNouveautes({required this.versions, required this.installed});

  final List<Nouveaute> versions;
  final String? installed;

  /// Ouvre le journal complet. Un refus du système (hors ligne, aucun
  /// navigateur) n'est pas rapporté ; une exception passe par `reportError`.
  Future<void> _ouvrirJournal(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await ref.read(ouvrirLienProvider)(kJournalComplet);
    } catch (error, stackTrace) {
      ref
          .read(errorReportServiceProvider)
          .reportError(
            feature: 'nouveautes.open_changelog',
            error: error,
            stackTrace: stackTrace,
            context: 'lien du journal complet',
          );
    }
    if (opened) return;
    messenger.showSnackBar(
      const SnackBar(content: Text(NouveautesScreen.lienEchec)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final installedVersion = installed;
    final intro = installedVersion == null
        ? 'Version installée indisponible.'
        : 'Version installée : $installedVersion.';
    return SelectionArea(
      child: ListView(
        padding: PageSecondaire.marges(context, const EdgeInsets.all(16)),
        children: [
          Text(
            '$intro Seules les versions qui changent ce que vous voyez '
            'sont listées.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          for (final v in versions)
            _CarteVersion(
              nouveaute: v,
              installed: v.version == installedVersion,
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              hint: 'Ouvre le navigateur',
              child: TextButton.icon(
                onPressed: () => _ouvrirJournal(context, ref),
                icon: const Icon(Icons.open_in_new),
                label: const Text(NouveautesScreen.journalComplet),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteVersion extends StatefulWidget {
  const _CarteVersion({required this.nouveaute, required this.installed});

  final Nouveaute nouveaute;
  final bool installed;

  @override
  State<_CarteVersion> createState() => _CarteVersionState();
}

/// Le détail est replié à l'ouverture ; l'état n'est pas mémorisé.
///
/// Une carte dépliée reste en mémoire pendant le défilement de la liste.
class _CarteVersionState extends State<_CarteVersion>
    with AutomaticKeepAliveClientMixin {
  var _deplie = false;

  @override
  bool get wantKeepAlive => _deplie;

  void _basculer() => setState(() {
    _deplie = !_deplie;
    updateKeepAlive();
  });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final nouveaute = widget.nouveaute;
    final installed = widget.installed;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  container: true,
                  child: Text(
                    'Version ${nouveaute.version}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (installed) const Etiquette(label: 'Installée'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              formatDateLongue(nouveaute.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            for (final summary in nouveaute.summaries) ...[
              const SizedBox(height: 12),
              Text(summary, style: theme.textTheme.bodyLarge),
            ],
            if (nouveaute.paragraphs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Semantics(
                label: _deplie
                    ? '${NouveautesScreen.masquerDetail} de la version '
                          '${nouveaute.version}'
                    : '${NouveautesScreen.voirDetail} de la version '
                          '${nouveaute.version}',
                button: true,
                container: true,
                expanded: _deplie,
                excludeSemantics: true,
                onTap: _basculer,
                child: TextButton.icon(
                  onPressed: _basculer,
                  icon: Icon(_deplie ? Icons.expand_less : Icons.expand_more),
                  label: Text(
                    _deplie
                        ? NouveautesScreen.masquerDetail
                        : NouveautesScreen.voirDetail,
                  ),
                ),
              ),
              if (_deplie)
                for (final paragraph in nouveaute.paragraphs) ...[
                  const SizedBox(height: 12),
                  Text(paragraph, style: theme.textTheme.bodyLarge),
                ],
            ],
          ],
        ),
      ),
    );
  }
}
