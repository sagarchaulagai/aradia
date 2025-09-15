// lib/screens/home/widgets/history_section.dart
import 'dart:io';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

import '../../../resources/designs/app_colors.dart';

class HistorySection extends StatefulWidget {
  const HistorySection({super.key});

  @override
  State<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<HistorySection> {
  final HistoryOfAudiobook historyOfAudiobook = HistoryOfAudiobook();
  late Box<dynamic> playingAudiobookDetailsBox;
  late AudioHandlerProvider audioHandlerProvider;
  late WeSlideController _weSlideController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    audioHandlerProvider = Provider.of<AudioHandlerProvider>(context);
    _weSlideController = Provider.of<WeSlideController>(context);
  }

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Cover resolution for History tiles
  // Prefers mapped per-book cover (by audiobook.id), then legacy keys, then
  // audiobook.lowQCoverImage, then first track's highQCoverImage.
  // ────────────────────────────────────────────────────────────────────────────
  static const String _coverMappingBoxName = 'cover_image_mapping';

  Future<String?> _getMappedCover(String key) async {
    try {
      final box = await Hive.openBox(_coverMappingBoxName);
      final path = box.get(key);
      if (path is String && path.isNotEmpty) {
        final f = File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path);
        if (await f.exists()) return f.path;
        // clean stale entry
        await box.delete(key);
      }
    } catch (_) {}
    return null;
  }

  // Helper: if URL is local-file-ish, return canonical file path; otherwise null.
  String? _asLocalPath(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      if (s.startsWith('file://')) return Uri.parse(s).toFilePath();
      if (s.startsWith('/')) return s;
      // treat windows-style abs paths too just in case
      if (s.contains(':/') && !s.startsWith('http')) return s;
    } catch (_) {}
    return null;
  }

  Future<String?> _resolveHistoryCover(HistoryOfAudiobookItem item) async {
    final a = item.audiobook;

    // 1) Preferred: mapped by audiobook.id (after your recent changes id == cover key)
    final byId = await _getMappedCover(a.id);
    if (byId != null) return byId;

    // 2) Legacy keys: try folder of first track (multi-track books) and track path (single-file books)
    if (item.audiobookFiles.isNotEmpty) {
      final firstUrl = item.audiobookFiles.first.url;
      final firstLocal = _asLocalPath(firstUrl);
      if (firstLocal != null) {
        // a) mapping by the exact file (single-file root books)
        final byFile = await _getMappedCover(firstLocal);
        if (byFile != null) return byFile;

        // b) mapping by the parent folder (multi-track folder books)
        final byFolder = await _getMappedCover(p.dirname(firstLocal));
        if (byFolder != null) return byFolder;
      }
    }

    // 3) Fallback to whatever the Audiobook carried (might be local path or URL)
    final low = a.lowQCoverImage;
    final lowLocal = _asLocalPath(low);
    if (lowLocal != null && await File(lowLocal).exists()) return lowLocal;
    if (low != null && low.isNotEmpty) return low; // URL or unknown, let Image.network handle it

    // 4) Last resort: first track's highQCoverImage (may come from metadata)
    if (item.audiobookFiles.isNotEmpty) {
      final hi = item.audiobookFiles.first.highQCoverImage;
      final hiLocal = _asLocalPath(hi);
      if (hiLocal != null && await File(hiLocal).exists()) return hiLocal;
      if (hi != null && hi.isNotEmpty) return hi;
    }

    return null;
  }

  // This method is used to format the progress of the audiobook
  String formatProgress(int position, double total, double completedTime) {
    final totalTimeCompleted = position + completedTime * 1000;
    final duration = Duration(milliseconds: totalTimeCompleted.toInt());

    final totalMinutes = total / 60;
    final completedMinutes = duration.inMinutes.toDouble();

    if (totalMinutes >= 1000) {
      final completedHours = completedMinutes / 60.0;
      final totalHours = totalMinutes / 60.0;
      return '${completedHours.toStringAsFixed(1)}h / ${totalHours.toStringAsFixed(1)}h';
    } else {
      return '${completedMinutes.toStringAsFixed(0)}m / ${totalMinutes.toStringAsFixed(0)}m';
    }
  }

  Widget _buildEmptyState() {
    return Container(
      height: 220,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No listening history yet',
              style: GoogleFonts.ubuntu(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Start listening to audiobooks and they'll appear here",
              textAlign: TextAlign.center,
              style: GoogleFonts.ubuntu(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCoverTile(HistoryOfAudiobookItem item, double size) {
    return FutureBuilder<String?>(
      future: _resolveHistoryCover(item),
      builder: (context, snap) {
        final v = snap.data;
        if (v != null && v.isNotEmpty) {
          // local file?
          final local = _asLocalPath(v);
          if (local != null && File(local).existsSync()) {
            return Image.file(File(local), width: size, height: size, fit: BoxFit.cover);
          }
          // remote or other path
          return Image.network(v, width: size, height: size, fit: BoxFit.cover);
        }
        // Placeholder
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryColor.withOpacity(0.7),
                AppColors.primaryColor,
              ],
            ),
          ),
          child: const Icon(Icons.headphones, color: Colors.white70, size: 42),
        );
      },
    );
  }

  Widget _buildHistoryItem(
      HistoryOfAudiobookItem item,
      double totalTime,
      double completedTime,
      ) {
    final progress = totalTime > 0
        ? (item.position + (completedTime * 1000)) / (totalTime * 1000)
        : 0.0;

    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onTap: () {
          if (audioHandlerProvider.audioHandler.getCurrentAudiobookId() ==
              item.audiobook.id) {
            _weSlideController.show();
            return;
          }

          playingAudiobookDetailsBox.put('audiobook', item.audiobook.toMap());
          playingAudiobookDetailsBox.put(
            'audiobookFiles',
            item.audiobookFiles.map((e) => e.toMap()).toList(),
          );

          final hist = historyOfAudiobook.getHistoryOfAudiobookItem(item.audiobook.id);
          audioHandlerProvider.audioHandler.initSongs(
            item.audiobookFiles,
            item.audiobook,
            hist.index,
            hist.position,
          );
          playingAudiobookDetailsBox.put('index', hist.index);
          playingAudiobookDetailsBox.put('position', hist.position);

          _weSlideController.show();
        },
        onLongPress: () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('Delete History', style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold)),
                content: Text('Do you want to delete this audiobook from history?', style: GoogleFonts.ubuntu()),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: GoogleFonts.ubuntu(color: Colors.grey[600])),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (audioHandlerProvider.audioHandler.getCurrentAudiobookId() ==
                          item.audiobook.id) {
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text(
                                'Cannot Delete',
                                style: GoogleFonts.ubuntu(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                              content: Text(
                                "This audiobook is currently playing. Can't delete it from history.",
                                style: GoogleFonts.ubuntu(),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: Text('OK', style: GoogleFonts.ubuntu(color: AppColors.primaryColor)),
                                ),
                              ],
                            );
                          },
                        );
                        return;
                      }

                      historyOfAudiobook.removeAudiobookFromHistory(item.audiobook.id);
                      Navigator.of(context).pop();
                    },
                    child: Text('Delete', style: GoogleFonts.ubuntu(color: AppColors.primaryColor)),
                  ),
                ],
              );
            },
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover + progress bar + origin badge
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 160,
                      width: 160,
                      child: _historyCoverTile(item, 160),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: Colors.black38,
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: AppColors.primaryColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 8,
                    child: Stack(
                      children: [
                        IconTheme(
                          data: const IconThemeData(color: Colors.black, size: 14),
                          child: _getOriginIcon(item.audiobook.origin),
                        ),
                        IconTheme(
                          data: const IconThemeData(color: Colors.white, size: 12),
                          child: _getOriginIcon(item.audiobook.origin),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              item.audiobook.title,
              style: GoogleFonts.ubuntu(fontSize: 15, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Track ${item.index + 1}',
                    style: GoogleFonts.ubuntu(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formatProgress(item.position, totalTime, completedTime),
                    style: GoogleFonts.ubuntu(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _getOriginIcon(String? origin) {
    if (origin == 'librivox') {
      return const Icon(Ionicons.book, color: Colors.white, size: 15);
    } else if (origin == 'youtube') {
      return const Icon(Ionicons.logo_youtube, color: Colors.white, size: 15);
    } else if (origin == 'download') {
      return const Icon(Ionicons.cloud_download, color: Colors.white, size: 15);
    } else if (origin == 'local') {
      return const Icon(Ionicons.musical_notes, color: Colors.white, size: 15);
    } else {
      return const Icon(Ionicons.help_circle, color: Colors.white, size: 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Text(
                'Recently Played',
                style: GoogleFonts.ubuntu(fontSize: 22, fontWeight: FontWeight.bold),
              )
            ],
          ),
        ),
        StreamBuilder(
          stream: historyOfAudiobook.historyStream,
          builder: (context, snapshot) {
            if (snapshot.data == null) return _buildEmptyState();

            final historyItems = snapshot.data as List<HistoryOfAudiobookItem>;
            if (historyItems.isEmpty) return _buildEmptyState();

            return SizedBox(
              height: 220,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: historyItems.length,
                itemBuilder: (context, index) {
                  final item = historyItems[index];
                  final double totalTime = item.audiobookFiles.fold(
                    0.0,
                        (sum, file) => sum + (file.length ?? 0.0),
                  );

                  double completedTime = 0;
                  for (int i = 0; i < item.index; i++) {
                    completedTime += (item.audiobookFiles[i].length ?? 0);
                  }

                  return _buildHistoryItem(item, totalTime, completedTime);
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
