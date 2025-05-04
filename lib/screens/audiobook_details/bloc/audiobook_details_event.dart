part of 'audiobook_details_bloc.dart';

@immutable
sealed class AudiobookDetailsEvent {}

class FetchAudiobookDetails extends AudiobookDetailsEvent {
  final String audiobookId;
  final bool isDownload;

  FetchAudiobookDetails(this.audiobookId, this.isDownload);
}

class FavouriteIconButtonClicked extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  FavouriteIconButtonClicked(this.audiobook);
}

class GetFavouriteStatus extends AudiobookDetailsEvent {
  final Audiobook audiobook;

  GetFavouriteStatus(this.audiobook);
}
