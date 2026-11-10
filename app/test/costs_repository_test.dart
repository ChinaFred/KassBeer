import 'dart:io';

import 'package:brewing/brewing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/brews/data/brews_repository.dart';
import 'package:kass_beer/features/brews/domain/brew.dart';
import 'package:kass_beer/features/costs/data/costs_repository.dart';
import 'package:kass_beer/features/costs/data/figeage_embouteillage.dart';
import 'package:kass_beer/features/costs/domain/brew_cost.dart';
import 'package:kass_beer/features/costs/domain/fee.dart';
import 'package:kass_beer/features/costs/domain/price.dart';
import 'package:kass_beer/features/recipes/domain/recipe.dart';

import 'support/brew_fixtures.dart';
import 'support/cost_fakes.dart';
import 'support/fakes.dart';

const _pils = Price(
  key: 'malt-pils',
  name: ' Pils ',
  priceEur: 47.5,
  quantity: 25000,
  unit: CostUnit.gram,
);
const _s04 = Price(
  key: 'levure-s-04',
  name: 'S-04',
  priceEur: 3.99,
  quantity: 1,
  unit: CostUnit.unit,
);
const _electricite = Fee(
  id: 'f-1',
  name: 'Électricité',
  amountEur: 2,
  basis: FeeBasis.perBrew,
);
const _capsules = Fee(
  id: 'f-2',
  name: 'Capsules',
  amountEur: 0.03,
  basis: FeeBasis.perBottle,
);

const _recette = RecipeContent(
  name: 'Blonde',
  batchVolumeL: 20,
  fermentables: [FermentableLine(name: 'Pils', type: 'grain', weightG: 5000)],
  yeasts: [YeastLine(name: 'S-04')],
);

final _cout = BrewCost(
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
  ],
  computedAt: DateTime(2026, 11, 12, 18, 30),
  freezeKind: FreezeKind.initial,
  bottlesCount: 50,
);

ListeLue<T> _lus<T>(Map<String, T> docs) => ListeLue(
  documents: [for (final e in docs.entries) DocumentValide(e.key, e.value)],
  fromCache: false,
);

