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

// For Most Popular Audiobooks

class PopularAudiobooksFetchingSuccessState extends HomeState {
  final List<Audiobook> audiobooks;
  PopularAudiobooksFetchingSuccessState(
    this.audiobooks,
  );
}

class PopularAudiobooksFetchingLoadingState extends HomeState {}

class PopularAudiobooksFetchingFailedState extends HomeState {}

// For Popular Audiobooks of the week

class PopularAudiobooksOfWeekFetchingSuccessState extends HomeState {
  final List<Audiobook> audiobooks;
  PopularAudiobooksOfWeekFetchingSuccessState(
    this.audiobooks,
  );
}

class PopularAudiobooksOfWeekFetchingLoadingState extends HomeState {}

class PopularAudiobooksOfWeekFetchingFailedState extends HomeState {}
