import 'dart:async';

import 'package:aradia/utils/app_logger.dart';
import 'package:bloc/bloc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive/hive.dart';
import 'package:aradia/resources/archive_api.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:meta/meta.dart';

part 'audiobook_details_event.dart';
part 'audiobook_details_state.dart';

class AudiobookDetailsBloc
    extends Bloc<AudiobookDetailsEvent, AudiobookDetailsState> {
  StreamSubscription? _favouriteBoxSubscription;
  String? _currentAudiobookId;
  AudiobookDetailsBloc() : super(AudiobookDetailsInitial()) {
    on<FetchAudiobookDetails>((event, emit) => fetchAudiobookDetails(
          event,
          emit,
          event.audiobookId,
          event.isDownload,
          event.isYoutube,
          event.isLocal,
        ));
    on<FavouriteIconButtonClicked>(favouriteIconButtonClicked);

    on<GetFavouriteStatus>(getFavouriteStatus);

    final box = Hive.box('favourite_audiobooks_box');
    _favouriteBoxSubscription = box.watch().listen((event) {
      if (_currentAudiobookId != null && event.key == _currentAudiobookId) {
        add(GetFavouriteStatus(Audiobook.fromMap(event.value ?? {})));
      }
    });
  }

  FutureOr<void> fetchAudiobookDetails(
    FetchAudiobookDetails event,
    Emitter<AudiobookDetailsState> emit,
    String id,
    bool isDownload,
    bool isYoutube,
    bool isLocal,
  ) async {
    emit(AudiobookDetailsLoading());
    AppLogger.debug('fetching audiobook details for id: $id');
    AppLogger.debug('isDownload: $isDownload');
    AppLogger.debug('isYoutube: $isYoutube');
    AppLogger.debug('isLocal: $isLocal');
    Either<String, List<AudiobookFile>> audiobookFiles;
    try {
      if (isDownload) {
        AppLogger.debug('fetching audiobook files from downloaded files');
        audiobookFiles = await AudiobookFile.fromDownloadedFiles(id);
      } else if (isYoutube) {
        AppLogger.debug('fetching audiobook files from imported files');
        audiobookFiles = await AudiobookFile.fromYoutubeFiles(id);
      } else if (isLocal) {
        AppLogger.debug('fetching audiobook files from local files');
        audiobookFiles = await AudiobookFile.fromLocalFiles(id);
      } else {
        AppLogger.debug('fetching audiobook files from api');
        audiobookFiles = await ArchiveApi().getAudiobookFiles(id);
      }

      audiobookFiles.fold((l) {
        emit(AudiobookDetailsError(l));
      }, (r) {
        emit(AudiobookDetailsLoaded([...r]));
      });
    } catch (e) {
      AppLogger.debug('Error coming from fetchAudiobookDetails bloc: $e');
      emit(AudiobookDetailsError(e.toString()));
    }
  }

  FutureOr<void> getFavouriteStatus(
    GetFavouriteStatus event,
    Emitter<AudiobookDetailsState> emit,
  ) async {
    _currentAudiobookId = event.audiobook.id;
    var box = Hive.box('favourite_audiobooks_box');
    emit(AudiobookDetailsFavourite(box.containsKey(event.audiobook.id)));
  }

  FutureOr<void> favouriteIconButtonClicked(
    FavouriteIconButtonClicked event,
    Emitter<AudiobookDetailsState> emit,
  ) async {
    var box = Hive.box('favourite_audiobooks_box');
    _currentAudiobookId = event.audiobook.id;
    AppLogger.debug('Favourite icon clicked and id is ${event.audiobook.id}');

    if (box.containsKey(event.audiobook.id)) {
      await box.delete(event.audiobook.id);
      AppLogger.debug('Favourite removed for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(false));
    } else {
      await box.put(event.audiobook.id, event.audiobook.toMap());
      AppLogger.debug('Favourite added for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(true));
    }
  }

  @override
  Future<void> close() {
    _favouriteBoxSubscription?.cancel();
    return super.close();
  }
}
