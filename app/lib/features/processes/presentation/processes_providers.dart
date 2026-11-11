import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../domain/modele_processus.dart';
import '../domain/preference_processus.dart';

/// Modèles de processus du groupe, lus par tous les membres. Lus à l'ouverture
/// de « Mes processus », pas au lancement.
final processTemplatesProvider =
    StreamProvider.autoDispose<ListeLue<ModeleProcessus>>(
      (ref) => ref.watch(processesRepositoryProvider).watchAll(),
      // Une panne s'affiche ; « Réessayer » relance la lecture.
      retry: (retryCount, error) => null,
    );

/// Choix par défaut du compte [uid], lu par lui seul.
final processPreferenceProvider = StreamProvider.autoDispose
    .family<RechercheDocument<PreferenceProcessus>, String>(
      (ref, uid) =>
          ref.watch(preferencesProcessusRepositoryProvider).watch(uid),
      retry: (retryCount, error) => null,
    );
