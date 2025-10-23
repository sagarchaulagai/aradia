import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/utils/app_constants.dart';
import 'package:aradia/utils/app_logger.dart';

class YoutubeAudiobookNotifier extends ChangeNotifier {
  static final YoutubeAudiobookNotifier _instance =
      YoutubeAudiobookNotifier._internal();
  factory YoutubeAudiobookNotifier() => _instance;
  YoutubeAudiobookNotifier._internal();

  List<Audiobook> _audiobooks = [];
  bool _isLoading = false;
  String? _error;

  List<Audiobook> get audiobooks => _audiobooks;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchAudiobooks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) {
        throw Exception('Could not access storage directory');
      }

      final youtubeDir =
          Directory(p.join(appDir.path, AppConstants.youtubeDirName));
      if (!await youtubeDir.exists()) {
        _audiobooks = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final List<Audiobook> audiobooks = [];
      final entities = youtubeDir.list();

      await for (final entity in entities) {
        if (entity is Directory) {
          final audiobookFile = File(p.join(entity.path, 'audiobook.txt'));
          if (await audiobookFile.exists()) {
            try {
              final content = await audiobookFile.readAsString();
              final audiobookData = jsonDecode(content) as Map<String, dynamic>;

              // Ensure origin is set
              if (!audiobookData.containsKey('origin') ||
                  audiobookData['origin'] == null) {
                audiobookData['origin'] = AppConstants.youtubeDirName;
              }

              // Handle cover image path
              if (audiobookData['lowQCoverImage'] != null &&
                  !(audiobookData['lowQCoverImage'] as String)
                      .startsWith('http') &&
                  (audiobookData['lowQCoverImage'] as String).isNotEmpty) {
                if (!p.isAbsolute(audiobookData['lowQCoverImage'])) {
                  audiobookData['lowQCoverImage'] =
                      p.join(entity.path, audiobookData['lowQCoverImage']);
                }
              }

              if (audiobookData['id'] != null &&
                  audiobookData['title'] != null) {
                audiobooks.add(Audiobook.fromMap(audiobookData));
              }
            } catch (e) {
              AppLogger.debug(
                  'Error decoding audiobook.txt in ${entity.path}: $e');
            }
          }
        }
      }

      // Sort by date (newest first)
      audiobooks.sort((a, b) {
        if (a.date == null && b.date == null) return 0;
        if (a.date == null) return 1;
        if (b.date == null) return -1;
        return b.date!.compareTo(a.date!);
      });

      _audiobooks = audiobooks;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      AppLogger.debug('Error fetching YouTube audiobooks: $e');
      notifyListeners();
    }
  }

  Future<bool> deleteAudiobook(String audiobookId) async {
    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) {
        throw Exception('Could not access storage directory');
      }

      final youtubeDir =
          Directory(p.join(appDir.path, AppConstants.youtubeDirName));
      final audiobookDir = Directory(p.join(youtubeDir.path, audiobookId));

      if (await audiobookDir.exists()) {
        await audiobookDir.delete(recursive: true);

        // Remove from local list
        _audiobooks.removeWhere((audiobook) => audiobook.id == audiobookId);
        notifyListeners();

        AppLogger.debug('Successfully deleted audiobook: $audiobookId');
        return true;
      } else {
        AppLogger.debug('Audiobook directory not found: $audiobookId');
        return false;
      }
    } catch (e) {
      AppLogger.debug('Error deleting audiobook $audiobookId: $e');
      return false;
    }
  }

  bool isAudiobookAlreadyImported(String audiobookId) {
    return _audiobooks.any((audiobook) => audiobook.id == audiobookId);
  }

  void addAudiobook(Audiobook audiobook) {
    // Check if audiobook already exists
    final existingIndex = _audiobooks.indexWhere((ab) => ab.id == audiobook.id);

    if (existingIndex != -1) {
      // Update existing audiobook
      _audiobooks[existingIndex] = audiobook;
    } else {
      // Add new audiobook
      _audiobooks.insert(0, audiobook); // Add at beginning for newest first
    }

    // Re-sort to maintain order
    _audiobooks.sort((a, b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });

    notifyListeners();
  }

  void refresh() {
    fetchAudiobooks();
  }
}
