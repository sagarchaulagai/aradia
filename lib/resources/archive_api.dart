import 'dart:convert';
import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:http/http.dart' as http;
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Fields we want back from Archive.org
const _fields =
    "runtime,avg_rating,num_reviews,title,description,identifier,creator,date,downloads,subject,item_size,language";

/// Map UI language codes to Archive.org language tokens (2/3-letter codes + English name).
/// IMPORTANT: No Hindi (hi) because LibriVox has no Hindi catalog.
const Map<String, List<String>> _langAliases = {
  'en': ['en', 'eng', 'english'],
  'de': ['de', 'deu', 'ger', 'german'],
  'es': ['es', 'spa', 'spanish'],
  'fr': ['fr', 'fra', 'fre', 'french'],
  'nl': ['nl', 'nld', 'dut', 'dutch'],
  'mul': ['mul', 'multiple', 'multilingual'],
  'pt': ['pt', 'por', 'portuguese'],
  'it': ['it', 'ita', 'italian'],
  'ru': ['ru', 'rus', 'russian'],
  'el': ['el', 'ell', 'greek'],
  'grc': ['grc', 'ancient greek', 'ancient', 'greek'], // Ancient Greek
  'ja': ['ja', 'jpn', 'japanese'],
  'pl': ['pl', 'pol', 'polish'],
  'zh': ['zh', 'zho', 'chi', 'chinese'],
  'he': ['he', 'heb', 'hebrew'],
  'la': ['la', 'lat', 'latin'],
  'fi': ['fi', 'fin', 'finnish'],
  'sv': ['sv', 'swe', 'swedish'],
  'ca': ['ca', 'cat', 'catalan'],
  'da': ['da', 'dan', 'danish'],
  'eo': ['eo', 'epo', 'esperanto'],
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
    final aliases = _langAliases[code.toLowerCase()];
    if (aliases == null) {
      // Ignore legacy/unsupported selections safely (e.g., 'hi').
      continue;
    }
    parts.add('language:(${aliases.join('+OR+')})');
  }
  if (parts.isEmpty) return '';
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

/// Base English seeds per category (kept for backfill and for English itself).
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

/// ========= File-driven language subject index =========
/// We load your language→all-subjects dump from an asset and parse into a Map.
/// Expected file format (your provided dump):
///   "===== english ===== <comma-separated subjects>"
///   "===== german  ===== <comma-separated subjects>"
class _LanguageSubjectIndex {
  static Map<String, List<String>>? _cache; // langKey(lower) -> subjects
  static final _langHeader = RegExp(r'^=+\s*([a-zA-Z ]+)\s*=+\s*$');

  /// Map friendly language header to our UI code in _langAliases.
  static final Map<String, String> _nameToUiCode = {
    'english': 'en',
    'german': 'de',
    'spanish': 'es',
    'french': 'fr',
    'dutch': 'nl',
    'multiple': 'mul',
    'portuguese': 'pt',
    'italian': 'it',
    'russian': 'ru',
    'greek': 'el',
    'ancient greek': 'grc',
    'japanese': 'ja',
    'polish': 'pl',
    'chinese': 'zh',
    'hebrew': 'he',
    'latin': 'la',
    'finnish': 'fi',
    'swedish': 'sv',
    'catalan': 'ca',
    'danish': 'da',
    'esperanto': 'eo',
  };

  static Future<void> ensureLoaded() async {
    if (_cache != null) return;
    final raw = await rootBundle.loadString('assets/language_subjects.txt');
    final map = <String, List<String>>{};
    String? currentLangCode;
    final buf = StringBuffer();
    for (final line in const LineSplitter().convert(raw)) {
      final m = _langHeader.firstMatch(line.trim());
      if (m != null) {
        // flush previous
        if (currentLangCode != null) {
          final items = buf
              .toString()
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList();
          map[currentLangCode!] = items;
          buf.clear();
        }
        final headerName = m.group(1)!.toLowerCase();
        currentLangCode = _nameToUiCode[headerName];
        continue;
      }
      if (currentLangCode != null) {
        if (buf.isNotEmpty) buf.write(', ');
        buf.write(line);
      }
    }
    if (currentLangCode != null) {
      final items = buf
          .toString()
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      map[currentLangCode!] = items;
    }
    _cache = map;
    AppLogger.info('Loaded language subjects for ${_cache!.length} languages',
        'ArchiveApi');
  }

  static List<String> subjectsFor(String uiCode) {
    final c = _cache;
    if (c == null) return const [];
    return c[uiCode.toLowerCase()] ?? const [];
  }
}

