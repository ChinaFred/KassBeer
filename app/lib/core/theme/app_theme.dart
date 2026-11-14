import 'package:flutter/material.dart';

/// Thème Material 3 de Kass'Beer. Seul fichier où une couleur est écrite : les
/// écrans lisent `Theme.of(context).colorScheme` et [CouleursEtat].
///
/// Palette tirée du logo : brun du bois (primaire), laiton des lettres
/// (secondaire et surfaces crème), ambre de la chope (tertiaire : en cours,
/// dépassé, avertissement), vert du gobelin (succès, dans [CouleursEtat]).
abstract final class AppTheme {
  /// Brun du bois du médaillon : rôles `primary*`.
  static const Color brun = Color(0xFF6B3E26);

  /// Laiton des lettres : rôles `secondary*` et gamme des surfaces.
  static const Color laiton = Color(0xFFA57C3B);

  /// Ambre de la chope : rôles `tertiary*`.
  static const Color ambre = Color(0xFFB5651D);

  /// Vert du gobelin : couleurs de succès.
  static const Color vert = Color(0xFF5E8C3A);

  /// Rayon des cartes et des encadrés.
  static const double rayon = 16;

  /// Rayon des champs de saisie et des lignes de liste.
  static const double rayonChamp = 12;

  static ThemeData light() => _build(schema(Brightness.light));

  static ThemeData dark() => _build(schema(Brightness.dark));

