import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';

part 'home_event.dart';
part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final ArchiveApi _archiveApi;

  HomeBloc({ArchiveApi? archiveApi})
      : _archiveApi = archiveApi ?? ArchiveApi(),
        super(HomeInitial()) {
    on<FetchLatestAudiobooks>(_onFetchLatestAudiobooks);
    on<FetchPopularAudiobooks>(_onFetchPopularAudiobooks);
    on<FetchPopularThisWeekAudiobooks>(_onFetchPopularThisWeekAudiobooks);
    on<FetchAudiobooksByGenre>(_onFetchAudiobooksByGenre);
  }

  Future<void> _onFetchLatestAudiobooks(
    FetchLatestAudiobooks event,
    Emitter<HomeState> emit,
  ) async {
    await _fetchAudiobooks(
      page: event.page,
      rows: event.rows,
      fetchFunction: () =>
          _archiveApi.getLatestAudiobook(event.page, event.rows),
      loadingState: LatestAudiobooksFetchingLoadingState(),
      successState: (audiobooks) =>
          LatestAudiobooksFetchingSuccessState(audiobooks),
      failureState: LatestAudiobooksFetchingFailedState(),
      emit: emit,
    );
  }

  Future<void> _onFetchPopularAudiobooks(
    FetchPopularAudiobooks event,
    Emitter<HomeState> emit,
  ) async {
    await _fetchAudiobooks(
      page: event.page,
      rows: event.rows,
      fetchFunction: () =>
          _archiveApi.getMostDownloadedEverAudiobook(event.page, event.rows),
      loadingState: PopularAudiobooksFetchingLoadingState(),
      successState: (audiobooks) =>
          PopularAudiobooksFetchingSuccessState(audiobooks),
      failureState: PopularAudiobooksFetchingFailedState(),
      emit: emit,
    );
  }

  Future<void> _onFetchPopularThisWeekAudiobooks(
    FetchPopularThisWeekAudiobooks event,
    Emitter<HomeState> emit,
  ) async {
    await _fetchAudiobooks(
      page: event.page,
      rows: event.rows,
      fetchFunction: () =>
          _archiveApi.getMostViewedWeeklyAudiobook(event.page, event.rows),
      loadingState: PopularAudiobooksOfWeekFetchingLoadingState(),
      successState: (audiobooks) =>
          PopularAudiobooksOfWeekFetchingSuccessState(audiobooks),
      failureState: PopularAudiobooksOfWeekFetchingFailedState(),
      emit: emit,
    );
  }

  Future<void> _onFetchAudiobooksByGenre(
    FetchAudiobooksByGenre event,
    Emitter<HomeState> emit,
  ) async {
    await _fetchAudiobooks(
      page: event.page,
      rows: event.rows,
      fetchFunction: () => _archiveApi.getAudiobooksByGenre(
        event.genre,
        event.page,
        event.rows,
        event.sortBy,
      ),
      loadingState: GenreAudiobooksFetchingLoadingState(),
      successState: (audiobooks) =>
          GenreAudiobooksFetchingSuccessState(audiobooks),
      failureState: GenreAudiobooksFetchingFailedState(),
      emit: emit,
    );
  }

  Future<void> _fetchAudiobooks({
    required int page,
    required int rows,
    required Future<Either<String, List<Audiobook>>> Function() fetchFunction,
    required HomeState loadingState,
    required HomeState Function(List<Audiobook>) successState,
    required HomeState failureState,
    required Emitter<HomeState> emit,
  }) async {
    if (page == 1) {
      emit(loadingState);
    }

    try {
      final result = await fetchFunction();
      result.fold(
        (error) {
          if (page == 1) {
            emit(failureState);
          }
        },
        (audiobooks) => emit(successState(audiobooks)),
      );
    } catch (e) {
      if (page == 1) {
        emit(failureState);
      }
    }
  }
}
