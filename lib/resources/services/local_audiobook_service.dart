import 'dart:io';
import 'dart:typed_data';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as path;
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path_provider/path_provider.dart';

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
    '.opus',
  ];

  // Supported image file extensions for cover images
  static const List<String> _supportedImageExtensions = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
  ];

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
    final rootPath = await getRootFolderPath();
    if (rootPath == null) return [];

    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return [];

    final List<LocalAudiobook> results = [];

    try {
      // 1) ROOT LEVEL: every audio file directly under root is a standalone book
      final rootChildren = await _listEntries(rootDir);
      final rootFiles = rootChildren.whereType<File>().toList();
      final rootAudios = rootFiles.where((f) => _isAudio(f.path)).toList();
      final rootImages = rootFiles.where((f) => _isImage(f.path)).toList();

      for (final audio in rootAudios) {
        final audioPath = audio.path;

        // Extract embedded tags/cover
        final meta = await _readFileMeta(audio);

        // Prefer embedded title/artist; fall back sensibly
        final derivedTitle =
        (meta.title?.isNotEmpty == true) ? meta.title! : _stem(audioPath);
        final derivedAuthor =
        (meta.artist?.isNotEmpty == true) ? meta.artist! : 'Unknown';

        // Prefer same-stem/priority image in folder; else embedded album art
        String? cover = _pickCoverForSingleFile(audio, rootImages);
        if (cover == null && meta.albumArt != null) {
          cover = await _saveAlbumArt(meta.albumArt!,
              stemHint: _stem(audioPath));
        }

        results.add(
          LocalAudiobook(
            id: 'root_${derivedTitle}_${DateTime.now().millisecondsSinceEpoch}',
            title: derivedTitle,
            author: derivedAuthor,
            folderPath: rootDir.path,
            coverImagePath: cover,
            audioFiles: [audioPath], // single-file book
            dateAdded: DateTime.now(),
            lastModified: DateTime.now(),
          ),
        );
      }

      // 2) Recurse into each subdirectory using the folder rules
      final rootDirs = rootChildren.whereType<Directory>().toList();
      for (final d in rootDirs) {
        results.addAll(await _scanFolder(d));
      }
    } catch (e) {
      AppLogger.error('Error scanning for audiobooks: $e');
    }

    return results;
  }

  /// Internal: recursively scan a folder with the level ≥ 1 rules.
  ///
  /// If folder has NO subfolders and HAS audio -> folder is a book; files = tracks.
  /// If folder HAS subfolders -> direct audio files are standalone books; subfolders are recursed.
  static Future<List<LocalAudiobook>> _scanFolder(Directory folder) async {
    final List<LocalAudiobook> found = [];

    try {
      final children = await _listEntries(folder);
      final subDirs = children.whereType<Directory>().toList();
      final files = children.whereType<File>().toList();
      final audioFiles = files.where((f) => _isAudio(f.path)).toList();
      final imageFiles = files.where((f) => _isImage(f.path)).toList();

      final folderName = path.basename(folder.path);
      final parentName = path.basename(folder.parent.path);
      final now = DateTime.now();

      if (subDirs.isEmpty) {
        // FOLDER = BOOK; audio inside = tracks
        if (audioFiles.isNotEmpty) {
          audioFiles.sort((a, b) => a.path.compareTo(b.path));

          // Try to infer author & cover from embedded tags across tracks
          String? inferredAuthor;
          String? cover = _pickCoverForFolderBook(imageFiles); // folder images first

          // Look into the first track(s) that have useful metadata
          for (final f in audioFiles) {
            final meta = await _readFileMeta(f);
            if (inferredAuthor == null && (meta.artist?.isNotEmpty == true)) {
              inferredAuthor = meta.artist;
            }
            if (cover == null && meta.albumArt != null) {
              final saved = await _saveAlbumArt(meta.albumArt!,
                  stemHint: _stem(f.path));
              cover = saved ?? cover;
            }
            if (inferredAuthor != null && cover != null) break;
          }

          final finalAuthor = (inferredAuthor?.isNotEmpty == true)
              ? inferredAuthor!
              : (parentName.isEmpty ? 'Unknown' : parentName);

          found.add(
            LocalAudiobook(
              id: 'folder_${parentName}_${folderName}_${now.millisecondsSinceEpoch}',
              title: folderName, // folder remains the book title
              author: finalAuthor,
              folderPath: folder.path,
              coverImagePath: cover,
              audioFiles: audioFiles.map((f) => f.path).toList(), // tracks
              dateAdded: now,
              lastModified: now,
            ),
          );
        }
      } else {
        // HAS SUBFOLDERS:
        //  • direct audio files here are standalone books
        //  • each subfolder is processed recursively
        for (final audio in audioFiles) {
          final meta = await _readFileMeta(audio);

          final title = (meta.title?.isNotEmpty == true)
              ? meta.title!
              : _stem(audio.path);
          final author = (meta.artist?.isNotEmpty == true)
              ? meta.artist!
              : (folderName.isEmpty ? 'Unknown' : folderName);

          String? cover = _pickCoverForSingleFile(audio, imageFiles);
          if (cover == null && meta.albumArt != null) {
            cover = await _saveAlbumArt(meta.albumArt!,
                stemHint: _stem(audio.path));
          }

          found.add(
            LocalAudiobook(
              id: 'file_${folderName}_${title}_${now.millisecondsSinceEpoch}',
              title: title,
              author: author,
              folderPath: folder.path,
              coverImagePath: cover,
              audioFiles: [audio.path], // single-file book
              dateAdded: now,
              lastModified: now,
            ),
          );
        }

        for (final sub in subDirs) {
          found.addAll(await _scanFolder(sub));
        }
      }
    } catch (e) {
      AppLogger.error('Error scanning audiobook folder ${folder.path}: $e');
    }

    return found;
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
  // Move support (unchanged)
  // ────────────────────────────────────────────────────────────────────────────
  static Future<bool> moveAudiobookFolder(
      LocalAudiobook audiobook,
      String newAuthor,
      String newTitle,
      ) async {
    try {
      final rootPath = await getRootFolderPath();
      if (rootPath == null) return false;

      final currentDir = Directory(audiobook.folderPath);
      if (!await currentDir.exists()) {
        AppLogger.error('Source directory does not exist: ${audiobook.folderPath}');
        return false;
      }

      final newPath = path.join(rootPath, newAuthor, newTitle);
      final newDir = Directory(newPath);

      if (currentDir.path == newDir.path) {
        return true;
      }

      await newDir.create(recursive: true);

      final List<File> filesToMove = [];
      await for (final entity in currentDir.list(followLinks: false)) {
        if (entity is File && await entity.exists()) {
          filesToMove.add(entity);
        }
      }

      for (final file in filesToMove) {
        try {
          final newFilePath = path.join(newPath, path.basename(file.path));
          final fileBytes = await file.readAsBytes();
          final newFile = File(newFilePath);
          await newFile.writeAsBytes(fileBytes);
          AppLogger.debug('Copied ${file.path} to $newFilePath');
        } catch (e) {
          AppLogger.error('Error copying file ${file.path}: $e');
          continue;
        }
      }

      for (final file in filesToMove) {
        try {
          if (await file.exists()) {
            await file.delete();
            AppLogger.debug('Deleted original file: ${file.path}');
          }
        } catch (e) {
          AppLogger.error('Error deleting original file ${file.path}: $e');
        }
      }

      try {
        if (await currentDir.exists() && await _isDirectoryEmpty(currentDir)) {
          await currentDir.delete();
          AppLogger.debug('Deleted empty directory: ${currentDir.path}');
          final parentDir = currentDir.parent;
          if (await parentDir.exists() && await _isDirectoryEmpty(parentDir)) {
            await parentDir.delete();
            AppLogger.debug('Deleted empty parent directory: ${parentDir.path}');
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

  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────

  static Future<List<FileSystemEntity>> _listEntries(Directory d) async {
    final items = <FileSystemEntity>[];
    await for (final e in d.list(followLinks: false)) {
      items.add(e);
    }
    return items;
  }

  static bool _isAudio(String p) {
    final ext = path.extension(p).toLowerCase();
    return _supportedAudioExtensions.contains(ext);
  }

  static bool _isImage(String p) {
    final ext = path.extension(p).toLowerCase();
    return _supportedImageExtensions.contains(ext);
  }

  static String _joinArtists(List<String> names) {
    // De-dupe & tidy
    final seen = <String>{};
    final cleaned = <String>[];
    for (final n in names) {
      final c = _clean(n);
      if (c != null && !seen.contains(c)) {
        seen.add(c);
        cleaned.add(c);
      }
    }
    return cleaned.join(', ');
  }

  static String _stem(String p) {
    final base = path.basename(p);
    final i = base.lastIndexOf('.');
    return i > 0 ? base.substring(0, i) : base;
  }

  /// Folder-book cover: prefer cover/folder/front/artwork.* then first image
  static String? _pickCoverForFolderBook(List<File> images) {
    if (images.isEmpty) return null;

    // 1) Priority basenames in this exact order (Voice)
    final priorities = [
      'cover',
      'folder',
      'audiobook',
      'front',
      'album',
      'art',
      'artwork',
      'book',
    ];

    // Exact match on basename (no extension)
    for (final key in priorities) {
      final hit = images.firstWhere(
            (f) => path.basenameWithoutExtension(f.path).toLowerCase() == key,
        orElse: () => File(''),
      );
      if (hit.path.isNotEmpty) return hit.path;
    }

    // Loose contains (handles cover (1).jpg etc.)
    for (final key in priorities) {
      final hit = images.firstWhere(
            (f) => path.basenameWithoutExtension(f.path).toLowerCase().contains(key),
        orElse: () => File(''),
      );
      if (hit.path.isNotEmpty) return hit.path;
    }

    // Fallback: first image
    return images.first.path;
  }

  static String? _pickCoverForSingleFile(File audio, List<File> imagesInFolder) {
    if (imagesInFolder.isEmpty) return null;

    // 1) Same-stem first (Voice does this)
    final stem = _stem(audio.path).toLowerCase();
    final sameStem = imagesInFolder.firstWhere(
          (f) => _stem(f.path).toLowerCase() == stem,
      orElse: () => File(''),
    );
    if (sameStem.path.isNotEmpty) return sameStem.path;

    // 2) Priority list (exact -> contains)
    final priorities = [
      'cover','folder','audiobook','front','album','art','artwork','book'
    ];

    for (final key in priorities) {
      final exact = imagesInFolder.firstWhere(
            (f) => path.basenameWithoutExtension(f.path).toLowerCase() == key,
        orElse: () => File(''),
      );
      if (exact.path.isNotEmpty) return exact.path;
    }
    for (final key in priorities) {
      final loose = imagesInFolder.firstWhere(
            (f) => path.basenameWithoutExtension(f.path).toLowerCase().contains(key),
        orElse: () => File(''),
      );
      if (loose.path.isNotEmpty) return loose.path;
    }

    // 3) First image
    return imagesInFolder.first.path;
  }

  static Future<bool> _isDirectoryEmpty(Directory dir) async {
    try {
      return await dir.list(followLinks: false).isEmpty;
    } catch (_) {
      return false;
    }
  }

  // Read tags/cover for a single audio file
  static Future<_FileMeta> _readFileMeta(File audioFile) async {
    try {
      // NOTE: flutter_media_metadata API is static: MetadataRetriever.fromFile(File)
      final m = await MetadataRetriever.fromFile(audioFile);

      // Title
      final title = _clean(m.trackName);

      // Artist preference: trackArtistNames (list) -> albumArtistName -> authorName
      String? artist;
      if (m.trackArtistNames != null && m.trackArtistNames!.isNotEmpty) {
        artist = _joinArtists(m.trackArtistNames!);
      } else {
        artist = _clean(m.albumArtistName) ?? _clean(m.authorName);
      }

      // in _readFileMeta
      return _FileMeta(
        title: title,
        artist: artist,
        trackNumber: m.trackNumber,
        albumArt: m.albumArt,
        // OPTIONAL: If you want to propagate genre up into LocalAudiobook:
        // add: genre: _clean(m.genre),
      );
    } catch (e) {
      AppLogger.debug('Meta extract failed for ${audioFile.path}: $e');
      return const _FileMeta();
    }
  }

  static String? _clean(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  // Persist embedded album art to an accessible file (so UI can load it)
  static Future<String?> _saveAlbumArt(Uint8List artBytes, {String stemHint = 'cover'}) async {
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir == null) return null;

      final coverDir = Directory(path.join(extDir.path, 'localCoverImages'));
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      // Try to infer extension (very small check like Voice does through frame mime)
      String ext = '.jpg';
      if (artBytes.length > 8) {
        // PNG signature
        const pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        bool isPng = true;
        for (int i = 0; i < pngSig.length; i++) {
          if (artBytes[i] != pngSig[i]) { isPng = false; break; }
        }
        if (isPng) ext = '.png';
      }

      final safeName = stemHint.isEmpty ? 'cover' : stemHint;
      final outPath = path.join(
        coverDir.path,
        '${safeName}_${DateTime.now().millisecondsSinceEpoch}$ext',
      );

      final f = File(outPath);
      await f.writeAsBytes(artBytes, flush: true);
      return outPath;
    } catch (e) {
      AppLogger.debug('Saving album art failed: $e');
      return null;
    }
  }


  // Duration calc placeholder (unchanged for now)
  static Future<Duration?> calculateTotalDuration(List<String> audioFiles) async {
    try {
      double totalSeconds = 0.0;
      for (final p in audioFiles) {
        final f = File(p);
        if (!await f.exists()) continue;
        final seconds = await MediaHelper.getAudioDuration(
            f); // you already use this elsewhere
        if (seconds != null) totalSeconds += seconds;
      }
      if (totalSeconds <= 0) return null;
      return Duration(milliseconds: (totalSeconds * 1000).round());
    } catch (_) {
      return null;
    }
  }
}

// Internal helper container for metadata
class _FileMeta {
  final String? title;
  final String? artist;
  final int? trackNumber;
  final Uint8List? albumArt;

  const _FileMeta({this.title, this.artist, this.trackNumber, this.albumArt});
}
