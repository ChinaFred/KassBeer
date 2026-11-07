import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/member.dart';

/// Liste des membres, triée. Lue par l'administrateur seul (`firestore.rules`).
final membersListProvider = StreamProvider.autoDispose<List<Member>>(
  (ref) => ref.watch(membersRepositoryProvider).watchAll(),
  // Une panne s'affiche ; « Réessayer » relance la lecture.
  retry: (retryCount, error) => null,
);
