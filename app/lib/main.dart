import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/services/error_report_service.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/brews/data/brews_repository.dart';
import 'features/costs/data/costs_repository.dart';
import 'features/equipment/data/equipment_repository.dart';
import 'features/library/data/library_repository.dart';
import 'features/members/data/members_repository.dart';
import 'features/processes/data/preferences_processus_repository.dart';
import 'features/processes/data/processes_repository.dart';
import 'features/recipes/data/recipes_repository.dart';
import 'features/tickets/data/tickets_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final env = FirebaseEnv.fromEnvironment();
  final missing = env.missingKeys(web: kIsWeb);
  if (missing.isNotEmpty) {
    runApp(MissingConfigurationApp(missingKeys: missing));
    return;
  }

  try {
    await Firebase.initializeApp(options: env.options(web: kIsWeb));
    // Cache persistant sans limite de taille : le jour de brassage marche hors ligne
    // (CLAUDE.md, « Le jour de brassage marche sans réseau »).
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (error, stackTrace) {
    // Sans Firebase, aucun rapport ne peut partir : la console est le seul recours,
    // et l'écran affiche la panne.
    debugPrint('[main] Firebase n\'a pas démarré : $error\n$stackTrace');
    runApp(const StartupFailureApp());
    return;
  }

  String? version;
  Object? versionError;
  StackTrace? versionStack;
  try {
    version = (await PackageInfo.fromPlatform()).version;
    if (version.isEmpty) version = null;
  } catch (error, stackTrace) {
    versionError = error;
    versionStack = stackTrace;
  }

  final errors = ErrorReportService(appVersion: version);
  if (versionError != null) {
    errors.reportError(
      feature: 'app.version',
      error: versionError,
      stackTrace: versionStack,
    );
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    errors.reportError(
      feature: 'flutter_error',
      error: details.exception,
      stackTrace: details.stack,
      context: details.library,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    errors.reportError(
      feature: 'platform_error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };

  if (!kIsWeb) {
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: env.googleServerClientId,
      );
    } catch (error, stackTrace) {
      // La connexion échouera et l'écran de connexion l'affichera.
      errors.reportError(
        feature: 'auth.google_sign_in_init',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        errorReportServiceProvider.overrideWithValue(errors),
        appVersionProvider.overrideWithValue(version),
        authRepositoryProvider.overrideWithValue(
          FirebaseAuthRepository(errorReportService: errors),
        ),
        membersRepositoryProvider.overrideWithValue(
          FirestoreMembersRepository(errorReportService: errors),
        ),
        recipesRepositoryProvider.overrideWithValue(
          FirestoreRecipesRepository(errorReportService: errors),
        ),
        equipmentRepositoryProvider.overrideWithValue(
          FirestoreEquipmentRepository(errorReportService: errors),
        ),
        brewsRepositoryProvider.overrideWithValue(
          FirestoreBrewsRepository(errorReportService: errors),
        ),
        costsRepositoryProvider.overrideWithValue(
          FirestoreCostsRepository(errorReportService: errors),
        ),
        processesRepositoryProvider.overrideWithValue(
          FirestoreProcessesRepository(errorReportService: errors),
        ),
        preferencesProcessusRepositoryProvider.overrideWithValue(
          FirestorePreferencesProcessusRepository(errorReportService: errors),
        ),
        libraryRepositoryProvider.overrideWithValue(
          FirestoreLibraryRepository(errorReportService: errors),
        ),
        ticketsRepositoryProvider.overrideWithValue(
          FirestoreTicketsRepository(errorReportService: errors),
        ),
      ],
      child: const KassBeerApp(),
    ),
  );
}
