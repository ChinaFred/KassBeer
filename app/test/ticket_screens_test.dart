import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/core/router/routes.dart';
import 'package:kass_beer/features/tickets/domain/ticket_screens.dart';
import 'package:kass_beer/features/tickets/presentation/ticket_form_screen.dart';

import 'support/fakes.dart';

/// Touche [label] dans le menu ouvert d'une liste déroulante. Le menu
/// s'ouvre autour du choix courant et ne construit que ses lignes visibles :
/// il défile vers le début ([delta] négatif) ou la fin jusqu'à [label].
Future<void> _choisir(WidgetTester tester, String label, double delta) async {
  await tester.scrollUntilVisible(
    find.text(label),
    delta,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
}

/// L'écran d'un ticket part sur une Issue publique : seule une valeur de
/// l'ensemble fermé de `ticket_screens.dart` peut sortir, jamais une adresse.
void main() {
  final allowed = {
    ...kTicketScreenNames.keys,
    ...kTicketElements.keys,
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

  group('éléments précis (menu ou fenêtre)', () {
    // Regex de `screen` dans `firestore.rules` (création d'un ticket).
    final rulesPattern = RegExp(
      r'^(/([a-z][a-z-]{0,39}|:[A-Za-z][A-Za-z0-9]{0,39}))+$',
    );

    test('chaque clé : écran connu, puis /menu/ ou /fenetre/', () {
      final key = RegExp(r'^(.+)/(menu|fenetre)/[a-z][a-z-]*$');
      expect(kTicketElements, isNotEmpty);
      for (final value in kTicketElements.keys) {
        final m = key.firstMatch(value);
        expect(m, isNotNull, reason: value);
        expect(kTicketScreenNames.keys, contains(m!.group(1)), reason: value);
        expect(ticketElementScreen(value), m.group(1), reason: value);
      }
    });

    test('aucune route ne contient de segment menu ou fenetre', () {
      for (final route in kTicketScreenNames.keys) {
        final segments = route.split('/');
        expect(segments, isNot(contains('menu')), reason: route);
        expect(segments, isNot(contains('fenetre')), reason: route);
      }
    });

    test('chaque valeur passe la regex des règles, 100 caractères au plus', () {
      for (final value in [
        ...kTicketScreenNames.keys,
        ...kTicketElements.keys,
      ]) {
        expect(rulesPattern.hasMatch(value), isTrue, reason: value);
        expect(value.length, lessThanOrEqualTo(100), reason: value);
      }
    });

    test('valeur stockée, nom affiché', () {
      const bottling = '/brassins/:id/fenetre/embouteillage';
      expect(ticketScreenValue(bottling), bottling);
      expect(ticketScreenLabel(bottling), 'Brassin › Embouteillage');
      expect(
        ticketScreenLabel('/recettes/menu/compte'),
        'Recettes › Menu du compte',
      );
      expect(ticketScreenValue('/brassins/:id/fenetre/inconnue'), 'inconnu');
      expect(ticketScreenValue('/prix/menu/compte'), '/prix/menu/compte');
      expect(
        ticketScreenLabel('/brassins/:id/jour/menu/compte'),
        'Jour de brassage › Menu du compte',
      );
      expect(ticketScreenValue('/prix/menu/navigation'), 'inconnu');
      expect(ticketElementScreen('/brassins/:id'), isNull);
    });

    test(
      '« L\'écran entier » d\'abord ; rien pour Autre et Je ne sais pas',
      () {
        final options = ticketElementOptions('/brassins/:id', isAdmin: false);
        expect(options.first, (
          value: '/brassins/:id',
          label: kTicketWholeScreen,
        ));
        expect(
          options.map((o) => o.value),
          contains('/brassins/:id/fenetre/embouteillage'),
        );
        expect(
          options.map((o) => o.value),
          contains('/brassins/:id/menu/compte'),
        );
        expect(
          options.map((o) => o.value),
          isNot(contains('/brassins/:id/jour/menu/actions')),
        );
        expect(
          ticketElementOptions(kTicketScreenOther, isAdmin: true),
          isEmpty,
        );
        expect(
          ticketElementOptions(kTicketScreenUnknown, isAdmin: true),
          isEmpty,
        );
        expect(ticketElementOptions('/nouveautes', isAdmin: true), [
          (value: '/nouveautes', label: kTicketWholeScreen),
          (value: '/nouveautes/menu/compte', label: 'Menu du compte'),
        ]);
      },
    );

    test('un brasseur ne voit aucun élément d\'Admin', () {
      for (final screen in ticketScreenOptions(isAdmin: false)) {
        for (final o in ticketElementOptions(screen.value, isAdmin: false)) {
          expect(isAdminTicketScreen(o.value), isFalse, reason: o.value);
        }
      }
      expect(ticketElementOptions('/admin/membres', isAdmin: false), isEmpty);
      expect(
        ticketElementOptions(
          '/admin/membres',
          isAdmin: true,
        ).map((o) => o.value),
        contains('/admin/membres/fenetre/inviter'),
      );
    });

    test('kTicketShellScreens : les routes de la coquille', () {
      final app = TestApp();
      addTearDown(app.container.dispose);
      final router = app.container.read(routerProvider);
      final inShell = <String>[];
      void walk(List<RouteBase> routes, String parent, bool shell) {
        for (final route in routes) {
          if (route is GoRoute) {
            final full = route.path.startsWith('/')
                ? route.path
                : '$parent/${route.path}';
            if (shell) inShell.add(full);
            walk(route.routes, full, shell);
          } else if (route is ShellRouteBase) {
            walk(route.routes, parent, true);
          }
        }
      }

      walk(router.configuration.routes, '', false);
      expect(inShell.toSet(), kTicketShellScreens.toSet());
    });

    test('kTicketAccountMenuScreens : les pages pleines hors coquille', () {
      final app = TestApp();
      addTearDown(app.container.dispose);
      final router = app.container.read(routerProvider);
      final outside = <String>[];
      void walk(List<RouteBase> routes, String parent) {
        for (final route in routes) {
          if (route is GoRoute) {
            final full = route.path.startsWith('/')
                ? route.path
                : '$parent/${route.path}';
            // Redirections (`/`, `/bibliotheque`) : aucune page.
            if (route.builder != null || route.pageBuilder != null) {
              outside.add(full);
            }
            walk(route.routes, full);
          }
        }
      }

      walk(router.configuration.routes, '');
      outside.removeWhere(AppRoutes.accessScreens.contains);
      expect(outside.toSet(), kTicketAccountMenuScreens.toSet());
      expect(
        kTicketAccountMenuScreens.toSet().intersection(
          kTicketShellScreens.toSet(),
        ),
        isEmpty,
      );
    });

    test('chaque menu ou fenêtre de lib/ porte son commentaire « ticket »', () {
      // Appels qui ouvrent un menu ou une fenêtre. Les définitions de
      // feuille_ou_dialogue.dart et ecriture.dart ne sont pas des appels.
      final call = RegExp(
        r'\b(showFeuilleOuDialogue|showDialog|showModalBottomSheet|'
        r'PopupMenuButton|MenuAnchor|confirmerActionOuAlternative|'
        r'confirmerAction|confirmerAbandon|confirmerSuppression|'
        r'showDatePicker|showTimePicker|showMenu|showGeneralDialog|'
        r'showDateRangePicker|SearchAnchor)\s*(<[^()]*>)?\s*\(',
      );
      final marker = RegExp(r'^// ticket: (.+)$');
      const definitions = {'feuille_ou_dialogue.dart', 'ecriture.dart'};
      final cited = <String>{};
      final missing = <String>[];
      final unknown = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          final m = marker.firstMatch(line);
          if (m != null) {
            final body = m.group(1)!;
            if (RegExp(r'^aucun \(.+\)$').hasMatch(body)) continue;
            for (final key in body.split(',').map((k) => k.trim())) {
              final expanded = key.startsWith('<coquille>/')
                  ? [
                      for (final s in kTicketShellScreens)
                        '$s${key.substring('<coquille>'.length)}',
                    ]
                  : key.startsWith('<hors-coquille>/')
                  ? [
                      for (final s in kTicketAccountMenuScreens)
                        '$s${key.substring('<hors-coquille>'.length)}',
                    ]
                  : [key];
              for (final k in expanded) {
                if (kTicketElements.containsKey(k)) {
                  cited.add(k);
                } else {
                  unknown.add('${file.path}:${i + 1} : $k');
                }
              }
            }
            continue;
          }
          if (line.startsWith('//')) continue;
          if (definitions.contains(file.uri.pathSegments.last)) continue;
          if (!call.hasMatch(line)) continue;
          final previous = i == 0 ? '' : lines[i - 1].trim();
          if (!marker.hasMatch(previous)) {
            missing.add('${file.path}:${i + 1} : $line');
          }
        }
      }
      expect(missing, isEmpty, reason: 'appel sans « // ticket: » au-dessus');
      expect(unknown, isEmpty, reason: 'clé absente de kTicketElements');
      expect(
        kTicketElements.keys.where((k) => !cited.contains(k)),
        isEmpty,
        reason: 'clé citée par aucun commentaire « // ticket: »',
      );
    });

    testWidgets('changer d\'écran remet « L\'écran entier »', (tester) async {
      final app = TestApp();
      await app.pump(tester, width: 400);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      unawaited(
        app.container
            .read(routerProvider)
            .push(ticketFormLocation('/brassins/:id')),
      );
      await tester.pumpAndSettle();

      final element = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Élément précis',
      );
      expect(element, findsOneWidget);
      expect(find.text(TicketFormScreen.elementHelp), findsOneWidget);
      expect(
        find.descendant(of: element, matching: find.text(kTicketWholeScreen)),
        findsOneWidget,
      );

      await tester.ensureVisible(element);
      await tester.pumpAndSettle();
      await tester.tap(element);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Embouteillage').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: element, matching: find.text('Embouteillage')),
        findsOneWidget,
      );

      final screen = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Écran concerné',
      );
      await tester.ensureVisible(screen);
      await tester.pumpAndSettle();
      await tester.tap(screen);
      await tester.pumpAndSettle();
      await _choisir(tester, 'Recette', -100);
      await tester.pumpAndSettle();
      final reset = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Élément précis',
      );
      expect(
        find.descendant(of: reset, matching: find.text(kTicketWholeScreen)),
        findsOneWidget,
      );
    });

    testWidgets('texte à 200 % : listes sans débordement', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp();
      await app.pump(tester, width: 360);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      unawaited(
        app.container
            .read(routerProvider)
            .push(ticketFormLocation('/brassins/:id')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final element = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Élément précis',
      );
      await tester.ensureVisible(element);
      await tester.pumpAndSettle();
      await tester.tap(element);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Densité ou volume saisi').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final screen = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Écran concerné',
      );
      await tester.ensureVisible(screen);
      await tester.pumpAndSettle();
      await tester.tap(screen);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _choisir(tester, 'Préparer le brassage', 100);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('« Je ne sais pas » : aucun « Élément précis »', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester, width: 400);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      unawaited(
        app.container.read(routerProvider).push(ticketFormLocation(null)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Je ne sais pas'), findsOneWidget);
      expect(find.text('Élément précis'), findsNothing);
    });
  });

  test('ticketFormLocation porte le modèle dans « ecran »', () {
    final uri = Uri.parse(ticketFormLocation('/recettes/:id'));
    expect(uri.path, AppRoutes.newTicket);
    expect(uri.queryParameters[kTicketScreenQueryParam], '/recettes/:id');
    expect(ticketFormLocation(null), AppRoutes.newTicket);
  });
}
