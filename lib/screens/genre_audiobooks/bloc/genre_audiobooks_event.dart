part of 'genre_audiobooks_bloc.dart';

@immutable
sealed class GenreAudiobooksEvent {}

class LoadInitialAudiobooksEvent extends GenreAudiobooksEvent {
  final String genre;
  final String listType;

  LoadInitialAudiobooksEvent({
    required this.genre,
    required this.listType,
  });
}

class LoadMoreAudiobooksEvent extends GenreAudiobooksEvent {
  final String genre;
  final String listType;

  LoadMoreAudiobooksEvent({
    required this.genre,
    required this.listType,
  });
}
