import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/screens/home/bloc/home_bloc.dart';
import 'package:aradia/widgets/audiobook_item.dart';

enum AudiobooksFetchType {
  latest,
  popular,
  popularOfWeek,
  genre,
}

final fetchTypeMapping = {
  AudiobooksFetchType.latest: {
    'fetchEvent': (int page, int rows) => FetchLatestAudiobooks(page, rows),
    'successState': LatestAudiobooksFetchingSuccessState,
    'loadingState': LatestAudiobooksFetchingLoadingState,
    'failedState': LatestAudiobooksFetchingFailedState,
  },
  AudiobooksFetchType.popular: {
    'fetchEvent': (int page, int rows) => FetchPopularAudiobooks(page, rows),
    'successState': PopularAudiobooksFetchingSuccessState,
    'loadingState': PopularAudiobooksFetchingLoadingState,
    'failedState': PopularAudiobooksFetchingFailedState,
  },
  AudiobooksFetchType.popularOfWeek: {
    'fetchEvent': (int page, int rows) =>
        FetchPopularThisWeekAudiobooks(page, rows),
    'successState': PopularAudiobooksOfWeekFetchingSuccessState,
    'loadingState': PopularAudiobooksOfWeekFetchingLoadingState,
    'failedState': PopularAudiobooksOfWeekFetchingFailedState,
  },
  // Add fetchType for genres
  AudiobooksFetchType.genre: {
    'fetchEvent': (int page, int rows, String genre, String sortBy) =>
        FetchAudiobooksByGenre(page, rows, genre, sortBy),
    'successState': GenreAudiobooksFetchingSuccessState,
    'loadingState': GenreAudiobooksFetchingLoadingState,
    'failedState': GenreAudiobooksFetchingFailedState,
  },
};

class MyAudiobooks extends StatefulWidget {
  final String title;
  final HomeBloc homeBloc;
  final AudiobooksFetchType fetchType;
  final String? genre;
  final String? sortBy;
  final int initialPage;
  final int rowsPerPage;

  final ScrollController scrollController;

  const MyAudiobooks({
    super.key,
    required this.title,
    required this.homeBloc,
    required this.fetchType,
    this.genre,
    this.sortBy,
    required this.scrollController,
    this.initialPage = 1,
    this.rowsPerPage = 15,
  });

  @override
  State<MyAudiobooks> createState() => _MyAudiobooksState();
}

class _MyAudiobooksState extends State<MyAudiobooks> {
  int _currentPage = 1;
  final List<Audiobook> audiobooks = [];
  final double _eachContainerWidth = 175;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _fetchData();
    widget.scrollController.addListener(() {
      if (widget.scrollController.position.pixels ==
          widget.scrollController.position.maxScrollExtent) {
        _currentPage++;
        _fetchData();
      }
    });
  }

  void _fetchData() {
    final fetchEvent = fetchTypeMapping[widget.fetchType]?['fetchEvent'];
    if (fetchEvent != null && fetchEvent is Function) {
      if (widget.fetchType == AudiobooksFetchType.genre &&
          widget.genre != null) {
        widget.homeBloc.add(fetchEvent(
          _currentPage,
          widget.rowsPerPage,
          widget.genre!,
          widget.sortBy ?? 'week',
        ));
      } else {
        widget.homeBloc.add(fetchEvent(_currentPage, widget.rowsPerPage));
      }
    } else {
      print('fetchEvent is not a function');
    }
  }

  @override
  void dispose() {
    widget.scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 250,
            child: BlocConsumer<HomeBloc, HomeState>(
              bloc: widget.homeBloc,
              listener: (context, state) {
                final successState =
                    fetchTypeMapping[widget.fetchType]?['successState'];
                if (successState != null && state.runtimeType == successState) {
                  setState(() {
                    audiobooks.addAll((state as dynamic).audiobooks);
                  });
                }
              },
              buildWhen: (previous, current) =>
                  current.runtimeType ==
                      fetchTypeMapping[widget.fetchType]?['successState'] ||
                  current.runtimeType ==
                      fetchTypeMapping[widget.fetchType]?['loadingState'] ||
                  current.runtimeType ==
                      fetchTypeMapping[widget.fetchType]?['failedState'],
              builder: (context, state) {
                if (state.runtimeType ==
                    fetchTypeMapping[widget.fetchType]?['loadingState']) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryColor),
                  );
                } else if (state.runtimeType ==
                    fetchTypeMapping[widget.fetchType]?['failedState']) {
                  return const Center(
                    child: Text("Failed to fetch audiobooks"),
                  );
                } else {
                  return ListView.builder(
                    controller: widget.scrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: audiobooks.length + 1,
                    itemBuilder: (context, index) {
                      if (index == audiobooks.length) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryColor,
                          ),
                        );
                      }
                      return AudiobookItem(
                        audiobook: audiobooks[index],
                        width: _eachContainerWidth,
                      );
                    },
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
