import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aradia/utils/media_helper.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/resources/services/local/chapter_parser.dart';
import 'package:aradia/resources/services/local/cover_image_service.dart';
import 'package:aradia/resources/services/local/local_audiobook_service.dart';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:saf/saf.dart';
import 'package:we_slide/we_slide.dart';

import '../../../utils/app_logger.dart';

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
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
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
                padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                child: Column(
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
                            const Icon(Icons.audiotrack,
                                size: 14, color: AppColors.primaryColor),
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
      future: resolveCoverForLocal(audiobook),
      builder: (context, snapshot) {
        final v = snapshot.data;
        if (v != null && v.isNotEmpty) {
          return Image(
            image: coverProvider(v),
            width: width,
            height: width,
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) => _buildPlaceholderCover(),
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
            AppColors.primaryColor.withValues(alpha: 0.7),
            AppColors.primaryColor,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.headphones,
              size: 48, color: Colors.white.withValues(alpha: 0.8)),
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

      final convertedAudiobook = await _convertToAudiobook();
      final audiobookFiles = await _convertToAudiobookFiles();

      // Store audiobook details in Hive (used by player + mini-player)
      await playingAudiobookDetailsBox.put(
        'audiobook',
        convertedAudiobook.toMap(),
      );
      await playingAudiobookDetailsBox.put(
        'audiobookFiles',
        audiobookFiles.map((e) => e.toMap()).toList(),
      );

      if (historyOfAudiobook.isAudiobookInHistory(convertedAudiobook.id)) {
        final hist =
            historyOfAudiobook.getHistoryOfAudiobookItem(convertedAudiobook.id);
        await audioHandlerProvider.audioHandler.initSongs(
          audiobookFiles,
          convertedAudiobook,
          hist.index,
          hist.position,
        );
        await playingAudiobookDetailsBox.put('index', hist.index);
        await playingAudiobookDetailsBox.put('position', hist.position);
      } else {
        await playingAudiobookDetailsBox.put('index', 0);
        await playingAudiobookDetailsBox.put('position', 0);
        await audioHandlerProvider.audioHandler.initSongs(
          audiobookFiles,
          convertedAudiobook,
          0,
          0,
        );
      }

      weSlideController.show();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error playing audiobook: $e')),
      );
    }
  }

  // Convert LocalAudiobook to Audiobook format (ID uses centralized layout key)
  Future<Audiobook> _convertToAudiobook() async {
    final key = MediaHelper.bookKeyForLocal(audiobook);
    final resolvedCover = await resolveCoverForLocal(audiobook);

    return Audiobook.fromMap({
      'id': key,
      'title': audiobook.title,
      'author': audiobook.author,
      'description': audiobook.description ?? '',
      'lowQCoverImage': resolvedCover, // unified custom/embedded resolution
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
    final key = MediaHelper.bookKeyForLocal(audiobook);

    // Resolve one cover to reuse across all tracks
    final resolvedCover = await resolveCoverForLocal(audiobook);

    // If single-file book, try chapter slices
    if (files.length == 1) {
      final filePath = MediaHelper.decodePath(files.first);
      AppLogger.info('filePath: $filePath', "LocalAudiobookItem");
      final lower = filePath.toLowerCase();
      final isChapterable = lower.endsWith('.m4b') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.mp3');

      if (isChapterable) {
        try {
          // Get root folder path for SAF operations
          final rootFolderPath =
              await LocalAudiobookService.getRootFolderPath();
          if (rootFolderPath == null) {
            AppLogger.error(
                'Root folder path is null, cannot cache file for chapter parsing');
            // Fall through to default single-track handling
          } else {
            // Cache the file using SAF singleCache method
            AppLogger.info('Caching file for chapter parsing: $filePath');
            String? cachedFilePath = await Saf(rootFolderPath)
                .singleCache(
                  filePath: filePath,
                  directory: rootFolderPath,
                )
                .timeout(const Duration(seconds: 30));

            if (cachedFilePath != null) {
              AppLogger.info('File cached successfully: $cachedFilePath');
              final f = File(cachedFilePath);
              final cues = await ChapterParser.parseFile(f);
              if (cues.length > 1) {
                AppLogger.info('Found ${cues.length} chapters in file');
                for (int i = 0; i < cues.length; i++) {
                  final start = cues[i].startMs;
                  final int? durationMs = (i + 1 < cues.length)
                      ? (cues[i + 1].startMs - start).clamp(1, 1 << 31)
                      : null;

                  out.add(
                    AudiobookFile.chapterSlice(
                      identifier: key,
                      url: MediaHelper.makeSafUriFromPath(
                          filePath), // Use original path, not cached path
                      parentTitle: audiobook.title,
                      track: i + 1,
                      chapterTitle: cues[i].title,
                      startMs: start,
                      durationMs: durationMs,
                      highQCoverImage: resolvedCover,
                    ),
                  );
                }
                return out; // done
              } else {
                AppLogger.info(
                    'No chapters found in file, falling back to single-track handling');
              }
            } else {
              AppLogger.error(
                  'Failed to cache file for chapter parsing: $filePath');
              // Fall through to default single-track handling
            }
          }
        } catch (e) {
          AppLogger.error('Error parsing chapters for file $filePath: $e');
          // fall through to default single-track handling
        }
      }
    }

    // Default: multi-file book or no chapter cues
    for (final entry in files.asMap().entries) {
      final index = entry.key;
      final filePath = MediaHelper.decodePath(entry.value);
      final fileName = filePath.split('/').last.split('\\').last;
      final uri = MediaHelper.makeSafUriFromPath(filePath);
      double? duration = audiobook.totalDuration?.inSeconds.toDouble();

      out.add(AudiobookFile.fromMap({
        'identifier': key,
        'track': index + 1,
        'title': fileName.replaceAll(RegExp(r'\.[^.]*$'), ''),
        'name': fileName,
        'url': uri,
        'length': duration,
        'size': null,
        'highQCoverImage': resolvedCover,
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

  // For "Use Default" tile
  bool _hasCustomCover = false;
  String? _defaultPreviewPath;

  @override
  void initState() {
    super.initState();
    _fetchCoverImages();
    _loadCoverState();
  }

  Future<void> _loadCoverState() async {
    final key = MediaHelper.bookKeyForLocal(widget.audiobook);
    final mapped = await getMappedCoverImage(key);
    final def = await resolveDefaultCoverForLocal(widget.audiobook);
    if (!mounted) return;
    setState(() {
      _hasCustomCover = mapped != null;
      _defaultPreviewPath = def;
    });
  }

  Future<void> _fetchCoverImages() async {
    setState(() => _isFetchingCovers = true);
    try {
      final coverUrls = await CoverImageRemote.fetchCoverImages(
        widget.audiobook.title,
        widget.audiobook.author,
      );
      if (!mounted) return;
      setState(() {
        _coverImageUrls = coverUrls;
        _isFetchingCovers = false;
      });
    } catch (e) {
      AppLogger.error('Error fetching cover images: $e');
      if (!mounted) return;
      setState(() => _isFetchingCovers = false);
    }
  }

  Future<void> _saveCoverImage() async {
    if (_selectedCoverUrl == null) return;
    setState(() => _isLoading = true);

    try {
      final downloadedPath =
          await CoverImageRemote.downloadCoverImage(_selectedCoverUrl!);

      if (downloadedPath != null) {
        await mapCoverForLocal(widget.audiobook, downloadedPath);

        if (mounted) {
          _hasCustomCover = true;
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _useDefaultCover() async {
    setState(() => _isLoading = true);
    try {
      final key = MediaHelper.bookKeyForLocal(widget.audiobook);

      // Remove custom mapping (deletes file, clears cache, emits coverArtBus)
      await removeCoverMapping(key);

      // Update "now playing" stored cover to the default metadata path
      final fallback = await resolveDefaultCoverForLocal(widget.audiobook);
      final box = Hive.box('playing_audiobook_details_box');
      final map = Map<String, dynamic>.from(box.get('audiobook') ?? {});
      if ((map['id'] as String?) == key) {
        map['lowQCoverImage'] = fallback;
        await box.put('audiobook', map);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reverted to default cover.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reverting cover: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasCustomCover = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Cover Image',
                          style: GoogleFonts.ubuntu(
                              fontSize: 20, fontWeight: FontWeight.bold)),
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

            // Content
            Expanded(child: _buildContent()),

            const SizedBox(height: 20),

            // Actions
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

    if (_coverImageUrls.isEmpty && !_hasCustomCover) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: Colors.grey[400]),
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
              style: GoogleFonts.ubuntu(fontSize: 14, color: Colors.grey[600]),
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

    final showUseDefault = _hasCustomCover;
    final itemCount = _coverImageUrls.length + (showUseDefault ? 1 : 0);

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Index 0 = "Use Default" tile when custom cover exists
        if (showUseDefault && index == 0) {
          return GestureDetector(
            onTap: _isLoading ? null : _useDefaultCover,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryColor, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      if (_defaultPreviewPath != null)
                        Image(
                          image: coverProvider(_defaultPreviewPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, _, __) =>
                              _defaultTilePlaceholder(),
                        )
                      else
                        _defaultTilePlaceholder(),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          color: Colors.black54,
                          alignment: Alignment.center,
                          child: const Text(
                            'Use Default',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      if (_isLoading)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x66000000),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Shift index when "Use Default" exists
        final dataIndex = showUseDefault ? index - 1 : index;
        final imageUrl = _coverImageUrls[dataIndex];
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
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Image(
                      image: coverProvider(imageUrl),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, _, __) => Container(
                        color: Colors.grey[200],
                        child:
                            const Icon(Icons.broken_image, color: Colors.grey),
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
                          child: const Icon(Icons.check,
                              color: Colors.white, size: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _defaultTilePlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.image_not_supported, color: Colors.grey),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
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
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save Cover'),
        ),
      ],
    );
  }
}

/// Network-only helpers used by the cover picker UI.
/// Mapping/lookup logic lives in cover_image_service.dart.
class CoverImageRemote {
  static const _duckDuckGoUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';

  static const Map<String, String> _duckDuckGoHeaders = {
    'User-Agent': _duckDuckGoUserAgent,
  };

  static const Map<String, String> _duckDuckGoImageHeaders = {
    'User-Agent': _duckDuckGoUserAgent,
    'Referer': 'https://duckduckgo.com/',
  };

  static Future<List<String>> fetchCoverImages(
      String title, String author) async {
    try {
      final trimmedTitle = title.trim();
      final trimmedAuthor = author.trim();
      final queryParts = <String>[
        if (trimmedTitle.isNotEmpty) trimmedTitle,
        if (trimmedAuthor.isNotEmpty) trimmedAuthor,
        'audiobook cover',
      ];
      if (queryParts.isEmpty) {
        return [];
      }
      final query = queryParts.join(' ');
      final encodedQuery = Uri.encodeComponent(query);

      final searchUri = Uri.parse(
        'https://duckduckgo.com/?q=$encodedQuery&iax=images&ia=images',
      );
      final searchResponse =
          await http.get(searchUri, headers: _duckDuckGoHeaders);
      if (searchResponse.statusCode != 200) {
        return [];
      }

      final vqd = _extractDuckDuckGoVqd(searchResponse.body);
      if (vqd == null || vqd.isEmpty) {
        AppLogger.debug('DuckDuckGo vqd token missing for query: $query',
            'CoverImageRemote');
        return [];
      }

      final imagesUri = Uri.parse(
        'https://duckduckgo.com/i.js?l=us-en&o=json&q=$encodedQuery&vqd=$vqd&p=1',
      );
      final imagesResponse =
          await http.get(imagesUri, headers: _duckDuckGoImageHeaders);
      if (imagesResponse.statusCode != 200) {
        return [];
      }

      final decoded = json.decode(imagesResponse.body);
      final results = decoded['results'];
      if (results is! List) {
        return [];
      }

      final seen = <String>{};
      final scored = <_ScoredCover>[];

      for (var i = 0; i < results.length; i++) {
        final item = results[i];
        if (item is! Map) continue;

        final rawImage = item['image'] ?? item['thumbnail'];
        if (rawImage is! String || rawImage.isEmpty) continue;

        final normalized = rawImage.replaceFirst(RegExp('^http:'), 'https:');
        if (!seen.add(normalized)) continue;

        double? width = (item['width'] as num?)?.toDouble();
        double? height = (item['height'] as num?)?.toDouble();

        if ((width == null || height == null) &&
            item['thumbnail_width'] != null &&
            item['thumbnail_height'] != null) {
          width = (item['thumbnail_width'] as num?)?.toDouble();
          height = (item['thumbnail_height'] as num?)?.toDouble();
        }

        final score = _squarenessScore(width, height);
        scored
            .add(_ScoredCover(url: normalized, score: score, originalIndex: i));
      }

      if (scored.isEmpty) {
        return [];
      }

      return _sortCoversBySquareness(scored);
    } catch (e) {
      AppLogger.error('Error fetching cover images from DuckDuckGo: $e');
    }
    return [];
  }

  static Future<String?> downloadCoverImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) return null;

      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) return null;

      final coverImagesDir =
          Directory(path.join(externalDir.path, 'localCoverImages'));
      if (!await coverImagesDir.exists()) {
        await coverImagesDir.create(recursive: true);
      }

      final randomName = _generateRandomString(10);
      final filePath = path.join(coverImagesDir.path, '$randomName.jpg');

      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      AppLogger.debug('Downloaded cover image to: $filePath');
      return filePath;
    } catch (e) {
      AppLogger.error('Error downloading cover image: $e');
      return null;
    }
  }

  static String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  static List<String> _sortCoversBySquareness(List<_ScoredCover> scored) {
    scored.sort((a, b) {
      final scoreCompare = a.score.compareTo(b.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.originalIndex.compareTo(b.originalIndex);
    });
    return scored.map((e) => e.url).toList();
  }

  static double _squarenessScore(double? width, double? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return double.infinity;
    }
    final larger = max(width, height);
    final smaller = min(width, height);
    if (smaller == 0) return double.infinity;
    return (larger / smaller - 1).abs();
  }

  static String? _extractDuckDuckGoVqd(String body) {
    final quotedMatch =
        RegExp("vqd=([\'\"])([A-Za-z0-9-]+)\\1").firstMatch(body);
    if (quotedMatch != null) {
      return quotedMatch.group(2);
    }
    final unquotedMatch = RegExp(r'vqd=([A-Za-z0-9-]+)&').firstMatch(body);
    if (unquotedMatch != null) {
      return unquotedMatch.group(1);
    }
    return null;
  }
}

class _ScoredCover {
  final String url;
  final double score;
  final int originalIndex;

  const _ScoredCover({
    required this.url,
    required this.score,
    required this.originalIndex,
  });
}
