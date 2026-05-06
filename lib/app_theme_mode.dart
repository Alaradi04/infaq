import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKeyDarkMode = 'app_dark_mode';
const _prefsKeyUseSystemTheme = 'app_use_system_theme';

/// Persists user dark-mode choice and drives [MaterialApp.themeMode].
class AppThemeMode extends ChangeNotifier {
  AppThemeMode._();
  static final AppThemeMode instance = AppThemeMode._();

  ThemeMode _themeMode = ThemeMode.system;
  SharedPreferences? _prefs;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isSystem => _themeMode == ThemeMode.system;

  Future<SharedPreferences> _prefsInstance() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> load() async {
    final prefs = await _prefsInstance();
    final useSystem = prefs.getBool(_prefsKeyUseSystemTheme);
    if (useSystem == null || useSystem) {
      _themeMode = ThemeMode.system;
    } else {
      final dark = prefs.getBool(_prefsKeyDarkMode) ?? false;
      _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> setDark(bool enabled) async {
    final next = enabled ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == next) return;
    _themeMode = next;
    notifyListeners();
    final prefs = await _prefsInstance();
    unawaited(prefs.setBool(_prefsKeyUseSystemTheme, false));
    unawaited(prefs.setBool(_prefsKeyDarkMode, enabled));
  }

  Future<void> setSystem(bool enabled) async {
    final prefs = await _prefsInstance();
    if (enabled) {
      if (_themeMode == ThemeMode.system) return;
      _themeMode = ThemeMode.system;
      notifyListeners();
      unawaited(prefs.setBool(_prefsKeyUseSystemTheme, true));
      return;
    }
    unawaited(prefs.setBool(_prefsKeyUseSystemTheme, false));
    final dark = prefs.getBool(_prefsKeyDarkMode) ?? false;
    final next = dark ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == next) return;
    _themeMode = next;
    notifyListeners();
  }
}
