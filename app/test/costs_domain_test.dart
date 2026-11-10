import 'dart:convert';
import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/core/services/error_report_service.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/costs/domain/brew_cost.dart';
import 'package:kass_beer/features/costs/domain/cost_evaluation.dart';
import 'package:kass_beer/features/costs/domain/fee.dart';
import 'package:kass_beer/features/costs/domain/price.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';

/// Rapports reçus, contexte compris (TE6).
class _Rapports extends ErrorReportService {
  final reports = <({String feature, Object error, String? context})>[];

  @override
  void reportError({
    required String feature,
    required Object error,
    StackTrace? stackTrace,
    String? context,
  }) {
    reports.add((feature: feature, error: error, context: context));
  }
}

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

ListeLue<Price> prixLus(
  List<Price> prices, {
  bool fromCache = false,
  List<String> illisibles = const [],
}) => ListeLue(
  documents: [
    for (final p in prices) DocumentValide(p.key, p),
    for (final id in illisibles)
      DocumentInvalide<Price>(
        id,
        const DocumentIllisible('unit', 'unité d\'achat inconnue'),
      ),
  ],
  fromCache: fromCache,
);

ListeLue<Fee> fraisLus(
  List<Fee> fees, {
  bool fromCache = false,
  bool illisible = false,
}) => ListeLue(
  documents: [
    for (final f in fees) DocumentValide(f.id, f),
    if (illisible)
      const DocumentInvalide<Fee>('f-x', DocumentIllisible('basis', 'base')),
  ],
  fromCache: fromCache,
);

const electricite = Fee(
  id: 'f-1',
  name: 'Électricité',
  amountEur: 2,
  basis: FeeBasis.perBrew,
);
const capsules = Fee(
  id: 'f-2',
  name: 'Capsules',
  amountEur: 0.2122,
  basis: FeeBasis.perBottle,
);

final pils = prix(IngredientNature.malt, 'Pils', 47.5, 25000);
final cascade = prix(IngredientNature.hop, 'Cascade', 4.5, 100);
final s04 = prix(IngredientNature.yeast, 'S-04', 3.99, 1);

const pils5kg = FermentableLine(
  name: 'Pils',
  kind: FermentableKind.malt,
  weightG: 5000,
);
HopLine houblon(String name, double grams) =>
    HopLine(name: name, weightG: grams, use: HopUse.boil, form: HopForm.pellet);
const s04Line = YeastLine(name: 'S-04');

const recette = RecipeContent(
  name: 'Blonde',
  batchVolumeL: 20,
  fermentables: [pils5kg],
  yeasts: [s04Line],
);

