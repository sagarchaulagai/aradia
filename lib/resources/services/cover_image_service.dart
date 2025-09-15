// lib/resources/services/cover_image_service.dart
import 'dart:async';
import 'dart:io';

import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ── Cover art event bus ──────────────────────────────────────────────────────
class CoverArtBus {
  static final CoverArtBus _i = CoverArtBus._();
  CoverArtBus._();
  factory CoverArtBus() => _i;

  final _ctrl = StreamController<String>.broadcast(); // payload: cover key/id
  Stream<String> get stream => _ctrl.stream;

  void emit(String key) {
    if (key.isEmpty) return;
    _ctrl.add(key);
  }
}

final coverArtBus = CoverArtBus();

/// All cover mappings are stored in this Hive box.
/// Keys are *normalized* strings representing either a file path (single-file book)
/// or a folder path (multi-track book). Values are absolute file paths to images.
const String kCoverMappingBox = 'cover_image_mapping';

/// ─────────────────────────────────────────────────────────────────────────────
/// Small LRU cache for resolved covers (per canonical book key).
/// Caches both hits (file path/URL) and misses (null) to avoid repeated IO.
/// ─────────────────────────────────────────────────────────────────────────────
class _CoverCache {
  static const int _maxEntries = 256;
  final _map = <String, String?>{}; // key -> resolved cover (or null for miss)

  bool containsKey(String key) => _map.containsKey(key);

  String? get(String key) {
    if (!_map.containsKey(key)) return null;
    // Touch (move to most-recent)
    final v = _map.remove(key);
    _map[key] = v;
    return v;
    // Note: returning null here means either "cached miss" or "not present".
    // Callers can use containsKey(key) to distinguish.
  }

  void set(String key, String? value) {
    if (!_map.containsKey(key) && _map.length >= _maxEntries) {
      // Evict least-recently-used (the first key)
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }

  void remove(String key) => _map.remove(key);
  void clear() => _map.clear();
}

final _coverCache = _CoverCache();

/// Cached Hive box accessor so we don't repeatedly call `Hive.openBox`.
class CoverImageStore {
  static final CoverImageStore _i = CoverImageStore._();
  CoverImageStore._();
  factory CoverImageStore() => _i;

  Box? _box;
  Future<Box> _getBox() async => _box ??= await Hive.openBox(kCoverMappingBox);

  Future<String?> get(String key) async {
    final b = await _getBox();
    final v = b.get(key);
    return (v is String && v.isNotEmpty) ? v : null;
  }

  Future<void> put(String key, String value) async {
    final b = await _getBox();
    await b.put(key, value);
  }

  Future<void> delete(String key) async {
    final b = await _getBox();
    await b.delete(key);
  }