/// Category→regex filters that capture category semantics across languages.
/// Built from language_subjects.txt (multi-language subjects) and expanded with
/// obvious cognates, historical conflicts, and variants.
final Map<String, List<RegExp>> _categoryFilters = {
  'war': [
    // English
    RegExp(r'\bwar\b', caseSensitive: false),
    RegExp(r'\bworld\s*war\b', caseSensitive: false),
    RegExp(r"\bthirty\s*years'?\s*war\b", caseSensitive: false),
    // German
    RegExp(r'\bkrieg\b', caseSensitive: false),
    RegExp(r'\bweltkrieg\b', caseSensitive: false),
    RegExp(r'\bdrei(ss|ß)igj[aä]hrige[rsn]?\s*krieg\b', caseSensitive: false),
    RegExp(r'\berster\s*weltkrieg\b', caseSensitive: false),
    RegExp(r'\bzweiter\s*weltkrieg\b', caseSensitive: false),
    RegExp(r'\bkreuzz(u|ü)ge?\b', caseSensitive: false),
    RegExp(r'\bboxeraufstand\b', caseSensitive: false),
    RegExp(r'\bburgunderkrieg\b', caseSensitive: false),
    RegExp(r'\bhererokrieg\b', caseSensitive: false),
    RegExp(r'\bnationalsozialismus\b', caseSensitive: false),
    // Romance langs
    RegExp(r'\bguerre\b', caseSensitive: false), // fr
    RegExp(r'\bguerra\b', caseSensitive: false), // es/it/pt
    // Russian / Slavic
    RegExp(r'войн', caseSensitive: false),
    RegExp(r'мировая', caseSensitive: false),
    RegExp(r'крестов(ый|ые)\s*поход', caseSensitive: false),
    RegExp(r'дридцатилетн|тридцатилетн', caseSensitive: false),
    // Scandinavian
    RegExp(r'\bkrig\b', caseSensitive: false), // sv/da/no
    // East Asian
    RegExp(r'戦争|世界大戦'), // ja/zh
    // General
    RegExp(r'\bmilit(ar|är|aire|are|are)\b', caseSensitive: false),
    RegExp(r'\bcrusad(e|es)\b', caseSensitive: false),
  ],
  'adventure': [
    RegExp(r'\badventur', caseSensitive: false),
    RegExp(r'\baventur', caseSensitive: false), // fr/es/it/pt
    RegExp(r'\babenteuer\b', caseSensitive: false), // de
    RegExp(r'\bseikkailu\b', caseSensitive: false), // fi
    RegExp(r'\bäventyr\b', caseSensitive: false), // sv
    RegExp(r'\bviaje|viajar|voyage|viagem\b', caseSensitive: false),
    RegExp(r'\bexplor', caseSensitive: false), // exploration
  ],
  'biography': [
    RegExp(r'\bbiograph', caseSensitive: false),
    RegExp(r'\bbiograf', caseSensitive: false),
    RegExp(r'\bmemoi', caseSensitive: false),
    RegExp(r'\blebensbeschreib', caseSensitive: false), // de
    RegExp(r'\bvida\b', caseSensitive: false), // es/pt
    RegExp(r'\bvie\b', caseSensitive: false), // fr
  ],
  'children': [
    RegExp(r'\bchildren\b', caseSensitive: false),
    RegExp(r'\bjuvenil|juvenile\b', caseSensitive: false),
    RegExp(r'\benfant|enfants\b', caseSensitive: false),
    RegExp(r'\bkind(er)?\b', caseSensitive: false), // de
    RegExp(r'\bbarn\b', caseSensitive: false), // sv/no
    RegExp(r'\bniñ[oa]s?\b', caseSensitive: false), // es
    RegExp(r'\bragazzi\b', caseSensitive: false), // it
    RegExp(r'\bboys|girls|kids\b', caseSensitive: false),
    RegExp(r'\bfairy tale|nursery rhyme\b', caseSensitive: false),
  ],
  'comedy': [
    RegExp(r'\bcomedy|\bhumou?r|\bsatire|\bfarce', caseSensitive: false),
    RegExp(r'\bcom(è|e)die\b', caseSensitive: false), // fr
    RegExp(r'\bkom(ö|o)die\b', caseSensitive: false), // de
    RegExp(r'\bsátira\b', caseSensitive: false), // es/pt
    RegExp(r'\bsatira\b', caseSensitive: false), // it/eo
  ],
  'crime': [
    RegExp(r'\bcrime|detective|murder|mystery|suspense', caseSensitive: false),
    RegExp(r'\bcrimen\b', caseSensitive: false), // es
    RegExp(r'\bdelitto\b', caseSensitive: false), // it
    RegExp(r'\bkriminal\b', caseSensitive: false), // de
    RegExp(r'\bforbrydelse\b', caseSensitive: false), // da
  ],
  'fantasy': [
    RegExp(r'\bfantasy\b', caseSensitive: false),
    RegExp(r'\bfantast', caseSensitive: false), // stems
    RegExp(r'\bmyth', caseSensitive: false),
    RegExp(r'\bmytholog', caseSensitive: false),
    RegExp(r'\blegend', caseSensitive: false),
    RegExp(r'\bghost', caseSensitive: false),
    RegExp(r'\bconte de fées\b', caseSensitive: false), // fr fairy tale
  ],
  'horror': [
    RegExp(r'\bhorror\b', caseSensitive: false),
    RegExp(r'\bterror\b', caseSensitive: false),
    RegExp(r'\bghost\b', caseSensitive: false),
    RegExp(r'\bsupernatural\b', caseSensitive: false),
    RegExp(r'\bespanto\b', caseSensitive: false), // es/pt
    RegExp(r'\bgespenst\b', caseSensitive: false), // de
  ],
  'love': [
    RegExp(r'\bromance\b', caseSensitive: false),
    RegExp(r'\blove( story)?\b', caseSensitive: false),
    RegExp(r'\bmarriage\b', caseSensitive: false),
    RegExp(r'\brelationship', caseSensitive: false),
    RegExp(r'\bamour\b', caseSensitive: false), // fr
    RegExp(r'\bamore\b', caseSensitive: false), // it
    RegExp(r'\bamor\b', caseSensitive: false), // es/pt
    RegExp(r'\brakkaus\b', caseSensitive: false), // fi
  ],
  'mystery': [
    RegExp(r'\bmystery\b', caseSensitive: false),
    RegExp(r'\bdetective\b', caseSensitive: false),
    RegExp(r'\bcrime\b', caseSensitive: false),
    RegExp(r'\bmurder\b', caseSensitive: false),
    RegExp(r'\bsuspense\b', caseSensitive: false),
    RegExp(r'\bkrimi\b', caseSensitive: false), // de shorthand
  ],
  'philosophy': [
    RegExp(r'\bphilosoph', caseSensitive: false),
    RegExp(r'\bfilosof', caseSensitive: false), // es/pt/it
    RegExp(r'\bfilosofi', caseSensitive: false), // sv
    RegExp(r'\bfilozof', caseSensitive: false), // pl
    RegExp(r'\bphilosophia\b', caseSensitive: false), // la
  ],
  'poem': [
    RegExp(r'\bpoe(m|try|ms)\b', caseSensitive: false),
    RegExp(r'\bpoesi', caseSensitive: false),
    RegExp(r'\bpoez(j|í|i)a\b', caseSensitive: false),
    RegExp(r'\bgedicht\b', caseSensitive: false), // de
    RegExp(r'\bvers\b', caseSensitive: false), // fr/es/pt
    RegExp(r'\bstih\b', caseSensitive: false), // slavic
  ],
  'romance': [
    RegExp(r'\bromance\b', caseSensitive: false),
    RegExp(r'\blove( story)?\b', caseSensitive: false),
    RegExp(r'\bamou?r\b', caseSensitive: false),
    RegExp(r'\bamore\b', caseSensitive: false),
    RegExp(r'\bamor\b', caseSensitive: false),
    RegExp(r'\brakkaus\b', caseSensitive: false),
  ],
  'scifi': [
    RegExp(r'\bscience fiction\b', caseSensitive: false),
    RegExp(r'\bsci-?fi\b', caseSensitive: false),
    RegExp(r'\bfic(ci[oó]n|ção)\s+cient', caseSensitive: false), // es/pt
    RegExp(r'\bfantascien', caseSensitive: false), // it
    RegExp(r'\bfiktion\b', caseSensitive: false), // de
    RegExp(r'\bfutur(ism|o)\b', caseSensitive: false),
    RegExp(r'\btechnolog', caseSensitive: false),
  ],
};

