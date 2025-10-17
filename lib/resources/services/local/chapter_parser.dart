import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/*
 * Parsing Method Credit: https://github.com/PaulWoitaschek/Voice/
 */

/// Public chapter cue.
class ChapterCue {
  final int startMs;
  final String title;
  const ChapterCue({required this.startMs, required this.title});
}

/// Voice-style parser (single entry point):
/// 1) MP3 ID3v2 CHAP frames
/// 2) MP4/M4B Nero 'chpl' atom
/// 3) MP4 chapter text track (tx3g) fallback
class ChapterParser {
  static Future<List<ChapterCue>> parseFile(File file) async {
    final lower = file.path.toLowerCase();
    final bytes = await file.readAsBytes();
    if (bytes.length < 10) return const [];

    // MP3: ID3 at the head
    if (_startsWith(bytes, [0x49, 0x44, 0x33])) {
      final mp3 = _parseMp3Id3Chapters(bytes);
      if (mp3.isNotEmpty) return mp3;
    }

    // MP4-family
    if (lower.endsWith('.m4b') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.mp4')) {
      // 1) Nero chpl
      final chpl = _parseMp4Chpl(bytes);
      if (chpl.isNotEmpty) return chpl;
      // 2) Chapter track fallback
      final trackCues = await _Mp4ChapterTrack.extract(file);
      if (trackCues.isNotEmpty) return trackCues;
      return const [];
    }

    // Last chance sniffers for unknown extensions
    final mp3 = _parseMp3Id3Chapters(bytes);
    if (mp3.isNotEmpty) return mp3;
    final chpl = _parseMp4Chpl(bytes);
    if (chpl.isNotEmpty) return chpl;
    final trackCues = await _Mp4ChapterTrack.extract(file);
    return trackCues;
  }

  // ───────────── MP3: ID3v2 CHAP frames ─────────────

  static List<ChapterCue> _parseMp3Id3Chapters(Uint8List data) {
    if (data.length < 10) return const [];
    if (!(data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33)) {
      return const [];
    }

    final version = data[3]; // 2,3,4
    final tagSize = _syncsafeToInt(data.sublist(6, 10));
    if (10 + tagSize > data.length) return const [];
    final tag = data.sublist(10, 10 + tagSize);

    final cues = <_Chap>{};
    int p = 0;
    while (p + 10 <= tag.length) {
      final frameId = _latin(tag, p, 4);
      final frameSize = (version == 4)
          ? _syncsafeToInt(tag.sublist(p + 4, p + 8))
          : _u32be(tag.sublist(p + 4, p + 8));
      p += 10;
      if (frameSize <= 0 || p + frameSize > tag.length) break;

      final body = tag.sublist(p, p + frameSize);
      p += frameSize;

      if (frameId != 'CHAP') continue;

      int i = 0;
      final idEnd = body.indexOf(0x00, i);
      final elementId = (idEnd >= 0) ? _latin(body, i, idEnd - i) : 'Chapter';
      i = (idEnd >= 0) ? idEnd + 1 : 0;

      if (i + 16 > body.length) continue;
      final start = _u32be(body.sublist(i, i + 4));
      i += 16; // skip end + offsets

      String? title;
      int j = i;
      while (j + 10 <= body.length) {
        final subId = _latin(body, j, 4);
        final subSize = (version == 4)
            ? _syncsafeToInt(body.sublist(j + 4, j + 8))
            : _u32be(body.sublist(j + 4, j + 8));
        j += 10;
        if (subSize <= 0 || j + subSize > body.length) break;

        final sub = body.sublist(j, j + subSize);
        j += subSize;

        if (subId == 'TIT2' && sub.isNotEmpty) {
          final enc = sub[0]; // 0=latin1,1=utf16,3=utf8
          final textBytes = sub.sublist(1);
          title = _decodeId3Text(enc, textBytes)?.trim();
        }
      }

      cues.add(_Chap(startMs: start, title: title ?? elementId));
    }

    final out = cues
        .map((c) => ChapterCue(startMs: c.startMs, title: c.title))
        .toList();
    out.sort((a, b) => a.startMs.compareTo(b.startMs));
    return out;
  }

