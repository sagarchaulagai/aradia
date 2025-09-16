import 'dart:convert';
import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:http/http.dart' as http;
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show listEquals;

// ─── Simple HTTP cache with ETag/Last-Modified ────────────────────────────────
class _CacheEntry {
  final String body;
  final String? etag;
  final String? lastModified;
  final DateTime storedAt;
  _CacheEntry({
    required this.body,
    this.etag,
    this.lastModified,
    required this.storedAt,
  });
}

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

// Memoize language clause across calls until prefs change
String? _memoLangClause;
List<String>? _memoSelected;
void _invalidateLangMemo() {
  _memoLangClause = null;
  _memoSelected = null;
}

// Memoize genre→subject OR clause per current language selection
final Map<String, String> _genreSubjectMemo = {}; // key: "<langs>#<genre>"

/// Build the language clause for Archive.org's `q=` param based on Hive prefs.
/// Returns an empty string if no languages are selected (no filter).
String _languageQueryClause() {
  final box = Hive.box('language_prefs_box');
  final selected = List<String>.from(
    box.get('selectedLanguages', defaultValue: <String>[]),
  );

  // Fast path if nothing changed
  if (_memoSelected != null &&
      _memoLangClause != null &&
      listEquals(selected, _memoSelected)) {
    return _memoLangClause!;
  }

  if (selected.isEmpty) {
    _memoSelected = selected;
    _memoLangClause = '';
    return '';
  }

  final parts = <String>[];
  for (final code in selected) {
    final aliases = _langAliases[code.toLowerCase()];
    if (aliases == null) continue; // ignore unsupported like 'hi'
    parts.add('language:(${aliases.join('+OR+')})');
  }
  if (parts.isEmpty) {
    _memoSelected = selected;
    _memoLangClause = '';
    return '';
  }
  final clause = '+AND+(${parts.join('+OR+')})';
  _memoSelected = selected;
  _memoLangClause = clause;
  return clause;
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
  "religion":[
    "religion",
    "god",
    "theology",
    "bible",
    "jesus",
    "christ",
    "quran",
    "buddha"
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
    // ===== English =====
    RegExp(r'\bwar(s)?\b', caseSensitive: false),
    RegExp(r'\bworld\s*war(s)?\b', caseSensitive: false),
    RegExp(r'\bww[i1]\b', caseSensitive: false),
    RegExp(r'\bwwii\b', caseSensitive: false),
    RegExp(r'\bww2\b', caseSensitive: false),
    RegExp(r'\bgreat\s+war\b', caseSensitive: false),
    RegExp(r'\bcivil\s+war(s)?\b', caseSensitive: false),
    RegExp(r"\bthirty\s*years'?\s*war\b", caseSensitive: false),
    RegExp(r'\bnapoleonic\s+wars?\b', caseSensitive: false),
    RegExp(r'\bboer\s+war\b', caseSensitive: false),
    RegExp(r'\bcrimean\s+war\b', caseSensitive: false),
    RegExp(r'\bfranco-prussian\s+war\b', caseSensitive: false),
    RegExp(r'\bfrench\s+and\s+indian\s+war\b', caseSensitive: false),
    RegExp(r'\bpatriot\s+war\b', caseSensitive: false),
    RegExp(r'\brussian-?japanese\s+war\b', caseSensitive: false),
    RegExp(r'\bamerican\s+(revolutionary|civil)\s+war\b', caseSensitive: false),
    RegExp(r'\binvasion\b', caseSensitive: false),
    RegExp(r'\bbattle(s)?\b', caseSensitive: false),
    RegExp(r'\bprisoners?\s+of\s+war\b', caseSensitive: false),
    RegExp(r'\bred\s+army\b', caseSensitive: false),
    RegExp(r'\bmilitary\b', caseSensitive: false),
    RegExp(r'\bsoldier(s)?\b', caseSensitive: false),
    RegExp(r'\bnaval\s+warfare\b', caseSensitive: false),

    // ===== German =====
    RegExp(r'\bkrieg(e|en)?\b', caseSensitive: false),
    RegExp(r'\bweltkrieg(e|en)?\b', caseSensitive: false),
    RegExp(r'\bdrei(ss|ß)igj[aä]hrig(er|en|e)?\s*krieg\b', caseSensitive: false),
    RegExp(r'\berster\s*weltkrieg\b', caseSensitive: false),
    RegExp(r'\bzweiter\s*weltkrieg\b', caseSensitive: false),
    RegExp(r'\bboxeraufstand\b', caseSensitive: false),
    RegExp(r'\bburgunderkrieg\b', caseSensitive: false),
    RegExp(r'\bhererokrieg\b', caseSensitive: false),
    RegExp(r'\bnationalsozialismus\b', caseSensitive: false),
    RegExp(r'\brote\s+armee\b', caseSensitive: false),
    RegExp(r'\brussisch-ukrainische\s+geschicht', caseSensitive: false),
    RegExp(r'\bt(ü|u)rkenkrieg\b', caseSensitive: false),
    RegExp(r'\bkreuzz(u|ü)g(e|en)?\b', caseSensitive: false),
    RegExp(r'\b(v|f)(ö|o)lkerwanderung\b', caseSensitive: false),
    RegExp(r'\bk\.?\s*u\.?\s*k\.?\s*(armee|monarchie)\b', caseSensitive: false),
    RegExp(r'\bkriegs(begin|leid)\b', caseSensitive: false),

    // ===== French =====
    RegExp(r'\bguerre(s)?\b', caseSensitive: false),
    RegExp(r'\bpremi[eè]re\s*guerre\s*mondiale\b', caseSensitive: false),
    RegExp(r'\bdeuxi[eè]me\s*guerre\s*mondiale\b', caseSensitive: false),
    RegExp(r'\bguerre\s*civile\b', caseSensitive: false),
    RegExp(r'\bguerres?\s*napol[ée]onienn', caseSensitive: false),
    RegExp(r'\bcroisad(e|es)\b', caseSensitive: false),
    RegExp(r'\barm[ée]e\b', caseSensitive: false),
    RegExp(r'\bmilitaire\b', caseSensitive: false),
    RegExp(r'\barm[ée]e\s+rouge\b', caseSensitive: false),

    // ===== Spanish / Portuguese =====
    RegExp(r'\bguerra(s)?\b', caseSensitive: false),
    RegExp(r'\bprimera\s*guerra\s*mundial\b', caseSensitive: false),
    RegExp(r'\bsegunda\s*guerra\s*mundial\b', caseSensitive: false),
    RegExp(r'\bguerra\s*civil\b', caseSensitive: false),
    RegExp(r'\bguerras?\s*napole[óo]nic', caseSensitive: false),
    RegExp(r'\bcruzad(a|as)\b', caseSensitive: false),
    RegExp(r'\bmilitar(ismo)?\b', caseSensitive: false),
    RegExp(r'\bej[ée]rcit[oa]\b', caseSensitive: false),

    // ===== Italian =====
    RegExp(r'\bguerra(e)?\b', caseSensitive: false),
    RegExp(r'\bprima\s*guerra\s*mondiale\b', caseSensitive: false),
    RegExp(r'\bseconda\s*guerra\s*mondiale\b', caseSensitive: false),
    RegExp(r'\bguerra\s*civile\b', caseSensitive: false),
    RegExp(r'\bguerre\s*napoleon', caseSensitive: false),
    RegExp(r'\bcrociat(a|e)\b', caseSensitive: false),
    RegExp(r'\bmilitare\b', caseSensitive: false),
    RegExp(r'\besercit[io]\b', caseSensitive: false),

    // ===== Russian / Slavic =====
    RegExp(r'войн', caseSensitive: false),
    RegExp(r'мировая\s*война', caseSensitive: false),
    RegExp(r'первая\s*мировая', caseSensitive: false),
    RegExp(r'вторая\s*мировая', caseSensitive: false),
    RegExp(r'гражданск(ая|ой)\s*война', caseSensitive: false),
    RegExp(r'крестов(ый|ые)\s*поход', caseSensitive: false),
    RegExp(r'красн(ая|ой)\s*армия', caseSensitive: false),
    RegExp(r'русско-украинск\w*\s*истор', caseSensitive: false),
    RegExp(r'тридцатилетн\w*\s*война', caseSensitive: false),

    // ===== Greek (modern & ancient) =====
    RegExp(r'πόλεμος', caseSensitive: false),
    RegExp(r'πολέμων', caseSensitive: false),
    RegExp(r'σταυροφορ(ία|ίες)', caseSensitive: false),
    RegExp(r'στρατός', caseSensitive: false),
    RegExp(r'polemos', caseSensitive: false),
    RegExp(r'polemon', caseSensitive: false),

    // ===== Latin =====
    RegExp(r'\bbellum\b', caseSensitive: false),
    RegExp(r'\bbella\b', caseSensitive: false),
    RegExp(r'\bbellum\s+civile\b', caseSensitive: false),
    RegExp(r'\bmilitia\b', caseSensitive: false),
    RegExp(r'\bcruciata\b', caseSensitive: false),

    // ===== Scandinavian =====
    RegExp(r'\bkrig\b', caseSensitive: false),
    RegExp(r'\bf(ö|o)rsta\s*v(ä|a)rldskrig(et)?\b', caseSensitive: false),
    RegExp(r'\bandra\s*v(ä|a)rldskrig(et)?\b', caseSensitive: false),
    RegExp(r'\bkorst(å|a)g\b', caseSensitive: false),
    RegExp(r'\binb(ö|o)rdeskrig\b', caseSensitive: false),

    // ===== Finnish =====
    RegExp(r'\bsota\b', caseSensitive: false),
    RegExp(r'\bensimm(ä|a)inen\s*maailmansota\b', caseSensitive: false),
    RegExp(r'\btoinen\s*maailmansota\b', caseSensitive: false),
    RegExp(r'\bristiretki\b', caseSensitive: false),

    // ===== Polish =====
    RegExp(r'\bwojn\w*\b', caseSensitive: false),
    RegExp(r'\bpierwsz\w*\s*wojn\w*\s*światow\w*\b', caseSensitive: false),
    RegExp(r'\bdrug\w*\s*wojn\w*\s*światow\w*\b', caseSensitive: false),
    RegExp(r'\bkrucjat\w*\b', caseSensitive: false),
    RegExp(r'\bczerw(on|on)a\s*armia\b', caseSensitive: false),

    // ===== Catalan =====
    RegExp(r'\bguerra(s)?\b', caseSensitive: false),
    RegExp(r'\bprimera\s*guerra\s*mundial\b', caseSensitive: false),
    RegExp(r'\bsegona\s*guerra\s*mundial\b', caseSensitive: false),
    RegExp(r'\bcroada(s)?\b', caseSensitive: false),
    RegExp(r'\bex[èe]rcit\b', caseSensitive: false),

    // ===== Esperanto =====
    RegExp(r'\bmilit(o|oj)\b', caseSensitive: false),
    RegExp(r'\bunua\s*mondmilit\w*\b', caseSensitive: false),
    RegExp(r'\bdua\s*mondmilit\w*\b', caseSensitive: false),
    RegExp(r'\bkrucmilit\w*\b', caseSensitive: false),

    // ===== Chinese (simplified/traditional) =====
    RegExp(r'战争|戰爭'),
    RegExp(r'世界大战|世界大戰'),
    RegExp(r'第一次世界大战|第一次世界大戰'),
    RegExp(r'第二次世界大战|第二次世界大戰'),
    RegExp(r'十字军东征|十字軍東征'),
    RegExp(r'战役|戰役'),
    RegExp(r'军队|軍隊'),
    RegExp(r'士兵'),

    // ===== Japanese =====
    RegExp(r'戦争'),
    RegExp(r'世界大戦'),
    RegExp(r'第一次世界大戦'),
    RegExp(r'第二次世界大戦'),
    RegExp(r'十字軍'),
    RegExp(r'軍隊'),
    RegExp(r'兵士'),
  ],
  'adventure': [
    RegExp(r'\badventur', caseSensitive: false),
    RegExp(r'\baventur', caseSensitive: false),  // fr/es/it/pt
    RegExp(r'\babenteuer\b', caseSensitive: false), // de
    RegExp(r'\bseikkailu\b', caseSensitive: false), // fi
    RegExp(r'\bäventyr\b', caseSensitive: false),   // sv
    RegExp(r'\bviaje|viajar|voyage|viagem\b', caseSensitive: false),
    RegExp(r'\bexplor', caseSensitive: false),      // exploration
  ],
  'biography': [
    RegExp(r'\bbiograph', caseSensitive: false),
    RegExp(r'\bbiograf', caseSensitive: false),
    RegExp(r'\bmemoi', caseSensitive: false),
    RegExp(r'\blebensbeschreib', caseSensitive: false), // de
    RegExp(r'\bvida\b', caseSensitive: false),          // es/pt
    RegExp(r'\bvie\b', caseSensitive: false),           // fr
  ],
  'children': [
    RegExp(r'\bchildren\b', caseSensitive: false),
    RegExp(r'\bjuvenil|juvenile\b', caseSensitive: false),
    RegExp(r'\benfant|enfants\b', caseSensitive: false),
    RegExp(r'\bkind(er)?\b', caseSensitive: false),  // de
    RegExp(r'\bbarn\b', caseSensitive: false),       // sv/no
    RegExp(r'\bniñ[oa]s?\b', caseSensitive: false), // es
    RegExp(r'\bragazzi\b', caseSensitive: false),   // it
    RegExp(r'\bboys|girls|kids\b', caseSensitive: false),
    RegExp(r'\bfairy tale|nursery rhyme\b', caseSensitive: false),
  ],
  'comedy': [
    RegExp(r'\bcomedy|\bhumou?r|\bsatire|\bfarce', caseSensitive: false),
    RegExp(r'\bcom(è|e)die\b', caseSensitive: false), // fr
    RegExp(r'\bkom(ö|o)die\b', caseSensitive: false), // de
    RegExp(r'\bsátira\b', caseSensitive: false),      // es/pt
    RegExp(r'\bsatira\b', caseSensitive: false),      // it/eo
  ],
  'fantasy': [
    RegExp(r'\bfantasy\b', caseSensitive: false),
    RegExp(r'\bfantast', caseSensitive: false),     // stems
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
    RegExp(r'\bespanto\b', caseSensitive: false),    // es/pt
    RegExp(r'\bgespenst\b', caseSensitive: false),   // de
  ],
  'love': [
    RegExp(r'\bromance\b', caseSensitive: false),
    RegExp(r'\blove( story)?\b', caseSensitive: false),
    RegExp(r'\bmarriage\b', caseSensitive: false),
    RegExp(r'\brelationship', caseSensitive: false),
    RegExp(r'\bamour\b', caseSensitive: false),   // fr
    RegExp(r'\bamore\b', caseSensitive: false),   // it
    RegExp(r'\bamor\b', caseSensitive: false),    // es/pt
    RegExp(r'\brakkaus\b', caseSensitive: false), // fi
  ],
  'mystery': [
    // ===== English =====
    RegExp(r'\bmystery|whodunit|who-?dunn?it|detective|sleuth|thriller|noir|cozy\s+mystery|police\s+procedural\b', caseSensitive: false),
    RegExp(r'\bcrime|criminal|heist|robber(y|ies)?|thief|burglary|theft|kidnapping\b', caseSensitive: false),
    RegExp(r'\bmurder|homicide|manslaughter|assassin(ation|s?)\b', caseSensitive: false),
    RegExp(r'\bsuspense|intrigue|investigat(ion|ive)|case\s+files?\b', caseSensitive: false),

    // ===== German =====
    RegExp(r'\bkrimi(nal|s|)\b', caseSensitive: false),            // Krimi / Kriminal-
    RegExp(r'\bverbrechen\b', caseSensitive: false),               // crime
    RegExp(r'\bmord|totschlag\b', caseSensitive: false),           // murder / manslaughter
    RegExp(r'\bdetektiv(en|e|)\b', caseSensitive: false),
    RegExp(r'\bpolizei(roman|arbeit)\b', caseSensitive: false),    // police novel / work
    RegExp(r'\bspannung\b', caseSensitive: false),                 // suspense
    RegExp(r'\bdieb(stahl)?|raub|entführung\b', caseSensitive: false),

    // ===== French =====
    RegExp(r'\bmyst[èe]re(s)?\b', caseSensitive: false),
    RegExp(r'\b(polici(er|ers?|ère|ères)|roman\s+policier|polar)\b', caseSensitive: false),
    RegExp(r'\b(enqu[êe]te|enqu[êe]teur(s)?|d[ée]tective?)\b', caseSensitive: false),
    RegExp(r'\bcrime(s)?|criminel(s|le|les)?\b', caseSensitive: false),
    RegExp(r'\bmeurtre(s)?|assassinat(s)?\b', caseSensitive: false),
    RegExp(r'\bsuspense|intrigue\b', caseSensitive: false),
    RegExp(r'\bvol(s)?|braquage(s)?|enl[èe]vement(s)?\b', caseSensitive: false),
    RegExp(r'\bnoir\b', caseSensitive: false),

    // ===== Spanish / Portuguese =====
    RegExp(r'\bmist(é|e)rio(s)?|misterio(s)?\b', caseSensitive: false),
    RegExp(r'\bpoliciac[oa]s?|policial(?!\w*mente)\b', caseSensitive: false),
    RegExp(r'\bcrimen(es)?|crim(e|es)?\b', caseSensitive: false),
    RegExp(r'\bdelito(s)?|delitto(s)?\b', caseSensitive: false),   // es/pt cognates and it form included below too
    RegExp(r'\bassassinato(s)?|asesinato(s)?|homicid(io|ios|io(s)?)\b', caseSensitive: false),
    RegExp(r'\bsuspens[eo]\b|\bintriga(s)?\b', caseSensitive: false),
    RegExp(r'\brobo(s)?|hurto(s)?|secuestro(s)?\b', caseSensitive: false),
    RegExp(r'\bdetective(s)?\b', caseSensitive: false),
    RegExp(r'\bnoir\b', caseSensitive: false),

    // ===== Italian =====
    RegExp(r'\bmistero(i)?\b', caseSensitive: false),
    RegExp(r'\bgiallo(i)?\b', caseSensitive: false),               // Italian term for crime/mystery genre
    RegExp(r'\bpoliziesc(o|hi|i)\b', caseSensitive: false),
    RegExp(r'\bcrimine|reato|delitto\b', caseSensitive: false),
    RegExp(r'\bomicidio(i)?|assassinio(i)?\b', caseSensitive: false),
    RegExp(r'\bsuspense|intrigo\b', caseSensitive: false),
    RegExp(r'\bfurt(o|i)|rapina(e)?|sequestro(i)?\b', caseSensitive: false),
    RegExp(r'\bdetective\b', caseSensitive: false),
    RegExp(r'\bnoir\b', caseSensitive: false),

    // ===== Dutch =====
    RegExp(r'\bmysterie(s)?\b', caseSensitive: false),
    RegExp(r'\bdetective(s)?|thriller(s)?\b', caseSensitive: false),
    RegExp(r'\bmisdaad\b', caseSensitive: false),
    RegExp(r'\bmoord\b', caseSensitive: false),
    RegExp(r'\bspanning\b', caseSensitive: false),
    RegExp(r'\bdiefstal|overval|ontvoering\b', caseSensitive: false),
    RegExp(r'\bpolitie(roman)?\b', caseSensitive: false),
    RegExp(r'\bnoir\b', caseSensitive: false),

    // ===== Scandinavian (sv/da/no) =====
    RegExp(r'\bmyster(ium|ier)\b', caseSensitive: false),          // sv/no
    RegExp(r'\bdeckare\b|\bkrimi\b', caseSensitive: false),        // sv crime novel / da/no krimi
    RegExp(r'\bbrott|forbrydelse|forbrytelse\b', caseSensitive: false),
    RegExp(r'\bmord\b', caseSensitive: false),
    RegExp(r'\bsp[äa]nning|sp[æa]nding\b', caseSensitive: false),
    RegExp(r'\bdetektiv\b', caseSensitive: false),
    RegExp(r'\btyveri|tyveri(er)?|røveri|ran\b', caseSensitive: false),
    RegExp(r'\bkidnapping|bortf(ö|o)rande\b', caseSensitive: false),

    // ===== Finnish =====
    RegExp(r'\bmysteeri(t)?\b', caseSensitive: false),
    RegExp(r'\brikos|rikosromaani\b', caseSensitive: false),
    RegExp(r'\bmurha(t)?\b', caseSensitive: false),
    RegExp(r'\bj[äa]nnitys\b', caseSensitive: false),
    RegExp(r'\bsalapoliisi(t)?\b', caseSensitive: false),
    RegExp(r'\bvaras|varkaus|ry[öo]st[öo]\b', caseSensitive: false),
    RegExp(r'\bkaappaus\b', caseSensitive: false),

    // ===== Polish =====
    RegExp(r'\btajemnic(a|e|y)\b', caseSensitive: false),
    RegExp(r'\bkrymina[łl]\b', caseSensitive: false),
    RegExp(r'\bzbrodni(a|e)\b', caseSensitive: false),
    RegExp(r'\bmorderstw(o|a)\b', caseSensitive: false),
    RegExp(r'\bśledztw(o|a)\b|\bdochodzeni(e|a)\b', caseSensitive: false),
    RegExp(r'\bdetektyw\b', caseSensitive: false),
    RegExp(r'\bnapieci(e|a)\b', caseSensitive: false),             // suspense/tension
    RegExp(r'\bkradzie(ż|z)y?\b|\bnapad\b|\bporwanie\b', caseSensitive: false),

    // ===== Russian / Slavic =====
    RegExp(r'детектив', caseSensitive: false),
    RegExp(r'преступлен', caseSensitive: false),                   // crime
    RegExp(r'убийств', caseSensitive: false),                      // murder
    RegExp(r'загадк|тайн', caseSensitive: false),                  // mystery/secret
    RegExp(r'триллер', caseSensitive: false),
    RegExp(r'угон|похищен', caseSensitive: false),                 // kidnapping
    RegExp(r'краж|грабеж|разбой', caseSensitive: false),           // theft/robbery
    RegExp(r'следств|расследован', caseSensitive: false),          // investigation
    RegExp(r'саспенс', caseSensitive: false),

    // ===== Greek =====
    RegExp(r'\bμυστ(ή|η)ριο\b', caseSensitive: false),
    RegExp(r'\bαστυνομικ(ό|ά)\b', caseSensitive: false),           // crime/police genre
    RegExp(r'\bέγκλημα\b|\bφόνος\b', caseSensitive: false),
    RegExp(r'\bντετέκτιβ\b', caseSensitive: false),
    RegExp(r'\bθρίλερ\b|\bσασπένς\b', caseSensitive: false),
    RegExp(r'\bκλοπ(ή|ές)\b|\bληστε(ία|ίες)\b|\bαπαγωγ(ή|ές)\b', caseSensitive: false),

    // ===== Catalan =====
    RegExp(r'\bmisteri(s)?\b', caseSensitive: false),
    RegExp(r'\bpolic[ií]ac(s)?\b', caseSensitive: false),
    RegExp(r'\bcrim(s)?\b', caseSensitive: false),
    RegExp(r'\bassassinat(s)?\b', caseSensitive: false),
    RegExp(r'\bintriga(s)?|suspens\b', caseSensitive: false),
    RegExp(r'\bdetectiu(s)?\b', caseSensitive: false),

    // ===== Esperanto =====
    RegExp(r'\bmister(o|oj)\b', caseSensitive: false),
    RegExp(r'\bkrim(o|oj)\b', caseSensitive: false),
    RegExp(r'\bmurd(o|oj)\b', caseSensitive: false),
    RegExp(r'\bdetektiv(o|oj)\b', caseSensitive: false),
    RegExp(r'\bsuspen(s|so)\b|\bintrigo\b', caseSensitive: false),
    RegExp(r'\bŝtelo|stelo\b|\bprirabo\b|\bforkapto\b', caseSensitive: false),

    // ===== Chinese (简/繁) =====
    RegExp(r'悬疑|懸疑'),
    RegExp(r'推理'),
    RegExp(r'侦探|偵探'),
    RegExp(r'犯罪'),
    RegExp(r'谋杀|謀殺|兇殺|凶殺'),
    RegExp(r'惊悚|驚悚'),                                        // thriller
    RegExp(r'悬念|懸念'),                                        // suspense
    RegExp(r'绑架|綁架'),
    RegExp(r'盗窃|盜竊|抢劫|搶劫'),

    // ===== Japanese =====
    RegExp(r'ミステリ|ミステリー'),
    RegExp(r'推理'),
    RegExp(r'探偵'),
    RegExp(r'犯罪'),
    RegExp(r'殺人'),
    RegExp(r'サスペンス'),
    RegExp(r'スリラー'),
    RegExp(r'誘拐'),
    RegExp(r'盗難|強盗'),

    // ===== Hebrew =====
    RegExp(r'מסתורין', caseSensitive: false),
    RegExp(r'בלש', caseSensitive: false),
    RegExp(r'פש[עה]', caseSensitive: false),
    RegExp(r'רצח', caseSensitive: false),
    RegExp(r'חטיפה', caseSensitive: false),
    RegExp(r'מתח', caseSensitive: false),                          // suspense
    RegExp(r'חקיר', caseSensitive: false),                         // investigation stem

    // ===== Latin (rare, but catch some tags) =====
    RegExp(r'\bmysterium\b', caseSensitive: false),
    RegExp(r'\bcrimen\b', caseSensitive: false),
    RegExp(r'\bcaedes\b', caseSensitive: false),                   // killing/murder
    RegExp(r'\binquisitio\b', caseSensitive: false),               // investigation
    RegExp(r'\bfurto|furtum\b', caseSensitive: false),

    // General catch-alls across languages
    RegExp(r'\bnoir\b', caseSensitive: false),
    RegExp(r'\b(policier|policial|policiaco|poliziesco|politie(roman)?)\b', caseSensitive: false),
  ],
  'philosophy': [
    // ===== English =====
    RegExp(r'\bphilosoph(y|ies|er|ers|ic|ical)\b', caseSensitive: false),
    RegExp(r'\bethic(s|al)?\b', caseSensitive: false),
    RegExp(r'\bmoral(ity|s)?\b', caseSensitive: false),
    RegExp(r'\blogic(al)?\b', caseSensitive: false),
    RegExp(r'\bepistemolog(y|ies)\b', caseSensitive: false),
    RegExp(r'\bmetaphysic(s|al)?\b', caseSensitive: false),
    RegExp(r'\baesthetic(s)?\b', caseSensitive: false),
    RegExp(r'\bontolog(y|ies|ical)\b', caseSensitive: false),
    RegExp(r'\bexistentialis(m|t)\b', caseSensitive: false),
    RegExp(r'\bphenomenolog(y|ies)\b', caseSensitive: false),
    RegExp(r'\brationalis(m|t)\b', caseSensitive: false),
    RegExp(r'\bempiricis(m|t)\b', caseSensitive: false),
    RegExp(r'\bidealism\b', caseSensitive: false),
    RegExp(r'\brealism\b', caseSensitive: false),
    RegExp(r'\bmaterialism\b', caseSensitive: false),
    RegExp(r'\bstoicis(m|t)\b', caseSensitive: false),
    RegExp(r'\b(skeptic|sceptic)ism\b', caseSensitive: false),
    RegExp(r'\bcynicis(m|t)\b', caseSensitive: false),
    RegExp(r'\bhedonis(m|t)\b', caseSensitive: false),
    RegExp(r'\butilitarianis(m|t)\b', caseSensitive: false),
    RegExp(r'\bdeterminism\b', caseSensitive: false),
    RegExp(r'\bpragmatism\b', caseSensitive: false),
    RegExp(r'\bhumanis(m|t)\b', caseSensitive: false),
    RegExp(r'\bscholastic(ism)?\b', caseSensitive: false),
    RegExp(r'\bpatristic(s)?\b', caseSensitive: false),
    RegExp(r'\benlightenment\b', caseSensitive: false),

    // ===== German =====
    RegExp(r'\bphilosoph(ie|isch|en|e|in|s)?\b', caseSensitive: false),
    RegExp(r'\bethik\b', caseSensitive: false),
    RegExp(r'\bmoral\b', caseSensitive: false),
    RegExp(r'\blogik\b', caseSensitive: false),
    RegExp(r'\berkenntnistheor', caseSensitive: false),   // epistemology (stem)
    RegExp(r'\bmetaphysik\b', caseSensitive: false),
    RegExp(r'\bästhetik\b', caseSensitive: false),
    RegExp(r'\bontologie\b', caseSensitive: false),
    RegExp(r'\bexistenzphilosoph', caseSensitive: false),
    RegExp(r'\bphänomenolog', caseSensitive: false),
    RegExp(r'\brationalism(us)?\b', caseSensitive: false),
    RegExp(r'\bempirism(us)?\b', caseSensitive: false),
    RegExp(r'\bidealism(us)?\b', caseSensitive: false),
    RegExp(r'\brealism(us)?\b', caseSensitive: false),
    RegExp(r'\bmaterialism(us)?\b', caseSensitive: false),
    RegExp(r'\bstoizism(us)?\b', caseSensitive: false),    // Stoizismus
    RegExp(r'\bskeptizism(us)?\b', caseSensitive: false),
    RegExp(r'\bzynism(us)?\b', caseSensitive: false),      // Zynismus
    RegExp(r'\bhedonism(us)?\b', caseSensitive: false),
    RegExp(r'\butilitarism(us)?\b', caseSensitive: false),
    RegExp(r'\bdeterminism(us)?\b', caseSensitive: false),
    RegExp(r'\bpragmatism(us)?\b', caseSensitive: false),
    RegExp(r'\bhumanism(us)?\b', caseSensitive: false),
    RegExp(r'\bscholastik\b', caseSensitive: false),
    RegExp(r'\bpatristik\b', caseSensitive: false),
    RegExp(r'\baufkl(ä|a)rung\b', caseSensitive: false),   // Enlightenment

    // ===== French =====
    RegExp(r'\bphilosoph(ie|es|e|ique|iques|e[sr])\b', caseSensitive: false),
    RegExp(r'\b[ée]thique\b', caseSensitive: false),
    RegExp(r'\bmoral(e|es)?\b', caseSensitive: false),
    RegExp(r'\blogique\b', caseSensitive: false),
    RegExp(r'\bm[ée]taphysique\b', caseSensitive: false),
    RegExp(r'\b[ée]pist[ée]mologie\b', caseSensitive: false),
    RegExp(r'\b[ée]sth[ée]tique\b', caseSensitive: false),
    RegExp(r'\bontologie\b', caseSensitive: false),
    RegExp(r'\bexistentialisme\b', caseSensitive: false),
    RegExp(r'\bph[ée]nom[ée]nologie\b', caseSensitive: false),
    RegExp(r'\brationalisme\b', caseSensitive: false),
    RegExp(r'\bempirisme\b', caseSensitive: false),
    RegExp(r'\bid[ée]alisme\b', caseSensitive: false),
    RegExp(r'\br[ée]alisme\b', caseSensitive: false),
    RegExp(r'\bmat[ée]rialisme\b', caseSensitive: false),
    RegExp(r'\bsto[ïi]cisme\b', caseSensitive: false),
    RegExp(r'\bscepticisme\b', caseSensitive: false),
    RegExp(r'\bcynisme\b', caseSensitive: false),
    RegExp(r'\bh[ée]donisme\b', caseSensitive: false),
    RegExp(r'\butilitarisme\b', caseSensitive: false),
    RegExp(r'\bd[ée]terminisme\b', caseSensitive: false),
    RegExp(r'\bpragmatisme\b', caseSensitive: false),
    RegExp(r'\bhumanisme\b', caseSensitive: false),
    RegExp(r'\bscolastique\b', caseSensitive: false),
    RegExp(r'\bpatristique\b', caseSensitive: false),
    RegExp(r'\blumi[èe]res\b', caseSensitive: false),      // Enlightenment

    // ===== Spanish / Portuguese =====
    RegExp(r'\bfilosof[ií]a(s)?\b', caseSensitive: false),
    RegExp(r'\bfil[óo]sof(o|a|os|as)\b', caseSensitive: false),
    RegExp(r'\b[ée]tica(s)?\b', caseSensitive: false),
    RegExp(r'\bmoral(es)?\b', caseSensitive: false),
    RegExp(r'\bl[óo]gica(s)?\b', caseSensitive: false),
    RegExp(r'\bmetaf[íi]sic[ao]s?\b', caseSensitive: false),
    RegExp(r'\bepistemolog[íi]a(s)?\b', caseSensitive: false),
    RegExp(r'\best[ée]tic[ao]s?\b', caseSensitive: false),
    RegExp(r'\bontolog[íi]a(s)?\b', caseSensitive: false),
    RegExp(r'\bexistencialismo(s)?\b', caseSensitive: false),
    RegExp(r'\bfenomenolog[íi]a(s)?\b', caseSensitive: false),
    RegExp(r'\bracionalismo(s)?\b', caseSensitive: false),
    RegExp(r'\bempirismo(s)?\b', caseSensitive: false),
    RegExp(r'\bidealismo(s)?\b', caseSensitive: false),
    RegExp(r'\brealismo(s)?\b', caseSensitive: false),
    RegExp(r'\bmaterialismo(s)?\b', caseSensitive: false),
    RegExp(r'\bestoicismo(s)?\b', caseSensitive: false),
    RegExp(r'\b(e|c)scepticismo(s)?\b', caseSensitive: false), // escepticismo / cepticismo (pt)
    RegExp(r'\bcinismo(s)?\b', caseSensitive: false),
    RegExp(r'\bhedonismo(s)?\b', caseSensitive: false),
    RegExp(r'\butilitarismo(s)?\b', caseSensitive: false),
    RegExp(r'\bdeterminismo(s)?\b', caseSensitive: false),
    RegExp(r'\bpragmatismo(s)?\b', caseSensitive: false),
    RegExp(r'\bhumanismo(s)?\b', caseSensitive: false),
    RegExp(r'\bescol[áa]stic[ao]s?\b', caseSensitive: false),
    RegExp(r'\bpatr[íi]stic[ao]s?\b', caseSensitive: false),
    RegExp(r'\bilustraci[óo]n\b|\biluminismo\b', caseSensitive: false),

    // ===== Italian =====
    RegExp(r'\bfilosofi(a|e|o|i)\b', caseSensitive: false),
    RegExp(r'\bfilosofo\b', caseSensitive: false),
    RegExp(r'\betica\b', caseSensitive: false),
    RegExp(r'\bmorale\b', caseSensitive: false),
    RegExp(r'\blogica\b', caseSensitive: false),
    RegExp(r'\bmetafisic(a|he)?\b', caseSensitive: false),
    RegExp(r'\bepistemologia\b', caseSensitive: false),
    RegExp(r'\bestetic(a|he)?\b', caseSensitive: false),
    RegExp(r'\bontologia\b', caseSensitive: false),
    RegExp(r'\besistenzialism(o|i)\b', caseSensitive: false),
    RegExp(r'\bfenomenologia\b', caseSensitive: false),
    RegExp(r'\brazionalism(o|i)\b', caseSensitive: false),
    RegExp(r'\bempirism(o|i)\b', caseSensitive: false),
    RegExp(r'\bidealism(o|i)\b', caseSensitive: false),
    RegExp(r'\brealism(o|i)\b', caseSensitive: false),
    RegExp(r'\bmaterialism(o|i)\b', caseSensitive: false),
    RegExp(r'\bstoicism(o|i)\b', caseSensitive: false),
    RegExp(r'\bscetticism(o|i)\b', caseSensitive: false),
    RegExp(r'\bcinism(o|i)\b', caseSensitive: false),
    RegExp(r'\bedonism(o|i)\b', caseSensitive: false),
    RegExp(r'\butilitarism(o|i)\b', caseSensitive: false),
    RegExp(r'\bdeterminism(o|i)\b', caseSensitive: false),
    RegExp(r'\bpragmatism(o|i)\b', caseSensitive: false),
    RegExp(r'\bumanesim(o|i)\b', caseSensitive: false),
    RegExp(r'\bscolastic(a|he)?\b', caseSensitive: false),
    RegExp(r'\bpatristic(a|he)?\b', caseSensitive: false),
    RegExp(r'\billuminismo\b', caseSensitive: false),

    // ===== Russian / Slavic =====
    RegExp(r'философ(ия|ии|ская|ские|ов|ств)', caseSensitive: false),
    RegExp(r'этик', caseSensitive: false),
    RegExp(r'морал', caseSensitive: false),
    RegExp(r'логик', caseSensitive: false),
    RegExp(r'(эпистемолог|гносеолог)', caseSensitive: false),
    RegExp(r'метафизик', caseSensitive: false),
    RegExp(r'эстетик', caseSensitive: false),
    RegExp(r'онтолог', caseSensitive: false),
    RegExp(r'экзистенциализм', caseSensitive: false),
    RegExp(r'феноменолог', caseSensitive: false),
    RegExp(r'рационализм', caseSensitive: false),
    RegExp(r'эмпиризм', caseSensitive: false),
    RegExp(r'идеализм', caseSensitive: false),
    RegExp(r'реализм', caseSensitive: false),
    RegExp(r'материализм', caseSensitive: false),
    RegExp(r'стоицизм', caseSensitive: false),
    RegExp(r'скептицизм', caseSensitive: false),
    RegExp(r'цинизм', caseSensitive: false),
    RegExp(r'гедонизм', caseSensitive: false),
    RegExp(r'утилитаризм', caseSensitive: false),
    RegExp(r'детерминизм', caseSensitive: false),
    RegExp(r'прагматизм', caseSensitive: false),
    RegExp(r'гуманизм', caseSensitive: false),
    RegExp(r'схоластик', caseSensitive: false),
    RegExp(r'патристик', caseSensitive: false),
    RegExp(r'просвещен', caseSensitive: false),  // Enlightenment (stem)

    // ===== Greek (modern & ancient) =====
    RegExp(r'φιλοσοφ(ία|ίας|ος|ική|ικ[έe]ς?)', caseSensitive: false),
    RegExp(r'ηθικ', caseSensitive: false),
    RegExp(r'λογικ', caseSensitive: false),
    RegExp(r'γνωσιολογ', caseSensitive: false),    // epistemology
    RegExp(r'αισθητικ', caseSensitive: false),
    RegExp(r'μεταφυσικ', caseSensitive: false),
    RegExp(r'οντολογ', caseSensitive: false),
    RegExp(r'υπαρξισμ', caseSensitive: false),
    RegExp(r'φαινομενολογ', caseSensitive: false),
    RegExp(r'ορθολογισμ', caseSensitive: false),
    RegExp(r'εμπειρισμ', caseSensitive: false),
    RegExp(r'ιδεαλισμ', caseSensitive: false),
    RegExp(r'ρεαλισμ', caseSensitive: false),
    RegExp(r'υλισμ', caseSensitive: false),
    RegExp(r'στωικισμ', caseSensitive: false),
    RegExp(r'σκεπτικισμ', caseSensitive: false),
    RegExp(r'κυνισμ', caseSensitive: false),
    RegExp(r'ηδονισμ', caseSensitive: false),
    RegExp(r'ωφελιμισμ', caseSensitive: false),    // utilitarianism
    RegExp(r'ντετερμινισμ', caseSensitive: false), // determinism (phon.)
    RegExp(r'πραγματισμ', caseSensitive: false),
    RegExp(r'ουμανισμ', caseSensitive: false),
    RegExp(r'σχολαστικ', caseSensitive: false),
    RegExp(r'πατριστικ', caseSensitive: false),
    RegExp(r'διαφωτισμ', caseSensitive: false),

    // ===== Latin =====
    RegExp(r'\bphilosophia\b', caseSensitive: false),
    RegExp(r'\bethica\b', caseSensitive: false),
    RegExp(r'\bmoralis\b', caseSensitive: false),
    RegExp(r'\blogica\b', caseSensitive: false),
    RegExp(r'\bmetaphysica\b', caseSensitive: false),
    RegExp(r'\baesthetica\b', caseSensitive: false),
    RegExp(r'\bepistemologia\b', caseSensitive: false),
    RegExp(r'\bontologia\b', caseSensitive: false),
    RegExp(r'\bexistentialismus\b', caseSensitive: false),
    RegExp(r'\bphenomenologia\b', caseSensitive: false),
    RegExp(r'\brationalismus\b', caseSensitive: false),
    RegExp(r'\bempirismus\b', caseSensitive: false),
    RegExp(r'\bidealismus\b', caseSensitive: false),
    RegExp(r'\brealismus\b', caseSensitive: false),
    RegExp(r'\bmaterialismus\b', caseSensitive: false),
    RegExp(r'\bstoicismus\b', caseSensitive: false),
    RegExp(r'\bscepticismus\b', caseSensitive: false),
    RegExp(r'\bcynismus\b', caseSensitive: false),
    RegExp(r'\bhedonismus\b', caseSensitive: false),
    RegExp(r'\butilitarianismus\b', caseSensitive: false),
    RegExp(r'\bdeterminismus\b', caseSensitive: false),
    RegExp(r'\bpragmatismus\b', caseSensitive: false),
    RegExp(r'\bhumanismus\b', caseSensitive: false),
    RegExp(r'\bscholastica\b', caseSensitive: false),
    RegExp(r'\bpatristica\b', caseSensitive: false),
    RegExp(r'\billuminismus\b', caseSensitive: false),

    // ===== Scandinavian (sv/da/no) =====
    RegExp(r'\bfilosofi\b', caseSensitive: false),
    RegExp(r'\bfilosof(er|i|isk|iske)?\b', caseSensitive: false),
    RegExp(r'\betik\b', caseSensitive: false),
    RegExp(r'\bmoral\b', caseSensitive: false),
    RegExp(r'\blogik\b', caseSensitive: false),
    RegExp(r'\bmetafysik\b', caseSensitive: false),
    RegExp(r'\bkunskapsteor', caseSensitive: false), // sv: epistemology stem
    RegExp(r'\bestetik\b', caseSensitive: false),
    RegExp(r'\bontologi\b', caseSensitive: false),
    RegExp(r'\bexistentialism\b', caseSensitive: false),
    RegExp(r'\bfenomenolog', caseSensitive: false),
    RegExp(r'\brationalism\b', caseSensitive: false),
    RegExp(r'\bempirism\b', caseSensitive: false),
    RegExp(r'\bidealism\b', caseSensitive: false),
    RegExp(r'\brealism\b', caseSensitive: false),
    RegExp(r'\bmaterialism\b', caseSensitive: false),
    RegExp(r'\bstoicism\b', caseSensitive: false),
    RegExp(r'\bskeptic(ism)?\b', caseSensitive: false),
    RegExp(r'\bcynism\b', caseSensitive: false),
    RegExp(r'\bhedonism\b', caseSensitive: false),
    RegExp(r'\butilitarism\b', caseSensitive: false),
    RegExp(r'\bdeterminism\b', caseSensitive: false),
    RegExp(r'\bpragmatism\b', caseSensitive: false),
    RegExp(r'\bhumanism\b', caseSensitive: false),
    RegExp(r'\bskolastik\b', caseSensitive: false),
    RegExp(r'\bpatristik\b', caseSensitive: false),
    RegExp(r'\bupplysning(en)?\b', caseSensitive: false),

    // ===== Finnish =====
    RegExp(r'\bfilosofi(a|an|assa)?\b', caseSensitive: false),
    RegExp(r'\bfilosofi\b', caseSensitive: false),
    RegExp(r'\betiikk?a?\b', caseSensitive: false),
    RegExp(r'\bmoraali\b', caseSensitive: false),
    RegExp(r'\blogiikk?a?\b', caseSensitive: false),
    RegExp(r'\bmetafysiikk?a?\b', caseSensitive: false),
    RegExp(r'\btietoteor', caseSensitive: false),      // epistemology stem
    RegExp(r'\bestetiikk?a?\b', caseSensitive: false),
    RegExp(r'\bontologi(a)?\b', caseSensitive: false),
    RegExp(r'\beksistentialism(i)?\b', caseSensitive: false),
    RegExp(r'\bfenomenologi(a)?\b', caseSensitive: false),
    RegExp(r'\brationalism(i)?\b', caseSensitive: false),
    RegExp(r'\bempirism(i)?\b', caseSensitive: false),
    RegExp(r'\bidealism(i)?\b', caseSensitive: false),
    RegExp(r'\brealism(i)?\b', caseSensitive: false),
    RegExp(r'\bmaterialism(i)?\b', caseSensitive: false),
    RegExp(r'\bstoalaisuus\b', caseSensitive: false),
    RegExp(r'\bskeptis(ismi|mi)\b', caseSensitive: false),
    RegExp(r'\bkyynisyys\b', caseSensitive: false),
    RegExp(r'\bhedonism(i)?\b', caseSensitive: false),
    RegExp(r'\butilitarism(i)?\b', caseSensitive: false),
    RegExp(r'\bdeterminism(i)?\b', caseSensitive: false),
    RegExp(r'\bpragmatism(i)?\b', caseSensitive: false),
    RegExp(r'\bhumanism(i)?\b', caseSensitive: false),
    RegExp(r'\bskolastiikk?a?\b', caseSensitive: false),
    RegExp(r'\bpatristiikk?a?\b', caseSensitive: false),
    RegExp(r'\bvalistus\b', caseSensitive: false),

    // ===== Polish =====
    RegExp(r'\bfilozofi(a|e|o|i)\b', caseSensitive: false),
    RegExp(r'\bfilozof(owie|em|ów|u|ie)?\b', caseSensitive: false),
    RegExp(r'\betyk(a|i)\b', caseSensitive: false),
    RegExp(r'\bmoralno(ść|sci)\b', caseSensitive: false),
    RegExp(r'\blogik(a|i)\b', caseSensitive: false),
    RegExp(r'\bmetafizyk(a|i)\b', caseSensitive: false),
    RegExp(r'\bepistemolog(i|ia)\b', caseSensitive: false),
    RegExp(r'\bestetyk(a|i)\b', caseSensitive: false),
    RegExp(r'\bontolog(ia|ii)\b', caseSensitive: false),
    RegExp(r'\begzystencjalizm\b', caseSensitive: false),
    RegExp(r'\bfenomenolog(ia|ii)\b', caseSensitive: false),
    RegExp(r'\bracjonalizm\b', caseSensitive: false),
    RegExp(r'\bempiryzm\b', caseSensitive: false),
    RegExp(r'\bidealizm\b', caseSensitive: false),
    RegExp(r'\brealizm\b', caseSensitive: false),
    RegExp(r'\bmaterializm\b', caseSensitive: false),
    RegExp(r'\bstoicyzm\b', caseSensitive: false),
    RegExp(r'\bsceptycyzm\b', caseSensitive: false),
    RegExp(r'\bcynizm\b', caseSensitive: false),
    RegExp(r'\bhedonizm\b', caseSensitive: false),
    RegExp(r'\butylitaryzm\b', caseSensitive: false),
    RegExp(r'\bdeterminizm\b', caseSensitive: false),
    RegExp(r'\bpragmatyzm\b', caseSensitive: false),
    RegExp(r'\bhumanizm\b', caseSensitive: false),
    RegExp(r'\bscholastyka\b', caseSensitive: false),
    RegExp(r'\bpatrystyka\b', caseSensitive: false),
    RegExp(r'\boświecenie\b', caseSensitive: false),

    // ===== Dutch (Nederlands) =====
    RegExp(r'\bfilosof(ie|isch|en|en)?\b', caseSensitive: false),
    RegExp(r'\bethiek\b', caseSensitive: false),
    RegExp(r'\bmoraal\b', caseSensitive: false),
    RegExp(r'\blogica\b', caseSensitive: false),
    RegExp(r'\bmetafysica\b', caseSensitive: false),
    RegExp(r'\bkennisleer\b', caseSensitive: false),    // epistemology
    RegExp(r'\besthetica\b', caseSensitive: false),
    RegExp(r'\bontologie\b', caseSensitive: false),
    RegExp(r'\bexistentialisme\b', caseSensitive: false),
    RegExp(r'\bfenomenologie\b', caseSensitive: false),
    RegExp(r'\brationalisme\b', caseSensitive: false),
    RegExp(r'\bempirisme\b', caseSensitive: false),
    RegExp(r'\bidealisme\b', caseSensitive: false),
    RegExp(r'\brealisme\b', caseSensitive: false),
    RegExp(r'\bmaterialisme\b', caseSensitive: false),
    RegExp(r'\bstoïcisme|stoicisme\b', caseSensitive: false),
    RegExp(r'\bscepticisme\b', caseSensitive: false),
    RegExp(r'\bcynisme\b', caseSensitive: false),
    RegExp(r'\bhedonisme\b', caseSensitive: false),
    RegExp(r'\butilitarisme\b', caseSensitive: false),
    RegExp(r'\bdeterminisme\b', caseSensitive: false),
    RegExp(r'\bpragmatisme\b', caseSensitive: false),
    RegExp(r'\bhumanisme\b', caseSensitive: false),
    RegExp(r'\bscholastiek\b', caseSensitive: false),
    RegExp(r'\bpatristiek\b', caseSensitive: false),
    RegExp(r'\bverlichting\b', caseSensitive: false),

    // ===== Catalan =====
    RegExp(r'\bfilosofi(a|es|e)?\b', caseSensitive: false),
    RegExp(r'\bfil[òo]sof(es|a|s)?\b', caseSensitive: false),
    RegExp(r'\b[èe]tica(s)?\b', caseSensitive: false),
    RegExp(r'\bmoral(s)?\b', caseSensitive: false),
    RegExp(r'\bl[òo]gica\b', caseSensitive: false),
    RegExp(r'\bmetaf[íi]sica\b', caseSensitive: false),
    RegExp(r'\bepistemologia\b', caseSensitive: false),
    RegExp(r'\best[èe]tica\b', caseSensitive: false),
    RegExp(r'\bontologia\b', caseSensitive: false),
    RegExp(r'\bexistencialisme\b', caseSensitive: false),
    RegExp(r'\bfenomenologia\b', caseSensitive: false),
    RegExp(r'\bracionalisme\b', caseSensitive: false),
    RegExp(r'\bempirisme\b', caseSensitive: false),
    RegExp(r'\bidealisme\b', caseSensitive: false),
    RegExp(r'\brealisme\b', caseSensitive: false),
    RegExp(r'\bmaterialisme\b', caseSensitive: false),
    RegExp(r'\besto[ïi]cisme\b', caseSensitive: false),
    RegExp(r'\bescepticisme\b', caseSensitive: false),
    RegExp(r'\bcinisme\b', caseSensitive: false),
    RegExp(r'\bhedonisme\b', caseSensitive: false),
    RegExp(r'\butilitarisme\b', caseSensitive: false),
    RegExp(r'\bdeterminisme\b', caseSensitive: false),
    RegExp(r'\bpragmatisme\b', caseSensitive: false),
    RegExp(r'\bhumanisme\b', caseSensitive: false),
    RegExp(r'\bescol[àa]stica\b', caseSensitive: false),
    RegExp(r'\bpatr[íi]stica\b', caseSensitive: false),
    RegExp(r'\bil·lustraci[óo]\b', caseSensitive: false),

    // ===== Esperanto =====
    RegExp(r'\bfilozofio\b', caseSensitive: false),
    RegExp(r'\bfilozofoj?|filozofo\b', caseSensitive: false),
    RegExp(r'\betiko\b', caseSensitive: false),
    RegExp(r'\bmoralo\b', caseSensitive: false),
    RegExp(r'\blogiko\b', caseSensitive: false),
    RegExp(r'\bmetafizik[ao]\b', caseSensitive: false),
    RegExp(r'\bepistemologi[ao]\b', caseSensitive: false),
    RegExp(r'\bestetik[ao]\b', caseSensitive: false),
    RegExp(r'\bontologi[ao]\b', caseSensitive: false),
    RegExp(r'\bekzistenc(ial)?ismo\b', caseSensitive: false),
    RegExp(r'\bfenomenologi[ao]\b', caseSensitive: false),
    RegExp(r'\braci(ism|ismo)\b', caseSensitive: false), // some corpora use raciismo for rationalism; kept cautiously
    RegExp(r'\bempirismo\b', caseSensitive: false),
    RegExp(r'\bidealismo\b', caseSensitive: false),
    RegExp(r'\brealismo\b', caseSensitive: false),
    RegExp(r'\bmaterialismo\b', caseSensitive: false),
    RegExp(r'\bstoikismo\b', caseSensitive: false),
    RegExp(r'\bsceptikismo|skeptikismo\b', caseSensitive: false),
    RegExp(r'\bcinismo\b', caseSensitive: false),
    RegExp(r'\bhedonismo\b', caseSensitive: false),
    RegExp(r'\butilitarismo\b', caseSensitive: false),
    RegExp(r'\bdeterminismo\b', caseSensitive: false),
    RegExp(r'\bpragmatismo\b', caseSensitive: false),
    RegExp(r'\bhumanismo\b', caseSensitive: false),
    RegExp(r'\bskolastik(o|a)\b', caseSensitive: false),
    RegExp(r'\bpatristik(o|a)\b', caseSensitive: false),
    RegExp(r'\biluminismo\b', caseSensitive: false),

    // ===== Chinese (简/繁) =====
    RegExp(r'哲学|哲理'),
    RegExp(r'伦理学|道德'),
    RegExp(r'逻辑|邏輯'),
    RegExp(r'形而上学|形而上學'),
    RegExp(r'认识论|認識論'),
    RegExp(r'美学|美學'),
    RegExp(r'本体论|本體論'),
    RegExp(r'存在主义|存在主義'),
    RegExp(r'现象学|現象學'),
    RegExp(r'理性主义|理性主義'),
    RegExp(r'经验主义|經驗主義'),
    RegExp(r'唯心主义|唯心主義'),
    RegExp(r'实在论|實在論'),
    RegExp(r'唯物主义|唯物主義'),
    RegExp(r'斯多葛主义'),
    RegExp(r'怀疑论|懷疑論'),
    RegExp(r'犬儒主义'),
    RegExp(r'享乐主义|享樂主義'),
    RegExp(r'功利主义|功利主義'),
    RegExp(r'决定论|決定論'),
    RegExp(r'实用主义|實用主義'),
    RegExp(r'人文主义|人文主義'),
    RegExp(r'经院哲学|經院哲學'),
    RegExp(r'启蒙运动|啟蒙運動'),

    // ===== Japanese =====
    RegExp(r'哲学'),
    RegExp(r'倫理学|道徳'),
    RegExp(r'論理学'),
    RegExp(r'形而上学'),
    RegExp(r'認識論'),
    RegExp(r'美学'),
    RegExp(r'存在主義'),
    RegExp(r'現象学'),
    RegExp(r'合理主義'),
    RegExp(r'経験主義'),
    RegExp(r'観念論'),
    RegExp(r'実在論'),
    RegExp(r'唯物論'),
    RegExp(r'ストア派'),
    RegExp(r'懐疑主義'),
    RegExp(r'犬儒学派'),
    RegExp(r'享楽主義'),
    RegExp(r'功利主義'),
    RegExp(r'決定論'),
    RegExp(r'プラグマティズム'),
    RegExp(r'ヒューマニズム'),
    RegExp(r'スコラ哲学'),
    RegExp(r'教父学'),
    RegExp(r'啓蒙'),

    // ===== Hebrew =====
    RegExp(r'פילוסופ(יה|י|ים)', caseSensitive: false),
    RegExp(r'אתיקה', caseSensitive: false),
    RegExp(r'מוסר', caseSensitive: false),
    RegExp(r'לוגיקה', caseSensitive: false),
    RegExp(r'מטאפיזיקה', caseSensitive: false),
    RegExp(r'אפיסטמולוגיה', caseSensitive: false),
    RegExp(r'אסתטיקה', caseSensitive: false),
    RegExp(r'אונטולוגיה', caseSensitive: false),
    RegExp(r'אקזיסטנציאליזם', caseSensitive: false),
    RegExp(r'פנומנולוגיה', caseSensitive: false),
    RegExp(r'רציונליזם', caseSensitive: false),
    RegExp(r'אמפיריציזם', caseSensitive: false),
    RegExp(r'אידיאליזם', caseSensitive: false),
    RegExp(r'ריאליזם', caseSensitive: false),
    RegExp(r'מטריאליזם', caseSensitive: false),
    RegExp(r'סטואיציזם', caseSensitive: false),
    RegExp(r'ספקנות', caseSensitive: false),
    RegExp(r'ציניזם', caseSensitive: false),
    RegExp(r'הדוניזם', caseSensitive: false),
    RegExp(r'תועלתנות', caseSensitive: false),
    RegExp(r'דטרמיניזם', caseSensitive: false),
    RegExp(r'פרגמטיזם', caseSensitive: false),
    RegExp(r'הומניזם', caseSensitive: false),
    RegExp(r'סכולסטיקה', caseSensitive: false),
    RegExp(r'נאורות', caseSensitive: false),
  ],
  'poem': [
    RegExp(r'\bpoe(m|try|ms)\b', caseSensitive: false),
    RegExp(r'\bpoesi', caseSensitive: false),
    RegExp(r'\bpoez(j|í|i)a\b', caseSensitive: false),
    RegExp(r'\bgedicht\b', caseSensitive: false), // de
    RegExp(r'\bvers\b', caseSensitive: false),    // fr/es/pt
    RegExp(r'\bstih\b', caseSensitive: false),    // slavic
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
    RegExp(r'\bfiktion\b', caseSensitive: false),  // de
    RegExp(r'\bfutur(ism|o)\b', caseSensitive: false),
    RegExp(r'\btechnolog', caseSensitive: false),
  ],
  'religion': [
    // ===== English =====
    RegExp(r'\breligion(s)?\b', caseSensitive: false),
    RegExp(r'\btheolog(y|ies)\b', caseSensitive: false),
    RegExp(r'\bfaith\b', caseSensitive: false),
    RegExp(r'\bchurch(es)?\b', caseSensitive: false),
    RegExp(r'\bclergy\b', caseSensitive: false),
    RegExp(r'\bbishop(s)?\b', caseSensitive: false),
    RegExp(r'\bprayer(s)?\b', caseSensitive: false),
    RegExp(r'\bsermon(s)?\b', caseSensitive: false),
    RegExp(r'\bhomil(y|ies)\b', caseSensitive: false),
    RegExp(r'\bhymn(s)?\b', caseSensitive: false),
    RegExp(r'\bpsalm(s)?\b', caseSensitive: false),
    RegExp(r'\bpsalter(y|ies)?\b', caseSensitive: false),
    RegExp(r'\bgospel(s)?\b', caseSensitive: false),
    RegExp(r'\bscripture(s)?\b', caseSensitive: false),
    RegExp(r'\bbible\b', caseSensitive: false),
    RegExp(r'\b(testament|apocrypha)\b', caseSensitive: false),
    RegExp(r'\bliturgy\b', caseSensitive: false),
    RegExp(r'\bmonk(s)?\b', caseSensitive: false),
    RegExp(r'\bmonastic\w*\b', caseSensitive: false),
    RegExp(r'\babbey|monastery|convent\b', caseSensitive: false),
    RegExp(r'\bsaint(s)?\b', caseSensitive: false),
    RegExp(r'\bmartyr(s|dom)?\b', caseSensitive: false),
    RegExp(r'\bchristian(ity|ism)?\b', caseSensitive: false),
    RegExp(r'\bcatholic(ism)?\b', caseSensitive: false),
    RegExp(r'\bprotestant(ism)?\b', caseSensitive: false),
    RegExp(r'\borthodox(y)?\b', caseSensitive: false),
    RegExp(r'\banglican\b', caseSensitive: false),
    RegExp(r'\blutheran\b', caseSensitive: false),
    RegExp(r'\bcalvin(ism|ist)?\b', caseSensitive: false),
    RegExp(r'\bmethodis(t|m)\b', caseSensitive: false),
    RegExp(r'\bjesus\b', caseSensitive: false),
    RegExp(r'\bchrist\b', caseSensitive: false),
    RegExp(r'\bgod\b', caseSensitive: false),
    RegExp(r'\bvirgin\s+mary\b', caseSensitive: false),
    RegExp(r'\bmary\b', caseSensitive: false),
    RegExp(r'\bjudaism\b', caseSensitive: false),
    RegExp(r'\bjew(ish)?\b', caseSensitive: false),
    RegExp(r'\btorah\b', caseSensitive: false),
    RegExp(r'\btanakh\b', caseSensitive: false),
    RegExp(r'\btalmud\b', caseSensitive: false),
    RegExp(r'\bmishnah\b', caseSensitive: false),
    RegExp(r'\bmidrash\b', caseSensitive: false),
    RegExp(r'\brabbi\b', caseSensitive: false),
    RegExp(r'\bsynagogue\b', caseSensitive: false),
    RegExp(r'\bkabbalah\b', caseSensitive: false),
    RegExp(r'\bhalakha\b', caseSensitive: false),
    RegExp(r'\bislam\b', caseSensitive: false),
    RegExp(r'\bmuslim(s)?\b', caseSensitive: false),
    RegExp(r'\bkoran\b', caseSensitive: false),
    RegExp(r"\bqur[’'`]?an\b", caseSensitive: false),
    RegExp(r'\bhadith\b', caseSensitive: false),
    RegExp(r'\bsharia\b', caseSensitive: false),
    RegExp(r'\bbuddh(ism|ist)\b', caseSensitive: false),
    RegExp(r'\bhindu(ism|istic)?\b', caseSensitive: false),
    RegExp(r'\bvedic\b', caseSensitive: false),
    RegExp(r'\bupanishad\w*\b', caseSensitive: false),
    RegExp(r'\bbhagavad\b', caseSensitive: false),
    RegExp(r'\bmah[\- ]?abharat', caseSensitive: false),
    RegExp(r'\bsikh(ism)?\b', caseSensitive: false),
    RegExp(r'\bjain(ism)?\b', caseSensitive: false),
    RegExp(r'\btao(ism)?\b', caseSensitive: false),
    RegExp(r'\bconfucian(ism)?\b', caseSensitive: false),
    RegExp(r'\bzen\b', caseSensitive: false),

    // ===== German =====
    RegExp(r'\breligion(en)?\b', caseSensitive: false),
    RegExp(r'\btheolog(ie|isch)\b', caseSensitive: false),
    RegExp(r'\bglaub(e|en|ens)\b', caseSensitive: false),
    RegExp(r'\bheil(ig|ige|igen)\b', caseSensitive: false),
    RegExp(r'\bheilige\s*schrift\b', caseSensitive: false),
    RegExp(r'\bbibel\b', caseSensitive: false),
    RegExp(r'\b(altes|neues)\s*testament\b', caseSensitive: false),
    RegExp(r'\bevangel(ium|isch)\b', caseSensitive: false),
    RegExp(r'\bkirche(n)?\b', caseSensitive: false),
    RegExp(r'\bpfarrer\b', caseSensitive: false),
    RegExp(r'\bpriester\b', caseSensitive: false),
    RegExp(r'\bpredigt(en)?\b', caseSensitive: false),
    RegExp(r'\bgebet(e)?\b', caseSensitive: false),
    RegExp(r'\bpsalm(en)?\b', caseSensitive: false),
    RegExp(r'\bpsalter\b', caseSensitive: false),
    RegExp(r'\bheiligen(?:legenden)?\b', caseSensitive: false),
    RegExp(r'\bkloster\b', caseSensitive: false),
    RegExp(r'\bm[öo]nch(e)?\b', caseSensitive: false),
    RegExp(r'\bgott\b', caseSensitive: false),
    RegExp(r'\bjesus\b', caseSensitive: false),
    RegExp(r'\bmaria\b', caseSensitive: false),
    RegExp(r'\borthodox(ie)?\b', caseSensitive: false),
    RegExp(r'\bprotestant(isch|ismus)?\b', caseSensitive: false),
    RegExp(r'\bkathol(isch|izismus)\b', caseSensitive: false),

    // ===== French =====
    RegExp(r'\breligion(s)?\b', caseSensitive: false),
    RegExp(r'\bth[ée]ologie\b', caseSensitive: false),
    RegExp(r'\bfoi\b', caseSensitive: false),
    RegExp(r'\bsacr[ée]?\b', caseSensitive: false),
    RegExp(r'\bsaint(e|s)?\b', caseSensitive: false),
    RegExp(r'\bmartyr(e|s)?\b', caseSensitive: false),
    RegExp(r'\b[eé]glise(s)?\b', caseSensitive: false),
    RegExp(r'\bclerg[ée]\b', caseSensitive: false),
    RegExp(r'\b[ée]v[êe]que(s)?\b', caseSensitive: false),
    RegExp(r'\bpri[èe]re(s)?\b', caseSensitive: false),
    RegExp(r'\bsermon(s)?\b', caseSensitive: false),
    RegExp(r'\bhom[ée]lie(s)?\b', caseSensitive: false),
    RegExp(r'\bhymne(s)?\b', caseSensitive: false),
    RegExp(r'\bpsaume(s)?\b', caseSensitive: false),
    RegExp(r'\bpsautier\b', caseSensitive: false),
    RegExp(r'\b[ée]vangile(s)?\b', caseSensitive: false),
    RegExp(r'\b[ée]critures?\b', caseSensitive: false),
    RegExp(r'\bbible\b', caseSensitive: false),
    RegExp(r'\btestament\b', caseSensitive: false),
    RegExp(r'\bliturgie\b', caseSensitive: false),
    RegExp(r'\bchr[ée]tien(ne|s|t[ée])?\b', caseSensitive: false),
    RegExp(r'\bcatholicisme\b', caseSensitive: false),
    RegExp(r'\bprotestant(isme)?\b', caseSensitive: false),
    RegExp(r'\borthodoxe\b', caseSensitive: false),
    RegExp(r'\bcalvin(isme)?\b', caseSensitive: false),
    RegExp(r'\bjuif(s|ve)?\b', caseSensitive: false),
    RegExp(r'\bjuda[ïi]sme\b', caseSensitive: false),
    RegExp(r'\btalmud\b', caseSensitive: false),
    RegExp(r'\btorah\b', caseSensitive: false),
    RegExp(r'\bsynagogue\b', caseSensitive: false),
    RegExp(r'\bislam\b', caseSensitive: false),
    RegExp(r'\bmusulman(e|s)?\b', caseSensitive: false),
    RegExp(r'\bcoran\b', caseSensitive: false),
    RegExp(r'\bhadith\b', caseSensitive: false),
    RegExp(r'\bbouddh(isme|iste)s?\b', caseSensitive: false),
    RegExp(r'\bhindou(isme)?\b', caseSensitive: false),

    // ===== Spanish / Portuguese =====
    RegExp(r'\breligi[óo]n(es)?\b', caseSensitive: false),
    RegExp(r'\bteolog[íi]a\b', caseSensitive: false),
    RegExp(r'\bfe\b', caseSensitive: false),
    RegExp(r'\bsagrad[ao]s?\b', caseSensitive: false),
    RegExp(r'\bsant[oa]s?\b', caseSensitive: false),
    RegExp(r'\bm[áa]rtir(es)?\b', caseSensitive: false),
    RegExp(r'\biglesia(s)?\b', caseSensitive: false),
    RegExp(r'\bclero\b', caseSensitive: false),
    RegExp(r'\bobispo(s)?\b', caseSensitive: false),
    RegExp(r'\boraci[óo]n(es)?\b', caseSensitive: false),
    RegExp(r'\bserm[óo]n(es)?\b', caseSensitive: false),
    RegExp(r'\bhomil[íi]a(s)?\b', caseSensitive: false),
    RegExp(r'\bhimno(s)?\b', caseSensitive: false),
    RegExp(r'\bsalmo(s)?\b', caseSensitive: false),
    RegExp(r'\bsalterio\b', caseSensitive: false),
    RegExp(r'\bevangelio(s)?\b', caseSensitive: false),
    RegExp(r'\bescritura(s)?\b', caseSensitive: false),
    RegExp(r'\bbiblia\b', caseSensitive: false),
    RegExp(r'\btestamento\b', caseSensitive: false),
    RegExp(r'\bliturgia\b', caseSensitive: false),
    RegExp(r'\bcristian(ismo|o|a)s?\b', caseSensitive: false),
    RegExp(r'\bcat[óo]lic[oa]s?\b', caseSensitive: false),
    RegExp(r'\bprotestant(ismo|e)s?\b', caseSensitive: false),
    RegExp(r'\bordodox[oa]s?\b', caseSensitive: false),
    RegExp(r'\bjud[íi]o(s|a)?\b', caseSensitive: false),
    RegExp(r'\bjuda[íi]smo\b', caseSensitive: false),
    RegExp(r'\btalmud\b', caseSensitive: false),
    RegExp(r'\btor[áa]\b', caseSensitive: false),
    RegExp(r'\bsinagog[ao]?\b', caseSensitive: false),
    RegExp(r'\bislam\b', caseSensitive: false),
    RegExp(r'\bmusulm[áa]n(es|a)?\b', caseSensitive: false),
    RegExp(r'\bcor[áa]n\b', caseSensitive: false),
    RegExp(r'\bhadiz\b', caseSensitive: false),
    RegExp(r'\bbud(ismo|ista)s?\b', caseSensitive: false),
    RegExp(r'\bhind(uis|[úu])mo\b', caseSensitive: false),

    // ===== Italian =====
    RegExp(r'\breligione(i)?\b', caseSensitive: false),
    RegExp(r'\bteologia\b', caseSensitive: false),
    RegExp(r'\bfede\b', caseSensitive: false),
    RegExp(r'\bsacro\b', caseSensitive: false),
    RegExp(r'\bsanto/i|santa/e\b', caseSensitive: false),
    RegExp(r'\bmartir(e|i)\b', caseSensitive: false),
    RegExp(r'\bchiesa(e)?\b', caseSensitive: false),
    RegExp(r'\bclero\b', caseSensitive: false),
    RegExp(r'\bvescovo(i)?\b', caseSensitive: false),
    RegExp(r'\bpreghiera(e)?\b', caseSensitive: false),
    RegExp(r'\bsermone(i)?\b', caseSensitive: false),
    RegExp(r'\bomelia(e)?\b', caseSensitive: false),
    RegExp(r'\binno(i)?\b', caseSensitive: false),
    RegExp(r'\bsalmo(i)?\b', caseSensitive: false),
    RegExp(r'\bsalterio\b', caseSensitive: false),
    RegExp(r'\bevangel(o|i)o\b', caseSensitive: false),
    RegExp(r'\bscrittura(e)?\b', caseSensitive: false),
    RegExp(r'\bbibbia\b', caseSensitive: false),
    RegExp(r'\btestamento\b', caseSensitive: false),
    RegExp(r'\bliturgia\b', caseSensitive: false),
    RegExp(r'\bcristian(esimo|o|a)\b', caseSensitive: false),
    RegExp(r'\bcattolic(ismo|o|a)\b', caseSensitive: false),
    RegExp(r'\bprotestantesimo\b', caseSensitive: false),
    RegExp(r'\bortodoss(o|a|i)\b', caseSensitive: false),
    RegExp(r'\beg(e|i)s[ùu]\b', caseSensitive: false),
    RegExp(r'\bdio\b', caseSensitive: false),
    RegExp(r'\bmaria\b', caseSensitive: false),

    // ===== Russian / Slavic =====
    RegExp(r'религ', caseSensitive: false),
    RegExp(r'богослов', caseSensitive: false),
    RegExp(r'\bвера\b', caseSensitive: false),
    RegExp(r'свят(ой|ая|ые)', caseSensitive: false),
    RegExp(r'мученик', caseSensitive: false),
    RegExp(r'церков', caseSensitive: false),
    RegExp(r'епископ', caseSensitive: false),
    RegExp(r'молитв', caseSensitive: false),
    RegExp(r'проповед', caseSensitive: false),
    RegExp(r'гимн', caseSensitive: false),
    RegExp(r'псалм', caseSensitive: false),
    RegExp(r'псалтыр', caseSensitive: false),
    RegExp(r'евангел', caseSensitive: false),
    RegExp(r'писан(и|ь)й', caseSensitive: false),
    RegExp(r'библия', caseSensitive: false),
    RegExp(r'завет', caseSensitive: false),
    RegExp(r'литург', caseSensitive: false),
    RegExp(r'православ', caseSensitive: false),
    RegExp(r'католиц', caseSensitive: false),
    RegExp(r'протестан', caseSensitive: false),
    RegExp(r'иудаиз', caseSensitive: false),
    RegExp(r'иудей', caseSensitive: false),
    RegExp(r'талмуд', caseSensitive: false),
    RegExp(r'тора', caseSensitive: false),
    RegExp(r'синагог', caseSensitive: false),
    RegExp(r'ислам', caseSensitive: false),
    RegExp(r'мусульман', caseSensitive: false),
    RegExp(r'коран', caseSensitive: false),
    RegExp(r'хадис', caseSensitive: false),
    RegExp(r'буддизм', caseSensitive: false),
    RegExp(r'индуизм', caseSensitive: false),
    RegExp(r'конфуциан', caseSensitive: false),
    RegExp(r'даос', caseSensitive: false),
    RegExp(r'дзен', caseSensitive: false),

    // ===== Greek (modern & ancient) =====
    RegExp(r'θρησκεία', caseSensitive: false),
    RegExp(r'θεολογ', caseSensitive: false),
    RegExp(r'πίστ', caseSensitive: false),
    RegExp(r'άγ(ιος|ια|ιοι)', caseSensitive: false),
    RegExp(r'μάρτυρ', caseSensitive: false),
    RegExp(r'εκκλησία', caseSensitive: false),
    RegExp(r'επίσκοπ', caseSensitive: false),
    RegExp(r'προσευχ', caseSensitive: false),
    RegExp(r'κήρυγ', caseSensitive: false),
    RegExp(r'ύμν', caseSensitive: false),
    RegExp(r'ψαλμ', caseSensitive: false),
    RegExp(r'ψαλτήρ', caseSensitive: false),
    RegExp(r'ευαγγέλ', caseSensitive: false),
    RegExp(r'γραφή', caseSensitive: false),
    RegExp(r'βίβλος', caseSensitive: false),
    RegExp(r'διαθήκη', caseSensitive: false),
    RegExp(r'λειτουργ', caseSensitive: false),
    RegExp(r'ορθόδοξ', caseSensitive: false),
    RegExp(r'καθολικ', caseSensitive: false),
    RegExp(r'προτεσταντ', caseSensitive: false),

    // ===== Latin =====
    RegExp(r'\breligio\b', caseSensitive: false),
    RegExp(r'\btheologi', caseSensitive: false),
    RegExp(r'\bfides\b', caseSensitive: false),
    RegExp(r'\bsacrum\b', caseSensitive: false),
    RegExp(r'\bsanct(us|a|i|ae)\b', caseSensitive: false),
    RegExp(r'\bmartyr\b', caseSensitive: false),
    RegExp(r'\becclesia\b', caseSensitive: false),
    RegExp(r'\bbiblia\b', caseSensitive: false),
    RegExp(r'\btestamentum\b', caseSensitive: false),
    RegExp(r'\bevangelium\b', caseSensitive: false),
    RegExp(r'\boratio\b', caseSensitive: false),
    RegExp(r'\bsermo\b', caseSensitive: false),
    RegExp(r'\bhymnus\b', caseSensitive: false),
    RegExp(r'\bpsalm(us|i)\b', caseSensitive: false),
    RegExp(r'\bpsalterium\b', caseSensitive: false),
    RegExp(r'\bliturgia\b', caseSensitive: false),
    RegExp(r'\bdeus\b', caseSensitive: false),
    RegExp(r'\biesus\b', caseSensitive: false),
    RegExp(r'\bmaria\b', caseSensitive: false),

    // ===== Scandinavian (sv/da/no) =====
    RegExp(r'\breligion\b', caseSensitive: false),
    RegExp(r'\bteologi\b', caseSensitive: false),
    RegExp(r'\b(kirke|kyrka|kirke)\b', caseSensitive: false),
    RegExp(r'\bmenighed|menighet\b', caseSensitive: false),
    RegExp(r'\bhelgen|helgon\b', caseSensitive: false),
    RegExp(r'\bbibel\b', caseSensitive: false),
    RegExp(r'\btestamente\b', caseSensitive: false),
    RegExp(r'\bgud\b', caseSensitive: false),
    RegExp(r'\bjesus\b', caseSensitive: false),
    RegExp(r'\bmaria\b', caseSensitive: false),
    RegExp(r'\bb[øöo]n|bøn\b', caseSensitive: false),
    RegExp(r'\bpr[æe]diken|predikan\b', caseSensitive: false),
    RegExp(r'\bpsalm(er)?\b', caseSensitive: false),
    RegExp(r'\bsalme(r)?\b', caseSensitive: false),
    RegExp(r'\bsalmebog\b', caseSensitive: false),

    // ===== Finnish =====
    RegExp(r'\buskonto\b', caseSensitive: false),
    RegExp(r'\bteologia\b', caseSensitive: false),
    RegExp(r'\bkirkko\b', caseSensitive: false),
    RegExp(r'\bpyh[äa]\b', caseSensitive: false),
    RegExp(r'\braamattu\b', caseSensitive: false),
    RegExp(r'\btestamentti\b', caseSensitive: false),
    RegExp(r'\bjumala\b', caseSensitive: false),
    RegExp(r'\bjeesus\b', caseSensitive: false),
    RegExp(r'\bmaria\b', caseSensitive: false),
    RegExp(r'\brukous\b', caseSensitive: false),
    RegExp(r'\bsaarna\b', caseSensitive: false),
    RegExp(r'\bvirsi\b', caseSensitive: false),
    RegExp(r'\bpsalmi\b', caseSensitive: false),
    RegExp(r'\bevankeliumi\b', caseSensitive: false),

    // ===== Polish =====
    RegExp(r'\breligia\b', caseSensitive: false),
    RegExp(r'\bteologia\b', caseSensitive: false),
    RegExp(r'\bkościoł', caseSensitive: false),
    RegExp(r'\bświęt(y|a|o|e)\b', caseSensitive: false),
    RegExp(r'\bbiblia\b', caseSensitive: false),
    RegExp(r'\btestament\b', caseSensitive: false),
    RegExp(r'\bb[óo]g\b', caseSensitive: false),
    RegExp(r'\bjezus\b', caseSensitive: false),
    RegExp(r'\bmaria\b', caseSensitive: false),
    RegExp(r'\bmodlitw', caseSensitive: false),
    RegExp(r'\bkazani', caseSensitive: false),
    RegExp(r'\bhymn', caseSensitive: false),
    RegExp(r'\bpsalm', caseSensitive: false),
    RegExp(r'\bpsałterz', caseSensitive: false),
    RegExp(r'\bewangelia\b', caseSensitive: false),
    RegExp(r'\bprawosław', caseSensitive: false),
    RegExp(r'\bkatolicyzm\b', caseSensitive: false),
    RegExp(r'\bprotestantyzm\b', caseSensitive: false),

    // ===== Catalan =====
    RegExp(r'\breligi[óo]\b', caseSensitive: false),
    RegExp(r'\bteologia\b', caseSensitive: false),
    RegExp(r'\besgl[ée]sia\b', caseSensitive: false),
    RegExp(r'\bsant(a|s)?\b', caseSensitive: false),
    RegExp(r'\bb[íi]blia\b', caseSensitive: false),
    RegExp(r'\btestament\b', caseSensitive: false),
    RegExp(r'\bd[ée]u\b', caseSensitive: false),
    RegExp(r'\bjes[úu]s\b', caseSensitive: false),
    RegExp(r'\bmaria\b', caseSensitive: false),
    RegExp(r'\boraci[óo]\b', caseSensitive: false),
    RegExp(r'\bserm[óo]\b', caseSensitive: false),
    RegExp(r'\bhimne\b', caseSensitive: false),
    RegExp(r'\bsalm\b', caseSensitive: false),
    RegExp(r'\bsaltiri\b', caseSensitive: false),
    RegExp(r'\bevangeli\b', caseSensitive: false),

    // ===== Esperanto =====
    RegExp(r'\breligio\b', caseSensitive: false),
    RegExp(r'\bteologio\b', caseSensitive: false),
    RegExp(r'\beklezio\b', caseSensitive: false),
    RegExp(r'\bsankta(j|n)?\b', caseSensitive: false),
    RegExp(r'\bbiblio\b', caseSensitive: false),
    RegExp(r'\btestamento\b', caseSensitive: false),
    RegExp(r'\bdio\b', caseSensitive: false),
    RegExp(r'\bjesuo\b', caseSensitive: false),
    RegExp(r'\bmario\b', caseSensitive: false),
    RegExp(r'\bpreĝo\b', caseSensitive: false),
    RegExp(r'\bprediko\b', caseSensitive: false),
    RegExp(r'\bhimno\b', caseSensitive: false),
    RegExp(r'\bpsalmo\b', caseSensitive: false),
    RegExp(r'\bpsaltaro\b', caseSensitive: false),
    RegExp(r'\bevangelio\b', caseSensitive: false),

    // ===== Chinese (简/繁) =====
    RegExp(r'宗教|神学|教会'),
    RegExp(r'圣经|聖經'),
    RegExp(r'旧约|舊約'),
    RegExp(r'新约|新約'),
    RegExp(r'上帝|神'),
    RegExp(r'耶稣|耶穌'),
    RegExp(r'玛利亚|瑪利亞'),
    RegExp(r'祈祷|祈禱'),
    RegExp(r'布道'),
    RegExp(r'赞美诗|讚美詩|圣歌|聖歌'),
    RegExp(r'诗篇|詩篇'),

    // ===== Japanese =====
    RegExp(r'宗教'),
    RegExp(r'神学'),
    RegExp(r'教会'),
    RegExp(r'聖書'),
    RegExp(r'旧約|新約'),
    RegExp(r'神|イエス|マリア'),
    RegExp(r'祈り'),
    RegExp(r'説教'),
    RegExp(r'賛美歌'),
    RegExp(r'詩編|詩篇'),

    // ===== Hebrew =====
    RegExp(r'יהדות', caseSensitive: false),              // Judaism
    RegExp(r'תורה', caseSensitive: false),               // Torah
    RegExp(r'תנ"?ך', caseSensitive: false),              // Tanakh
    RegExp(r'תלמוד', caseSensitive: false),              // Talmud
    RegExp(r'משנה', caseSensitive: false),               // Mishnah
    RegExp(r'מדרש', caseSensitive: false),              // Midrash
    RegExp(r'רב', caseSensitive: false),                 // Rabbi
    RegExp(r'בית\s*כנסת', caseSensitive: false),        // Synagogue
    RegExp(r'תפילה', caseSensitive: false),             // Prayer
    RegExp(r'תהילים', caseSensitive: false),            // Psalms
    // Additional religious/biblical/literary subjects from dump
    RegExp(r'בראשית|genesis', caseSensitive: false),     // Book of Genesis
    RegExp(r'שמות|šemot', caseSensitive: false),         // Book of Exodus (Šemot)
    RegExp(r'ספר(ים| הקבצנים)?|ספורים|ספור(ים)?', caseSensitive: false), // sefarim / seforim (books/scriptures)
    RegExp(r'אהבת\s+ציון', caseSensitive: false),        // Love of Zion (classic religious novel)
    RegExp(r'ציונו?ת|Zionism', caseSensitive: false),    // Zionism
    RegExp(r'מדינת\s+היהודים|Judenstaat', caseSensitive: false), // The Jewish State
    RegExp(r'ספר\s+הקבצנים', caseSensitive: false),     // Book of Beggars
    // Religious authors / Jewish literary figures tied to religion & Zionism
    RegExp(r'אברהם\s+מאפו|Abraham\s+Mapu', caseSensitive: false),
    RegExp(r'אחד\s+העם|Ahad\s+Haam|Asher\s+Ginzberg', caseSensitive: false),
    RegExp(r'אליעזר\s+בן\s+יהודה|Ben\s+Yehuda', caseSensitive: false),
    RegExp(r'מנדלה\s+מוכר\s+ספרים|Mendele', caseSensitive: false),
    RegExp(r'שלום\s+עליכם|Shalom\s+Aleichem|Solomon\s+Rabinovich', caseSensitive: false),
    RegExp(r'יוסף\s+חיים?\s+ברנר|Yosef\s+(Haim|Hayim)\s+Brenner', caseSensitive: false),
    RegExp(r'ביאליק|biaik', caseSensitive: false),       // H.N. Bialik, Jewish poet
    RegExp(r'Micah|מיכה', caseSensitive: false),         // Micah / prophet
    RegExp(r"(?:\b(?:Micah|Micha)\s+(?:Yosef|Joseph|Josef)?\s*(?:Berdichevsky|Berdychevsky|Berdichevski|Berdichevskii|Berdyczewski)\b|מיכה(?:\s+יוסף)?\s+ברדיצ['׳’]?בסקי)", caseSensitive: false),
    // Cultural/Religious Jewish life subjects
    RegExp(r'ספרות\s+עברית|Hebrew\s+literature', caseSensitive: false),
    RegExp(r'שירה\s+עברית|Hebrew\s+poetry', caseSensitive: false),
    RegExp(r'חיים\s+יהודיים|Jewish\s+life', caseSensitive: false),
    RegExp(r'הגירה\s+יהודית|Jewish\s+immigration', caseSensitive: false),
    RegExp(r'סופר\s+יהודי|Jewish\s+poet', caseSensitive: false),
    RegExp(r'עיירה\s+יהודית|shtetl|Jewish\s+town', caseSensitive: false),
  ],
};

