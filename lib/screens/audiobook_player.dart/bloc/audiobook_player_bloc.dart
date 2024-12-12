import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

part 'audiobook_player_event.dart';
part 'audiobook_player_state.dart';

class AudiobookPlayerBloc extends Bloc<AudiobookPlayerEvent, AudiobookPlayerState> {
  AudiobookPlayerBloc() : super(AudiobookPlayerInitial()) {
    on<AudiobookPlayerEvent>((event, emit) {
      // TODO: implement event handler
    });
  }
}
