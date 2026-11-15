import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/member.dart';

/// Liste des membres, triée. Lue par l'administrateur seul (`firestore.rules`).
final membersListProvider = StreamProvider.autoDispose<List<Member>>(
  (ref) => ref.watch(membersRepositoryProvider).watchAll(),
  // Une panne s'affiche ; « Réessayer » relance la lecture.
  retry: (retryCount, error) => null,
);

/// Identifiant du projet Firebase, lu à la compilation (`FIREBASE_PROJECT_ID`).
/// Remplacé dans les tests.
final firebaseProjectIdProvider = Provider<String>(
  (ref) => const String.fromEnvironment('FIREBASE_PROJECT_ID'),
);

final _projectIdPattern = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');

/// Page « Audience » de Google Auth Platform, où se gèrent les utilisateurs test
/// de l'écran de consentement OAuth. Google ne fournit aucune API pour les
/// ajouter : l'administrateur le fait à la main. `null` pour un identifiant de
/// projet absent ou mal formé.
Uri? consoleUtilisateursTest(String projectId) {
  if (!_projectIdPattern.hasMatch(projectId)) return null;
  return Uri.https('console.cloud.google.com', '/auth/audience', {
    'project': projectId,
  });
}
