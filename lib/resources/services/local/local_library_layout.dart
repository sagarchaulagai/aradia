import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:path/path.dart' as p;

class LocalLibraryLayout {
  const LocalLibraryLayout._();

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
    // Normalize and get relative path (strip '/storage/emulated/0/' if present)
    String rel = inputPath;
    const androidPrefix = '/storage/emulated/0/';
    if (rel.startsWith(androidPrefix)) {
      rel = rel.substring(androidPrefix.length);
    }
    rel = rel.replaceAll(RegExp(r'^/+'), ''); // remove any leading slashes

    // Split into segments and encode each segment separately
    final segments = rel.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw ArgumentError('Path is empty after normalization');
    }

    // Top-level folder used for tree URI (first segment)
    final treeRoot = Uri.encodeComponent(segments.first);

    // For document part encode each segment and join with literal %2F
    final encodedSegments =
        segments.map((s) => Uri.encodeComponent(s)).join('%2F');

    const base = 'content://com.android.externalstorage.documents/';
    final treeUri = '${base}tree/primary%3A$treeRoot';
    return '$treeUri/document/primary%3A$encodedSegments';
  }
}
