import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/presentation/access_providers.dart';
import '../data/ai_repository.dart';
import '../domain/comptes_ia.dart';
import '../domain/reglages_ia.dart';

Duration? _sansNouvelEssai(int retryCount, Object error) => null;

/// `ai_config/policy`, lu par `get()` à la première écoute ; une écoute
/// nouvelle après l'abandon relit (éditeur, panneau, menu du compte). Une
/// panne est rapportée par le dépôt, puis rendue en erreur.
final politiqueIaProvider = FutureProvider.autoDispose<LectureIa<PolitiqueIa>>(
  (ref) => ref.watch(aiRepositoryProvider).lirePolitique(),
  retry: _sansNouvelEssai,
);

/// `ai_config/pricing`, pour l'administrateur.
final grilleIaProvider = FutureProvider.autoDispose<LectureIa<GrilleTarifaire>>(
  (ref) => ref.watch(aiRepositoryProvider).lireGrille(),
  retry: _sansNouvelEssai,
);

/// `ai_quotas/{uid}` du compte connecté ; `null` sans compte.
final quotasIaProvider = FutureProvider.autoDispose<LectureIa<QuotasIa>?>((
  ref,
) {
  final uid = ref.watch(grantedAccessProvider.select((a) => a?.user.uid));
  if (uid == null) return null;
  return ref.watch(aiRepositoryProvider).lireQuotas(uid);
}, retry: _sansNouvelEssai);

/// Compte du mois en cours (heure de l'appareil) du compte connecté ; `null`
/// sans compte.
final compteMoisIaProvider =
    FutureProvider.autoDispose<LectureIa<CompteMoisIa>?>((ref) {
      final uid = ref.watch(grantedAccessProvider.select((a) => a?.user.uid));
      if (uid == null) return null;
      final mois = cleMois(ref.read(horlogeProvider)());
      return ref.watch(aiRepositoryProvider).lireCompteMois(mois, uid);
    }, retry: _sansNouvelEssai);

/// Comptes du mois `AAAA-MM` de tous les membres (Admin › Coûts de l'IA).
final comptesDuMoisProvider = FutureProvider.autoDispose
    .family<ComptesDuMois, String>(
      (ref, mois) => ref.watch(aiRepositoryProvider).listerComptesMois(mois),
      retry: _sansNouvelEssai,
    );
