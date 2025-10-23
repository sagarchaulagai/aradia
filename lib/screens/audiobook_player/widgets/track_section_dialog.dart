import 'package:aradia/resources/designs/theme_notifier.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

class TrackSelectionDialog extends StatefulWidget {
  final MyAudioHandler audioHandler;

  const TrackSelectionDialog({
    super.key,
    required this.audioHandler,
  });

  @override
  State<TrackSelectionDialog> createState() => _TrackSelectionDialogState();
}

class _TrackSelectionDialogState extends State<TrackSelectionDialog> {
  bool _showPosition = true;
  late List<Duration> _cumulativePositions;
  late ThemeNotifier themeNotifier;
  late Box<dynamic> playingAudiobookDetailsBox;
  List<AudiobookFile> _audiobookFiles = [];
  int _currentTrackIndex = 0;

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);
    _loadCurrentData();
  }

  Duration _effectiveLength(int index) {
    final f = _audiobookFiles[index];
    if (f.durationMs != null) return Duration(milliseconds: f.durationMs!);
    if (f.length != null) return Duration(seconds: f.length!.toInt());
    // if last resort and we have the next chapter’s start, infer by diff
    if (f.startMs != null && index + 1 < _audiobookFiles.length) {
      final next = _audiobookFiles[index + 1];
      if (next.startMs != null) {
        final diffMs = next.startMs! - f.startMs!;
        if (diffMs > 0) return Duration(milliseconds: diffMs);
      }
    }
    return Duration.zero;
  }

  void _loadCurrentData() {
    // Get current audiobook files from Hive
    final audiobookFilesData =
        playingAudiobookDetailsBox.get('audiobookFiles') as List?;
    if (audiobookFilesData != null) {
      _audiobookFiles = audiobookFilesData
          .map((fileData) => AudiobookFile.fromMap(fileData))
          .toList();
    }

    // Get current track index from audio handler
    _currentTrackIndex = widget.audioHandler.queue.value.indexWhere(
      (item) => item.id == widget.audioHandler.mediaItem.value?.id,
    );
    if (_currentTrackIndex == -1) _currentTrackIndex = 0;

    _calculateCumulativePositions();
  }

  void _calculateCumulativePositions() {
    _cumulativePositions = [];
    Duration running = Duration.zero;

    for (int i = 0; i < _audiobookFiles.length; i++) {
      final f = _audiobookFiles[i];

      // Prefer explicit chapter start if present (single-file m4b chapters)
      if (f.startMs != null) {
        final start = Duration(milliseconds: f.startMs!);
        _cumulativePositions.add(start);
        // advance running as well so later tracks without startMs still look sane
        running = start + _effectiveLength(i);
      } else {
        // multi-file fallback: use running total of file lengths
        _cumulativePositions.add(running);
        running += _effectiveLength(i);
      }
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _getTrackDurationText(int index) {
    if (index >= _audiobookFiles.length) return '';

    if (_showPosition) {
      final position = (index < _cumulativePositions.length)
          ? _cumulativePositions[index]
          : Duration.zero;
      return _formatDuration(position);
    } else {
      // show the chapter/file length
      final len = _effectiveLength(index);
      return _formatDuration(len);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MediaItem>>(
      stream: widget.audioHandler.queue,
      builder: (context, queueSnapshot) {
        // Reload data when queue changes
        if (queueSnapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadCurrentData();
          });
        }

        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeNotifier.themeMode == ThemeMode.dark
                        ? Colors.black.withValues(alpha: 0.1)
                        : Colors.grey[100],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.queue_music, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Chapters',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Toggle button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildToggleButton('Position', true),
                            _buildToggleButton('Length', false),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Track list
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _audiobookFiles.length,
                    itemBuilder: (context, index) {
                      final isCurrentTrack = index == _currentTrackIndex;

                      return Container(
                        decoration: BoxDecoration(
                          color: isCurrentTrack ? Colors.deepOrange[50] : null,
                          border: isCurrentTrack
                              ? Border(
                                  left: BorderSide(
                                      color: Colors.deepOrange, width: 4))
                              : null,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCurrentTrack
                                ? Colors.deepOrange
                                : Colors.grey[300],
                            child: Icon(
                              isCurrentTrack
                                  ? Icons.play_arrow
                                  : Icons.music_note,
                              color: isCurrentTrack
                                  ? Colors.white
                                  : Colors.grey[600],
                            ),
                          ),
                          title: Text(
                            _audiobookFiles[index].title ??
                                'Track ${_audiobookFiles[index].track ?? (index + 1)}',
                            style: TextStyle(
                              fontWeight: isCurrentTrack
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrentTrack
                                  ? Colors.deepOrange[800]
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            _getTrackDurationText(index),
                            style: TextStyle(
                              color: isCurrentTrack
                                  ? Colors.deepOrange[600]
                                  : Colors.grey[600],
                            ),
                          ),
                          trailing: isCurrentTrack
                              ? const Icon(Icons.check_circle,
                                  color: Colors.deepOrange)
                              : null,
                          onTap: () {
                            if (index != _currentTrackIndex) {
                              widget.audioHandler.skipToQueueItem(index);
                            }
                            Navigator.of(context).pop();
                          },
                        ),
                      );
                    },
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeNotifier.themeMode == ThemeMode.dark
                        ? Colors.black.withValues(alpha: 0.1)
                        : Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_audiobookFiles.length} tracks',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToggleButton(String label, bool isPosition) {
    final isSelected = _showPosition == isPosition;

    return GestureDetector(
      onTap: () {
        setState(() {
          _showPosition = isPosition;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.deepOrange : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
