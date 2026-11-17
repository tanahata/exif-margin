import 'package:flutter/material.dart';

/// Shared yamabuki palette for EXIF Margin and future personal apps.
///
/// The bright brand yellow is for icons and decorative accents. Text/actions
/// use darker (light mode) or lighter (dark mode) shades with verified contrast.
abstract final class YamabukiColors {
  static const Color brand = Color(0xFFD99A22);
  static const Color lightPrimary = Color(0xFF8A5900);
  static const Color lightSurface = Color(0xFFFFFBF4);
  static const Color lightOnSurface = Color(0xFF29231B);
  static const Color lightPrimaryContainer = Color(0xFFFFE8B3);
  static const Color lightOnPrimaryContainer = Color(0xFF493000);
  static const Color lightOutline = Color(0xFF796F60);
  static const Color darkPrimary = Color(0xFFF5C76E);
  static const Color darkSurface = Color(0xFF201D18);
  static const Color darkOnSurface = Color(0xFFF7F0E7);
  static const Color darkPrimaryContainer = Color(0xFF63450F);
  static const Color darkOnPrimaryContainer = Color(0xFFFFDEAA);
  static const Color darkOutline = Color(0xFFB0A28C);
}

/// Create an accessible theme without changing private Photo Frame styling.
///
/// The generated Material 3 palette supplies semantic status colors. Override
/// only identity and interaction roles; error/success should not become amber.
ThemeData yamabukiAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: YamabukiColors.brand,
        brightness: brightness,
        contrastLevel: 0.5,
      ).copyWith(
        primary: dark
            ? YamabukiColors.darkPrimary
            : YamabukiColors.lightPrimary,
        onPrimary: dark ? YamabukiColors.lightOnSurface : Colors.white,
        primaryContainer: dark
            ? YamabukiColors.darkPrimaryContainer
            : YamabukiColors.lightPrimaryContainer,
        onPrimaryContainer: dark
            ? YamabukiColors.darkOnPrimaryContainer
            : YamabukiColors.lightOnPrimaryContainer,
        secondary: dark ? const Color(0xFFDEC18B) : const Color(0xFF76541A),
        onSecondary: dark ? const Color(0xFF34260B) : Colors.white,
        secondaryContainer: dark
            ? const Color(0xFF553C16)
            : YamabukiColors.lightPrimaryContainer,
        onSecondaryContainer: dark
            ? const Color(0xFFF7E4C1)
            : YamabukiColors.lightOnPrimaryContainer,
        surface: dark
            ? YamabukiColors.darkSurface
            : YamabukiColors.lightSurface,
        onSurface: dark
            ? YamabukiColors.darkOnSurface
            : YamabukiColors.lightOnSurface,
        outline: dark
            ? YamabukiColors.darkOutline
            : YamabukiColors.lightOutline,
        outlineVariant: dark
            ? YamabukiColors.darkOutline
            : YamabukiColors.lightOutline,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.24),
      selectionHandleColor: scheme.primary,
    ),
  );
}
