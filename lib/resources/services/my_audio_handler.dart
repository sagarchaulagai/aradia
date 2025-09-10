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
  final _playlist = ConcatenatingAudioSource(children: []);
  Box<dynamic> playingAudiobookDetailsBox =
  Hive.box('playing_audiobook_details_box');
  ConcatenatingAudioSource get playlist => _playlist;
  final HistoryOfAudiobook historyOfAudiobook = HistoryOfAudiobook();
  Timer? _positionUpdateTimer;

  bool _sessionConfigured = false;

  // Prevents cold-restore from clobbering a live re-init.
  bool _isReinitializing = false;

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
      List<AudiobookFile> playlist,
      Audiobook audiobook,
      int initialIndex,
      int positionInMilliseconds,
      ) async {
    _isReinitializing = true;
    try {
      await _ensureAudioSession();

      // Keep the "now playing" box in sync with the queue we're about to build.
      await playingAudiobookDetailsBox.put('audiobook', audiobook.toMap());
      await playingAudiobookDetailsBox.put(
        'audiobookFiles',
        playlist.map((f) => f.toMap()).toList(),
      );
      await playingAudiobookDetailsBox.put('index', initialIndex);
      await playingAudiobookDetailsBox.put('position', positionInMilliseconds);

      _playlist.clear();
      queue.add([]);
      mediaItem.add(null);

      // clear timer for previous audiobook
      _positionUpdateTimer?.cancel();

      playbackState.add(
        playbackState.value.copyWith(
          controls: [],
          systemActions: const {},
          processingState: AudioProcessingState.idle,
          playing: false,
          bufferedPosition: Duration.zero,
          speed: 1.0,
          queueIndex: null,
        ),
      );

      final mediaItems = await parseMediaItems(playlist, audiobook);
      addQueueItems(mediaItems);
      _listenForCurrentSongIndexChanges();

      await _player.setAudioSource(
        _playlist,
        initialIndex: initialIndex,
        initialPosition: Duration(milliseconds: positionInMilliseconds),
      );

      _player.playbackEventStream.listen(_broadcastState);
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          _player.seekToNext();
        }
      });

      historyOfAudiobook.addToHistory(
        audiobook,
        playlist,
        initialIndex,
        positionInMilliseconds,
      );
      _startPositionUpdateTimer(audiobook.id);
    } finally {
      _isReinitializing = false;
    }
  }

  Future<List<MediaItem>> parseMediaItems(
      List<AudiobookFile> playlist,
      Audiobook audiobook,
      ) async {
    final mediaItems = <MediaItem>[];

    for (var song in playlist) {
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

      if (isYouTube) {
        final videoId = VideoId.parseVideoId(song.url!) ?? song.url!;
        _playlist.add(
          YouTubeAudioSource(videoId: videoId, tag: item, quality: 'high'),
        );
      } else if (song.url != null) {
        Uri uri;
        if (song.url!.startsWith('/')) {
          uri = Uri.file(song.url!);
        } else {
          uri = Uri.parse(song.url!);
        }
        _playlist.add(AudioSource.uri(uri, tag: item));
      }
    }

    return mediaItems;
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    queue.add(queue.value..addAll(mediaItems));
  }

  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.listen((index) {
      final playList = queue.value;
      if (index != null && index < playList.length) {
        mediaItem.add(playList[index]);
        playingAudiobookDetailsBox.put('index', index);
        final currentMediaItem = playList[index];
        final audiobookId = currentMediaItem.extras!['audiobook_id'];
        historyOfAudiobook.updateAudiobookPosition(
          audiobookId,
          index,
          _player.position.inMilliseconds,
        );
      }
    });
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
      final currentIndex = _player.currentIndex;
      if (currentIndex != null) {
        historyOfAudiobook.updateAudiobookPosition(
          audiobookId,
          currentIndex,
          _player.position.inMilliseconds,
        );
        playingAudiobookDetailsBox.put(
            'position', _player.position.inMilliseconds);
        AppLogger.debug(
          'Position updated: ${_player.position.inMilliseconds} ms',
        );
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
            position, bufferedPosition, duration ?? Duration.zero);
      },
    );
  }

  // Cold-restore only: rebuild queue from Hive if we have nothing loaded.
  Future<void> _restoreQueueFromBoxIfEmpty() async {
    if (_isReinitializing) return;
    if (_playlist.children.isNotEmpty) return;

    try {
      final box = playingAudiobookDetailsBox;
      final storedAudiobookMap = box.get('audiobook');
      final storedFiles = box.get('audiobookFiles');
      if (storedAudiobookMap == null || storedFiles == null) return;

      final audiobook =
      Audiobook.fromMap(Map<String, dynamic>.from(storedAudiobookMap));
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

  String getCurrentAudiobookId() {
    final currentMediaItem = mediaItem.value;
    return currentMediaItem?.extras!['audiobook_id'];
  }

  List<AudioSource> getAudioSourcesFromPlaylist() {
    return _playlist.children;
  }

  @override
  Future<void> play() async {
    await _restoreQueueFromBoxIfEmpty(); // only at cold start
    _player.play();
  }

  @override
  Future<void> pause() async {
    _player.pause();
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
    if (_player.currentIndex != 0) {
      _player.seekToPrevious();
    }
  }

  void playNext() {
    if (_player.currentIndex != _playlist.children.length - 1) {
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
