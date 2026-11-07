import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/equipment/domain/equipment.dart';
import 'package:kass_beer/features/equipment/presentation/equipment_detail_screen.dart';
import 'package:kass_beer/features/equipment/presentation/equipment_editor_screen.dart';
import 'package:kass_beer/features/equipment/presentation/equipment_list_screen.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/fakes.dart';

Equipment equipment(
  String id, {
  String owner = 'uid-brasseur',
  String? ownerName = 'Bruno Brasseur',
  String name = 'Grainfather',
  double? efficiency = 72,
}) => Equipment(
  id: id,
  ownerUid: owner,
  ownerName: ownerName,
  content: EquipmentContent(
    name: name,
    kind: EquipmentKind.allInOne,
    mashEfficiencyPct: efficiency,
  ),
);

Recipe recipe(String id, String name, {String? equipmentId, String? owner}) =>
    Recipe(
      id: id,
      ownerUid: owner ?? 'uid-brasseur',
      content: RecipeContent(name: name, equipmentId: equipmentId),
    );

Future<TestApp> open(
  WidgetTester tester,
  String path, {
  double width = 400,
  double height = 900,
}) async {
  final app = TestApp();
  await app.pump(tester, width: width, height: height);
  app.signIn(brewerUser, member: brewerMember);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

void main() {
  testWidgets('liste vide : message et Nouvel équipement', (tester) async {
    await open(tester, '/equipements');
    expect(find.text(EquipmentListScreen.emptyMessage), findsOneWidget);
    expect(find.text('Nouvel équipement'), findsOneWidget);
  });

  testWidgets('liste illisible : panne et Réessayer', (tester) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(brewerUser, member: brewerMember);
    app.equipment.all.addError(Exception('permission-denied'));
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/equipements');
    await tester.pumpAndSettle();
    expect(find.text('Impossible de lire les équipements.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('ligne : type, rendement, auteur ; les miens d\'abord', (
    tester,
  ) async {
    final app = await open(tester, '/equipements');
    app.equipment.publish([
      equipment('b', owner: 'uid-zoe', ownerName: 'Zoé', name: 'Anvil'),
      equipment('a', name: 'Zébulon', efficiency: null),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.text('Tout-en-un · Rendement non renseigné · Vous'),
      findsOneWidget,
    );
    expect(find.text('Tout-en-un · Rendement 72 % · Zoé'), findsOneWidget);
    final mine = tester.getTopLeft(find.text('Zébulon'));
    final other = tester.getTopLeft(find.text('Anvil'));
    expect(mine.dy, lessThan(other.dy));
  });

  testWidgets('équipement d\'un autre : lecture seule', (tester) async {
    final app = await open(tester, '/equipements/z');
    app.equipment.publish([equipment('z', owner: 'uid-zoe', ownerName: 'Zoé')]);
    await tester.pumpAndSettle();
    expect(find.text('Tout-en-un · Équipement de Zoé'), findsOneWidget);
    expect(find.text('Modifier'), findsNothing);
    expect(find.text('Supprimer'), findsNothing);

    app.container.read(routerProvider).go('/equipements/z/modifier');
    await tester.pumpAndSettle();
    expect(find.text(EquipmentEditorScreen.readOnlyMessage), findsOneWidget);
    expect(find.text('Voir l\'équipement'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
  });

  testWidgets('équipement absent du serveur : supprimé ; du cache hors ligne : '
      'indisponible', (tester) async {
    final app = await open(tester, '/equipements/x');
    expect(
      find.text('Cet équipement n\'existe pas ou a été supprimé.'),
      findsOneWidget,
    );
    app.signIn(brewerUser, member: brewerMember, fromCache: true);
    app.equipment.publish(const [], fromCache: true);
    await tester.pumpAndSettle();
    expect(find.text('Équipement indisponible hors ligne.'), findsOneWidget);
  });

  testWidgets('suppression d\'un équipement utilisé : recettes nommées (E9)', (
    tester,
  ) async {
    final app = await open(tester, '/equipements/e');
    app.equipment.publish([equipment('e')]);
    app.recipes.publish([
      recipe('r1', 'Blonde', equipmentId: 'e'),
      recipe('r2', 'IPA de Zoé', equipmentId: 'e', owner: 'uid-zoe'),
      recipe('r3', 'Stout', equipmentId: 'autre'),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer « Grainfather » ?'), findsOneWidget);
    expect(find.text(EquipmentDetailScreen.deleteGroup), findsOneWidget);
    expect(
      find.text(
        'Utilisé par 2 recettes : Blonde, IPA de Zoé. Leurs calculs '
        'afficheront Équipement supprimé.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
    await tester.pumpAndSettle();
    expect(app.equipment.writes.single.kind, 'delete');
    expect(app.equipment.writes.single.id, 'e');
    // Aucune recette n'est écrite.
    expect(app.recipes.writes, isEmpty);
    expect(find.text(EquipmentDetailScreen.deletedMessage), findsOneWidget);
  });

  testWidgets('création : nom, type, rendement « 72,5 », nom du jeton', (
    tester,
  ) async {
    final app = await open(tester, '/equipements/nouveau');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom de l\'équipement'),
      'Grainfather',
    );
    await tester.tap(find.text('Tout-en-un'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rendement d\'empâtage (%)'),
      '72,5',
    );
    await tester.pump();
    // Tout-en-un : un seul jeu de champs de cuve.
    expect(find.text('Volume de la cuve (L)'), findsOneWidget);
    expect(find.text('Volume de la cuve d\'ébullition (L)'), findsNothing);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final write = app.equipment.writes.single;
    expect(write.kind, 'create');
    expect(write.ownerUid, 'uid-brasseur');
    expect(write.ownerName, 'Bruno Brasseur');
    expect(write.content!.mashEfficiencyPct, 72.5);
    expect(write.content!.kind, EquipmentKind.allInOne);
    expect(find.text('Équipement enregistré.'), findsOneWidget);
  });

  testWidgets('valeur hors bornes : message, rien n\'est enregistré (E5)', (
    tester,
  ) async {
    final app = await open(tester, '/equipements/nouveau');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom de l\'équipement'),
      'Cuves',
    );
    await tester.tap(find.text('Cuves séparées'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rendement d\'empâtage (%)'),
      '120',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Entre 0 et 100.'), findsOneWidget);
    expect(app.equipment.writes, isEmpty);
  });

  testWidgets('type obligatoire', (tester) async {
    final app = await open(tester, '/equipements/nouveau');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom de l\'équipement'),
      'Cuves',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Choisissez un type.'), findsOneWidget);
    expect(app.equipment.writes, isEmpty);
  });

  testWidgets('quitter avec des changements demande confirmation', (
    tester,
  ) async {
    await open(tester, '/equipements/nouveau');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom de l\'équipement'),
      'Brouillon',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);
    await tester.tap(find.text('Continuer la saisie'));
    await tester.pumpAndSettle();
    expect(find.text('Brouillon'), findsOneWidget);
  });

  testWidgets(
    'écran court : une valeur invalide hors écran bloque l\x27enregistrement',
    (tester) async {
      final app = await open(tester, '/equipements/nouveau', height: 600);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom de l\x27équipement'),
        'Cuves',
      );
      await tester.tap(find.text('Cuves séparées'));
      final far = find.widgetWithText(
        TextFormField,
        'Pertes au fermenteur (L)',
      );
      await tester.ensureVisible(far);
      await tester.enterText(far, '-2');
      await tester.pump();
      // Retour en haut : le champ fautif sort de l'écran.
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Nom de l\x27équipement'),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(far).dy, greaterThan(600));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.equipment.writes, isEmpty);
      // L'éditeur défile jusqu'au champ en erreur.
      expect(find.text('Nombre positif attendu.'), findsOneWidget);
      expect(tester.getTopLeft(far).dy, lessThan(600));
    },
  );

  testWidgets('nom manquant : message, défilement et focus sur le nom', (
    tester,
  ) async {
    final app = await open(tester, '/equipements/nouveau', height: 600);
    await tester.tap(find.text('Tout-en-un'));
    await tester.ensureVisible(
      find.widgetWithText(TextFormField, 'Pertes au trub (L)'),
    );
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Donnez un nom à l\x27équipement.'), findsOneWidget);
    final name = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Nom de l\x27équipement'),
        matching: find.byType(EditableText),
      ),
    );
    expect(name.focusNode.hasFocus, isTrue);
    expect(app.equipment.writes, isEmpty);
  });

  testWidgets(
    'fiche : « En attente du réseau » tant que le serveur n\x27a pas reçu',
    (tester) async {
      final app = await open(tester, '/equipements/p');
      app.equipment.publish([
        const Equipment(
          id: 'p',
          ownerUid: 'uid-brasseur',
          content: EquipmentContent(name: 'Neuf', kind: EquipmentKind.allInOne),
          hasPendingWrites: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('En attente du réseau'), findsOneWidget);
    },
  );
}
