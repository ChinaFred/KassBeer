import 'package:brewing/brewing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/presentation/formats.dart';
import 'package:kass_beer/core/router/app_router.dart';
import 'package:kass_beer/features/auth/domain/session_user.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/costs/domain/brew_cost.dart';
import 'package:kass_beer/features/costs/domain/fee.dart';
import 'package:kass_beer/features/costs/domain/price.dart';
import 'package:kass_beer/features/costs/presentation/price_form.dart';
import 'package:kass_beer/features/costs/presentation/prices_screen.dart';
import 'package:kass_beer/features/members/domain/member.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/fakes.dart';

const uid = 'uid-brasseur';

String eur(String montant) => '$montant$nbsp€';

Price prix(
  IngredientNature nature,
  String name,
  double priceEur,
  double quantity, {
  CostUnit? unit,
}) => Price(
  key: ingredientKey(nature, name),
  name: name,
  priceEur: priceEur,
  quantity: quantity,
  unit: unit ?? purchaseUnitOf(nature),
);

final pils = prix(IngredientNature.malt, 'Pils', 47.5, 25000);
final cascade = prix(IngredientNature.hop, 'Cascade', 4.5, 100);
final s04 = prix(IngredientNature.yeast, 'S-04', 3.99, 1);
final tousLesPrix = [pils, cascade, s04];

const electricite = Fee(
  id: 'f1',
  name: 'Électricité',
  amountEur: 2,
  basis: FeeBasis.perBrew,
);
const capsules = Fee(
  id: 'f2',
  name: 'Capsules',
  amountEur: 0.05,
  basis: FeeBasis.perBottle,
);

/// 20 L : Pils 5 kg (9,50 €), Cascade 50 g (2,25 €), S-04 (3,99 €). Avec
/// l'électricité et les capsules sur 60,6 bouteilles de 33 cl : 20,77 €.
const blonde = RecipeContent(
  name: 'Blonde',
  batchVolumeL: 20,
  fermentables: [FermentableLine(name: 'Pils', type: 'grain', weightG: 5000)],
  hops: [
    HopLine(
      name: 'Cascade',
      amount: Quantite.grammes(50),
      use: HopUse.boil,
      form: 'pellet',
      timeMin: 60,
    ),
  ],
  yeasts: [YeastLine(name: 'S-04')],
  brewSteps: [palier, ebullition],
);

Recipe recette({String owner = uid}) => Recipe(
  id: 'r1',
  ownerUid: owner,
  ownerName: 'Bruno Brasseur',
  content: blonde,
);

BrewCost coutFige({int? bottles = 50, double? volume = 17}) => BrewCost(
  brewId: 'b1',
  totalEur: 40.84,
  lines: const [
    BrewCostLine(
      key: 'malt-pils',
      name: 'Pils',
      quantity: 5000,
      unit: CostUnit.gram,
      costEur: 9.5,
    ),
    BrewCostLine(
      key: 'frais-f2',
      name: 'Capsules',
      quantity: 50,
      unit: CostUnit.bottle,
      costEur: 2.5,
    ),
  ],
  computedAt: DateTime(2026, 11, 12, 18),
  freezeKind: FreezeKind.initial,
  bottlesCount: bottles,
  packagedVolumeL: volume,
);

final brewedAt = DateTime(2026, 11, 8, 15, 20);

void publierPrix(
  TestApp app, {
  List<Price>? prices,
  List<Fee> fees = const [electricite, capsules],
  bool fromCache = false,
  String owner = uid,
}) {
  app.costs.publishPrices(owner, prices ?? tousLesPrix, fromCache: fromCache);
  app.costs.publishFees(owner, fees, fromCache: fromCache);
}

Future<TestApp> ouvrir(
  WidgetTester tester,
  String path, {
  void Function(TestApp app)? before,
  SessionUser user = brewerUser,
  Member member = brewerMember,
  double width = 400,
  double height = 1400,
}) async {
  final app = TestApp();
  await app.pump(tester, width: width, height: height);
  app.signIn(user, member: member);
  app.now = DateTime(2026, 11, 20, 12);
  before?.call(app);
  await tester.pumpAndSettle();
  app.container.read(routerProvider).go(path);
  await tester.pumpAndSettle();
  return app;
}

Future<TestApp> ficheBrassin(
  WidgetTester tester,
  Brew brew, {
  RechercheDocument<BrewCost>? cout,
  List<Price>? prices,
  List<Fee> fees = const [electricite, capsules],
  bool publier = true,
  SessionUser user = brewerUser,
  Member member = brewerMember,
  double height = 1400,
}) => ouvrir(
  tester,
  '/brassins/b1',
  user: user,
  member: member,
  height: height,
  before: (app) {
    app.brews.publish([brew]);
    app.brews.publishEvents('b1', const []);
    if (publier) {
      publierPrix(app, prices: prices, fees: fees, owner: brew.ownerUid);
      app.costs
          .brewCostOf(brew.ownerUid, 'b1')
          .add(cout ?? const DocumentAbsent<BrewCost>());
    }
  },
);

