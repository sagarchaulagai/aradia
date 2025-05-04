import 'dart:async';

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
  ) async {
    emit(AudiobookDetailsLoading());
    Either<String, List<AudiobookFile>> audiobookFiles;
    try {
      if (isDownload) {
        print('fetching audiobook files from downloaded files');
        audiobookFiles = await AudiobookFile.fromDownloadedFiles(id);
      } else if (isYoutube) {
        print('fetching audiobook files from imported files');
        audiobookFiles = await AudiobookFile.fromYoutubeFiles(id);
      } else {
        print('fetching audiobook files from api');
        audiobookFiles = await ArchiveApi().getAudiobookFiles(id);
      }

      audiobookFiles.fold((l) {
        emit(AudiobookDetailsError());
      }, (r) {
        emit(AudiobookDetailsLoaded([...r]));
      });
    } catch (e) {
      print('Error coming from fetchAudiobookDetails bloc: $e');
      emit(AudiobookDetailsError());
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
    print('Favourite icon clicked and id is ${event.audiobook.id}');

    if (box.containsKey(event.audiobook.id)) {
      await box.delete(event.audiobook.id);
      print('Favourite removed for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(false));
    } else {
      await box.put(event.audiobook.id, event.audiobook.toMap());
      print('Favourite added for this id ${event.audiobook.id}');
      emit(AudiobookDetailsFavourite(true));
    }
  }

  @override
  Future<void> close() {
    _favouriteBoxSubscription?.cancel();
    return super.close();
  }
}
