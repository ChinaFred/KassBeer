import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/auth/presentation/access_error_screen.dart';
import '../../features/auth/presentation/access_providers.dart';
import '../../features/auth/presentation/loading_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/not_invited_screen.dart';
import '../../features/brews/presentation/brews_screen.dart';
import '../../features/equipment/presentation/equipment_screen.dart';
import '../../features/members/presentation/members_screen.dart';
import '../../features/recipes/presentation/recipes_screen.dart';
import '../presentation/app_shell.dart';
import '../presentation/etats.dart';
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
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.recipes,
            builder: (_, _) => const RecipesScreen(),
          ),
          GoRoute(
            path: AppRoutes.brews,
            builder: (_, _) => const BrewsScreen(),
          ),
          GoRoute(
            path: AppRoutes.equipment,
            builder: (_, _) => const EquipmentScreen(),
          ),
          GoRoute(
            path: AppRoutes.admin,
            builder: (_, _) => const AdminScreen(),
            routes: [
              GoRoute(
                path: 'membres',
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
