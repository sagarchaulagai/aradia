import 'dart:async';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';

class ChromeCastService {
  static final ChromeCastService _instance = ChromeCastService._internal();
  factory ChromeCastService() => _instance;
  ChromeCastService._internal();

  bool _initialized = false;
  StreamSubscription<List<GoogleCastDevice>>? _devicesSubscription;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      const appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
      final options = GoogleCastOptionsAndroid(appId: appId);
      GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      _initialized = true;
      AppLogger.debug('ChromeCast initialized');
    } catch (e) {
      AppLogger.error('ChromeCast init failed: $e');
    }
  }

  void startDiscovery() {
    try {
      GoogleCastDiscoveryManager.instance.startDiscovery();
      AppLogger.debug('ChromeCast device discovery started');

      // Listen for discovered devices (for debugging)
      _devicesSubscription?.cancel();
      _devicesSubscription = devicesStream.listen((devices) {
        for (final device in devices) {
          AppLogger.debug('  - ${device.friendlyName} (${device.modelName})');
        }
      });
    } catch (e) {
      AppLogger.error('Failed to start ChromeCast discovery: $e');
    }
  }

  void stopDiscovery() {
    try {
      GoogleCastDiscoveryManager.instance.stopDiscovery();
      AppLogger.debug('ChromeCast device discovery stopped');
    } catch (e) {
      AppLogger.error('Failed to stop ChromeCast discovery: $e');
    }
  }

  Stream<List<GoogleCastDevice>> get devicesStream =>
      GoogleCastDiscoveryManager.instance.devicesStream;

  Stream<GoogleCastSession?> get sessionStream =>
      GoogleCastSessionManager.instance.currentSessionStream;

  bool get isConnected =>
      GoogleCastSessionManager.instance.connectionState ==
      GoogleCastConnectState.connected;

  Future<void> connectToDevice(GoogleCastDevice device) async {
    try {
      await GoogleCastSessionManager.instance.startSessionWithDevice(device);
      AppLogger.debug('Connected to ${device.friendlyName}');
    } catch (e) {
      AppLogger.error('Failed to connect: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
      AppLogger.debug('Disconnected from ChromeCast');
    } catch (e) {
      AppLogger.error('Failed to disconnect: $e');
    }
  }

  Future<void> loadAudiobook(
    Audiobook audiobook,
    List<AudiobookFile> files,
    int startIndex,
    Duration startPosition,
  ) async {
    if (files.isEmpty) return;

    final items = <GoogleCastQueueItem>[];
    for (final file in files) {
      if (file.url == null) continue;
      items.add(GoogleCastQueueItem(
        mediaInformation: GoogleCastMediaInformationIOS(
          contentId: file.url!,
          streamType: CastMediaStreamType.buffered,
          contentUrl: Uri.parse(file.url!),
          contentType: 'audio/mp3',
          metadata: GoogleCastGenericMediaMetadata(
            title: file.title ?? audiobook.title,
            subtitle: audiobook.author ?? 'Unknown',
            images: audiobook.lowQCoverImage != null
                ? [
                    GoogleCastImage(
                      url: Uri.parse(audiobook.lowQCoverImage!),
                      width: 480,
                      height: 480,
                    ),
                  ]
                : [],
          ),
        ),
      ));
    }

    await GoogleCastRemoteMediaClient.instance.queueLoadItems(
      items,
      options: GoogleCastQueueLoadOptions(
        startIndex: startIndex,
        playPosition: startPosition,
      ),
    );
  }

  Future<void> play() async => GoogleCastRemoteMediaClient.instance.play();
  Future<void> pause() async => GoogleCastRemoteMediaClient.instance.pause();
  Future<void> stop() async => GoogleCastRemoteMediaClient.instance.stop();
  Future<void> seek(Duration position) async =>
      GoogleCastRemoteMediaClient.instance
          .seek(GoogleCastMediaSeekOption(position: position));
  Future<void> skipToNext() async =>
      GoogleCastRemoteMediaClient.instance.queueNextItem();
  Future<void> skipToPrevious() async =>
      GoogleCastRemoteMediaClient.instance.queuePrevItem();

  Stream<GoggleCastMediaStatus?> get mediaStatusStream =>
      GoogleCastRemoteMediaClient.instance.mediaStatusStream;

  Duration get currentPosition =>
      GoogleCastRemoteMediaClient.instance.playerPosition;

  void dispose() {
    _devicesSubscription?.cancel();
    stopDiscovery();
  }
}
