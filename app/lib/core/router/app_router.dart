import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/auth/presentation/access_error_screen.dart';
import '../../features/auth/presentation/access_providers.dart';
import '../../features/auth/presentation/loading_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/not_invited_screen.dart';
import '../../features/brew_day/presentation/brew_day_screen.dart';
import '../../features/brew_day/presentation/prepare_brew_screen.dart';
import '../../features/brews/presentation/brew_detail_screen.dart';
import '../../features/brews/presentation/brews_screen.dart';
import '../../features/costs/presentation/prices_screen.dart';
import '../../features/equipment/presentation/equipment_detail_screen.dart';
import '../../features/equipment/presentation/equipment_editor_screen.dart';
import '../../features/equipment/presentation/equipment_list_screen.dart';
import '../../features/library/presentation/data_sources_screen.dart';
import '../../features/library/presentation/library_providers.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/library/presentation/public_recipe_screen.dart';
import '../../features/library/presentation/reference_entry_screen.dart';
import '../../features/members/presentation/members_screen.dart';
import '../../features/recipes/presentation/brew_steps_editor_screen.dart';
import '../../features/recipes/presentation/import_recipes_screen.dart';
import '../../features/recipes/presentation/recipe_detail_screen.dart';
import '../../features/recipes/presentation/recipe_editor_screen.dart';
import '../../features/recipes/presentation/recipes_list_screen.dart';
import '../../features/tickets/domain/ticket.dart';
import '../../features/tickets/presentation/my_tickets_screen.dart';
import '../../features/tickets/presentation/ticket_detail_screen.dart';
import '../../features/tickets/presentation/ticket_form_screen.dart';
import '../presentation/app_shell.dart';
import '../presentation/etats.dart';
import '../presentation/nouveautes_screen.dart';
import 'page_de_coquille.dart';
import 'routes.dart';

/// Chemin où envoyer [location] selon [access], ou `null` pour y rester.
///
/// Pure, testée. Pendant le chargement, le chemin demandé est gardé dans `?depuis=`
/// pour y revenir une fois l'accès lu (rechargement d'une page sur le web).
String? redirectFor(AccessState access, Uri location) {
  final path = location.path;
  String toAccessScreen(String target) {
    final from = _intendedPath(location);
    return from == null
        ? target
        : Uri(path: target, queryParameters: {'depuis': from}).toString();
  }

  switch (access) {
    case AccessLoading():
      return path == AppRoutes.loading
          ? null
          : toAccessScreen(AppRoutes.loading);
    case AccessSignedOut():
      return path == AppRoutes.login ? null : toAccessScreen(AppRoutes.login);
    case AccessNotInvited():
      return path == AppRoutes.notInvited
          ? null
          : toAccessScreen(AppRoutes.notInvited);
    case AccessFailed():
      return path == AppRoutes.accessError
          ? null
          : toAccessScreen(AppRoutes.accessError);
    case AccessGranted(:final member):
      if (AppRoutes.accessScreens.contains(path)) {
        final from = location.queryParameters['depuis'];
        if (from != null &&
            _isAppPath(from) &&
            (member.isAdmin || !_isAdminPath(from))) {
          return from;
        }
        return AppRoutes.home;
      }
      if (_isAdminPath(path) && !member.isAdmin) return AppRoutes.home;
      return null;
  }
}

bool _isAdminPath(String path) =>
    path == AppRoutes.admin || path.startsWith('${AppRoutes.admin}/');

bool _isAppPath(String path) =>
    path.startsWith('/') &&
    !path.startsWith('//') &&
    !AppRoutes.accessScreens.contains(Uri.parse(path).path);

/// Chemin applicatif à retrouver après un écran d'accès.
String? _intendedPath(Uri location) {
  if (AppRoutes.accessScreens.contains(location.path)) {
    final from = location.queryParameters['depuis'];
    return from != null && _isAppPath(from) ? from : null;
  }
  return location.path == '/' ? null : location.path;
}

