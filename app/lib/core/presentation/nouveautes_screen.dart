import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/nouveautes.dart';
import '../providers.dart';
import '../router/routes.dart';
import 'breakpoints.dart';
import 'etats.dart';
import 'etiquette.dart';
import 'formats.dart';

/// Écran « Nouveautés », ouvert depuis le menu du compte : les dernières versions
/// qui ont une entrée « fonctionnel » au CHANGELOG, livrées avec l'application.
class NouveautesScreen extends ConsumerWidget {
  const NouveautesScreen({super.key});

  static const errorMessage = "Impossible d'afficher les nouveautés.";
  static const emptyMessage = 'Aucune nouveauté à afficher.';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveautés'),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
      ),
      body: SafeArea(top: false, child: body),
    );
  }
}

class _ListeNouveautes extends StatelessWidget {
  const _ListeNouveautes({required this.versions, required this.installed});

  final List<Nouveaute> versions;
  final String? installed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installedVersion = installed;
    final intro = installedVersion == null
        ? 'Version installée indisponible.'
        : 'Version installée : $installedVersion.';
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteVersion extends StatelessWidget {
  const _CarteVersion({required this.nouveaute, required this.installed});

  final Nouveaute nouveaute;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            for (final paragraph in nouveaute.paragraphs) ...[
              const SizedBox(height: 12),
              Text(paragraph, style: theme.textTheme.bodyLarge),
            ],
          ],
        ),
      ),
    );
  }
}