  Future<Iterable<String>> values() async {
    final b = await _getBox();
    return b.values.whereType<String>();
  }
}

/// Returns a stable, per-book key for *local* audiobooks:
/// - single-file books → absolute file path
/// - multi-track (folder) books → absolute folder path
String coverKeyForLocal(LocalAudiobook a) {
  final files = a.audioFiles.map(decodePath).toList();
  if (files.length == 1) {
    return files.first; // single-file book keyed by its file path
  }
  return decodePath(a.folderPath); // multi-track book keyed by its folder
}

/// Save a cover for a local audiobook using the canonical key.
/// Also removes any old *folder* mapping to prevent cross-book bleed.
/// Primes the in-memory cache so UI updates immediately.
Future<void> mapCoverForLocal(LocalAudiobook a, String coverImagePath) async {
  final key = coverKeyForLocal(a);
  final normalized = decodePath(coverImagePath);

  await mapCoverImage(key, normalized);

  final folderKey = decodePath(a.folderPath);
  if (folderKey != key) {
    await removeCoverMapping(folderKey);
  }

  _coverCache.set(key, normalized);
  coverArtBus.emit(key); // 🔔 publish for this local book too
}

/// Resolve a cover for a local audiobook using consistent rules:
/// 1) mapping[key] → 2) mapping[legacy: a.id] → 3) mapping[legacy: folderPath]
/// → 4) explicit/embedded LocalAudiobook.coverImagePath → null
/// Uses a small LRU cache (with negative caching) to avoid repeated IO.
Future<String?> resolveCoverForLocal(LocalAudiobook a) async {
  final key = coverKeyForLocal(a);

  // Cache hit?
  if (_coverCache.containsKey(key)) {
    final cached = _coverCache.get(key); // may be null (negative cache)
    if (cached != null) {
      // If it's a local file, make sure it still exists; otherwise evict and recompute.
      final local = asLocalPath(cached);
      if (local == null || await File(local).exists()) return cached;
      _coverCache.remove(key);
    } else {
      // Cached miss
      return null;
    }
  }

  // 1) Preferred mapping by canonical key
  final byKey = await getMappedCoverImage(key);
  if (byKey != null) {
    _coverCache.set(key, byKey);
    return byKey;
  }

  // 2) Legacy id-based mapping (in case older code saved under a.id)
  final byId = await getMappedCoverImage(a.id);
  if (byId != null) {
    _coverCache.set(key, byId);
    return byId;
  }

  // 3) Legacy folder-based mapping
  final byFolder = await getMappedCoverImage(decodePath(a.folderPath));
  if (byFolder != null) {
    _coverCache.set(key, byFolder);
    return byFolder;
  }

  // 4) Explicit/embedded path on the model
  final explicit = a.coverImagePath == null ? null : decodePath(a.coverImagePath!);
  if (explicit != null && await File(explicit).exists()) {
    _coverCache.set(key, explicit);
    return explicit;
  }

  // Nothing found; cache the miss (negative cache).
  _coverCache.set(key, null);
  return null;
}

/// Resolve artwork for a History tile. This mirrors player/card precedence and
/// remains backward-compatible with older history entries.
///
/// Order:
/// 1) mapping[audiobook.id]
/// 2) mapping[firstTrackFilePath] → mapping[parentFolder]
/// 3) audiobook.lowQCoverImage (local or URL)
/// 4) first track's highQCoverImage (local or URL)
Future<String?> resolveCoverForHistory(HistoryOfAudiobookItem item) async {
  final a = item.audiobook;

  // 1) Mapping by audiobook.id (post-refactor invariant)
  final byId = await getMappedCoverImage(a.id);
  if (byId != null) return byId;

  // 2) Legacy keys derived from the first track
  if (item.audiobookFiles.isNotEmpty) {
    final firstTrack = item.audiobookFiles.first;
    final firstPath = decodePath(firstTrack.url ?? '');
    if (firstPath.isNotEmpty) {
      final byFile = await getMappedCoverImage(firstPath);
      if (byFile != null) return byFile;

      final byFolder = await getMappedCoverImage(p.dirname(firstPath));
      if (byFolder != null) return byFolder;
    }
  }

  // 3) Fallback to the audiobook's cover (can be file or URL)
  final low = a.lowQCoverImage;
  final lowLocal = asLocalPath(low);
  if (lowLocal != null && await File(lowLocal).exists()) return lowLocal;
  if (low != null && low.isNotEmpty) return low;

  // 4) Last resort: first track’s highQCoverImage (file or URL)
  if (item.audiobookFiles.isNotEmpty) {
    final hi = item.audiobookFiles.first.highQCoverImage;
    final hiLocal = asLocalPath(hi);
    if (hiLocal != null && await File(hiLocal).exists()) return hiLocal;
    if (hi != null && hi.isNotEmpty) return hi;
  }

  return null;
}

/// Low-level: get mapped cover (verifies file exists; prunes stale entries).
Future<String?> getMappedCoverImage(String key) async {
  if (key.isEmpty) return null;
  final store = CoverImageStore();
  final path = await store.get(key);
  if (path == null) return null;

  final normalized = decodePath(path);
  final f = File(normalized);
  if (await f.exists()) return f.path;

  // Prune stale mapping if file is gone.
  await store.delete(key);
  return null;
}

/// Low-level: put a mapping (expects an absolute path to an image file).
Future<void> mapCoverImage(String key, String coverImagePath) async {
  if (key.isEmpty) return;
  final store = CoverImageStore();
  await store.put(key, decodePath(coverImagePath));
  coverArtBus.emit(key); // 🔔 notify listeners
}

Future<void> removeCoverMapping(String key) async {
  if (key.isEmpty) return;
  final store = CoverImageStore();
  final path = await store.get(key);
  if (path != null) {
    final f = File(decodePath(path));
    if (await f.exists()) {
      try { await f.delete(); } catch (_) {}
    }
  }
  await store.delete(key);
  _coverCache.remove(key);
  coverArtBus.emit(key); // 🔔 notify listeners
}

/// Optional explicit invalidation helpers, if other modules need them.
void invalidateCoverForLocal(LocalAudiobook a) {
  _coverCache.remove(coverKeyForLocal(a));
}
void invalidateCoverByKey(String key) {
  _coverCache.remove(key);
}

/// Convert any path/URI to a canonical local filesystem path if possible.
/// Returns null for non-local (e.g., HTTP URLs).
String? asLocalPath(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    if (s.startsWith('file://')) return Uri.parse(s).toFilePath();
    if (s.startsWith('/')) return s;
    // Windows-style absolute path like C:\... or D:/...
    if (s.contains(':/') && !s.startsWith('http')) return s;
  } catch (_) {}
  return null;
}

