// bin/dump_atoms.dart
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/dump_atoms.dart <file.m4b>');
    exit(1);
  }

  final file = File(args.first);
  final data = await file.readAsBytes();
  _walkAtoms(data, 0, data.length, 0);
}

void _walkAtoms(Uint8List data, int start, int end, int depth) {
  int offset = start;
  while (offset + 8 <= end) {
    int size = _readUint32(data, offset);
    final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));
    int header = 8;

    // Extended-size box
    if (size == 1) {
      if (offset + 16 > end) break;
      final hi = _readUint32(data, offset + 8);
      final lo = _readUint32(data, offset + 12);
      size = (hi * 0x100000000) + lo;
      header = 16;
    }

    print('${'  ' * depth}Atom: $type  (size=$size @ $offset)');

    if (size < header) break; // corrupt
    final next = offset + size;
    if (next > end) break;

    // Recurse into common container boxes
    const containers = {
      'moov','trak','mdia','minf','stbl','edts','udta','meta','ilst'
    };
    if (containers.contains(type)) {
      // 'meta' has 4 bytes version/flags before children
      final contentStart = type == 'meta' ? offset + header + 4 : offset + header;
      _walkAtoms(data, contentStart, next, depth + 1);
    }

    offset = next;
  }
}

int _readUint32(Uint8List data, int offset) {
  return (data[offset] << 24) |
  (data[offset + 1] << 16) |
  (data[offset + 2] << 8) |
  (data[offset + 3]);
}
