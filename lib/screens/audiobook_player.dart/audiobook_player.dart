import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/services/my_audio_handler.dart';
import 'package:aradia/widgets/low_and_high_image.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

import '../../resources/designs/app_colors.dart';
import '../../services/audio_handler_provider.dart';

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

  // variables for timer
  bool _isTimerActive = false;
  bool _skipSilence = false;
  Duration? _activeTimerDuration;

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    audiobook = Audiobook.fromMap(playingAudiobookDetailsBox.get('audiobook'));
    for (int i = 0;
        i < playingAudiobookDetailsBox.get('audiobookFiles').length;
        i++) {
      audiobookFiles.add(AudiobookFile.fromMap(
          playingAudiobookDetailsBox.get('audiobookFiles')[i]));
    }
    audioHandlerProvider = Provider.of<AudioHandlerProvider>(context);
    int index = playingAudiobookDetailsBox.get('index');

    audioHandlerProvider.audioHandler
        .initSongs(audiobookFiles, audiobook, index);
  }

  Future<void> startTimer(Duration duration) async {
    setState(() {
      _isTimerActive = true;
      _activeTimerDuration = duration;
    });

    // Enable background execution
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "Audiobook Timer Running",
      notificationText: "The timer will pause playback when it expires.",
      notificationImportance: AndroidNotificationImportance.max,
    );

    final result =
        await FlutterBackground.initialize(androidConfig: androidConfig);
    if (result) {
      await FlutterBackground.enableBackgroundExecution();

      // Periodically update remaining time
      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_isTimerActive) {
          timer.cancel();
          return;
        }
        setState(() {
          _activeTimerDuration =
              _activeTimerDuration! - const Duration(seconds: 1);
          if (_activeTimerDuration!.inSeconds <= 0) {
            timer.cancel();
            audioHandlerProvider.audioHandler.pause();
            setState(() {
              _isTimerActive = false;
              _activeTimerDuration = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Timer expired! Audiobook paused.')),
            );
            FlutterBackground.disableBackgroundExecution();
          }
        });
      });
    }
  }

  void cancelTimer() {
    setState(() {
      _isTimerActive = false;
      _activeTimerDuration = null;
    });
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
                _timerButton(context, "15 min", const Duration(minutes: 15)),
                _timerButton(context, "30 min", const Duration(minutes: 30)),
                _timerButton(context, "45 min", const Duration(minutes: 45)),
                _timerButton(context, "60 min", const Duration(minutes: 60)),
                _timerButton(context, "90 min", const Duration(minutes: 90)),
                _timerButton(context, "120 min", const Duration(minutes: 120)),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          Provider.of<WeSlideController>(context, listen: false).hide();
        }
      },
      child: StreamBuilder<MediaItem?>(
        stream: audioHandlerProvider.audioHandler.mediaItem,
        builder: (context, snapshot) {
          if (snapshot.data == null) {
            return Container();
          }
          MediaItem mediaItem = snapshot.data!;
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.grey[850],
              foregroundColor: Colors.white,
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  LowAndHighImage(
                    lowQImage: audiobook.lowQCoverImage,
                    highQImage: mediaItem.artUri.toString(),
                    width: 50,
                    height: 50,
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
                    Provider.of<WeSlideController>(context, listen: false)
                        .hide();
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
                            color: Colors.black.withOpacity(0.3),
                            spreadRadius: 3,
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LowAndHighImage(
                          lowQImage: audiobook.lowQCoverImage,
                          highQImage: mediaItem.artUri.toString(),
                          width: 250,
                          height: 250,
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
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    mediaItem.album ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                  ),
                  Text(
                    mediaItem.artist ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ProgressBarWidget(
                    audioHandler: audioHandlerProvider.audioHandler,
                  ),
                  const SizedBox(height: 20),
                  Controls(
                    audioHandler: audioHandlerProvider.audioHandler,
                    onTimerPressed: showTimerOptions,
                    isTimerActive: _isTimerActive,
                    activeTimerDuration: _activeTimerDuration,
                    onCancelTimer: cancelTimer,
                    onToggleSkipSilence: () {
                      setState(() {
                        _skipSilence = !_skipSilence;
                        audioHandlerProvider.audioHandler
                            .setSkipSilence(_skipSilence);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 1),
                            content: Text(
                              _skipSilence
                                  ? 'Skip Silence Enabled'
                                  : 'Skip Silence Disabled',
                            ),
                          ),
                        );
                      });
                    },
                    skipSilence: _skipSilence,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class Controls extends StatefulWidget {
  final MyAudioHandler audioHandler;
  final void Function(BuildContext) onTimerPressed;
  final VoidCallback onCancelTimer;
  final VoidCallback onToggleSkipSilence;
  final bool isTimerActive;
  final Duration? activeTimerDuration;
  final bool skipSilence;

  const Controls({
    super.key,
    required this.audioHandler,
    required this.onTimerPressed,
    required this.isTimerActive,
    required this.activeTimerDuration,
    required this.onCancelTimer,
    required this.onToggleSkipSilence,
    required this.skipSilence,
  });

  @override
  State<Controls> createState() => _ControlsState();
}

class _ControlsState extends State<Controls> {
  double _playbackSpeed = 1.0;
  double _volume = 0.5;

  void _changePlaybackSpeed() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Adjust Playback Speed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Slider(
                activeColor: const Color.fromRGBO(255, 165, 0, 1),
                inactiveColor: Colors.grey[300],
                thumbColor: const Color.fromRGBO(204, 119, 34, 1),
                value: _playbackSpeed,
                min: 0.5,
                max: 2.0,
                divisions: 6,
                label: "${_playbackSpeed.toStringAsFixed(1)}x",
                onChanged: (value) {
                  setModalState(() {
                    _playbackSpeed = value;
                  });
                  setState(() {
                    widget.audioHandler.setSpeed(_playbackSpeed);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _changeVolume() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Adjust Volume',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Slider(
                activeColor: const Color.fromRGBO(255, 165, 0, 1),
                inactiveColor: Colors.grey[300],
                thumbColor: const Color.fromRGBO(204, 119, 34, 1),
                value: _volume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                label: "${(_volume * 100).toInt()}%",
                onChanged: (value) {
                  setModalState(() {
                    _volume = value;
                  });
                  setState(() {
                    widget.audioHandler.setVolume(_volume);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.isTimerActive && widget.activeTimerDuration != null)
          Text(
            "Timer: ${widget.activeTimerDuration!.inMinutes}:${(widget.activeTimerDuration!.inSeconds % 60).toString().padLeft(2, '0')} remaining",
            style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _changePlaybackSpeed,
              icon: const Icon(Ionicons.speedometer),
              tooltip: 'Adjust Playback Speed',
              color: _playbackSpeed != 1.0 ? Colors.deepOrange : Colors.black,
            ),
            IconButton(
              onPressed: _changeVolume,
              icon: const Icon(Ionicons.volume_high),
              tooltip: 'Adjust Volume',
            ),
            IconButton(
              onPressed: widget.onToggleSkipSilence,
              icon: Icon(
                widget.skipSilence ? Ionicons.flash : Ionicons.flash_outline,
                color: widget.skipSilence ? Colors.deepOrange : Colors.black,
              ),
              tooltip:
                  widget.skipSilence ? 'Skip Silence On' : 'Skip Silence Off',
            ),
            IconButton(
              onPressed: widget.isTimerActive
                  ? widget.onCancelTimer
                  : () => widget.onTimerPressed(context),
              icon: Icon(
                widget.isTimerActive ? Ionicons.timer_outline : Ionicons.timer,
                color: widget.isTimerActive ? Colors.deepOrange : Colors.black,
              ),
              tooltip: widget.isTimerActive
                  ? 'Cancel Timer (${widget.activeTimerDuration?.inMinutes} min)'
                  : 'Set Sleep Timer',
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () {
                widget.audioHandler.seek(
                    widget.audioHandler.position - const Duration(seconds: 10));
              },
              icon: const Icon(Icons.replay_10),
              iconSize: 32.0,
              color: Colors.black,
            ),
            IconButton(
              onPressed: () {
                widget.audioHandler.playPrevious();
              },
              icon: const Icon(Icons.skip_previous),
              iconSize: 32.0,
              color: Colors.black,
            ),
            StreamBuilder<PlaybackState>(
              stream: widget.audioHandler.playbackState,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data?.playing ?? false;
                PlaybackState playbackState = snapshot.data!;
                final processingState = playbackState.processingState;
                if (processingState == AudioProcessingState.loading ||
                    processingState == AudioProcessingState.buffering) {
                  return const CircularProgressIndicator(
                    color: AppColors.primaryColor,
                    strokeWidth: 2,
                  );
                }
                return IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.black,
                    size: 40,
                  ),
                  onPressed: () {
                    if (isPlaying) {
                      widget.audioHandler.pause();
                    } else {
                      widget.audioHandler.play();
                    }
                  },
                );
              },
            ),
            IconButton(
              onPressed: () {
                widget.audioHandler.playNext();
              },
              icon: const Icon(Icons.skip_next),
              iconSize: 32.0,
              color: Colors.black,
            ),
            IconButton(
              onPressed: () {
                widget.audioHandler.seek(
                    widget.audioHandler.position + const Duration(seconds: 10));
              },
              icon: const Icon(Icons.forward_10),
              iconSize: 32.0,
              color: Colors.black,
            ),
          ],
        ),
      ],
    );
  }
}

class ProgressBarWidget extends StatelessWidget {
  final MyAudioHandler audioHandler;
  const ProgressBarWidget({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: audioHandler.getPositionStream(),
      builder: (context, snapshot) {
        final positionData = snapshot.data;
        final totalDuration = positionData?.duration ?? Duration.zero;
        final remainingTime =
            totalDuration - (positionData?.position ?? Duration.zero);
        return Column(
          children: [
            ProgressBar(
              progressBarColor: Colors.deepOrange[600],
              thumbColor: Colors.deepOrange[800],
              baseBarColor: Colors.deepOrange[100],
              bufferedBarColor: Colors.deepOrange[200]!,
              progress: positionData?.position ?? Duration.zero,
              buffered: positionData?.bufferedPosition ?? Duration.zero,
              total: totalDuration,
              onSeek: (duration) {
                audioHandler.seek(duration);
              },
            ),
            Text(
              "Time Remaining: ${remainingTime.inMinutes}:${(remainingTime.inSeconds % 60).toString().padLeft(2, '0')}",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        );
      },
    );
  }
}