void main() {
  late FakeFirebaseFirestore firestore;
  late RecordingErrorReportService errors;
  late FirestoreCostsRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    errors = RecordingErrorReportService();
    repository = FirestoreCostsRepository(
      errorReportService: errors,
      firestore: firestore,
    );
  });

  DocumentReference<Map<String, dynamic>> doc(String path) =>
      firestore.doc(path);

  group('prix (PR4, PR8, PR10)', () {
    test('écrit sous la clé, nom sans espaces, unité g', () async {
      await repository.savePrice(uid: 'u', price: _pils);
      final data = (await doc('users/u/prices/malt-pils').get()).data()!;
      expect(data['name'], 'Pils');
      expect(data['price_eur'], 47.5);
      expect(data['quantity'], 25000);
      expect(data['unit'], 'g');
      expect(data.keys.toSet(), {
        'name',
        'price_eur',
        'quantity',
        'unit',
        'updated_at',
      });
    });

    test('même clé : un seul document reste', () async {
      await repository.savePrice(uid: 'u', price: _pils);
      await repository.savePrice(
        uid: 'u',
        price: const Price(
          key: 'malt-pils',
          name: 'pils',
          priceEur: 52,
          quantity: 25000,
          unit: CostUnit.gram,
        ),
      );
      final docs = await firestore.collection('users/u/prices').get();
      expect(docs.docs.length, 1);
      expect(docs.docs.single.data()['price_eur'], 52);
    });

    test('suppression, puis réécriture du même document (Annuler)', () async {
      await repository.savePrice(uid: 'u', price: _pils);
      await repository.deletePrice(uid: 'u', key: 'malt-pils');
      expect((await doc('users/u/prices/malt-pils').get()).exists, isFalse);
      await repository.savePrice(uid: 'u', price: _pils);
      expect((await doc('users/u/prices/malt-pils').get()).exists, isTrue);
    });

    test('lecture : un prix illisible est rapporté sans son prix', () async {
      await doc('users/u/prices/malt-pils').set({
        'name': 'Pils',
        'price_eur': 47.5,
        'quantity': 25000,
        'unit': 'g',
      });
      await doc('users/u/prices/malt-munich').set({
        'name': 'Munich',
        'price_eur': 31.25,
        'quantity': 1000,
        'unit': 'kwh',
      });
      final lus = await repository.watchPrices('u').first;
      expect(lus.valides.single.key, 'malt-pils');
      expect(
        lus.chercher('malt-munich'),
        isA<DocumentIllisibleTrouve<Price>>(),
      );
      final report = errors.reports.single;
      expect(report.feature, 'costs.read');
      expect('${report.error}', isNot(contains('31.25')));
      expect('${report.error}', isNot(contains('kwh')));
    });

    test('S4 : clé hors format, illisible, rapport sans nom ni prix', () async {
      final valide = {
        'name': 'Pils',
        'price_eur': 47.5,
        'quantity': 25000,
        'unit': 'g',
      };
      await doc('users/u/prices/autre-x').set(valide);
      await doc('users/u/prices/malt-Pils').set(valide);
      await doc('users/u/prices/malt-${'a' * 100}').set(valide);
      final lus = await repository.watchPrices('u').first;
      expect(lus.valides, isEmpty);
      expect(lus.documents, hasLength(3));
      for (final id in ['autre-x', 'malt-Pils', 'malt-${'a' * 100}']) {
        expect(lus.chercher(id), isA<DocumentIllisibleTrouve<Price>>());
      }
      expect(errors.reports, hasLength(3));
      for (final r in errors.reports) {
        expect(r.feature, 'costs.read');
        expect('${r.error}', 'DocumentIllisible(id) : clé hors format');
        for (final texte in ['Pils', 'autre', '47.5', 'aaaa']) {
          expect(r.context, isNot(contains(texte)));
        }
      }
    });

    test('un brasseur ne lit que ses prix', () async {
      await repository.savePrice(uid: 'autre', price: _pils);
      final lus = await repository.watchPrices('u').first;
      expect(lus.documents, isEmpty);
    });
  });

  group('frais (FR2)', () {
    test('identifiant créé par l\'appareil, écriture, suppression', () async {
      final id = repository.newFeeId('u');
      expect(id, isNotEmpty);
      await repository.saveFee(
        uid: 'u',
        fee: Fee(
          id: id,
          name: ' Capsules ',
          amountEur: 0.03,
          basis: FeeBasis.perBottle,
        ),
      );
      final data = (await doc('users/u/fees/$id').get()).data()!;
      expect(data['name'], 'Capsules');
      expect(data['basis'], 'per_bottle');
      expect(data.keys.toSet(), {'name', 'amount_eur', 'basis', 'updated_at'});
      final lus = await repository.watchFees('u').first;
      expect(lus.valides.single.basis, FeeBasis.perBottle);
      await repository.deleteFee(uid: 'u', id: id);
      expect((await doc('users/u/fees/$id').get()).exists, isFalse);
    });
  });

  group('coût figé (CB12, HL5)', () {
    test('écrit le document entier, relu tel quel', () async {
      await repository.saveBrewCost(uid: 'u', cost: _cout);
      final data = (await doc('users/u/brew_costs/b1').get()).data()!;
      expect(data['brew_id'], 'b1');
      expect(data['freeze_kind'], 'initial');
      expect(data['computed_at'], isA<Timestamp>());
      final lu = await repository.watchBrewCost(uid: 'u', brewId: 'b1').first;
      expect((lu as DocumentTrouve<BrewCost>).value.totalEur, 40.84);
    });

    test('absent : DocumentAbsent', () async {
      expect(
        await repository.watchBrewCost(uid: 'u', brewId: 'b1').first,
        isA<DocumentAbsent<BrewCost>>(),
      );
    });

    test('illisible : rapporté sans contenu (CB20)', () async {
      await doc('users/u/brew_costs/b1').set({
        'brew_id': 'b1',
        'total_eur': -40.84,
        'lines': <Object>[],
        'computed_at': Timestamp.now(),
        'freeze_kind': 'initial',
      });
      expect(
        await repository.watchBrewCost(uid: 'u', brewId: 'b1').first,
        isA<DocumentIllisibleTrouve<BrewCost>>(),
      );
      expect(errors.reports.single.feature, 'costs.read');
      expect('${errors.reports.single.error}', isNot(contains('40.84')));
    });

    final refus = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    test('premier figeage refusé, coût absent du serveur : annoncé', () async {
      await expectLater(
        repository.ecritureCoutSuivie(
          ref: doc('users/u/brew_costs/b1'),
          kind: FreezeKind.initial,
          write: () async => throw refus,
        ),
        throwsA(same(refus)),
      );
      expect(errors.reports.single.feature, 'costs.freeze_rejected');
    });

    test('premier figeage refusé, coût déjà sur le serveur (rejeu, autre '
        'appareil) : journalisé, jamais annoncé', () async {
      await doc('users/u/brew_costs/b1').set(_cout.toFirestore());
      await repository.ecritureCoutSuivie(
        ref: doc('users/u/brew_costs/b1'),
        kind: FreezeKind.initial,
        write: () async => throw refus,
      );
      expect(errors.reports.single.feature, 'costs.freeze_replayed');
    });

    test('recalcul refusé : annoncé même si un coût existe', () async {
      await doc('users/u/brew_costs/b1').set(_cout.toFirestore());
      await expectLater(
        repository.ecritureCoutSuivie(
          ref: doc('users/u/brew_costs/b1'),
          kind: FreezeKind.recalculation,
          write: () async => throw refus,
        ),
        throwsA(same(refus)),
      );
      expect(errors.reports.single.feature, 'costs.freeze_rejected');
    });
  });

  group('suppression d\'un brassin et de son coût (CB19)', () {
    late FirestoreBrewsRepository brews;

    setUp(() async {
      brews = FirestoreBrewsRepository(
        errorReportService: errors,
        firestore: firestore,
      );
      await doc('brews/b1').set({'owner_uid': 'u'});
      await doc('users/u/brew_costs/b1').set(_cout.toFirestore());
      await doc('users/u/brew_costs/b2').set(_cout.toFirestore());
    });

    test('sans saisie : brassin et coût supprimés, aucun orphelin', () async {
      await brews.delete('b1', ownerUid: 'u');
      expect((await doc('brews/b1').get()).exists, isFalse);
      expect((await doc('users/u/brew_costs/b1').get()).exists, isFalse);
      expect((await doc('users/u/brew_costs/b2').get()).exists, isTrue);
    });

    test('avec saisies : saisies, brassin et coût supprimés', () async {
      await doc('brews/b1/events/e1').set({'kind': 'note'});
      await brews.deleteWithEvents('b1', ownerUid: 'u');
      expect((await doc('brews/b1').get()).exists, isFalse);
      expect((await doc('brews/b1/events/e1').get()).exists, isFalse);
      expect((await doc('users/u/brew_costs/b1').get()).exists, isFalse);
    });

    test('brassin sans coût figé : suppression acceptée', () async {
      await doc('brews/b3').set({'owner_uid': 'u'});
      await brews.delete('b3', ownerUid: 'u');
      expect((await doc('brews/b3').get()).exists, isFalse);
    });
  });

  group('figeage au premier embouteillage (CB3 à CB9)', () {
    late FakeBrewsRepository brews;
    late FakeCostsRepository costs;
    late Set<String> reported;
    final now = DateTime(2026, 11, 12, 18, 30);
    final embouteillage = Embouteillage(
      bottledAt: DateTime(2026, 11, 12),
      bottlesCount: 50,
      packagedVolumeL: 17,
    );

    setUp(() {
      brews = FakeBrewsRepository();
      costs = FakeCostsRepository();
      reported = <String>{};
    });

    EmbouteillageEnvoye envoyer({
      Brew? brew,
      bool modification = false,
      RechercheDocument<BrewCost>? coutLu,
      ListeLue<Price>? prices,
      ListeLue<Fee>? fees,
      Embouteillage? saisie,
    }) => enregistrerEmbouteillage(
      brews: brews,
      costs: costs,
      errors: errors,
      reported: reported,
      brew: brew ?? unBrassin(recipe: _recette, status: BrewStatus.fermenting),
      embouteillage: saisie ?? embouteillage,
      finalGravity: null,
      modification: modification,
      ownerName: 'Bruno',
      prices: prices ?? _lus({'malt-pils': _pils, 'levure-s-04': _s04}),
      fees: fees ?? _lus({'f-1': _electricite, 'f-2': _capsules}),
      coutLu: coutLu,
      now: now,
    );

    test('les deux écritures partent dans l\'ordre, sans attente entre '
        'elles', () {
      final envoye = envoyer();
      // Aucune attente : les deux écritures sont déjà faites au retour.
      expect(brews.writes.single.kind, 'bottling');
      expect(brews.writes.single.detail['status'], BrewStatus.conditioning);
      final ecrit = costs.writes.single;
      expect(ecrit.kind, 'brew_cost');
      expect(ecrit.uid, 'uid-brasseur');
      final cout = ecrit.value! as BrewCost;
      expect(cout.freezeKind, FreezeKind.initial);
      expect(cout.computedAt, now);
      expect(cout.bottlesCount, 50);
      expect(cout.packagedVolumeL, 17);
      expect(cout.totalEur, closeTo(9.5 + 3.99 + 2 + 0.03 * 50, 1e-9));
      expect(envoye.cout, isA<CoutFigeEnvoye>());
    });

    test('modification de l\'embouteillage : aucun coût écrit', () {
      final envoye = envoyer(
        brew: unBrassin(
          recipe: _recette,
          status: BrewStatus.conditioning,
          bottledAt: DateTime(2026, 11, 12),
        ),
        modification: true,
      );
      expect(envoye.cout, isA<FigeageNonDemande>());
      expect(brews.writes.single.detail['status'], isNull);
      expect(costs.writes, isEmpty);
    });

    test('nouvel embouteillage après un retour en arrière : aucun coût '
        'écrit', () {
      final envoye = envoyer(
        brew: unBrassin(
          recipe: _recette,
          status: BrewStatus.fermenting,
          bottledAt: DateTime(2026, 11, 12),
        ),
      );
      expect(envoye.cout, isA<FigeageNonDemande>());
      expect(costs.writes, isEmpty);
    });

    test('coût déjà figé (abandon puis reprise) : inchangé', () {
      final envoye = envoyer(coutLu: DocumentTrouve(_cout));
      expect(envoye.cout, isA<FigeageNonDemande>());
      expect(costs.writes, isEmpty);
    });

    test('prix manquant : l\'embouteillage part, coût non figé', () {
      final envoye = envoyer(prices: _lus({'malt-pils': _pils}));
      expect(brews.writes.single.kind, 'bottling');
      expect(costs.writes, isEmpty);
      expect(envoye.cout, isA<CoutNonFige>());
    });

    test('calcul refusé : l\'embouteillage part, rapport sans montant', () {
      final envoye = envoyer(
        brew: unBrassin(
          status: BrewStatus.fermenting,
          recipe: const RecipeContent(
            name: 'X',
            fermentables: [
              FermentableLine(name: 'Pils', type: 'grain', weightG: -1),
            ],
          ),
        ),
      );
      expect(brews.writes.single.kind, 'bottling');
      expect(costs.writes, isEmpty);
      expect(envoye.cout, isA<CoutNonFige>());
      expect(errors.reports.single.feature, 'costs.freeze_failed');
    });

    test('prix non chargés : l\'embouteillage part, coût non figé (HL4)', () {
      final envoye = enregistrerEmbouteillage(
        brews: brews,
        costs: costs,
        errors: errors,
        reported: reported,
        brew: unBrassin(recipe: _recette, status: BrewStatus.fermenting),
        embouteillage: embouteillage,
        finalGravity: 1.012,
        modification: false,
        ownerName: null,
        prices: null,
        fees: null,
        coutLu: null,
        now: now,
      );
      expect(brews.writes.single.detail['final_gravity'], 1.012);
      expect(envoye.cout, isA<CoutNonFige>());
    });

    test(
      'refus du coût seul : l\'embouteillage reste enregistré (CB7)',
      () async {
        brews.serverAnswer = () async {};
        final refus = Exception('refusé');
        costs.serverAnswer = () async => throw refus;
        final envoye = envoyer();
        final refusDuCout = expectLater(
          (envoye.cout as CoutFigeEnvoye).written,
          throwsA(same(refus)),
        );
        await envoye.embouteillage;
        await refusDuCout;
      },
    );

    test(
      'refus de l\'embouteillage seul : le coût part quand même (CB7)',
      () async {
        final refus = Exception('refusé');
        brews.serverAnswer = () async => throw refus;
        costs.serverAnswer = () async {};
        final envoye = envoyer();
        await expectLater(envoye.embouteillage, throwsA(same(refus)));
        await (envoye.cout as CoutFigeEnvoye).written;
      },
    );

    test('sur Firestore : saveBrewCost hors du lot de saveBottling, aucune '
        'écriture sous users/ par saveBottling', () async {
      final brewsFs = FirestoreBrewsRepository(
        errorReportService: errors,
        firestore: firestore,
      );
      await doc('brews/b1').set({'owner_uid': 'uid-brasseur'});
      final saved = <String>[];
      final envoye = enregistrerEmbouteillage(
        brews: brewsFs,
        costs: repository,
        errors: errors,
        reported: reported,
        brew: unBrassin(recipe: _recette, status: BrewStatus.fermenting),
        embouteillage: embouteillage,
        finalGravity: 1.010,
        modification: false,
        ownerName: 'Bruno',
        prices: _lus({'malt-pils': _pils, 'levure-s-04': _s04}),
        fees: _lus({'f-1': _electricite}),
        coutLu: null,
        now: now,
      );
      await envoye.embouteillage.then((_) => saved.add('bottling'));
      await (envoye.cout as CoutFigeEnvoye).written;
      final brew = (await doc('brews/b1').get()).data()!;
      expect(brew['status'], 'conditioning');
      expect(brew['bottles_count'], 50);
      expect(brew.keys.where((k) => k.contains('cost')), isEmpty);
      final cout = (await doc(
        'users/uid-brasseur/brew_costs/b1',
      ).get()).data()!;
      expect(cout['freeze_kind'], 'initial');
      expect(cout['bottles_count'], 50);
      expect(saved, ['bottling']);
    });
  });

  test('aucune transaction, aucune lecture exigeant le serveur, aucune requête '
      'HTTP dans features/costs (HL1)', () {
    final offenders = <String>[];
    for (final entity in Directory(
      'lib/features/costs',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity.readAsLinesSync().map((l) => l.split('//').first);
      for (final line in code) {
        if (RegExp(
          r'runTransaction|Source\.server|package:http|HttpClient|httpsCallable',
        ).hasMatch(line)) {
          offenders.add('${entity.path} : $line');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('le flux de coût figé suit les changements', () async {
    final valeurs = <RechercheDocument<BrewCost>>[];
    final sub = repository
        .watchBrewCost(uid: 'u', brewId: 'b1')
        .listen(valeurs.add);
    await pumpEventQueue();
    await repository.saveBrewCost(uid: 'u', cost: _cout);
    await pumpEventQueue();
    await sub.cancel();
    expect(valeurs.first, isA<DocumentAbsent<BrewCost>>());
    expect(valeurs.last, isA<DocumentTrouve<BrewCost>>());
  });
}