/// Prévient le routeur à chaque changement de l'état d'accès.
class _AccessListenable extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Routeur de l'application. Le routeur ne décide que du chemin ; les droits
/// d'accès aux données restent dans `firestore.rules`.
final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AccessListenable();
  ref.listen<AccessState>(accessStateProvider, (_, _) => listenable.notify());
  ref.onDispose(listenable.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.loading,
    refreshListenable: listenable,
    redirect: (context, state) =>
        redirectFor(ref.read(accessStateProvider), state.uri),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.home),
      // `/bibliotheque` mène aux styles : une seule page par segment, que le
      // retour d'une fiche retrouve avec sa recherche.
      GoRoute(
        path: AppRoutes.library,
        redirect: (_, state) => state.uri.path == AppRoutes.library
            ? AppRoutes.librarySegment(SegmentBibliotheque.styles.slug)
            : null,
      ),
      GoRoute(
        path: AppRoutes.loading,
        builder: (_, _) => const LoadingScreen(),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.notInvited,
        builder: (_, _) => const NotInvitedScreen(),
      ),
      GoRoute(
        path: AppRoutes.accessError,
        builder: (_, _) => const AccessErrorScreen(),
      ),
      // Éditeurs plein écran, hors de la coquille. Déclarés avant elle : sans quoi
      // « nouvelle » serait lu comme l'identifiant d'une recette.
      GoRoute(
        path: AppRoutes.newRecipe,
        builder: (_, _) => const RecipeEditorScreen(),
      ),
      // Import de recettes (ADR-005, L2) : avant « :id » pour la même raison.
      GoRoute(
        path: AppRoutes.importRecipes,
        builder: (_, _) => const ImportRecipesScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.recipes}/:id/modifier',
        builder: (_, state) =>
            RecipeEditorScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: '${AppRoutes.recipes}/:id/chronologie',
        builder: (_, state) =>
            BrewStepsEditorScreen(id: state.pathParameters['id']!),
      ),
      // Écran du jour : plein écran, hors de la coquille.
      GoRoute(
        path: '${AppRoutes.brews}/:id/jour',
        builder: (_, state) => BrewDayScreen(
          id: state.pathParameters['id']!,
          reprise: state.extra == kRepriseBrassage,
        ),
      ),
      // « Mes prix » : page pleine avec retour, hors de la coquille.
      GoRoute(path: AppRoutes.prices, builder: (_, _) => const PricesScreen()),
      GoRoute(
        path: AppRoutes.newEquipment,
        builder: (_, _) => const EquipmentEditorScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.equipment}/:id/modifier',
        builder: (_, state) =>
            EquipmentEditorScreen(id: state.pathParameters['id']),
      ),
      // Nouveautés : plein écran, hors de la coquille, ouvert par `push` depuis le
      // menu du compte.
      GoRoute(
        path: AppRoutes.news,
        builder: (_, _) => const NouveautesScreen(),
      ),
      // Sources des données (ADR-005) : plein écran, hors de la coquille, ouvert
      // par `push` depuis la Bibliothèque et le menu du compte.
      GoRoute(
        path: AppRoutes.dataSources,
        builder: (_, _) => const DataSourcesScreen(),
      ),
      // Tickets (ADR-006) : pleines pages hors de la coquille, ouvertes par
      // `push`. « nouveau » avant « :id », sans quoi il serait lu comme un
      // identifiant.
      GoRoute(
        path: AppRoutes.newTicket,
        builder: (_, state) => TicketFormScreen(
          ecranOrigine: state.uri.queryParameters[kTicketScreenQueryParam],
          reprise: switch (state.extra) {
            final TicketBrouillon brouillon => brouillon,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: '${AppRoutes.tickets}/:id',
        builder: (_, state) =>
            TicketDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.tickets,
        builder: (_, _) => const MyTicketsScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final page = state.topRoute;
          return AppShell(
            location: state.uri.path,
            title: page is PageDeCoquille ? page.titre : "Kass'Beer",
            backTo: page is PageDeCoquilleDynamique
                ? page.retourDepuis(state)
                : page is PageDeCoquille
                ? page.retour
                : null,
            child: child,
          );
        },
        routes: [
          PageDeCoquille(
            path: AppRoutes.recipes,
            titre: 'Recettes',
            builder: (_, _) => const RecipesListScreen(),
            routes: [
              PageDeCoquille(
                path: ':id',
                titre: 'Recette',
                retour: AppRoutes.recipes,
                builder: (_, state) =>
                    RecipeDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          // Bibliothèque (ADR-005, L4) : un chemin par segment, la fiche sous
          // son segment, qui garde la liste lue et la recherche au retour.
          for (final segment in SegmentBibliotheque.values)
            PageDeCoquille(
              path: AppRoutes.librarySegment(segment.slug),
              titre: 'Bibliothèque',
              builder: (_, _) => LibraryScreen(segment: segment),
              routes: [
                PageDeCoquille(
                  path: ':id',
                  titre: segment.titreFiche,
                  retour: AppRoutes.librarySegment(segment.slug),
                  builder: (_, state) {
                    final id = state.pathParameters['id']!;
                    return segment.nature == null
                        ? PublicRecipeScreen(id: id)
                        : ReferenceEntryScreen(segment: segment, id: id);
                  },
                ),
              ],
            ),
          PageDeCoquille(
            path: AppRoutes.brews,
            titre: 'Brassins',
            builder: (_, _) => const BrewsScreen(),
            routes: [
              PageDeCoquille(
                path: ':id',
                titre: 'Brassin',
                retour: AppRoutes.brews,
                builder: (_, state) =>
                    BrewDetailScreen(id: state.pathParameters['id']!),
              ),
              PageDeCoquilleDynamique(
                path: ':id/preparer',
                titre: 'Préparer le brassage',
                retourDepuis: (state) =>
                    AppRoutes.brew(state.pathParameters['id']!),
                builder: (_, state) =>
                    PrepareBrewScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          PageDeCoquille(
            path: AppRoutes.equipment,
            titre: 'Équipements',
            builder: (_, _) => const EquipmentListScreen(),
            routes: [
              PageDeCoquille(
                path: ':id',
                titre: 'Équipement',
                retour: AppRoutes.equipment,
                builder: (_, state) =>
                    EquipmentDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          PageDeCoquille(
            path: AppRoutes.admin,
            titre: 'Admin',
            builder: (_, _) => const AdminScreen(),
            routes: [
              PageDeCoquille(
                path: 'membres',
                titre: 'Membres',
                retour: AppRoutes.admin,
                builder: (_, _) => const MembersScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _NotFoundScreen(),
  );
  ref.onDispose(router.dispose);
  return router;
});

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: EtatVide(
          icon: Icons.search_off,
          message: 'Cette page n\'existe pas.',
          action: FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Revenir à l\'accueil'),
          ),
        ),
      ),
    );
  }
}
