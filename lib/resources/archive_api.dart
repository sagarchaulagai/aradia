import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:http/http.dart' as http;
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Fields we want back from Archive.org
const _fields =
    "runtime,avg_rating,num_reviews,title,description,identifier,creator,date,downloads,subject,item_size,language";

/// Map short UI codes to common Archive.org language tokens (2/3-letter codes + English name).
const Map<String, List<String>> _langAliases = {
  'en': ['en', 'eng', 'english'],
  'de': ['de', 'deu', 'ger', 'german'],
  'fr': ['fr', 'fra', 'fre', 'french'],
  'es': ['es', 'spa', 'spanish'],
  'it': ['it', 'ita', 'italian'],
  'pt': ['pt', 'por', 'portuguese'],
  'nl': ['nl', 'nld', 'dut', 'dutch'],
  'ru': ['ru', 'rus', 'russian'],
  'zh': ['zh', 'zho', 'chi', 'chinese'],
  'ja': ['ja', 'jpn', 'japanese'],
  'ar': ['ar', 'ara', 'arabic'],
  'hi': ['hi', 'hin', 'hindi'],
};

/// Build the language clause for Archive.org's `q=` param based on Hive prefs.
/// Returns an empty string if no languages are selected (no filter).
String _languageQueryClause() {
  final box = Hive.box('language_prefs_box');
  final List<String> selected =
  List<String>.from(box.get('selectedLanguages', defaultValue: <String>[]));

  if (selected.isEmpty) return '';

  // language:(eng OR english) OR language:(ger OR deu)
  final parts = <String>[];
  for (final code in selected) {
    final aliases = _langAliases[code.toLowerCase()] ?? [code.toLowerCase()];
    parts.add('language:(${aliases.join('+OR+')})');
  }
  return '+AND+(${parts.join('+OR+')})';
}

/// Build a full advancedsearch URL with a base collection, optional extra query,
/// sorting, paging, and injected language clause.
String _buildAdvancedSearchUrl({
  required String collection,
  String extraQuery = '',
  String sortBy = '',
  required int page,
  required int rows,
}) {
  final lang = _languageQueryClause();
  final sort = sortBy.isNotEmpty ? '&sort[]=$sortBy+desc' : '';

  // q=collection:(librivoxaudio)+AND+(language:...)+AND+(<extraQuery>)
  final qParts = <String>[
    'collection:($collection)',
  ];
  if (lang.isNotEmpty) {
    // `lang` already starts with "+AND+(...)"
    qParts[0] = '${qParts[0]}$lang';
  }
  if (extraQuery.isNotEmpty) {
    // Encode the extra query component to be safe with spaces/ORs, then wrap.
    final enc = Uri.encodeComponent(extraQuery);
    qParts.add('($enc)');
  }
  final q = 'q=${qParts.join('+AND+')}';

  return 'https://archive.org/advancedsearch.php?$q&fl=$_fields$sort&output=json&page=$page&rows=$rows';
}

