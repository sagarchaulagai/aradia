import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as path;
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/utils/app_logger.dart';

class LocalAudiobookService {
  static const String _rootFolderKey = 'local_audiobooks_root_folder';
  static const String _audiobooksBoxName = 'local_audiobooks';

  // Supported audio file extensions
  static const List<String> _supportedAudioExtensions = [
    '.mp3',
    '.m4a',
    '.m4b',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.opus'
  ];

  // Supported image file extensions for cover images
  static const List<String> _supportedImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp'
  ];

  // Get the root folder path from Hive
  static Future<String?> getRootFolderPath() async {
    final box = await Hive.openBox('settings');
    return box.get(_rootFolderKey);
  }

  // Set the root folder path in Hive
  static Future<void> setRootFolderPath(String path) async {
    final box = await Hive.openBox('settings');
    await box.put(_rootFolderKey, path);
  }

  // Get all local audiobooks from Hive
  static Future<List<LocalAudiobook>> getAllAudiobooks() async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      final List<LocalAudiobook> audiobooks = [];

      for (final key in box.keys) {
        final map = Map<String, dynamic>.from(box.get(key));
        audiobooks.add(LocalAudiobook.fromMap(map));
      }

      return audiobooks;
    } catch (e) {
      AppLogger.error('Error getting audiobooks from Hive: $e');
      return [];
    }
  }

  // Save audiobook to Hive
  static Future<void> saveAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.put(audiobook.id, audiobook.toMap());
    } catch (e) {
      AppLogger.error('Error saving audiobook to Hive: $e');
    }
  }

  // Update audiobook in Hive
  static Future<void> updateAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.put(audiobook.id, audiobook.toMap());
    } catch (e) {
      AppLogger.error('Error updating audiobook in Hive: $e');
    }
  }

  // Delete audiobook from Hive
  static Future<void> deleteAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.delete(audiobook.id);
    } catch (e) {
      AppLogger.error('Error deleting audiobook from Hive: $e');
    }
  }

  // Scan the root folder for audiobooks
  static Future<List<LocalAudiobook>> scanForAudiobooks() async {
    final rootPath = await getRootFolderPath();
    if (rootPath == null) return [];

    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return [];

    final List<LocalAudiobook> audiobooks = [];

    try {
      await for (final entity in rootDir.list()) {
        if (entity is Directory) {
          final audiobook = await _scanAudiobookFolder(entity);
          if (audiobook != null) {
            audiobooks.add(audiobook);
          }
        }
      }
    } catch (e) {
      AppLogger.error('Error scanning for audiobooks: $e');
    }

    return audiobooks;
  }

  // Scan a single folder for audiobook content
  static Future<LocalAudiobook?> _scanAudiobookFolder(Directory folder) async {
    try {
      final List<String> audioFiles = [];
      String? coverImagePath;

      // Check if folder has subfolders (Author/Title structure)
      final List<Directory> subDirs = [];
      await for (final entity in folder.list()) {
        if (entity is Directory) {
          subDirs.add(entity);
        }
      }

      Directory targetDir = folder;
      String folderName = path.basename(folder.path);
      String author = 'Unknown';
      String title = folderName;

      // If there are subdirectories, check if it follows Author/Title structure
      if (subDirs.isNotEmpty) {
        // Assume first subdirectory contains the audiobook
        targetDir = subDirs.first;
        author = folderName;
        title = path.basename(targetDir.path);
      }

      // Scan the target directory for audio files and cover image
      await for (final entity in targetDir.list()) {
        if (entity is File) {
          final extension = path.extension(entity.path).toLowerCase();

          if (_supportedAudioExtensions.contains(extension)) {
            audioFiles.add(entity.path);
          } else if (_supportedImageExtensions.contains(extension)) {
            final fileName =
                path.basenameWithoutExtension(entity.path).toLowerCase();
            // Look for common cover image names
            if (fileName.contains('cover') ||
                fileName.contains('folder') ||
                fileName.contains('front') ||
                fileName == 'artwork' ||
                coverImagePath == null) {
              coverImagePath = entity.path;
            }
          }
        }
      }

      // Only create audiobook if we found audio files
      if (audioFiles.isNotEmpty) {
        audioFiles.sort(); // Sort audio files alphabetically

        return LocalAudiobook(
          id: '${author}_${title}_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          author: author,
          folderPath: targetDir.path,
          coverImagePath: coverImagePath,
          audioFiles: audioFiles,
          dateAdded: DateTime.now(),
          lastModified: DateTime.now(),
        );
      }
    } catch (e) {
      AppLogger.error('Error scanning audiobook folder ${folder.path}: $e');
    }

    return null;
  }

  // Refresh audiobooks by scanning and updating the database
  static Future<List<LocalAudiobook>> refreshAudiobooks() async {
    try {
      // Scan for new audiobooks
      final scannedAudiobooks = await scanForAudiobooks();

      // Clear existing audiobooks from database

      // Clear existing audiobooks and add scanned ones
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.clear();

      for (final audiobook in scannedAudiobooks) {
        await box.put(audiobook.id, audiobook.toMap());
      }

      return scannedAudiobooks;
    } catch (e) {
      AppLogger.error('Error refreshing audiobooks: $e');
      return [];
    }
  }

  // Move audiobook folder when metadata changes
  static Future<bool> moveAudiobookFolder(
      LocalAudiobook audiobook, String newAuthor, String newTitle) async {
    try {
      final rootPath = await getRootFolderPath();
      if (rootPath == null) return false;

      final currentDir = Directory(audiobook.folderPath);
      if (!await currentDir.exists()) {
        AppLogger.error(
            'Source directory does not exist: ${audiobook.folderPath}');
        return false;
      }

      final newPath = path.join(rootPath, newAuthor, newTitle);
      final newDir = Directory(newPath);

      // If the new path is the same as current path, no need to move
      if (currentDir.path == newDir.path) {
        return true;
      }

      // Create new directory structure
      await newDir.create(recursive: true);

      // Move all files from old directory to new directory
      final List<File> filesToMove = [];
      await for (final entity in currentDir.list()) {
        if (entity is File && await entity.exists()) {
          filesToMove.add(entity);
        }
      }

      // Copy files to new location using read/write to avoid permission issues
      for (final file in filesToMove) {
        try {
          final newFilePath = path.join(newPath, path.basename(file.path));
          final fileBytes = await file.readAsBytes();
          final newFile = File(newFilePath);
          await newFile.writeAsBytes(fileBytes);
          AppLogger.debug('Copied ${file.path} to $newFilePath');
        } catch (e) {
          AppLogger.error('Error copying file ${file.path}: $e');
          // Continue with other files instead of failing completely
          continue;
        }
      }

      // Delete original files only after successful copy
      for (final file in filesToMove) {
        try {
          if (await file.exists()) {
            await file.delete();
            AppLogger.debug('Deleted original file: ${file.path}');
          }
        } catch (e) {
          AppLogger.error('Error deleting original file ${file.path}: $e');
          // Continue with other files even if one fails
        }
      }

      // Remove old directory if empty
      try {
        if (await currentDir.exists() && await _isDirectoryEmpty(currentDir)) {
          await currentDir.delete();
          AppLogger.debug('Deleted empty directory: ${currentDir.path}');

          // Also try to remove parent directory if it's empty
          final parentDir = currentDir.parent;
          if (await parentDir.exists() && await _isDirectoryEmpty(parentDir)) {
            await parentDir.delete();
            AppLogger.debug(
                'Deleted empty parent directory: ${parentDir.path}');
          }
        }
      } catch (e) {
        AppLogger.debug('Could not remove old directory: $e');
      }

      return true;
    } catch (e) {
      AppLogger.error('Error moving audiobook folder: $e');
      return false;
    }
  }

  // Check if directory is empty
  static Future<bool> _isDirectoryEmpty(Directory dir) async {
    try {
      return await dir.list().isEmpty;
    } catch (e) {
      return false;
    }
  }

  // Get total duration of all audio files in an audiobook
  static Future<Duration?> calculateTotalDuration(
      List<String> audioFiles) async {
    // This would require a media metadata library to get actual durations
    // For now, return null and implement later if needed
    return null;
  }
}
