import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class LanguageNotifier extends ChangeNotifier {
  final Box _box = Hive.box('language_prefs_box');
  List<String> _selectedLanguages = [];

  LanguageNotifier() {
    _load();
  }

  List<String> get selectedLanguages => _selectedLanguages;

  void _load() {
    _selectedLanguages =
    List<String>.from(_box.get('selectedLanguages', defaultValue: ['en']));
    notifyListeners();
  }

  void toggleLanguage(String langCode) {
    if (_selectedLanguages.contains(langCode)) {
      _selectedLanguages.remove(langCode);
    } else {
      _selectedLanguages.add(langCode);
    }
    _box.put('selectedLanguages', _selectedLanguages);
    notifyListeners();
  }

  bool isSelected(String langCode) => _selectedLanguages.contains(langCode);
}
