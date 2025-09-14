// lib/resources/services/my_audio_handler.dart
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
import 'package:rxdart/rxdart.dart';
import 'package:rxdart_ext/utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class MyAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  ConcatenatingAudioSource? _playlist;
  ConcatenatingAudioSource? get playlist => _playlist;

  Box<dynamic> playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');

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

  // Subscriptions to keep PlaybackState in sync
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<bool>? _playingSub;

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

    // Keep notification/media session state in lock-step with the real player
    _bindStatePipelines();
  }

  void _bindStatePipelines() {
    _eventSub?.cancel();
    _playerStateSub?.cancel();
    _playingSub?.cancel();

    // 1) Playback events (buffering, ready, completed, index, position updates)
    _eventSub = _player.playbackEventStream.listen(_broadcastState);

    // 2) PlayerState (processing + playing bool changes)
    _playerStateSub = _player.playerStateStream.listen((_) {
      _broadcastState(_player.playbackEvent);
    });

    // 3) Explicit playing changes (extra belt-and-suspenders for Android)
    _playingSub = _player.playingStream.listen((_) {
      _broadcastState(_player.playbackEvent);
    });
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

      // Build MediaItems & Sources
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
            // Helpful for debugging
            'startMs': song.startMs,
            'durationMs': song.durationMs,
          },
        );
        mediaItems.add(item);

        if (isYouTube && song.url != null) {
          final videoId = VideoId.parseVideoId(song.url!) ?? song.url!;
          sources.add(YouTubeAudioSource(videoId: videoId, tag: item, quality: 'high'));
        } else if (song.url != null) {
          final uri = song.url!.startsWith('/') ? Uri.file(song.url!) : Uri.parse(song.url!);

          // If this "file" is actually a chapter slice, clip it
          if ((song.startMs ?? 0) > 0 || (song.durationMs ?? 0) > 0) {
            final start = Duration(milliseconds: song.startMs ?? 0);
            final end = (song.durationMs != null)
                ? start + Duration(milliseconds: song.durationMs!)
                : null; // last chapter to EOF
            sources.add(
              ClippingAudioSource(
                start: start,
                end: end,
                child: AudioSource.uri(uri, tag: item),
              ),
            );
          } else {
            sources.add(AudioSource.uri(uri, tag: item));
          }
        }
      }

      if (myGen != _initGen) return;

      final safeIndex = sources.isEmpty ? 0 : initialIndex.clamp(0, sources.length - 1);

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
        initialPosition: currentIsYT ? Duration.zero : Duration(milliseconds: positionInMilliseconds),
      );

      if (myGen != _initGen) return;

      if (currentIsYT && positionInMilliseconds > 0) {
        await _waitForProcessingReady(timeout: const Duration(seconds: 5));
        await _player.seek(Duration(milliseconds: positionInMilliseconds), index: safeIndex);
      } else {
        await _player.seek(Duration(milliseconds: positionInMilliseconds), index: safeIndex);
      }

      // Auto-advance on completed
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

      // Broadcast once after init settles (ensures controls show immediately)
      _broadcastState(_player.playbackEvent);
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
      final posOk = (_player.position.inMilliseconds - positionMs).abs() <= posEpsMs;

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
    if (liveMs >= 0) {
      historyOfAudiobook.updateAudiobookPosition(audiobookId, index, liveMs);
      playingAudiobookDetailsBox.put('position', liveMs);
      _lastPersistAt = now;
      AppLogger.debug('Position updated: $liveMs ms');
    }
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processing = _player.processingState;
    final audioProcessing = const {
      ProcessingState.idle: AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[processing]!;

    // Controls shown in quick settings / notification
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.stop,
      MediaControl.skipToNext,
    ];

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
        },
        processingState: audioProcessing,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ),
    );
  }

  void _startPositionUpdateTimer(String audiobookId) {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isReinitializing || !_canPersistProgress) return;
      if (audiobookId != _activeAudiobookId) return;
      if (!_player.playing) return;

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

      final audiobook = Audiobook.fromMap(Map<String, dynamic>.from(storedAudiobookMap));
      final files = (storedFiles as List)
          .map((e) => AudiobookFile.fromMap(Map<String, dynamic>.from(e as Map)))
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

  // ── AudioHandler overrides ────────────────────────────────────────────────
  @override
  Future<void> play() async {
    await _restoreQueueFromBoxIfEmpty(); // only at cold start
    await _player.play();
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    // Opportunistic persist when pausing the active item
    final id = _activeAudiobookId;
    final idx = _player.currentIndex;
    if (_canPersistProgress && !_isReinitializing && id != null && idx != null) {
      _persistNow(id, idx);
    }
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> stop() async {
    _positionUpdateTimer?.cancel();
    await _player.stop();
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player.seek(Duration.zero, index: index);
    await play();
  }

  @override
  Future<void> skipToNext() async {
    await _player.seekToNext();
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> skipToPrevious() async {
    await _player.seekToPrevious();
    _broadcastState(_player.playbackEvent);
  }

  // Map Android's seekForward/seekBackward to fast-forward/rewind
  static const _ffAmount = Duration(seconds: 15);
  static const _rwAmount = Duration(seconds: 10);

  @override
  Future<void> fastForward() async {
    final newPos = _player.position + _ffAmount;
    await _player.seek(newPos);
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> rewind() async {
    final newPos = _player.position - _rwAmount;
    await _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _broadcastState(_player.playbackEvent);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  Future<void> setSkipSilence(bool skipSilence) async {
    await _player.setSkipSilenceEnabled(skipSilence);
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
    if (_player.currentIndex != null && length > 0 && _player.currentIndex! < length - 1) {
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
