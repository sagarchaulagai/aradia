import 'dart:convert';
import 'dart:io';

import 'package:aradia/utils/app_logger.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

const String _base = "https://archive.org/download";

class AudiobookFile {
  final String? identifier;
  final String? title;
  final String? name;
  final String? url;
  final double? length; // seconds
  final int? track;
  final int? size;
  final String? highQCoverImage;

  /// NEW: optional chapter slicing for a single physical file
  final int? startMs;    // chapter start (ms from file start)
  final int? durationMs; // chapter duration (ms); null => to EOF

  // ────────────────────────────────────────────────────────────────────────────
  // Constructors for existing sources
  // ────────────────────────────────────────────────────────────────────────────

  AudiobookFile.fromJson(Map json)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = "$_base/${json['identifier']}/${json['name']}",
        highQCoverImage =
        "$_base/${json['identifier']}/${json["highQCoverImage"]}",
        startMs = null,
        durationMs = null;

  AudiobookFile.fromYoutubeJson(Map json)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = json["url"]?.toString(),
        highQCoverImage = json["highQCoverImage"]?.toString(),
        startMs = null,
        durationMs = null;

  AudiobookFile.fromLocalJson(Map json, String location)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = "$location/${json["url"]!}",
        highQCoverImage = "$location/cover.jpg",
        startMs = null,
        durationMs = null;

