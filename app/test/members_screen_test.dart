import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/ligne_liste.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/members/domain/member.dart';
import 'package:kass_beer/features/members/presentation/invite_member_form.dart';
import 'package:kass_beer/features/members/presentation/members_providers.dart';
import 'package:kass_beer/features/members/presentation/members_screen.dart';

import 'package:kass_beer/features/recipes/presentation/recipes_list_screen.dart';

import 'support/fakes.dart';

const _other = Member(email: 'zoe@exemple.fr', role: MemberRole.brewer);
const _otherAdmin = Member(
  email: 'bob@exemple.fr',
  role: MemberRole.admin,
  displayName: 'Bob',
);

Future<TestApp> _openMembers(WidgetTester tester, {double width = 400}) async {
  final app = TestApp();
  await app.pump(tester, width: width);
  app.signIn(adminUser, member: adminMember);
  app.members.all.add(const [adminMember, _otherAdmin, _other]);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go('/admin/membres');
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('un brasseur n\'ouvre pas Admin › Membres', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(brewerUser, member: brewerMember);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/admin/membres');
    await tester.pumpAndSettle();
    expect(find.text(RecipesListScreen.emptyMessage), findsOneWidget);
  });

  testWidgets('lignes : nom, e-mail, rôle, « Vous » sur sa ligne', (
    tester,
  ) async {
    await _openMembers(tester);
    expect(find.text('Alice Admin'), findsWidgets);
    expect(find.text('Nom non renseigné'), findsOneWidget);
    expect(find.text('Administrateur'), findsNWidgets(2));
    expect(find.text('Brasseur'), findsOneWidget);
    expect(find.text('Vous'), findsOneWidget);
    expect(
      find.text('Vous ne pouvez pas vous retirer vous-même'),
      findsOneWidget,
    );
    // Repère en disque de 40 px : le texte s'aligne sur celui des lignes de
    // l'accueil Admin (16 + 40 + 16).
    expect(find.byType(RepereDisque), findsNWidgets(3));
    expect(tester.getTopLeft(find.text('Bob')).dx, 72);
  });

  testWidgets('retrait absent de sa propre ligne', (tester) async {
    await _openMembers(tester);
    expect(find.byTooltip('Retirer admin@exemple.fr'), findsNothing);
    expect(find.byTooltip('Retirer bob@exemple.fr'), findsNothing);
    expect(find.byTooltip('Retirer zoe@exemple.fr'), findsOneWidget);
    final size = tester.getSize(find.byTooltip('Retirer zoe@exemple.fr'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('un autre admin : pas de retrait, renvoi à la console', (
    tester,
  ) async {
    await _openMembers(tester);
    expect(find.byTooltip('Retirer bob@exemple.fr'), findsNothing);
    expect(
      find.text('Un administrateur se retire depuis la console Firebase.'),
      findsOneWidget,
    );
  });

  testWidgets('retirer demande confirmation', (tester) async {
    final app = await _openMembers(tester);
    await tester.tap(find.byTooltip('Retirer zoe@exemple.fr'));
    await tester.pumpAndSettle();
    expect(find.text('Retirer zoe@exemple.fr ?'), findsOneWidget);
    expect(
      find.text(
        'Ce compte n\'aura plus accès à Kass\'Beer. Ses recettes et brassins restent '
        'visibles du groupe.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(app.members.removed, isEmpty);

    await tester.tap(find.byTooltip('Retirer zoe@exemple.fr'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
    await tester.pumpAndSettle();
    expect(app.members.removed, ['zoe@exemple.fr']);
    expect(find.text('zoe@exemple.fr est retiré.'), findsOneWidget);
  });

  testWidgets('retrait refusé par le serveur : annoncé', (tester) async {
    final app = await _openMembers(tester);
    app.members.serverAnswer = () async => throw Exception('permission-denied');
    await tester.tap(find.byTooltip('Retirer zoe@exemple.fr'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
    await tester.pumpAndSettle();
    expect(find.text('Le retrait de zoe@exemple.fr a échoué.'), findsOneWidget);
    expect(find.text('zoe@exemple.fr est retiré.'), findsNothing);
  });

  group('invitation', () {
    testWidgets('téléphone : bouton flottant et feuille du bas', (
      tester,
    ) async {
      await _openMembers(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Adresse e-mail Google'), findsOneWidget);
      expect(find.text('Nom (facultatif)'), findsOneWidget);
      final role = tester.widget<SegmentedButton<MemberRole>>(
        find.byType(SegmentedButton<MemberRole>),
      );
      expect(role.selected, {MemberRole.brewer});
    });

    testWidgets('grand écran : bouton en tête de liste et dialogue', (
      tester,
    ) async {
      await _openMembers(tester, width: 1000);
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Inviter'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('adresse mise en minuscules, nom et rôle transmis', (
      tester,
    ) async {
      final app = await _openMembers(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Adresse e-mail Google'),
        ' Nouveau@Exemple.FR ',
      );
      await tester.pump();
      expect(find.text(' nouveau@exemple.fr '), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nom (facultatif)'),
        'Nina',
      );
      await tester.tap(find.text('Administrateur').last);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Inviter'));
      await tester.pumpAndSettle();

      expect(app.members.invitations, hasLength(1));
      final invitation = app.members.invitations.single;
      expect(invitation.email, 'nouveau@exemple.fr');
      expect(invitation.role, MemberRole.admin);
      expect(invitation.displayName, 'Nina');
      expect(invitation.invitedBy, 'uid-admin');
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.text(
          'nouveau@exemple.fr est invité. Aucun e-mail n\'est envoyé : prévenez-le.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('doublon refusé', (tester) async {
      final app = await _openMembers(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Adresse e-mail Google'),
        'ZOE@exemple.fr',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Inviter'));
      await tester.pumpAndSettle();
      expect(find.text('Cette adresse est déjà membre.'), findsOneWidget);
      expect(app.members.invitations, isEmpty);
    });

    group('console Google', () {
      String? copied;
      setUp(() => copied = null);

      void mockClipboard(WidgetTester tester) {
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
      }

      test('adresse de la page des utilisateurs test', () {
        expect(
          consoleUtilisateursTest('kassbeer').toString(),
          'https://console.cloud.google.com/auth/audience?project=kassbeer',
        );
        expect(consoleUtilisateursTest(''), isNull);
        expect(consoleUtilisateursTest('a/b?x'), isNull);
      });

      testWidgets('adresse valide : copiée, page ouverte', (tester) async {
        mockClipboard(tester);
        final app = await _openMembers(tester);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(find.text(InviteMemberForm.consoleHint), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Adresse e-mail Google'),
          'Nina@Exemple.fr',
        );
        await tester.ensureVisible(find.text(InviteMemberForm.consoleButton));
        await tester.tap(find.text(InviteMemberForm.consoleButton));
        await tester.pumpAndSettle();
        expect(copied, 'nina@exemple.fr');
        expect(app.openedLinks, [
          Uri.parse(
            'https://console.cloud.google.com/auth/audience?project=demo-kassbeer',
          ),
        ]);
        expect(
          find.text(InviteMemberForm.consoleCopied('nina@exemple.fr')),
          findsOneWidget,
        );
        // L'adresse changée efface le message de copie.
        await tester.enterText(
          find.widgetWithText(TextField, 'Adresse e-mail Google'),
          'nino@exemple.fr',
        );
        await tester.pump();
        expect(
          find.text(InviteMemberForm.consoleCopied('nina@exemple.fr')),
          findsNothing,
        );
        // Le formulaire reste ouvert : l'invitation n'est pas encore écrite.
        expect(app.members.invitations, isEmpty);
        expect(find.text('Inviter un membre'), findsOneWidget);
      });

      testWidgets('adresse vide : page ouverte sans copie', (tester) async {
        mockClipboard(tester);
        final app = await _openMembers(tester);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(InviteMemberForm.consoleButton));
        await tester.tap(find.text(InviteMemberForm.consoleButton));
        await tester.pumpAndSettle();
        expect(copied, isNull);
        expect(app.openedLinks, hasLength(1));
        expect(find.text(InviteMemberForm.consoleNoEmail), findsOneWidget);
      });

      testWidgets('ouverture refusée : rapport sans adresse, lien affiché', (
        tester,
      ) async {
        mockClipboard(tester);
        final app = await _openMembers(tester);
        app.openLinkResult = false;
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Adresse e-mail Google'),
          'nina@exemple.fr',
        );
        await tester.ensureVisible(find.text(InviteMemberForm.consoleButton));
        await tester.tap(find.text(InviteMemberForm.consoleButton));
        await tester.pumpAndSettle();
        expect(find.text(InviteMemberForm.consoleOpenFailure), findsOneWidget);
        expect(
          find.text(
            'https://console.cloud.google.com/auth/audience?project=demo-kassbeer',
          ),
          findsOneWidget,
        );
        final report = app.errors.reports.single;
        expect(report.feature, 'members.open_console');
        expect(report.context, isNot(contains('nina')));
      });
    });

    testWidgets('adresse invalide refusée', (tester) async {
      final app = await _openMembers(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Adresse e-mail Google'),
        'pas-une-adresse',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Inviter'));
      await tester.pumpAndSettle();
      expect(find.text('Adresse e-mail invalide.'), findsOneWidget);
      expect(app.members.invitations, isEmpty);
    });

    testWidgets('ligne en attente du réseau', (tester) async {
      final app = await _openMembers(tester);
      app.members.all.add(const [
        adminMember,
        Member(
          email: 'nina@exemple.fr',
          role: MemberRole.brewer,
          hasPendingWrites: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('En attente du réseau'), findsOneWidget);
    });
  });

  testWidgets('liste illisible : panne et Réessayer', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(adminUser, member: adminMember);
    app.members.all.addError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/admin/membres');
    await tester.pumpAndSettle();
    expect(
      find.text('Impossible de lire la liste des membres.'),
      findsOneWidget,
    );
    app.members.all.add(const [adminMember]);
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Vous'), findsOneWidget);
  });

  testWidgets(
    'panne après une liste lue : la liste reste, la panne s\'affiche',
    (tester) async {
      final app = await _openMembers(tester);
      app.members.all.addError(Exception('unavailable'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Mise à jour de la liste impossible. Elle peut ne plus être à jour.',
        ),
        findsOneWidget,
      );
      expect(find.text('zoe@exemple.fr'), findsOneWidget);
    },
  );

  testWidgets('liste vide : invite à ajouter un compte', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(adminUser, member: adminMember);
    app.members.all.add(const []);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/admin/membres');
    await tester.pumpAndSettle();
    expect(find.text(MembersScreen.emptyTitle), findsOneWidget);
    expect(
      find.text('Appuyez sur Inviter pour ajouter un compte.'),
      findsOneWidget,
    );
  });

  testWidgets('formulaire : titre « Rôle » au-dessus du choix', (tester) async {
    await _openMembers(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final title = tester.getTopLeft(find.text('Rôle'));
    final segments = tester.getTopLeft(
      find.byType(SegmentedButton<MemberRole>),
    );
    expect(title.dy, lessThan(segments.dy));
  });
}