  // ───────────── MP4/M4B: Nero 'chpl' (fast path) ─────────────

  static List<ChapterCue> _parseMp4Chpl(Uint8List data) {
    final result = <ChapterCue>[];

    void walk(int start, int end) {
      int off = start;
      while (off + 8 <= end) {
        int size = _u32(data, off);
        if (size < 8 && size != 1) break;
        final type = _type(data, off + 4);
        int header = 8;

        if (size == 1) {
          if (off + 16 > end) break;
          final hi = _u32(data, off + 8);
          final lo = _u32(data, off + 12);
          size = (hi * 0x100000000) + lo;
          header = 16;
        }

        final boxStart = off + header;
        final boxEnd = (off + size).clamp(0, data.length);

        if (type == 'chpl') {
          final b = data.sublist(boxStart, boxEnd);
          if (b.length >= 5) {
            final count = b[4];
            int i = 5;
            for (int n = 0; n < count; n++) {
              if (i + 9 > b.length) break;
              final time = _u64(b, i);
              i += 8;
              final len = b[i++];

              if (i + len > b.length) break;
              final title =
                  utf8.decode(b.sublist(i, i + len), allowMalformed: true);
              i += len;

              final ms = (time > 0x7FFFFFFF) ? (time ~/ 1000) : time; // guard
              result.add(ChapterCue(
                startMs: ms,
                title: title.isNotEmpty ? title : 'Chapter ${n + 1}',
              ));
            }
          }
        } else if (_isContainer(type)) {
          final childStart = (type == 'meta' && boxStart + 4 <= boxEnd)
              ? boxStart + 4
              : boxStart;
          walk(childStart, boxEnd);
        }

        off += size;
      }
    }

    walk(0, data.length);
    result.sort((a, b) => a.startMs.compareTo(b.startMs));
    return result;
  }

  // ───────────── helpers ─────────────

  static bool _startsWith(Uint8List b, List<int> sig) {
    if (b.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[i] != sig[i]) return false;
    }
    return true;
  }

  static String _latin(Uint8List b, int start, int len) {
    final end = (start + len).clamp(0, b.length);
    return latin1.decode(b.sublist(start, end));
  }

  static int _syncsafeToInt(Uint8List ss) {
    int v = 0;
    for (final byte in ss) {
      v = (v << 7) | (byte & 0x7F);
    }
    return v;
  }

  static int _u32be(Uint8List b) =>
      (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _u64(Uint8List b, int o) {
    int v = 0;
    for (int i = 0; i < 8; i++) {
      v = (v << 8) | b[o + i];
    }
    return v;
  }

  static bool _isContainer(String type) {
    return {
      'moov',
      'trak',
      'mdia',
      'minf',
      'stbl',
      'tref',
      'edts',
      'udta',
      'meta',
      'ilst',
      'free',
      'skip',
      'uuid',
      '----'
    }.contains(type);
  }

  static String? _decodeId3Text(int enc, Uint8List data) {
    try {
      switch (enc) {
        case 0:
          return latin1.decode(data);
        case 1:
          return _decodeUtf16(data);
        case 3:
          return utf8.decode(data);
        default:
          return utf8.decode(data);
      }
    } catch (_) {
      return utf8.decode(data, allowMalformed: true);
    }
  }

  static String _decodeUtf16(Uint8List bytes, {Endian endian = Endian.big}) {
    if (bytes.isEmpty) return '';
    int offset = 0;
    if (bytes.length >= 2) {
      final b0 = bytes[0], b1 = bytes[1];
      if (b0 == 0xFE && b1 == 0xFF) {
        endian = Endian.big;
        offset = 2;
      } else if (b0 == 0xFF && b1 == 0xFE) {
        endian = Endian.little;
        offset = 2;
      }
    }
    final usableLen = bytes.length - offset;
    final codeUnits = <int>[];
    final bd = ByteData.sublistView(bytes, offset);
    for (int i = 0; i + 1 < usableLen; i += 2) {
      codeUnits.add(bd.getUint16(i, endian));
    }
    return String.fromCharCodes(codeUnits);
  }
}

