import 'dart:async';

import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/library/domain/recette_publique.dart';
import 'package:kass_beer/features/library/domain/referentiel.dart';
import 'package:kass_beer/features/library/presentation/lien_bibliotheque.dart';
import 'package:kass_beer/features/library/presentation/reference_entry_screen.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';
import 'package:kass_beer/features/recipes/presentation/contenu_recette.dart';
import 'package:kass_beer/features/recipes/presentation/recipe_detail_screen.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';
import 'support/library_fixtures.dart';

/// Liens des lignes de houblons et d'autres ajouts vers leur fiche de la
/// Bibliothèque (ADR-018, lot D4).

const _cascade = HopLine(
  name: 'Cascade US',
  amount: Quantite.grammes(20),
  use: HopUse.boil,
  form: 'pellet',
  timeMin: 60,
);

const _inconnu = HopLine(
  name: 'Houblon inconnu',
  amount: Quantite.grammes(10),
  form: 'pellet',
  use: HopUse.boil,
  timeMin: 10,
);

const _mousse = OtherLine(
  name: 'Mousse irlandaise',
  amount: Quantite.grammes(5),
  use: OtherUse.boil,
  timeMin: 15,
);

const _sel = OtherLine(name: 'Sel inventé', amount: Quantite.grammes(2));

const _contenu = RecipeContent(
  name: 'Blonde liée',
  hops: [_cascade, _inconnu],
  others: [_mousse, _sel],
);

final _miscsIndex = indexDoc([
  {
    'id': 'misc-mousse-irlandaise',
    'name': 'Mousse irlandaise',
    'aliases': ['Algue clarifiante'],
    'type': 'fining',
  },
]);

void _indexer(TestApp app) {
  app.library.index[NatureReferentiel.hops] = DocumentTrouve(
    IndexReferentiel.fromFirestore(NatureReferentiel.hops, hopsIndex),
  );
  app.library.index[NatureReferentiel.miscs] = DocumentTrouve(
    IndexReferentiel.fromFirestore(NatureReferentiel.miscs, _miscsIndex),
  );
}

