import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  final Box<dynamic> _themeBox = Hive.box('theme_mode_box');

  ThemeNotifier() {
    _loadTheme(); 
  }

  void _loadTheme() {
    final savedTheme = _themeBox.get('theme_mode_box', defaultValue: 'light');
    _themeMode = (savedTheme == 'dark') ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void toggleTheme() {
    _themeMode =
        (_themeMode == ThemeMode.light) ? ThemeMode.dark : ThemeMode.light;

    _themeBox.put(
        'theme_mode_box', _themeMode == ThemeMode.dark ? 'dark' : 'light');

    notifyListeners(); 
  }
}