/// Build subject OR-clause for a category by merging:
///  - base English seeds (genresSubjectsJson),
///  - all subjects from each selected language that match the category filters.
Future<String> _buildSubjectQueryForGenre(String genreLower) async {
  await _LanguageSubjectIndex.ensureLoaded();
  final base = genresSubjectsJson[genreLower] ?? <String>[genreLower];

  // Selected UI language codes
  final box = Hive.box('language_prefs_box');
  final selected = List<String>.from(
    box.get('selectedLanguages', defaultValue: <String>[]),
  )
      .map((c) => c.toLowerCase())
      .where((c) => _langAliases.containsKey(c))
      .toList();

  final filters = _categoryFilters[genreLower] ?? const <RegExp>[];
  final tokens = {...base}; // set
  for (final code in selected) {
    final subjects = _LanguageSubjectIndex.subjectsFor(code);
    if (subjects.isEmpty) continue;
    if (filters.isEmpty) {
      tokens.addAll(subjects);
    } else {
      for (final s in subjects) {
        if (filters.any((re) => re.hasMatch(s))) tokens.add(s);
      }
    }
  }
  // Fallback: if filtering produced only base, include a couple of obvious language stems to avoid empties.
  if (tokens.length == base.length) {
    for (final code in selected) {
      switch (genreLower) {
        case 'war':
          tokens.addAll(['guerra', 'guerre', 'Krieg', 'война']);
          break;
        case 'adventure':
          tokens.addAll(['aventura', 'aventure', 'Abenteuer']);
          break;
      }
    }
  }
  return tokens.join(' OR ');
}

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
    final genreQuery = genre
        .split(RegExp(r'\s+OR\s+',
            caseSensitive: false)) // split by any 'OR' variant
        .map((s) => s.trim().toLowerCase())
        .join(' OR '); // join back with uppercase OR

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
