part of 'home_bloc.dart';

@immutable
sealed class HomeState {}

final class HomeInitial extends HomeState {}

class LatestAudiobooksFetchingSuccessState extends HomeState {
  final List<Audiobook> audiobooks;
  LatestAudiobooksFetchingSuccessState(
    this.audiobooks,
  );
}

class LatestAudiobooksFetchingLoadingState extends HomeState {}

class LatestAudiobooksFetchingFailedState extends HomeState {}

class PopularAudiobooksFetchingSuccessState extends HomeState {
  final List<Audiobook> audiobooks;
  PopularAudiobooksFetchingSuccessState(
    this.audiobooks,
  );
}

class PopularAudiobooksFetchingLoadingState extends HomeState {}

class PopularAudiobooksFetchingFailedState extends HomeState {}

class PopularAudiobooksOfWeekFetchingSuccessState extends HomeState {
  final List<Audiobook> audiobooks;
  PopularAudiobooksOfWeekFetchingSuccessState(
    this.audiobooks,
  );
}

class PopularAudiobooksOfWeekFetchingLoadingState extends HomeState {}

class PopularAudiobooksOfWeekFetchingFailedState extends HomeState {}

// New states for fetching audiobooks by genre
class GenreAudiobooksFetchingSuccessState extends HomeState {
  final List<Audiobook> audiobooks;
  GenreAudiobooksFetchingSuccessState(
    this.audiobooks,
  );
}

class GenreAudiobooksFetchingLoadingState extends HomeState {}

class GenreAudiobooksFetchingFailedState extends HomeState {}
