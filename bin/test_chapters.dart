import 'dart:io';
import 'package:aradia/resources/services/chapter_parser.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/test_chapters.dart <path-to-m4b>');
    exit(1);
  }

  final f = File(args.first);
  final cues = await ChapterParser.parseFile(f);
  print("chapters: ${cues.length}");
  for (var i = 0; i < cues.length; i++) {
    final c = cues[i];
    print("${i + 1}. ${c.startMs}ms  ${c.title}");
  }
}