Future<TestApp> _ouvrir(
  WidgetTester tester,
  String path, {
  void Function(TestApp app)? before,
  bool offline = false,
}) async {
  final app = TestApp();
  await app.pump(tester, height: 3200);
  app.signIn(brewerUser, member: brewerMember, fromCache: offline);
  before?.call(app);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

void _recette(TestApp app) => app.recipes.publish([
  Recipe(
    id: 'r1',
    ownerUid: 'uid-brasseur',
    ownerName: 'Bruno Brasseur',
    content: _contenu,
  ),
]);

/// Chemin de la page du dessus, page empilée par `push` comprise.
String _location(TestApp app) =>
    app.container.read(routerProvider).state.uri.path;

Finder get _liees => find.byType(LigneVersBibliotheque);

/// Ligne liée de [nom] : celle qui porte le chevron.
Finder _lien(String nom) => find.ancestor(
  of: find.byIcon(Icons.chevron_right),
  matching: find.widgetWithText(InkWell, nom),
);

void main() {
  testWidgets('fiche d\'une recette : houblon et divers résolus liés, les '
      'autres inchangés', (tester) async {
    await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    expect(_liees, findsNWidgets(4));
    // « Cascade US » : alias de Cascade ; « Mousse irlandaise » : nom.
    expect(_lien('Cascade US'), findsOneWidget);
    expect(_lien('Mousse irlandaise'), findsOneWidget);
    expect(_lien('Houblon inconnu'), findsNothing);
    expect(_lien('Sel inventé'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });

  testWidgets('ouvre la fiche du houblon, la flèche ramène à la recette', (
    tester,
  ) async {
    final app = await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    await tester.tap(_lien('Cascade US'));
    await tester.pumpAndSettle();
    expect(_location(app), '/bibliotheque/houblons/hop-cascade');
    expect(
      find.byWidgetPredicate(
        (w) => w is ReferenceEntryScreen && w.id == 'hop-cascade',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_location(app), '/recettes/r1');
    expect(find.byType(RecipeDetailScreen), findsOneWidget);
  });

  testWidgets('ouvre la fiche du divers ; retour Android vers la recette', (
    tester,
  ) async {
    final app = await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    await tester.tap(_lien('Mousse irlandaise'));
    await tester.pumpAndSettle();
    expect(_location(app), '/bibliotheque/divers/misc-mousse-irlandaise');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_location(app), '/recettes/r1');
  });

  testWidgets('fiche ouverte par son adresse : le retour reste la liste', (
    tester,
  ) async {
    final app = await _ouvrir(
      tester,
      '/bibliotheque/houblons/hop-cascade',
      before: _indexer,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_location(app), '/bibliotheque/houblons');
  });

  testWidgets('clavier : Entrée ouvre la fiche', (tester) async {
    final app = await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    final inkWell = tester.widget<InkWell>(_lien('Mousse irlandaise'));
    expect(inkWell.canRequestFocus, isTrue);
    Focus.of(tester.element(find.text('Mousse irlandaise'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_location(app), '/bibliotheque/divers/misc-mousse-irlandaise');
  });

  testWidgets('clavier : Espace ouvre la fiche', (tester) async {
    final app = await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    Focus.of(tester.element(find.text('Mousse irlandaise'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_location(app), '/bibliotheque/divers/misc-mousse-irlandaise');
  });

  testWidgets('sémantique : un bouton, nom, détails et indice lu une fois', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    final noeud = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^Mousse irlandaise, ')),
    );
    expect(
      noeud,
      matchesSemantics(
        label:
            'Mousse irlandaise, ${detailsAjout(_mousse).join(', ')}. '
            'Ouvre la fiche dans la Bibliothèque.',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    // Hauteur d'appui d'au moins 48 px.
    expect(
      tester.getSize(_lien('Mousse irlandaise')).height,
      greaterThanOrEqualTo(48),
    );
    handle.dispose();
  });

  testWidgets('index absent, en panne ou en lecture : aucun lien', (
    tester,
  ) async {
    final app = await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        app.library.indexErrors[NatureReferentiel.hops] = Exception('panne');
        _recette(app);
      },
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('Cascade US'), findsOneWidget);
    expect(find.text('Mousse irlandaise'), findsOneWidget);
    expect(
      app.library.indexReads,
      containsAll([NatureReferentiel.hops, NatureReferentiel.miscs]),
    );
  });

  testWidgets('index en lecture : sans chevron ni indicateur, chevron dès '
      'qu\'il est lu', (tester) async {
    final attente = Completer<void>();
    await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        app.library.indexAttente[NatureReferentiel.miscs] = attente;
        _recette(app);
      },
    );
    expect(_lien('Cascade US'), findsOneWidget);
    expect(_lien('Mousse irlandaise'), findsNothing);
    expect(find.text('Mousse irlandaise'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    attente.complete();
    await tester.pumpAndSettle();
    expect(_lien('Mousse irlandaise'), findsOneWidget);
  });

  testWidgets('hors ligne : index lu dans le cache, lien actif', (
    tester,
  ) async {
    final app = await _ouvrir(
      tester,
      '/recettes/r1',
      offline: true,
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    expect(app.library.indexCacheReads, contains(NatureReferentiel.hops));
    expect(_lien('Cascade US'), findsOneWidget);
  });

  testWidgets('recette figée d\'un brassin : lignes liées', (tester) async {
    await _ouvrir(
      tester,
      '/brassins/b1',
      before: (app) {
        _indexer(app);
        app.brews.publish([unBrassin(recipe: _contenu)]);
        app.brews.publishEvents('b1', const []);
      },
    );
    await tester.scrollUntilVisible(
      _lien('Mousse irlandaise'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(_lien('Mousse irlandaise'), findsOneWidget);
    expect(_lien('Sel inventé'), findsNothing);
  });

  testWidgets('recette publique : houblon résolu lié, retour à la recette', (
    tester,
  ) async {
    final app = await _ouvrir(
      tester,
      '/bibliotheque/recettes/diydog-1',
      before: (app) {
        app.library.index[NatureReferentiel.hops] = DocumentTrouve(
          IndexReferentiel.fromFirestore(
            NatureReferentiel.hops,
            indexDoc([
              {'id': 'hop-houblon-alpha', 'name': 'Houblon Alpha'},
            ]),
          ),
        );
        app.library.recettes.add(
          RecettePublique.fromFirestore('diydog-1', publicRecipeDoc()),
        );
      },
    );
    expect(_lien('Houblon Alpha'), findsOneWidget);
    expect(_lien('Houblon Arôme'), findsNothing);
    await tester.tap(_lien('Houblon Alpha'));
    await tester.pumpAndSettle();
    expect(_location(app), '/bibliotheque/houblons/hop-houblon-alpha');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_location(app), '/bibliotheque/recettes/diydog-1');
  });

  testWidgets('écran du jour : feuille Recette sans lien ni lecture d\'index', (
    tester,
  ) async {
    final app = TestApp();
    await app.pump(tester);
    app.signIn(brewerUser, member: brewerMember);
    _indexer(app);
    app.brews.publish([
      unBrassin(brewedAt: DateTime(2026, 11, 21, 9), recipe: _contenu),
    ]);
    app.brews.publishEvents('b1', const []);
    await tester.pumpAndSettle();
    app.container.read(routerProvider).go('/brassins/b1/jour');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Plus d\'actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voir la recette'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mousse irlandaise'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(_liees, findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(app.library.indexReads, isNot(contains(NatureReferentiel.hops)));
    expect(app.library.indexReads, isNot(contains(NatureReferentiel.miscs)));
  });

  testWidgets('texte à 200 % : lignes liées sans débordement', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _ouvrir(
      tester,
      '/recettes/r1',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    await tester.scrollUntilVisible(
      _lien('Mousse irlandaise'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    final ligne = tester.getRect(_lien('Mousse irlandaise'));
    final chevron = tester.getRect(
      find.descendant(
        of: _lien('Mousse irlandaise'),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    expect(chevron.right, lessThanOrEqualTo(ligne.right));
    expect(ligne.height, greaterThanOrEqualTo(48));
    // Le nom passe à la ligne au besoin, sans repli.
    expect(find.text('Mousse irlandaise'), findsOneWidget);
  });

  testWidgets('fiche importée (hors coquille, coquille dessous) : aucune '
      'ligne liée', (tester) async {
    final app = await _ouvrir(
      tester,
      '/recettes',
      before: (app) {
        _indexer(app);
        _recette(app);
      },
    );
    // Un `push` d'une page de coquille depuis cette fiche lèverait
    // `!keyReservation.contains(key)` (ticket #60).
    unawaited(app.container.read(routerProvider).push('/recettes/importer/r1'));
    await tester.pumpAndSettle();
    expect(find.text('Cascade US'), findsOneWidget);
    expect(_liees, findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });
}
