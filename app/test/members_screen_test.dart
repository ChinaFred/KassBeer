import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/members/domain/member.dart';

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
    expect(
      find.text('Les recettes arriveront dans une prochaine version.'),
      findsOneWidget,
    );
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
  });

  testWidgets('retrait absent de sa propre ligne', (tester) async {
    await _openMembers(tester);
    expect(find.byTooltip('Retirer admin@exemple.fr'), findsNothing);
    expect(find.byTooltip('Retirer bob@exemple.fr'), findsOneWidget);
    expect(find.byTooltip('Retirer zoe@exemple.fr'), findsOneWidget);
    final size = tester.getSize(find.byTooltip('Retirer zoe@exemple.fr'));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
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
  });

  testWidgets('retrait refusé par le serveur : annoncé', (tester) async {
    final app = await _openMembers(tester);
    app.members.serverAnswer = () async => throw Exception('permission-denied');
    await tester.tap(find.byTooltip('Retirer zoe@exemple.fr'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Retirer'));
    await tester.pumpAndSettle();
    expect(find.text('Le retrait de zoe@exemple.fr a échoué.'), findsOneWidget);
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
}
