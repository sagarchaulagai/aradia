import 'dart:math';
import 'package:flutter/foundation.dart' show immutable;

@immutable
class StringHelper {
  const StringHelper._();

  static String generateRandomId({int length = 10}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)])
        .join();
  }
}