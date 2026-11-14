import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/access_providers.dart';
import '../../features/brew_day/presentation/reprise_brassage.dart';
import '../router/routes.dart';
import 'bandeau_hors_ligne.dart';
import 'breakpoints.dart';
import 'logo_kass_beer.dart';
import 'menu_compte.dart';
import 'verification_mise_a_jour.dart';
import 'zone_capture.dart';

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
      actions: [const MenuCompte(), const SizedBox(width: 8)],
    );

    final offline = granted?.offline ?? false;

    /// Bandeau en pleine largeur au-dessus du contenu, centré ou non.
    Widget withBanner(Widget body) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline) const BandeauHorsLigne(),
        Expanded(
          // Fenêtre « Nouvelle version » de l'APK, une fois par lancement
          // (ADR-012).
          child: VerificationMiseAJour(
            child: RepriseBrassage(location: location, child: body),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = WindowSize.of(constraints.maxWidth);
        if (size == WindowSize.compact) {
          return Scaffold(
            appBar: appBar,
            // Zone de la capture de « Signaler ou proposer » : la barre du
            // haut et la barre de navigation n'y figurent pas (ADR-008, T6).
            body: ZoneCapture(child: withBanner(child)),
            // ticket: <coquille>/menu/navigation
            bottomNavigationBar: NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: goTo,
              // Icônes seules sous 600 px : `label` reste l'infobulle et le
              // nom lu par le lecteur d'écran.
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
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
                        // Rail étendu : médaillon et nom en tête. Le rail
                        // réduit (600 à 839 px) n'a pas la place.
                        leading: expanded ? const _EnteteRail() : null,
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
                // Zone de la capture de « Signaler ou proposer » : le rail
                // n'y figure pas (ADR-008, T6).
                child: ZoneCapture(
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

/// En-tête du rail étendu : médaillon de 48 px et nom de l'application. Exclu
/// de la sémantique : la barre du haut porte déjà le titre de l'écran.
class _EnteteRail extends StatelessWidget {
  const _EnteteRail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: kRailEtenduWidth - 32,
          child: Row(
            children: [
              const MedaillonKassBeer(taille: MedaillonKassBeer.tailleMin),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  "Kass'Beer",
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
