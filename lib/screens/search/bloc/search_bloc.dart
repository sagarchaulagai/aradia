import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:meta/meta.dart';

part 'search_event.dart';
part 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  int currentPage = 1;

  SearchBloc() : super(SearchInitial()) {
    on<EventSearchIconClicked>(
      (event, emit) async {
        currentPage = 1; // Reset to first page for a new search
        await eventSearchIconClicked(
            event, emit, event.searchQuery, currentPage);
      },
    );
    on<EventLoadMoreResults>(
      (event, emit) async {
        currentPage++; // Increment page for loading more results
        await eventSearchIconClicked(
            event, emit, event.searchQuery, currentPage);
      },
    );
  }

  FutureOr<void> eventSearchIconClicked(
    SearchEvent event,
    Emitter<SearchState> emit,
    String searchQuery,
    int page,
  ) async {
    if (event is EventSearchIconClicked) {
      emit(SearchLoading());
    }
    try {
      var audiobooks =
          await ArchiveApi().searchAudiobook(searchQuery, page, 10);
      audiobooks.fold(
        (left) {
          emit(SearchFailure(left));
        },
        (right) {
          if (event is EventSearchIconClicked) {
            emit(SearchSuccess(right));
          } else if (event is EventLoadMoreResults && state is SearchSuccess) {
            final previousAudiobooks = (state as SearchSuccess).audiobooks;
            emit(SearchSuccess([...previousAudiobooks, ...right]));
          }
        },
      );
    } catch (e) {
      emit(SearchFailure('Failed to search audiobooks'));
    }
  }
}
