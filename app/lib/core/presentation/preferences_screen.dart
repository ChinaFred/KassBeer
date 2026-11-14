import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/theme_mode_provider.dart';
import 'page_secondaire.dart';

/// Page « Préférences », ouverte depuis le menu du compte : thème de cet
/// appareil (ADR-009). Un choix s'applique et s'enregistre aussitôt.
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  static const titre = 'Préférences';
  static const apparence = 'Apparence';
  static const commeAppareil = "Comme l'appareil";
  static const commeAppareilAide =
      'Suit le mode clair ou sombre du téléphone ou du navigateur.';
  static const clair = 'Clair';
  static const sombre = 'Sombre';
  static const noteAppareil = 'Ce choix vaut pour cet appareil seulement.';
  static const echecEnregistrement =
      "Thème non enregistré : l'ancien thème reviendra au prochain démarrage.";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);

    Future<void> choisir(ThemeMode? choix) async {
      if (choix == null || choix == mode) return;
      final messenger = ScaffoldMessenger.of(context);
      final enregistre = await ref
          .read(themeModeProvider.notifier)
          .choisir(choix);
      if (!enregistre) {
        // Un seul message après plusieurs échecs de suite.
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(content: Text(echecEnregistrement)),
        );
      }
    }

    return PageSecondaire(
      titre: titre,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            header: true,
            child: Text(apparence, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: mode,
              onChanged: (choix) => unawaited(choisir(choix)),
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    secondary: Icon(Icons.brightness_auto_outlined),
                    title: Text(commeAppareil),
                    subtitle: Text(commeAppareilAide),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    secondary: Icon(Icons.light_mode_outlined),
                    title: Text(clair),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    secondary: Icon(Icons.dark_mode_outlined),
                    title: Text(sombre),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            noteAppareil,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
