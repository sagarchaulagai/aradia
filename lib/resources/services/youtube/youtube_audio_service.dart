import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
/*
 * This code is based on the implementation from:
 * https://github.com/jhelumcorp/gyawun/blob/main/lib/services/yt_audio_stream.dart
 * 
 * Original implementation by jhelumcorp
 * Modified and adapted for use in this project
 */

class YouTubeAudioSource extends StreamAudioSource {
  final String videoId;
  final String quality; // 'high' or 'low'
  final YoutubeExplode ytExplode;

  YouTubeAudioSource({
    required this.videoId,
    required this.quality,
    super.tag,
  }) : ytExplode = YoutubeExplode();

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    try {
      final manifest = await ytExplode.videos.streams.getManifest(
        videoId,
        requireWatchPage: true,
        ytClients: [YoutubeApiClient.androidVr],
      );

      final supportedStreams = manifest.audioOnly.sortByBitrate();
      final audioStream =
      quality == 'high' ? supportedStreams.firstOrNull : supportedStreams.lastOrNull;

      if (audioStream == null) {
        throw Exception('No audio stream available for this video.');
      }

      // Coerce to non-null ints that respect total size
      int s = start ?? 0;
      int e;
      if (audioStream.isThrottled) {
        // cap chunk size to keep Exo happy on throttled streams
        final cap = 10 * 1024 * 1024; // ~10MB
        e = (end ?? (s + cap));
      } else {
        e = end ?? audioStream.size.totalBytes;
      }
      if (e > audioStream.size.totalBytes) e = audioStream.size.totalBytes;

      final stream = ytExplode.videos.streams.get(audioStream, s, e);

      return StreamAudioResponse(
        sourceLength: audioStream.size.totalBytes,
        contentLength: e - s,
        offset: s,
        stream: stream,
        contentType: audioStream.codec.mimeType,
      );
    } catch (e) {
      throw Exception('Failed to load audio: $e');
    }
  }
}
