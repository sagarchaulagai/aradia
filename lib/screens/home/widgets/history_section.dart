import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';
import 'package:ionicons/ionicons.dart';

import '../../../resources/designs/app_colors.dart';
import '../../../widgets/low_and_high_image.dart';

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

  // This method is used to format the progress of the audiobook
  String formatProgress(int position, double total, double completedTime) {
    double totalTimeCompleted = position + completedTime * 1000;
    Duration duration = Duration(milliseconds: totalTimeCompleted.toInt());

    double totalMinutes = total / 60;
    double completedMinutes = duration.inMinutes.toDouble();

    if (totalMinutes >= 1000) {
      // Show hours with 1 decimal
      double completedHours = completedMinutes / 60.0;
      double totalHours = totalMinutes / 60.0;
      return '${completedHours.toStringAsFixed(1)}h / ${totalHours.toStringAsFixed(1)}h';
    } else {
      // Show minutes
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
            Icon(
              Icons.history,
              size: 48,
              color: Colors.grey[400],
            ),
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
              style: GoogleFonts.ubuntu(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
      HistoryOfAudiobookItem item, double totalTime, double completedTime) {
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
          audioHandlerProvider.audioHandler.initSongs(
            item.audiobookFiles,
            item.audiobook,
            historyOfAudiobook
                .getHistoryOfAudiobookItem(item.audiobook.id)
                .index,
            historyOfAudiobook
                .getHistoryOfAudiobookItem(item.audiobook.id)
                .position,
          );
          playingAudiobookDetailsBox.put(
            'index',
            historyOfAudiobook
                .getHistoryOfAudiobookItem(item.audiobook.id)
                .index,
          );
          playingAudiobookDetailsBox.put(
            'position',
            historyOfAudiobook
                .getHistoryOfAudiobookItem(item.audiobook.id)
                .position,
          );
          _weSlideController.show();
        },
        onLongPress: () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(
                  'Delete History',
                  style: GoogleFonts.ubuntu(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Text(
                  'Do you want to delete this audiobook from history?',
                  style: GoogleFonts.ubuntu(),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.ubuntu(
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (audioHandlerProvider.audioHandler
                              .getCurrentAudiobookId() ==
                          item.audiobook.id) {
                        Navigator.of(context).pop(); // Close the current dialog

                        // Show error message in a new dialog
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
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
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

                      historyOfAudiobook.removeAudiobookFromHistory(
                        item.audiobook.id,
                      );
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
                      child: LowAndHighImage(
                        lowQImage: item.audiobook.lowQCoverImage,
                        highQImage: item.audiobookFiles[0].highQCoverImage,
                      ),
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
                        // Shadow/outline icon
                        IconTheme(
                          data: IconThemeData(
                            color: Colors.black,
                            size: 14,
                          ),
                          child: _getOriginIcon(item.audiobook.origin),
                        ),
                        // Main icon
                        IconTheme(
                          data: IconThemeData(
                            color: Colors.white,
                            size: 12,
                          ),
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
                    formatProgress(item.position, totalTime, completedTime),
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
      return const Icon(
        Ionicons.book,
        color: Colors.white,
        size: 15,
      );
    } else if (origin == 'youtube') {
      return const Icon(
        Ionicons.logo_youtube,
        color: Colors.white,
        size: 15,
      );
    } else if (origin == 'download') {
      return const Icon(
        Ionicons.cloud_download,
        color: Colors.white,
        size: 15,
      );
    } else if (origin == 'local') {
      return const Icon(
        Ionicons.musical_notes,
        color: Colors.white,
        size: 15,
      );
    } else {
      // Default icon for unknown origin
      return const Icon(
        Ionicons.help_circle,
        color: Colors.white,
        size: 15,
      );
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
                style: GoogleFonts.ubuntu(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              )
            ],
          ),
        ),
        StreamBuilder(
          stream: historyOfAudiobook.historyStream,
          builder: (context, snapshot) {
            if (snapshot.data == null) {
              return _buildEmptyState();
            }

            final historyItems = snapshot.data as List<HistoryOfAudiobookItem>;
            if (historyItems.isEmpty) {
              return _buildEmptyState();
            }

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
