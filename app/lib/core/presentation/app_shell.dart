import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/session_user.dart';
import '../../features/auth/presentation/access_providers.dart';
import '../../features/auth/presentation/sign_out.dart';
import '../../features/brew_day/presentation/reprise_brassage.dart';
import '../../features/tickets/presentation/ticket_form_screen.dart';
import '../../features/tickets/presentation/tickets_providers.dart';
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
const _library = ShellDestination(
  path: AppRoutes.library,
  label: 'Bibliothèque',
  icon: Icons.local_library_outlined,
  selectedIcon: Icons.local_library,
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
  _library,
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
    this.fullWidth = false,
    required this.child,
  });

  /// Chemin courant (`GoRouterState.uri.path`).
  final String location;

  /// Titre de la barre du haut.
  final String title;

  /// Chemin du bouton retour ; `null` pour une destination principale.
  final String? backTo;

  /// Contenu sur toute la largeur, sans la borne de [kContentMaxWidth] (liste et
  /// fiche côte à côte).
  final bool fullWidth;
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
        if (granted != null)
          _AccountMenu(user: granted.user, isAdmin: granted.member.isAdmin),
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
            // ticket: <coquille>/menu/navigation
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
                      // ticket: <coquille>/menu/navigation
                      child: NavigationRail(
                        selectedIndex: selected,
                        onDestinationSelected: goTo,
                        extended: expanded,
                        // Largeur fixée ici : le seuil côte à côte d'Admin ›
                        // Tickets la retranche de la fenêtre.
                        minExtendedWidth: kRailEtenduWidth,
                        labelType: expanded
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        destinations: [
                          for (final d in destinations)
                            NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: Icon(d.selectedIcon),
                              label: expanded
                                  ? Text(d.label)
                                  : ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: kRailLabelMaxWidth,
                                      ),
                                      // Réduit plutôt que coupé : le rail
                                      // garde la hauteur que donne
                                      // IntrinsicHeight, sur une ligne.
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(d.label),
                                      ),
                                    ),
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
                  expanded && !fullWidth
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

/// Texte d'une pastille : « 99+ » au-delà de 99.
String textePastille(int count) => count > 99 ? '99+' : '$count';

/// Infobulle de l'avatar : « Mon compte », suivie des suivis à lire et, pour
/// l'administrateur, des tickets à traiter.
String infobulleCompte({required int unread, required int toProcess}) => [
  'Mon compte',
  if (unread == 1) '1 suivi de ticket à lire',
  if (unread > 1) '$unread suivis de ticket à lire',
  if (toProcess == 1) '1 ticket à traiter',
  if (toProcess > 1) '$toProcess tickets à traiter',
].join(', ');

/// Avatar Google et menu du compte : nom, e-mail, version, Mes prix, Signaler ou
/// proposer, Mes tickets, Tickets à traiter (admin), Nouveautés, Sources des données,
/// déconnexion. La pastille compte les suivis de ticket à lire et, pour
/// l'administrateur, les tickets à traiter.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.user, required this.isAdmin});

  final SessionUser user;
  final bool isAdmin;

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
    final unread = ref.watch(unreadTicketsCountProvider);
    final toProcess = ref.watch(ticketsToProcessCountProvider);
    final total = unread + toProcess;

    // ticket: <coquille>/menu/compte
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
          leadingIcon: const Icon(Icons.sell_outlined),
          onPressed: () => unawaited(context.push(AppRoutes.prices)),
          child: const Text('Mes prix'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.feedback_outlined),
          // Le modèle de la route courante (`/recettes/:id`), jamais son
          // adresse : l'écran part sur une Issue publique.
          onPressed: () => unawaited(
            context.push(
              ticketFormLocation(GoRouter.of(context).state.fullPath),
            ),
          ),
          child: const Text('Signaler ou proposer'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.confirmation_number_outlined),
          trailingIcon: unread == 0
              ? null
              : Badge(label: Text(textePastille(unread))),
          semanticsLabel: unread == 0 ? null : 'Mes tickets, $unread à lire',
          onPressed: () => unawaited(context.push(AppRoutes.tickets)),
          child: const Text('Mes tickets'),
        ),
        if (isAdmin)
          MenuItemButton(
            leadingIcon: const Icon(Icons.inbox_outlined),
            trailingIcon: toProcess == 0
                ? null
                : Badge(label: Text(textePastille(toProcess))),
            semanticsLabel: toProcess == 0
                ? null
                : 'Tickets à traiter, $toProcess',
            onPressed: () => context.go(AppRoutes.adminTickets),
            child: const Text('Tickets à traiter'),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.new_releases_outlined),
          onPressed: () => unawaited(context.push(AppRoutes.news)),
          child: const Text('Nouveautés'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.info_outline),
          onPressed: () => unawaited(context.push(AppRoutes.dataSources)),
          child: const Text('Sources des données'),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => signOutFrom(context, ref),
          child: const Text('Se déconnecter'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: infobulleCompte(unread: unread, toProcess: toProcess),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Badge(
          isLabelVisible: total > 0,
          label: Text(textePastille(total)),
          child: CircleAvatar(
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
      ),
    );
  }
}
