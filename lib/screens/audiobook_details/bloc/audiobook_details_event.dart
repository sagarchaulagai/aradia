part of 'audiobook_details_bloc.dart';

@immutable
sealed class AudiobookDetailsEvent {}

class FetchAudiobookDetails extends AudiobookDetailsEvent {
  final String audiobookId;
  final bool isDownload;
  final bool isYoutube;
  final bool isLocal;

  FetchAudiobookDetails(
    this.audiobookId,
    this.isDownload,
    this.isYoutube,
    this.isLocal,
  );
}

class FavouriteIconButtonClicked extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  FavouriteIconButtonClicked(this.audiobook);
}

class GetFavouriteStatus extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  GetFavouriteStatus(this.audiobook);
}