/// Build subject OR-clause for a category by merging:
///  - base English seeds (genresSubjectsJson),
///  - all subjects from each selected language that match the category filters.
Future<String> _buildSubjectQueryForGenre(String genreLower) async {
  await _LanguageSubjectIndex.ensureLoaded();

  // Selected UI language codes (normalized + filtered)
  final box = Hive.box('language_prefs_box');
  final selected = List<String>.from(
    box.get('selectedLanguages', defaultValue: <String>[]),
  ).map((c) => c.toLowerCase()).where((c) => _langAliases.containsKey(c)).toList();

  // Try memo first: key is "<langs>#<genre>"
  final memoKey = '${selected.join(",")}#$genreLower';
  final memoHit = _genreSubjectMemo[memoKey];
  if (memoHit != null) return memoHit;

  final base = genresSubjectsJson[genreLower] ?? <String>[genreLower];
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

  // Fallback: add a few obvious stems if nothing new was added
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

  final clause = tokens.join(' OR ');
  _genreSubjectMemo[memoKey] = clause;
  return clause;
}

class ArchiveApi {
  // Reuse one client to keep TCP alive & reduce handshake cost.
  static final http.Client _client = http.Client();

  // Very small in-memory cache (URL -> response + validators).
  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  static const Duration _maxStale = Duration(minutes: 15); // tune as you like
  static const int _maxEntries = 100; // tiny LRU-ish trim

