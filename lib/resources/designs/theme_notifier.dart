import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeNotifier extends ChangeNotifier {
  // Default to light theme
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  final Box<dynamic> _themeBox = Hive.box('theme_mode_box');

  ThemeNotifier() {
    _loadTheme(); // Load the saved theme on initialization
  }

  void _loadTheme() {
    final savedTheme = _themeBox.get('theme_mode_box', defaultValue: 'light');
    _themeMode = (savedTheme == 'dark') ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode =
        (_themeMode == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;

    // Save the updated theme to Hive
    _themeBox.put(
        'theme_mode_box', _themeMode == ThemeMode.dark ? 'dark' : 'light');

    notifyListeners(); // Notify listeners to rebuild
  }
}
