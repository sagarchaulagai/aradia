import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

const String _base = "https://archive.org/download";

class AudiobookFile {
  final String? identifier;
  final String? title;
  final String? name;
  final String? url;
  final double? length; // second unit
  final int? track;
  final int? size;
  final String? highQCoverImage;

  AudiobookFile.fromJson(Map json)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = "$_base/${json['identifier']}/${json['name']}",
        highQCoverImage =
            "$_base/${json['identifier']}/${json["highQCoverImage"]}";

  AudiobookFile.fromYoutubeJson(Map json)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = json["url"]?.toString(),
        highQCoverImage = json["highQCoverImage"]?.toString();

  AudiobookFile.fromLocalJson(Map json, String location)
      : identifier = json["identifier"]?.toString(),
        title = json["title"]?.toString(),
        name = json["name"]?.toString(),
        track = _parseTrack(json["track"]),
        size = _parseIntSafely(json["size"]),
        length = _parseDoubleSafely(json["length"]),
        url = location + "/" + json["url"]!.toString(),
        highQCoverImage = location + "/cover.jpg";

  static int _parseTrack(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;

    try {
      final trackStr = value.toString();
      return int.parse(trackStr.split("/")[0]);
    } catch (e) {
      print('Error parsing track value: $value, error: $e');
      return 0;
    }
  }

  static int _parseIntSafely(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;

    try {
      return int.parse(value.toString());
    } catch (e) {
      print('Error parsing int value: $value, error: $e');
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
      print('Error parsing double value: $value, error: $e');
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
        print('Error parsing file at index $i: $e');
        print('Data: ${jsonFiles[i]}');
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
    };
  }

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
      files
          .sort((a, b) => a.statSync().changed.compareTo(b.statSync().changed));

      debugPrint('Now the files are going to be parsed from the downloaded files');

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
            "length": duration, // Use the actual audio file length
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
      debugPrint('Unexpected error: $e');
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
        print('JSON list length: ${jsonContent.length}');
        if (jsonContent.isNotEmpty) {
          print('First item sample fields:');
          final item = jsonContent[0];
          if (item is Map) {
            item.forEach((key, value) {
              print('  $key: $value (${value.runtimeType})');
            });
          }
        }
      }

      final List<AudiobookFile> audiobookFiles =
          AudiobookFile.fromLocalJsonArray(jsonContent, downloadDir.path);
      return Right(audiobookFiles);
    } catch (e) {
      print('Unexpected error: $e');
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
        print('JSON list length: ${jsonContent.length}');
        if (jsonContent.isNotEmpty) {
          print('First item sample fields:');
          final item = jsonContent[0];
          if (item is Map) {
            item.forEach((key, value) {
              print('  $key: $value (${value.runtimeType})');
            });
          }
        }
      }

      final List<AudiobookFile> audiobookFiles =
          AudiobookFile.fromYoutubeJsonArray(jsonContent);
      return Right(audiobookFiles);
    } catch (e) {
      print('Unexpected error: $e');
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
        highQCoverImage = map["highQCoverImage"];

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
    };
  }
}
