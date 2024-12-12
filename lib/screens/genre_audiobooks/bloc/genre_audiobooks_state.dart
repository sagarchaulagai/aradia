part of 'genre_audiobooks_bloc.dart';

// Bloc State
class GenreAudiobooksState {
  final Map<String, List<Audiobook>> audiobooks;
  final Map<String, bool> isLoading;
  final Map<String, bool> hasReachedMax;
  final Map<String, String?> errors;

  const GenreAudiobooksState({
    this.audiobooks = const {},
    this.isLoading = const {},
    this.hasReachedMax = const {},
    this.errors = const {},
  });

  GenreAudiobooksState copyWith({
    Map<String, List<Audiobook>>? audiobooks,
    Map<String, bool>? isLoading,
    Map<String, bool>? hasReachedMax,
    Map<String, String?>? errors,
  }) {
    return GenreAudiobooksState(
      audiobooks: audiobooks ?? this.audiobooks,
      isLoading: isLoading ?? this.isLoading,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      errors: errors ?? this.errors,
    );
  }

  List<Audiobook> getAudiobooksForListType(String listType) {
    return audiobooks[listType] ?? [];
  }

  bool isLoadingListType(String listType) {
    return isLoading[listType] ?? false;
  }

  bool hasReachedMaxForListType(String listType) {
    return hasReachedMax[listType] ?? false;
  }

  String? getErrorForListType(String listType) {
    return errors[listType];
  }
}
