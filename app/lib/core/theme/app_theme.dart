import 'package:flutter/material.dart';

/// Thème Material 3 de Kass'Beer. Seul fichier où une couleur est écrite : les
/// écrans lisent `Theme.of(context).colorScheme`.
abstract final class AppTheme {
  /// Graine de la palette : ambre de bière.
  static const Color seed = Color(0xFFB8741A);

  /// Surface crème du thème clair.
  static const Color _creamSurface = Color(0xFFFFF8EE);

  /// Surface brun très sombre du thème sombre.
  static const Color _darkBrownSurface = Color(0xFF1C140D);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(seedColor: seed).copyWith(surface: _creamSurface),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: _darkBrownSurface),
  );

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      // Cibles de 48 px sur toutes les plateformes, web compris.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      navigationBarTheme: const NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      extensions: const [StylesJourDeBrassage.standard],
    );
  }
}

/// Tailles de texte de l'écran du jour de brassage, lisible à deux mètres.
@immutable
class StylesJourDeBrassage extends ThemeExtension<StylesJourDeBrassage> {
  const StylesJourDeBrassage({
    required this.minuteur,
    required this.minuteurPaysage,
    required this.minuteurLarge,
    required this.etape,
    required this.etapeLarge,
    required this.ensuite,
    required this.chronologie,
  });

  static const standard = StylesJourDeBrassage(
    minuteur: 88,
    minuteurPaysage: 72,
    minuteurLarge: 128,
    etape: 36,
    etapeLarge: 45,
    ensuite: 22,
    chronologie: 16,
  );

  static StylesJourDeBrassage of(BuildContext context) =>
      Theme.of(context).extension<StylesJourDeBrassage>() ?? standard;

  final double minuteur;
  final double minuteurPaysage;
  final double minuteurLarge;
  final double etape;
  final double etapeLarge;
  final double ensuite;
  final double chronologie;

  @override
  StylesJourDeBrassage copyWith({double? minuteur, double? etape}) =>
      StylesJourDeBrassage(
        minuteur: minuteur ?? this.minuteur,
        minuteurPaysage: minuteurPaysage,
        minuteurLarge: minuteurLarge,
        etape: etape ?? this.etape,
        etapeLarge: etapeLarge,
        ensuite: ensuite,
        chronologie: chronologie,
      );

  @override
  StylesJourDeBrassage lerp(StylesJourDeBrassage? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