void main() {
  late _Rapports errors;
  late Set<String> reported;

  setUp(() {
    errors = _Rapports();
    reported = <String>{};
  });

  EvaluationCout recetteAvec(
    RecipeContent content, {
    ListeLue<Price>? prices,
    ListeLue<Fee>? fees,
    String reportKey = 'r1',
  }) => evaluerCoutRecette(
    content,
    prices: prices,
    fees: fees,
    errors: errors,
    reported: reported,
    reportKey: reportKey,
  );

  EvaluationFigeage figer({
    RecipeContent content = recette,
    int? bottles = 50,
    double? volume = 17,
    double? primingG,
    String? primingName,
    ListeLue<Price>? prices,
    ListeLue<Fee>? fees,
    bool sansFraisParBouteille = false,
  }) => evaluerFigeage(
    brewId: 'b1',
    recipe: content,
    bottlesCount: bottles,
    packagedVolumeL: volume,
    primingSugarG: primingG,
    primingSugarName: primingName,
    prices: prices ?? prixLus([pils, s04]),
    fees: fees ?? fraisLus([electricite, capsules]),
    kind: FreezeKind.initial,
    now: DateTime(2026, 11, 12, 18, 30),
    sansFraisParBouteille: sansFraisParBouteille,
    errors: errors,
    reported: reported,
  );

  group('clé dérivée du nom (LI1)', () {
    test('une ligne construite sans clé a son prix', () {
      final cout =
          recetteAvec(recette, prices: prixLus([pils, s04]), fees: fraisLus([]))
              as CoutObtenu;
      expect(cout.lignes.first.key, 'malt-pils');
      expect(cout.lignes.first.costEur, closeTo(9.5, 1e-9));
      expect(cout.totalEur, closeTo(13.49, 1e-9));
    });

    test('une ligne stockée sans champ key a son prix', () {
      final content = RecipeContent.fromFirestore({
        'name': 'Blonde',
        'batch_volume_l': 20,
        'fermentables': [
          {'name': 'Pils', 'kind': 'grain', 'weight_g': 5000},
        ],
      });
      final cout =
          recetteAvec(content, prices: prixLus([pils]), fees: fraisLus([]))
              as CoutObtenu;
      expect(cout.totalEur, closeTo(9.5, 1e-9));
    });

    test('une clé stockée différente du nom est ignorée', () {
      final content = RecipeContent.fromFirestore({
        'name': 'Blonde',
        'batch_volume_l': 20,
        'fermentables': [
          {
            'key': 'malt-autre-chose',
            'name': 'Pils',
            'kind': 'grain',
            'weight_g': 5000,
          },
        ],
      });
      expect(
        recetteAvec(content, prices: prixLus([pils]), fees: fraisLus([])),
        isA<CoutObtenu>(),
      );
    });
  });

  group('regroupement et levure (LI2, LI3)', () {
    test('Cascade 20 g et 30 g : une ligne de 50 g à 2,25 €', () {
      final content = RecipeContent(
        name: 'H',
        batchVolumeL: 20,
        hops: [houblon('Cascade', 20), houblon('cascade', 30)],
      );
      final cout =
          recetteAvec(content, prices: prixLus([cascade]), fees: fraisLus([]))
              as CoutObtenu;
      expect(cout.lignes.single.name, 'Cascade');
      expect(cout.lignes.single.quantity, 50);
      expect(cout.lignes.single.costEur, closeTo(2.25, 1e-9));
    });

    test('Cascade sans prix est nommé une fois, avec 50 g', () {
      final content = RecipeContent(
        name: 'H',
        batchVolumeL: 20,
        hops: [houblon('Cascade', 20), houblon('Cascade', 30)],
      );
      final cout =
          recetteAvec(content, prices: prixLus([]), fees: fraisLus([]))
              as CoutIndisponible;
      final manquant = cout.raisons.single as PrixManquant;
      expect(manquant.ingredient.name, 'Cascade');
      expect(manquant.ingredient.quantity, 50);
      expect(cout.prixManquants, 1);
    });

    test('une levure compte pour un sachet ; lot de 5 divisé', () {
      final lot = prix(IngredientNature.yeast, 'S-04', 19.95, 5);
      final cout =
          recetteAvec(
                const RecipeContent(
                  name: 'L',
                  batchVolumeL: 20,
                  yeasts: [s04Line],
                ),
                prices: prixLus([lot]),
                fees: fraisLus([]),
              )
              as CoutObtenu;
      final ligne = cout.lignes.single;
      expect(ligne.quantity, 1);
      expect(ligne.unit, CostUnit.unit);
      expect(ligne.costEur, closeTo(3.99, 1e-9));
    });

    test('même nom, nature différente : deux clés', () {
      final content = RecipeContent(
        name: 'N',
        batchVolumeL: 20,
        fermentables: const [pils5kg],
        others: const [OtherLine(name: 'Pils', weightG: 10)],
      );
      final cout =
          recetteAvec(content, prices: prixLus([pils]), fees: fraisLus([]))
              as CoutIndisponible;
      expect(
        (cout.raisons.single as PrixManquant).ingredient.key,
        'ajout-pils',
      );
    });
  });

  group('coût d\'une recette (CR)', () {
    test('total, par litre, bouteille de 33 cl ; frais par bouteille estimés '
        '(CR1 à CR3)', () {
      final cout =
          recetteAvec(
                recette,
                prices: prixLus([pils, s04]),
                fees: fraisLus([electricite, capsules]),
              )
              as CoutObtenu;
      final bouteilles = 20 / 0.33;
      expect(cout.bouteilles, closeTo(bouteilles, 1e-9));
      expect(cout.bouteillesEstimees, isTrue);
      final total = 9.5 + 3.99 + 2 + 0.2122 * bouteilles;
      expect(cout.totalEur, closeTo(total, 1e-9));
      expect(cout.perLitreEur, closeTo(total / 20, 1e-9));
      expect(cout.perBottle33clEur, closeTo(total / 20 * 0.33, 1e-9));
      expect(cout.perBottleEur, isNull);
      expect(cout.aucunFrais, isFalse);
      final frais = cout.lignes
          .where((l) => l.key.startsWith('frais-'))
          .toList();
      expect(frais.map((l) => l.key), ['frais-f-1', 'frais-f-2']);
      expect(frais.last.unit, CostUnit.bottle);
    });

    test('un prix manquant : aucun montant, la liste (CR4, Twin bottle 4)', () {
      final content = RecipeContent(
        name: 'Twin bottle 4',
        batchVolumeL: 20,
        fermentables: const [
          FermentableLine(
            name: 'Munich (17.7 EBC)',
            kind: FermentableKind.malt,
            weightG: 400,
          ),
          FermentableLine(
            name: 'Wheat',
            kind: FermentableKind.malt,
            weightG: 700,
          ),
        ],
        hops: [houblon('Cascade', 15.5)],
      );
      final cout =
          recetteAvec(
                content,
                prices: prixLus([
                  prix(IngredientNature.malt, 'Munich (17.7 EBC)', 0.86, 400),
                  cascade,
                ]),
                fees: fraisLus([electricite]),
              )
              as CoutIndisponible;
      expect(
        [
          for (final r in cout.raisons.whereType<RaisonPrix>())
            r.ingredient.name,
        ],
        ['Wheat'],
      );
      expect(cout.raisons.length, 1);
    });

    test('volume non renseigné (CR5)', () {
      final cout =
          recetteAvec(
                const RecipeContent(name: 'V', fermentables: [pils5kg]),
                prices: prixLus([pils]),
                fees: fraisLus([capsules]),
              )
              as CoutIndisponible;
      expect(cout.raisons, [isA<VolumeNonRenseigne>()]);
    });

    test('aucun ingrédient : jamais 0,00 € (CR6)', () {
      final cout =
          recetteAvec(
                const RecipeContent(name: 'Vide', batchVolumeL: 20),
                prices: prixLus([]),
                fees: fraisLus([electricite]),
              )
              as CoutIndisponible;
      expect(cout.raisons, [isA<AucunIngredient>()]);
    });

    test('recette d\'un autre, prix du lecteur : deux montants (CR7)', () {
      final a =
          recetteAvec(recette, prices: prixLus([pils, s04]), fees: fraisLus([]))
              as CoutObtenu;
      final b =
          recetteAvec(
                recette,
                prices: prixLus([
                  prix(IngredientNature.malt, 'Pils', 60, 25000),
                  s04,
                ]),
                fees: fraisLus([]),
              )
              as CoutObtenu;
      expect(a.totalEur, isNot(closeTo(b.totalEur, 0.01)));
    });

    test('valeur refusée : calcul impossible, rapporté une fois sans montant '
        '(CR9, SE4, TE6)', () {
      const negatif = RecipeContent(
        name: 'Négatif',
        batchVolumeL: 20,
        fermentables: [
          FermentableLine(
            name: 'Pils',
            kind: FermentableKind.malt,
            weightG: -4321,
          ),
        ],
      );
      for (var i = 0; i < 2; i++) {
        final cout =
            recetteAvec(negatif, prices: prixLus([pils]), fees: fraisLus([]))
                as CoutIndisponible;
        expect(cout.raisons, [isA<CalculImpossible>()]);
      }
      final report = errors.reports.single;
      expect(report.feature, 'costs.calculation');
      expect(report.error, isA<CalculCoutRefuse>());
      final texte = '${report.error} ${report.context}';
      expect(texte, isNot(contains('4321')));
      expect(texte, isNot(contains('47.5')));
      expect(texte, isNot(contains('Pils')));
    });

    test('aucun frais : montant et mention (FR5)', () {
      final cout =
          recetteAvec(recette, prices: prixLus([pils, s04]), fees: fraisLus([]))
              as CoutObtenu;
      expect(cout.aucunFrais, isTrue);
    });
  });

  group('raisons (LI8 à LI10, HL4)', () {
    test('unité du prix incompatible (LI8)', () {
      final enGrammes = prix(
        IngredientNature.yeast,
        'S-04',
        3.99,
        11.5,
        unit: CostUnit.gram,
      );
      final cout =
          recetteAvec(
                recette,
                prices: prixLus([pils, enGrammes]),
                fees: fraisLus([]),
              )
              as CoutIndisponible;
      final raison = cout.raisons.single as PrixUniteIncompatible;
      expect(raison.ingredient.key, 'levure-s-04');
      expect(raison.price, same(enGrammes));
      expect(cout.prixManquants, 1);
    });

    test('prix illisible (LI9)', () {
      final cout =
          recetteAvec(
                recette,
                prices: prixLus([pils], illisibles: ['levure-s-04']),
                fees: fraisLus([]),
              )
              as CoutIndisponible;
      expect(cout.raisons, [isA<PrixIllisible>()]);
    });

    test('ligne sans nom utilisable : aucun montant, aucun rapport (LI10)', () {
      final cout =
          recetteAvec(
                const RecipeContent(
                  name: 'Import',
                  batchVolumeL: 20,
                  fermentables: [
                    pils5kg,
                    FermentableLine(
                      name: '---',
                      kind: FermentableKind.malt,
                      weightG: 100,
                    ),
                  ],
                ),
                prices: prixLus([pils]),
                fees: fraisLus([]),
              )
              as CoutIndisponible;
      expect(cout.raisons, [isA<LigneSansNom>()]);
      expect(errors.reports, isEmpty);
    });

    test('hors ligne : clé absente du cache, jamais « manquant » (HL4)', () {
      final cout =
          recetteAvec(
                recette,
                prices: prixLus([pils], fromCache: true),
                fees: fraisLus([electricite], fromCache: true),
              )
              as CoutIndisponible;
      expect(cout.raisons, [isA<PrixIndisponiblesHorsLigne>()]);
      expect(cout.prixManquants, 0);
    });

    test('hors ligne : liste de frais vide lue du cache (HL4)', () {
      final cout =
          recetteAvec(
                recette,
                prices: prixLus([pils, s04]),
                fees: fraisLus([], fromCache: true),
              )
              as CoutIndisponible;
      expect(cout.raisons, [isA<PrixIndisponiblesHorsLigne>()]);
    });

    test('prix présent dans le cache : il sert (HL4)', () {
      expect(
        recetteAvec(
          recette,
          prices: prixLus([pils, s04], fromCache: true),
          fees: fraisLus([electricite], fromCache: true),
        ),
        isA<CoutObtenu>(),
      );
    });

    test('prix ou frais non chargés', () {
      expect(
        (recetteAvec(recette, prices: null, fees: fraisLus([]))
                as CoutIndisponible)
            .raisons,
        [isA<PrixIndisponiblesHorsLigne>()],
      );
      expect(
        (recetteAvec(recette, prices: prixLus([pils, s04]), fees: null)
                as CoutIndisponible)
            .raisons,
        [isA<PrixIndisponiblesHorsLigne>()],
      );
    });

    test('frais illisible : aucun montant', () {
      final cout =
          recetteAvec(
                recette,
                prices: prixLus([pils, s04]),
                fees: fraisLus([electricite], illisible: true),
              )
              as CoutIndisponible;
      expect(cout.raisons, [isA<FraisIllisible>()]);
    });
  });

  group('estimation d\'un brassin (CB2)', () {
    test('nombre de bouteilles du brassin', () {
      final brew = unBrassin(recipe: recette, bottlesCount: 50);
      final cout =
          evaluerEstimationBrassin(
                brew,
                prices: prixLus([pils, s04]),
                fees: fraisLus([electricite, capsules]),
                errors: errors,
                reported: reported,
              )
              as CoutObtenu;
      expect(cout.bouteilles, 50);
      expect(cout.bouteillesEstimees, isFalse);
      expect(cout.totalEur, closeTo(9.5 + 3.99 + 2 + 0.2122 * 50, 1e-9));
      expect(cout.perBottleEur, closeTo(cout.totalEur / 50, 1e-9));
    });

    test('sans nombre de bouteilles : volume de la copie / 0,33', () {
      final cout =
          evaluerEstimationBrassin(
                unBrassin(recipe: recette),
                prices: prixLus([pils, s04]),
                fees: fraisLus([capsules]),
                errors: errors,
                reported: reported,
              )
              as CoutObtenu;
      expect(cout.bouteilles, closeTo(20 / 0.33, 1e-9));
      expect(cout.bouteillesEstimees, isTrue);
    });
  });

  group('figeage (CB4, CB8)', () {
    test('tout est connu : document complet', () {
      final f = figer(primingG: 120, primingName: 'Saccharose');
      expect(f, isA<FigeageImpossible>());
      final avecSucre = figer(
        primingG: 120,
        primingName: 'Saccharose',
        prices: prixLus([
          pils,
          s04,
          prix(IngredientNature.sugar, 'Saccharose', 1.2, 1000),
        ]),
      );
      final cout = (avecSucre as FigeagePossible).cout;
      expect(cout.brewId, 'b1');
      expect(cout.freezeKind, FreezeKind.initial);
      expect(cout.computedAt, DateTime(2026, 11, 12, 18, 30));
      expect(cout.bottlesCount, 50);
      expect(cout.packagedVolumeL, 17);
      expect(cout.primingSugarG, 120);
      expect(cout.primingSugarName, 'Saccharose');
      expect(cout.lines.map((l) => l.key), [
        'malt-pils',
        'levure-s-04',
        'sucre-saccharose',
        'frais-f-1',
        'frais-f-2',
      ]);
      final total = 9.5 + 3.99 + 0.144 + 2 + 0.2122 * 50;
      expect(cout.totalEur, closeTo(total, 1e-9));
      expect(cout.perBottleEur, closeTo(total / 50, 1e-9));
      expect(cout.perLitreEur, closeTo(total / 17, 1e-9));
    });

    test('sucre de resucrage regroupé avec le sucre de même nom', () {
      const content = RecipeContent(
        name: 'S',
        fermentables: [
          FermentableLine(
            name: 'Saccharose',
            kind: FermentableKind.sugar,
            weightG: 200,
          ),
        ],
      );
      final f = figer(
        content: content,
        primingG: 120,
        primingName: 'saccharose',
        prices: prixLus([
          prix(IngredientNature.sugar, 'Saccharose', 1.2, 1000),
        ]),
        fees: fraisLus([]),
      );
      final ligne = (f as FigeagePossible).cout.lines.single;
      expect(ligne.quantity, 320);
    });

    test('prix manquant (LI7)', () {
      final f = figer(prices: prixLus([pils])) as FigeageImpossible;
      expect(f.raisons, [isA<PrixManquant>()]);
      expect(f.seulementBouteilles, isFalse);
    });

    test('ligne sans nom utilisable (LI10)', () {
      final f =
          figer(
                content: const RecipeContent(
                  name: 'X',
                  fermentables: [pils5kg],
                  yeasts: [YeastLine(name: '???')],
                ),
                prices: prixLus([pils]),
              )
              as FigeageImpossible;
      expect(f.raisons, [isA<LigneSansNom>()]);
    });

    test('calcul refusé : rapporté sans montant (costs.freeze_failed)', () {
      final f =
          figer(
                content: const RecipeContent(
                  name: 'X',
                  fermentables: [
                    FermentableLine(
                      name: 'Pils',
                      kind: FermentableKind.malt,
                      weightG: double.nan,
                    ),
                  ],
                ),
              )
              as FigeageImpossible;
      expect(f.raisons, [isA<CalculImpossible>()]);
      final report = errors.reports.single;
      expect(report.feature, 'costs.freeze_failed');
      expect('${report.error}', 'CalculCoutRefuse(BrewingInputException)');
    });

    test('prix non chargés ou absents du cache (HL4)', () {
      final f =
          evaluerFigeage(
                brewId: 'b1',
                recipe: recette,
                bottlesCount: 50,
                packagedVolumeL: 17,
                primingSugarG: null,
                primingSugarName: null,
                prices: null,
                fees: null,
                kind: FreezeKind.initial,
                now: DateTime(2026),
                errors: errors,
                reported: reported,
              )
              as FigeageImpossible;
      expect(f.raisons, [isA<PrixIndisponiblesHorsLigne>()]);
    });

    test('masse de resucrage sans nature', () {
      final f = figer(primingG: 120) as FigeageImpossible;
      expect(f.raisons, [isA<SucreResucrageSansNature>()]);
    });

    test('nature de sucre sans masse : aucune ligne, le figeage continue', () {
      final f = figer(primingG: 0, primingName: 'Saccharose');
      expect(
        (f as FigeagePossible).cout.lines.map((l) => l.key),
        isNot(contains('sucre-saccharose')),
      );
    });

    test(
      'sans nombre de bouteilles, avec un frais par bouteille : à rattraper, '
      'ou figé sans ce frais après confirmation (CB11)',
      () {
        final f = figer(bottles: null) as FigeageImpossible;
        expect(f.raisons, [isA<BouteillesNonRenseignees>()]);
        expect(f.seulementBouteilles, isTrue);
        final confirme = figer(bottles: null, sansFraisParBouteille: true);
        final cout = (confirme as FigeagePossible).cout;
        expect(cout.lines.map((l) => l.key), isNot(contains('frais-f-2')));
        expect(cout.perBottleEur, isNull);
      },
    );

    test('sans nombre de bouteilles ni frais par bouteille : figé', () {
      expect(
        figer(bottles: null, fees: fraisLus([electricite])),
        isA<FigeagePossible>(),
      );
    });

    test(
      'sans volume conditionné : total figé, sans prix par litre (CB14)',
      () {
        final cout = (figer(volume: null) as FigeagePossible).cout;
        expect(cout.packagedVolumeL, isNull);
        expect(cout.perLitreEur, isNull);
      },
    );

    test('rattrapage sur le brassin enregistré', () {
      final brew = unBrassin(
        recipe: recette,
        status: BrewStatus.conditioning,
        bottlesCount: 50,
      );
      final f = evaluerFigeageDuBrassin(
        brew,
        prices: prixLus([pils, s04]),
        fees: fraisLus([electricite, capsules]),
        kind: FreezeKind.recalculation,
        now: DateTime(2026, 11, 20),
        errors: errors,
        reported: reported,
      );
      final cout = (f as FigeagePossible).cout;
      expect(cout.freezeKind, FreezeKind.recalculation);
      expect(cout.bottlesCount, 50);
    });
  });

  group('déclencheur du figeage automatique (CB3)', () {
    final avant = DateTime(2026, 11, 1);
    test('premier embouteillage, aucun coût lu : vrai', () {
      for (final lu in <RechercheDocument<BrewCost>?>[
        null,
        const DocumentAbsent(),
        const DocumentAbsentDuCache(),
      ]) {
        expect(
          doitFigerAuPremierEmbouteillage(
            modification: false,
            bottledAtAvant: null,
            coutLu: lu,
          ),
          isTrue,
        );
      }
    });

    test('modification de l\'embouteillage : faux', () {
      expect(
        doitFigerAuPremierEmbouteillage(
          modification: true,
          bottledAtAvant: null,
          coutLu: null,
        ),
        isFalse,
      );
    });

    test('bottled_at déjà posé (retour en arrière puis nouvel embouteillage) : '
        'faux', () {
      expect(
        doitFigerAuPremierEmbouteillage(
          modification: false,
          bottledAtAvant: avant,
          coutLu: null,
        ),
        isFalse,
      );
    });

    test('coût déjà lu, lisible ou non : faux', () {
      final cout = BrewCost(
        brewId: 'b1',
        totalEur: 40.84,
        lines: const [],
        computedAt: avant,
        freezeKind: FreezeKind.initial,
      );
      for (final lu in <RechercheDocument<BrewCost>>[
        DocumentTrouve(cout),
        const DocumentIllisibleTrouve('illisible'),
      ]) {
        expect(
          doitFigerAuPremierEmbouteillage(
            modification: false,
            bottledAtAvant: null,
            coutLu: lu,
          ),
          isFalse,
        );
      }
    });
  });

  group('rattrapage et recalcul proposés (CB10, CB16, CB1)', () {
    final cout = BrewCost(
      brewId: 'b1',
      totalEur: 40.84,
      lines: const [],
      computedAt: DateTime(2026, 11, 12),
      freezeKind: FreezeKind.initial,
    );

    test(
      '« Figer le coût » : propriétaire, statut de rattrapage, aucun coût',
      () {
        for (final status in BrewStatus.values) {
          expect(
            figerLeCoutPropose(
              brew: unBrassin(status: status),
              readerUid: 'uid-brasseur',
              coutLu: const DocumentAbsent(),
            ),
            kStatutsDeRattrapage.contains(status),
            reason: status.name,
          );
        }
        final brew = unBrassin(status: BrewStatus.done);
        expect(
          figerLeCoutPropose(
            brew: brew,
            readerUid: 'uid-autre',
            coutLu: const DocumentAbsent(),
          ),
          isFalse,
        );
        expect(
          figerLeCoutPropose(
            brew: brew,
            readerUid: 'uid-brasseur',
            coutLu: DocumentTrouve(cout),
          ),
          isFalse,
        );
        expect(
          figerLeCoutPropose(
            brew: brew,
            readerUid: 'uid-brasseur',
            coutLu: null,
          ),
          isFalse,
        );
      },
    );

    test('« Recalculer » : propriétaire et coût figé, même illisible', () {
      final brew = unBrassin(status: BrewStatus.done);
      expect(
        recalculerPropose(
          brew: brew,
          readerUid: 'uid-brasseur',
          coutLu: DocumentTrouve(cout),
        ),
        isTrue,
      );
      expect(
        recalculerPropose(
          brew: brew,
          readerUid: 'uid-brasseur',
          coutLu: const DocumentIllisibleTrouve('x'),
        ),
        isTrue,
      );
      expect(
        recalculerPropose(
          brew: brew,
          readerUid: 'uid-admin',
          coutLu: DocumentTrouve(cout),
        ),
        isFalse,
      );
    });
  });

  group('écart avec l\'embouteillage (CB15)', () {
    final cout = BrewCost(
      brewId: 'b1',
      totalEur: 40.84,
      lines: const [],
      computedAt: DateTime(2026, 11, 12),
      freezeKind: FreezeKind.initial,
      bottlesCount: 50,
    );

    test('Bouteilles 50 → 52', () {
      final ecarts = ecartsDepuisFigeage(
        cout,
        unBrassin(bottlesCount: 52, bottledAt: DateTime(2026, 11, 12)),
      );
      expect(ecarts.single.champ, ChampEmbouteillage.bouteilles);
      expect(ecarts.single.figee, 50);
      expect(ecarts.single.actuelle, 52);
    });

    test('date seule changée : aucun écart', () {
      expect(
        ecartsDepuisFigeage(
          cout,
          unBrassin(bottlesCount: 50, bottledAt: DateTime(2026, 11, 14)),
        ),
        isEmpty,
      );
    });
  });

  group('documents', () {
    test('coût figé : écriture puis lecture', () {
      final cout = BrewCost(
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
            key: 'frais-f-2',
            name: 'Capsules',
            quantity: 50,
            unit: CostUnit.bottle,
            costEur: 1.5,
          ),
        ],
        computedAt: DateTime(2026, 11, 12, 18, 30),
        freezeKind: FreezeKind.initial,
        bottlesCount: 50,
        packagedVolumeL: 17,
      );
      final data = cout.toFirestore();
      expect(data.containsKey('priming_sugar_g'), isFalse);
      expect(data['freeze_kind'], 'initial');
      final lu = BrewCost.fromFirestore('b1', data);
      expect(lu.totalEur, 40.84);
      expect(lu.lines.last.unit, CostUnit.bottle);
      expect(lu.perBottleEur, closeTo(0.8168, 1e-9));
      expect(lu.computedAt, DateTime(2026, 11, 12, 18, 30));
    });

    test('coût figé illisible sans valeur dans l\'erreur (CB20)', () {
      final data = BrewCost(
        brewId: 'b1',
        totalEur: 40.84,
        lines: const [],
        computedAt: DateTime(2026),
        freezeKind: FreezeKind.initial,
      ).toFirestore();
      for (final bad in [
        {...data, 'freeze_kind': 'manual'},
        {...data, 'total_eur': -40.84},
        {...data, 'bottles_count': 1.5},
        {...data}..remove('computed_at'),
      ]) {
        expect(
          () => BrewCost.fromFirestore('b1', bad),
          throwsA(
            isA<DocumentIllisible>().having(
              (e) => e.toString(),
              'toString',
              isNot(contains('40.84')),
            ),
          ),
        );
      }
    });

    test('prix : unités l et kwh illisibles, sans valeur dans l\'erreur', () {
      for (final unit in ['l', 'kwh', 'kg']) {
        expect(
          () => Price.fromFirestore('malt-pils', {
            'name': 'Pils',
            'price_eur': 47.5,
            'quantity': 25000,
            'unit': unit,
          }),
          throwsA(
            isA<DocumentIllisible>().having(
              (e) => e.toString(),
              'toString',
              isNot(contains(unit == 'l' ? '= l' : unit)),
            ),
          ),
        );
      }
      expect(
        () => Price.fromFirestore('malt-pils', {
          'name': 'Pils',
          'price_eur': -1,
          'quantity': 25000,
          'unit': 'g',
        }),
        throwsA(isA<DocumentIllisible>()),
      );
      final p = Price.fromFirestore('malt-pils', {
        'name': 'Pils',
        'price_eur': 47.5,
        'quantity': 25000,
        'unit': 'g',
      });
      expect(p.nature, IngredientNature.malt);
      expect(p.unitPriceEur, closeTo(0.0019, 1e-12));
      expect(p.toFirestore()['unit'], 'g');
    });

    test('frais : base inconnue illisible', () {
      expect(
        () => Fee.fromFirestore('f-1', {
          'name': 'Eau',
          'amount_eur': 1.66,
          'basis': 'per_litre',
        }),
        throwsA(isA<DocumentIllisible>()),
      );
      final fee = Fee.fromFirestore('f-1', {
        'name': 'Eau',
        'amount_eur': 1.66,
        'basis': 'per_brew',
      });
      expect(fee.basis, FeeBasis.perBrew);
      expect(fee.lineKey, 'frais-f-1');
    });
  });

  test('prix inhabituel (PR6)', () {
    final normal = unitPrice(priceEur: 47.5, quantity: 25000);
    final erreur = unitPrice(priceEur: 47.5, quantity: 25);
    expect(isUnusualPrice(IngredientNature.malt, normal), isFalse);
    expect(isUnusualPrice(IngredientNature.malt, erreur), isTrue);
    expect(isUnusualPrice(IngredientNature.hop, 0.045), isFalse);
    expect(isUnusualPrice(IngredientNature.hop, 0.6), isTrue);
    expect(isUnusualPrice(IngredientNature.yeast, 3.99), isFalse);
    expect(isUnusualPrice(IngredientNature.yeast, 60), isTrue);
  });

  test('coût des fiches retrouvé par l\'application (FIN2)', () {
    final fixture =
        jsonDecode(
              File('../brewing/test/fixtures/cost.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases =
        ((fixture['brew_cases'] as Map<String, dynamic>)['cases']
                as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .where((c) => c['bottles'] != null);
    expect(cases.length, 2);
    for (final c in cases) {
      final fermentables = <FermentableLine>[];
      final hops = <HopLine>[];
      final others = <OtherLine>[];
      final yeasts = <YeastLine>[];
      final prices = <Price>[];
      for (final m
          in (c['ingredients'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final name = m['name'] as String;
        final quantity = (m['quantity'] as num).toDouble();
        final nature = IngredientNature.values.firstWhere(
          (n) => n.prefix == m['nature'],
        );
        switch (nature) {
          case IngredientNature.malt:
            fermentables.add(
              FermentableLine(
                name: name,
                kind: FermentableKind.malt,
                weightG: quantity,
              ),
            );
          case IngredientNature.hop:
            hops.add(houblon(name, quantity));
          case IngredientNature.addition:
            others.add(OtherLine(name: name, weightG: quantity));
          case IngredientNature.yeast:
            yeasts.add(YeastLine(name: name));
          case IngredientNature.sugar:
            fail('aucun sucre dans ces fiches');
        }
        prices.add(prix(nature, name, (m['unit_price'] as num).toDouble(), 1));
      }
      final fees = [
        for (final (i, f)
            in (c['fees'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .indexed)
          Fee(
            id: 'f$i',
            name: f['name'] as String,
            amountEur: (f['amount_eur'] as num).toDouble(),
            basis: FeeBasis.values.firstWhere(
              (b) => b.storedValue == f['basis'],
            ),
          ),
      ];
      final f = figer(
        content: RecipeContent(
          name: c['id'] as String,
          fermentables: fermentables,
          hops: hops,
          others: others,
          yeasts: yeasts,
        ),
        bottles: c['bottles'] as int,
        volume: (c['volume_litres'] as num).toDouble(),
        prices: prixLus(prices),
        fees: fraisLus(fees),
      );
      final cout = (f as FigeagePossible).cout;
      final expected = c['expected'] as Map<String, dynamic>;
      final fiche = c['fiche_value'] as Map<String, dynamic>;
      expect(
        cout.totalEur,
        closeTo((expected['total'] as num).toDouble(), 0.0001),
        reason: c['id'] as String,
      );
      expect(
        cout.totalEur,
        closeTo((fiche['total'] as num).toDouble(), 0.05),
        reason: c['id'] as String,
      );
      expect(
        cout.perBottleEur,
        closeTo((expected['per_bottle'] as num).toDouble(), 0.0001),
      );
    }
  });
}
