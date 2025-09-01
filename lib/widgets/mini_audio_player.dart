import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/screens/audiobook_player/audiobook_player.dart';
import 'package:aradia/services/audio_handler_provider.dart';
import 'package:aradia/widgets/low_and_high_image.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

class MiniAudioPlayer extends StatefulWidget {
  final Box<dynamic> playingAudiobookDetailsBox;
  final StatefulNavigationShell navigationShell;
  final BottomNavigationBar bottomNavigationBar;
  final double bottomNavBarSize;

  const MiniAudioPlayer({
    super.key,
    required this.playingAudiobookDetailsBox,
    required this.navigationShell,
    required this.bottomNavigationBar,
    required this.bottomNavBarSize,
  });

  @override
  State<MiniAudioPlayer> createState() => _MiniAudioPlayerState();
}

class _MiniAudioPlayerState extends State<MiniAudioPlayer> {
  late AudioHandlerProvider audioHandlerProvider;
  late WeSlideController weSlideController;
  static int idk = 0;

  @override
  void initState() {
    super.initState();
    weSlideController = Provider.of<WeSlideController>(context, listen: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (idk == 0) {
      audioHandlerProvider = Provider.of<AudioHandlerProvider>(context);

      List<AudiobookFile> audiobookFiles = [];
      for (int i = 0;
          i < widget.playingAudiobookDetailsBox.get('audiobookFiles').length;
          i++) {
        audiobookFiles.add(AudiobookFile.fromMap(
            widget.playingAudiobookDetailsBox.get('audiobookFiles')[i]));
      }
      int index = widget.playingAudiobookDetailsBox.get('index');
      Audiobook audiobook =
          Audiobook.fromMap(widget.playingAudiobookDetailsBox.get('audiobook'));

      int position = widget.playingAudiobookDetailsBox.get('position');
      audioHandlerProvider.audioHandler
          .initSongs(audiobookFiles, audiobook, index, position);
      idk++;
    }
  }

  Widget _buildSliderIndicator() {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(128),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final double panelMaxSize = MediaQuery.of(context).size.height;
    final double panelMinSize = 80 + widget.bottomNavBarSize;

    return WeSlide(
      controller: weSlideController,
      panelMinSize: panelMinSize,
      panelMaxSize: panelMaxSize,
      footerHeight: widget.bottomNavBarSize,
      footer: widget.bottomNavigationBar,
      body: widget.navigationShell,
      panel: const AudiobookPlayer(),
      panelHeader: GestureDetector(
        onTap: () {
          weSlideController.show();
        },
        child: Container(
          height: 80,
          color: colorScheme.secondary,
          child: Container(
            color: Colors.grey[850],
            child: Column(
              children: [
                Center(child: _buildSliderIndicator()),
                Expanded(
                  child: StreamBuilder<MediaItem?>(
                    stream: audioHandlerProvider.audioHandler.mediaItem,
                    builder: (context, snapshot) {
                      if (snapshot.data != null) {
                        MediaItem mediaItem = snapshot.data!;
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  LowAndHighImage(
                                    lowQImage: mediaItem.artUri.toString(),
                                    highQImage: mediaItem.artUri.toString(),
                                    width: 50,
                                    height: 50,
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width * 0.5,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          mediaItem.album ?? "",
                                          style: const TextStyle(
                                              color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        Text(
                                          mediaItem.title,
                                          style: const TextStyle(
                                              color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              StreamBuilder<PlaybackState>(
                                stream: audioHandlerProvider
                                    .audioHandler.playbackState,
                                builder: (context, snapshot) {
                                  if (snapshot.data != null) {
                                    PlaybackState playbackState =
                                        snapshot.data!;
                                    final processingState =
                                        playbackState.processingState;
                                    if (processingState ==
                                            AudioProcessingState.loading ||
                                        processingState ==
                                            AudioProcessingState.buffering) {
                                      return const CircularProgressIndicator(
                                        color: AppColors.primaryColor,
                                        strokeWidth: 2,
                                      );
                                    }
                                    return IconButton(
                                      icon: Icon(
                                        playbackState.playing
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                      ),
                                      onPressed: () {
                                        if (playbackState.playing) {
                                          audioHandlerProvider.audioHandler
                                              .pause();
                                        } else {
                                          audioHandlerProvider.audioHandler
                                              .play();
                                        }
                                      },
                                    );
                                  }
                                  return const SizedBox();
                                },
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}