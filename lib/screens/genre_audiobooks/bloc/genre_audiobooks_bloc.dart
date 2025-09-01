import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';

part 'genre_audiobooks_event.dart';
part 'genre_audiobooks_state.dart';

// Bloc
class GenreAudiobooksBloc
    extends Bloc<GenreAudiobooksEvent, GenreAudiobooksState> {
  final ArchiveApi archiveApi;

  GenreAudiobooksBloc({required this.archiveApi})
      : super(const GenreAudiobooksState()) {
    on<LoadInitialAudiobooksEvent>(_onLoadInitialAudiobooks);
    on<LoadMoreAudiobooksEvent>(_onLoadMoreAudiobooks);
  }

  Future<void> _onLoadInitialAudiobooks(
    LoadInitialAudiobooksEvent event,
    Emitter<GenreAudiobooksState> emit,
  ) async {
    // If audiobooks for this list type already exist, don't reload
    if (state.audiobooks.containsKey(event.listType) &&
        state.audiobooks[event.listType]!.isNotEmpty) {
      return;
    }

    // Update loading state
    emit(state.copyWith(
      isLoading: Map.of(state.isLoading)..[event.listType] = true,
    ));

    try {
      final result = await _fetchAudiobooks(event.genre, event.listType, 1);

      result.fold(
        (error) => emit(state.copyWith(
          errors: Map.of(state.errors)..[event.listType] = error,
          isLoading: Map.of(state.isLoading)..[event.listType] = false,
        )),
        (audiobooks) => emit(state.copyWith(
          audiobooks: Map.of(state.audiobooks)..[event.listType] = audiobooks,
          isLoading: Map.of(state.isLoading)..[event.listType] = false,
          hasReachedMax: Map.of(state.hasReachedMax)
            ..[event.listType] = audiobooks.length < 20,
        )),
      );
    } catch (e) {
      emit(state.copyWith(
        errors: Map.of(state.errors)..[event.listType] = e.toString(),
        isLoading: Map.of(state.isLoading)..[event.listType] = false,
      ));
    }
  }

  Future<void> _onLoadMoreAudiobooks(
    LoadMoreAudiobooksEvent event,
    Emitter<GenreAudiobooksState> emit,
  ) async {
    // Check if we've reached max for this list type
    if (state.hasReachedMaxForListType(event.listType)) return;

    // Update loading state
    emit(state.copyWith(
      isLoading: Map.of(state.isLoading)..[event.listType] = true,
    ));

    try {
      final result = await _fetchAudiobooks(event.genre, event.listType,
          (state.getAudiobooksForListType(event.listType).length ~/ 20) + 1);

      result.fold(
        (error) => emit(state.copyWith(
          errors: Map.of(state.errors)..[event.listType] = error,
          isLoading: Map.of(state.isLoading)..[event.listType] = false,
        )),
        (newAudiobooks) {
          final currentAudiobooks =
              state.getAudiobooksForListType(event.listType);
          final updatedAudiobooks = List.of(currentAudiobooks)
            ..addAll(newAudiobooks);

          return emit(state.copyWith(
            audiobooks: Map.of(state.audiobooks)
              ..[event.listType] = updatedAudiobooks,
            isLoading: Map.of(state.isLoading)..[event.listType] = false,
            hasReachedMax: Map.of(state.hasReachedMax)
              ..[event.listType] = newAudiobooks.length < 20,
          ));
        },
      );
    } catch (e) {
      emit(state.copyWith(
        errors: Map.of(state.errors)..[event.listType] = e.toString(),
        isLoading: Map.of(state.isLoading)..[event.listType] = false,
      ));
    }
  }

  Future<Either<String, List<Audiobook>>> _fetchAudiobooks(
      String genre, String listType, int page) async {
    debugPrint(' My genre is $genre');
    switch (listType) {
      case 'popular':
        return await archiveApi.getAudiobooksByGenre(
            genre, page, 20, 'downloads');
      case 'popularWeekly':
        return await archiveApi.getAudiobooksByGenre(genre, page, 20, 'week');
      case 'latest':
        return await archiveApi.getAudiobooksByGenre(
            genre, page, 20, 'addeddate');
      default:
        return const Left('Invalid list type');
    }
  }
}