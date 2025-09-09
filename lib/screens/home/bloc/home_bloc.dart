import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/utils/app_events.dart';
import 'package:fpdart/fpdart.dart';
import 'package:meta/meta.dart';

part 'home_event.dart';
part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final ArchiveApi _archiveApi;

  StreamSubscription<void>? _langSub;
  int _reqGen = 0; // <--- generation token

  HomeBloc({ArchiveApi? archiveApi})
      : _archiveApi = archiveApi ?? ArchiveApi(),
        super(HomeInitial()) {
    on<FetchLatestAudiobooks>(_onFetchLatestAudiobooks);
    on<FetchPopularAudiobooks>(_onFetchPopularAudiobooks);
    on<FetchPopularThisWeekAudiobooks>(_onFetchPopularThisWeekAudiobooks);
    on<FetchAudiobooksByGenre>(_onFetchAudiobooksByGenre);

    on<ResetHomeLists>((event, emit) {
      // bump generation so any in-flight old requests are ignored
      _reqGen++;
      emit(HomeInitial());
      add(FetchLatestAudiobooks(1, 20));
      add(FetchPopularAudiobooks(1, 20));
      add(FetchPopularThisWeekAudiobooks(1, 20));
    });

    _langSub = AppEvents.languagesChanged.stream.listen((_) {
      add(ResetHomeLists());
    });
  }

  Future<void> _onFetchLatestAudiobooks(
      FetchLatestAudiobooks event,
      Emitter<HomeState> emit,
      ) async {
    await _fetchAudiobooks(
      page: event.page,
      rows: event.rows,
      fetchFunction: () => _archiveApi.getLatestAudiobook(event.page, event.rows),
      loadingState: LatestAudiobooksFetchingLoadingState(),
      successState: (audiobooks) => LatestAudiobooksFetchingSuccessState(audiobooks),
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
      fetchFunction: () => _archiveApi.getMostDownloadedEverAudiobook(event.page, event.rows),
      loadingState: PopularAudiobooksFetchingLoadingState(),
      successState: (audiobooks) => PopularAudiobooksFetchingSuccessState(audiobooks),
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
      fetchFunction: () => _archiveApi.getMostViewedWeeklyAudiobook(event.page, event.rows),
      loadingState: PopularAudiobooksOfWeekFetchingLoadingState(),
      successState: (audiobooks) => PopularAudiobooksOfWeekFetchingSuccessState(audiobooks),
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
      successState: (audiobooks) => GenreAudiobooksFetchingSuccessState(audiobooks),
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
    // capture the generation at the time this request starts
    final localGen = _reqGen;

    if (page == 1) {
      // Only show loading for page 1; if gen changed meanwhile, this is harmless
      emit(loadingState);
    }

    try {
      final result = await fetchFunction();

      // if the language changed while this was in-flight, drop it silently
      if (localGen != _reqGen) return;

      result.fold(
            (_) {
          if (page == 1) {
            emit(failureState);
          }
        },
            (audiobooks) => emit(successState(audiobooks)),
      );
    } catch (_) {
      if (localGen != _reqGen) return; // also ignore late errors
      if (page == 1) {
        emit(failureState);
      }
    }
  }

  @override
  Future<void> close() {
    _langSub?.cancel();
    return super.close();
  }
}
