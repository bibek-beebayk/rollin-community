import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'app_theme_mode';
  static const String _accentColorKey = 'app_accent_color';
  static const String _visualStyleKey = 'app_visual_style';

  ThemeMode _themeMode = ThemeMode.dark;
  Color _accentColor = AppTheme.rollinPurple;
  VisualStyle _visualStyle = VisualStyle.card;

  bool _isInitialized = false;

  ThemeProvider() {
    _loadPreferences();
    _syncLegacyPalette();
  }

  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  VisualStyle get visualStyle => _visualStyle;
  bool get isInitialized => _isInitialized;

  static const List<Color> accentPresets = [
    AppTheme.rollinPurple,
    AppTheme.rollinViolet,
    AppTheme.rollinGold,
    Color(0xFF10B981), // Emerald
    Color(0xFF059669), // Forest
    Color(0xFF22C55E), // Green
    Color(0xFF2563EB), // Blue
    Color(0xFF0EA5E9), // Sky
    Color(0xFF06B6D4), // Cyan
    Color(0xFF8B5CF6), // Violet
    Color(0xFF7C3AED), // Indigo
    Color(0xFFA855F7), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFFF43F5E), // Rose
    Color(0xFFEF4444), // Red
    Color(0xFFF97316), // Orange
    Color(0xFFF59E0B), // Amber
    Color(0xFFEAB308), // Yellow
    Color(0xFF14B8A6), // Teal
  ];

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final modeRaw = prefs.getString(_themeModeKey);
    final accentRaw = prefs.getInt(_accentColorKey);
    final styleRaw = prefs.getString(_visualStyleKey);

    if (modeRaw != null) {
      _themeMode = _parseThemeMode(modeRaw);
    }
    if (accentRaw != null) {
      _accentColor = Color(accentRaw);
    }
    if (styleRaw != null) {
      _visualStyle = styleRaw == 'flat' ? VisualStyle.flat : VisualStyle.card;
    }

    _syncLegacyPalette();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    _syncLegacyPalette();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _themeMode.name);
  }

  Future<void> setAccentColor(Color color) async {
    if (_accentColor.toARGB32() == color.toARGB32()) return;
    _accentColor = color;
    _syncLegacyPalette();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentColorKey, color.toARGB32());
  }

  Future<void> setVisualStyle(VisualStyle style) async {
    if (_visualStyle == style) return;
    _visualStyle = style;
    _syncLegacyPalette();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_visualStyleKey, style.name);
  }

  static ThemeMode _parseThemeMode(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  void _syncLegacyPalette() {
    final brightness = _effectiveBrightness();
    AppTheme.syncLegacyPalette(
      brightness: brightness,
      accentColor: _accentColor,
      style: _visualStyle,
    );
  }

  Brightness _effectiveBrightness() {
    switch (_themeMode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }
}
