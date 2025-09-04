import 'package:flutter/foundation.dart';

class AppLogger {
  static const String _tag = 'Aradia';

  static void debug(String message, [String? tag]) {
    if (kDebugMode) {
      print('[${tag ?? _tag}] DEBUG: $message');
    }
  }

  static void info(String message, [String? tag]) {
    if (kDebugMode) {
      print('[${tag ?? _tag}] INFO: $message');
    }
  }

  static void warning(String message, [String? tag]) {
    if (kDebugMode) {
      print('[${tag ?? _tag}] WARNING: $message');
    }
  }

  static void error(String message, [String? tag]) {
    if (kDebugMode) {
      print('[${tag ?? _tag}] ERROR: $message');
    }
  }

  static void log(String message, [String? tag]) {
    if (kDebugMode) {
      print('[${tag ?? _tag}] $message');
    }
  }
}
