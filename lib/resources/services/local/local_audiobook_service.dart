import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:saf/saf.dart';
import 'package:saf/src/storage_access_framework/api.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class LocalAudiobookService {
  static const String _rootFolderKey = 'local_audiobooks_root_folder';
  static const String _audiobooksBoxName = 'local_audiobooks';

  // ────────────────────────────────────────────────────────────────────────────
  // Settings (root path)
  // ────────────────────────────────────────────────────────────────────────────
  static Future<String?> getRootFolderPath() async {
    final box = await Hive.openBox('settings');
    return box.get(_rootFolderKey);
  }

  static Future<void> setRootFolderPath(String p) async {
    final box = await Hive.openBox('settings');
    await box.put(_rootFolderKey, p);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // CRUD in Hive
  // ────────────────────────────────────────────────────────────────────────────
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

  // ────────────────────────────────────────────────────────────────────────────
  // Refresh: rescans and replaces the Hive box contents
  // ────────────────────────────────────────────────────────────────────────────
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

  // ────────────────────────────────────────────────────────────────────────────
  // SCANNER: Implements your rules + metadata extraction
  // ────────────────────────────────────────────────────────────────────────────

  /// Public: scan the entire tree according to the rules and return all books.
  ///
  /// Rules:
  /// • Root (level 0): each audio file directly in root is a standalone book.
  /// • Any subfolder (level ≥ 1):
  ///    - If NO subfolders and HAS audio → the folder is a book; its files are tracks.
  ///    - If HAS subfolders → direct audio files are standalone books; recurse into subfolders.
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

    // Process all levels of audiobooks
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

  static Future<List<LocalAudiobook>> processLevel0Audiobooks(
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

    // Here i split path of all files by "/" and get all the paths after rootFolderPath
    List<String> level0FilesPaths = [];
    for (String filePath in pathOfAllFilesInsideRootFolder) {
      List<String> pathParts = filePath.split(rootFolderPath);
      String relativePath = pathParts.last;
      List<String> pathPartsAfterRootFolder = relativePath.split("/");
      if (pathPartsAfterRootFolder.length == 2) {
        // Only add audio files to level 0 processing
        if (await isAudioFile(filePath)) {
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
          metadata = await getAudioMetadata(filePath)
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
        String? coverImagePath =
            await findCoverImageForAudioFile(filePath, rootFolderPath);

        // If no cover image found, try to extract from metadata
        if (coverImagePath == null && metadata.albumArt != null) {
          coverImagePath = await saveAlbumArtFromMetadata(
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

  // Process Level 1 Audiobooks: Single subfolder audiobooks
  // Example: /Audiobooks/artofwar/artofwar_part1.mp3, /Audiobooks/artofwar/artofwar_part2.mp3
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
        if (await isAudioFile(filePath)) {
          audioFiles.add(filePath);
        }
      }

      if (audioFiles.isEmpty) continue;

      try {
        AppLogger.info('Processing Level 1 audiobook: $subfolder');

        // Title is the subfolder name (capitalized)
        String title = _capitalizeWords(subfolder);
        String author = 'Unknown';

        // Find cover image in the subfolder
        String? coverImagePath = await findCoverImageInFolder(
            filesInFolder, subfolder, rootFolderPath);

        // If no cover found, try to extract from first audio file metadata
        if (coverImagePath == null && audioFiles.isNotEmpty) {
          coverImagePath = await extractCoverFromAudioMetadata(
              audioFiles.first, rootFolderPath, subfolder);
        }

        // Calculate total duration from all audio files
        Duration? totalDuration =
            await calculateTotalDuration(audioFiles, rootFolderPath);

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

  // Process Level 2 Audiobooks: Two subfolder audiobooks
  // Example: /Audiobooks/SunTzu/artofwar/artofwar_part1.mp3, /Audiobooks/SunTzu/artofwar/artofwar_part2.mp3
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
          if (await isAudioFile(filePath)) {
            audioFiles.add(filePath);
          }
        }

        if (audioFiles.isEmpty) continue;

        try {
          AppLogger.info('Processing Level 2 audiobook: $author/$book');

          // Title is the book name (capitalized), Author is the author name (capitalized)
          String title = _capitalizeWords(book);
          String authorName = _capitalizeWords(author);

          // Find cover image in the book folder
          String? coverImagePath =
              await findCoverImageInFolder(filesInBook, book, rootFolderPath);

          // If no cover found, try to extract from first audio file metadata
          if (coverImagePath == null && audioFiles.isNotEmpty) {
            coverImagePath = await extractCoverFromAudioMetadata(
                audioFiles.first, rootFolderPath, book);
          }

          // Calculate total duration from all audio files
          Duration? totalDuration =
              await calculateTotalDuration(audioFiles, rootFolderPath);

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

  // Method to get metadata of an audio file using SAF
  static Future<Metadata> getAudioMetadata(String filePath) async {
    AppLogger.info('Starting metadata extraction for: $filePath');

    // For SAF, we always need to cache the file first, then read metadata from the cached file
    final rootFolderPath = await getRootFolderPath();
    if (rootFolderPath == null) {
      throw Exception('Root folder path is null');
    }

    try {
      // Try using sync method first to cache all files, then find our specific file
      AppLogger.info('Attempting SAF sync cache for: $filePath');

      // Use sync method to cache all files
      Saf saf = Saf(rootFolderPath);
      bool? result = await saf.sync().timeout(const Duration(seconds: 60));

      if (result == true) {
        // Find the cached file by looking for the filename
        String fileName = path.basename(filePath);
        String cacheDir = await _getCacheDirectory();
        String cachedFilePath =
            path.join(cacheDir, 'audiobooks_cache', fileName);

        if (await File(cachedFilePath).exists()) {
          AppLogger.info('File found in sync cache: $cachedFilePath');
          // Read metadata from the cached file
          final metadata =
              await MetadataRetriever.fromFile(File(cachedFilePath))
                  .timeout(const Duration(seconds: 10));
          AppLogger.info(
              'Successfully read metadata from cached file: $cachedFilePath');
          return metadata;
        }
      }

      // Fallback to singleCache if sync fails
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
      // Read metadata from the cached file
      final metadata = await MetadataRetriever.fromFile(File(cachePath))
          .timeout(const Duration(seconds: 10));
      AppLogger.info('Successfully read metadata from cached file: $cachePath');
      return metadata;
    } catch (e) {
      AppLogger.error('Metadata reading failed for $filePath: $e');
      // Return empty metadata as fallback
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

  // Helper method to get cache directory
  static Future<String> _getCacheDirectory() async {
    final externalDir = await getExternalStorageDirectory();
    return externalDir?.path ?? '';
  }

  // Method to check if file is an audio file
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

  // Method to check if file is an image file
  static Future<bool> isImageFile(String filePath) async {
    return filePath.endsWith('.jpg') ||
        filePath.endsWith('.jpeg') ||
        filePath.endsWith('.png') ||
        filePath.endsWith('.webp') ||
        filePath.endsWith('.bmp');
  }

  // Method to find cover image with same name as audio file
  static Future<String?> findCoverImageForAudioFile(
      String audioFilePath, String rootFolderPath) async {
    try {
      final audioFileName = path.basenameWithoutExtension(audioFilePath);
      final audioFileDir = path.dirname(audioFilePath);

      // List of supported image extensions
      final imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.bmp'];

      for (String ext in imageExtensions) {
        final potentialCoverPath =
            path.join(audioFileDir, '$audioFileName$ext');

        // Check if the file exists using SAF
        final files = await Saf.getFilesPathFor(rootFolderPath);
        if (files != null && files.contains(potentialCoverPath)) {
          AppLogger.info('Found cover image: $potentialCoverPath');

          // Copy the cover image to local storage and return the local path
          String? localCoverPath = await _copyCoverImageToLocalStorage(
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

  // Method to save album art from metadata as PNG
  static Future<String?> saveAlbumArtFromMetadata(
      Uint8List albumArtData, String baseName) async {
    try {
      // Get external storage directory
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        AppLogger.error('Failed to get external storage directory');
        return null;
      }

      // Create localCoverImages directory
      final coverImagesDir =
          Directory(path.join(externalDir.path, 'localCoverImages'));
      if (!await coverImagesDir.exists()) {
        await coverImagesDir.create(recursive: true);
      }

      // Create unique filename using baseName only (no timestamp to prevent duplicates)
      final fileName = '${_sanitizeFileName(baseName)}.png';
      final filePath = path.join(coverImagesDir.path, fileName);

      // Write the album art data to file
      final file = File(filePath);
      await file.writeAsBytes(albumArtData);

      AppLogger.info('Saved album art: $filePath');
      return filePath;
    } catch (e) {
      AppLogger.error('Error saving album art for $baseName: $e');
      return null;
    }
  }

  // Method to copy cover image from SAF path to local storage
  static Future<String?> _copyCoverImageToLocalStorage(String sourceImagePath,
      String audiobookName, String rootFolderPath) async {
    try {
      AppLogger.info('Copying cover image: $sourceImagePath');

      // Get external storage directory
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        AppLogger.error('Failed to get external storage directory');
        return null;
      }

      // Create localCoverImages directory
      final coverImagesDir =
          Directory(path.join(externalDir.path, 'localCoverImages'));
      if (!await coverImagesDir.exists()) {
        await coverImagesDir.create(recursive: true);
      }

      // Create unique filename using audiobook name
      String originalExtension = path.extension(sourceImagePath);
      String fileName = '${_sanitizeFileName(audiobookName)}$originalExtension';
      String localFilePath = path.join(coverImagesDir.path, fileName);

      // Check if file already exists (to prevent duplicates)
      if (await File(localFilePath).exists()) {
        AppLogger.info('Cover image already exists: $localFilePath');
        return localFilePath;
      }

      // Cache the source image using SAF
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

      // Copy from cached file to local storage
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

  // Helper method to sanitize filename for safe storage
  static String _sanitizeFileName(String fileName) {
    // Remove or replace invalid characters for file names
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'),
            '_') // Replace invalid chars with underscore
        .replaceAll(' ', '_') // Replace spaces with underscore
        .replaceAll(
            RegExp(r'_+'), '_') // Replace multiple underscores with single
        .toLowerCase();
  }

  // Helper method to capitalize words (e.g., "art of war" -> "Art Of War")
  static String _capitalizeWords(String text) {
    if (text.isEmpty) return text;

    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  // Find cover image in a folder with specific logic
  static Future<String?> findCoverImageInFolder(List<String> filesInFolder,
      String folderName, String rootFolderPath) async {
    try {
      // Filter image files
      List<String> imageFiles = [];
      for (String filePath in filesInFolder) {
        if (await isImageFile(filePath)) {
          imageFiles.add(filePath);
        }
      }

      if (imageFiles.isEmpty) {
        AppLogger.info('No image files found in folder: $folderName');
        return null;
      }

      String? selectedImagePath;

      // If only one image, use it
      if (imageFiles.length == 1) {
        AppLogger.info('Found single cover image: ${imageFiles.first}');
        selectedImagePath = imageFiles.first;
      } else {
        // If multiple images, look for specific names in order
        List<String> preferredNames = [
          'cover',
          'folder',
          'audiobook',
          'front',
          'album',
          'art',
          'artwork',
          'book'
        ];

        for (String preferredName in preferredNames) {
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

        // If no preferred name found, use the first image
        if (selectedImagePath == null) {
          AppLogger.info(
              'No preferred cover name found, using first image: ${imageFiles.first}');
          selectedImagePath = imageFiles.first;
        }
      }

      // Copy the cover image to local storage and return the local path
      String? localCoverPath = await _copyCoverImageToLocalStorage(
          selectedImagePath, folderName, rootFolderPath);

      return localCoverPath;
    } catch (e) {
      AppLogger.error('Error finding cover image in folder $folderName: $e');
      return null;
    }
  }

  // Extract cover from audio file metadata
  static Future<String?> extractCoverFromAudioMetadata(
      String audioFilePath, String rootFolderPath, String baseName) async {
    try {
      // Extract metadata (this will cache the file internally)
      final metadata = await getAudioMetadata(audioFilePath);

      // If album art exists, save it
      if (metadata.albumArt != null) {
        return await saveAlbumArtFromMetadata(metadata.albumArt!, baseName);
      }

      AppLogger.info('No album art found in metadata for: $baseName');
      return null;
    } catch (e) {
      AppLogger.error('Error extracting cover from metadata for $baseName: $e');
      return null;
    }
  }

  // Calculate total duration from multiple audio files
  static Future<Duration?> calculateTotalDuration(
      List<String> audioFiles, String rootFolderPath) async {
    try {
      int totalMilliseconds = 0;

      for (String audioFile in audioFiles) {
        try {
          // Get metadata (this will cache the file internally)
          final metadata = await getAudioMetadata(audioFile);
          if (metadata.trackDuration != null) {
            totalMilliseconds += metadata.trackDuration!;
          }
        } catch (e) {
          AppLogger.error('Error getting metadata for $audioFile: $e');
          // Continue with other files
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
}