/// Internal MP4 chapter-track reader (tx3g). Only used if 'chpl' is absent.
class _Mp4ChapterTrack {
  static Future<List<ChapterCue>> extract(File f) async {
    if (!await f.exists()) return const [];
    final raf = await f.open();
    try {
      final len = await raf.length();
      final root = await raf.read(len);
      final ctx = _Ctx(root);

      _walk(ctx, 0, root.length, []);

      final chapId = ctx.chapterTrackId ?? ctx.guessChapterTrackId();
      if (chapId == null) return const [];

      final scale = ctx.timeScale[chapId] ?? 0;
      if (scale <= 0) return const [];

      final stts = ctx.stts[chapId];
      final stsc = ctx.stsc[chapId];
      final stco = ctx.stco[chapId];
      final co64 = ctx.co64[chapId];
      final stsz = ctx.stsz[chapId];
      if (stts == null || stsc == null || stsz == null) return const [];

      final chunkOffsets = (co64 != null && co64.isNotEmpty)
          ? co64
          : (stco ?? const <int>[]).map((e) => e.toInt()).toList();
      if (chunkOffsets.isEmpty) return const [];

      final sampleDur = _expandStts(stts);

      int sampleIndex = 0;
      int ticks = 0;
      final cues = <ChapterCue>[];

      for (int c = 0;
          c < chunkOffsets.length && sampleIndex < stsz.length;
          c++) {
        final samplesInChunk = _samplesPerChunkAt(stsc, c);
        int offset = chunkOffsets[c];
        for (int s = 0; s < samplesInChunk && sampleIndex < stsz.length; s++) {
          final size = stsz[sampleIndex];
          if (size < 2) {
            ticks += (sampleDur.isNotEmpty && sampleIndex < sampleDur.length)
                ? sampleDur[sampleIndex]
                : 0;
            sampleIndex++;
            continue;
          }
          if (offset + size > root.length) return cues;

          final sample = root.sublist(offset, offset + size);
          String title = '';
          if (sample.length >= 2) {
            final textLen = (sample[0] << 8) | sample[1];
            if (2 + textLen <= sample.length && textLen > 0) {
              try {
                title = utf8
                    .decode(sample.sublist(2, 2 + textLen),
                        allowMalformed: true)
                    .trim();
              } catch (_) {
                title = const Latin1Codec()
                    .decode(sample.sublist(2, 2 + textLen), allowInvalid: true)
                    .trim();
              }
            }
            final startMs = (ticks * 1000) ~/ scale;
            cues.add(ChapterCue(
                startMs: startMs,
                title: title.isEmpty ? 'Chapter ${cues.length + 1}' : title));
          }

          ticks += (sampleDur.isNotEmpty && sampleIndex < sampleDur.length)
              ? sampleDur[sampleIndex]
              : 0;
          offset += size;
          sampleIndex++;
        }
      }

      cues.sort((a, b) => a.startMs.compareTo(b.startMs));
      final clean = <ChapterCue>[];
      int last = -1;
      for (final c in cues) {
        if (c.startMs >= 0 && (clean.isEmpty || c.startMs >= last)) {
          clean.add(c);
          last = c.startMs;
        }
      }
      return clean;
    } finally {
      await raf.close();
    }
  }

  // walkers/helpers
  static void _walk(_Ctx ctx, int start, int end, List<String> path) {
    int off = start;
    final data = ctx.data;
    while (off + 8 <= end) {
      int size = _u32(data, off);
      final type = _type(data, off + 4);
      int header = 8;

      if (size == 1) {
        if (off + 16 > end) break;
        final hi = _u32(data, off + 8);
        final lo = _u32(data, off + 12);
        size = (hi * 0x100000000) + lo;
        header = 16;
      }
      if (size < header || off + size > end) break;

      final boxStart = off + header;
      final boxEnd = off + size;

      path.add(type);
      _visit(ctx, path, boxStart, boxEnd);

      if (_isContainer(type)) {
        final childStart = (type == 'meta' && boxStart + 4 <= boxEnd)
            ? boxStart + 4
            : boxStart;
        _walk(ctx, childStart, boxEnd, path);
      }
      path.removeLast();

      off += size;
    }
  }

