import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/members/data/members_repository.dart';
import 'services/error_report_service.dart';

/// Services de l'application. `main.dart` les fournit par `overrides` ; les tests y
/// mettent des doubles. Aucun n'a de valeur par défaut : un oubli lève une erreur
/// au lieu de construire un client Firebase.
final errorReportServiceProvider = Provider<ErrorReportService>(
  (ref) => throw UnimplementedError('errorReportServiceProvider non fourni'),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('authRepositoryProvider non fourni'),
);

final membersRepositoryProvider = Provider<MembersRepository>(
  (ref) => throw UnimplementedError('membersRepositoryProvider non fourni'),
);

/// Version installée (`version` de `pubspec.yaml`, lue par `package_info_plus` au
/// démarrage) ; `null` si la lecture a échoué. Le menu du compte l'affiche.
final appVersionProvider = Provider<String?>(
  (ref) => throw UnimplementedError('appVersionProvider non fourni'),
);
