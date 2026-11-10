import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../domain/brew_cost.dart';
import '../domain/fee.dart';
import '../domain/price.dart';

/// Prix du compte [uid], lus avec le cache hors ligne. Seul ce compte les lit
/// (P5) : le coût d'une recette se calcule avec les prix du lecteur (CR7).
final pricesProvider = StreamProvider.autoDispose
    .family<ListeLue<Price>, String>(
      (ref, uid) => ref.watch(costsRepositoryProvider).watchPrices(uid),
      // Une panne s'affiche ; « Réessayer » relance la lecture.
      retry: (retryCount, error) => null,
    );

/// Frais du compte [uid].
final feesProvider = StreamProvider.autoDispose.family<ListeLue<Fee>, String>(
  (ref, uid) => ref.watch(costsRepositoryProvider).watchFees(uid),
  retry: (retryCount, error) => null,
);

/// Coût figé d'un brassin du compte `uid`.
final brewCostProvider = StreamProvider.autoDispose
    .family<RechercheDocument<BrewCost>, ({String uid, String brewId})>(
      (ref, key) => ref
          .watch(costsRepositoryProvider)
          .watchBrewCost(uid: key.uid, brewId: key.brewId),
      retry: (retryCount, error) => null,
    );

/// Calculs de coût refusés déjà rapportés, par recette ou par brassin : un
/// rapport par session, pas un par lecture (CR9).
final costReportsProvider = Provider<Set<String>>((ref) => <String>{});
