import 'dart:async';
import 'dart:io';

import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/designs/theme_notifier.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/resources/services/character_service.dart';
import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:aradia/screens/audiobook_player/widgets/track_section_dialog.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:aradia/utils/optimized_timer.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

import 'widgets/controls.dart';
import 'widgets/equalizer_dialog.dart';
import 'widgets/equalizer_icon.dart';
import 'widgets/progress_bar_widget.dart';
import 'widgets/chromecast_button.dart';

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
  late CharacterService characterService;

  // variables for timer and skip silence
  final bool _skipSilence = false;
  late final OptimizedTimer _sleepTimer;
  StreamSubscription<PositionData>? _positionSubscription;
  bool _isEndOfTrackTimerActive = false;

  // ValueNotifier for skip silence to prevent unnecessary rebuilds
  final ValueNotifier<bool> _skipSilenceNotifier = ValueNotifier<bool>(false);

  // GlobalKey for equalizer icon to refresh it
  final GlobalKey<EqualizerIconState> _equalizerIconKey =
      GlobalKey<EqualizerIconState>();

  @override
  void initState() {
    super.initState();
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');
    _sleepTimer = OptimizedTimer();
    characterService = CharacterService();
    _initializeCharacterService();
  }

  Future<void> _initializeCharacterService() async {
    await characterService.init();
  }

  @override
  void dispose() {
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
    // Do NOT reinitialize here. If the handler is empty (fresh app start),
    // calling play() will cold-restore from Hive via _restoreQueueFromBoxIfEmpty().
    if (audioHandlerProvider.audioHandler
        .getAudioSourcesFromPlaylist()
        .isEmpty) {
      audioHandlerProvider.audioHandler.restoreIfNeeded();
    }

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
      await _startEndOfTrackTimer();
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

  Future<void> _startEndOfTrackTimer() async {
    _isEndOfTrackTimerActive = true;
    Duration? lastKnownDuration;
    Duration? lastKnownPosition;

    // Enable background execution for end-of-track timer too
    const androidConfig = FlutterBackgroundAndroidConfig(
      notificationTitle: "End of Track Timer Running",
      notificationText:
          "The timer will pause playback at the end of current track.",
      notificationImportance: AndroidNotificationImportance.max,
    );

    final result =
        await FlutterBackground.initialize(androidConfig: androidConfig);
    if (result) {
      await FlutterBackground.enableBackgroundExecution();

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
                  FlutterBackground.disableBackgroundExecution();
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
    ThemeNotifier themeNotifier =
        Provider.of<ThemeNotifier>(context, listen: false);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        color: themeNotifier.themeMode == ThemeMode.dark
            ? Colors.grey[800]!
            : Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Set a Sleep Timer",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
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
        backgroundColor: AppColors.primaryColor.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
      onPressed: () async {
        await startTimer(TimerDurations.endOfTrack);
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

  // -------- Artwork helpers (handle local file:// and remote http/https) -----

  Widget _artThumb(Uri? art, {double size = 50}) {
    final isLocal = art != null && art.scheme == 'file';
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: isLocal
            ? Image.file(
                File(art.toFilePath()),
                fit: BoxFit.cover,
              )
            : CachedNetworkImage(
                imageUrl: art?.toString() ?? '',
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white54),
              ),
      ),
    );
  }

  Widget _artLarge(Uri? art, {double size = 250}) {
    final isLocal = art != null && art.scheme == 'file';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: isLocal
          ? Image.file(
              File(art.toFilePath()),
              fit: BoxFit.cover,
              height: size,
              width: size,
            )
          : CachedNetworkImage(
              imageUrl: art?.toString() ?? '',
              fit: BoxFit.cover,
              height: size,
              width: size,
              errorWidget: (_, __, ___) => const Icon(Icons.error),
            ),
    );
  }

  void _showTrackSelectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => TrackSelectionDialog(
        audioHandler: audioHandlerProvider.audioHandler,
      ),
    );
  }

  void _showEqualizerDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => EqualizerDialog(
        audioHandler: audioHandlerProvider.audioHandler,
      ),
    );
    // Refresh the equalizer icon after dialog closes
    _equalizerIconKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandlerProvider.audioHandler.mediaItem,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final MediaItem mediaItem = snapshot.data!;

        // Decide what to show for title/subtitle when there's only one track.
        // We read the same Hive box you already use to persist "now playing".
        final box = playingAudiobookDetailsBox;
        final filesDyn = box.get('audiobookFiles') as List?;
        final isSingleTrack = (filesDyn?.length ?? 0) <= 1;

        // Prefer author from our stored Audiobook; fall back to MediaItem.artist.
        String? authorFromBox;
        final audiobookMap = box.get('audiobook');
        if (audiobookMap != null) {
          authorFromBox = Audiobook.fromMap(
            Map<String, dynamic>.from(audiobookMap as Map),
          ).author;
        }

        // Titles to render in the app bar and in the large title below the cover.
        final headerTitle = isSingleTrack
            ? (mediaItem.album ?? mediaItem.title)
            : mediaItem.title;
        final headerSubtitle = isSingleTrack
            ? (authorFromBox ?? mediaItem.artist ?? 'Unknown')
            : (mediaItem.artist ?? 'Unknown');
        final contentTitle = headerTitle; // keep the big center title in sync

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.grey[850],
            foregroundColor: Colors.white,
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _artThumb(mediaItem.artUri, size: 45),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headerTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          overflow: TextOverflow.ellipsis,
                        ),
                        maxLines: 1,
                      ),
                      Text(
                        headerSubtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          overflow: TextOverflow.ellipsis,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ChromeCastButton(
                    chromeCastService:
                        audioHandlerProvider.audioHandler.chromeCastService,
                  ),
                  IconButton(
                    onPressed: () {
                      _showEqualizerDialog(context);
                    },
                    icon: EqualizerIcon(
                      key: _equalizerIconKey,
                      size: 25,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      _showTrackSelectionDialog(context);
                    },
                    icon: Icon(Icons.list, color: Colors.white, size: 30),
                  ),
                  IconButton(
                    onPressed: () {
                      Provider.of<WeSlideController>(context, listen: false)
                          .hide();
                    },
                    icon: const Icon(Icons.expand_more,
                        color: Colors.white, size: 30),
                  ),
                ],
              ),
            ],
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: Theme.of(context).brightness == Brightness.dark
                    ? [
                        const Color(0xFF1A1A1A),
                        const Color(0xFF0D0D0D),
                      ]
                    : [
                        const Color(0xFFF8F9FA),
                        const Color(0xFFE9ECEF),
                        const Color(0xFFDEE2E6),
                      ],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 30),

                    // Modern cover art with glassmorphism effect
                    Hero(
                      tag: 'audiobook_cover',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.black.withValues(alpha: 0.6)
                                  : Colors.black.withValues(alpha: 0.15),
                              spreadRadius: 0,
                              blurRadius: 30,
                              offset: const Offset(0, 15),
                            ),
                            BoxShadow(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.black.withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.08),
                              spreadRadius: 0,
                              blurRadius: 60,
                              offset: const Offset(0, 30),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: _artLarge(mediaItem.artUri, size: 280),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Modern title section with better typography
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          Text(
                            contentTitle,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.darkTextColor
                                  : AppColors.textColor,
                              height: 1.2,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!isSingleTrack) ...[
                            const SizedBox(height: 8),
                            Text(
                              mediaItem.album ?? 'Unknown',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? AppColors.listTileSubtitleColor
                                    : AppColors.subtitleTextColorLight,
                                height: 1.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            mediaItem.artist ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppColors.listTileSubtitleColor
                                      .withValues(alpha: 0.8)
                                  : AppColors.subtitleTextColorLight,
                              height: 1.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Modern progress bar container
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ProgressBarWidget(
                        audioHandler: audioHandlerProvider.audioHandler,
                      ),
                    ),

                    const SizedBox(height: 40),
                    // Modern controls container with glassmorphism
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.black.withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.1),
                            spreadRadius: 0,
                            blurRadius: 25,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.black.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.05),
                            spreadRadius: 0,
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _sleepTimer.isActive,
                        builder: (context, isTimerActive, child) {
                          return ValueListenableBuilder<Duration?>(
                            valueListenable: _sleepTimer.remainingTime,
                            builder: (context, activeTimerDuration, child) {
                              return ValueListenableBuilder<bool>(
                                valueListenable: _skipSilenceNotifier,
                                builder: (context, skipSilence, child) {
                                  return Controls(
                                    audioHandler:
                                        audioHandlerProvider.audioHandler,
                                    onTimerPressed: showTimerOptions,
                                    isTimerActive: isTimerActive,
                                    activeTimerDuration: activeTimerDuration,
                                    onCancelTimer: cancelTimer,
                                    onToggleSkipSilence: () {
                                      final newValue =
                                          !_skipSilenceNotifier.value;
                                      _skipSilenceNotifier.value = newValue;
                                      audioHandlerProvider.audioHandler
                                          .setSkipSilence(newValue);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
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
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
