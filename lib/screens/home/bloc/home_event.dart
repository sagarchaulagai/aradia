part of 'home_bloc.dart';

@immutable
sealed class HomeEvent {}

class FetchLatestAudiobooks extends HomeEvent {
  final int page;
  final int rows;
  FetchLatestAudiobooks(this.page, this.rows);
}

class FetchPopularAudiobooks extends HomeEvent {
  final int page;
  final int rows;
  FetchPopularAudiobooks(this.page, this.rows);
}

class FetchPopularThisWeekAudiobooks extends HomeEvent {
  final int page;
  final int rows;
  FetchPopularThisWeekAudiobooks(this.page, this.rows);
}

class FetchAudiobooksByGenre extends HomeEvent {
  final int page;
  final int rows;
  final String genre;
  final String sortBy;
  FetchAudiobooksByGenre(this.page, this.rows, this.genre, this.sortBy);
}

class ResetHomeLists extends HomeEvent {
  ResetHomeLists();
}
