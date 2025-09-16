import 'package:aradia/resources/services/youtube/youtube_audiobook_notifier.dart';
import 'package:flutter/material.dart';
import 'package:aradia/widgets/audiobook_item.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:provider/provider.dart';

class YoutubeImportsSection extends StatefulWidget {
  const YoutubeImportsSection({super.key});

  @override
  State<YoutubeImportsSection> createState() => _YoutubeImportsSectionState();
}

class _YoutubeImportsSectionState extends State<YoutubeImportsSection> {
  @override
  void initState() {
    super.initState();
    // Fetch audiobooks when widget initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      YoutubeAudiobookNotifier().fetchAudiobooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YouTube Imports',
                style: GoogleFonts.ubuntu(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isLightMode
                      ? AppColors.textColor
                      : AppColors.darkTextColor,
                ),
              ),
              TextButton(
                onPressed: () {
                  YoutubeAudiobookNotifier().refresh();
                },
                child: Icon(
                  Icons.refresh,
                  color: AppColors.primaryColor,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 250,
          child: Consumer<YoutubeAudiobookNotifier>(
            builder: (context, notifier, child) {
              if (notifier.isLoading) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (notifier.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Error loading YouTube imports',
                        style: GoogleFonts.ubuntu(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final audiobooks = notifier.audiobooks;

              if (audiobooks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.video_library_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No YouTube imports yet',
                        style: GoogleFonts.ubuntu(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.8),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Import videos from YouTube to see them here',
                        style: GoogleFonts.ubuntu(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: audiobooks.length,
                itemBuilder: (context, index) {
                  final audiobook = audiobooks[index];
                  return AudiobookItem(
                    audiobook: audiobook,
                    width: 175,
                    height: 250,
                    onLongPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: Text(
                              'Delete Audiobook',
                              style: GoogleFonts.ubuntu(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            content: Text(
                              'Are you sure you want to delete "${audiobook.title}"? This action cannot be undone.',
                              style: GoogleFonts.ubuntu(),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.ubuntu(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();

                                  // Show loading indicator
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );

                                  // Delete the audiobook
                                  final success =
                                      await YoutubeAudiobookNotifier()
                                          .deleteAudiobook(audiobook.id);

                                  // Hide loading indicator
                                  if (context.mounted) {
                                    Navigator.of(context).pop();

                                    // Show result message
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? 'Audiobook deleted successfully'
                                              : 'Failed to delete audiobook',
                                          style: GoogleFonts.ubuntu(),
                                        ),
                                        backgroundColor:
                                            success ? Colors.green : Colors.red,
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                  'Delete',
                                  style: GoogleFonts.ubuntu(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
