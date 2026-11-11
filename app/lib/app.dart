import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/preferences/theme_mode_provider.dart';
import 'core/presentation/breakpoints.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

/// Langue de l'application : sélecteurs de date et d'heure en français, sur 24 h.
const kLocale = Locale('fr');
const kLocalizationsDelegates = <LocalizationsDelegate<Object?>>[
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Application Kass'Beer, une fois Firebase configuré.
class KassBeerApp extends ConsumerWidget {
  const KassBeerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: "Kass'Beer",
      debugShowCheckedModeBanner: false,
      locale: kLocale,
      supportedLocales: const [kLocale],
      localizationsDelegates: kLocalizationsDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Démarrage sans configuration Firebase : l'application ne démarre pas avec des
/// valeurs factices, elle nomme les clés manquantes.
class MissingConfigurationApp extends StatelessWidget {
  const MissingConfigurationApp({super.key, required this.missingKeys});

  static const title = 'Configuration Firebase absente';

  final List<String> missingKeys;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Kass'Beer",
      debugShowCheckedModeBanner: false,
      locale: kLocale,
      supportedLocales: const [kLocale],
      localizationsDelegates: kLocalizationsDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: _StartupMessage(
        title: title,
        message:
            'Compilez avec --dart-define-from-file=firebase.env.json '
            '(modèle : firebase.env.example.json). Clés manquantes :',
        details: missingKeys,
      ),
    );
  }
}

/// Firebase n'a pas pu démarrer : aucun rapport n'est possible, le message le dit.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key});

  static const title = 'Kass\'Beer n\'a pas pu démarrer';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Kass'Beer",
      debugShowCheckedModeBanner: false,
      locale: kLocale,
      supportedLocales: const [kLocale],
      localizationsDelegates: kLocalizationsDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _StartupMessage(
        title: title,
        message: 'Vérifiez le réseau, puis fermez et rouvrez l\'application.',
        details: [],
      ),
    );
  }
}

class _StartupMessage extends StatelessWidget {
  const _StartupMessage({
    required this.title,
    required this.message,
    required this.details,
  });

  final String title;
  final String message;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMessageMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(title, style: theme.textTheme.headlineSmall),
                  ),
                  const SizedBox(height: 16),
                  Text(message),
                  for (final key in details) ...[
                    const SizedBox(height: 4),
                    SelectableText(
                      key,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
