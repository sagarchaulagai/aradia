// lib/screens/home/widgets/history_section.dart
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/resources/services/local/cover_image_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
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

  // Helper: seconds for a file whether it's a full file (length in seconds)
  // or a chapter slice (durationMs in milliseconds).
  double _secondsForFile(AudiobookFile f) {
    if (f.durationMs != null) return (f.durationMs! / 1000.0);
    return f.length ?? 0.0;
  }

  // This method is used to format the progress of the audiobook.
  // position = current track position in ms
  // total = total duration of the whole book in seconds
  // completedTime = total seconds from all tracks BEFORE the current index
  String formatProgress(int position, double total, double completedTime) {
    final totalTimeCompleted = position + completedTime * 1000;
    final duration = Duration(milliseconds: totalTimeCompleted.toInt());

    final totalMinutes = total / 60.0; // total seconds → minutes
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
      height: 235,
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

  // Uses the centralized cover resolver/provider so History shows the same cover
  // precedence as the grid and the player.
  Widget _historyCoverTile(HistoryOfAudiobookItem item, double size) {
    return StreamBuilder<String>(
      stream: coverArtBus.stream,
      builder: (context, _) {
        return FutureBuilder<String?>(
          future: resolveCoverForHistory(item),
          builder: (context, snap) {
            final v = snap.data;
            if (v != null && v.isNotEmpty) {
              return Image(
                image: coverProvider(v),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, _, __) => _placeholderCover(size),
              );
            }
            return _placeholderCover(size);
          },
        );
      },
    );
  }

  Widget _placeholderCover(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryColor.withValues(alpha: 0.7),
            AppColors.primaryColor,
          ],
        ),
      ),
      child: const Icon(Icons.headphones, color: Colors.white70, size: 42),
    );
  }

  Widget _buildHistoryItem(
    HistoryOfAudiobookItem item,
    double totalTimeSeconds,
    double completedSecondsBeforeIndex,
  ) {
    final progress = totalTimeSeconds > 0
        ? (item.position + (completedSecondsBeforeIndex * 1000)) /
            (totalTimeSeconds * 1000)
        : 0.0;

    return Container(
      width: 175,
      padding: const EdgeInsets.only(right: 8),
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

          final hist =
              historyOfAudiobook.getHistoryOfAudiobookItem(item.audiobook.id);
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
                title: Text(
                  'Delete History',
                  style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold),
                ),
                content: Text(
                  'Do you want to delete this audiobook from history?',
                  style: GoogleFonts.ubuntu(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.ubuntu(color: Colors.grey[600]),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (audioHandlerProvider.audioHandler
                              .getCurrentAudiobookId() ==
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
                                  child: Text(
                                    'OK',
                                    style: GoogleFonts.ubuntu(
                                      color: AppColors.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                        return;
                      }

                      historyOfAudiobook
                          .removeAudiobookFromHistory(item.audiobook.id);
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Delete',
                      style: GoogleFonts.ubuntu(
                        color: AppColors.primaryColor,
                      ),
                    ),
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
                      height: 175,
                      width: 175,
                      child: _historyCoverTile(item, 175),
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
                        const IconTheme(
                          data: IconThemeData(color: Colors.black, size: 14),
                          child:
                              Icon(Ionicons.help_circle, color: Colors.black),
                        ),
                        IconTheme(
                          data: const IconThemeData(
                              color: Colors.white, size: 12),
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
              style: GoogleFonts.ubuntu(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    formatProgress(
                      item.position,
                      totalTimeSeconds,
                      completedSecondsBeforeIndex,
                    ),
                    style: GoogleFonts.ubuntu(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
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
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Text(
                'Recently Played',
                style: GoogleFonts.ubuntu(
                    fontSize: 22, fontWeight: FontWeight.bold),
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
              height: 235,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: historyItems.length,
                itemBuilder: (context, index) {
                  final item = historyItems[index];

                  // Total book duration (seconds) — supports chapter slices.
                  final double totalSecs = item.audiobookFiles.fold(
                    0.0,
                    (sum, f) => sum + _secondsForFile(f),
                  );

                  // Seconds completed across all tracks prior to the current one.
                  double completedSecs = 0;
                  for (int i = 0; i < item.index; i++) {
                    completedSecs += _secondsForFile(item.audiobookFiles[i]);
                  }

                  return _buildHistoryItem(item, totalSecs, completedSecs);
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