const Map<String, List<String>> genresSubjectsJson = {
  "adventure": [
    "adventure",
    "exploration",
    "shipwreck",
    "voyage",
    "sea stories",
    "sailing",
    "battle",
    "treasure",
    "frontier",
    "Great War"
  ],
  "biography": [
    "biography",
    "autobiography",
    "memoirs",
    "memoir",
    "George Washington",
    "Life",
    "Jesus",
    "Nederlands"
  ],
  "children": [
    "children",
    "juvenile",
    "juvenile fiction",
    "juvenile literature",
    "kids",
    "fairy tales",
    "fairy tale",
    "nursery rhyme",
    "youth",
    "boys",
    "girls"
  ],
  "comedy": [
    "comedy",
    "humor",
    "satire",
    "farce",
    "mistaken identity",
  ],
  "crime": [
    "crime",
    "murder",
    "detective",
    "mystery",
    "Mystery",
    "thief",
    "suspense",
    "Christian fiction",
    "steal"
  ],
  "fantasy": [
    "fantasy",
    "fairy tales",
    "magic",
    "supernatural",
    "myth",
    "mythology",
    "myths",
    "legends",
    "ghost",
    "ghosts"
  ],
  "horror": [
    "horror",
    "terror",
    "ghost",
    "ghosts",
    "supernatural",
    "suspense",
  ],
  "humor": [
    "humor",
    "comedy",
    "satire",
    "farce",
    "mistaken identity",
  ],
  "love": [
    "romance",
    "love",
    "marriage",
    "love story",
    "relationships",
  ],
  "mystery": [
    "mystery",
    "Mystery",
    "crime",
    "murder",
    "detective",
    "suspense",
    "Christian fiction"
  ],
  "philosophy": [
    "philosophy",
    "ethics",
    "morality",
    "metaphysics",
    "logic",
  ],
  "poem": [
    "poetry",
    "poem",
    "short poetry",
    "long poetry",
    "poems",
    "nursery rhyme"
  ],
  "romance": [
    "romance",
    "love",
    "love story",
    "relationships",
    "marriage",
  ],
  "scifi": [
    "science fiction",
    "sci-fi",
    "space",
    "futurism",
    "technology",
  ],
  "war": [
    "war",
    "soldier",
    "world war",
  ]
};

class ArchiveApi {
  Future<Either<String, List<Audiobook>>> getLatestAudiobook(
      int page,
      int rows,
      ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'addeddate',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getMostViewedWeeklyAudiobook(
      int page,
      int rows,
      ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'week',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getMostDownloadedEverAudiobook(
      int page,
      int rows,
      ) async {
    final url = _buildAdvancedSearchUrl(
      collection: 'librivoxaudio',
      sortBy: 'downloads',
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> getAudiobooksByGenre(
      String genre,
      int page,
      int rows,
      String sortBy,
      ) async {
    final genreQuery = genresSubjectsJson.containsKey(genre.toLowerCase())
        ? genresSubjectsJson[genre.toLowerCase()]!.join(' OR ')
        : genre;

    final url = _buildAdvancedSearchUrl(
      collection: 'audio_bookspoetry',
      extraQuery: 'subject:($genreQuery)',
      sortBy: sortBy,
      page: page,
      rows: rows,
    );
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<AudiobookFile>>> getAudiobookFiles(
      String identifier,
      ) async {
    final url = "https://archive.org/metadata/$identifier/files?output=json";

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final resJson = json.decode(response.body);
        List<AudiobookFile> audiobookFiles = [];
        String? highQCoverImage;

        for (final item in resJson["result"]) {
          if (item["source"] == "original" && item["format"] == "JPEG") {
            highQCoverImage = item["name"];
          }
        }

        for (final item in resJson["result"]) {
          if (item["source"] == "original" && item["track"] != null) {
            item["identifier"] = identifier;
            item["highQCoverImage"] = highQCoverImage;
            audiobookFiles.add(AudiobookFile.fromJson(item));
          }
        }

        return Right(audiobookFiles);
      } else {
        throw Exception('Failed to load audiobook files');
      }
    } catch (e) {
      return Left(e.toString());
    }
  }

  Future<Either<String, List<Audiobook>>> searchAudiobook(
      String searchQuery,
      int page,
      int rows,
      ) async {
    // Encode the free-form query to avoid breaking the `q` param.
    final encoded = Uri.encodeComponent(searchQuery);
    final lang = _languageQueryClause(); // may be empty

    final q =
        '$encoded+AND+collection:(audio_bookspoetry)${lang.isNotEmpty ? lang : ''}';

    final url =
        "https://archive.org/advancedsearch.php?q=$q&fl=$_fields&sort[]=downloads+desc&output=json&page=$page&rows=$rows";
    AppLogger.debug('Search URL: $url', 'ArchiveApi');
    return _fetchAudiobooks(url);
  }

  Future<Either<String, List<Audiobook>>> _fetchAudiobooks(String url) async {
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return Right(Audiobook.fromJsonArray(
            json.decode(response.body)['response']['docs']));
      } else {
        throw Exception('Failed to load audiobooks');
      }
    } catch (e) {
      return Left(e.toString());
    }
  }
}
