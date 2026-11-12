import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Spatial Obsidian Design System for Ozone v2.0.0
class OzoneTheme {
  // Spatial Obsidian Dark Palette
  static const Color background = Color(0xFF090A0F); // Deep obsidian canvas
  static const Color surface = Color(0xFF131620); // Elevated glass surface
  static const Color surfaceCard = Color(0xFF131620); // Elevated glass card
  static const Color glassSurface = Color(0xCC131620); // Translucent glass
  static const Color statsCard = Color(0xFF1C1632); // Telemetry glass card

  // Accents & Signals
  static const Color cyan = Color(0xFF00E5FF); // Electric cyan accent
  static const Color indigo = Color(0xFF6E56CF); // Electric indigo secondary accent
  static const Color emerald = Color(0xFF00E676); // Connected / active signal
  static const Color amber = Color(0xFFFFB300); // Warning / invite signal
  static const Color ruby = Color(0xFFFF3366); // Call end / critical signal

  // Typography Palette
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E92A0);
  static const Color textTertiary = Color(0xFF5A5E6D);

  // 1px Hairline Borders (0.08 alpha white)
  static const Color hairlineColor = Color(0x14FFFFFF);
  static const BorderSide hairlineBorderSide = BorderSide(
    color: hairlineColor,
    width: 1.0,
  );
  static final Border hairlineBorder = Border.all(
    color: hairlineColor,
    width: 1.0,
  );

  /// Spatial Glass Container Decoration
  static BoxDecoration glassBox({
    Color? color,
    double borderRadius = 16,
    Border? border,
    List<BoxShadow>? shadows,
    Gradient? gradient,
  }) {
    return BoxDecoration(
      color: gradient == null ? (color ?? surface.withValues(alpha: 0.88)) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(borderRadius),
      border: border ?? hairlineBorder,
      boxShadow: shadows ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
    );
  }

  /// Refined Dark Theme with Spatial Obsidian Styling
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: cyan,
      secondary: indigo,
      surface: surface,
      error: ruby,
      onPrimary: Colors.black,
      onSecondary: Colors.white,
      onSurface: textPrimary,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: hairlineBorderSide,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: textPrimary,
      ),
      iconTheme: IconThemeData(color: cyan),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: cyan,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(color: textSecondary, fontSize: 14),
      prefixIconColor: cyan,
      suffixIconColor: textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: hairlineBorderSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: hairlineBorderSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: cyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: ruby, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: hairlineColor,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Subtle Haptic Feedback Manager
class OzoneHaptics {
  static Future<void> light() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static Future<void> medium() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  static Future<void> selection() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }
}

/// Adaptive Layout Helper for Desktop, Tablet and Mobile
class OzoneResponsive {
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 900;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 600 && width < 900;
  }

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;
}
