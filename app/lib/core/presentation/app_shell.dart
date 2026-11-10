import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/session_user.dart';
import '../../features/auth/presentation/access_providers.dart';
import '../../features/auth/presentation/sign_out.dart';
import '../../features/brew_day/presentation/reprise_brassage.dart';
import '../providers.dart';
import '../router/routes.dart';
import 'bandeau_hors_ligne.dart';
import 'breakpoints.dart';

/// Destination de la navigation principale.
class ShellDestination {
  const ShellDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _recipes = ShellDestination(
  path: AppRoutes.recipes,
  label: 'Recettes',
  icon: Icons.menu_book_outlined,
  selectedIcon: Icons.menu_book,
);
const _brews = ShellDestination(
  path: AppRoutes.brews,
  label: 'Brassins',
  icon: Icons.science_outlined,
  selectedIcon: Icons.science,
);
const _equipment = ShellDestination(
  path: AppRoutes.equipment,
  label: 'Équipements',
  icon: Icons.kitchen_outlined,
  selectedIcon: Icons.kitchen,
);
const _admin = ShellDestination(
  path: AppRoutes.admin,
  label: 'Admin',
  icon: Icons.admin_panel_settings_outlined,
  selectedIcon: Icons.admin_panel_settings,
);

/// Destinations visibles : Admin pour l'administrateur seul.
List<ShellDestination> shellDestinations({required bool isAdmin}) => [
  _recipes,
  _brews,
  _equipment,
  if (isAdmin) _admin,
];

/// Coquille de l'accueil : barre du haut, navigation adaptée à la largeur, bandeau
/// hors ligne. Le titre et le bouton retour viennent de la route (`PageDeCoquille`).
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.title,
    this.backTo,
    required this.child,
  });

  /// Chemin courant (`GoRouterState.uri.path`).
  final String location;

  /// Titre de la barre du haut.
  final String title;

  /// Chemin du bouton retour ; `null` pour une destination principale.
  final String? backTo;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessStateProvider);
    // Le routeur n'affiche la coquille qu'à un membre ; pendant une transition,
    // l'état peut encore être un autre.
    final granted = access is AccessGranted ? access : null;
    final destinations = shellDestinations(
      isAdmin: granted?.member.isAdmin ?? false,
    );
    final selected = _selectedIndex(destinations);
    final back = backTo;

    void goTo(int index) => context.go(destinations[index].path);

    final appBar = AppBar(
      title: Text(title),
      leading: back == null
          ? null
          : BackButton(onPressed: () => context.go(back)),
      automaticallyImplyLeading: false,
      actions: [
        if (granted != null) _AccountMenu(user: granted.user),
        const SizedBox(width: 8),
      ],
    );

    final offline = granted?.offline ?? false;

    /// Bandeau en pleine largeur au-dessus du contenu, centré ou non.
    Widget withBanner(Widget body) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline) const BandeauHorsLigne(),
        Expanded(
          child: RepriseBrassage(location: location, child: body),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = WindowSize.of(constraints.maxWidth);
        if (size == WindowSize.compact) {
          return Scaffold(
            appBar: appBar,
            body: withBanner(child),
            bottomNavigationBar: NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: goTo,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
          );
        }
        final expanded = size == WindowSize.expanded;
        return Scaffold(
          appBar: appBar,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Défilable : avec un grand texte ou un écran bas, les destinations
              // dépassent la hauteur disponible.
              LayoutBuilder(
                builder: (context, railConstraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: railConstraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: selected,
                        onDestinationSelected: goTo,
                        extended: expanded,
                        labelType: expanded
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        destinations: [
                          for (final d in destinations)
                            NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: Text(d.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: withBanner(
                  expanded
                      ? Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: kContentMaxWidth,
                            ),
                            child: child,
                          ),
                        )
                      : child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  int _selectedIndex(List<ShellDestination> destinations) {
    for (var i = 0; i < destinations.length; i++) {
      if (location == destinations[i].path ||
          location.startsWith('${destinations[i].path}/')) {
        return i;
      }
    }
    return 0;
  }
}

/// Avatar Google et menu du compte : nom, e-mail, version, Nouveautés, déconnexion.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.user});

  final SessionUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);
    final name = user.displayName?.trim();
    final initial =
        (name != null && name.isNotEmpty ? name : (user.email ?? '?'))
            .characters
            .first
            .toUpperCase();
    final photo = user.photoUrl;

    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kAccountMenuMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null && name.isNotEmpty)
                  Text(name, style: theme.textTheme.titleMedium),
                if (user.email != null)
                  Text(user.email!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  version == null ? 'Version indisponible' : 'Version $version',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.new_releases_outlined),
          onPressed: () => unawaited(context.push(AppRoutes.news)),
          child: const Text('Nouveautés'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => signOutFrom(context, ref),
          child: const Text('Se déconnecter'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Mon compte',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: CircleAvatar(
          radius: 16,
          foregroundImage: photo == null ? null : NetworkImage(photo),
          onForegroundImageError: photo == null
              ? null
              : (error, stackTrace) => ref
                    .read(errorReportServiceProvider)
                    .reportError(
                      feature: 'shell.avatar',
                      error: error,
                      stackTrace: stackTrace,
                      // Ni l'URL de la photo (retirée aussi par le service), ni
                      // l'adresse : le type d'erreur et le code HTTP suffisent.
                      context: error is NetworkImageLoadException
                          ? 'photo du compte Google illisible, HTTP ${error.statusCode}'
                          : 'photo du compte Google illisible',
                    ),
          child: ExcludeSemantics(child: Text(initial)),
        ),
      ),
    );
  }
}
