part of 'audiobook_details_bloc.dart';

@immutable
sealed class AudiobookDetailsState {}

final class AudiobookDetailsInitial extends AudiobookDetailsState {}

final class AudiobookDetailsLoading extends AudiobookDetailsState {}

final class AudiobookDetailsLoaded extends AudiobookDetailsState {
  final List<AudiobookFile> audiobookFiles;

  AudiobookDetailsLoaded(this.audiobookFiles);
}

final class AudiobookDetailsError extends AudiobookDetailsState {}

final class AudiobookDetailsFavourite extends AudiobookDetailsState {
  final bool isFavourite;

  AudiobookDetailsFavourite(this.isFavourite);
}
