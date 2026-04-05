import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKeyDarkMode = 'app_dark_mode';

/// Persists user dark-mode choice and drives [MaterialApp.themeMode].
class AppThemeMode extends ChangeNotifier {
  AppThemeMode._();
  static final AppThemeMode instance = AppThemeMode._();

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool(_prefsKeyDarkMode) ?? false;
    _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setDark(bool enabled) async {
    _themeMode = enabled ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyDarkMode, enabled);
  }
}
