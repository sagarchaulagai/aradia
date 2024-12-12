part of 'search_bloc.dart';

@immutable
sealed class SearchEvent {}

class EventSearchIconClicked extends SearchEvent {
  final String searchQuery;
  EventSearchIconClicked(this.searchQuery);
}

class EventLoadMoreResults extends SearchEvent {
  final String searchQuery;
  EventLoadMoreResults(this.searchQuery);
}
