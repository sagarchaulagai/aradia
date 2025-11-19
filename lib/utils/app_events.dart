import 'dart:async';

class AppEvents {
  /// Fire when visible languages change. Listeners should refresh their data.
  static final languagesChanged = StreamController<void>.broadcast();

  /// Fire when local audiobooks directory changes. Listeners should refresh their data.
  static final localDirectoryChanged = StreamController<void>.broadcast();

  static void dispose() {
    languagesChanged.close();
    localDirectoryChanged.close();
  }
}
