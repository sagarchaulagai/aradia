import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:ionicons/ionicons.dart';
import 'package:aradia/resources/designs/app_circular_progress_indicator.dart';
import 'package:aradia/resources/models/audiobook.dart';

import 'package:aradia/screens/audiobook_details/bloc/audiobook_details_bloc.dart';
import 'package:aradia/screens/audiobook_details/widgets/description_text.dart';
import 'package:aradia/screens/download_audiobook/widget/download_button.dart';
import 'package:aradia/resources/services/audio_handler_provider.dart';
import 'package:aradia/widgets/low_and_high_image.dart';
import 'package:aradia/widgets/rating_widget.dart';
import 'package:provider/provider.dart';
import 'package:we_slide/we_slide.dart';

import '../../resources/models/history_of_audiobook.dart';

class AudiobookDetails extends StatefulWidget {
  final Audiobook audiobook;
  final bool isDownload;
  final bool isYoutube;
  const AudiobookDetails({
    super.key,
    required this.audiobook,
    this.isDownload = false,
    this.isYoutube = false,
  });

  @override
  State<AudiobookDetails> createState() => _AudiobookDetailsState();
}

class _AudiobookDetailsState extends State<AudiobookDetails> {
  late AudiobookDetailsBloc _audiobookDetailsBloc;
  late Box<dynamic> playingAudiobookDetailsBox;
  late WeSlideController _weSlideController;
  late AudioHandlerProvider audioHandlerProvider;

