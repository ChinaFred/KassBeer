import 'dart:async';

import 'package:kass_beer/core/data/lecture_document.dart';
import 'package:kass_beer/features/costs/data/costs_repository.dart';
import 'package:kass_beer/features/costs/domain/brew_cost.dart';
import 'package:kass_beer/features/costs/domain/fee.dart';
import 'package:kass_beer/features/costs/domain/price.dart';

import 'fakes.dart' show Replay;

/// Écriture reçue par [FakeCostsRepository].
class CostWrite {
  CostWrite(this.kind, this.uid, this.id, [this.value]);

  /// `price`, `price_delete`, `fee`, `fee_delete`, `brew_cost`.
  final String kind;
  final String uid;
  final String id;
  final Object? value;

  @override
  String toString() => 'CostWrite($kind, $uid, $id)';
}

/// Double de [CostsRepository] sans Firebase : flux rejoués, écritures notées.
class FakeCostsRepository implements CostsRepository {
  final _prices = <String, Replay<ListeLue<Price>>>{};
  final _fees = <String, Replay<ListeLue<Fee>>>{};
  final _brewCosts = <String, Replay<RechercheDocument<BrewCost>>>{};
  final writes = <CostWrite>[];
  int _next = 0;

  /// Réponse du serveur à une écriture ; jamais terminée par défaut (hors ligne).
  Future<void> Function() serverAnswer = () => Completer<void>().future;

  Replay<ListeLue<Price>> pricesOf(String uid) =>
      _prices.putIfAbsent(uid, Replay.new);

  Replay<ListeLue<Fee>> feesOf(String uid) =>
      _fees.putIfAbsent(uid, Replay.new);

  Replay<RechercheDocument<BrewCost>> brewCostOf(String uid, String brewId) =>
      _brewCosts.putIfAbsent('$uid/$brewId', Replay.new);

  void publishPrices(
    String uid,
    List<Price> prices, {
    bool fromCache = false,
  }) => pricesOf(uid).add(
    ListeLue(
      documents: [for (final p in prices) DocumentValide(p.key, p)],
      fromCache: fromCache,
    ),
  );

  void publishFees(String uid, List<Fee> fees, {bool fromCache = false}) =>
      feesOf(uid).add(
        ListeLue(
          documents: [for (final f in fees) DocumentValide(f.id, f)],
          fromCache: fromCache,
        ),
      );

  @override
  Stream<ListeLue<Price>> watchPrices(String uid) => pricesOf(uid).stream;

  @override
  Stream<ListeLue<Fee>> watchFees(String uid) => feesOf(uid).stream;

  @override
  Stream<RechercheDocument<BrewCost>> watchBrewCost({
    required String uid,
    required String brewId,
  }) => brewCostOf(uid, brewId).stream;

  @override
  Future<void> savePrice({required String uid, required Price price}) {
    writes.add(CostWrite('price', uid, price.key, price));
    return serverAnswer();
  }

  @override
  Future<void> deletePrice({required String uid, required String key}) {
    writes.add(CostWrite('price_delete', uid, key));
    return serverAnswer();
  }

  @override
  String newFeeId(String uid) => 'fee-${_next++}';

  @override
  Future<void> saveFee({required String uid, required Fee fee}) {
    writes.add(CostWrite('fee', uid, fee.id, fee));
    return serverAnswer();
  }

  @override
  Future<void> deleteFee({required String uid, required String id}) {
    writes.add(CostWrite('fee_delete', uid, id));
    return serverAnswer();
  }

  @override
  Future<void> saveBrewCost({required String uid, required BrewCost cost}) {
    writes.add(CostWrite('brew_cost', uid, cost.brewId, cost));
    return serverAnswer();
  }
}
