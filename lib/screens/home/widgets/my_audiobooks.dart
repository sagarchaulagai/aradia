import 'package:aradia/utils/app_logger.dart';
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
  // Genres
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
  final bool autoFetch;

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
    this.autoFetch = true,
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
    if (widget.autoFetch) {
      _fetchData();
    }
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
      AppLogger.debug('fetchEvent is not a function');
    }
  }

  bool _isLoadingState(HomeState s) {
    final loadingType =
        fetchTypeMapping[widget.fetchType]?['loadingState'] as Type?;
    return loadingType != null && s.runtimeType == loadingType;
  }

  bool _isSuccessState(HomeState s) {
    final successType =
        fetchTypeMapping[widget.fetchType]?['successState'] as Type?;
    return successType != null && s.runtimeType == successType;
  }

  bool _isFailedState(HomeState s) {
    final failedType =
        fetchTypeMapping[widget.fetchType]?['failedState'] as Type?;
    return failedType != null && s.runtimeType == failedType;
  }

  @override
  void dispose() {
    widget.scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Match FavouriteSection's header padding exactly
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Text(
                widget.title,
                style: GoogleFonts.ubuntu(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Match FavouriteSection's list height and horizontal padding exactly
        SizedBox(
          height: 250,
          child: BlocConsumer<HomeBloc, HomeState>(
            bloc: widget.homeBloc,
            listener: (context, state) {
              if (_isLoadingState(state)) {
                setState(() {
                  _currentPage = widget.initialPage;
                  audiobooks.clear();
                });
              }
              if (_isSuccessState(state)) {
                setState(() {
                  audiobooks.addAll((state as dynamic).audiobooks);
                });
              }
            },
            buildWhen: (previous, current) =>
                _isSuccessState(current) ||
                _isLoadingState(current) ||
                _isFailedState(current),
            builder: (context, state) {
              if (_isLoadingState(state) && audiobooks.isEmpty) {
                return const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primaryColor),
                );
              }
              if (_isFailedState(state) && audiobooks.isEmpty) {
                return const Center(child: Text("Failed to fetch audiobooks"));
              }

              return ListView.builder(
                controller: widget.scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8), // <-- same as FavouriteSection
                itemCount: audiobooks.length + 1,
                itemBuilder: (context, index) {
                  if (index == audiobooks.length) {
                    // keep the paging spinner at the end (FavouriteSection doesn't page, but this preserves your UX)
                    return const Center(
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                            color: AppColors.primaryColor),
                      ),
                    );
                  }
                  return AudiobookItem(
                    audiobook: audiobooks[index],
                    width: _eachContainerWidth,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
