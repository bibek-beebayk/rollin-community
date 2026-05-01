import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Runtime palette used by legacy AppTheme.* consumers across the app.
  // These values are synchronized by ThemeProvider whenever mode/accent changes.
  static Color primary = const Color(0xFF2563EB);
  static Color secondary = const Color(0xFF1D4ED8);
  static Color accent = const Color(0xFF10B981);
  static Color background = const Color(0xFF0F172A);
  static Color surface = const Color(0xFF1E293B);
  static Color textPrimary = Colors.white;
  static Color textSecondary = const Color(0xFFCBD5E1);
  static Color cardBorder = Colors.white.withValues(alpha: 0.12);

  // Gradients
  static LinearGradient get primaryGradient => LinearGradient(
        colors: [
          _shiftLightness(primary, 0.12),
          primary,
          _shiftLightness(primary, -0.10),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static ThemeData buildTheme({
    required Brightness brightness,
    required Color accentColor,
  }) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final sf = isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2F7);
    final tp = isDark ? Colors.white : const Color(0xFF1E293B);
    final ts = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);
    final primaryColor = accentColor;
    final secondaryColor = _shiftLightness(accentColor, isDark ? -0.18 : -0.12);
    final tertiaryColor = _shiftLightness(accentColor, isDark ? 0.12 : 0.08);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      primaryColor: primaryColor,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: tertiaryColor,
        surface: sf,
        onSurface: tp,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).apply(bodyColor: tp, displayColor: tp),
      appBarTheme: AppBarTheme(
        backgroundColor: bg.withValues(alpha: 0.96),
        elevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: tp,
        ),
        iconTheme: IconThemeData(color: tp),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor),
        ),
        hintStyle: TextStyle(color: ts),
        labelStyle: TextStyle(color: tp),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  static void syncLegacyPalette({
    required Brightness brightness,
    required Color accentColor,
  }) {
    final isDark = brightness == Brightness.dark;
    primary = accentColor;
    secondary = _shiftLightness(accentColor, isDark ? -0.18 : -0.12);
    accent = _shiftLightness(accentColor, isDark ? 0.12 : 0.08);
    background = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    surface = isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2F7);
    textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
    textSecondary = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);
    cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);
  }

  static ThemeData get theme => buildTheme(
        brightness: textPrimary == Colors.white ? Brightness.dark : Brightness.light,
        accentColor: accent,
      );

  static Color _shiftLightness(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final adjusted = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(adjusted).toColor();
  }
}