  ArchiveApi() {
    // If the user changes language prefs, recompute next time.
    Hive.box('language_prefs_box').watch(key: 'selectedLanguages').listen((_) {
      _invalidateLangMemo();
      _genreSubjectMemo.clear();
    });
  }

  // Centralized GET with conditional requests.
  static Future<String> _getJson(String url) async {
    final headers = <String, String>{};
    final cached = _cache[url];

    if (cached != null && DateTime.now().difference(cached.storedAt) < _maxStale) {
      if (cached.etag != null) headers['If-None-Match'] = cached.etag!;
      if (cached.lastModified != null) headers['If-Modified-Since'] = cached.lastModified!;
    }

    final resp = await _client.get(Uri.parse(url), headers: headers);

    if (resp.statusCode == 304 && cached != null) {
      // Not modified — serve cached body
      return cached.body;
    }
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} for $url');
    }

    final etag = resp.headers['etag'];
    final lastMod = resp.headers['last-modified'];

    // Store/refresh cache (simple trim to avoid unbounded growth)
    _cache[url] = _CacheEntry(
      body: resp.body,
      etag: etag,
      lastModified: lastMod,
      storedAt: DateTime.now(),
    );
    if (_cache.length > _maxEntries) {
      // Drop the stalest ~10% (super simple)
      final entries = _cache.entries.toList()
        ..sort((a, b) => a.value.storedAt.compareTo(b.value.storedAt));
      for (var i = 0; i < (_maxEntries / 10).ceil(); i++) {
        _cache.remove(entries[i].key);
      }
    }

    return resp.body;
  }

  // Optional: call this from app shutdown if you want.
  static void dispose() => _client.close();

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
        .split(RegExp(r'\s+OR\s+', caseSensitive: false)) // split by any 'OR' variant
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
      final body = await _getJson(url);
      final resJson = json.decode(body);

      final List result = resJson["result"] ?? const [];
      String? highQCoverImage = result.firstWhere(
            (item) => item is Map && item["source"] == "original" && item["format"] == "JPEG",
        orElse: () => null,
      )?["name"];

      final files = <AudiobookFile>[];
      for (final item in result) {
        if (item is Map && item["source"] == "original" && item["track"] != null) {
          item["identifier"] = identifier;
          item["highQCoverImage"] = highQCoverImage;
          files.add(AudiobookFile.fromJson(item));
        }
      }
      return Right(files);
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
      final body = await _getJson(url);
      final docs = json.decode(body)['response']['docs'];
      return Right(Audiobook.fromJsonArray(docs));
    } catch (e) {
      return Left(e.toString());
    }
  }
}
