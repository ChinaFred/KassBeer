import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lecture_document.dart';
import '../../../core/providers.dart';
import '../domain/equipment.dart';

/// Équipements du groupe, lus par tous les membres.
final equipmentListProvider = StreamProvider.autoDispose<ListeLue<Equipment>>(
  (ref) => ref.watch(equipmentRepositoryProvider).watchAll(),
  // Une panne s'affiche ; « Réessayer » relance la lecture.
  retry: (retryCount, error) => null,
);
