import 'package:flutter/foundation.dart' show immutable;

@immutable
class AppConstants {
  const AppConstants._(); 

  static const String youtubeDirName = 'youtube';
  static const String localDirName = 'local';

  static const List<String> supportedAudioExtensions = [
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
    '.flac',
  ];
}