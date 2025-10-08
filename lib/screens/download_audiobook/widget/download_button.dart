import 'dart:convert';
import 'dart:io';

import 'package:aradia/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ionicons/ionicons.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/download/download_manager.dart';
import 'package:aradia/utils/permission_helper.dart';

class DownloadButton extends StatefulWidget {
  final Audiobook audiobook;
  final List<AudiobookFile> audiobookFiles;

  const DownloadButton({
    super.key,
    required this.audiobook,
    required this.audiobookFiles,
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  final DownloadManager _downloadManager = DownloadManager();
  double _progress = 0;
  bool _isDownloading = false;
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  void _loadInitialState() {
    _progress = _downloadManager.getProgress(widget.audiobook.id);
    _isDownloading = _downloadManager.isDownloading(widget.audiobook.id);
    _isDownloaded = _downloadManager.isDownloaded(widget.audiobook.id);
  }

  Future<void> _handleStoragePermission(BuildContext context) async {
    try {
      final hasPermission =
          await PermissionHelper.handleDownloadPermissionWithDialog(context);
      if (hasPermission) {
        // Permissions granted, start download
        await _startDownload();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startDownload() async {
    if (!mounted) return;

    setState(() {
      _isDownloading = true;
    });

    // Convert AudiobookFile list to the required map format
    final List<Map<String, dynamic>> files = widget.audiobookFiles
        .map((file) => {
              'title': file.title,
              'url': file.url,
            })
        .toList();

    try {
      // Get the appropriate metadata directory based on Android version
      final downloadManager = DownloadManager();
      final metadataDir = await downloadManager.getMetadataDirectory(widget.audiobook.id);
      
      // Now create a file name audiobook.txt and save the audiobook details
      final audiobookFile = File('${metadataDir.path}/audiobook.txt');
      // Create a modified copy of the audiobook with origin set to 'download'
      final modifiedAudiobook =
          Map<String, dynamic>.from(widget.audiobook.toMap())
            ..['origin'] = 'download';
      await audiobookFile.writeAsString(jsonEncode(modifiedAudiobook));

      // Now create a file name files.txt and save the audiobook files
      final filesFile = File('${metadataDir.path}/files.txt');
      await filesFile.writeAsString(
        jsonEncode(files),
      );

      await _downloadManager.downloadAudiobook(
        widget.audiobook.id,
        widget.audiobook.title,
        files,
        (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
        (completed) {
          if (!mounted) return;

          setState(() {
            _isDownloading = false;
            _isDownloaded = completed;
          });

          if (completed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Download completed: ${widget.audiobook.title}'),
              ),
            );
          }
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDownloading = false;
      });

      AppLogger.debug(e.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloaded) {
      return IconButton(
        onPressed: () => context.push('/download'), // Add navigation
        icon: const Icon(
          Ionicons.cloud_done,
          size: 50,
          color: Colors.white,
        ),
      );
    } else if (_isDownloading) {
      return GestureDetector(
        onTap: () => context.push('/download'),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                value: _progress,
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            Text(
              '${(_progress * 100).toInt()}%',
              style: GoogleFonts.ubuntu(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return IconButton(
      onPressed: () => _handleStoragePermission(context),
      icon: const Icon(
        Ionicons.cloud_download,
        size: 50,
        color: Colors.white,
      ),
    );
  }
}
