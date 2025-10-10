import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogger {
  static const String _tag = 'Aradia';
  static bool _fileLoggingEnabled = true;
  static String? _logFilePath;

  /// Initialize the logger and set up the log file path for Android
  static Future<void> initialize() async {
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final logDir = Directory('${externalDir.path}/log');
        if (!await logDir.exists()) {
          await logDir.create(recursive: true);
        }
        _logFilePath = '${logDir.path}/applogs.txt';
      } else {
        _fileLoggingEnabled = false;
        if (kDebugMode) {
          print('[$_tag] External storage not available');
        }
      }
    } catch (e) {
      _fileLoggingEnabled = false;
      if (kDebugMode) {
        print('[$_tag] Failed to initialize file logging: $e');
      }
    }
  }

  /// Write log to file
  static Future<void> _writeToFile(String logMessage) async {
    if (!_fileLoggingEnabled || _logFilePath == null) return;

    try {
      final file = File(_logFilePath!);
      final timestamp = DateTime.now().toIso8601String();
      final formattedMessage = '[$timestamp] $logMessage\n';
      
      // Append to file
      await file.writeAsString(formattedMessage, mode: FileMode.append);
      
      // Keep log file size manageable (max 1MB)
      final fileSize = await file.length();
      if (fileSize > 1024 * 1024) {
        await _rotateLogFile(file);
      }
    } catch (e) {
      if (kDebugMode) {
        print('[$_tag] Failed to write to log file: $e');
      }
    }
  }

  /// Rotate log file when it gets too large
  static Future<void> _rotateLogFile(File logFile) async {
    try {
      final lines = await logFile.readAsLines();
      // Keep only the last 1000 lines
      final keepLines = lines.length > 1000 ? lines.sublist(lines.length - 1000) : lines;
      await logFile.writeAsString('${keepLines.join('\n')}\n');
    } catch (e) {
      // If rotation fails, just clear the file
      await logFile.writeAsString('');
    }
  }

  /// Get the current log file path
  static String? get logFilePath => _logFilePath;

  /// Clear all logs
  static Future<void> clearLogs() async {
    if (_logFilePath != null) {
      try {
        final file = File(_logFilePath!);
        if (await file.exists()) {
          await file.writeAsString('');
        }
      } catch (e) {
        if (kDebugMode) {
          print('[$_tag] Failed to clear logs: $e');
        }
      }
    }
  }

  static void debug(String message, [String? tag]) {
    final logMessage = '[${tag ?? _tag}] DEBUG: $message';
    if (kDebugMode) {
      print(logMessage);
    }
    _writeToFile(logMessage);
  }

  static void info(String message, [String? tag]) {
    final logMessage = '[${tag ?? _tag}] INFO: $message';
    if (kDebugMode) {
      print(logMessage);
    }
    _writeToFile(logMessage);
  }

  static void warning(String message, [String? tag]) {
    final logMessage = '[${tag ?? _tag}] WARNING: $message';
    if (kDebugMode) {
      print(logMessage);
    }
    _writeToFile(logMessage);
  }

  static void error(String message, [String? tag]) {
    final logMessage = '[${tag ?? _tag}] ERROR: $message';
    if (kDebugMode) {
      print(logMessage);
    }
    _writeToFile(logMessage);
  }

  static void log(String message, [String? tag]) {
    final logMessage = '[${tag ?? _tag}] $message';
    if (kDebugMode) {
      print(logMessage);
    }
    _writeToFile(logMessage);
  }
}
