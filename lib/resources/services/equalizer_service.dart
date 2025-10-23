// lib/resources/services/equalizer_service.dart

import 'package:aradia/resources/models/equalizer_settings.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:hive/hive.dart';

class EqualizerService {
  static const String _boxName = 'equalizer_box';
  static const String _activeSettingsKey = 'active_settings';
  static const String _presetsPrefix = 'preset_';

  Box<dynamic>? _box;

  // Initialize the service and open Hive box
  Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      AppLogger.debug('EqualizerService initialized');
    } catch (e) {
      AppLogger.error('Error initializing EqualizerService: $e');
    }
  }

  // Get the currently active equalizer settings
  EqualizerSettings getActiveSettings() {
    try {
      final map = _box?.get(_activeSettingsKey);
      if (map != null) {
        return EqualizerSettings.fromMap(Map<String, dynamic>.from(map));
      }
    } catch (e) {
      AppLogger.error('Error getting active equalizer settings: $e');
    }
    return EqualizerSettings.defaultSettings();
  }

  // Save the active equalizer settings
  Future<void> saveActiveSettings(EqualizerSettings settings) async {
    try {
      await _box?.put(_activeSettingsKey, settings.toMap());
      AppLogger.debug('Active equalizer settings saved: $settings');
    } catch (e) {
      AppLogger.error('Error saving active equalizer settings: $e');
    }
  }

  // Save a named preset
  Future<void> savePreset(String name, EqualizerSettings settings) async {
    try {
      final presetKey = '$_presetsPrefix$name';
      final settingsWithName = settings.copyWith(presetName: name);
      await _box?.put(presetKey, settingsWithName.toMap());
      AppLogger.debug('Equalizer preset saved: $name');
    } catch (e) {
      AppLogger.error('Error saving equalizer preset: $e');
    }
  }

  // Load a named preset
  EqualizerSettings? loadPreset(String name) {
    try {
      final presetKey = '$_presetsPrefix$name';
      final map = _box?.get(presetKey);
      if (map != null) {
        return EqualizerSettings.fromMap(Map<String, dynamic>.from(map));
      }
    } catch (e) {
      AppLogger.error('Error loading equalizer preset: $e');
    }
    return null;
  }

  // Get all preset names
  List<String> getPresetNames() {
    try {
      if (_box == null) return [];
      return _box!.keys
          .where((key) => key.toString().startsWith(_presetsPrefix))
          .map((key) => key.toString().replaceFirst(_presetsPrefix, ''))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting preset names: $e');
      return [];
    }
  }

  // Delete a named preset
  Future<void> deletePreset(String name) async {
    try {
      final presetKey = '$_presetsPrefix$name';
      await _box?.delete(presetKey);
      AppLogger.debug('Equalizer preset deleted: $name');
    } catch (e) {
      AppLogger.error('Error deleting equalizer preset: $e');
    }
  }

  // Reset to default settings
  Future<void> resetToDefault() async {
    final defaultSettings = EqualizerSettings.defaultSettings();
    await saveActiveSettings(defaultSettings);
  }

  // Get built-in presets optimized for audiobook listening
  static Map<String, EqualizerSettings> getBuiltInPresets() {
    return {
      'Voice Clarity': EqualizerSettings(
        band60Hz: -3.0,
        band230Hz: 2.0,
        band910Hz: 5.0,
        band4kHz: 6.0,
        band14kHz: 2.0,
        presetName: 'Voice Clarity',
      ),
      'Car Mode': EqualizerSettings(
        band60Hz: -4.0,
        band230Hz: 4.0,
        band910Hz: 6.0,
        band4kHz: 7.0,
        band14kHz: 4.0,
        presetName: 'Car Mode',
      ),
      'Headphone Mode': EqualizerSettings(
        band60Hz: -2.0,
        band230Hz: 1.0,
        band910Hz: 3.0,
        band4kHz: 4.0,
        band14kHz: 1.0,
        presetName: 'Headphone Mode',
      ),
      'Bass Reducer': EqualizerSettings(
        band60Hz: -6.0,
        band230Hz: -2.0,
        band910Hz: 1.0,
        band4kHz: 3.0,
        band14kHz: 0.0,
        presetName: 'Bass Reducer',
      ),
      'Bright & Clear': EqualizerSettings(
        band60Hz: -4.0,
        band230Hz: 0.0,
        band910Hz: 4.0,
        band4kHz: 7.0,
        band14kHz: 5.0,
        presetName: 'Bright & Clear',
      ),
      'Warm & Smooth': EqualizerSettings(
        band60Hz: 2.0,
        band230Hz: 4.0,
        band910Hz: 3.0,
        band4kHz: 1.0,
        band14kHz: -2.0,
        presetName: 'Warm & Smooth',
      ),
    };
  }
}