Future<void> voir(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Finder dansFeuille(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Finder champ(String label) =>
    dansFeuille(find.widgetWithText(TextFormField, label));

Finder dansDialogue(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

Finder dansAnnonce(Finder finder) =>
    find.descendant(of: find.byType(SnackBar), matching: finder);

Brew enFermentation({String owner = uid}) => unBrassin(
  owner: owner,
  status: BrewStatus.fermenting,
  brewedAt: brewedAt,
  recipe: blonde,
);

Brew enConditionnement({int? bottles = 50, double? volume = 17}) => unBrassin(
  status: BrewStatus.conditioning,
  brewedAt: brewedAt,
  bottledAt: DateTime(2026, 11, 12),
  bottlesCount: bottles,
  packagedVolumeL: volume,
  recipe: blonde,
);

void main() {
  group('Mes prix', () {
    testWidgets('menu du compte : « Mes prix » ouvre la page', (tester) async {
      await ouvrir(tester, '/recettes', before: publierPrix);
      await tester.tap(find.byTooltip('Mon compte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mes prix'));
      await tester.pumpAndSettle();
      expect(find.byType(PricesScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Mes prix'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PricesScreen), findsNothing);
    });

    testWidgets('PR11 : aucun prix, aucun frais', (tester) async {
      await ouvrir(
        tester,
        '/prix',
        before: (app) => publierPrix(app, prices: const [], fees: const []),
      );
      expect(find.text(PricesScreen.aucunPrix), findsOneWidget);
      expect(find.text(PricesScreen.aucunFrais), findsOneWidget);
      expect(find.text('Ajouter un prix'), findsOneWidget);
    });

    testWidgets('PR1 : frais triés par nom, prix par nature, format', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/prix',
        before: (app) => publierPrix(
          app,
          prices: [
            pils,
            prix(IngredientNature.malt, 'Munich', 30, 25000),
            prix(IngredientNature.yeast, 'S-04', 3.99, 5),
          ],
        ),
      );
      expect(find.text('2 frais'), findsOneWidget);
      // Nom en titre, montant et base dessous.
      final capsulesY = tester.getTopLeft(find.text('Capsules')).dy;
      final electriciteY = tester.getTopLeft(find.text('Électricité')).dy;
      expect(capsulesY, lessThan(electriciteY));
      expect(
        tester.getTopLeft(find.text('${eur('0,05')} par bouteille')).dy,
        greaterThan(capsulesY),
      );
      expect(
        tester.getTopLeft(find.text('${eur('2,00')} par brassin')).dy,
        greaterThan(electriciteY),
      );
      // Fermées sur téléphone.
      expect(find.text('Pils'), findsNothing);
      expect(find.text('2 prix'), findsOneWidget);
      await tester.tap(find.text('Malts'));
      await tester.pumpAndSettle();
      expect(
        find.text('${eur('47,50')} les 25${nbsp}kg · 1,90$nbsp€/kg'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Munich')).dy,
        lessThan(tester.getTopLeft(find.text('Pils')).dy),
      );
      await tester.tap(find.text('Levures'));
      await tester.pumpAndSettle();
      expect(
        find.text('${eur('3,99')} les 5${nbsp}sachets · 0,80$nbsp€/sachet'),
        findsOneWidget,
      );
    });

    testWidgets('PR4, PR7 : 47,50 € pour 25 kg, enregistré en grammes', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        '/prix',
        before: (app) => publierPrix(app, prices: const []),
      );
      await tester.tap(find.text('Ajouter un prix'));
      await tester.pumpAndSettle();
      expect(dansFeuille(find.text('Nouveau prix')), findsOneWidget);
      await tester.tap(dansFeuille(find.text('Nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Malt').last);
      await tester.pumpAndSettle();
      await tester.enterText(champ('Nom'), 'Pils');
      await tester.enterText(champ('Prix payé (€)'), '47,50');
      await tester.enterText(champ('Quantité achetée (kg)'), '25');
      await tester.pumpAndSettle();
      expect(find.text('Soit 1,90$nbsp€/kg'), findsOneWidget);
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final write = app.costs.writes.single;
      expect(write.kind, 'price');
      expect(write.id, 'malt-pils');
      final saved = write.value! as Price;
      expect(saved.priceEur, 47.5);
      expect(saved.quantity, 25000);
      expect(saved.unit, CostUnit.gram);
      expect(find.text('Prix enregistré.'), findsOneWidget);
    });

    testWidgets('unités kg, g, L, ml en colonne à 360 dp et 200 % ; prix au '
        'gramme remplacé par un prix au litre', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final lactique = prix(
        IngredientNature.addition,
        'Acide lactique',
        6,
        100,
      );
      await ouvrir(
        tester,
        '/prix',
        width: 360,
        before: (app) => publierPrix(app, prices: [lactique]),
      );
      // Nouveau prix du même ingrédient : il remplacera le prix au gramme.
      await tester.tap(find.text('Ajouter un prix'));
      await tester.pumpAndSettle();
      await tester.tap(dansFeuille(find.text('Nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajout').last);
      await tester.pumpAndSettle();
      await tester.enterText(champ('Nom'), 'Acide lactique');
      await tester.pumpAndSettle();
      final unites = tester.widget<SegmentedButton<UniteAchat>>(
        dansFeuille(find.byType(SegmentedButton<UniteAchat>)),
      );
      expect(unites.direction, Axis.vertical);
      expect(unites.segments, hasLength(4));
      expect(tester.takeException(), isNull);
      expect(dansFeuille(find.text(TextesPrix.remplaceAuGramme)), findsNothing);
      final litres = dansFeuille(find.text('L'));
      await tester.ensureVisible(litres);
      await tester.tap(litres);
      await tester.pumpAndSettle();
      expect(
        dansFeuille(find.text(TextesPrix.remplaceAuGramme)),
        findsOneWidget,
      );
    });

    testWidgets('ligne en volume, unité choisie en grammes : avertissement', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([
            Recipe(
              id: 'r1',
              ownerUid: uid,
              content: const RecipeContent(
                name: 'Saison',
                batchVolumeL: 20,
                others: [
                  OtherLine(
                    name: 'Acide lactique',
                    amount: Quantite.litres(0.005),
                  ),
                ],
              ),
            ),
          ]);
          publierPrix(app, prices: const [], fees: const []);
        },
      );
      await voir(tester, find.text('Saisir le prix au litre'));
      await tester.tap(find.text('Saisir le prix au litre'));
      await tester.pumpAndSettle();
      expect(dansFeuille(find.text(TextesPrix.ligneEnVolume)), findsNothing);
      await tester.tap(dansFeuille(find.text('g')));
      await tester.pumpAndSettle();
      expect(dansFeuille(find.text(TextesPrix.ligneEnVolume)), findsOneWidget);
    });

    testWidgets('PR6, PR8 : prix inhabituel, prix existant remplacé', (
      tester,
    ) async {
      final app = await ouvrir(tester, '/prix', before: publierPrix);
      await tester.tap(find.text('Ajouter un prix'));
      await tester.pumpAndSettle();
      await tester.tap(dansFeuille(find.text('Nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Malt').last);
      await tester.pumpAndSettle();
      await tester.enterText(champ('Nom'), 'pils');
      await tester.pumpAndSettle();
      expect(
        find.text('Un prix existe déjà pour « Pils ». Il sera remplacé.'),
        findsOneWidget,
      );
      await tester.enterText(champ('Prix payé (€)'), '47,50');
      await tester.tap(dansFeuille(find.text('g')));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Quantité achetée (g)'), '25');
      await tester.pumpAndSettle();
      expect(
        find.text('Prix inhabituel : vérifiez la quantité.'),
        findsOneWidget,
      );
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      // Non bloquant ; un seul document par clé.
      expect(app.costs.writes.single.id, 'malt-pils');
      expect((app.costs.writes.single.value! as Price).quantity, 25);
    });

    testWidgets('PR9 : nom sans lettre ni chiffre refusé', (tester) async {
      final app = await ouvrir(tester, '/prix', before: publierPrix);
      await tester.tap(find.text('Ajouter un prix'));
      await tester.pumpAndSettle();
      await tester.tap(dansFeuille(find.text('Nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Houblon').last);
      await tester.pumpAndSettle();
      await tester.enterText(champ('Nom'), '---');
      await tester.enterText(champ('Prix payé (€)'), '4');
      await tester.enterText(champ('Quantité achetée (g)'), '100');
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      expect(
        find.text('Le nom doit contenir une lettre ou un chiffre.'),
        findsOneWidget,
      );
      expect(app.costs.writes, isEmpty);
    });

    testWidgets('U3 : prix illisible supprimé après confirmation', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        '/prix',
        before: (app) {
          app.costs
              .pricesOf(uid)
              .add(
                const ListeLue(
                  documents: [
                    DocumentInvalide<Price>(
                      'malt-pils',
                      DocumentIllisible('unit', 'unité d\'achat inconnue'),
                    ),
                  ],
                  fromCache: false,
                ),
              );
          app.costs.publishFees(uid, const [electricite]);
        },
      );
      expect(
        find.text(
          'Ce prix ne peut pas être lu. Supprimez-le, puis saisissez-le de '
          'nouveau.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Supprimer le prix illisible'));
      await tester.pumpAndSettle();
      expect(
        dansDialogue(find.text('Supprimer le prix illisible ?')),
        findsOneWidget,
      );
      await tester.tap(dansDialogue(find.text('Annuler')));
      await tester.pumpAndSettle();
      expect(app.costs.writes, isEmpty);
      await tester.tap(find.bySemanticsLabel('Supprimer le prix illisible'));
      await tester.pumpAndSettle();
      await tester.tap(dansDialogue(find.text('Supprimer')));
      await tester.pumpAndSettle();
      expect(app.costs.writes.single.kind, 'price_delete');
      expect(app.costs.writes.single.id, 'malt-pils');
    });

    testWidgets(
      'S4 : clés hors format, illisibles, supprimées sans rien réécrire',
      (tester) async {
        final app = await ouvrir(
          tester,
          '/prix',
          before: (app) {
            app.costs
                .pricesOf(uid)
                .add(
                  const ListeLue(
                    documents: [
                      DocumentInvalide<Price>(
                        'autre-x',
                        DocumentIllisible('id', 'clé hors format'),
                      ),
                      DocumentInvalide<Price>(
                        'malt-Pils',
                        DocumentIllisible('id', 'clé hors format'),
                      ),
                    ],
                    fromCache: false,
                  ),
                );
            app.costs.publishFees(uid, const [electricite]);
          },
        );
        expect(find.text('Prix illisible'), findsNWidgets(2));
        expect(find.text('Autres'), findsNothing);
        for (var i = 0; i < 2; i++) {
          await tester.tap(
            // Le double ne retire pas la ligne : chacune à son tour.
            find.bySemanticsLabel('Supprimer le prix illisible').at(i),
          );
          await tester.pumpAndSettle();
          await tester.tap(dansDialogue(find.text('Supprimer')));
          await tester.pumpAndSettle();
          expect(dansAnnonce(find.text('Annuler')), findsNothing);
        }
        expect(app.costs.writes.map((w) => w.kind), [
          'price_delete',
          'price_delete',
        ]);
        expect(app.costs.writes.map((w) => w.id), ['autre-x', 'malt-Pils']);
      },
    );

    testWidgets('PR10 : Supprimer, puis Annuler réécrit le même document', (
      tester,
    ) async {
      final app = await ouvrir(tester, '/prix', before: publierPrix);
      await tester.tap(find.text('Malts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pils'));
      await tester.pumpAndSettle();
      expect(dansFeuille(find.text('Modifier le prix')), findsOneWidget);
      expect(
        dansFeuille(
          find.text(
            'Le nom suit celui des recettes. Pour le changer, supprimez ce '
            'prix et ajoutez-en un autre.',
          ),
        ),
        findsOneWidget,
      );
      expect(champ('Nom'), findsNothing);
      await tester.tap(dansFeuille(find.text('Supprimer')));
      await tester.pumpAndSettle();
      expect(app.costs.writes.single.kind, 'price_delete');
      expect(find.text('Prix de « Pils » supprimé.'), findsOneWidget);
      await tester.tap(dansAnnonce(find.text('Annuler')));
      await tester.pumpAndSettle();
      expect(app.costs.writes.last.kind, 'price');
      expect(app.costs.writes.last.value, same(pils));
    });

    testWidgets('FR1, FR2 : frais saisi, base obligatoire, aucune valeur', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        '/prix',
        before: (app) => publierPrix(app, fees: const []),
      );
      await tester.tap(find.text('Ajouter un frais'));
      await tester.pumpAndSettle();
      expect(dansFeuille(find.text('Nouveau frais')), findsOneWidget);
      expect(champ('Montant (€)'), findsOneWidget);
      await tester.enterText(champ('Nom'), 'Capsules');
      await tester.enterText(champ('Montant (€)'), '0,05');
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      expect(find.text('Choisissez une base.'), findsOneWidget);
      expect(app.costs.writes, isEmpty);
      await tester.tap(dansFeuille(find.text('Par bouteille')));
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final fee = app.costs.writes.single.value! as Fee;
      expect(fee.name, 'Capsules');
      expect(fee.amountEur, 0.05);
      expect(fee.basis, FeeBasis.perBottle);
      expect(fee.id, 'fee-0');
      expect(find.text('Frais enregistré.'), findsOneWidget);
    });

    testWidgets('FR1 : 20 frais au plus', (tester) async {
      await ouvrir(
        tester,
        '/prix',
        height: 2400,
        before: (app) => publierPrix(
          app,
          fees: [
            for (var i = 0; i < kMaxFees; i++)
              Fee(
                id: 'f$i',
                name: 'Frais $i',
                amountEur: 1,
                basis: FeeBasis.perBrew,
              ),
          ],
        ),
      );
      expect(find.text(PricesScreen.limiteFrais), findsOneWidget);
      expect(find.text('Ajouter un frais'), findsNothing);
    });

    testWidgets('lecture en panne : message et Réessayer', (tester) async {
      final app = await ouvrir(
        tester,
        '/prix',
        before: (app) {
          app.costs.pricesOf(uid).addError(Exception('refus'));
          app.costs.publishFees(uid, const []);
        },
      );
      expect(find.text('Impossible de lire vos prix.'), findsOneWidget);
      final avant = app.costs.pricesOf(uid).subscriptions;
      app.costs.publishPrices(uid, tousLesPrix);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(app.costs.pricesOf(uid).subscriptions, greaterThan(avant));
      expect(find.text('Ingrédients'), findsOneWidget);
    });

    testWidgets('HL4 : hors ligne sans cache, indisponible', (tester) async {
      await ouvrir(
        tester,
        '/prix',
        before: (app) =>
            publierPrix(app, prices: const [], fees: const [], fromCache: true),
      );
      expect(
        find.text('Prix indisponibles sur cet appareil hors ligne.'),
        findsOneWidget,
      );
      expect(find.text('Réessayer'), findsNothing);
      expect(find.text('Ajouter un prix'), findsNothing);
    });

    testWidgets('texte à 200 %, thème sombre : lisible', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ouvrir(tester, '/prix', width: 360, before: publierPrix);
      await tester.tap(find.text('Malts'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Pils'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });

  group('coût d\'une recette', () {
    testWidgets('CR1, CR2 : total, par litre, 33 cl ; rien n\'est écrit', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(app);
        },
      );
      await voir(tester, find.text('Coût avec vos prix'));
      expect(find.text(eur('20,77')), findsOneWidget);
      expect(find.text('1,04$nbsp€/L'), findsOneWidget);
      expect(find.text(eur('0,34')), findsOneWidget);
      expect(
        find.text('Pour 20${nbsp}L · environ 61 bouteilles de 33 cl'),
        findsOneWidget,
      );
      await voir(tester, find.text('Détail du coût'));
      await tester.tap(find.text('Détail du coût'));
      await tester.pumpAndSettle();
      expect(find.text('Pils · 5${nbsp}kg · ${eur('9,50')}'), findsOneWidget);
      expect(
        find.text('S-04 · 1${nbsp}sachet · ${eur('3,99')}'),
        findsOneWidget,
      );
      expect(
        find.text('Capsules · par bouteille · ${eur('3,03')}'),
        findsOneWidget,
      );
      expect(app.recipes.writes, isEmpty);
      expect(app.costs.writes, isEmpty);
    });

    testWidgets('CR4 : un prix manquant, liste et aucun montant', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(app, prices: [pils, s04]);
        },
      );
      await voir(tester, find.text('Coût indisponible : 1 prix manquant.'));
      expect(find.text('Cascade · 50${nbsp}g'), findsOneWidget);
      expect(find.text('Saisir le prix'), findsOneWidget);
      expect(find.textContaining('€'), findsNothing);
      expect(
        find.bySemanticsLabel('Cascade, 50 grammes, prix manquant'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Saisir le prix de Cascade'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.text('Coût indisponible : 1 prix manquant.')),
        isSemantics(isLiveRegion: true),
      );
    });

    testWidgets('LI7 : Saisir le prix sans quitter la recette', (tester) async {
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(app, prices: [pils, s04]);
        },
      );
      await voir(tester, find.text('Saisir le prix'));
      await tester.tap(find.text('Saisir le prix'));
      await tester.pumpAndSettle();
      expect(dansFeuille(find.text('Prix de « Cascade »')), findsOneWidget);
      expect(dansFeuille(find.text('Houblon · Cascade')), findsOneWidget);
      // Aucun prix de houblon à reprendre.
      expect(find.text('Reprendre un de mes prix'), findsNothing);
      await tester.enterText(champ('Prix payé (€)'), '4,5');
      await tester.enterText(champ('Quantité achetée (g)'), '100');
      await tester.pumpAndSettle();
      expect(find.text('Soit 45,00$nbsp€/kg'), findsOneWidget);
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final saved = app.costs.writes.single.value! as Price;
      expect(saved.key, 'houblon-cascade');
      expect(saved.quantity, 100);
      expect(find.text('Prix enregistré.'), findsOneWidget);
      // Le flux renvoie la liste à jour : le montant apparaît, le focus est sur
      // le titre du bloc.
      app.costs.publishPrices(uid, tousLesPrix);
      await tester.pumpAndSettle();
      expect(find.text(eur('20,77')), findsOneWidget);
      final titre = tester.widget<Focus>(
        find
            .ancestor(
              of: find.text('Coût avec vos prix'),
              matching: find.byType(Focus),
            )
            .first,
      );
      expect(titre.focusNode!.hasFocus, isTrue);
      expect(titre.focusNode!.skipTraversal, isTrue);
    });

    testWidgets('S2 : nom de 121 caractères d\'une recette importée, coupé', (
      tester,
    ) async {
      final long = 'C${'a' * 120}';
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([
            Recipe(
              id: 'r1',
              ownerUid: 'uid-autre',
              ownerName: 'Autre',
              content: RecipeContent(
                name: 'Longue',
                batchVolumeL: 20,
                hops: [
                  HopLine(
                    name: long,
                    amount: Quantite.grammes(50),
                    use: HopUse.boil,
                    form: 'pellet',
                    timeMin: 60,
                  ),
                ],
              ),
            ),
          ]);
          publierPrix(app, prices: const []);
        },
      );
      await voir(tester, find.text('Saisir le prix'));
      await tester.tap(find.text('Saisir le prix'));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Prix payé (€)'), '4');
      await tester.enterText(champ('Quantité achetée (g)'), '100');
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final saved = app.costs.writes.single.value! as Price;
      expect(long.length, 121);
      expect(saved.name.length, lessThanOrEqualTo(kPriceNameMaxLength));
      expect(saved.key, ingredientKey(IngredientNature.hop, long));
    });

    testWidgets('U6 : unité incompatible, quantité à saisir de nouveau', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(
            app,
            prices: [
              prix(IngredientNature.malt, 'Pils', 47.5, 2, unit: CostUnit.unit),
              cascade,
              s04,
            ],
          );
        },
      );
      // L'unité demandée est celle de la ligne : des grammes.
      await voir(
        tester,
        find.text(
          'Pils · 5${nbsp}kg : votre prix est au sachet. Saisissez un prix au '
          'gramme pour compter cette ligne.',
        ),
      );
      await tester.tap(find.text('Corriger le prix'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'L\'unité enregistrée ne correspond pas : saisissez la quantité en '
          'kg.',
        ),
        findsOneWidget,
      );
      await tester.enterText(champ('Quantité achetée (kg)'), '25');
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final saved = app.costs.writes.single.value! as Price;
      expect(saved.unit, CostUnit.gram);
      expect(saved.quantity, 25000);
    });

    // v0.1.17 — prix au litre (décision du 2026-11-10).
    Recipe saison(List<OtherLine> others, {String owner = uid}) => Recipe(
      id: 'r1',
      ownerUid: owner,
      ownerName: 'Bruno Brasseur',
      content: RecipeContent(
        name: 'Saison',
        batchVolumeL: 20,
        fermentables: const [
          FermentableLine(name: 'Pils', type: 'grain', weightG: 5000),
        ],
        others: others,
        yeasts: const [YeastLine(name: 'S-04')],
      ),
    );
    const lactique5ml = OtherLine(
      name: 'Acide lactique',
      amount: Quantite.litres(0.005),
    );

    testWidgets('ligne en ml sans prix : Saisir le prix au litre, enregistré '
        'en litres, ligne chiffrée', (tester) async {
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([
            saison(const [lactique5ml]),
          ]);
          publierPrix(app, prices: [pils, s04], fees: const []);
        },
      );
      await voir(tester, find.text('Acide lactique · 5${nbsp}ml'));
      await tester.tap(find.text('Saisir le prix au litre'));
      await tester.pumpAndSettle();
      // La ligne est en volume : la saisie s'ouvre en litres.
      expect(champ('Quantité achetée (L)'), findsOneWidget);
      await tester.tap(dansFeuille(find.text('ml')));
      await tester.pumpAndSettle();
      await tester.enterText(champ('Prix payé (€)'), '6');
      await tester.enterText(champ('Quantité achetée (ml)'), '100');
      await tester.pumpAndSettle();
      expect(find.text('Soit 60,00$nbsp€/L'), findsOneWidget);
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final saved = app.costs.writes.single.value! as Price;
      expect(saved.key, 'ajout-acide-lactique');
      expect(saved.unit, CostUnit.litre);
      expect(saved.quantity, closeTo(0.1, 1e-12));
      app.costs.publishPrices(uid, [pils, s04, saved]);
      await tester.pumpAndSettle();
      // 9,50 + 0,30 (5 ml à 60 €/L) + 3,99.
      expect(find.text(eur('13,79')), findsOneWidget);
    });

    testWidgets('ligne en ml, prix au gramme ; ligne en g, prix au litre : '
        'texte de chaque sens', (tester) async {
      final auGramme = prix(
        IngredientNature.addition,
        'Acide lactique',
        6,
        100,
      );
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([
            saison(const [lactique5ml]),
          ]);
          publierPrix(app, prices: [pils, s04, auGramme], fees: const []);
        },
      );
      final texte = find.text(
        'Acide lactique · 5${nbsp}ml : votre prix est au gramme. Saisissez un '
        'prix au litre pour compter cette ligne.',
      );
      await voir(tester, texte);
      expect(texte, findsOneWidget);
      app.recipes.publish([
        saison(const [
          OtherLine(name: 'Acide lactique', amount: Quantite.grammes(5)),
        ]),
      ]);
      app.costs.publishPrices(uid, [
        pils,
        s04,
        prix(
          IngredientNature.addition,
          'Acide lactique',
          6.5,
          0.1,
          unit: CostUnit.litre,
        ),
      ]);
      await tester.pumpAndSettle();
      final inverse = find.text(
        'Acide lactique · 5${nbsp}g : votre prix est au litre. Saisissez un '
        'prix au gramme pour compter cette ligne.',
      );
      await voir(tester, inverse);
      expect(inverse, findsOneWidget);
    });

    testWidgets('même nom en g et en ml : auteur, autre membre', (
      tester,
    ) async {
      const deux = [
        lactique5ml,
        OtherLine(name: 'Acide lactique', amount: Quantite.grammes(2)),
      ];
      const commun =
          'Acide lactique : quantités en grammes et en volume, qui ne '
          's\'additionnent pas.';
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([saison(deux)]);
          publierPrix(app, prices: [pils, s04], fees: const []);
        },
      );
      final auteur = find.text(
        '$commun Mettez les deux lignes dans la même unité.',
      );
      await voir(tester, auteur);
      expect(auteur, findsOneWidget);
      app.recipes.publish([saison(deux, owner: 'uid-autre')]);
      await tester.pumpAndSettle();
      final lecteur = find.text(
        '$commun Dupliquez la recette pour la corriger à votre nom.',
      );
      await voir(tester, lecteur);
      expect(lecteur, findsOneWidget);
    });

    testWidgets('LI6 : Reprendre un de mes prix copie sans lier', (
      tester,
    ) async {
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(
            app,
            prices: [
              pils,
              s04,
              prix(IngredientNature.hop, 'Cascade bio', 6, 100),
            ],
          );
        },
      );
      await voir(tester, find.text('Saisir le prix'));
      await tester.tap(find.text('Saisir le prix'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reprendre un de mes prix'));
      await tester.pumpAndSettle();
      expect(find.text('Reprendre un prix de houblon'), findsOneWidget);
      await tester.tap(find.text('Cascade bio'));
      await tester.pumpAndSettle();
      await tester.tap(dansFeuille(find.text('Enregistrer')));
      await tester.pumpAndSettle();
      final saved = app.costs.writes.single.value! as Price;
      expect(saved.key, 'houblon-cascade');
      expect(saved.name, 'Cascade');
      expect(saved.priceEur, 6);
      expect(saved.quantity, 100);
    });

    testWidgets('CR7 : recette d\'un autre, calculée avec mes prix', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette(owner: 'uid-autre')]);
          publierPrix(app);
          publierPrix(app, prices: const [], owner: 'uid-autre');
        },
      );
      await voir(tester, find.text('Coût avec vos prix'));
      expect(find.text(eur('20,77')), findsOneWidget);
      expect(find.text('Compléter la recette'), findsNothing);
    });

    testWidgets('FR5 : aucun frais, mention et accès à Mes prix', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(app, fees: const []);
        },
      );
      await voir(tester, find.text('Ajouter mes frais'));
      expect(find.text(eur('15,74')), findsOneWidget);
      expect(
        find.text('Aucun frais compté (eau, électricité, embouteillage).'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ajouter mes frais'));
      await tester.pumpAndSettle();
      expect(find.byType(PricesScreen), findsOneWidget);
    });

    testWidgets('HL4 : prix absents du cache, jamais « manquant »', (
      tester,
    ) async {
      await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(app, prices: const [], fromCache: true);
        },
      );
      await voir(tester, find.text('Coût avec vos prix'));
      expect(
        find.text('Prix indisponibles sur cet appareil hors ligne.'),
        findsOneWidget,
      );
      expect(find.text('Saisir le prix'), findsNothing);
    });

    testWidgets('chargement puis panne de la lecture des prix', (tester) async {
      final app = await ouvrir(
        tester,
        '/recettes/r1',
        before: (app) => app.recipes.publish([recette()]),
      );
      await voir(tester, find.text('Chargement de vos prix'));
      app.costs.pricesOf(uid).addError(Exception('refus'));
      await tester.pumpAndSettle();
      expect(find.text('Impossible de lire vos prix.'), findsOneWidget);
    });

    testWidgets('texte à 200 %, contraste clair et sombre', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ouvrir(
        tester,
        '/recettes/r1',
        width: 360,
        height: 3000,
        before: (app) {
          app.recipes.publish([recette()]);
          publierPrix(app, prices: [pils, s04], fees: const []);
        },
      );
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });

  group('coût d\'un brassin', () {
    testWidgets('CB1 : un autre membre ne voit ni bloc ni titre', (
      tester,
    ) async {
      final app = await ficheBrassin(
        tester,
        unBrassin(
          owner: 'uid-autre',
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 12),
          recipe: blonde,
        ),
        cout: DocumentTrouve(coutFige()),
      );
      await voir(tester, find.text('Embouteillage'));
      expect(find.text('Coût'), findsNothing);
      expect(find.text('Coût non figé'), findsNothing);
      expect(find.textContaining('€'), findsNothing);
      expect(app.costs.pricesOf('uid-autre').subscriptions, 0);
      expect(app.costs.brewCostOf('uid-autre', 'b1').subscriptions, 0);
    });

    testWidgets('CB1 : l\'admin ne voit pas le bloc d\'un autre', (
      tester,
    ) async {
      await ficheBrassin(
        tester,
        enFermentation(owner: 'uid-autre'),
        user: adminUser,
        member: adminMember,
      );
      expect(find.text('Coût'), findsNothing);
      expect(find.text('Coût estimé avec vos prix actuels'), findsNothing);
    });

    testWidgets('CB2 : estimation avec les prix actuels, rien n\'est écrit', (
      tester,
    ) async {
      final app = await ficheBrassin(tester, enFermentation());
      await voir(tester, find.text('Coût estimé avec vos prix actuels'));
      expect(find.text(eur('20,77')), findsOneWidget);
      expect(find.text('Bouteille de 33 cl'), findsOneWidget);
      expect(
        find.text(
          'Pour 20${nbsp}L · environ 61 bouteilles de 33 cl, nombre de '
          'bouteilles non renseigné',
        ),
        findsOneWidget,
      );
      // Rattrapage hors de En conditionnement, Terminé, Abandonné.
      expect(find.text('Figer le coût'), findsNothing);
      expect(app.costs.writes, isEmpty);
      expect(app.brews.writes, isEmpty);
    });

    testWidgets('CB3 à CB9 : premier embouteillage, coût figé, sans montant', (
      tester,
    ) async {
      final app = await ficheBrassin(tester, enFermentation());
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre de bouteilles (facultatif)'),
        '50',
      );
      await tester.tap(find.text('Enregistrer l\'embouteillage'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'bottling');
      final write = app.costs.writes.single;
      expect(write.kind, 'brew_cost');
      expect(write.uid, uid);
      final cost = write.value! as BrewCost;
      expect(cost.freezeKind, FreezeKind.initial);
      expect(cost.bottlesCount, 50);
      expect(cost.totalEur, closeTo(15.74 + 2 + 2.5, 1e-9));
      expect(cost.computedAt, app.now);
      expect(
        find.text(
          'Embouteillage enregistré. Brassin en conditionnement. Coût figé.',
        ),
        findsOneWidget,
      );
      expect(dansAnnonce(find.textContaining('€')), findsNothing);
    });

    testWidgets('CB8 : prix manquant, embouteillage enregistré, Voir le coût', (
      tester,
    ) async {
      final app = await ficheBrassin(
        tester,
        enFermentation(),
        prices: [pils, s04],
        height: 700,
      );
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enregistrer l\'embouteillage'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer l\'embouteillage'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'bottling');
      expect(app.costs.writes, isEmpty);
      const annonce =
          'Embouteillage enregistré. Brassin en conditionnement. Coût non figé.';
      expect(find.text(annonce), findsOneWidget);
      expect(dansAnnonce(find.textContaining('€')), findsNothing);
      // La fiche reçoit le nouvel état du brassin.
      app.brews.publish([
        unBrassin(
          status: BrewStatus.conditioning,
          brewedAt: brewedAt,
          bottledAt: DateTime(2026, 11, 20),
          recipe: blonde,
        ),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(dansAnnonce(find.text('Voir le coût')));
      await tester.pumpAndSettle();
      expect(find.text('Coût non figé'), findsOneWidget);
      expect(find.text('Cascade · 50${nbsp}g'), findsOneWidget);
    });

    testWidgets('CB7 : refus du seul coût annoncé', (tester) async {
      // Aucun frais par bouteille : le coût se fige sans nombre de bouteilles.
      final app = await ficheBrassin(
        tester,
        enFermentation(),
        fees: const [electricite],
      );
      app.costs.serverAnswer = () => Future.error(Exception('refus'));
      await tester.tap(find.text('Embouteiller'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer l\'embouteillage'));
      await tester.pumpAndSettle();
      expect(
        find.text('Coût non figé : l\'enregistrement a été refusé.'),
        findsOneWidget,
      );
      expect(dansAnnonce(find.text('Voir le coût')), findsOneWidget);
    });

    testWidgets(
      'CB3 : retour en arrière puis embouteillage, aucun coût écrit',
      (tester) async {
        final app = await ficheBrassin(
          tester,
          unBrassin(
            status: BrewStatus.fermenting,
            brewedAt: brewedAt,
            bottledAt: DateTime(2026, 11, 12),
            bottlesCount: 50,
            recipe: blonde,
          ),
          fees: const [electricite],
        );
        await tester.tap(find.text('Embouteiller'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Enregistrer l\'embouteillage'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Enregistrer l\'embouteillage'));
        await tester.pumpAndSettle();
        expect(app.brews.writes.single.kind, 'bottling');
        expect(app.costs.writes, isEmpty);
        expect(
          find.text('Embouteillage enregistré. Brassin en conditionnement.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('CB3 : modification de l\'embouteillage, aucun coût écrit', (
      tester,
    ) async {
      final app = await ficheBrassin(
        tester,
        enConditionnement(),
        cout: const DocumentAbsent<BrewCost>(),
      );
      await voir(tester, find.text('Modifier l\'embouteillage'));
      await tester.tap(find.text('Modifier l\'embouteillage'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();
      expect(app.brews.writes.single.kind, 'bottling');
      expect(app.costs.writes, isEmpty);
      expect(find.text('Embouteillage modifié.'), findsOneWidget);
    });

    testWidgets('CB12 : coût figé, inchangé quand un prix change', (
      tester,
    ) async {
      final app = await ficheBrassin(
        tester,
        enConditionnement(),
        cout: DocumentTrouve(coutFige()),
      );
      await voir(tester, find.text('Coût figé le 12 nov. 2026'));
      expect(find.text(eur('40,84')), findsOneWidget);
      expect(find.text('Par bouteille (50${nbsp}bouteilles)'), findsOneWidget);
      expect(find.text(eur('0,82')), findsOneWidget);
      expect(find.text('Par litre (17${nbsp}L)'), findsOneWidget);
      expect(find.text('2,40$nbsp€/L'), findsOneWidget);
      expect(find.text('Figer le coût'), findsNothing);
      app.costs.publishPrices(uid, [
        prix(IngredientNature.malt, 'Pils', 95, 25000),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(eur('40,84')), findsOneWidget);
      expect(app.costs.writes, isEmpty);
    });

    testWidgets('CB12 : sans nombre de bouteilles ni volume conditionné', (
      tester,
    ) async {
      await ficheBrassin(
        tester,
        enConditionnement(bottles: null, volume: null),
        cout: DocumentTrouve(coutFige(bottles: null, volume: null)),
      );
      await voir(tester, find.text('Aucun frais par bouteille compté.'));
      expect(find.textContaining('Par bouteille'), findsNothing);
      expect(find.textContaining('Par litre'), findsNothing);
    });

    testWidgets('CB15, CB16 : écart, Recalculer après confirmation', (
      tester,
    ) async {
      final app = await ficheBrassin(
        tester,
        enConditionnement(bottles: 52),
        cout: DocumentTrouve(coutFige()),
      );
      await voir(
        tester,
        find.text(
          'L\'embouteillage a changé depuis le figeage : Bouteilles 50 → 52.',
        ),
      );
      expect(find.text(eur('40,84')), findsOneWidget);
      expect(app.costs.writes, isEmpty);
      await voir(
        tester,
        find.widgetWithText(OutlinedButton, 'Recalculer avec mes prix actuels'),
      );
      await tester.tap(find.text('Recalculer avec mes prix actuels'));
      await tester.pumpAndSettle();
      expect(
        dansDialogue(find.text('Remplacer le coût figé ?')),
        findsOneWidget,
      );
      expect(
        dansDialogue(
          find.text(
            '${eur('40,84')} du 12 nov. 2026 deviendra ${eur('20,34')}. Les '
            'prix actuels remplacent ceux du figeage.',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(dansDialogue(find.text('Remplacer')));
      await tester.pumpAndSettle();
      final cost = app.costs.writes.single.value! as BrewCost;
      expect(cost.freezeKind, FreezeKind.recalculation);
      expect(cost.bottlesCount, 52);
      expect(find.text('Coût recalculé.'), findsOneWidget);
    });

    testWidgets(
      'U5 : Recalculer sans bouteilles, sans les frais par bouteille',
      (tester) async {
        final app = await ficheBrassin(
          tester,
          enConditionnement(bottles: null, volume: null),
          cout: DocumentTrouve(coutFige(bottles: null, volume: null)),
        );
        await voir(tester, find.text('Recalculer avec mes prix actuels'));
        await tester.tap(find.text('Recalculer avec mes prix actuels'));
        await tester.pumpAndSettle();
        expect(
          dansDialogue(find.text('Remplacer le coût figé ?')),
          findsOneWidget,
        );
        expect(
          dansDialogue(
            find.text(
              'Aucun nombre de bouteilles n\'est renseigné : les frais par '
              'bouteille ne seront pas comptés.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          dansDialogue(find.text('Renseigner les bouteilles')),
          findsOneWidget,
        );
        await tester.tap(dansDialogue(find.text('Remplacer')));
        await tester.pumpAndSettle();
        final cost = app.costs.writes.single.value! as BrewCost;
        expect(cost.freezeKind, FreezeKind.recalculation);
        expect(cost.lines.map((l) => l.name), isNot(contains('Capsules')));
        expect(find.text('Coût recalculé.'), findsOneWidget);
      },
    );

    testWidgets('CB16 : Annuler le dialogue n\'écrit rien', (tester) async {
      final app = await ficheBrassin(
        tester,
        enConditionnement(),
        cout: DocumentTrouve(coutFige()),
      );
      await voir(tester, find.text('Recalculer avec mes prix actuels'));
      await tester.tap(find.text('Recalculer avec mes prix actuels'));
      await tester.pumpAndSettle();
      await tester.tap(dansDialogue(find.text('Annuler')));
      await tester.pumpAndSettle();
      expect(app.costs.writes, isEmpty);
    });

    testWidgets('CB11 : sans bouteilles, dialogue à trois boutons', (
      tester,
    ) async {
      final app = await ficheBrassin(
        tester,
        enConditionnement(bottles: null, volume: null),
      );
      await voir(tester, find.text('Coût non figé'));
      expect(
        find.text(
          'Nombre de bouteilles non renseigné : les frais par bouteille ne '
          'peuvent pas être comptés.',
        ),
        findsOneWidget,
      );
      await voir(tester, find.text('Figer le coût'));
      await tester.tap(find.text('Figer le coût'));
      await tester.pumpAndSettle();
      expect(
        dansDialogue(find.text('Figer sans les frais par bouteille ?')),
        findsOneWidget,
      );
      expect(dansDialogue(find.byType(TextButton)), findsNWidgets(2));
      expect(
        dansDialogue(find.text('Renseigner les bouteilles')),
        findsOneWidget,
      );
      await tester.tap(dansDialogue(find.text('Figer')));
      await tester.pumpAndSettle();
      final cost = app.costs.writes.single.value! as BrewCost;
      expect(cost.freezeKind, FreezeKind.initial);
      expect(cost.lines.map((l) => l.name), isNot(contains('Capsules')));
      expect(cost.totalEur, closeTo(15.74 + 2, 1e-9));
      expect(find.text('Coût figé.'), findsOneWidget);
    });

    testWidgets('CB11 : Renseigner les bouteilles ouvre l\'embouteillage', (
      tester,
    ) async {
      final app = await ficheBrassin(
        tester,
        enConditionnement(bottles: null, volume: null),
      );
      await voir(tester, find.text('Figer le coût'));
      await tester.tap(find.text('Figer le coût'));
      await tester.pumpAndSettle();
      await tester.tap(dansDialogue(find.text('Renseigner les bouteilles')));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Nombre de bouteilles (facultatif)'),
        findsOneWidget,
      );
      expect(app.costs.writes, isEmpty);
    });

    testWidgets('CB10 : prix manquant, Figer le coût désactivé', (
      tester,
    ) async {
      await ficheBrassin(tester, enConditionnement(), prices: [pils, s04]);
      await voir(tester, find.text('Coût non figé'));
      expect(find.text('Cascade · 50${nbsp}g'), findsOneWidget);
      expect(find.textContaining('€'), findsNothing);
      await voir(tester, find.text('Figer le coût'));
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Figer le coût'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text('Complétez les éléments ci-dessus pour figer le coût.'),
        findsOneWidget,
      );
    });

    testWidgets('CB10 : Figer le coût au rattrapage, hors ligne', (
      tester,
    ) async {
      final app = await ficheBrassin(tester, enConditionnement());
      app.signIn(brewerUser, member: brewerMember, fromCache: true);
      await tester.pumpAndSettle();
      await voir(tester, find.text('Figer le coût'));
      await tester.tap(find.text('Figer le coût'));
      await tester.pumpAndSettle();
      expect(app.costs.writes.single.kind, 'brew_cost');
      expect(
        find.text('Coût figé sur l\'appareil. Il partira au retour du réseau.'),
        findsOneWidget,
      );
    });

    testWidgets('CB20 : coût figé illisible, Recalculer', (tester) async {
      await ficheBrassin(
        tester,
        enConditionnement(),
        cout: const DocumentIllisibleTrouve<BrewCost>(
          DocumentIllisible('total_eur', 'total négatif'),
        ),
      );
      await voir(tester, find.text('Coût figé illisible.'));
      expect(find.text('Recalculer avec mes prix actuels'), findsOneWidget);
    });

    testWidgets('chargement et panne du coût', (tester) async {
      final app = await ficheBrassin(
        tester,
        enConditionnement(),
        publier: false,
      );
      await voir(tester, find.text('Chargement du coût'));
      app.costs.brewCostOf(uid, 'b1').addError(Exception('refus'));
      await tester.pumpAndSettle();
      expect(find.text('Impossible de lire le coût.'), findsOneWidget);
    });

    testWidgets('texte à 200 %, contraste clair et sombre', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await ficheBrassin(
        tester,
        enConditionnement(bottles: 52),
        cout: DocumentTrouve(coutFige()),
        height: 4000,
      );
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
