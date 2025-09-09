import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeNotifier extends ChangeNotifier {
  // Default to system so first launch matches device theme.
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  final Box<dynamic> _themeBox = Hive.box('theme_mode_box');

  ThemeNotifier() {
    _loadTheme();
  }

  void _loadTheme() {
    // Store one of: 'system' | 'light' | 'dark'
    final saved = _themeBox.get('theme_mode_box', defaultValue: 'system') as String;

    switch (saved) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  // Optional: keep your existing toggle between light/dark.
  // If currently 'system', toggling will go to dark; toggle again → light.
  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }
    _themeBox.put(
      'theme_mode_box',
      _themeMode == ThemeMode.dark ? 'dark' : 'light',
    );
    notifyListeners();
  }

  // (Optional helper) If you ever add a "Use system theme" button in Settings:
  void useSystemTheme() {
    _themeMode = ThemeMode.system;
    _themeBox.put('theme_mode_box', 'system');
    notifyListeners();
  }
}
