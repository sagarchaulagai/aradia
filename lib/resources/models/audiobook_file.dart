import 'dart:io';

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
      : identifier = json["identifier"],
        title = json["title"],
        name = json["name"],
        track = int.parse(json["track"].toString().split("/")[0]),
        size = int.parse(json["size"]),
        length = double.parse(json["length"]),
        url = "$_base/${json['identifier']}/${json['name']}",
        highQCoverImage =
            "$_base/${json['identifier']}/${json["highQCoverImage"]}";

  static List<AudiobookFile> fromJsonArray(List jsonFiles) {
    List<AudiobookFile> audiobookFiles = <AudiobookFile>[];
    for (var jsonFile in jsonFiles) {
      audiobookFiles.add(AudiobookFile.fromJson(jsonFile));
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
      final downloadDir = Directory('${appDir?.path}/$audiobookId');

      // Get all MP3 files in the directory sorted by date
      List<FileSystemEntity> files = downloadDir
          .listSync()
          .where((file) => file.path.endsWith('.mp3'))
          .toList();
      files
          .sort((a, b) => a.statSync().changed.compareTo(b.statSync().changed));

      print('Now the files are going to be parsed from the downloaded files');

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
