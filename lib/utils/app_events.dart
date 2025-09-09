// lib/utils/app_events.dart
import 'dart:async';

class AppEvents {
  /// Fire when visible languages change. Listeners should refresh their data.
  static final languagesChanged = StreamController<void>.broadcast();

  static void dispose() {
    languagesChanged.close();
  }
}
