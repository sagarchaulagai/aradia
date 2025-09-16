// Centralized cover-art mapping + lookup with a tiny in-memory cache and an
// event bus so UIs / the audio handler can react to changes immediately.
// File/folder semantics (what counts as a "book key") are delegated to
// LocalLibraryLayout so you can tweak rules in ONE place.

import 'dart:async';
import 'dart:io';

import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/services/local/local_library_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cover art event bus
// Subscribers (player, history, tiles) can listen and refresh when a cover
// changes for a specific book key.
// payload: the canonical book key (see LocalLibraryLayout.bookKeyForLocal)
class CoverArtBus {
  static final CoverArtBus _i = CoverArtBus._();
  CoverArtBus._();
  factory CoverArtBus() => _i;

  final _ctrl = StreamController<String>.broadcast();
  Stream<String> get stream => _ctrl.stream;

  void emit(String key) {
    if (key.isEmpty) return;
    _ctrl.add(key);
  }
}

final coverArtBus = CoverArtBus();

/// Hive box name for custom cover mappings
const String kCoverMappingBox = 'cover_image_mapping';

// ─────────────────────────────────────────────────────────────────────────────
// Small LRU cache for resolved covers (per canonical book key).
// Caches both hits (String path/URL) and misses (null) to avoid repeated IO.
class _CoverCache {
  static const int _maxEntries = 256;
  final _map = <String, String?>{};

  bool containsKey(String key) => _map.containsKey(key);

  String? get(String key) {
    if (!_map.containsKey(key)) return null;
    final v = _map.remove(key);
    _map[key] = v; // touch
    return v;
  }

  void set(String key, String? value) {
    if (!_map.containsKey(key) && _map.length >= _maxEntries) {
      _map.remove(_map.keys.first); // evict LRU
    }
    _map[key] = value;
  }

  void remove(String key) => _map.remove(key);
  void clear() => _map.clear();
}

final _coverCache = _CoverCache();

// ─────────────────────────────────────────────────────────────────────────────
// Cached Hive box accessor so we don't repeatedly call `Hive.openBox`.
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

// ─────────────────────────────────────────────────────────────────────────────
// Public helpers (keep existing names to avoid touching call sites)

/// Canonical per-book key for local audiobooks.
/// Delegates to LocalLibraryLayout so the rule is defined in one place.
String coverKeyForLocal(LocalAudiobook a) =>
    LocalLibraryLayout.bookKeyForLocal(a);

/// Convert any path/URI to a local filesystem path if possible; null for URLs.
String? asLocalPath(String? s) => LocalLibraryLayout.asLocalPath(s);

/// Decode a path/URI consistently (safe for keys and values).
String decodePath(String s) => LocalLibraryLayout.decodePath(s);

/// Heuristic for "is local (not http/https)".
bool looksLocal(String s) => s.isNotEmpty && LocalLibraryLayout.looksLocal(s);

/// A small helper so widgets can render images without branching.
/// Usage:
///   final v = await resolveCoverForLocal(a);
///   return v != null ? Image(image: coverProvider(v)) : placeholder();
ImageProvider<Object> coverProvider(String v) {
  final local = asLocalPath(v);
  if (local != null) {
    return FileImage(File(local));
  }
  return NetworkImage(v);
}

// ─────────────────────────────────────────────────────────────────────────────
// High-level operations

/// Save a cover for a local audiobook using the canonical key.
/// Also removes any old *folder* mapping to prevent cross-book bleed.
/// Primes the in-memory cache so UI updates immediately.
Future<void> mapCoverForLocal(LocalAudiobook a, String coverImagePath) async {
  final key = coverKeyForLocal(a);
  final normalized = decodePath(coverImagePath);

  await mapCoverImage(key, normalized);

  // Remove legacy per-folder mapping if different from canonical key.
  final folderKey = decodePath(a.folderPath);
  if (folderKey != key) {
    await removeCoverMapping(folderKey);
  }

  _coverCache.set(key, normalized);
  coverArtBus.emit(key); // notify listeners
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
      final local = asLocalPath(cached);
      if (local == null || await File(local).exists()) return cached;
      _coverCache.remove(key); // stale file → evict and recompute
    } else {
      return null; // cached miss
    }
  }

  // 1) Preferred mapping by canonical key
  final byKey = await getMappedCoverImage(key);
  if (byKey != null) {
    _coverCache.set(key, byKey);
    return byKey;
  }

  // 2) Legacy id-based mapping (older code may have saved a.id)
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

  // 4) Explicit/embedded cover on the model
  final explicit =
      a.coverImagePath == null ? null : decodePath(a.coverImagePath!);
  if (explicit != null && await File(explicit).exists()) {
    _coverCache.set(key, explicit);
    return explicit;
  }

  // Nothing found; cache the miss.
  _coverCache.set(key, null);
  return null;
}

