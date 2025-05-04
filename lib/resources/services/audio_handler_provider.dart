import 'package:aradia/resources/services/my_audio_handler.dart';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

class AudioHandlerProvider extends ChangeNotifier {
  late MyAudioHandler _audioHandler = MyAudioHandler();

  Future<void> initialize() async {
    _audioHandler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.oseamiya.librivoxaudiobook',
        androidNotificationChannelName: 'Audio playback',
        androidNotificationOngoing: true,
      ),
    );
    notifyListeners(); // Notifies listeners that initialization is done
  }

  MyAudioHandler get audioHandler => _audioHandler;
}
