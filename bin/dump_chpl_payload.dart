// bin/dump_chpl_payload.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('usage: dart run bin/dump_chpl_payload.dart <file.m4b>');
    exit(64);
  }
  final f = File(args.first);
  final data = await f.readAsBytes();

  // Walk to find first 'chpl' atom (handles extended-size boxes)
  int off = 0;
  while (off + 8 <= data.length) {
    int size = _u32(data, off);
    if (size < 8 && size != 1) break;
    final type = _fourCC(data, off + 4);
    int header = 8;
    if (size == 1) {
      if (off + 16 > data.length) break;
      final hi = _u32(data, off + 8);
      final lo = _u32(data, off + 12);
      size = (hi * 0x100000000) + lo;
      header = 16;
    }
    if (type == 'moov' || type == 'trak' || type == 'mdia' || type == 'minf' ||
        type == 'stbl' || type == 'edts' || type == 'udta' || type == 'ilst') {
      // Scan children
      _walk(data, off + header, off + size);
      break;
    } else if (type == 'chpl') {
      _dumpChpl(data.sublist(off + header, off + size));
      break;
    }
    off += size;
  }
}

void _walk(Uint8List d, int start, int end) {
  int off = start;
  while (off + 8 <= end) {
    int size = _u32(d, off);
    if (size < 8 && size != 1) break;
    final type = _fourCC(d, off + 4);
    int header = 8;
    if (size == 1) {
      if (off + 16 > end) break;
      final hi = _u32(d, off + 8);
      final lo = _u32(d, off + 12);
      size = (hi * 0x100000000) + lo;
      header = 16;
    }
    final boxEnd = off + size;

    if (type == 'meta') {
      // meta has 4 bytes ver/flags then children
      if (off + header + 4 < boxEnd) {
        _walk(d, off + header + 4, boxEnd);
      }
    } else if (type == 'chpl') {
      _dumpChpl(d.sublist(off + header, boxEnd));
      return;
    } else if (type == 'moov' || type == 'trak' || type == 'mdia' ||
        type == 'minf' || type == 'stbl' || type == 'edts' ||
        type == 'udta' || type == 'ilst') {
      _walk(d, off + header, boxEnd);
    }

    off = boxEnd;
  }
}

void _dumpChpl(Uint8List body) {
  print('chpl payload ${body.length} bytes');
  final head = body.take(32).toList();
  print('first bytes: ${head.map((b)=>b.toRadixString(16).padLeft(2,"0")).join(" ")}');

  // Try to parse with several header/time variants and print the first sane result.
  final variants = <(String name,int hdr,int tbytes)>[
    ('ver+flags+count(u64),time(u64)', 5, 8),
    ('ver+flags+count(u64),time(u32)', 5, 4),
    ('ver+flags+count(u8),time(u64)',  1, 8),
    ('ver+flags+count(u32),time(u64)', 2, 8),
    ('ver+flags+count(u8),time(u32)',  1, 4),
    ('ver+flags+count(u32),time(u32)', 2, 4),
    ('count(u8),time(u64)',            3, 8),
    ('count(u32),time(u64)',           4, 8),
    ('count(u8),time(u32)',            3, 4),
    ('count(u32),time(u32)',           4, 4),
    ('no-header,time(u64)',            0, 8),
    ('no-header,time(u32)',            0, 4),
  ];

  for (final (name,hdr,tb) in variants) {
    final parsed = _tryParse(body, headerKind: hdr, timeBytes: tb);
    if (parsed != null) {
      print('decoded using: $name');
      for (int i = 0; i < parsed.length; i++) {
        final e = parsed[i];
        print('  [${i}] t=${e.$1}ms  "${e.$2}"');
      }
      return;
    }
  }

  print('could not decode chpl with known variants.');
}

List<(int,String)>? _tryParse(Uint8List body, {required int headerKind, required int timeBytes}) {
  int p = 0;
  int count;

  int maybeMicrosToMillis(int t) => (t >= 10000000) ? (t ~/ 1000) : t;

  if (headerKind == 1) {
    if (body.length < 5) return null;
    p = 1 + 3; // ver + flags
    count = body[p];
    p += 1;
  } else if (headerKind == 2) {
    if (body.length < 8) return null;
    p = 1 + 3;
    if (p + 4 > body.length) return null;
    count = _u32(body, p);
    p += 4;
  } else if (headerKind == 5) {
    if (body.length < 12) return null;
    p = 1 + 3;
    if (p + 8 > body.length) return null;
    final c64 = _u64(body, p);
    if (c64 > 0x7fffffff) return null;
    count = c64.toInt();
    p += 8;
  } else if (headerKind == 3) {
    if (body.length < 1) return null;
    count = body[p];
    p += 1;
  } else if (headerKind == 4) {
    if (body.length < 4) return null;
    count = _u32(body, p);
    p += 4;
  } else {
    // greedy
    final out = <(int,String)>[];
    while (true) {
      if (p + timeBytes + 1 > body.length) break;
      final t = (timeBytes == 8) ? _u64(body, p) : _u32(body, p);
      p += timeBytes;
      final l = body[p]; p += 1;
      if (p + l > body.length) return null;
      final s = utf8.decode(body.sublist(p, p + l), allowMalformed: true).trim();
      p += l;
      out.add((maybeMicrosToMillis(t), s.isEmpty ? 'Chapter ${out.length}' : s));
    }
    return _sane(out) ? out : null;
  }

  final out = <(int,String)>[];
  for (int i = 0; i < count; i++) {
    if (p + timeBytes + 1 > body.length) return null;
    final t = (timeBytes == 8) ? _u64(body, p) : _u32(body, p);
    p += timeBytes;
    final l = body[p]; p += 1;
    if (p + l > body.length) return null;
    final s = utf8.decode(body.sublist(p, p + l), allowMalformed: true).trim();
    p += l;
    out.add((maybeMicrosToMillis(t), s.isEmpty ? 'Chapter ${i + 1}' : s));
  }
  return _sane(out) ? out : null;
}

bool _sane(List<(int,String)> entries) {
  if (entries.isEmpty) return false;
  for (int i = 1; i < entries.length; i++) {
    if (entries[i].$1 < entries[i-1].$1) return false;
  }
  return true;
}

String _fourCC(Uint8List d, int off) =>
    String.fromCharCodes(d.sublist(off, off + 4));

int _u32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

int _u64(Uint8List b, int o) {
  int v = 0;
  for (int i = 0; i < 8; i++) v = (v << 8) | b[o + i];
  return v;
}
