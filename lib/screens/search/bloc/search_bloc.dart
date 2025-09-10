import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/utils/app_events.dart';
import 'package:meta/meta.dart';

part 'search_event.dart';
part 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  int currentPage = 1;

  /// The last query that was explicitly submitted (button press / Enter).
  String? lastQuery;

  StreamSubscription<void>? _langSub;

  SearchBloc() : super(SearchInitial()) {
    on<EventSearchIconClicked>(_onSearchSubmitted);
    on<EventLoadMoreResults>(_onLoadMore);

    // Refresh results for current query on language change
    _langSub = AppEvents.languagesChanged.stream.listen((_) {
      final q = lastQuery?.trim();
      if (q != null && q.isNotEmpty) {
        add(EventSearchIconClicked(q));
      }
    });
  }

  Future<void> _onSearchSubmitted(
      EventSearchIconClicked event,
      Emitter<SearchState> emit,
      ) async {
    // New search starts at page 1 and locks in the query
    currentPage = 1;
    lastQuery = event.searchQuery;

    await _runSearch(emit, query: lastQuery!, page: currentPage, isFresh: true);
  }

  Future<void> _onLoadMore(
      EventLoadMoreResults event,
      Emitter<SearchState> emit,
      ) async {
    // Ignore the UI's current text; keep using the locked-in lastQuery
    final q = lastQuery?.trim();
    if (q == null || q.isEmpty) return;

    currentPage += 1;
    await _runSearch(emit, query: q, page: currentPage, isFresh: false);
  }

  Future<void> _runSearch(
      Emitter<SearchState> emit, {
        required String query,
        required int page,
        required bool isFresh,
      }) async {
    if (isFresh) {
      emit(SearchLoading());
    }

    try {
      final res = await ArchiveApi().searchAudiobook(query, page, 10);

      res.fold(
            (err) {
          if (isFresh) {
            emit(SearchFailure(err));
          } // if not fresh and we failed, keep existing page quietly
        },
            (list) {
          if (isFresh) {
            emit(SearchSuccess(list));
          } else {
            // Append to existing list if already successful
            final prev = state;
            if (prev is SearchSuccess) {
              emit(SearchSuccess([...prev.audiobooks, ...list]));
            } else {
              // If somehow we weren't in success state, just set fresh results
              emit(SearchSuccess(list));
            }
          }
        },
      );
    } catch (_) {
      if (isFresh) {
        emit(SearchFailure('Failed to search audiobooks'));
      }
    }
  }

  @override
  Future<void> close() {
    _langSub?.cancel();
    return super.close();
  }
}
