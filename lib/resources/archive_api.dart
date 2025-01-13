import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:http/http.dart' as http;
import 'package:aradia/resources/models/audiobook_file.dart';

const _commonParams =
    "q=collection:(librivoxaudio)&fl=runtime,avg_rating,num_reviews,title,description,identifier,creator,date,downloads,subject,item_size,language";

const _latestAudiobook =
    "https://archive.org/advancedsearch.php?$_commonParams&sort[]=addeddate+desc&output=json";

const _mostViewedInThisWeek =
    "https://archive.org/advancedsearch.php?$_commonParams&sort[]=week+desc&output=json";

const _mostDownloadedOfAllTime =
    "https://archive.org/advancedsearch.php?$_commonParams&sort[]=downloads+desc&output=json";

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
    return _fetchAudiobooks("$_latestAudiobook&page=$page&rows=$rows");
  }

  Future<Either<String, List<Audiobook>>> getMostViewedWeeklyAudiobook(
    int page,
    int rows,
  ) async {
    return _fetchAudiobooks("$_mostViewedInThisWeek&page=$page&rows=$rows");
  }

  Future<Either<String, List<Audiobook>>> getMostDownloadedEverAudiobook(
    int page,
    int rows,
  ) async {
    return _fetchAudiobooks("$_mostDownloadedOfAllTime&page=$page&rows=$rows");
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

    final url =
        "https://archive.org/advancedsearch.php?q=collection:(audio_bookspoetry)+AND+subject:($genreQuery)&fl=runtime,avg_rating,num_reviews,title,description,identifier,creator,date,downloads,subject,item_size,language&sort[]=$sortBy+desc&output=json&page=$page&rows=$rows";
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
    final url =
        "https://archive.org/advancedsearch.php?q=$searchQuery+AND+collection:(audio_bookspoetry)&fl=runtime,avg_rating,num_reviews,title,description,identifier,creator,date,downloads,subject,item_size,language&sort[]=downloads+desc&output=json&page=$page&rows=$rows";

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
