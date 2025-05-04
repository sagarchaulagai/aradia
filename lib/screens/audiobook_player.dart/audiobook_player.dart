import 'dart:async';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/widgets/low_and_high_image.dart';
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
    int position = playingAudiobookDetailsBox.get('position');
    audioHandlerProvider.audioHandler
        .initSongs(audiobookFiles, audiobook, index, position);
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
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  mediaItem.album ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[800]
                        : Colors.grey[300],
                  ),
                ),
                Text(
                  mediaItem.artist ?? 'Unknown',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[600]
                        : Colors.grey[200],
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
    );
  }
}