  late HistoryOfAudiobook historyOfAudiobook;
  @override
  void initState() {
    _audiobookDetailsBloc = BlocProvider.of<AudiobookDetailsBloc>(context);
    _audiobookDetailsBloc.add(GetFavouriteStatus(widget.audiobook));
    _audiobookDetailsBloc.add(FetchAudiobookDetails(
      widget.audiobook.id,
      widget.isDownload,
      widget.isYoutube,
    ));
    playingAudiobookDetailsBox = Hive.box('playing_audiobook_details_box');

    historyOfAudiobook = HistoryOfAudiobook();

    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _weSlideController = Provider.of<WeSlideController>(context);
    audioHandlerProvider = Provider.of<AudioHandlerProvider>(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.audiobook.title,
          style: GoogleFonts.ubuntu(
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          BlocConsumer<AudiobookDetailsBloc, AudiobookDetailsState>(
            listener: (context, state) {},
            listenWhen: (previous, current) =>
                current is AudiobookDetailsFavourite,
            buildWhen: (previous, current) =>
                current is AudiobookDetailsFavourite,
            builder: (context, state) {
              if (state is AudiobookDetailsFavourite) {
                return IconButton(
                  icon: state.isFavourite
                      ? const Icon(
                          Icons.favorite,
                          color: Colors.red,
                          size: 30,
                        )
                      : const Icon(Icons.favorite_border,
                          color: Colors.red, size: 30),
                  onPressed: () {
                    _audiobookDetailsBloc
                        .add(FavouriteIconButtonClicked(widget.audiobook));
                  },
                );
              } else {
                return const SizedBox();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: BlocConsumer<AudiobookDetailsBloc, AudiobookDetailsState>(
          listener: (context, state) {},
          listenWhen: (previous, current) =>
              current is AudiobookDetailsInitial ||
              current is AudiobookDetailsLoading ||
              current is AudiobookDetailsError ||
              current is AudiobookDetailsLoaded,
          buildWhen: (previous, current) =>
              current is AudiobookDetailsInitial ||
              current is AudiobookDetailsLoading ||
              current is AudiobookDetailsError ||
              current is AudiobookDetailsLoaded,
          builder: (context, state) {
            if (state is AudiobookDetailsInitial) {
              return const Center(
                child: AppCircularProgressIndicator(),
              );
            } else if (state is AudiobookDetailsLoading) {
              return const Center(
                child: AppCircularProgressIndicator(),
              );
            } else if (state is AudiobookDetailsLoaded) {
              return Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LowAndHighImage(
                          lowQImage: widget.audiobook.lowQCoverImage,
                          highQImage: state.audiobookFiles[0].highQCoverImage,
                          height: 200,
                          width: 200,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 200,
                      alignment: Alignment.center,
                      child: Text(
                        widget.audiobook.title,
                        style: GoogleFonts.ubuntu(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      widget.audiobook.author ?? 'N/A',
                      style: GoogleFonts.ubuntu(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      "Downloads : ${widget.audiobook.downloads != null ? widget.audiobook.downloads! > 999 ? widget.audiobook.downloads! > 999999 ? "${(widget.audiobook.downloads! / 1000000).toStringAsFixed(1)}M" : "${(widget.audiobook.downloads! / 1000).toStringAsFixed(1)}K" : widget.audiobook.downloads.toString() : "N/A"}",
                      style: GoogleFonts.ubuntu(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      "${widget.audiobook.origin ?? "librivox"}",
                      style: GoogleFonts.ubuntu(
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    RatingWidget(
                      rating: widget.audiobook.rating ?? 0.0,
                      size: 20,
                    ),
                    const SizedBox(height: 10),
                    Card(
                      color: const Color.fromRGBO(204, 119, 34, 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Improved by Nadia
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: Center(
                                child: DownloadButton(
                                  audiobook: widget.audiobook,
                                  audiobookFiles: state.audiobookFiles,
                                ),
                              ),
                            ),
                            // Improved divider
                            Container(
                              height: 40,
                              width: 1,
                              color: Colors.white.withValues(alpha: 0.5),
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            // Imporved by Nadia
                            SizedBox(
                              width: 60,
                              height: 60,
                              child: Center(
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () {
                                    playingAudiobookDetailsBox.put(
                                        'audiobook', widget.audiobook.toMap());
                                    playingAudiobookDetailsBox.put(
                                        'audiobookFiles',
                                        state.audiobookFiles
                                            .map((e) => e.toMap())
                                            .toList());

                                    if (historyOfAudiobook.isAudiobookInHistory(
                                        widget.audiobook.id)) {
                                      audioHandlerProvider.audioHandler
                                          .initSongs(
                                        state.audiobookFiles,
                                        widget.audiobook,
                                        historyOfAudiobook
                                            .getHistoryOfAudiobookItem(
                                                widget.audiobook.id)
                                            .index,
                                        historyOfAudiobook
                                            .getHistoryOfAudiobookItem(
                                                widget.audiobook.id)
                                            .position,
                                      );
                                      playingAudiobookDetailsBox.put(
                                          'index',
                                          historyOfAudiobook
                                              .getHistoryOfAudiobookItem(
                                                  widget.audiobook.id)
                                              .index);
                                      playingAudiobookDetailsBox.put(
                                          'position',
                                          historyOfAudiobook
                                              .getHistoryOfAudiobookItem(
                                                  widget.audiobook.id)
                                              .position);
                                    } else {
                                      playingAudiobookDetailsBox.put(
                                          'index', 0);
                                      playingAudiobookDetailsBox.put(
                                          'position', 0);
                                      audioHandlerProvider.audioHandler
                                          .initSongs(
                                        state.audiobookFiles,
                                        widget.audiobook,
                                        0,
                                        0,
                                      );
                                    }

                                    audioHandlerProvider.audioHandler.play();
                                    _weSlideController.show();
                                  },
                                  icon: const Icon(
                                    Ionicons.play,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        DescriptionText(
                          description: widget.audiobook.description ?? 'N/A',
                        ),
                        const SizedBox(height: 10),
                        Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Audio Files",
                                style: GoogleFonts.ubuntu(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ListView.builder(
                                itemCount: state.audiobookFiles.length,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  return ListTile(
                                      onTap: () {
                                        playingAudiobookDetailsBox.put(
                                            'audiobook',
                                            widget.audiobook.toMap());
                                        playingAudiobookDetailsBox.put(
                                            'audiobookFiles',
                                            state.audiobookFiles
                                                .map((e) => e.toMap())
                                                .toList());
                                        playingAudiobookDetailsBox.put(
                                            'index', index);
                                        playingAudiobookDetailsBox.put(
                                            'position', 0);
                                        audioHandlerProvider.audioHandler
                                            .initSongs(state.audiobookFiles,
                                                widget.audiobook, index, 0);
                                        audioHandlerProvider.audioHandler
                                            .play();
                                        _weSlideController.show();
                                      },
                                      title: Text(
                                        state.audiobookFiles[index].title ??
                                            'N/A',
                                        style: GoogleFonts.ubuntu(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        state.audiobookFiles[index].length !=
                                                null
                                            ? "${(state.audiobookFiles[index].length! / 60).floor()} minutes"
                                            : 'N/A',
                                        style: GoogleFonts.ubuntu(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        onPressed: () {},
                                        icon: const Icon(Icons.play_arrow),
                                      ));
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Subjects',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Wrap(
                          spacing: 5,
                          children: List.generate(
                            widget.audiobook.subject!.length,
                            (index) {
                              return GestureDetector(
                                onTap: () {
                                  final subjectName =
                                      widget.audiobook.subject![index];
                                  context.push(
                                    '/genre_audiobooks',
                                    extra: subjectName,
                                  );
                                  print('Tapped subject: $subjectName');
                                },
                                child: Chip(
                                  label: Text(
                                    widget.audiobook.subject![index],
                                    style: GoogleFonts.ubuntu(
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            } else if (state is AudiobookDetailsError) {
              return const Center(
                child: Text('Error loading audiobook details 1'),
              );
            }

            return const Center(
              child: Text('Error loading audiobook details 2'),
            );
          },
        ),
      ),
    );
  }
}
