import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:rxdart_ext/utils.dart';

class MyAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  Box<dynamic> playingAudiobookDetailsBox =
      Hive.box('playing_audiobook_details_box');

  ConcatenatingAudioSource get playlist => _playlist;

  void initSongs(List<AudiobookFile> playlist, Audiobook audiobook,
      int initialIndex) async {
    // we need to clear the playlist before adding new items
    _playlist.clear();
    // also change the queue
    queue.add([]);
    // also change the mediaItem
    mediaItem.add(null);
    // also change the playbackState
    playbackState.add(playbackState.value.copyWith(
      controls: [],
      systemActions: const {},
      processingState: AudioProcessingState.idle,
      playing: false,
      bufferedPosition: Duration.zero,
      speed: 1.0,
      queueIndex: null,
    ));
    // then we can add the new items
    final mediaItems = parseMediaItems(playlist, audiobook);
    addQueueItems(mediaItems);
    _listenForCurrentSongIndexChanges();
    _player.playbackEventStream.listen(_broadcastState);
    await _player.setAudioSource(_playlist, initialIndex: initialIndex);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _player.seekToNext();
      }
    });
  }

  List<MediaItem> parseMediaItems(
    List<AudiobookFile> playlist,
    Audiobook audiobook,
  ) {
    return playlist
        .map(
          (song) => MediaItem(
            id: song.track.toString(),
            album: audiobook.title,
            title: song.title ?? '',
            artist: audiobook.author ?? 'Librivox',
            artUri: Uri.parse(song.highQCoverImage ?? ''),
            extras: {
              'url': song.url,
            },
          ),
        )
        .toList();
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    final audioSource = mediaItems
        .map((item) => AudioSource.uri(Uri.parse(item.extras!['url'])))
        .toList();
    _playlist.addAll(audioSource);

    final newQueue = queue.value..addAll(mediaItems);
    queue.add(newQueue);
  }

  void _listenForCurrentSongIndexChanges() {
    _player.currentIndexStream.listen((index) {
      final playList = queue.value;
      if (index != null && index < playList.length) {
        mediaItem.add(playList[index]);
        playingAudiobookDetailsBox.put('index', index);
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

  // used for rx dart for smooth playback

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

  void dispose() {
    _player.dispose();
  }

  // test
  List<AudioSource> getAudioSourcesFromPlaylist() {
    return _playlist.children;
  }

  @override
  Future<void> play() async {
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

  // get position
  Duration get position => _player.position;

  // play previous queue item if current queue item is not the first one
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
  const PositionData(
    this.position,
    this.bufferedPosition,
    this.duration,
  );
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
}
