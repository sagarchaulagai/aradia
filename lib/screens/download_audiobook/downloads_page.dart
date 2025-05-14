import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:ionicons/ionicons.dart'; // Using Ionicons for some icons
import 'package:aradia/resources/models/audiobook.dart'; // Your Audiobook model
import 'package:aradia/resources/services/download/download_manager.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:open_filex/open_filex.dart'; // For opening folder/files
// import 'package:url_launcher/url_launcher.dart'; // For opening folder URIs

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final DownloadManager _downloadManager = DownloadManager();
  // It's better to rely on Hive for state rather than local _isPaused flags in the page
  // final Map<String, bool> _isPausedMap = {};

  Future<void> _openDownloadFolder() async {
    try {
      // Consistently use the directory your DownloadManager saves to
      final directory = await getExternalStorageDirectory();
      final downloadsPath = '${directory?.path}/downloads';
      final downloadsDir = Directory(downloadsPath);

      if (!await downloadsDir.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloads folder does not exist yet.')),
          );
        }
        return;
      }

      print('Attempting to open downloads folder: $downloadsPath');

      // Platform-specific ways to open a folder are tricky with just url_launcher for local paths.
      // open_filex or similar packages are better for this.
      // For now, just show the path.
      // if (Platform.isAndroid || Platform.isIOS) { // open_filex might work here
      //   final result = await OpenFilex.open(downloadsPath);
      //   print("Open folder result: ${result.message}");
      // } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Downloads folder: $downloadsPath (Manual navigation may be required)')),
        );
      }
      // }
    } catch (e) {
      print("Error opening download folder: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open download folder: $e')),
        );
      }
    }
  }

  Future<void> _handleItemDeletion(
      BuildContext context, String audiobookId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$title"?', style: GoogleFonts.ubuntu()),
        content: const Text(
            'This will remove the downloaded files from your device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _downloadManager.cancelDownload(audiobookId); // This handles cleanup and Hive
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$title" has been deleted.')),
        );
      }
    }
  }

  void _pauseDownload(String audiobookId, String? firstFileTaskId) {
    final status = Hive.box('download_status_box').get('status_$audiobookId')
        as Map<dynamic, dynamic>?;

    // For now, only enable for direct downloads if a task ID exists
    bool isYouTubeDownload = status?['files']?.any((file) =>
            (file['url'] as String).contains('youtube.com') ||
            (file['url'] as String).contains('youtu.be')) ??
        false; // crude check

    if (!isYouTubeDownload && firstFileTaskId != null) {
      print('UI: Pausing direct download for $audiobookId, task $firstFileTaskId');
      _downloadManager.pauseDownload(firstFileTaskId);
      // Update Hive status to reflect "paused"
      if (status != null) {
        Hive.box('download_status_box').put('status_$audiobookId', {
          ...status,
          'isPaused': true,
          'isDownloading': false, // Explicitly set isDownloading to false when paused
        });
      }
    } else {
      print('UI: Pause not supported for this type or no task ID: $audiobookId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pause not yet supported for YouTube downloads.')),
        );
      }
    }
  }

  void _resumeDownload(String audiobookId, String? firstFileTaskId) {
    final status = Hive.box('download_status_box').get('status_$audiobookId')
        as Map<dynamic, dynamic>?;
    bool isYouTubeDownload = status?['files']?.any((file) =>
            (file['url'] as String).contains('youtube.com') ||
            (file['url'] as String).contains('youtu.be')) ??
        false;

    if (!isYouTubeDownload && firstFileTaskId != null) {
      print('UI: Resuming direct download for $audiobookId, task $firstFileTaskId');
      _downloadManager.resumeDownload(firstFileTaskId);
      if (status != null) {
        Hive.box('download_status_box').put('status_$audiobookId', {
          ...status,
          'isPaused': false,
          'isDownloading': true,
        });
      }
    } else {
      print('UI: Resume not supported for this type or no task ID: $audiobookId');
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resume not yet supported for YouTube downloads.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Downloads',
          style: GoogleFonts.ubuntu(
            fontSize: 22, // Slightly larger
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Ionicons.folder_open_outline),
            onPressed: _openDownloadFolder,
            tooltip: 'Open Downloads Folder',
          ),
        ],
        elevation: 1, // Subtle elevation
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box('download_status_box').listenable(),
        builder: (context, Box<dynamic> box, _) {
          final allStatuses = box.values
              .whereType<Map<dynamic, dynamic>>() // Ensure we only get maps
              .toList();

          // Sort by a timestamp if available, otherwise by title
          allStatuses.sort((a, b) {
            final DateTime? dateA = a['downloadDate'] != null ? DateTime.tryParse(a['downloadDate']) : null;
            final DateTime? dateB = b['downloadDate'] != null ? DateTime.tryParse(b['downloadDate']) : null;
            if (dateA != null && dateB != null) return dateB.compareTo(dateA); // Newest first
            return (a['audiobookTitle'] as String? ?? "").compareTo(b['audiobookTitle'] as String? ?? "");
          });


          final activeDownloads = allStatuses
              .where((status) => (status['isDownloading'] == true || status['isPaused'] == true) && status['isCompleted'] != true && status['error'] == null)
              .toList();
          final erroredDownloads = allStatuses
              .where((status) => status['error'] != null && status['isCompleted'] != true)
              .toList();
          final completedDownloads = allStatuses
              .where((status) => status['isCompleted'] == true && status['error'] == null)
              .toList();

          if (allStatuses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Ionicons.cloud_offline_outline,
                      size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 20),
                  Text(
                    'No Downloads Yet',
                    style: GoogleFonts.ubuntu(
                      fontSize: 20,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Audiobooks you download will appear here.',
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView( // Changed to ListView for simplicity with sections
            padding: const EdgeInsets.only(bottom: 80), // Space for potential FAB
            children: [
              if (activeDownloads.isNotEmpty) ...[
                _buildSectionHeader('Active Downloads', activeDownloads.length, context, Ionicons.download_outline),
                ...activeDownloads.map((status) {
                  final String audiobookId = status['audiobookId'] as String;
                  final List<String> taskIds = _downloadManager.getTaskIdsForAudiobook(audiobookId);
                  final String? firstFileTaskId = taskIds.isNotEmpty ? taskIds.first : null;
                  bool isYouTubeDownload = status['files']?.any((file) => // A more robust check would be ideal
                      (file['url'] as String).contains('youtube.com') ||
                      (file['url'] as String).contains('youtu.be')) ?? false;

                  return _buildDownloadItem(
                    context,
                    status,
                    onCancel: () => _downloadManager.cancelDownload(audiobookId),
                    onPause: !isYouTubeDownload && firstFileTaskId != null // Conditionally enable
                        ? () => _pauseDownload(audiobookId, firstFileTaskId)
                        : null,
                    onResume: !isYouTubeDownload && firstFileTaskId != null
                        ? () => _resumeDownload(audiobookId, firstFileTaskId)
                        : null,
                  );
                }).toList(),
                const SizedBox(height: 16),
              ],
              if (erroredDownloads.isNotEmpty) ...[
                 _buildSectionHeader('Failed Downloads', erroredDownloads.length, context, Ionicons.warning_outline, headerColor: Colors.red.shade300),
                ...erroredDownloads.map((status) => _buildDownloadItem(
                      context,
                      status,
                      onDelete: () => _handleItemDeletion(
                          context,
                          status['audiobookId'] as String,
                          status['audiobookTitle'] as String),
                      onRetry: () { // Placeholder for retry
                         ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Retry for "${status['audiobookTitle']}" not yet implemented.')),
                        );
                        // To implement retry:
                        // 1. Delete existing status: await Hive.box('download_status_box').delete('status_${status['audiobookId']}');
                        // 2. Call _downloadManager.downloadAudiobook(...) again with original details
                        //    You'd need to fetch/reconstruct the original Audiobook and files list.
                      }
                    )).toList(),
                const SizedBox(height: 16),
              ],
              if (completedDownloads.isNotEmpty) ...[
                _buildSectionHeader('Completed', completedDownloads.length, context, Ionicons.checkmark_circle_outline),
                ...completedDownloads.map((status) => _buildDownloadItem(
                      context,
                      status,
                      onDelete: () => _handleItemDeletion(
                          context,
                          status['audiobookId'] as String,
                          status['audiobookTitle'] as String),
                    )).toList(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, BuildContext context, IconData icon, {Color? headerColor}) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: headerColor ?? (isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700), size: 20),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.ubuntu(
              fontSize: 18,
              fontWeight: FontWeight.w600, // Bolder
              color: headerColor ?? (isDarkMode ? Colors.grey.shade300 : Colors.grey.shade800),
            ),
          ),
          const SizedBox(width: 8),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (headerColor ?? (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300)).withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.grey.shade200 : Colors.grey.shade800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDownloadItem(
    BuildContext context,
    Map<dynamic, dynamic> status, {
    VoidCallback? onCancel,
    VoidCallback? onDelete,
    VoidCallback? onPause,
    VoidCallback? onResume,
    VoidCallback? onRetry,
  }) {
    final String audiobookId = status['audiobookId'] as String;
    final String audiobookTitle = status['audiobookTitle'] as String;
    final bool isDownloading = status['isDownloading'] == true && status['isCompleted'] != true && status['error'] == null && status['isPaused'] != true;
    final bool isPaused = status['isPaused'] == true && status['isCompleted'] != true && status['error'] == null;
    final bool isCompleted = status['isCompleted'] == true && status['error'] == null;
    final String? errorMessage = status['error'] as String?;
    final bool hasError = errorMessage != null;
    final double progress = (status['progress'] as num?)?.toDouble() ?? 0.0;

    final String? downloadDateStr = status['downloadDate'] as String?;
    String formattedDate = '';
    if (downloadDateStr != null) {
      try {
        formattedDate = DateFormat('MMM d, yyyy').format(DateTime.parse(downloadDateStr));
      } catch (_) {}
    }

    // Determine icon and color based on state
    IconData itemIcon;
    Color itemIconColor;
    Color progressColor = Theme.of(context).colorScheme.primary;

    if (isDownloading) {
      itemIcon = Ionicons.arrow_down_circle_outline;
      itemIconColor = Theme.of(context).colorScheme.primary;
    } else if (isPaused) {
      itemIcon = Ionicons.pause_circle_outline;
      itemIconColor = Colors.orange.shade600;
      progressColor = Colors.orange.shade600;
    } else if (isCompleted) {
      itemIcon = Ionicons.checkmark_done_circle_outline;
      itemIconColor = Colors.green.shade600;
    } else if (hasError) {
      itemIcon = Ionicons.alert_circle_outline;
      itemIconColor = Theme.of(context).colorScheme.error;
    } else {
      itemIcon = Ionicons.document_text_outline; // Default for unknown state
      itemIconColor = Colors.grey.shade500;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Reduced margin
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Softer corners
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar( // Using CircleAvatar for a cleaner look
                radius: 24,
                backgroundColor: itemIconColor.withOpacity(0.15),
                child: Icon(itemIcon, color: itemIconColor, size: 26),
              ),
              title: Text(
                audiobookTitle,
                style: GoogleFonts.lato( // Changed font for title
                  fontWeight: FontWeight.w600, // Slightly bolder
                  fontSize: 16,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: (isDownloading || isPaused)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect( // Clip progress bar for rounded corners
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: progressColor.withOpacity(0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                              minHeight: 5, // Thicker progress bar
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            isPaused
                                ? 'Paused at ${(progress * 100).toInt()}%'
                                : '${(progress * 100).toInt()}%',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : hasError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'Error: $errorMessage',
                            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : isCompleted
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                'Downloaded on $formattedDate',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12),
                              ),
                            )
                          : null,
              trailing: _buildTrailingActions(
                context: context,
                status: status,
                isDownloading: isDownloading,
                isPaused: isPaused,
                isCompleted: isCompleted,
                hasError: hasError,
                onCancel: onCancel,
                onDelete: onDelete,
                onPause: onPause,
                onResume: onResume,
                onRetry: onRetry,
                audiobookId: audiobookId, // Pass ID for play action
                audiobookTitle: audiobookTitle, // Pass title for play action
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailingActions({
    required BuildContext context,
    required Map<dynamic, dynamic> status,
    required bool isDownloading,
    required bool isPaused,
    required bool isCompleted,
    required bool hasError,
    VoidCallback? onCancel,
    VoidCallback? onDelete,
    VoidCallback? onPause,
    VoidCallback? onResume,
    VoidCallback? onRetry,
    required String audiobookId,
    required String audiobookTitle,
  }) {
    List<Widget> actions = [];

    if (isDownloading && onPause != null) {
      actions.add(IconButton(
          icon: const Icon(Ionicons.pause_outline),
          tooltip: 'Pause',
          onPressed: onPause,
          color: Colors.orange.shade700));
    }
    if (isPaused && onResume != null) {
      actions.add(IconButton(
          icon: const Icon(Ionicons.play_outline),
          tooltip: 'Resume',
          onPressed: onResume,
          color: Colors.green.shade700));
    }
    if ((isDownloading || isPaused) && onCancel != null) {
      actions.add(IconButton(
          icon: const Icon(Ionicons.close_circle_outline),
          tooltip: 'Cancel',
          onPressed: onCancel,
          color: Theme.of(context).colorScheme.error));
    }

    if (isCompleted) {
      actions.add(IconButton(
          icon: const Icon(Ionicons.play_circle_outline),
          tooltip: 'Play',
          color: Theme.of(context).colorScheme.primary,
          onPressed: () async {
             try {
                // --- Robust Audiobook Data Retrieval for Playback ---
                // Option 1: Read from dedicated metadata file (created by DownloadButton)
                final appDir = await getExternalStorageDirectory();
                final metadataFilePath = '${appDir?.path}/downloads/$audiobookId/audiobook_metadata.json'; // Standardize filename
                final metadataFile = File(metadataFilePath);
                Audiobook? audiobook;

                if (await metadataFile.exists()) {
                  final content = await metadataFile.readAsString();
                  audiobook = Audiobook.fromMap(jsonDecode(content) as Map<String, dynamic>);
                } else {
                  // Fallback: Try to get from the deprecated audiobook.txt or construct minimally
                  final oldMetadataFile = File('${appDir?.path}/downloads/$audiobookId/audiobook.txt');
                  if (await oldMetadataFile.exists()) {
                     final content = await oldMetadataFile.readAsString();
                     audiobook = Audiobook.fromMap(jsonDecode(content) as Map<String, dynamic>);
                  } else {
                     print("Warning: Metadata file not found for $audiobookId. Playing with minimal data.");
                     // Construct a minimal object if all else fails
                     audiobook = Audiobook.fromMap({ // Ensure Audiobook.fromMap handles missing fields gracefully
                        'id': audiobookId,
                        'title': audiobookTitle,
                        'origin': 'download', // Mark as downloaded
                        // You MUST ensure Audiobook can be constructed with minimal data for details page
                     });
                  }
                }
                // --- End of Retrieval ---

                print('Playing downloaded audiobook: ${audiobook.title}');
                context.push(
                  '/audiobook-details', // Ensure this route exists
                  extra: {
                    'audiobook': audiobook,
                    'isDownload': true,
                    'isYoutube': false,
                    'isLocal': false,
                  },
                );
              } catch (e) {
                print('Error preparing to play audiobook $audiobookId: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error playing: ${e.toString()}')),
                  );
                }
              }
          }));
    }

    if ((isCompleted || hasError) && onDelete != null) {
      actions.add(IconButton(
          icon: const Icon(Ionicons.trash_outline),
          tooltip: 'Delete',
          onPressed: onDelete,
          color: Theme.of(context).colorScheme.error));
    }
     if (hasError && onRetry != null) {
      actions.add(IconButton(
          icon: const Icon(Ionicons.refresh_outline),
          tooltip: 'Retry',
          onPressed: onRetry,
          color: Colors.blueAccent));
    }


    if (actions.isEmpty) return const SizedBox(width: 48); // Keep layout consistent

    return Row(mainAxisSize: MainAxisSize.min, children: actions);
  }
}