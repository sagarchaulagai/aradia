import 'dart:async';
import 'package:flutter/foundation.dart';

class OptimizedTimer {
  Timer? _timer;
  final ValueNotifier<bool> _isActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Duration?> _remainingTimeNotifier =
      ValueNotifier<Duration?>(null);

  VoidCallback? _onExpired;
  VoidCallback? _onCanceled;

  /// Whether the timer is currently active
  ValueListenable<bool> get isActive => _isActiveNotifier;

  /// Remaining time in the timer
  ValueListenable<Duration?> get remainingTime => _remainingTimeNotifier;

  /// Start a new timer with the specified duration
  void start({
    required Duration duration,
    VoidCallback? onExpired,
    VoidCallback? onCanceled,
  }) {
    // Cancel any existing timer
    cancel();

    _onExpired = onExpired;
    _onCanceled = onCanceled;

    // Set initial state
    _isActiveNotifier.value = true;
    _remainingTimeNotifier.value = duration;

    // Start the periodic timer
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentDuration = _remainingTimeNotifier.value;
      if (currentDuration == null) {
        timer.cancel();
        return;
      }

      final newDuration = currentDuration - const Duration(seconds: 1);

      if (newDuration.inSeconds <= 0) {
        // Timer expired
        timer.cancel();
        _timer = null;
        _isActiveNotifier.value = false;
        _remainingTimeNotifier.value = null;
        _onExpired?.call();
      } else {
        // Update remaining time
        _remainingTimeNotifier.value = newDuration;
      }
    });
  }

  /// Cancel the current timer
  void cancel() {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
      _isActiveNotifier.value = false;
      _remainingTimeNotifier.value = null;
      _onCanceled?.call();
    }
  }

  /// Get remaining time as formatted string (MM:SS)
  String get formattedRemainingTime {
    final duration = _remainingTimeNotifier.value;
    if (duration == null) return '00:00';

    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Dispose of resources
  void dispose() {
    cancel();
    _isActiveNotifier.dispose();
    _remainingTimeNotifier.dispose();
  }
}

/// Extension to provide common timer durations
extension TimerDurations on OptimizedTimer {
  static const Duration fifteenMinutes = Duration(minutes: 15);
  static const Duration thirtyMinutes = Duration(minutes: 30);
  static const Duration fortyFiveMinutes = Duration(minutes: 45);
  static const Duration oneHour = Duration(minutes: 60);
  static const Duration ninetyMinutes = Duration(minutes: 90);
  
  /// Special duration to indicate end-of-track timer
  static const Duration endOfTrack = Duration(milliseconds: -1);
}
