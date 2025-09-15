// lib/resources/services/local_library_layout.dart
import 'dart:io';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:path/path.dart' as p;

/// If you ever change your local rules (root = books, subfolders = tracks,
/// pictures amidst tracks = covers, etc.) do it here and the whole app follows.
class LocalLibraryLayout {
  const LocalLibraryLayout._();

  // ───────────────────────────────────────────────────────────────────────────
  // Path helpers (shared across the app)
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

  // ───────────────────────────────────────────────────────────────────────────
  // “What is a book?” rules

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
    return first == null ? null : p.dirname(first);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Embedded cover discovery (pictures alongside tracks)  ⬅️ NEW HELPERS

  /// Allowed image extensions (case-insensitive).
  static const Set<String> kImageExtensions = {
    '.jpg', '.jpeg', '.png', '.webp', '.bmp'
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

  /// Whether to ignore “hidden” files like `.DS_Store`, `._foo.jpg`, etc.
  static bool _isHidden(String base) {
    // dotfiles and Apple resource forks
    return base.startsWith('.') || base.startsWith('._');
  }

  /// Returns a list of image files inside [folder]. If [recursive] is true,
  /// also scans one level of subfolders (handy if tracks live in subfolders).
  static Future<List<File>> listImagesInFolder(
      String folder, {
        bool recursive = false,
      }) async {
    final dir = Directory(decodePath(folder));
    if (!await dir.exists()) return const [];

    final out = <File>[];
    final lister = dir.list(recursive: recursive, followLinks: false);

    await for (final ent in lister) {
      if (ent is! File) continue;
      final ext = p.extension(ent.path).toLowerCase();
      if (!kImageExtensions.contains(ext)) continue;

      final base = p.basenameWithoutExtension(ent.path).toLowerCase();
      if (_isHidden(base)) continue;

      out.add(ent);
    }
    return out;
  }

  /// Score an image by (1) preferred basename priority, then (2) file size.
  /// Lower score wins; we subtract size so bigger files are preferred.
  static int _basenamePriority(String base) {
    final name = base.toLowerCase();
    final idx = kPreferredCoverBasenames.indexOf(name);
    return idx >= 0 ? idx : 1000; // non-preferred go to the back
  }

  static Future<int> _fileSizeOrZero(File f) async {
    try {
      final stat = await f.stat();
      return stat.size;
    } catch (_) {
      return 0;
    }
  }

  /// Pick the most likely cover in [folder]. If none found, returns null.
  ///
  /// Strategy:
  /// 1) Prefer files whose basename matches kPreferredCoverBasenames (e.g.
  ///    cover.jpg/folder.png/front.webp), in that order.
  /// 2) If multiple candidates tie, prefer the *largest* file (approx for quality).
  /// 3) If nothing matches the preferred names, pick the *largest* image file.
  static Future<String?> findEmbeddedCoverInFolder(
      String folder, {
        bool recursive = false,
      }) async {
    final images = await listImagesInFolder(folder, recursive: recursive);
    if (images.isEmpty) return null;

    // Candidates grouped by basename priority
    final byPriority = <int, List<File>>{};
    for (final f in images) {
      final base = p.basenameWithoutExtension(f.path);
      final pri = _basenamePriority(base);
      (byPriority[pri] ??= <File>[]).add(f);
    }

    // Check preferred-name buckets from best to worst
    final sortedKeys = byPriority.keys.toList()..sort();
    for (final pri in sortedKeys) {
      final bucket = byPriority[pri]!;
      if (bucket.isEmpty) continue;

      // If this bucket is the "non-preferred" one (>=1000) but we later find
      // nothing else, we will still select its largest file; for preferred
      // buckets we also pick the largest file inside the bucket.
      File? best;
      int bestSize = -1;
      for (final f in bucket) {
        final size = await _fileSizeOrZero(f);
        if (size > bestSize) {
          best = f;
          bestSize = size;
        }
      }
      if (best != null && pri < 1000) {
        return best.path; // return early for a preferred name
      }
    }

    // No preferred-name hits → pick the largest image overall.
    File? largest;
    int largestSize = -1;
    for (final f in images) {
      final size = await _fileSizeOrZero(f);
      if (size > largestSize) {
        largest = f;
        largestSize = size;
      }
    }
    return largest?.path;
  }

  /// Convenience: find a folder-embedded cover for a given LocalAudiobook.
  /// - For single-file books: scans the file's parent folder
  /// - For multi-file books: scans the audiobook's folderPath
  /// Set [recursive] to true if your tracks are nested; default false for speed.
  static Future<String?> findEmbeddedCoverForLocal(
      LocalAudiobook a, {
        bool recursive = false,
      }) async {
    if (isSingleFileBook(a)) {
      final file = decodePath(a.audioFiles.first);
      final parent = p.dirname(file);
      return findEmbeddedCoverInFolder(parent, recursive: recursive);
    }
    final folder = decodePath(a.folderPath);
    return findEmbeddedCoverInFolder(folder, recursive: recursive);
  }

  /// Convenience: try to find a folder-embedded cover given a history item.
  static Future<String?> findEmbeddedCoverForHistory(
      HistoryOfAudiobookItem item, {
        bool recursive = false,
      }) async {
    final folder = bookFolderFromHistory(item);
    if (folder == null || folder.isEmpty) return null;
    return findEmbeddedCoverInFolder(folder, recursive: recursive);
  }
}
