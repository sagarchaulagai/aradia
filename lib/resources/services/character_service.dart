import 'package:aradia/utils/app_logger.dart';
import 'package:hive/hive.dart';
import '../models/character.dart';

class CharacterService {
  static const String _boxName = 'characters_box';
  late Box<dynamic> _box;

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  List<Character> getAllCharacters({String? audiobookId}) {
    AppLogger.info("Audiobook id is $audiobookId", "CharacterService");
    final charactersData =
        _box.get('characters', defaultValue: <Map<String, dynamic>>[]);
    if (charactersData is List) {
      final allCharacters = charactersData
          .map((data) {
            if (data is Map) {
              return Character.fromMap(Map<String, dynamic>.from(data));
            }
            return null;
          })
          .where((character) => character != null)
          .cast<Character>()
          .toList();

      if (audiobookId != null) {
        return allCharacters
            .where((char) => char.audiobookId == audiobookId)
            .toList();
      }
      return allCharacters;
    }
    return [];
  }

  Future<void> addCharacter(Character character) async {
    final characters = getAllCharacters();
    characters.add(character);
    await _saveCharacters(characters);
  }

  Future<void> updateCharacter(Character updatedCharacter) async {
    final characters = getAllCharacters();
    final index =
        characters.indexWhere((char) => char.id == updatedCharacter.id);
    if (index != -1) {
      characters[index] = updatedCharacter;
      await _saveCharacters(characters);
    }
  }

  Future<void> deleteCharacter(String characterId) async {
    final characters = getAllCharacters();
    characters.removeWhere((char) => char.id == characterId);
    await _saveCharacters(characters);
  }

  Character? getCharacterById(String characterId) {
    final characters = getAllCharacters();
    try {
      return characters.firstWhere((char) => char.id == characterId);
    } catch (e) {
      return null;
    }
  }

  List<Character> searchCharacters(String query, {String? audiobookId}) {
    final characters = getAllCharacters(audiobookId: audiobookId);
    if (query.isEmpty) return characters;

    return characters
        .where((char) =>
            char.name.toLowerCase().contains(query.toLowerCase()) ||
            char.description.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  Future<void> _saveCharacters(List<Character> characters) async {
    final charactersData = characters.map((char) => char.toMap()).toList();
    await _box.put('characters', charactersData);
  }

  Future<void> clearAllCharacters() async {
    await _box.delete('characters');
  }

  int getCharacterCount() {
    return getAllCharacters().length;
  }

  Future<void> close() async {
    await _box.close();
  }
}