/// Decode a path/URI consistently (safe for keys and values).
String decodePath(String s) {
  if (s.isEmpty) return s;
  try {
    if (s.startsWith('file://')) return Uri.parse(s).toFilePath();
    // If it looks like a percent-encoded file path, decode components.
    return Uri.decodeComponent(s);
  } catch (_) {
    return s; // return as-is if decoding fails
  }
}

/// Quick heuristic for "is this a local path (not http/https)".
bool looksLocal(String s) =>
    s.startsWith('file://') ||
        s.startsWith('/') ||
        (s.contains(':/') && !s.startsWith('http'));

/// A small helper so widgets can render images without branching.
/// Usage:
///   final v = await resolveCoverForLocal(a);
///   return v != null ? Image(image: coverProvider(v)) : placeholder();
ImageProvider<Object> coverProvider(String v) {
  final local = asLocalPath(v);
  if (local != null) {
    return FileImage(File(local));
  }
  // Treat everything else as remote; NetworkImage will handle http/https.
  return NetworkImage(v);
}

/// Optional: housekeeping to remove orphaned images from your cover folder
/// (and stale mappings pointing to missing files).
/// - Scans the default 'localCoverImages' directory under external storage.
/// - Deletes files not referenced by any mapping.
/// Safe to run at app start or from a settings screen.
Future<void> cleanupUnusedCoverImages() async {
  try {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return;

    final coverDir = Directory(p.join(ext.path, 'localCoverImages'));
    if (!await coverDir.exists()) return;

    final store = CoverImageStore();
    final mapped = Set<String>.from(await store.values());

    await for (final ent in coverDir.list()) {
      if (ent is File) {
        final presentInMap = mapped.contains(ent.path);
        if (!presentInMap) {
          try { await ent.delete(); } catch (_) {}
        }
      }
    }

    // Also prune stale mappings (files deleted elsewhere)
    final box = await Hive.openBox(kCoverMappingBox);
    final keys = box.keys.toList(growable: false);
    for (final key in keys) {
      final val = box.get(key);
      if (val is String && val.isNotEmpty) {
        final f = File(decodePath(val));
        if (!await f.exists()) {
          try { await box.delete(key); } catch (_) {}
        }
      }
    }
  } catch (_) {
    // best-effort cleanup; ignore errors
  }
}
