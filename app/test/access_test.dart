import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/auth/domain/session_user.dart';
import 'package:kass_beer/features/auth/presentation/access_error_screen.dart';
import 'package:kass_beer/features/auth/presentation/access_providers.dart';
import 'package:kass_beer/features/auth/presentation/login_screen.dart';
import 'package:kass_beer/features/auth/presentation/not_invited_screen.dart';
import 'package:kass_beer/features/members/data/members_repository.dart';
import 'package:kass_beer/features/members/domain/member.dart';

import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('chargement tant que la session n\'est pas lue', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    await tester.pump();
    expect(find.text("Kass'Beer"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('chargement tant que members/ n\'est pas lu', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.auth.session.add(brewerUser);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(NotInvitedScreen), findsNothing);
  });

  group('connexion', () {
    testWidgets('écran sans session', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.auth.session.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text("Kass'Beer"), findsOneWidget);
      expect(find.text('Recettes et brassins du groupe'), findsOneWidget);
      expect(find.text('Se connecter avec Google'), findsOneWidget);
      expect(find.text('Accès réservé aux comptes invités.'), findsOneWidget);
      final button = tester.getSize(
        find.widgetWithText(FilledButton, 'Se connecter avec Google'),
      );
      expect(button.height, 56);
    });

    testWidgets('fenêtre Google fermée : aucun message', (tester) async {
      final app = TestApp();
      app.auth.onSignIn = () async => SignInOutcome.cancelled;
      await app.pump(tester);
      app.auth.session.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se connecter avec Google'));
      await tester.pumpAndSettle();
      expect(app.auth.signInCalls, 1);
      expect(find.text(LoginScreen.networkError), findsNothing);
      expect(find.text(LoginScreen.otherError), findsNothing);
    });

    testWidgets('réseau absent : message réseau', (tester) async {
      final app = TestApp();
      app.auth.onSignIn = () async =>
          throw SignInFailure(network: true, cause: Exception('réseau'));
      await app.pump(tester);
      app.auth.session.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se connecter avec Google'));
      await tester.pumpAndSettle();
      expect(
        find.text('Connexion impossible. Vérifiez le réseau et réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('connexion réussie : membre sur Recettes', (tester) async {
      final app = TestApp();
      app.auth.onSignIn = () async {
        app.signIn(brewerUser, member: brewerMember);
        return SignInOutcome.signedIn;
      };
      await app.pump(tester);
      app.auth.session.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se connecter avec Google'));
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
    });
  });

  group('compte non invité', () {
    testWidgets('document absent du serveur', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser);
      await tester.pumpAndSettle();
      expect(find.byType(NotInvitedScreen), findsOneWidget);
      expect(find.text("Ce compte n'a pas accès à Kass'Beer"), findsOneWidget);
      expect(find.text('Vous êtes connecté avec :'), findsOneWidget);
      expect(
        find.widgetWithText(SelectableText, 'Brasseur@Exemple.fr'),
        findsOneWidget,
      );
      expect(find.text('Copier l\'adresse'), findsOneWidget);
      expect(find.text('Vérifier à nouveau'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
    });

    testWidgets('la lecture porte sur l\'e-mail en minuscules', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      expect(app.members.lookups.keys, ['brasseur@exemple.fr']);
    });

    testWidgets('copier l\'adresse est annoncé', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copier l\'adresse'));
      await tester.pump();
      expect(copied, 'Brasseur@Exemple.fr');
      expect(find.text('Adresse copiée'), findsOneWidget);
    });

    testWidgets('vérifier à nouveau relit le document', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser);
      await tester.pumpAndSettle();
      final before = app.members.lookup('brasseur@exemple.fr').subscriptions;
      app.members
          .lookup('brasseur@exemple.fr')
          .add(const MemberLookup(member: brewerMember, fromCache: false));
      await tester.tap(find.text('Vérifier à nouveau'));
      await tester.pumpAndSettle();
      expect(
        app.members.lookup('brasseur@exemple.fr').subscriptions,
        greaterThan(before),
      );
      expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
    });

    testWidgets('membre retiré : bascule à la lecture suivante', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser, member: brewerMember);
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
      app.members
          .lookup('brasseur@exemple.fr')
          .add(const MemberLookup(member: null, fromCache: false));
      await tester.pumpAndSettle();
      expect(find.byType(NotInvitedScreen), findsOneWidget);
    });

    testWidgets('se déconnecter revient à la connexion', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.signIn(brewerUser);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      expect(app.auth.signOutCalls, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('panne', () {
    testWidgets('lecture impossible : écran Erreur, jamais non invité', (
      tester,
    ) async {
      final app = TestApp();
      await app.pump(tester);
      app.auth.session.add(brewerUser);
      app.members
          .lookup('brasseur@exemple.fr')
          .addError(const MemberLookupUnavailable('aucune réponse du serveur'));
      await tester.pumpAndSettle();
      expect(find.byType(AccessErrorScreen), findsOneWidget);
      expect(find.byType(NotInvitedScreen), findsNothing);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('réessayer relance la lecture', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.auth.session.add(brewerUser);
      final lookup = app.members.lookup('brasseur@exemple.fr');
      lookup.addError(Exception('permission-denied'));
      await tester.pumpAndSettle();
      lookup.add(const MemberLookup(member: brewerMember, fromCache: false));
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
    });

    testWidgets('session illisible : écran Erreur', (tester) async {
      final app = TestApp();
      await app.pump(tester);
      app.auth.session.addError(Exception('auth'));
      await tester.pumpAndSettle();
      expect(find.byType(AccessErrorScreen), findsOneWidget);
    });
  });

  testWidgets('hors ligne : bandeau annoncé', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(brewerUser, member: brewerMember, fromCache: true);
    await tester.pumpAndSettle();
    expect(
      find.text('Hors ligne. Les modifications partiront au retour du réseau.'),
      findsOneWidget,
    );
    app.members
        .lookup('brasseur@exemple.fr')
        .add(const MemberLookup(member: brewerMember, fromCache: false));
    await tester.pumpAndSettle();
    expect(
      find.text('Hors ligne. Les modifications partiront au retour du réseau.'),
      findsNothing,
    );
  });

  group('redirectFor', () {
    const granted = AccessGranted(
      user: brewerUser,
      member: brewerMember,
      offline: false,
    );
    const admin = AccessGranted(
      user: adminUser,
      member: adminMember,
      offline: false,
    );

    test('un chemin demandé pendant le chargement est retrouvé', () {
      final toLoading = redirectFor(
        const AccessLoading(),
        Uri.parse('/brassins'),
      );
      expect(toLoading, '/chargement?depuis=%2Fbrassins');
      expect(redirectFor(granted, Uri.parse(toLoading!)), '/brassins');
    });

    test('un brasseur n\'ouvre pas Admin', () {
      expect(redirectFor(granted, Uri.parse('/admin/membres')), '/recettes');
      expect(
        redirectFor(
          granted,
          Uri.parse('/chargement?depuis=%2Fadmin%2Fmembres'),
        ),
        '/recettes',
      );
    });

    test('un admin ouvre Admin', () {
      expect(redirectFor(admin, Uri.parse('/admin/membres')), isNull);
    });

    test('une adresse externe dans depuis est ignorée', () {
      expect(
        redirectFor(granted, Uri.parse('/connexion?depuis=https://exemple.fr')),
        '/recettes',
      );
      expect(
        redirectFor(granted, Uri.parse('/connexion?depuis=%2F%2Fexemple.fr')),
        '/recettes',
      );
    });
  });

  testWidgets('vérifier à nouveau, toujours absent : annoncé', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(brewerUser);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vérifier à nouveau'));
    await tester.pumpAndSettle();
    expect(find.text('Ce compte n\'est toujours pas invité.'), findsOneWidget);
  });

  testWidgets('compte sans adresse : pas de copie, consigne de reconnexion', (
    tester,
  ) async {
    final app = TestApp();
    await app.pump(tester);
    app.auth.session.add(const SessionUser(uid: 'sans-adresse', email: null));
    await tester.pumpAndSettle();
    expect(find.byType(NotInvitedScreen), findsOneWidget);
    expect(find.text('Copier l\'adresse'), findsNothing);
    expect(
      find.text(
        'Adresse du compte indisponible. Déconnectez-vous et reconnectez-vous.',
      ),
      findsOneWidget,
    );
    expect(find.text('Se déconnecter'), findsOneWidget);
  });

  testWidgets('page introuvable : message et retour à l\'accueil', (
    tester,
  ) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/nulle-part');
    await tester.pumpAndSettle();
    expect(find.text('Cette page n\'existe pas.'), findsOneWidget);
    await tester.tap(find.text('Revenir à l\'accueil'));
    await tester.pumpAndSettle();
    expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
  });
}
