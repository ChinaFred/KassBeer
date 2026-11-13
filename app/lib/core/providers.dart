import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/brew_day/data/alerte_minuteur.dart';
import '../features/brews/data/brews_repository.dart';
import '../features/costs/data/costs_repository.dart';
import '../features/equipment/data/equipment_repository.dart';
import '../features/library/data/library_repository.dart';
import '../features/members/data/members_repository.dart';
import '../features/processes/data/preferences_processus_repository.dart';
import '../features/processes/data/processes_repository.dart';
import '../features/recipes/data/recipes_repository.dart';
import '../features/tickets/data/tickets_repository.dart';
import 'fichiers/echange_fichiers.dart';
import 'preferences/preferences_appareil.dart';
import 'services/error_report_service.dart';
import 'services/screen_wakelock.dart';

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

final recipesRepositoryProvider = Provider<RecipesRepository>(
  (ref) => throw UnimplementedError('recipesRepositoryProvider non fourni'),
);

final equipmentRepositoryProvider = Provider<EquipmentRepository>(
  (ref) => throw UnimplementedError('equipmentRepositoryProvider non fourni'),
);

final brewsRepositoryProvider = Provider<BrewsRepository>(
  (ref) => throw UnimplementedError('brewsRepositoryProvider non fourni'),
);

/// Prix, frais et coûts figés du compte connecté (`users/{uid}/`).
final costsRepositoryProvider = Provider<CostsRepository>(
  (ref) => throw UnimplementedError('costsRepositoryProvider non fourni'),
);

/// Modèles de processus du groupe (`process_templates/`, ADR-010).
final processesRepositoryProvider = Provider<ProcessesRepository>(
  (ref) => throw UnimplementedError('processesRepositoryProvider non fourni'),
);

/// Choix par défaut du compte connecté (`users/{uid}/preferences/processes`).
final preferencesProcessusRepositoryProvider =
    Provider<PreferencesProcessusRepository>(
      (ref) => throw UnimplementedError(
        'preferencesProcessusRepositoryProvider non fourni',
      ),
    );

/// Bibliothèque : `beer_index/`, `beer_*/`, `public_recipes/`, lus par `get()`
/// seul (ADR-005, P22).
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => throw UnimplementedError('libraryRepositoryProvider non fourni'),
);

/// Tickets des membres (`tickets/`, `ticket_status/github`, ADR-006).
final ticketsRepositoryProvider = Provider<TicketsRepository>(
  (ref) => throw UnimplementedError('ticketsRepositoryProvider non fourni'),
);

/// Heure de l'appareil. Injectée pour les tests : un minuteur se recalcule à
/// partir des heures enregistrées, jamais d'un `Timer` (CLAUDE.md, P2).
final horlogeProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Verrou d'écran du jour de brassage.
final screenWakelockProvider = Provider<ScreenWakelock>(
  (ref) =>
      ScreenWakelock(errorReportService: ref.watch(errorReportServiceProvider)),
);

/// Alerte de fin de minuteur (son et vibration).
final alerteMinuteurProvider = Provider<AlerteMinuteur>(
  (ref) => AlerteMinuteurPlateforme(
    errorReportService: ref.watch(errorReportServiceProvider),
  ),
);

/// Choix d'un fichier et envoi d'un fichier exporté (ADR-007).
final echangeFichiersProvider = Provider<EchangeFichiers>(
  (ref) => EchangeFichiersPlateforme(
    errorReportService: ref.watch(errorReportServiceProvider),
  ),
);

/// Version installée (`version` de `pubspec.yaml`, lue par `package_info_plus` au
/// démarrage) ; `null` si la lecture a échoué. Le menu du compte l'affiche.
final appVersionProvider = Provider<String?>(
  (ref) => throw UnimplementedError('appVersionProvider non fourni'),
);

/// Préférences gardées sur l'appareil (ADR-009) : canal `fr.kassbeer/prefs` sur
/// Android, `localStorage` sur le web. `main.dart` fournit l'instance qui a lu le
/// thème au démarrage.
final preferencesAppareilProvider = Provider<PreferencesAppareil>(
  (ref) => PreferencesAppareilPlateforme(),
);

/// Thème lu sur l'appareil avant `runApp` (`main.dart`) ; [ThemeMode.system] si
/// rien n'est enregistré ou si la lecture a échoué.
final themeModeInitialProvider = Provider<ThemeMode>(
  (ref) => throw UnimplementedError('themeModeInitialProvider non fourni'),
);
