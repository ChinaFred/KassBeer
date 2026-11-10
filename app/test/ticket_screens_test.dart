import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/tickets/domain/ticket_screens.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_form_screen.dart';

import 'support/fakes.dart';

/// L'écran d'un ticket part sur une Issue publique : seule une valeur de
/// l'ensemble fermé de `ticket_screens.dart` peut sortir, jamais une adresse.
void main() {
  final allowed = {
    ...kTicketScreenNames.keys,
    kTicketScreenOther,
    kTicketScreenUnknown,
  };

  test('un modèle de route connu passe tel quel', () {
    expect(ticketScreenValue('/recettes/:id'), '/recettes/:id');
    expect(ticketScreenValue('/admin/membres'), '/admin/membres');
    expect(ticketScreenValue(kTicketScreenOther), kTicketScreenOther);
    expect(ticketScreenValue(null), kTicketScreenUnknown);
  });

  test('aucune adresse réelle ne sort', () {
    for (final value in [
      '/recettes/aB3xYz',
      '/recettes/aB3xYz/modifier',
      '/recettes/:id?depuis=/x',
      '/tickets/t1',
      'https://kassbeer.web.app/recettes/aB3',
      '/',
      '',
    ]) {
      expect(ticketScreenValue(value), kTicketScreenUnknown, reason: value);
      expect(allowed, contains(ticketScreenValue(value)));
    }
  });

  test('aucune clé de la table ne porte d\'identifiant ni de requête', () {
    final segment = RegExp(r'^(?:[a-z][a-z-]*|:[a-z]+)$');
    for (final key in kTicketScreenNames.keys) {
      expect(key.startsWith('/'), isTrue, reason: key);
      for (final s in key.substring(1).split('/')) {
        expect(segment.hasMatch(s), isTrue, reason: '$key : « $s »');
      }
    }
  });

  test('la liste finit par « Autre écran » puis « Je ne sais pas »', () {
    final options = ticketScreenOptions(isAdmin: true);
    expect(options.map((o) => o.value), contains('/admin/membres'));
    expect(options[options.length - 2].label, 'Autre écran');
    expect(options.last.label, 'Je ne sais pas');
    expect(options.map((o) => o.value).toSet().length, options.length);
    expect(ticketScreenLabel('/recettes/:id'), 'Recette');
    expect(ticketScreenLabel('/route/retiree'), '/route/retiree');
  });

  test('un brasseur ne voit pas les écrans d\'Admin', () {
    final values = ticketScreenOptions(isAdmin: false).map((o) => o.value);
    expect(values, isNot(contains('/admin')));
    expect(values, isNot(contains('/admin/membres')));
    expect(values, contains('/recettes/:id'));
    expect(values, contains(kTicketScreenUnknown));
  });

  test('chaque route du routeur a son nom d\'écran', () {
    final app = TestApp();
    addTearDown(app.container.dispose);
    final router = app.container.read(routerProvider);

    final patterns = <String>[];
    void walk(List<RouteBase> routes, String parent) {
      for (final route in routes) {
        if (route is GoRoute) {
          final full = route.path.startsWith('/')
              ? route.path
              : '$parent/${route.path}';
          patterns.add(full);
          walk(route.routes, full);
        } else if (route is ShellRouteBase) {
          walk(route.routes, parent);
        }
      }
    }

    walk(router.configuration.routes, '');
    // Écrans d'accès et redirection de « / » : le menu du compte n'y est pas.
    patterns.removeWhere(
      (p) => p == '/' || AppRoutes.accessScreens.contains(p),
    );
    expect(patterns, contains('/admin/membres'));
    expect(patterns, contains(AppRoutes.newTicket));
    for (final p in patterns) {
      expect(
        kTicketScreenNames.containsKey(p),
        isTrue,
        reason: 'la route $p n\'a pas de nom dans kTicketScreenNames',
      );
    }
  });

  test('ticketFormLocation porte le modèle dans « ecran »', () {
    final uri = Uri.parse(ticketFormLocation('/recettes/:id'));
    expect(uri.path, AppRoutes.newTicket);
    expect(uri.queryParameters[kTicketScreenQueryParam], '/recettes/:id');
    expect(ticketFormLocation(null), AppRoutes.newTicket);
  });
}
