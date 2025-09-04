import 'dart:async';
import 'dart:io';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/utils/optimized_timer.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';
import 'widgets/controls.dart';
import 'widgets/progress_bar_widget.dart';

class AudiobookPlayer extends StatefulWidget {
  const AudiobookPlayer({super.key});

  @override
  State<AudiobookPlayer> createState() => _AudiobookPlayerState();
}

class _AudiobookPlayerState extends State<AudiobookPlayer> {
  late AudioHandlerProvider audioHandlerProvider;
  late Box<dynamic> playingAudiobookDetailsBox;
  late Audiobook audiobook;
  late List<AudiobookFile> audiobookFiles = [];

  // variables for timer and skip silence
  final bool _skipSilence = false;
  late final OptimizedTimer _sleepTimer;
  StreamSubscription<PositionData>? _positionSubscription;
  bool _isEndOfTrackTimerActive = false;

  // ValueNotifier for skip silence to prevent unnecessary rebuilds
  final ValueNotifier<bool> _skipSilenceNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    _sleepTimer = OptimizedTimer();
  }

  @override
  void dispose() {
    // Clean up timer and ValueNotifiers
    _sleepTimer.dispose();
    _skipSilenceNotifier.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    audiobook = Audiobook.fromMap(playingAudiobookDetailsBox.get('audiobook'));

    // Optimize list building
    final audiobookFilesData =
        playingAudiobookDetailsBox.get('audiobookFiles') as List;
    audiobookFiles = audiobookFilesData
        .map((fileData) => AudiobookFile.fromMap(fileData))
        .toList();

    audioHandlerProvider = Provider.of<AudioHandlerProvider>(context);
    int index = playingAudiobookDetailsBox.get('index');
    int position = playingAudiobookDetailsBox.get('position');
    audioHandlerProvider.audioHandler
        .initSongs(audiobookFiles, audiobook, index, position);

    // Initialize skip silence state
    _skipSilenceNotifier.value = _skipSilence;

    if (kDebugMode) {
      AppLogger.debug('audiobookFiles: ${audiobookFiles.length}');
      if (audiobookFiles.isNotEmpty) {
        AppLogger.debug('audiobookFiles: ${audiobookFiles[0].highQCoverImage}');
      }
    }
  }

  Future<void> startTimer(Duration duration) async {
    // Check if this is an end-of-track timer
    if (duration == TimerDurations.endOfTrack) {
      _startEndOfTrackTimer();
      return;
    }

    // Enable background execution for regular timers
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Audiobook Timer Running",
      notificationText: "The timer will pause playback when it expires.",
      notificationImportance: AndroidNotificationImportance.max,
    );

    final result =
        await FlutterBackground.initialize(androidConfig: androidConfig);
    if (result) {
      await FlutterBackground.enableBackgroundExecution();

      // Use the optimized timer with callbacks
      _sleepTimer.start(
        duration: duration,
        onExpired: () {
          audioHandlerProvider.audioHandler.pause();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Timer expired! Audiobook paused.')),
            );
          }
          FlutterBackground.disableBackgroundExecution();
        },
      );
    }
  }

  void _startEndOfTrackTimer() {
    _isEndOfTrackTimerActive = true;
    Duration? lastKnownDuration;
    Duration? lastKnownPosition;

    // Listen to the audio handler's position stream for real-time updates
    _positionSubscription = audioHandlerProvider.audioHandler
        .getPositionStream()
        .listen((positionData) {
      if (_isEndOfTrackTimerActive && positionData.duration > Duration.zero) {
        // Only update timer if there's a significant change in position or duration
        final positionChanged = lastKnownPosition == null ||
            (positionData.position - lastKnownPosition!).abs() >
                const Duration(seconds: 2);
        final durationChanged = lastKnownDuration != positionData.duration;

        if (positionChanged || durationChanged) {
          lastKnownPosition = positionData.position;
          lastKnownDuration = positionData.duration;

          // Calculate remaining time in current track
          final remainingTime = positionData.duration - positionData.position;

          if (remainingTime > Duration.zero) {
            // Restart timer with updated remaining time
            _sleepTimer.start(
              duration: remainingTime,
              onExpired: () {
                audioHandlerProvider.audioHandler.pause();
                _isEndOfTrackTimerActive = false;
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Track ended! Audiobook paused.')),
                  );
                }
              },
            );
          }
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Timer set to pause at end of current track.')),
      );
    }
  }

  void cancelTimer() {
    _sleepTimer.cancel();
    _isEndOfTrackTimerActive = false;
    _positionSubscription?.cancel();
    FlutterBackground.disableBackgroundExecution();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sleep timer canceled.')),
    );
  }

  void showTimerOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Set a Sleep Timer",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _timerButton(context, "15 min", TimerDurations.fifteenMinutes),
                _timerButton(context, "30 min", TimerDurations.thirtyMinutes),
                _timerButton(
                    context, "45 min", TimerDurations.fortyFiveMinutes),
                _timerButton(context, "60 min", TimerDurations.oneHour),
                _timerButton(context, "90 min", TimerDurations.ninetyMinutes),
                _endOfTrackTimerButton(context),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  ElevatedButton _timerButton(
      BuildContext context, String label, Duration duration) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[200],
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      onPressed: () {
        startTimer(duration);
        Navigator.pop(context);
      },
      child: Text(label),
    );
  }

  ElevatedButton _endOfTrackTimerButton(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange[200],
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      onPressed: () {
        startTimer(TimerDurations.endOfTrack);
        Navigator.pop(context);
      },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.skip_next, size: 16),
          SizedBox(width: 4),
          Text('End of Track'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandlerProvider.audioHandler.mediaItem,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return Container();
        }
        MediaItem mediaItem = snapshot.data!;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.grey[850],
            foregroundColor: Colors.white,
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (mediaItem.artUri.toString().contains('storage/emulated'))
                  Image.file(
                    File(mediaItem.artUri.toString()),
                    fit: BoxFit.cover,
                    height: 50,
                    width: 50,
                  )
                else
                  CachedNetworkImage(
                    imageUrl: mediaItem.artUri.toString(),
                    fit: BoxFit.cover,
                    height: 50,
                    width: 50,
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                    placeholder: (context, url) => CachedNetworkImage(
                      imageUrl: audiobook.lowQCoverImage,
                      fit: BoxFit.cover,
                      height: 50,
                      width: 50,
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error),
                    ),
                  ),
                const SizedBox(
                  width: 10,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width - 150,
                      child: Text(
                        mediaItem.title,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: MediaQuery.of(context).size.width - 150,
                      child: Text(
                        mediaItem.artist ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
            actions: [
              IconButton(
                onPressed: () {
                  Provider.of<WeSlideController>(context, listen: false).hide();
                },
                icon: const Icon(Icons.expand_more, color: Colors.white),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Hero(
                  tag: 'audiobook_cover',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black.withValues(alpha: 0.5)
                              : Colors.grey.withValues(alpha: 0.5),
                          spreadRadius: 3,
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: mediaItem.artUri
                              .toString()
                              .contains('storage/emulated')
                          ? Image.file(
                              File(mediaItem.artUri.toString()),
                              fit: BoxFit.cover,
                              height: 250,
                              width: 250,
                            )
                          : CachedNetworkImage(
                              imageUrl: mediaItem.artUri.toString(),
                              fit: BoxFit.cover,
                              height: 250,
                              width: 250,
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                              placeholder: (context, url) => CachedNetworkImage(
                                imageUrl: audiobook.lowQCoverImage,
                                fit: BoxFit.cover,
                                height: 250,
                                width: 250,
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                  Icons.error,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  mediaItem.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  mediaItem.album ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[800]
                        : Colors.grey[300],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  mediaItem.artist ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[600]
                        : Colors.grey[200],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                ProgressBarWidget(
                  audioHandler: audioHandlerProvider.audioHandler,
                ),
                const SizedBox(height: 20),
                // Highly optimized Controls with nested ValueListenableBuilders
                ValueListenableBuilder<bool>(
                  valueListenable: _sleepTimer.isActive,
                  builder: (context, isTimerActive, child) {
                    return ValueListenableBuilder<Duration?>(
                      valueListenable: _sleepTimer.remainingTime,
                      builder: (context, activeTimerDuration, child) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _skipSilenceNotifier,
                          builder: (context, skipSilence, child) {
                            return Controls(
                              audioHandler: audioHandlerProvider.audioHandler,
                              onTimerPressed: showTimerOptions,
                              isTimerActive: isTimerActive,
                              activeTimerDuration: activeTimerDuration,
                              onCancelTimer: cancelTimer,
                              onToggleSkipSilence: () {
                                final newValue = !_skipSilenceNotifier.value;
                                _skipSilenceNotifier.value = newValue;
                                audioHandlerProvider.audioHandler
                                    .setSkipSilence(newValue);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 1),
                                    content: Text(
                                      newValue
                                          ? 'Skip Silence Enabled'
                                          : 'Skip Silence Disabled',
                                    ),
                                  ),
                                );
                              },
                              skipSilence: skipSilence,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
