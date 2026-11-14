import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kass_beer/core/theme/app_theme.dart';

/// Rapport de contraste WCAG entre deux couleurs opaques.
double contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    group('Thème ${brightness.name}', () {
      final theme = brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark();
      final s = theme.colorScheme;
      final etat = theme.extension<CouleursEtat>()!;

      final couples = <String, (Color, Color)>{
        'primary': (s.primary, s.onPrimary),
        'primaryContainer': (s.primaryContainer, s.onPrimaryContainer),
        'secondary': (s.secondary, s.onSecondary),
        'secondaryContainer': (s.secondaryContainer, s.onSecondaryContainer),
        'tertiary': (s.tertiary, s.onTertiary),
        'tertiaryContainer': (s.tertiaryContainer, s.onTertiaryContainer),
        'error': (s.error, s.onError),
        'errorContainer': (s.errorContainer, s.onErrorContainer),
        'surface / onSurface': (s.surface, s.onSurface),
        'surface / onSurfaceVariant': (s.surface, s.onSurfaceVariant),
        'surfaceContainer / onSurface': (s.surfaceContainer, s.onSurface),
        'surfaceContainerLow / onSurfaceVariant': (
          s.surfaceContainerLow,
          s.onSurfaceVariant,
        ),
        'surfaceContainerHighest / onSurfaceVariant': (
          s.surfaceContainerHighest,
          s.onSurfaceVariant,
        ),
        'surface / primary': (s.surface, s.primary),
        'surface / tertiary': (s.surface, s.tertiary),
        'succès': (etat.succes, etat.surSucces),
        'conteneur succès': (etat.conteneurSucces, etat.surConteneurSucces),
        'surface / succès': (s.surface, etat.succes),
        // Bouton texte posé dans un encadré coloré.
        'primaryContainer / primary': (s.primaryContainer, s.primary),
        'secondaryContainer / primary': (s.secondaryContainer, s.primary),
        'tertiaryContainer / primary': (s.tertiaryContainer, s.primary),
        'conteneur succès / primary': (etat.conteneurSucces, s.primary),
      };

      for (final MapEntry(key: nom, value: (fond, texte)) in couples.entries) {
        test('$nom : contraste d’au moins 4,5:1', () {
          expect(contraste(fond, texte), greaterThanOrEqualTo(4.5));
        });
      }

      test('les surfaces vont de la plus basse à la plus haute', () {
        final niveaux = [
          s.surfaceContainerLowest,
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ].map((c) => c.computeLuminance()).toList();
        final croissant = brightness == Brightness.dark;
        for (var i = 1; i < niveaux.length; i++) {
          expect(
            croissant
                ? niveaux[i] > niveaux[i - 1]
                : niveaux[i] < niveaux[i - 1],
            isTrue,
            reason: 'niveau $i',
          );
        }
      });

      test('polices embarquées : Roboto, Bitter aux titres, secours', () {
        final t = theme.textTheme;
        for (final style in [t.bodyMedium, t.labelLarge, t.titleMedium]) {
          expect(style?.fontFamily, 'Roboto');
          expect(style?.fontFamilyFallback, ['Roboto', 'Symboles']);
        }
        for (final style in [t.headlineLarge, t.titleLarge]) {
          expect(style?.fontFamily, 'Bitter');
          expect(style?.fontWeight, FontWeight.w600);
          expect(style?.fontFamilyFallback, ['Roboto', 'Symboles']);
        }
      });
    });
  }
}
