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
