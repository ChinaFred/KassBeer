import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/presentation/ligne_editeur.dart';

Future<void> monter(WidgetTester tester, LigneEditeur ligne) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: ligne)));

void main() {
  testWidgets('avec formulaire : bouton « Modifier », ⋮ complet', (
    tester,
  ) async {
    var taps = 0;
    await monter(
      tester,
      LigneEditeur(
        title: '1. Empâtage',
        details: const ['+0 min', '60 min'],
        onTap: () => taps++,
        onRemove: () {},
        onDuplicate: () {},
        onMoveDown: () {},
      ),
    );
    expect(
      find.bySemanticsLabel('1. Empâtage, +0 min, 60 min. Modifier.'),
      findsOneWidget,
    );
    await tester.tap(find.text('1. Empâtage'));
    expect(taps, 1);
    await tester.tap(find.byTooltip('Actions sur « 1. Empâtage »'));
    await tester.pumpAndSettle();
    expect(find.text('Descendre'), findsOneWidget);
    expect(find.text('Dupliquer'), findsOneWidget);
    expect(find.text('Retirer'), findsOneWidget);
    expect(find.text('Monter'), findsNothing);
  });

  testWidgets('sans formulaire : icône en tête, lu sans « Modifier »', (
    tester,
  ) async {
    await monter(
      tester,
      LigneEditeur(
        title: 'Houblons à cru',
        details: const [],
        icone: Icons.menu_book_outlined,
        semanticsLabel: 'Bloc de la recette : Houblons à cru',
        onMoveUp: () {},
        onRemove: () {},
      ),
    );
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel('Bloc de la recette : Houblons à cru.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Modifier')), findsNothing);
  });

  testWidgets('aucune action : pas de ⋮', (tester) async {
    await monter(
      tester,
      const LigneEditeur(
        title: 'Chronologie de la recette',
        details: ['Obligatoire dans la journée de brassage'],
      ),
    );
    expect(find.byType(PopupMenuButton<VoidCallback>), findsNothing);
  });
}