/// Only the metadata/embedded default (used for "Use Default" tile preview).
Future<String?> resolveDefaultCoverForLocal(LocalAudiobook a) async {
  final explicit =
      a.coverImagePath == null ? null : decodePath(a.coverImagePath!);
  if (explicit != null && await File(explicit).exists()) {
    return explicit;
  }
  return null;
}

/// Resolve artwork for a History tile.
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

  // 2) Legacy keys from the first track
  final firstPath = LocalLibraryLayout.firstTrackLocalPath(item);
  if (firstPath != null && firstPath.isNotEmpty) {
    final byFile = await getMappedCoverImage(firstPath);
    if (byFile != null) return byFile;

    final folder =
        LocalLibraryLayout.bookFolderFromHistory(item) ?? p.dirname(firstPath);
    final byFolder = await getMappedCoverImage(folder);
    if (byFolder != null) return byFolder;
  }

  // 3) Fallback: audiobook's cover (can be file or URL)
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

// ─────────────────────────────────────────────────────────────────────────────
// Low-level mapping helpers

/// Get mapped cover for a key (verifies file exists; prunes stale entries).
Future<String?> getMappedCoverImage(String key) async {
  if (key.isEmpty) return null;
  final store = CoverImageStore();
  final mapped = await store.get(key);
  if (mapped == null) return null;

  final normalized = decodePath(mapped);
  final f = File(normalized);
  if (await f.exists()) return f.path;

  // Prune stale mapping if the file is gone.
  await store.delete(key);
  return null;
}

/// Put a mapping (expects absolute path to an image file or a URL).
Future<void> mapCoverImage(String key, String coverImagePath) async {
  if (key.isEmpty) return;
  final store = CoverImageStore();
  await store.put(key, decodePath(coverImagePath));
  _coverCache.set(key, coverImagePath);
  coverArtBus.emit(key); // notify listeners
}

/// Remove a mapping; if it points to a local file under our control, delete it.
Future<void> removeCoverMapping(String key) async {
  if (key.isEmpty) return;
  final store = CoverImageStore();
  final path = await store.get(key);
  if (path != null) {
    final local = asLocalPath(path);
    if (local != null) {
      final f = File(local);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
  await store.delete(key);
  _coverCache.remove(key);
  coverArtBus.emit(key); // notify listeners
}

// Optional explicit invalidation helpers, if other modules need them.
void invalidateCoverForLocal(LocalAudiobook a) {
  _coverCache.remove(coverKeyForLocal(a));
}

void invalidateCoverByKey(String key) {
  _coverCache.remove(key);
}

// ─────────────────────────────────────────────────────────────────────────────
// Optional housekeeping to remove orphaned images and stale mappings.
Future<void> cleanupUnusedCoverImages() async {
  try {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return;

    final coverDir = Directory(p.join(ext.path, 'localCoverImages'));
    if (!await coverDir.exists()) return;

    final store = CoverImageStore();
    final mapped = Set<String>.from(await store.values());

    // Delete files in the cover folder that are not referenced by any mapping.
    await for (final ent in coverDir.list()) {
      if (ent is File) {
        final presentInMap = mapped.contains(ent.path);
        if (!presentInMap) {
          try {
            await ent.delete();
          } catch (_) {}
        }
      }
    }

    // Also prune stale mappings (files deleted elsewhere)
    final box = await Hive.openBox(kCoverMappingBox);
    final keys = box.keys.toList(growable: false);
    for (final key in keys) {
      final val = box.get(key);
      if (val is String && val.isNotEmpty) {
        final local = asLocalPath(val);
        if (local != null && !await File(local).exists()) {
          try {
            await box.delete(key);
          } catch (_) {}
        }
      }
    }
  } catch (_) {
    // best-effort cleanup; ignore errors
  }
}
