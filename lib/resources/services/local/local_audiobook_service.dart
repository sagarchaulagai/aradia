import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:saf/saf.dart';
// ignore: implementation_imports
import 'package:saf/src/storage_access_framework/api.dart';
import 'package:path/path.dart' as path;

class LocalAudiobookService {
  static const String _rootFolderKey = 'local_audiobooks_root_folder';
  static const String _audiobooksBoxName = 'local_audiobooks';
  static const String _fileCacheBoxName = 'local_audiobooks_file_cache';

  static Future<String?> getRootFolderPath() async {
    final box = await Hive.openBox('settings');
    return box.get(_rootFolderKey);
  }

  static Future<void> setRootFolderPath(String p) async {
    final box = await Hive.openBox('settings');
    await box.put(_rootFolderKey, p);
  }

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

  static Future<void> saveAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.put(audiobook.id, audiobook.toMap());
    } catch (e) {
      AppLogger.error('Error saving audiobook to Hive: $e');
    }
  }

  static Future<void> updateAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.put(audiobook.id, audiobook.toMap());
    } catch (e) {
      AppLogger.error('Error updating audiobook in Hive: $e');
    }
  }

  static Future<void> deleteAudiobook(LocalAudiobook audiobook) async {
    try {
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.delete(audiobook.id);
    } catch (e) {
      AppLogger.error('Error deleting audiobook from Hive: $e');
    }
  }

  /// Get the last scanned file paths from cache
  static Future<List<String>?> getLastScannedFiles() async {
    try {
      final box = await Hive.openBox(_fileCacheBoxName);
      final cacheData = box.get('file_cache');
      if (cacheData != null) {
        final map = Map<String, dynamic>.from(cacheData);
        return List<String>.from(map['file_paths'] ?? []);
      }
      return null;
    } catch (e) {
      AppLogger.error('Error getting last scanned files from cache: $e');
      return null;
    }
  }

  /// Save the scanned file paths to cache
  static Future<void> saveScannedFiles(List<String> files) async {
    try {
      final box = await Hive.openBox(_fileCacheBoxName);
      final cacheData = {
        'file_paths': files,
        'last_scan_time': DateTime.now().millisecondsSinceEpoch,
      };
      await box.put('file_cache', cacheData);
    } catch (e) {
      AppLogger.error('Error saving scanned files to cache: $e');
    }
  }

  /// Clear the file cache (useful when changing root folder)
  static Future<void> clearFileCache() async {
    try {
      final box = await Hive.openBox(_fileCacheBoxName);
      await box.clear();
    } catch (e) {
      AppLogger.error('Error clearing file cache: $e');
    }
  }

  /// Clear all audiobook caches (useful when changing root folder)
  static Future<void> clearAllCaches() async {
    try {
      // Clear file cache
      await clearFileCache();

      // Clear audiobooks cache
      final audiobooksBox = await Hive.openBox(_audiobooksBoxName);
      await audiobooksBox.clear();

      AppLogger.info('Cleared all audiobook caches');
    } catch (e) {
      AppLogger.error('Error clearing all caches: $e');
    }
  }

  static Future<List<LocalAudiobook>> refreshAudiobooks() async {
    try {
      final scanned = await scanForAudiobooks();
      final box = await Hive.openBox(_audiobooksBoxName);
      await box.clear();
      for (final a in scanned) {
        await box.put(a.id, a.toMap());
      }
      return scanned;
    } catch (e) {
      AppLogger.error('Error refreshing audiobooks: $e');
      return [];
    }
  }

  /// Smart refresh that only processes changed files
  static Future<List<LocalAudiobook>> smartRefreshAudiobooks() async {
    try {
      final rootFolderPath = await getRootFolderPath();
      if (rootFolderPath == null) {
        AppLogger.error('Root folder path is null');
        return [];
      }

      // Get current file list from SAF
      List<String>? currentFiles = await Saf.getFilesPathFor(rootFolderPath);
      if (currentFiles == null) {
        AppLogger.error('Failed to get files from root folder');
        return [];
      }

      // Get cached file list
      List<String>? cachedFiles = await getLastScannedFiles();

      // If no cache exists, do a full scan
      if (cachedFiles == null) {
        AppLogger.info('No cache found, performing full scan');
        final scanned = await scanForAudiobooks();
        AppLogger.info(
            'Full scan completed, found ${scanned.length} audiobooks');
        await saveScannedFiles(currentFiles);

        // Save all audiobooks to Hive
        final box = await Hive.openBox(_audiobooksBoxName);
        await box.clear();
        for (final audiobook in scanned) {
          await box.put(audiobook.id, audiobook.toMap());
        }
        AppLogger.info('Saved ${scanned.length} audiobooks to Hive');

        return scanned;
      }

      // Compare file lists to detect changes
      Set<String> currentFileSet = currentFiles.toSet();
      Set<String> cachedFileSet = cachedFiles.toSet();

      Set<String> newFiles = currentFileSet.difference(cachedFileSet);
      Set<String> deletedFiles = cachedFileSet.difference(currentFileSet);
      Set<String> changedFiles = newFiles.union(deletedFiles);

      AppLogger.info(
          'File changes detected: ${newFiles.length} new, ${deletedFiles.length} deleted');

      if (newFiles.isNotEmpty) {
        AppLogger.info(
            'New files: ${newFiles.take(5).join(', ')}${newFiles.length > 5 ? '...' : ''}');
      }
      if (deletedFiles.isNotEmpty) {
        AppLogger.info(
            'Deleted files: ${deletedFiles.take(5).join(', ')}${deletedFiles.length > 5 ? '...' : ''}');
      }

      // If no changes, return cached audiobooks
      if (changedFiles.isEmpty) {
        AppLogger.info('No file changes detected, returning cached audiobooks');
        await saveScannedFiles(currentFiles); // Update scan time
        return await getAllAudiobooks();
      }

      // Get affected audiobook IDs
      Set<String> affectedIds =
          _getAffectedAudiobookIds(changedFiles.toList(), rootFolderPath);
      AppLogger.info('Affected audiobook IDs: ${affectedIds.length}');
      if (affectedIds.isNotEmpty) {
        AppLogger.info('Affected IDs: ${affectedIds.join(', ')}');
      }

      // Get all current audiobooks from cache
      List<LocalAudiobook> allAudiobooks = await getAllAudiobooks();
      Map<String, LocalAudiobook> audiobookMap = {
        for (var a in allAudiobooks) a.id: a
      };

      // Remove deleted audiobooks
      for (String deletedFile in deletedFiles) {
        String? audiobookId =
            _getAudiobookIdForFile(deletedFile, rootFolderPath);
        if (audiobookId != null && audiobookMap.containsKey(audiobookId)) {
          // Check if this was the last file in the audiobook
          LocalAudiobook audiobook = audiobookMap[audiobookId]!;
          bool hasRemainingFiles = audiobook.audioFiles.any(
              (file) => currentFileSet.contains(file) && file != deletedFile);

          if (!hasRemainingFiles) {
            AppLogger.info('Removing deleted audiobook: $audiobookId');
            audiobookMap.remove(audiobookId);
            await deleteAudiobook(audiobook);
          }
        }
      }

      // Process affected audiobooks
      for (String audiobookId in affectedIds) {
        AppLogger.info('Processing affected audiobook ID: $audiobookId');

        // Get files for this specific audiobook
        List<String> audiobookFiles = currentFiles.where((file) {
          String? fileAudiobookId =
              _getAudiobookIdForFile(file, rootFolderPath);
          return fileAudiobookId == audiobookId;
        }).toList();

        AppLogger.info(
            'Found ${audiobookFiles.length} files for audiobook ID: $audiobookId');

        // Determine level and process accordingly
        if (audiobookFiles.isNotEmpty) {
          Map<String, dynamic> fileInfo =
              _getFileLevelAndFolder(audiobookFiles.first, rootFolderPath);
          int level = fileInfo['level'];

          AppLogger.info(
              'Processing level $level for audiobook ID: $audiobookId');

          LocalAudiobook? processedAudiobook = await _processSingleAudiobook(
              audiobookId, audiobookFiles, level, rootFolderPath);

          // Update or add the audiobook in our map
          if (processedAudiobook != null) {
            audiobookMap[audiobookId] = processedAudiobook;
            await updateAudiobook(processedAudiobook);
            AppLogger.info(
                'Updated/Added audiobook: ${processedAudiobook.title}');
          } else {
            AppLogger.warning('No audiobook processed for ID: $audiobookId');
          }
        } else {
          AppLogger.warning('No files found for audiobook ID: $audiobookId');
        }
      }

      // Save updated file list to cache
      await saveScannedFiles(currentFiles);

      // Return all audiobooks (updated + unchanged)
      return audiobookMap.values.toList();
    } catch (e) {
      AppLogger.error('Error in smart refresh: $e');
      // Fallback to full scan
      return await refreshAudiobooks();
    }
  }

  /// Determine which audiobook IDs are affected by file changes
  static Set<String> _getAffectedAudiobookIds(
      List<String> changedFilePaths, String rootFolderPath) {
    Set<String> affectedIds = {};

    for (String filePath in changedFilePaths) {
      // Determine the level and get the audiobook ID
      String? audiobookId = _getAudiobookIdForFile(filePath, rootFolderPath);
      if (audiobookId != null) {
        affectedIds.add(audiobookId);
      }
    }

    return affectedIds;
  }

  /// Determine the audiobook ID for a given file based on its level
  static String? _getAudiobookIdForFile(
      String filePath, String rootFolderPath) {
    try {
      List<String> pathParts = filePath.split(rootFolderPath);
      if (pathParts.length < 2) return null;

      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");

      // Level 0: rootFolder/file (2 parts after root)
      if (pathPartsAfterRootFolder.length == 2) {
        return filePath; // Use file path as ID for level 0
      }

      // Level 1: rootFolder/subfolder/file (3 parts after root)
      if (pathPartsAfterRootFolder.length == 3) {
        String subfolder = pathPartsAfterRootFolder[1];
        return path.join(rootFolderPath, subfolder);
      }

      // Level 2: rootFolder/author/book/file (4 parts after root)
      if (pathPartsAfterRootFolder.length == 4) {
        String author = pathPartsAfterRootFolder[1];
        String book = pathPartsAfterRootFolder[2];
        return path.join(rootFolderPath, author, book);
      }

      return null;
    } catch (e) {
      AppLogger.error('Error determining audiobook ID for file $filePath: $e');
      return null;
    }
  }

  /// Get the level (0, 1, or 2) and folder path for a file
  static Map<String, dynamic> _getFileLevelAndFolder(
      String filePath, String rootFolderPath) {
    try {
      List<String> pathParts = filePath.split(rootFolderPath);
      if (pathParts.length < 2) {
        return {'level': -1, 'folder': null};
      }

      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");

      // Level 0: rootFolder/file (2 parts after root)
      if (pathPartsAfterRootFolder.length == 2) {
        return {'level': 0, 'folder': rootFolderPath};
      }

      // Level 1: rootFolder/subfolder/file (3 parts after root)
      if (pathPartsAfterRootFolder.length == 3) {
        String subfolder = pathPartsAfterRootFolder[1];
        return {'level': 1, 'folder': path.join(rootFolderPath, subfolder)};
      }

      // Level 2: rootFolder/author/book/file (4 parts after root)
      if (pathPartsAfterRootFolder.length == 4) {
        String author = pathPartsAfterRootFolder[1];
        String book = pathPartsAfterRootFolder[2];
        return {'level': 2, 'folder': path.join(rootFolderPath, author, book)};
      }

      return {'level': -1, 'folder': null};
    } catch (e) {
      AppLogger.error('Error determining file level for $filePath: $e');
      return {'level': -1, 'folder': null};
    }
  }

  /// Process a single audiobook based on its level and files
  static Future<LocalAudiobook?> _processSingleAudiobook(String audiobookId,
      List<String> audiobookFiles, int level, String rootFolderPath) async {
    try {
      if (level == 0) {
        // Level 0: Single file audiobook
        if (audiobookFiles.length == 1) {
          return await _processSingleLevel0Audiobook(
              audiobookFiles.first, rootFolderPath);
        }
      } else if (level == 1) {
        // Level 1: Single folder audiobook
        return await _processSingleLevel1Audiobook(
            audiobookId, audiobookFiles, rootFolderPath);
      } else if (level == 2) {
        // Level 2: Author/Book audiobook
        return await _processSingleLevel2Audiobook(
            audiobookId, audiobookFiles, rootFolderPath);
      }

      return null;
    } catch (e) {
      AppLogger.error('Error processing single audiobook $audiobookId: $e');
      return null;
    }
  }

  /// Process a single Level 0 audiobook
  static Future<LocalAudiobook?> _processSingleLevel0Audiobook(
      String filePath, String rootFolderPath) async {
    try {
      if (!await MediaHelper.isAudioFile(filePath)) {
        return null;
      }

      AppLogger.info('Processing single Level 0 audiobook: $filePath');

      // Extract metadata from the audio file
      Metadata metadata;
      try {
        metadata = await MediaHelper.getAudioMetadata(filePath, rootFolderPath)
            .timeout(const Duration(seconds: 60));
      } catch (timeoutError) {
        AppLogger.error('Metadata extraction timed out for: $filePath');
        metadata = Metadata(
          trackName: path.basenameWithoutExtension(filePath),
          albumName: path.basenameWithoutExtension(filePath),
          albumArtistName: 'Unknown',
          trackDuration: null,
          albumArt: null,
          filePath: filePath,
        );
      }

      // Get title and author from metadata
      String title = metadata.albumName ??
          metadata.trackName ??
          path.basenameWithoutExtension(filePath);
      String author = metadata.albumArtistName ??
          metadata.trackArtistNames?.join(', ') ??
          'Unknown';

      // Look for cover image with same name as audio file
      String? coverImagePath = await MediaHelper.findCoverImageForAudioFile(
          filePath, rootFolderPath);

      // If no cover image found, try to extract from metadata
      if (coverImagePath == null && metadata.albumArt != null) {
        coverImagePath = await MediaHelper.saveAlbumArtFromMetadata(
            metadata.albumArt!, path.basenameWithoutExtension(filePath));
      }

      // Create the audiobook object
      return LocalAudiobook(
        id: filePath,
        title: title,
        author: author,
        folderPath: rootFolderPath,
        coverImagePath: coverImagePath,
        audioFiles: [filePath],
        totalDuration: metadata.trackDuration != null
            ? Duration(milliseconds: metadata.trackDuration!)
            : null,
        dateAdded: DateTime.now(),
        lastModified: DateTime.now(),
        description: metadata.authorName ?? metadata.writerName,
        genre: metadata.genre,
      );
    } catch (e) {
      AppLogger.error(
          'Error processing single Level 0 audiobook $filePath: $e');
      return null;
    }
  }

  /// Process a single Level 1 audiobook
  static Future<LocalAudiobook?> _processSingleLevel1Audiobook(
      String audiobookId,
      List<String> audiobookFiles,
      String rootFolderPath) async {
    try {
      // Filter audio files
      List<String> audioFiles = [];
      for (String filePath in audiobookFiles) {
        if (await MediaHelper.isAudioFile(filePath)) {
          audioFiles.add(filePath);
        }
      }

      if (audioFiles.isEmpty) return null;

      // Extract folder name from audiobook ID
      String subfolder = path.basename(audiobookId);
      String title = MediaHelper.capitalizeWords(subfolder);
      String author = 'Unknown';

      // Find cover image in the subfolder
      String? coverImagePath = await MediaHelper.findCoverImageInFolder(
          audiobookFiles, subfolder, rootFolderPath);

      // If no cover found, try to extract from first audio file metadata
      if (coverImagePath == null && audioFiles.isNotEmpty) {
        coverImagePath = await MediaHelper.extractCoverFromAudioMetadata(
            audioFiles.first, rootFolderPath, subfolder);
      }

      // Calculate total duration from all audio files
      Duration? totalDuration =
          await MediaHelper.calculateTotalDuration(audioFiles, rootFolderPath);

      // Create the audiobook object
      return LocalAudiobook(
        id: audiobookId,
        title: title,
        author: author,
        folderPath: audiobookId,
        coverImagePath: coverImagePath,
        audioFiles: audioFiles,
        totalDuration: totalDuration,
        dateAdded: DateTime.now(),
        lastModified: DateTime.now(),
      );
    } catch (e) {
      AppLogger.error(
          'Error processing single Level 1 audiobook $audiobookId: $e');
      return null;
    }
  }

  /// Process a single Level 2 audiobook
  static Future<LocalAudiobook?> _processSingleLevel2Audiobook(
      String audiobookId,
      List<String> audiobookFiles,
      String rootFolderPath) async {
    try {
      // Filter audio files
      List<String> audioFiles = [];
      for (String filePath in audiobookFiles) {
        if (await MediaHelper.isAudioFile(filePath)) {
          audioFiles.add(filePath);
        }
      }

      if (audioFiles.isEmpty) return null;

      // Extract author and book from audiobook ID
      String relativePath = audiobookId.replaceFirst(rootFolderPath, '');
      List<String> pathParts =
          relativePath.split('/').where((s) => s.isNotEmpty).toList();

      if (pathParts.length < 2) return null;

      String author = pathParts[0];
      String book = pathParts[1];
      String title = MediaHelper.capitalizeWords(book);
      String authorName = MediaHelper.capitalizeWords(author);

      // Find cover image in the book folder
      String? coverImagePath = await MediaHelper.findCoverImageInFolder(
          audiobookFiles, book, rootFolderPath);

      // If no cover found, try to extract from first audio file metadata
      if (coverImagePath == null && audioFiles.isNotEmpty) {
        coverImagePath = await MediaHelper.extractCoverFromAudioMetadata(
            audioFiles.first, rootFolderPath, book);
      }

      // Calculate total duration from all audio files
      Duration? totalDuration =
          await MediaHelper.calculateTotalDuration(audioFiles, rootFolderPath);

      // Create the audiobook object
      return LocalAudiobook(
        id: audiobookId,
        title: title,
        author: authorName,
        folderPath: audiobookId,
        coverImagePath: coverImagePath,
        audioFiles: audioFiles,
        totalDuration: totalDuration,
        dateAdded: DateTime.now(),
        lastModified: DateTime.now(),
      );
    } catch (e) {
      AppLogger.error(
          'Error processing single Level 2 audiobook $audiobookId: $e');
      return null;
    }
  }

  // Here we scan each level of the audiobook tree and return all the audiobooks
  static Future<List<LocalAudiobook>> scanForAudiobooks() async {
    final rootFolderPath = await getRootFolderPath();
    if (rootFolderPath == null) {
      AppLogger.error('Root folder path is null');
      return [];
    }

    List<String>? allFilesInsideRootFolder =
        await Saf.getFilesPathFor(rootFolderPath);

    if (allFilesInsideRootFolder == null) {
      AppLogger.error('Failed to get files from root folder');
      return [];
    }

    AppLogger.info(
        'Found ${allFilesInsideRootFolder.length} files in root folder');

    List<LocalAudiobook> allAudiobooks = [];

    // Level 0: Standalone audiobooks (files directly in root)
    List<LocalAudiobook> level0Audiobooks =
        await processLevel0Audiobooks(rootFolderPath, allFilesInsideRootFolder);
    allAudiobooks.addAll(level0Audiobooks);

    // Level 1: Single subfolder audiobooks
    List<LocalAudiobook> level1Audiobooks =
        await processLevel1Audiobooks(rootFolderPath, allFilesInsideRootFolder);
    allAudiobooks.addAll(level1Audiobooks);

    // Level 2: Two subfolder audiobooks
    List<LocalAudiobook> level2Audiobooks =
        await processLevel2Audiobooks(rootFolderPath, allFilesInsideRootFolder);
    allAudiobooks.addAll(level2Audiobooks);

    // Save the scanned file list to cache
    await saveScannedFiles(allFilesInsideRootFolder);

    return allAudiobooks;
  }

  /// LOGIC FOR PROCESSING LEVEL 0 AUDIOBOOKS
  /// Level-0 standalone audiobooks:
  /// - All audio files located directly under the rootFolder are treated as standalone audiobooks.
  ///   Example (rootFolder = "/Audiobooks"):
  ///     /Audiobooks/artofwar.mp3
  ///     /Audiobooks/thinkandgrowrich.mp3
  ///   These are two different audiobooks.
  ///
  /// Cover image lookup (example: /Audiobooks/artofwar.mp3):
  /// - First, check for an image in the same folder with the same base name:
  ///     /Audiobooks/artofwar.png
  ///     /Audiobooks/artofwar.jpg
  ///     (etc.)
  /// - If no matching image is found, try to extract the image from the file’s metadata.
  ///
  /// Metadata for title, author, and cover:
  /// - To fetch title, author, and cover for a standalone file (e.g., artofwar.mp3),
  ///   read the audio metadata of that file.
  /// - Use Saf singleCache to read metadata reliably: cache the file into the app’s cache
  ///   via SAF, then read the metadata from the cached file.

  static Future<List<LocalAudiobook>> processLevel0Audiobooks(
      String rootFolderPath,
      List<String> pathOfAllFilesInsideRootFolder) async {
    List<LocalAudiobook> audiobooks = [];

    bool? hasPermission = await Saf.isPersistedPermissionDirectoryFor(
        makeUriString(path: rootFolderPath, isTreeUri: true));

    if (hasPermission != true) {
      AppLogger.error('No permission to access root folder: $rootFolderPath');
      return audiobooks;
    }

    // Here i split path of all files by "/" and get all the paths after rootFolderPath
    List<String> level0FilesPaths = [];
    for (String filePath in pathOfAllFilesInsideRootFolder) {
      List<String> pathParts = filePath.split(rootFolderPath);
      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");
      if (pathPartsAfterRootFolder.length == 2) {
        // Only add audio files to level 0 processing
        if (await MediaHelper.isAudioFile(filePath)) {
          AppLogger.info('Found level 0 audio file: $filePath');
          level0FilesPaths.add(filePath);
        } else {
          AppLogger.info('Skipping non-audio file: $filePath');
        }
      }
    }
    // Process each audio file as a standalone audiobook
    for (String filePath in level0FilesPaths) {
      try {
        AppLogger.info('Processing standalone audiobook: $filePath');

        // Extract metadata from the audio file (this will cache it internally)
        AppLogger.info('About to call getAudioMetadata for: $filePath');
        Metadata metadata;
        try {
          metadata =
              await MediaHelper.getAudioMetadata(filePath, rootFolderPath)
                  .timeout(const Duration(seconds: 60));
          AppLogger.info('Metadata extraction completed for: $filePath');
        } catch (timeoutError) {
          AppLogger.error('Metadata extraction timed out for: $filePath');
          // Create basic metadata as fallback
          metadata = Metadata(
            trackName: path.basenameWithoutExtension(filePath),
            albumName: path.basenameWithoutExtension(filePath),
            albumArtistName: 'Unknown',
            trackDuration: null,
            albumArt: null,
            filePath: filePath,
          );
        }

        // Get title and author from metadata
        String title = metadata.albumName ??
            metadata.trackName ??
            path.basenameWithoutExtension(filePath);
        String author = metadata.albumArtistName ??
            metadata.trackArtistNames?.join(', ') ??
            'Unknown';

        String? lastModified = metadata.modifiedDate;
        AppLogger.info('Last modified: $lastModified');

        // Look for cover image with same name as audio file
        String? coverImagePath = await MediaHelper.findCoverImageForAudioFile(
            filePath, rootFolderPath);

        // If no cover image found, try to extract from metadata
        if (coverImagePath == null && metadata.albumArt != null) {
          coverImagePath = await MediaHelper.saveAlbumArtFromMetadata(
              metadata.albumArt!, path.basenameWithoutExtension(filePath));
        }

        // Create the audiobook object
        final audiobook = LocalAudiobook(
          id: filePath, // Use file path as unique ID
          title: title,
          author: author,
          folderPath: rootFolderPath,
          coverImagePath: coverImagePath,
          audioFiles: [filePath], // Single file for standalone audiobook
          totalDuration: metadata.trackDuration != null
              ? Duration(milliseconds: metadata.trackDuration!)
              : null,
          dateAdded: DateTime.now(),
          lastModified: DateTime.now(),
          description: metadata.authorName ?? metadata.writerName,
          genre: metadata.genre,
        );

        audiobooks.add(audiobook);
        AppLogger.info('Created audiobook: $title by $author');
      } catch (e) {
        AppLogger.error('Error processing audiobook $filePath: $e');
        continue;
      }
    }
    return audiobooks;
  }

  /// LOGIC FOR PROCESSING LEVEL 1 AUDIOBOOKS
  /// Level 1 Audiobooks
  /// - Definition:
  ///   - An audiobook is considered "Level 1" when its audio files live in exactly one
  ///     subfolder directly under the rootFolder.
  ///   - Example (rootFolder = "/Audiobooks"):
  ///       /Audiobooks/artofwar/artofwar_part1.mp3
  ///       /Audiobooks/artofwar/artofwar_part2.mp3
  ///
  /// - Title and Author:
  ///   - Title = the name of that subfolder (e.g., "artofwar"), optionally humanized
  ///     (e.g., "Art Of War") for display.
  ///   - Author = "Unknown".
  ///
  /// - Cover image selection (within the subfolder that contains the audio files):
  ///   1) If there is exactly one image file in the folder, use it as the cover.
  ///   2) If multiple images exist, search by exact base name (case-insensitive) in this order:
  ///      cover, folder, audiobook, front, album, art, artwork, book
  ///      (match with common image extensions like .png, .jpg, .jpeg, .webp).
  ///   3) If still not found, pick any one audio file from the folder and try to extract
  ///      embedded album art by first caching the file via Saf singleCache and then
  ///      reading its metadata.
  ///   4) If no image is found anywhere, set coverImagePath = null.
  static Future<List<LocalAudiobook>> processLevel1Audiobooks(
      String rootFolderPath,
      List<String> pathOfAllFilesInsideRootFolder) async {
    List<LocalAudiobook> audiobooks = [];

    // Check if we have permission to access the root folder
    bool? hasPermission = await Saf.isPersistedPermissionDirectoryFor(
        makeUriString(path: rootFolderPath, isTreeUri: true));

    if (hasPermission != true) {
      AppLogger.error('No permission to access root folder: $rootFolderPath');
      return audiobooks;
    }

    // Group files by their first subfolder (level 1)
    Map<String, List<String>> folderGroups = {};

    for (String filePath in pathOfAllFilesInsideRootFolder) {
      List<String> pathParts = filePath.split(rootFolderPath);
      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");

      // Level 1: rootFolder/subfolder/file (3 parts after root)
      if (pathPartsAfterRootFolder.length == 3) {
        String subfolder = pathPartsAfterRootFolder[1];
        if (!folderGroups.containsKey(subfolder)) {
          folderGroups[subfolder] = [];
        }
        folderGroups[subfolder]!.add(filePath);
      }
    }

    // Process each subfolder as a potential audiobook
    for (String subfolder in folderGroups.keys) {
      List<String> filesInFolder = folderGroups[subfolder]!;

      // Filter audio files
      List<String> audioFiles = [];
      for (String filePath in filesInFolder) {
        if (await MediaHelper.isAudioFile(filePath)) {
          audioFiles.add(filePath);
        }
      }

      if (audioFiles.isEmpty) continue;

      try {
        AppLogger.info('Processing Level 1 audiobook: $subfolder');

        // Title is the subfolder name (capitalized)
        String title = MediaHelper.capitalizeWords(subfolder);
        String author = 'Unknown';

        // Find cover image in the subfolder
        String? coverImagePath = await MediaHelper.findCoverImageInFolder(
            filesInFolder, subfolder, rootFolderPath);

        // If no cover found, try to extract from first audio file metadata
        if (coverImagePath == null && audioFiles.isNotEmpty) {
          coverImagePath = await MediaHelper.extractCoverFromAudioMetadata(
              audioFiles.first, rootFolderPath, subfolder);
        }

        // Calculate total duration from all audio files
        Duration? totalDuration = await MediaHelper.calculateTotalDuration(
            audioFiles, rootFolderPath);

        // Create the audiobook object
        final audiobook = LocalAudiobook(
          id: path.join(rootFolderPath, subfolder), // Use folder path as ID
          title: title,
          author: author,
          folderPath: path.join(rootFolderPath, subfolder),
          coverImagePath: coverImagePath,
          audioFiles: audioFiles,
          totalDuration: totalDuration,
          dateAdded: DateTime.now(),
          lastModified: DateTime.now(),
        );

        audiobooks.add(audiobook);
        AppLogger.info('Created Level 1 audiobook: $title');
      } catch (e) {
        AppLogger.error('Error processing Level 1 audiobook $subfolder: $e');
        continue;
      }
    }

    return audiobooks;
  }

  /// LOGIC FOR PROCESSING LEVEL 2 AUDIOBOOKS
  ///Level 2 Audiobooks
  /// - Definition:
  ///   - An audiobook is considered "Level 2" when its audio files live in a second-level
  ///     subfolder under the rootFolder (two folders deep).
  ///   - Example (rootFolder = "/Audiobooks"):
  ///       /Audiobooks/SunTzu/artofwar/artofwar_part1.mp3
  ///       /Audiobooks/SunTzu/artofwar/artofwar_part2.mp3
  ///
  /// - Title and Author:
  ///   - Title = the name of the second-level folder (e.g., "artofwar").
  ///   - Author = the name of the first-level folder (e.g., "SunTzu").
  ///   - You may optionally normalize names (e.g., replace underscores/dashes with spaces,
  ///     apply title-casing) depending on your UI/UX needs.
  ///
  /// - Cover image selection (within the second-level folder that contains the audio files):
  ///   1) If there is exactly one image file in the folder, use it as the cover.
  ///   2) If multiple images exist, search by exact base name (case-insensitive) in this order:
  ///      cover, folder, audiobook, front, album, art, artwork, book
  ///      (match with common image extensions like .png, .jpg, .jpeg, .webp).
  ///   3) If still not found, pick any one audio file from the folder and try to extract
  ///      embedded album art by first caching the file via Saf singleCache and then
  ///      reading its metadata.
  ///   4) If no image is found anywhere, set coverImagePath = null.

  static Future<List<LocalAudiobook>> processLevel2Audiobooks(
      String rootFolderPath,
      List<String> pathOfAllFilesInsideRootFolder) async {
    List<LocalAudiobook> audiobooks = [];

    // Check if we have permission to access the root folder
    bool? hasPermission = await Saf.isPersistedPermissionDirectoryFor(
        makeUriString(path: rootFolderPath, isTreeUri: true));

    if (hasPermission != true) {
      AppLogger.error('No permission to access root folder: $rootFolderPath');
      return audiobooks;
    }

    // Group files by their author/book combination (level 2)
    Map<String, Map<String, List<String>>> authorBookGroups = {};

    for (String filePath in pathOfAllFilesInsideRootFolder) {
      List<String> pathParts = filePath.split(rootFolderPath);
      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");

      // Level 2: rootFolder/author/book/file (4 parts after root)
      if (pathPartsAfterRootFolder.length == 4) {
        String author = pathPartsAfterRootFolder[1];
        String book = pathPartsAfterRootFolder[2];

        if (!authorBookGroups.containsKey(author)) {
          authorBookGroups[author] = {};
        }
        if (!authorBookGroups[author]!.containsKey(book)) {
          authorBookGroups[author]![book] = [];
        }
        authorBookGroups[author]![book]!.add(filePath);
      }
    }

    // Process each author/book combination as a potential audiobook
    for (String author in authorBookGroups.keys) {
      for (String book in authorBookGroups[author]!.keys) {
        List<String> filesInBook = authorBookGroups[author]![book]!;

        // Filter audio files
        List<String> audioFiles = [];
        for (String filePath in filesInBook) {
          if (await MediaHelper.isAudioFile(filePath)) {
            audioFiles.add(filePath);
          }
        }

        if (audioFiles.isEmpty) continue;

        try {
          AppLogger.info('Processing Level 2 audiobook: $author/$book');

          // Title is the book name (capitalized), Author is the author name (capitalized)
          String title = MediaHelper.capitalizeWords(book);
          String authorName = MediaHelper.capitalizeWords(author);

          // Find cover image in the book folder
          String? coverImagePath = await MediaHelper.findCoverImageInFolder(
              filesInBook, book, rootFolderPath);

          // If no cover found, try to extract from first audio file metadata
          if (coverImagePath == null && audioFiles.isNotEmpty) {
            coverImagePath = await MediaHelper.extractCoverFromAudioMetadata(
                audioFiles.first, rootFolderPath, book);
          }

          // Calculate total duration from all audio files
          Duration? totalDuration = await MediaHelper.calculateTotalDuration(
              audioFiles, rootFolderPath);

          // Create the audiobook object
          final audiobook = LocalAudiobook(
            id: path.join(rootFolderPath, author, book), // Use full path as ID
            title: title,
            author: authorName,
            folderPath: path.join(rootFolderPath, author, book),
            coverImagePath: coverImagePath,
            audioFiles: audioFiles,
            totalDuration: totalDuration,
            dateAdded: DateTime.now(),
            lastModified: DateTime.now(),
          );

          audiobooks.add(audiobook);
          AppLogger.info('Created Level 2 audiobook: $title by $authorName');
        } catch (e) {
          AppLogger.error(
              'Error processing Level 2 audiobook $author/$book: $e');
          continue;
        }
      }
    }

    return audiobooks;
  }
}
