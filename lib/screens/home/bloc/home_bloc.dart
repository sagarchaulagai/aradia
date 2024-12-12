import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:meta/meta.dart';

part 'home_event.dart';
part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc() : super(HomeInitial()) {
    on<FetchLatestAudiobooks>((event, emit) async {
      await fetchLatestAudiobooks(event, emit, event.page, event.rows);
    });

    on<FetchPopularAudiobooks>((event, emit) async {
      await fetchPopularAudiobooks(event, emit, event.page, event.rows);
    });

    on<FetchPopularThisWeekAudiobooks>((event, emit) async {
      await fetchPopularThisWeekAudiobooks(event, emit, event.page, event.rows);
    });
  }

  FutureOr<void> fetchLatestAudiobooks(
    FetchLatestAudiobooks event,
    Emitter<HomeState> emit,
    int page,
    int rows,
  ) async {
    if (page == 1) {
      emit(LatestAudiobooksFetchingLoadingState());
    }
    try {
      var audiobooks = await ArchiveApi().getLatestAudiobook(page, rows);
      audiobooks.fold(
        (left) {
          if (page == 1) {
            emit(LatestAudiobooksFetchingFailedState());
          }
        },
        (right) {
          emit(LatestAudiobooksFetchingSuccessState(right));
        },
      );
    } catch (e) {
      emit(LatestAudiobooksFetchingFailedState());
    }
  }

  FutureOr<void> fetchPopularAudiobooks(
    FetchPopularAudiobooks event,
    Emitter<HomeState> emit,
    int page,
    int rows,
  ) async {
    if (page == 1) {
      emit(PopularAudiobooksFetchingLoadingState());
    }
    try {
      var audiobooks =
          await ArchiveApi().getMostDownloadedEverAudiobook(page, rows);

      audiobooks.fold(
        (left) {
          if (page == 1) {
            emit(PopularAudiobooksFetchingFailedState());
          }
        },
        (right) {
          emit(PopularAudiobooksFetchingSuccessState(right));
        },
      );
    } catch (e) {
      emit(PopularAudiobooksFetchingFailedState());
    }
  }

  FutureOr fetchPopularThisWeekAudiobooks(
    FetchPopularThisWeekAudiobooks event,
    Emitter<HomeState> emit,
    int page,
    int rows,
  ) async {
    if (page == 1) {
      emit(PopularAudiobooksOfWeekFetchingLoadingState());
    }
    try {
      var audiobooks = await ArchiveApi().getMostViewedWeeklyAudiobook(
        page,
        rows,
      );

      audiobooks.fold(
        (left) {
          if (page == 1) {
            emit(PopularAudiobooksOfWeekFetchingFailedState());
          }
        },
        (right) {
          emit(PopularAudiobooksOfWeekFetchingSuccessState(right));
        },
      );
    } catch (e) {
      emit(PopularAudiobooksOfWeekFetchingFailedState());
    }
  }
}
