import 'dart:io';
import 'dart:typed_data';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:saf/saf.dart';
import 'package:aradia/utils/app_logger.dart';

class MediaHelper {
  const MediaHelper._();

  /// Check if file is an audio file
  static Future<bool> isAudioFile(String filePath) async {
    return filePath.endsWith('.mp3') ||
        filePath.endsWith('.m4a') ||
        filePath.endsWith('.m4b') ||
        filePath.endsWith('.aac') ||
        filePath.endsWith('.wav') ||
        filePath.endsWith('.flac') ||
        filePath.endsWith('.ogg') ||
        filePath.endsWith('.opus');
  }

  /// Check if file is an image file
  static Future<bool> isImageFile(String filePath) async {
    return filePath.endsWith('.jpg') ||
        filePath.endsWith('.jpeg') ||
        filePath.endsWith('.png') ||
        filePath.endsWith('.webp') ||
        filePath.endsWith('.bmp');
  }

  /// Get metadata of an audio file using SAF
  static Future<Metadata> getAudioMetadata(
      String filePath, String rootFolderPath) async {
    try {
      AppLogger.info('Attempting SAF sync cache for: $filePath');

      Saf saf = Saf(rootFolderPath);
      bool? result = await saf.sync().timeout(const Duration(seconds: 60));

      if (result == true) {
        String fileName = path.basename(filePath);
        String cacheDir = await _getCacheDirectory();
        String cachedFilePath =
            path.join(cacheDir, 'audiobooks_cache', fileName);

        if (await File(cachedFilePath).exists()) {
          AppLogger.info('File found in sync cache: $cachedFilePath');
          final metadata =
              await MetadataRetriever.fromFile(File(cachedFilePath))
                  .timeout(const Duration(seconds: 10));
          AppLogger.info(
              'Successfully read metadata from cached file: $cachedFilePath');
          return metadata;
        }
      }

      AppLogger.info('Sync cache failed, trying singleCache for: $filePath');
      String? cachePath = await Saf(rootFolderPath)
          .singleCache(
            filePath: filePath,
            directory: rootFolderPath,
          )
          .timeout(const Duration(seconds: 30));

      if (cachePath == null) {
        throw Exception('Failed to cache file: $filePath');
      }

      AppLogger.info(
          'File cached successfully, reading metadata from: $cachePath');
      final metadata = await MetadataRetriever.fromFile(File(cachePath))
          .timeout(const Duration(seconds: 10));
      return metadata;
    } catch (e) {
      AppLogger.error('Metadata reading failed for $filePath: $e');
      AppLogger.info('Returning fallback metadata for: $filePath');
      return Metadata(
        trackName: path.basenameWithoutExtension(filePath),
        albumName: path.basenameWithoutExtension(filePath),
        albumArtistName: 'Unknown',
        trackDuration: null,
        albumArt: null,
        filePath: filePath,
      );
    }
  }

  /// Save album art from metadata as PNG
  static Future<String?> saveAlbumArtFromMetadata(
      Uint8List albumArtData, String baseName) async {
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        AppLogger.error('Failed to get external storage directory');
        return null;
      }

      final coverImagesDir =
          Directory(path.join(externalDir.path, 'localCoverImages'));
      if (!await coverImagesDir.exists()) {
        await coverImagesDir.create(recursive: true);
      }

      final fileName = '${_sanitizeFileName(baseName)}.png';
      final filePath = path.join(coverImagesDir.path, fileName);

      final file = File(filePath);
      await file.writeAsBytes(albumArtData);