  /// Couleurs principales en variante `fidelity` : la couleur de départ reste
  /// reconnaissable, au lieu des tons délavés de la variante par défaut.
  /// Conteneurs en variante `tonalSpot` : clairs en thème clair, sombres en
  /// thème sombre, pour qu'un texte ou un bouton posé dessus reste lisible (les
  /// conteneurs `fidelity` sont de teinte moyenne).
  static ColorScheme _depuis(Color graine, Brightness brightness) {
    final vive = ColorScheme.fromSeed(
      seedColor: graine,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final douce = ColorScheme.fromSeed(
      seedColor: graine,
      brightness: brightness,
    );
    return vive.copyWith(
      primaryContainer: douce.primaryContainer,
      onPrimaryContainer: douce.onPrimaryContainer,
    );
  }

  /// Schéma complet : primaires du brun, secondaires et surfaces du laiton,
  /// tertiaires de l'ambre. Les sept surfaces viennent d'une même gamme.
  static ColorScheme schema(Brightness brightness) {
    final brunS = _depuis(brun, brightness);
    final laitonS = _depuis(laiton, brightness);
    final ambreS = _depuis(ambre, brightness);
    return brunS.copyWith(
      secondary: laitonS.primary,
      onSecondary: laitonS.onPrimary,
      secondaryContainer: laitonS.primaryContainer,
      onSecondaryContainer: laitonS.onPrimaryContainer,
      tertiary: ambreS.primary,
      onTertiary: ambreS.onPrimary,
      tertiaryContainer: ambreS.primaryContainer,
      onTertiaryContainer: ambreS.onPrimaryContainer,
      surface: laitonS.surface,
      surfaceDim: laitonS.surfaceDim,
      surfaceBright: laitonS.surfaceBright,
      surfaceContainerLowest: laitonS.surfaceContainerLowest,
      surfaceContainerLow: laitonS.surfaceContainerLow,
      surfaceContainer: laitonS.surfaceContainer,
      surfaceContainerHigh: laitonS.surfaceContainerHigh,
      surfaceContainerHighest: laitonS.surfaceContainerHighest,
      onSurface: laitonS.onSurface,
      onSurfaceVariant: laitonS.onSurfaceVariant,
      outline: laitonS.outline,
      outlineVariant: laitonS.outlineVariant,
      inverseSurface: laitonS.inverseSurface,
      onInverseSurface: laitonS.onInverseSurface,
    );
  }

  /// Police des titres, embarquée (`assets/fonts/`, demi-grasse seule).
  static const String policeTitres = 'Bitter';

  /// Titres en Bitter demi-grasse ; chiffres de largeur fixe partout, pour que
  /// densités, heures et quantités restent alignées d'une ligne à l'autre.
  static TextTheme _textes(TextTheme t) {
    TextStyle? titre(TextStyle? s) => s?.copyWith(
      fontFamily: policeTitres,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    TextStyle? corps(TextStyle? s) =>
        s?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return t.copyWith(
      displayLarge: titre(t.displayLarge),
      displayMedium: titre(t.displayMedium),
      displaySmall: titre(t.displaySmall),
      headlineLarge: titre(t.headlineLarge),
      headlineMedium: titre(t.headlineMedium),
      headlineSmall: titre(t.headlineSmall),
      titleLarge: titre(t.titleLarge),
      titleMedium: corps(t.titleMedium),
      titleSmall: corps(t.titleSmall),
      bodyLarge: corps(t.bodyLarge),
      bodyMedium: corps(t.bodyMedium),
      bodySmall: corps(t.bodySmall),
      labelLarge: corps(t.labelLarge),
      labelMedium: corps(t.labelMedium),
      labelSmall: corps(t.labelSmall),
    );
  }

  static ThemeData _build(ColorScheme scheme) {
    final defaut = ThemeData(colorScheme: scheme, useMaterial3: true);
    final base = defaut.copyWith(textTheme: _textes(defaut.textTheme));
    final text = base.textTheme;
    final bordChamp = OutlineInputBorder(
      borderRadius: BorderRadius.circular(rayonChamp),
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      // Cibles de 48 px sur toutes les plateformes, web compris.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rayon),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: bordChamp,
        enabledBorder: bordChamp.copyWith(
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: bordChamp.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: bordChamp.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: bordChamp.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        disabledBorder: bordChamp.copyWith(
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rayonChamp),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : null,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: scheme.primary,
        collapsedIconColor: scheme.onSurfaceVariant,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      extensions: [
        StylesJourDeBrassage.standard,
        CouleursEtat.depuis(_depuis(vert, scheme.brightness)),
      ],
    );
  }
}

/// Couleurs d'état absentes de `ColorScheme` : le succès (« fait », « tout est
/// prêt »). L'avertissement utilise les rôles `tertiary*` (ambre).
@immutable
class CouleursEtat extends ThemeExtension<CouleursEtat> {
  const CouleursEtat({
    required this.succes,
    required this.surSucces,
    required this.conteneurSucces,
    required this.surConteneurSucces,
  });

  /// Rôles primaires d'un schéma tiré du vert du gobelin.
  factory CouleursEtat.depuis(ColorScheme vert) => CouleursEtat(
    succes: vert.primary,
    surSucces: vert.onPrimary,
    conteneurSucces: vert.primaryContainer,
    surConteneurSucces: vert.onPrimaryContainer,
  );

  /// Extension du thème ; un thème sans elle (tests de widget) reçoit les
  /// couleurs tirées du vert pour sa luminosité.
  static CouleursEtat of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CouleursEtat>() ??
        CouleursEtat.depuis(AppTheme._depuis(AppTheme.vert, theme.brightness));
  }

  final Color succes;
  final Color surSucces;
  final Color conteneurSucces;
  final Color surConteneurSucces;

  @override
  CouleursEtat copyWith({
    Color? succes,
    Color? surSucces,
    Color? conteneurSucces,
    Color? surConteneurSucces,
  }) => CouleursEtat(
    succes: succes ?? this.succes,
    surSucces: surSucces ?? this.surSucces,
    conteneurSucces: conteneurSucces ?? this.conteneurSucces,
    surConteneurSucces: surConteneurSucces ?? this.surConteneurSucces,
  );

  @override
  CouleursEtat lerp(CouleursEtat? other, double t) {
    if (other == null) return this;
    return CouleursEtat(
      succes: Color.lerp(succes, other.succes, t)!,
      surSucces: Color.lerp(surSucces, other.surSucces, t)!,
      conteneurSucces: Color.lerp(conteneurSucces, other.conteneurSucces, t)!,
      surConteneurSucces: Color.lerp(
        surConteneurSucces,
        other.surConteneurSucces,
        t,
      )!,
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
