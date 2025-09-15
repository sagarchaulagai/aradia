import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/resources/services/chapter_parser.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:we_slide/we_slide.dart';

import '../../../utils/app_logger.dart';

// Unique key for mapping covers to *this* local book.
String coverKeyForLocal(LocalAudiobook a) {
  // Decode because we store decoded paths elsewhere in this file.
  final files = a.audioFiles.map((s) => Uri.decodeComponent(s)).toList();
  if (files.length == 1) {
    // Root-level or any single-file book: key by the *file* itself.
    return files.first;
  }
  // Multi-track book (folder of tracks): key by the folder.
  return Uri.decodeComponent(a.folderPath);
}

class LocalAudiobookItem extends StatelessWidget {
  final LocalAudiobook audiobook;
  final double width;
  final double height;
  final VoidCallback? onUpdated;

  const LocalAudiobookItem({
    super.key,
    required this.audiobook,
    this.width = 175.0,
    this.height = 250.0,
    this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Ink(
      width: width,
      height: height,
      child: Card(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(8),
          ),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(
            Radius.circular(8),
          ),
          splashColor: AppColors.primaryColor,
          splashFactory: InkRipple.splashFactory,
          onLongPress: () => _showEditDialog(context),
          onTap: () => _playAudiobook(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                child: _buildCoverImage(),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  bottom: 8,
                  left: 8,
                  right: 8,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: width,
                      child: Text(
                        audiobook.title,
                        style: GoogleFonts.ubuntu(
                          textStyle: const TextStyle(
                            overflow: TextOverflow.ellipsis,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      audiobook.author,
                      style: GoogleFonts.ubuntu(
                        textStyle: const TextStyle(
                          overflow: TextOverflow.ellipsis,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.audiotrack,
                              size: 14,
                              color: AppColors.primaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${audiobook.audioFiles.length} files',
                              style: GoogleFonts.ubuntu(
                                textStyle: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (audiobook.totalDuration != null)
                          Text(
                            audiobook.formattedDuration,
                            style: GoogleFonts.ubuntu(
                              textStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    return FutureBuilder<String?>(
      future: CoverImageService.getBestCoverPathForLocal(audiobook),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          final coverFile = File(snapshot.data!);
          return Image.file(
            coverFile,
            width: width,
            height: width,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildPlaceholderCover(),
          );
        }
        return _buildPlaceholderCover();
      },
    );
  }

  Widget _buildPlaceholderCover() {
    return Container(
      width: width,
      height: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryColor.withOpacity(0.7),
            AppColors.primaryColor,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.headphones,
            size: 48,
            color: Colors.white.withOpacity(0.8),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              audiobook.title,
              style: GoogleFonts.ubuntu(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => LocalAudiobookCoverSelector(
        audiobook: audiobook,
        onUpdated: onUpdated,
      ),
    );
  }

  void _playAudiobook(BuildContext context) async {
    try {
      final audioHandlerProvider =
          Provider.of<AudioHandlerProvider>(context, listen: false);
      final weSlideController =
          Provider.of<WeSlideController>(context, listen: false);
      final playingAudiobookDetailsBox =
          Hive.box('playing_audiobook_details_box');
      final historyOfAudiobook = HistoryOfAudiobook();

      // Convert LocalAudiobook to required format
      final convertedAudiobook = await _convertToAudiobook();
      final audiobookFiles = await _convertToAudiobookFiles();

      // Store audiobook details in Hive
      playingAudiobookDetailsBox.put('audiobook', convertedAudiobook.toMap());
      playingAudiobookDetailsBox.put(
          'audiobookFiles', audiobookFiles.map((e) => e.toMap()).toList());

      // Check if audiobook is in history
      if (historyOfAudiobook.isAudiobookInHistory(convertedAudiobook.id)) {
        final historyItem =
            historyOfAudiobook.getHistoryOfAudiobookItem(convertedAudiobook.id);
        audioHandlerProvider.audioHandler.initSongs(
          audiobookFiles,
          await convertedAudiobook,
          historyItem.index,
          historyItem.position,
        );
        playingAudiobookDetailsBox.put('index', historyItem.index);
        playingAudiobookDetailsBox.put('position', historyItem.position);
      } else {
        playingAudiobookDetailsBox.put('index', 0);
        playingAudiobookDetailsBox.put('position', 0);
        audioHandlerProvider.audioHandler.initSongs(
          audiobookFiles,
          await convertedAudiobook,
          0,
          0,
        );
      }

      // Start playback
      audioHandlerProvider.audioHandler.play();
      weSlideController.show();
    } catch (e) {
      // Handle error - could show a snackbar or dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audiobook: $e')),
      );
    }
  }

  // Convert LocalAudiobook to Audiobook format
  Future<Audiobook> _convertToAudiobook() async {
    final key = coverKeyForLocal(audiobook);
    return Audiobook.fromMap({
      'id': key, // was: audiobook.folderPath
      'title': audiobook.title,
      'author': audiobook.author,
      'description': audiobook.description ?? '',
      'lowQCoverImage': audiobook.coverImagePath != null
          ? Uri.decodeComponent(audiobook.coverImagePath!)
          : await CoverImageService.getMappedCoverImage(key), // was: folderPath
      'subject': ['Local Audiobook'],
      'language': 'Unknown',
      'origin': 'local',
      'rating': audiobook.rating ?? 0.0,
      'totalTime': null,
      'date': null,
      'downloads': 0,
      'size': 0,
      'reviews': 0,
    });
  }

  // Convert audio files to AudiobookFile format
  Future<List<AudiobookFile>> _convertToAudiobookFiles() async {
    final List<AudiobookFile> out = [];
    final files = audiobook.audioFiles;
    final key = coverKeyForLocal(audiobook);

    if (files.length == 1) {
      final filePath = Uri.decodeComponent(files.first);
      final lower = filePath.toLowerCase();
      final isChapterable = lower.endsWith('.m4b') || lower.endsWith('.mp4') || lower.endsWith('.m4a') || lower.endsWith('.mp3');

      if (isChapterable) {
        try {
          // Parse chapters
          final f = File(filePath);
          final cues = await ChapterParser.parseFile(f);

          if (cues.length > 1) {
            // Build per-chapter slices
            for (int i = 0; i < cues.length; i++) {
              final start = cues[i].startMs;
              final int? durationMs = (i + 1 < cues.length)
                  ? (cues[i + 1].startMs - start).clamp(1, 1 << 31)
                  : null; // last chapter goes to EOF

              out.add(
                AudiobookFile.chapterSlice(
                  identifier: key,
                  url: filePath,
                  parentTitle: audiobook.title,
                  track: i + 1,
                  chapterTitle: cues[i].title,
                  startMs: start,
                  durationMs: durationMs,
                  highQCoverImage: audiobook.coverImagePath != null
                      ? Uri.decodeComponent(audiobook.coverImagePath!)
                      : null,
                ),
              );
            }
            return out; // done
          }
        } catch (e) {
          // fall back to default
        }
      }
    }

    // Default behavior (multi-file folder books OR no chapters found)
    for (final entry in files.asMap().entries) {
      final index = entry.key;
      final filePath = Uri.decodeComponent(entry.value);
      final fileName = filePath.split('/').last.split('\\').last;

      double? duration;
      try {
        final file = File(filePath);
        if (await file.exists()) {
          duration = await MediaHelper.getAudioDuration(file);
        }
      } catch (_) {
        duration = null;
      }

      out.add(AudiobookFile.fromMap({
        'identifier': key,
        'track': index + 1,
        'title': fileName.replaceAll(RegExp(r'\.[^.]*$'), ''),
        'name': fileName,
        'url': filePath,
        'length': duration,
        'size': null,
        'highQCoverImage': audiobook.coverImagePath != null
            ? Uri.decodeComponent(audiobook.coverImagePath!)
            : null,
        // No startMs/durationMs for whole-file tracks
      }));
    }

    return out;
  }
}

class LocalAudiobookCoverSelector extends StatefulWidget {
  final LocalAudiobook audiobook;
  final VoidCallback? onUpdated;

  const LocalAudiobookCoverSelector({
    super.key,
    required this.audiobook,
    this.onUpdated,
  });

  @override
  State<LocalAudiobookCoverSelector> createState() =>
      _LocalAudiobookCoverSelectorState();
}

class _LocalAudiobookCoverSelectorState
    extends State<LocalAudiobookCoverSelector> {
  List<String> _coverImageUrls = [];
  String? _selectedCoverUrl;
  bool _isLoading = false;
  bool _isFetchingCovers = false;

  @override
  void initState() {
    super.initState();
    _fetchCoverImages();
  }

  Future<void> _fetchCoverImages() async {
    setState(() {
      _isFetchingCovers = true;
    });

    try {
      final coverUrls = await CoverImageService.fetchCoverImagesFromGoogle(
        widget.audiobook.title,
        widget.audiobook.author,
      );

      setState(() {
        _coverImageUrls = coverUrls;
        _isFetchingCovers = false;
      });
    } catch (e) {
      AppLogger.error('Error fetching cover images: $e');
      setState(() {
        _isFetchingCovers = false;
      });
    }
  }

  Future<void> _saveCoverImage() async {
    if (_selectedCoverUrl == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Download the selected cover image
      final downloadedPath =
      await CoverImageService.downloadCoverImage(_selectedCoverUrl!);

      if (downloadedPath != null) {
        final key = coverKeyForLocal(widget.audiobook);
        await CoverImageService.mapCoverImage(key, downloadedPath);

        // Remove any old per-folder mapping so other books don’t inherit it
        await CoverImageService.removeCoverMapping(widget.audiobook.folderPath);


        if (mounted) {
          Navigator.pop(context);
          widget.onUpdated?.call();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cover image saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to download cover image'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error saving cover image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving cover image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Cover Image',
                        style: GoogleFonts.ubuntu(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.audiobook.title} by ${widget.audiobook.author}',
                        style: GoogleFonts.ubuntu(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _buildContent(),
            ),
            const SizedBox(height: 20),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isFetchingCovers) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryColor),
            SizedBox(height: 16),
            Text('Fetching cover images...'),
          ],
        ),
      );
    }

    if (_coverImageUrls.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No cover images found',
              style: GoogleFonts.ubuntu(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching with a different title or author',
              style: GoogleFonts.ubuntu(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchCoverImages,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: _coverImageUrls.length,
      itemBuilder: (context, index) {
        final imageUrl = _coverImageUrls[index];
        final isSelected = _selectedCoverUrl == imageUrl;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedCoverUrl = isSelected ? null : imageUrl;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppColors.primaryColor : Colors.grey[300]!,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryColor,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed:
              _selectedCoverUrl != null && !_isLoading ? _saveCoverImage : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save Cover'),
        ),
      ],
    );
  }
}

class CoverImageService {
  static const String _coverMappingBoxName = 'cover_image_mapping';

  static Future<String?> getBestCoverPathForLocal(LocalAudiobook a) async {
    // 1) Per-book mapping (new, correct behavior)
    // 1) Unified key (exactly what we use when saving)
    final byKey = await getMappedCoverImage(coverKeyForLocal(a));
    if (byKey != null) return byKey;

    // 2) Optional: historical per-id mapping (if you ever had one)
    final byId = await getMappedCoverImage(a.id);
    if (byId != null) return byId;

    // 3) Legacy per-folder mapping
    final byFolder = await getMappedCoverImage(a.folderPath);
    if (byFolder != null) return byFolder;

    // 3) Embedded/explicit cover in the audiobook itself
    if (a.coverImagePath != null) {
      final p = Uri.decodeComponent(a.coverImagePath!);
      final f = File(p);
      if (await f.exists()) return p;
    }

    return null;
  }

  // Get cover images from Google Books API
  static Future<List<String>> fetchCoverImagesFromGoogle(
      String title, String author) async {
    try {
      final query = Uri.encodeComponent('$title $author');
      final url =
          'https://www.googleapis.com/books/v1/volumes?q=$query&maxResults=10';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<String> coverUrls = [];

        if (data['items'] != null) {
          for (final item in data['items']) {
            final volumeInfo = item['volumeInfo'];
            if (volumeInfo['imageLinks'] != null) {
              // Get different sizes if available
              final imageLinks = volumeInfo['imageLinks'];
              if (imageLinks['thumbnail'] != null) {
                coverUrls.add(imageLinks['thumbnail']);
              }
              if (imageLinks['smallThumbnail'] != null) {
                coverUrls.add(imageLinks['smallThumbnail']);
              }
              if (imageLinks['small'] != null) {
                coverUrls.add(imageLinks['small']);
              }
              if (imageLinks['medium'] != null) {
                coverUrls.add(imageLinks['medium']);
              }
            }
          }
        }

        // Remove duplicates and return
        return coverUrls.toSet().toList();
      }
    } catch (e) {
      AppLogger.error('Error fetching cover images from Google: $e');
    }

    return [];
  }

  // Download cover image to external storage
  static Future<String?> downloadCoverImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) return null;

      // Get external storage directory
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) return null;

      // Create localCoverImages directory
      final coverImagesDir =
          Directory(path.join(externalDir.path, 'localCoverImages'));
      if (!await coverImagesDir.exists()) {
        await coverImagesDir.create(recursive: true);
      }

      // Generate random filename
      final randomName = _generateRandomString(10);
      final filePath = path.join(coverImagesDir.path, '$randomName.jpg');

      // Save image
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      AppLogger.debug('Downloaded cover image to: $filePath');
      return filePath;
    } catch (e) {
      AppLogger.error('Error downloading cover image: $e');
      return null;
    }
  }

  // Map audiobook path to cover image path
  static Future<void> mapCoverImage(
      String audiobookPath, String coverImagePath) async {
    try {
      final box = await Hive.openBox(_coverMappingBoxName);
      await box.put(audiobookPath, coverImagePath);
      AppLogger.debug('Mapped $audiobookPath to $coverImagePath');
    } catch (e) {
      AppLogger.error('Error mapping cover image: $e');
    }
  }

  // Get mapped cover image path for audiobook
  static Future<String?> getMappedCoverImage(String audiobookPath) async {
    try {
      final box = await Hive.openBox(_coverMappingBoxName);
      final coverPath = box.get(audiobookPath);

      // Check if file still exists
      if (coverPath != null) {
        final file = File(coverPath);
        if (await file.exists()) {
          return coverPath;
        } else {
          // Remove mapping if file doesn't exist
          await box.delete(audiobookPath);
        }
      }
    } catch (e) {
      AppLogger.error('Error getting mapped cover image: $e');
    }

    return null;
  }

  // Remove cover image mapping
  static Future<void> removeCoverMapping(String audiobookPath) async {
    try {
      final box = await Hive.openBox(_coverMappingBoxName);
      final coverPath = box.get(audiobookPath);

      if (coverPath != null) {
        // Delete the actual file
        final file = File(coverPath);
        if (await file.exists()) {
          await file.delete();
        }

        // Remove mapping
        await box.delete(audiobookPath);
        AppLogger.debug('Removed cover mapping for: $audiobookPath');
      }
    } catch (e) {
      AppLogger.error('Error removing cover mapping: $e');
    }
  }

  // Generate random string for filename
  static String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
          length, (_) => chars.codeUnitAt(random.nextInt(chars.length))),
    );
  }

  // Clean up unused cover images
  static Future<void> cleanupUnusedCoverImages() async {
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) return;

      final coverImagesDir =
          Directory(path.join(externalDir.path, 'localCoverImages'));
      if (!await coverImagesDir.exists()) return;

      final box = await Hive.openBox(_coverMappingBoxName);
      final mappedPaths = box.values.toSet();

      // Delete files that are not mapped
      await for (final entity in coverImagesDir.list()) {
        if (entity is File && !mappedPaths.contains(entity.path)) {
          await entity.delete();
          AppLogger.debug('Cleaned up unused cover image: ${entity.path}');
        }
      }
    } catch (e) {
      AppLogger.error('Error cleaning up cover images: $e');
    }
  }
}