      AppLogger.info('Saved album art: $filePath');
      return filePath;
    } catch (e) {
      AppLogger.error('Error saving album art for $baseName: $e');
      return null;
    }
  }

  /// Copy cover image from SAF path to local storage
  static Future<String?> copyCoverImageToLocalStorage(String sourceImagePath,
      String audiobookName, String rootFolderPath) async {
    try {
      AppLogger.info('Copying cover image: $sourceImagePath');

      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        AppLogger.error('Failed to get external storage directory');
        return null;
      }

      final coverImagesDir =
          Directory(path.join(externalDir.path, 'localCoverImages'));
      if (!await coverImagesDir.exists()) {
        await coverImagesDir.create(recursive: true);
      }

      String originalExtension = path.extension(sourceImagePath);
      String fileName = '${_sanitizeFileName(audiobookName)}$originalExtension';
      String localFilePath = path.join(coverImagesDir.path, fileName);

      if (await File(localFilePath).exists()) {
        AppLogger.info('Cover image already exists: $localFilePath');
        return localFilePath;
      }

      String? cachedImagePath = await Saf(rootFolderPath)
          .singleCache(
            filePath: sourceImagePath,
            directory: rootFolderPath,
          )
          .timeout(const Duration(seconds: 30));

      if (cachedImagePath == null) {
        AppLogger.error('Failed to cache source image: $sourceImagePath');
        return null;
      }

      final sourceFile = File(cachedImagePath);

      if (await sourceFile.exists()) {
        await sourceFile.copy(localFilePath);
        AppLogger.info('Successfully copied cover image to: $localFilePath');
        return localFilePath;
      } else {
        AppLogger.error('Cached source file does not exist: $cachedImagePath');
        return null;
      }
    } catch (e) {
      AppLogger.error('Error copying cover image for $audiobookName: $e');
      return null;
    }
  }

  /// Calculate total duration from multiple audio files
  static Future<Duration?> calculateTotalDuration(
      List<String> audioFiles, String rootFolderPath) async {
    try {
      int totalMilliseconds = 0;

      for (String audioFile in audioFiles) {
        try {
          final metadata = await getAudioMetadata(audioFile, rootFolderPath);
          if (metadata.trackDuration != null) {
            totalMilliseconds += metadata.trackDuration!;
          }
        } catch (e) {
          AppLogger.error('Error getting metadata for $audioFile: $e');
        }
      }

      return totalMilliseconds > 0
          ? Duration(milliseconds: totalMilliseconds)
          : null;
    } catch (e) {
      AppLogger.error('Error calculating total duration: $e');
      return null;
    }
  }

  /// Sanitize filename for safe storage
  static String _sanitizeFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();
  }

  /// Get cache directory
  static Future<String> _getCacheDirectory() async {
    final externalDir = await getExternalStorageDirectory();
    return externalDir?.path ?? '';
  }

  static String decodePath(String s) {
    if (s.isEmpty) return s;
    try {
      if (s.startsWith('file://')) return Uri.parse(s).toFilePath();
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  static bool looksLocal(String s) =>
      s.startsWith('file://') ||
      s.startsWith('/') ||
      (s.contains(':/') && !s.startsWith('http'));

  static String? asLocalPath(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      if (s.startsWith('file://')) return Uri.parse(s).toFilePath();
      if (s.startsWith('/')) return s;
      if (s.contains(':/') && !s.startsWith('http')) return s;
    } catch (_) {}
    return null;
  }

  /// True if a LocalAudiobook should be treated as a single-file "book".
  static bool isSingleFileBook(LocalAudiobook a) => a.audioFiles.length == 1;

  /// Canonical per-book key:
  /// - Single-file books → absolute file path
  /// - Multi-track books → absolute folder path
  static String bookKeyForLocal(LocalAudiobook a) {
    final files = a.audioFiles.map(decodePath).toList();
    if (files.length == 1) return files.first;
    return decodePath(a.folderPath);
  }

  /// For a history item, returns the first track's absolute local path (if any).
  static String? firstTrackLocalPath(HistoryOfAudiobookItem item) {
    if (item.audiobookFiles.isEmpty) return null;
    final raw = item.audiobookFiles.first.url ?? '';
    final local = asLocalPath(raw) ?? decodePath(raw);
    return local.isEmpty ? null : local;
  }

  /// For multi-track: folder that holds the tracks; for single-file: the
  /// file’s parent directory.
  static String? bookFolderFromHistory(HistoryOfAudiobookItem item) {
    final first = firstTrackLocalPath(item);
    return first == null ? null : path.dirname(first);
  }

  /// Allowed image extensions (case-insensitive).
  static const Set<String> kImageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp'
  };

  /// Filenames we consider “more likely to be the intended cover”, checked in
  /// order of preference (no extension, case-insensitive).
  static const List<String> kPreferredCoverBasenames = [
    'cover',
    'folder',
    'front',
    'album',
    'art',
    'book',
  ];

  /// Convert Directory path to URI String with proper handling of spaces and special characters
  /// This is a fixed version of the SAF package's makeUriString function
  static String makeSafUriFromPath(String inputPath) {
    String rel = inputPath;
    const androidPrefix = '/storage/emulated/0/';
    if (rel.startsWith(androidPrefix)) {
      rel = rel.substring(androidPrefix.length);
    }
    rel = rel.replaceAll(RegExp(r'^/+'), '');
    final segments = rel.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw ArgumentError('Path is empty after normalization');
    }

    final treeRoot = Uri.encodeComponent(segments.first);

    final encodedSegments =
        segments.map((s) => Uri.encodeComponent(s)).join('%2F');

    const base = 'content://com.android.externalstorage.documents/';
    final treeUri = '${base}tree/primary%3A$treeRoot';
    return '$treeUri/document/primary%3A$encodedSegments';
  }

  /// Find cover image with same name as audio file
  static Future<String?> findCoverImageForAudioFile(
      String audioFilePath, String rootFolderPath) async {
    try {
      final audioFileName = path.basenameWithoutExtension(audioFilePath);
      final audioFileDir = path.dirname(audioFilePath);

      for (String ext in kImageExtensions) {
        final potentialCoverPath =
            path.join(audioFileDir, '$audioFileName$ext');

        final files = await Saf.getFilesPathFor(rootFolderPath);
        if (files != null && files.contains(potentialCoverPath)) {
          AppLogger.info('Found cover image: $potentialCoverPath');

          String? localCoverPath =
              await MediaHelper.copyCoverImageToLocalStorage(
                  potentialCoverPath, audioFileName, rootFolderPath);

          return localCoverPath;
        }
      }

      AppLogger.info('No cover image found for: $audioFileName');
      return null;
    } catch (e) {
      AppLogger.error('Error finding cover image for $audioFilePath: $e');
      return null;
    }
  }

  /// Find cover image in a folder with specific logic
  static Future<String?> findCoverImageInFolder(List<String> filesInFolder,
      String folderName, String rootFolderPath) async {
    try {
      List<String> imageFiles = [];
      for (String filePath in filesInFolder) {
        if (await MediaHelper.isImageFile(filePath)) {
          imageFiles.add(filePath);
        }
      }

      if (imageFiles.isEmpty) {
        AppLogger.info('No image files found in folder: $folderName');
        return null;
      }

      String? selectedImagePath;

      if (imageFiles.length == 1) {
        AppLogger.info('Found single cover image: ${imageFiles.first}');
        selectedImagePath = imageFiles.first;
      } else {
        for (String preferredName in kPreferredCoverBasenames) {
          for (String imageFile in imageFiles) {
            String fileName =
                path.basenameWithoutExtension(imageFile).toLowerCase();
            if (fileName == preferredName) {
              AppLogger.info('Found preferred cover image: $imageFile');
              selectedImagePath = imageFile;
              break;
            }
          }
          if (selectedImagePath != null) break;
        }

        if (selectedImagePath == null) {
          AppLogger.info(
              'No preferred cover name found, using first image: ${imageFiles.first}');
          selectedImagePath = imageFiles.first;
        }
      }

      String? localCoverPath = await MediaHelper.copyCoverImageToLocalStorage(
          selectedImagePath, folderName, rootFolderPath);

      return localCoverPath;
    } catch (e) {
      AppLogger.error('Error finding cover image in folder $folderName: $e');
      return null;
    }
  }

  /// Extract cover from audio file metadata
  static Future<String?> extractCoverFromAudioMetadata(
      String audioFilePath, String rootFolderPath, String baseName) async {
    try {
      final metadata =
          await MediaHelper.getAudioMetadata(audioFilePath, rootFolderPath);

      if (metadata.albumArt != null) {
        return await MediaHelper.saveAlbumArtFromMetadata(
            metadata.albumArt!, baseName);
      }

      AppLogger.info('No album art found in metadata for: $baseName');
      return null;
    } catch (e) {
      AppLogger.error('Error extracting cover from metadata for $baseName: $e');
      return null;
    }
  }

  /// Capitalize words (e.g., "art of war" -> "Art Of War")
  static String capitalizeWords(String text) {
    if (text.isEmpty) return text;

    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