  static void _visit(_Ctx ctx, List<String> path, int s, int e) {
    if (_endsWith(path, ['trak', 'tkhd'])) {
      final b = ctx.data.sublist(s, e);
      if (b.length < 20) return;
      final version = b[0];
      final has64 = version == 1;
      final trackIdOff = has64 ? 20 : 12;
      if (trackIdOff + 4 <= b.length) {
        final id = _u32(b, trackIdOff);
        ctx.currentTrakId = id;
      }
      return;
    }

    if (_endsWith(path, ['trak', 'tref', 'chap'])) {
      final b = ctx.data.sublist(s, e);
      for (int i = 0; i + 4 <= b.length; i += 4) {
        ctx.chapterTrackId = _u32(b, i);
      }
      return;
    }

    if (_endsWith(path, ['trak', 'mdia', 'mdhd'])) {
      final b = ctx.data.sublist(s, e);
      if (b.length < 24) return;
      final version = b[0];
      final has64 = version == 1;
      final timeScaleOff = has64 ? 20 : 12;
      if (timeScaleOff + 4 <= b.length) {
        final scale = _u32(b, timeScaleOff);
        final id = ctx.currentTrakId;
        if (id != null) ctx.timeScale[id] = scale;
      }
      return;
    }

    if (_endsWith(path, ['trak', 'mdia', 'minf', 'stbl', 'stsd'])) {
      final id = ctx.currentTrakId;
      if (id == null) return;
      final b = ctx.data.sublist(s, e);
      if (b.length < 16) return;
      int p = 8; // ver/flags + entry-count
      if (p + 8 > b.length) return;
      ctx.sampleEntryType[id] = _type(b, p + 4); // e.g., 'tx3g'
      return;
    }

    if (_endsWith(path, ['trak', 'mdia', 'minf', 'stbl', 'stts'])) {
      final id = ctx.currentTrakId;
      if (id == null) return;
      final b = ctx.data.sublist(s, e);
      if (b.length < 8) return;
      int p = 4;
      if (p + 4 > b.length) return;
      final count = _u32(b, p);
      p += 4;
      final out = <(int count, int delta)>[];
      for (int i = 0; i < count; i++) {
        if (p + 8 > b.length) break;
        out.add((_u32(b, p), _u32(b, p + 4)));
        p += 8;
      }
      ctx.stts[id] = out;
      return;
    }

    if (_endsWith(path, ['trak', 'mdia', 'minf', 'stbl', 'stsc'])) {
      final id = ctx.currentTrakId;
      if (id == null) return;
      final b = ctx.data.sublist(s, e);
      if (b.length < 8) return;
      int p = 4;
      if (p + 4 > b.length) return;
      final count = _u32(b, p);
      p += 4;
      final out = <(int firstChunk, int samplesPerChunk, int descIdx)>[];
      for (int i = 0; i < count; i++) {
        if (p + 12 > b.length) break;
        out.add((_u32(b, p), _u32(b, p + 4), _u32(b, p + 8)));
        p += 12;
      }
      ctx.stsc[id] = out;
      return;
    }

    if (_endsWith(path, ['trak', 'mdia', 'minf', 'stbl', 'stco'])) {
      final id = ctx.currentTrakId;
      if (id == null) return;
      final b = ctx.data.sublist(s, e);
      if (b.length < 8) return;
      int p = 4;
      if (p + 4 > b.length) return;
      final count = _u32(b, p);
      p += 4;
      final out = <int>[];
      for (int i = 0; i < count; i++) {
        if (p + 4 > b.length) break;
        out.add(_u32(b, p));
        p += 4;
      }
      ctx.stco[id] = out;
      return;
    }

    if (_endsWith(path, ['trak', 'mdia', 'minf', 'stbl', 'co64'])) {
      final id = ctx.currentTrakId;
      if (id == null) return;
      final b = ctx.data.sublist(s, e);
      if (b.length < 8) return;
      int p = 4;
      if (p + 4 > b.length) return;
      final count = _u32(b, p);
      p += 4;
      final out = <int>[];
      for (int i = 0; i < count; i++) {
        if (p + 8 > b.length) break;
        out.add(_u64(b, p));
        p += 8;
      }
      ctx.co64[id] = out;
      return;
    }

    if (_endsWith(path, ['trak', 'mdia', 'minf', 'stbl', 'stsz'])) {
      final id = ctx.currentTrakId;
      if (id == null) return;
      final b = ctx.data.sublist(s, e);
      if (b.length < 12) return;
      int p = 4;
      final sampleSize = _u32(b, p);
      p += 4;
      final count = _u32(b, p);
      p += 4;
      final out = <int>[];
      if (sampleSize != 0) {
        for (int i = 0; i < count; i++) {
          out.add(sampleSize);
        }
      } else {
        for (int i = 0; i < count; i++) {
          if (p + 4 > b.length) break;
          out.add(_u32(b, p));
          p += 4;
        }
      }
      ctx.stsz[id] = out;
      return;
    }
  }

