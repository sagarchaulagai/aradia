import 'dart:async';
import 'dart:io';

import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/models/history_of_audiobook.dart';
import 'package:aradia/resources/services/youtube_audio_service.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart_ext/utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class MyAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  ConcatenatingAudioSource? _playlist;
  ConcatenatingAudioSource? get playlist => _playlist;

  Box<dynamic> playingAudiobookDetailsBox =
  Hive.box('playing_audiobook_details_box');

  final HistoryOfAudiobook historyOfAudiobook = HistoryOfAudiobook();
  Timer? _positionUpdateTimer;

  bool _sessionConfigured = false;
  bool _isReinitializing = false;
  int _initGen = 0;

  // Write barrier + context about the current audiobook
  bool _canPersistProgress = false;
  String? _activeAudiobookId;
  int _targetStartMs = 0;
  int _targetStartIndex = 0;

  // Debounce MRU/position writes so UIs don’t “flap”
  DateTime _lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _persistInterval = Duration(seconds: 12);

  Future<void> _ensureAudioSession() async {
    if (_sessionConfigured) return;

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    if (Platform.isAndroid) {
      await _player.setAndroidAudioAttributes(
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      );
    }

    // Pause if headphones unplugged
    session.becomingNoisyEventStream.listen((_) {
      if (_player.playing) _player.pause();
    });

    _sessionConfigured = true;
  }

  Future<void> initSongs(
      List<AudiobookFile> files,
      Audiobook audiobook,
      int initialIndex,
      int positionInMilliseconds,
      ) async {
    _isReinitializing = true;
    final myGen = ++_initGen;

    try {
      await _ensureAudioSession();

      // Disable persistence until the new queue is fully settled
      _canPersistProgress = false;
      _activeAudiobookId = audiobook.id;
      _targetStartMs = positionInMilliseconds;
      _targetStartIndex = initialIndex;

      // Keep the "now playing" box in sync up front
      await playingAudiobookDetailsBox.put('audiobook', audiobook.toMap());
      await playingAudiobookDetailsBox.put(
        'audiobookFiles',
        files.map((f) => f.toMap()).toList(),
      );
      await playingAudiobookDetailsBox.put('index', initialIndex);
      await playingAudiobookDetailsBox.put('position', positionInMilliseconds);

      await _player.stop();

      queue.add([]);
      mediaItem.add(null);

      _positionUpdateTimer?.cancel();

      playbackState.add(
        playbackState.value.copyWith(
          controls: const [],
          systemActions: const {},
          processingState: AudioProcessingState.idle,
          playing: false,
          bufferedPosition: Duration.zero,
          speed: 1.0,
          queueIndex: null,
        ),
      );

      // Build MediaItems
      final mediaItems = <MediaItem>[];
      final sources = <AudioSource>[];

      for (final song in files) {
        final isYouTube = song.url?.contains('youtube.com') == true ||
            song.url?.contains('youtu.be') == true;

        final item = MediaItem(
          id: song.track.toString(),
          album: audiobook.title,
          title: song.title ?? '',
          artist: audiobook.author ?? 'Librivox',
          artUri: Uri.parse(
            audiobook.lowQCoverImage.contains("youtube")
                ? audiobook.lowQCoverImage
                : (song.highQCoverImage ?? ''),
          ),
          extras: {
            'url': song.url,
            'audiobook_id': audiobook.id,
            'is_youtube': isYouTube,
          },
        );
        mediaItems.add(item);

        if (isYouTube && song.url != null) {
          final videoId = VideoId.parseVideoId(song.url!) ?? song.url!;
          sources.add(
            YouTubeAudioSource(videoId: videoId, tag: item, quality: 'high'),
          );
        } else if (song.url != null) {
          final uri = song.url!.startsWith('/') ? Uri.file(song.url!) : Uri.parse(song.url!);
          sources.add(AudioSource.uri(uri, tag: item));
        }
      }

      if (myGen != _initGen) return;

      final safeIndex =
      sources.isEmpty ? 0 : initialIndex.clamp(0, sources.length - 1);

      addQueueItems(mediaItems);
      if (mediaItems.isNotEmpty) {
        mediaItem.add(mediaItems[safeIndex]);
      }

      _playlist = ConcatenatingAudioSource(children: sources);

      // For YouTube, some backends ignore the initialPosition until READY.
      final currentIsYT = _isIndexYouTube(safeIndex);

      await _player.setAudioSource(
        _playlist!,
        initialIndex: sources.isEmpty ? 0 : safeIndex,
        // Pass 0 here for YT; we will seek after READY
        initialPosition:
        currentIsYT ? Duration.zero : Duration(milliseconds: positionInMilliseconds),
      );

      if (myGen != _initGen) return;

      if (currentIsYT && positionInMilliseconds > 0) {
        // Wait for READY so seek is honored
        await _waitForProcessingReady(timeout: const Duration(seconds: 5));
        await _player.seek(Duration(milliseconds: positionInMilliseconds), index: safeIndex);
      } else {
        // Idempotent final seek to pin exact start
        await _player.seek(Duration(milliseconds: positionInMilliseconds), index: safeIndex);
      }

      _player.playbackEventStream.listen(_broadcastState);
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          _player.seekToNext();
        }
      });

      // Wait until the player reports our intended start (looser eps for YT)
      await _waitForStartToSettle(
        safeIndex,
        positionInMilliseconds,
        isYouTube: currentIsYT,
        timeout: const Duration(seconds: 3),
      );

      if (myGen != _initGen) return;

      _listenForCurrentSongIndexChanges();

      // Only add to history once, after we have a settled start
      historyOfAudiobook.addToHistory(
        audiobook,
        files,
        safeIndex,
        positionInMilliseconds,
      );

      _startPositionUpdateTimer(audiobook.id);

      _canPersistProgress = true; // lift the barrier
      _lastPersistAt = DateTime.now().subtract(_persistInterval);
    } finally {
      _isReinitializing = false;
    }
  }

  bool _isIndexYouTube(int index) {
    final children = _playlist?.children;
    if (children == null || index < 0 || index >= children.length) return false;
    return children[index] is YouTubeAudioSource;
  }

  Future<void> _waitForProcessingReady({Duration timeout = const Duration(seconds: 5)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_player.processingState == ProcessingState.ready) return;
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _waitForStartToSettle(
      int index,
      int positionMs, {
        required bool isYouTube,
        Duration timeout = const Duration(seconds: 2),
      }) async {
    final deadline = DateTime.now().add(timeout);

    // Tolerances: YT tends to have more jitter/latency
    final posEpsMs = isYouTube ? 2500 : 1200;

    while (DateTime.now().isBefore(deadline)) {
      final idxOk = _player.currentIndex == index;
      final posOk =
          (_player.position.inMilliseconds - positionMs).abs() <= posEpsMs;

      if (idxOk && posOk) return;
      await Future.delayed(const Duration(milliseconds: 60));
    }
    // If we time out, proceed; barrier will be lifted and periodic saves will correct position.
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    queue.add(queue.value..addAll(mediaItems));
  }

  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.listen((index) {
      if (_isReinitializing) return;
      if (index == null) return;

      final playList = queue.value;
      if (index >= playList.length) return;

      final seqState = _player.sequenceState;
      if (seqState == null) return;

      final item = playList[index];
      mediaItem.add(item);
      playingAudiobookDetailsBox.put('index', index);

      // Don’t persist anything until barrier is lifted
      if (!_canPersistProgress) return;

      final audiobookId = item.extras?['audiobook_id'] as String?;
      if (audiobookId == null || audiobookId != _activeAudiobookId) return;
      if (!_player.playing) return; // don’t push MRU while not playing

      _persistNow(audiobookId, index);
    });
  }

  void _persistNow(String audiobookId, int index) {
    final now = DateTime.now();
    if (now.difference(_lastPersistAt) < _persistInterval) return;

    final liveMs = _player.position.inMilliseconds;
    // Only persist if we have a meaningful timestamp
    if (liveMs >= 0) {
      historyOfAudiobook.updateAudiobookPosition(audiobookId, index, liveMs);
      playingAudiobookDetailsBox.put('position', liveMs);
      _lastPersistAt = now;
      AppLogger.debug('Position updated: $liveMs ms');
    }
  }

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        updatePosition: event.updatePosition,
        bufferedPosition:
        Duration(milliseconds: event.bufferedPosition.inMilliseconds),
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  void _startPositionUpdateTimer(String audiobookId) {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      // Don’t persist during re-init or before barrier lift
      if (_isReinitializing || !_canPersistProgress) return;
      if (audiobookId != _activeAudiobookId) return;
      if (!_player.playing) return; // only update MRU while playing

      final currentIndex = _player.currentIndex;
      if (currentIndex != null) {
        _persistNow(audiobookId, currentIndex);
      }
    });
  }

  Stream<PositionData> getPositionStream() {
    return Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      _player.positionStream,
      _player.bufferedPositionStream,
      _player.durationStream,
          (position, bufferedPosition, duration) {
        return PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        );
      },
    );
  }

  // Cold-restore only: rebuild queue from Hive if we have nothing loaded.
  Future<void> _restoreQueueFromBoxIfEmpty() async {
    if (_isReinitializing) return;
    if ((_playlist?.children.isNotEmpty ?? false)) return;

    try {
      final box = playingAudiobookDetailsBox;
      final storedAudiobookMap = box.get('audiobook');
      final storedFiles = box.get('audiobookFiles');
      if (storedAudiobookMap == null || storedFiles == null) return;

      final audiobook =
      Audiobook.fromMap(Map<String, dynamic>.from(storedAudiobookMap));
      final files = (storedFiles as List)
          .map((e) =>
          AudiobookFile.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      final index = (box.get('index') as int?) ?? 0;
      final position = (box.get('position') as int?) ?? 0;

      await initSongs(files, audiobook, index, position);
    } catch (_) {
      // best-effort only
    }
  }

  String? getCurrentAudiobookId() {
    final extras = mediaItem.value?.extras;
    return extras == null ? null : (extras['audiobook_id'] as String?);
  }

  List<AudioSource> getAudioSourcesFromPlaylist() {
    return _playlist?.children ?? const [];
  }

  @override
  Future<void> play() async {
    await _restoreQueueFromBoxIfEmpty(); // only at cold start
    _player.play();
  }

  @override
  Future<void> pause() async {
    _player.pause();
    // Opportunistic persist when pausing the active item
    final id = _activeAudiobookId;
    final idx = _player.currentIndex;
    if (_canPersistProgress && !_isReinitializing && id != null && idx != null) {
      _persistNow(id, idx);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _player.seek(position);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _player.seek(Duration.zero, index: index);
    play();
  }

  @override
  Future<void> skipToNext() async {
    _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    _player.seekToPrevious();
  }

  @override
  Future<void> setSpeed(double speed) async {
    _player.setSpeed(speed);
  }

  Future<void> setVolume(double volume) async {
    _player.setVolume(volume);
  }

  Future<void> setSkipSilence(bool skipSilence) async {
    _player.setSkipSilenceEnabled(skipSilence);
  }

  Duration get position => _player.position;

  void playPrevious() {
    final length = _playlist?.children.length ?? 0;
    if (_player.currentIndex != null && _player.currentIndex! > 0) {
      _player.seekToPrevious();
    } else if (length > 0) {
      _player.seek(Duration.zero, index: 0);
    }
  }

  void playNext() {
    final length = _playlist?.children.length ?? 0;
    if (_player.currentIndex != null &&
        length > 0 &&
        _player.currentIndex! < length - 1) {
      _player.seekToNext();
    }
  }
}

class PositionData {
  const PositionData(this.position, this.bufferedPosition, this.duration);
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
}
