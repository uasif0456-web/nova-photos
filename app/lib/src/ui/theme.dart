/// NOVA PHOTOS design system — Material 3, original branding.
///
/// Branding is deliberately NOT Google Photos (no four-colour pinwheel,
/// no Google blue/red/yellow/green): deep indigo/violet with an aurora
/// accent (violet → teal → rose), dark-first night-sky feel with a
/// light cream/day variant. The mark is a geometric nova burst
/// (see `assets/icons/`).
library;

import 'package:material_ui/material_ui.dart';

/// Brand palette (original — drawn for NOVA PHOTOS).
abstract class NovaColors {
  /// Deep indigo — the night sky of the dark theme.
  static const Color indigoDeep = Color(0xFF14102E);

  /// Indigo surface.
  static const Color indigo = Color(0xFF241A5E);

  /// Primary violet.
  static const Color violet = Color(0xFF7C5CFF);

  /// Light violet (on-dark accents).
  static const Color violetLight = Color(0xFFA894FF);

  /// Aurora teal — the "aurora" accent.
  static const Color auroraTeal = Color(0xFF2DD4BF);

  /// Aurora rose — the third aurora stop.
  static const Color auroraRose = Color(0xFFF472B6);

  /// Light theme background — pale starlight cream.
  static const Color starlight = Color(0xFFF6F5FB);

  /// Light theme surface.
  static const Color starlightSurface = Color(0xFFFFFFFF);

  /// Dark theme background.
  static const Color night = Color(0xFF0E0A1F);

  /// Dark theme surface.
  static const Color nightSurface = Color(0xFF1B1533);
}

final _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: NovaColors.violet,
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFFE4DEFF),
  onPrimaryContainer: NovaColors.indigo,
  secondary: NovaColors.auroraTeal,
  onSecondary: const Color(0xFF00201B),
  secondaryContainer: const Color(0xFFB8F1E6),
  onSecondaryContainer: const Color(0xFF00201B),
  tertiary: NovaColors.auroraRose,
  onTertiary: const Color(0xFF3D0A26),
  tertiaryContainer: const Color(0xFFFFD9EC),
  onTertiaryContainer: const Color(0xFF3D0A26),
  error: const Color(0xFFBA1A1A),
  onError: Colors.white,
  surface: NovaColors.starlightSurface,
  onSurface: const Color(0xFF1B1830),
  surfaceContainerHighest: const Color(0xFFE9E6F2),
  onSurfaceVariant: const Color(0xFF4A4763),
  outline: const Color(0xFF7B7894),
  surfaceTint: NovaColors.violet,
  shadow: Colors.black,
);

final _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: NovaColors.violetLight,
  onPrimary: NovaColors.indigoDeep,
  primaryContainer: NovaColors.indigo,
  onPrimaryContainer: const Color(0xFFE4DEFF),
  secondary: NovaColors.auroraTeal,
  onSecondary: const Color(0xFF00201B),
  secondaryContainer: const Color(0xFF004D40),
  onSecondaryContainer: const Color(0xFFB8F1E6),
  tertiary: NovaColors.auroraRose,
  onTertiary: const Color(0xFF3D0A26),
  tertiaryContainer: const Color(0xFF5B1A3D),
  onTertiaryContainer: const Color(0xFFFFD9EC),
  error: const Color(0xFFFFB4AB),
  onError: const Color(0xFF690005),
  surface: NovaColors.nightSurface,
  onSurface: const Color(0xFFEDEAF7),
  surfaceContainerHighest: const Color(0xFF2C2547),
  onSurfaceVariant: const Color(0xFFC6C2DA),
  outline: const Color(0xFF8F8CA8),
  surfaceTint: NovaColors.violetLight,
  shadow: Colors.black,
);

ThemeData novaLightTheme() {
  return ThemeData(
    colorScheme: _lightScheme,
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: NovaColors.starlight,
    appBarTheme: AppBarTheme(
      backgroundColor: NovaColors.starlight,
      foregroundColor: _lightScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: NovaColors.starlightSurface,
      selectedItemColor: NovaColors.violet,
      unselectedItemColor: _lightScheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NovaColors.violet, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NovaColors.violet,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: NovaColors.starlightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _lightScheme.outline.withValues(alpha: 0.2)),
      ),
    ),
  );
}

ThemeData novaDarkTheme() {
  return ThemeData(
    colorScheme: _darkScheme,
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: NovaColors.night,
    appBarTheme: AppBarTheme(
      backgroundColor: NovaColors.night,
      foregroundColor: _darkScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: NovaColors.nightSurface,
      selectedItemColor: NovaColors.violetLight,
      unselectedItemColor: _darkScheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: NovaColors.violetLight, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NovaColors.violet,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: NovaColors.nightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _darkScheme.outline.withValues(alpha: 0.25)),
      ),
    ),
  );
}
