import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum VisualStyle { card, flat }

class AppTheme {
  static VisualStyle visualStyle = VisualStyle.card;

  static const Color rollinPurple = Color(0xFF8A2CFF);
  static const Color rollinViolet = Color(0xFFB066FF);
  static const Color rollinGold = Color(0xFFF7C94B);
  static const Color rollinDeep = Color(0xFF07040F);
  static const Color rollinPanel = Color(0xFF120A22);
  static const Color rollinPanelSoft = Color(0xFF1A1030);

  // Runtime palette used by legacy AppTheme.* consumers across the app.
  // These values are synchronized by ThemeProvider whenever mode/accent changes.
  static Color primary = rollinPurple;
  static Color secondary = const Color(0xFF5B21B6);
  static Color accent = rollinGold;
  static Color background = rollinDeep;
  static Color surface = rollinPanel;
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
    required VisualStyle style,
  }) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? rollinDeep : const Color(0xFFF8F7FC);
    final sf = isDark ? rollinPanel : Colors.white;
    final tp = isDark ? Colors.white : const Color(0xFF1C102C);
    final ts = isDark ? const Color(0xFFD8CFE8) : const Color(0xFF6D617C);
    final primaryColor = accentColor;
    final secondaryColor = _shiftLightness(accentColor, isDark ? -0.18 : -0.12);
    final tertiaryColor = _shiftLightness(accentColor, isDark ? 0.12 : 0.08);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      primaryColor: primaryColor,
      colorScheme:
          (isDark ? const ColorScheme.dark() : const ColorScheme.light())
              .copyWith(
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: tertiaryColor,
        error: const Color(0xFFFF5C7A),
        surface: sf,
        onSurface: tp,
        onPrimary: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ).apply(bodyColor: tp, displayColor: tp),
      appBarTheme: AppBarTheme(
        backgroundColor: bg.withValues(alpha: 0.92),
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
            borderRadius:
                BorderRadius.circular(style == VisualStyle.card ? 12 : 6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(style == VisualStyle.card ? 12 : 6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(style == VisualStyle.card ? 12 : 6),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(style == VisualStyle.card ? 12 : 6),
          borderSide: BorderSide(color: primaryColor),
        ),
        hintStyle: TextStyle(color: ts),
        labelStyle: TextStyle(color: tp),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: style == VisualStyle.card ? 16 : 12,
        ),
      ),
    );
  }

  static void syncLegacyPalette({
    required Brightness brightness,
    required Color accentColor,
    VisualStyle? style,
  }) {
    if (style != null) visualStyle = style;

    final isDark = brightness == Brightness.dark;
    primary = accentColor;
    secondary = _shiftLightness(accentColor, isDark ? -0.20 : -0.12);
    accent = rollinGold;
    background = isDark ? rollinDeep : const Color(0xFFF8F7FC);
    surface = isDark ? rollinPanel : Colors.white;
    textPrimary = isDark ? Colors.white : const Color(0xFF1C102C);
    textSecondary = isDark ? const Color(0xFFD8CFE8) : const Color(0xFF6D617C);
    cardBorder = isDark
        ? rollinViolet.withValues(alpha: 0.22)
        : rollinPurple.withValues(alpha: 0.12);
  }

  static ThemeData get theme => buildTheme(
        brightness:
            textPrimary == Colors.white ? Brightness.dark : Brightness.light,
        accentColor: accent,
        style: visualStyle,
      );

  static Color _shiftLightness(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final adjusted = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(adjusted).toColor();
  }

  // --- Design Helpers ---

  static double get radius => visualStyle == VisualStyle.card ? 14.0 : 6.0;

  static BorderRadius get borderRadius => BorderRadius.circular(radius);

  static BoxDecoration itemDecoration({
    Color? color,
    double? alpha,
    BorderRadius? customRadius,
    bool hasBorder = true,
  }) {
    final isFlat = visualStyle == VisualStyle.flat;
    final bgColor = color ?? surface;
    final effectiveAlpha = alpha ?? (isFlat ? 0.46 : 0.86);

    return BoxDecoration(
      color: bgColor.withValues(alpha: effectiveAlpha),
      borderRadius: customRadius ?? borderRadius,
      border: hasBorder ? Border.all(color: cardBorder) : null,
      boxShadow: isFlat
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
    );
  }

  static BoxDecoration dashboardBackground() {
    return BoxDecoration(
      color: background,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: textPrimary == Colors.white
            ? const [
                Color(0xFF090512),
                Color(0xFF11081E),
                Color(0xFF06030B),
              ]
            : const [
                Color(0xFFFDFBFF),
                Color(0xFFF4EEFF),
                Color(0xFFF8F7FC),
              ],
      ),
    );
  }
}
