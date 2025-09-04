import 'dart:async';
import 'package:aradia/utils/app_logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';

class RecommendationService {
  final List<String> excludedGenres = ['librivox', 'audiobooks', 'audiobook'];
  final String hiveBoxName = 'recommened_audiobooks_box';

  Future<List<String>> getRecommendedGenres() async {
    // Step 1: Retrieve history from HistoryOfAudiobook
    List<HistoryOfAudiobookItem> history = HistoryOfAudiobook().getHistory();

    // Step 2: Collect all genres from history, excluding specified genres
    List<String> allHistoryGenres = history
        .where((item) => item.audiobook.origin == "librivox")
        .map((item) => (item.audiobook.subject as List<dynamic>).cast<String>())
        .expand((genres) => genres)
        .where((genre) => !excludedGenres.contains(genre.toLowerCase().trim()))
        .map((genre) => genre.toLowerCase().trim())
        .toList();

    // Step 3: Count frequency of each genre in history
    Map<String, int> genreFrequency = {};
    for (String genre in allHistoryGenres) {
      genreFrequency.update(genre, (count) => count + 1, ifAbsent: () => 1);
    }

    // Step 4: Retrieve selected genres from Hive box
    Box box = await Hive.openBox(hiveBoxName);
    List<String> selectedGenres = box.get('selectedGenres') ?? [];
    selectedGenres = selectedGenres
        .map((genre) => genre.toLowerCase().trim())
        .where((genre) => !excludedGenres.contains(genre))
        .toList();

    // Step 5: Add weight to selected genres
    for (String genre in selectedGenres) {
      genreFrequency.update(genre, (count) => count + 5, ifAbsent: () => 5);
    }

    // Step 6: Sort genres by frequency in descending order
    List<String> sortedGenres = genreFrequency.keys.toList()
      ..sort(
          (a, b) => (genreFrequency[b] ?? 0).compareTo(genreFrequency[a] ?? 0));

    // Step 7: Select top 10 genres
    List<String> recommendedGenres = sortedGenres.take(10).toList();
    recommendedGenres = recommendedGenres
        .map((genre) => genre.split('&'))
        .expand((genres) => genres)
        .toList();
    AppLogger.debug('flutter - recommended genres: $recommendedGenres');
    return recommendedGenres;
  }
}
