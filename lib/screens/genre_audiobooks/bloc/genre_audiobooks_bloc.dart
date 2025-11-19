import 'dart:async'; // <-- added
import 'package:aradia/utils/app_logger.dart';
import 'package:aradia/utils/app_events.dart'; // <-- added
import 'package:bloc/bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:meta/meta.dart';

part 'genre_audiobooks_event.dart';
part 'genre_audiobooks_state.dart';

// Bloc
class GenreAudiobooksBloc
    extends Bloc<GenreAudiobooksEvent, GenreAudiobooksState> {
  // Keep only first occurrence of each logical book, preserve order.
  // Use the Archive.org identifier exposed as `id`; fallback to title+author if needed.
  List<Audiobook> _mergeUniqueById(
      List<Audiobook> current, List<Audiobook> incoming) {
    String _key(Audiobook a) {
      final id = (a.id).trim();
      if (id.isNotEmpty) return id;
      final t = (a.title).trim().toLowerCase();
      final c = (a.author ?? '').trim().toLowerCase();
      return '$t|||$c';
    }

    final seen = current.map(_key).toSet();
    final dedupIncoming = <Audiobook>[];
    for (final a in incoming) {
      final k = _key(a);
      if (k.isEmpty) continue;
      if (seen.add(k)) dedupIncoming.add(a);
    }
    return <Audiobook>[...current, ...dedupIncoming];
  }

  final ArchiveApi archiveApi;

  String? _lastGenre;
  StreamSubscription<void>? _langSub;

  GenreAudiobooksBloc({required this.archiveApi})
      : super(const GenreAudiobooksState()) {
    on<LoadInitialAudiobooksEvent>(_onLoadInitialAudiobooks);
    on<LoadMoreAudiobooksEvent>(_onLoadMoreAudiobooks);

    // Listen for language changes and refresh lists
    _langSub = AppEvents.languagesChanged.stream.listen((_) {
      final g = _lastGenre;
      if (g != null && g.isNotEmpty) {
        add(LoadInitialAudiobooksEvent(genre: g, listType: 'popular'));
        add(LoadInitialAudiobooksEvent(genre: g, listType: 'popularWeekly'));
        add(LoadInitialAudiobooksEvent(genre: g, listType: 'latest'));
      }
    });
  }

  Future<void> _onLoadInitialAudiobooks(
      LoadInitialAudiobooksEvent event,
      Emitter<GenreAudiobooksState> emit,
      ) async {
    _lastGenre = event.genre; // <-- remember genre

    // NEW: don't double-load same listType while it's already loading
    if (state.isLoadingListType(event.listType)) return;

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
            (audiobooks) {
          // Initial page = 1
          final nextPageMap = Map.of(state.page)..[event.listType] = 1;

          emit(state.copyWith(
            audiobooks: Map.of(state.audiobooks)
              ..[event.listType] = audiobooks,
            isLoading: Map.of(state.isLoading)..[event.listType] = false,
            hasReachedMax: Map.of(state.hasReachedMax)
              ..[event.listType] = audiobooks.length < 20,
            page: nextPageMap,
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

  Future<void> _onLoadMoreAudiobooks(
      LoadMoreAudiobooksEvent event,
      Emitter<GenreAudiobooksState> emit,
      ) async {
    // Check if we've reached max for this list type
    if (state.hasReachedMaxForListType(event.listType)) return;

    // NEW: don't fetch if already fetching
    if (state.isLoadingListType(event.listType)) return;

    // Update loading state
    emit(state.copyWith(
      isLoading: Map.of(state.isLoading)..[event.listType] = true,
    ));

    try {
      final currentPage = state.getPageForListType(event.listType);
      final nextPage = currentPage + 1;

      final result = await _fetchAudiobooks(
        event.genre,
        event.listType,
        nextPage,
      );

      result.fold(
            (error) => emit(state.copyWith(
          errors: Map.of(state.errors)..[event.listType] = error,
          isLoading: Map.of(state.isLoading)..[event.listType] = false,
        )),
            (newAudiobooks) {
          final currentAudiobooks =
          state.getAudiobooksForListType(event.listType);

          // DE-DUPE HERE
          final updatedAudiobooks =
          _mergeUniqueById(currentAudiobooks, newAudiobooks);

          emit(state.copyWith(
            audiobooks: Map.of(state.audiobooks)
              ..[event.listType] = updatedAudiobooks,
            isLoading: Map.of(state.isLoading)..[event.listType] = false,
            hasReachedMax: Map.of(state.hasReachedMax)
            // Keep your original logic so we don't prematurely stop due to de-dupe
              ..[event.listType] = newAudiobooks.length < 20,
            page: Map.of(state.page)..[event.listType] = nextPage,
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
    AppLogger.debug(' My genre is $genre');
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

  @override
  Future<void> close() {
    _langSub?.cancel(); // <-- cleanup
    return super.close();
  }
}