  /// NEW: convenient factory for a chapter slice of a single-file book
  static AudiobookFile chapterSlice({
    required String identifier,
    required String url,
    required String parentTitle,
    required int track,
    required String chapterTitle,
    required int startMs,
    int? durationMs,
    String? highQCoverImage,
  }) {
    return AudiobookFile.fromMap({
      "identifier": identifier,
      "title": chapterTitle.isNotEmpty ? chapterTitle : "$parentTitle — Chapter $track",
      "name": parentTitle,
      "track": track,
      "size": 0,
      "length": null, // player derives effective length via ClippingAudioSource
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Parsing helpers
  // ────────────────────────────────────────────────────────────────────────────

  static int _parseTrack(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;

    try {
      final trackStr = value.toString();
      return int.parse(trackStr.split("/")[0]);
    } catch (e) {
      AppLogger.debug('Error parsing track value: $value, error: $e');
      return 0;
    }
  }

  static int _parseIntSafely(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;

    try {
      return int.parse(value.toString());
    } catch (e) {
      AppLogger.debug('Error parsing int value: $value, error: $e');
      return 0;
    }
  }

  static double _parseDoubleSafely(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();

    try {
      return double.parse(value.toString());
    } catch (e) {
      AppLogger.debug('Error parsing double value: $value, error: $e');
      return 0.0;
    }
  }

  static List<AudiobookFile> fromJsonArray(List jsonFiles) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      try {
        var jsonFile = jsonFiles[i];
        audiobookFiles.add(AudiobookFile.fromJson(jsonFile));
      } catch (e) {
        AppLogger.debug('Error parsing file at index $i: $e');
        AppLogger.debug('Data: ${jsonFiles[i]}');
      }
    }
    return audiobookFiles;
  }

  static List<AudiobookFile> fromLocalJsonArray(
      List jsonFiles, String location) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      audiobookFiles.add(AudiobookFile.fromLocalJson(jsonFiles[i], location));
    }
    return audiobookFiles;
  }

  static List<AudiobookFile> fromYoutubeJsonArray(List jsonFiles) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var i = 0; i < jsonFiles.length; i++) {
      audiobookFiles.add(AudiobookFile.fromYoutubeJson(jsonFiles[i]));
    }
    return audiobookFiles;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Disk discovery helpers (unchanged behavior)
  // ────────────────────────────────────────────────────────────────────────────

  static Future<Either<String, List<AudiobookFile>>> fromDownloadedFiles(
      String audiobookId) async {
    try {
      final appDir = await getExternalStorageDirectory();
      final downloadDir = Directory('${appDir?.path}/downloads/$audiobookId');

      // Get all MP3 files in the directory sorted by date
      List<FileSystemEntity> files = downloadDir
          .listSync()
          .where((file) => file.path.endsWith('.mp3'))
          .toList();
      files.sort(
            (a, b) => a.statSync().changed.compareTo(b.statSync().changed),
      );

      AppLogger.debug(
          'Now the files are going to be parsed from the downloaded files');

      List<AudiobookFile> audiobookFiles = <AudiobookFile>[];

      for (var i = 0; i < files.length; i++) {
        final player = AudioPlayer();
        try {
          await player.setFilePath(files[i].path);
          final duration = player.duration?.inSeconds.toDouble() ?? 0.0;

          audiobookFiles.add(AudiobookFile.fromMap({
            "identifier": audiobookId,
            "title": files[i].path.split('/').last.split('.').first,
            "name": files[i].path.split('/').last,
            "track": i + 1,
            "size": files[i].statSync().size,
            "length": duration,
            "url": files[i].path,
            "highQCoverImage":
            'https://archive.org/services/get-item-image.php?identifier=$audiobookId',
          }));
        } finally {
          await player.dispose();
        }
      }

      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  static Future<Either<String, List<AudiobookFile>>> fromLocalFiles(
      String audiobookId) async {
    try {
      final appDir = await getExternalStorageDirectory();
      final downloadDir = Directory('${appDir?.path}/local/$audiobookId');

      final stringContent =
      await File('${downloadDir.path}/files.txt').readAsString();
      final jsonContent = jsonDecode(stringContent);
      if (jsonContent is List) {
        AppLogger.debug('JSON list length: ${jsonContent.length}');
        if (jsonContent.isNotEmpty) {
          AppLogger.debug('First item sample fields:');
          final item = jsonContent[0];
          if (item is Map) {
            item.forEach((key, value) {
              AppLogger.debug('  $key: $value (${value.runtimeType})');
            });
          }
        }
      }

      final List<AudiobookFile> audiobookFiles =
      AudiobookFile.fromLocalJsonArray(jsonContent, downloadDir.path);
      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  static Future<Either<String, List<AudiobookFile>>> fromYoutubeFiles(
      String audiobookId) async {
    try {
      final appDir = await getExternalStorageDirectory();
      final downloadDir = Directory('${appDir?.path}/youtube/$audiobookId');

      final stringContent =
      await File('${downloadDir.path}/files.txt').readAsString();
      final jsonContent = jsonDecode(stringContent);
      if (jsonContent is List) {
        AppLogger.debug('JSON list length: ${jsonContent.length}');
        if (jsonContent.isNotEmpty) {
          AppLogger.debug('First item sample fields:');
          final item = jsonContent[0];
          if (item is Map) {
            item.forEach((key, value) {
              AppLogger.debug('  $key: $value (${value.runtimeType})');
            });
          }
        }
      }

      final List<AudiobookFile> audiobookFiles =
      AudiobookFile.fromYoutubeJsonArray(jsonContent);
      return Right(audiobookFiles);
    } catch (e) {
      AppLogger.debug('Unexpected error: $e');
      return Left('Unexpected error: $e');
    }
  }

  // TODO Fix the toMap and fromMap so that we can use it by Hive without the error
  AudiobookFile.fromMap(Map<dynamic, dynamic> map)
      : identifier = map["identifier"],
        title = map["title"],
        name = map["name"],
        track = map["track"],
        size = map["size"],
        length = map["length"],
        url = map["url"],
        highQCoverImage = map["highQCoverImage"],
        startMs = map["startMs"],
        durationMs = map["durationMs"];

  Map<dynamic, dynamic> toMap() {
    return {
      "identifier": identifier,
      "title": title,
      "name": name,
      "track": track,
      "size": size,
      "length": length,
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      "identifier": identifier,
      "title": title,
      "name": name,
      "track": track,
      "size": size,
      "length": length,
      "url": url,
      "highQCoverImage": highQCoverImage,
      "startMs": startMs,
      "durationMs": durationMs,
    };
  }
}
