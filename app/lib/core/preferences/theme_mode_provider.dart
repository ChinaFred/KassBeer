import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'preferences_appareil.dart';

/// Thème choisi sur cet appareil (ADR-009). Part de [themeModeInitialProvider],
/// lu avant `runApp` : le premier écran s'affiche dans le bon thème.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// Numéro du dernier appel de [choisir] : un échec ne s'annonce que s'il
  /// porte sur le dernier choix, même si un choix suivant a remis le même thème.
  int _dernierChoix = 0;

  @override
  ThemeMode build() => ref.read(themeModeInitialProvider);

  /// Applique [mode] aussitôt, puis l'enregistre. Rend `false` si
  /// l'enregistrement échoue (rapporté) : le thème reste choisi pour la session.
  /// Un échec d'un choix déjà suivi d'un autre appel est rapporté mais rend
  /// `true` : l'écran n'annonce que l'échec du dernier choix.
  Future<bool> choisir(ThemeMode mode) async {
    final choix = ++_dernierChoix;
    state = mode;
    try {
      await ref.read(preferencesAppareilProvider).ecrireTheme(mode);
      return true;
    } catch (error, stackTrace) {
      ref
          .read(errorReportServiceProvider)
          .reportError(
            feature: 'theme_mode.save',
            error: error,
            stackTrace: stackTrace,
            context: contextePreference(error),
          );
      return choix != _dernierChoix;
    }
  }
}
