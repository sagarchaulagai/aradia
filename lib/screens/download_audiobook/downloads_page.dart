import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/services/download/download_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({
    super.key,
  });

  Future<void> _openDownloadFolder() async {
    // TODO
  }

  Future<void> _deleteDownload(
      BuildContext context, String audiobookId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Download'),
        content: Text('Are you sure you want to delete "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final appDir = await getExternalStorageDirectory();
        final downloadDir = Directory('${appDir?.path}/$audiobookId');
        print('we are deleting $downloadDir');
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
        await Hive.box('download_status_box').delete('status_$audiobookId');
      } catch (e) {
        print('Error deleting download: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Downloads',
          style: GoogleFonts.ubuntu(
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openDownloadFolder,
            tooltip: 'Open Downloads Folder',
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box('download_status_box').listenable(),
        builder: (context, Box<dynamic> box, _) {
          if (box.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No downloads yet',
                    style: GoogleFonts.ubuntu(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          final activeDownloads = box.values
              .where((status) => status['isDownloading'] == true)
              .toList();
          final completedDownloads = box.values
              .where((status) => status['isCompleted'] == true)
              .toList();

          return CustomScrollView(
            slivers: [
              if (activeDownloads.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildSectionHeader(
                      'Active Downloads', activeDownloads.length, context),
                ),
              SliverList(
                delegate: SliverChildListDelegate(
                  activeDownloads
                      .map((status) => _buildDownloadItem(
                            context,
                            status,
                            onCancel: () async {
                              print(
                                  'we are cancelling ${status['audiobookId']}');
                              await Hive.box('download_status_box')
                                  .delete('status_${status['audiobookId']}');
                              DownloadManager()
                                  .cancelDownload(status['audiobookId']);
                            },
                          ))
                      .toList(),
                ),
              ),
              if (completedDownloads.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Completed Downloads',
                      completedDownloads.length, context),
                ),
              SliverList(
                delegate: SliverChildListDelegate(
                  completedDownloads
                      .map((status) => _buildDownloadItem(
                            context,
                            status,
                            onDelete: () => _deleteDownload(
                              context,
                              status['audiobookId'],
                              status['audiobookTitle'],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count, BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).brightness == Brightness.light
          ? Colors.grey[100]
          : Colors.grey[900],
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.ubuntu(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.grey[800]
                  : Colors.grey[300],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
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
  }) {
    final bool isDownloading = status['isDownloading'] == true;
    final double progress = status['progress'] ?? 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isDownloading ? Icons.downloading : Icons.headphones,
                color: isDownloading ? Colors.blue : Colors.grey[800],
              ),
            ),
            title: Text(
              status['audiobookTitle'],
              style: GoogleFonts.ubuntu(
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDownloading) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[200],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(progress * 100).toInt()}% completed',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDownloading)
                  IconButton(
                    icon: const Icon(
                      Icons.cancel,
                      color: Colors.red,
                    ),
                    onPressed: onCancel,
                    tooltip: 'Cancel Download',
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () async {
                      try {
                        final appDir = await getExternalStorageDirectory();
                        final downloadDir = Directory(
                            '${appDir?.path}/${status['audiobookId']}');
                        final audiobookFile =
                            File('${downloadDir.path}/audiobook.txt');

                        if (!await audiobookFile.exists()) {
                          print('Audiobook file does not exist');
                          return;
                        }

                        // Read the file content
                        final String fullContent =
                            await audiobookFile.readAsString();

                        // Parse the JSON content
                        try {
                          final audiobookData =
                              jsonDecode(fullContent) as Map<String, dynamic>;
                          Audiobook audiobook =
                              Audiobook.fromMap(audiobookData);

                          // Navigate to audiobook details
                          print(
                              'Audiobook object is parsed and navigating to details');
                          context.push(
                            '/audiobook/true',
                            extra: audiobook,
                          );
                        } catch (parseError) {
                          print('Error parsing audiobook JSON: $parseError');
                          print('Raw content: $fullContent');
                        }
                      } catch (e) {
                        print('Unexpected error: $e');
                      }
                    },
                    tooltip: 'Play',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete,
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
          ),
          if (!isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Downloaded on ${DateFormat('MMM d, yyyy').format(DateTime.now())}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
