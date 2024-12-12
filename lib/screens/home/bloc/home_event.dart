part of 'home_bloc.dart';

@immutable
sealed class HomeEvent {}

class FetchLatestAudiobooks extends HomeEvent {
  final int page;
  final int rows;
  FetchLatestAudiobooks(
    this.page,
    this.rows,
  );
}

class FetchPopularAudiobooks extends HomeEvent {
  final int page;
  final int rows;
  FetchPopularAudiobooks(
    this.page,
    this.rows,
  );
}

class FetchPopularThisWeekAudiobooks extends HomeEvent {
  final int page;
  final int rows;
  FetchPopularThisWeekAudiobooks(
    this.page,
    this.rows,
  );
}