  static bool _endsWith(List<String> path, List<String> suffix) {
    if (suffix.length > path.length) return false;
    for (int i = 0; i < suffix.length; i++) {
      if (path[path.length - 1 - i] != suffix[suffix.length - 1 - i]) {
        return false;
      }
    }
    return true;
  }

  static List<int> _expandStts(List<(int count, int delta)> stts) {
    final out = <int>[];
    for (final e in stts) {
      for (int i = 0; i < e.$1; i++) {
        out.add(e.$2);
      }
    }
    return out;
  }

  /// stsc.firstChunk is 1-based. Return samples-per-chunk for a 0-based chunk.
  static int _samplesPerChunkAt(
      List<(int firstChunk, int samplesPerChunk, int descIdx)> stsc,
      int chunkIndexZeroBased) {
    final chunkNumber = chunkIndexZeroBased + 1;
    for (int i = 0; i < stsc.length; i++) {
      final entry = stsc[i];
      final next = (i + 1 < stsc.length) ? stsc[i + 1] : null;
      if (chunkNumber >= entry.$1 && (next == null || chunkNumber < next.$1)) {
        return entry.$2;
      }
    }
    return 1;
  }
}

// Minimal MP4 parse context for chapter-track
class _Ctx {
  final Uint8List data;
  _Ctx(this.data);

  int? currentTrakId;
  int? chapterTrackId;

  final Map<int, int> timeScale = {};
  final Map<int, List<(int count, int delta)>> stts = {};
  final Map<int, List<(int firstChunk, int samplesPerChunk, int descIdx)>>
      stsc = {};
  final Map<int, List<int>> stco = {};
  final Map<int, List<int>> co64 = {};
  final Map<int, List<int>> stsz = {};
  final Map<int, String> sampleEntryType = {};

  int? guessChapterTrackId() {
    for (final id in timeScale.keys) {
      final ty = sampleEntryType[id];
      if (ty == 'tx3g' && stsz[id] != null && stsz[id]!.isNotEmpty) {
        final avg = stsz[id]!.fold<int>(0, (a, b) => a + b) ~/ stsz[id]!.length;
        if (avg > 0 && avg < 400) return id;
      }
    }
    return null;
  }
}

// Shared low-level utils (local copies to avoid cross-file deps)
int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _u64(Uint8List b, int o) {
  int v = 0;
  for (int i = 0; i < 8; i++) {
    v = (v << 8) | b[o + i];
  }
  return v;
}

String _type(Uint8List b, int o) => String.fromCharCodes(b.sublist(o, o + 4));

bool _isContainer(String type) {
  return {
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
    'tref',
    'edts',
    'udta',
    'meta',
    'ilst',
    'free',
    'skip',
    'uuid',
    '----'
  }.contains(type);
}

class _Chap {
  final int startMs;
  final String title;
  const _Chap({required this.startMs, required this.title});
  @override
  bool operator ==(Object other) =>
      other is _Chap && startMs == other.startMs && title == other.title;
  @override
  int get hashCode => Object.hash(startMs, title);
}
