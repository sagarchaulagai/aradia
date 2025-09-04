import 'dart:io';
import 'package:aradia/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show immutable;

const String kCoverFileName = 'cover.jpg';

@immutable
class MediaHelper {
  const MediaHelper._();

  static Future<XFile?> pickImageFromGallery(ImagePicker picker) async {
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      return image;
    } catch (e) {
      AppLogger.debug('Error picking image from gallery: $e');
      return null;
    }
  }

  static Future<double> getAudioDuration(File file) async {
    try {
      final player = AudioPlayer();
      await player.setFilePath(file.path);
      final duration = await player.durationFuture; // Use durationFuture
      await player.dispose();
      return duration?.inSeconds.toDouble() ?? 0.0;
    } catch (e) {
      AppLogger.debug('Error getting audio duration for ${file.path}: $e');
      return 0.0;
    }
  }

  static Future<String?> saveOrUpdateCoverImage({
    required Directory
        audiobookSpecificDir, // e.g., .../app_path/local/audiobook_id/
    File? newLocalCoverFileToSave, // If user picked a new local file
    String? newNetworkCoverUrlToSave, // If user selected a new GBooks cover URL
    String?
        currentCoverPathInDb, // The path currently stored in the Audiobook object
  }) async {
    if (!await audiobookSpecificDir.exists()) {
      await audiobookSpecificDir.create(recursive: true);
    }
    final File standardCoverFile =
        File(p.join(audiobookSpecificDir.path, kCoverFileName));
    String? finalPathForDb;

    // 1. If a new local file was picked
    if (newLocalCoverFileToSave != null) {
      try {
        // Delete existing standard cover file if it's different from the new source
        if (await standardCoverFile.exists() &&
            standardCoverFile.absolute.path !=
                newLocalCoverFileToSave.absolute.path) {
          await standardCoverFile.delete();
        }
        // Delete the old cover from DB if it was local, not the standard name, and exists
        if (currentCoverPathInDb != null &&
            !currentCoverPathInDb.startsWith('http') &&
            currentCoverPathInDb != standardCoverFile.absolute.path) {
          final oldDbFile = File(currentCoverPathInDb);
          if (await oldDbFile.exists()) {
            try {
              await oldDbFile.delete();
            } catch (e) {
              AppLogger.debug("Error deleting old DB file: $e");
            }
          }
        }
        await newLocalCoverFileToSave.copy(standardCoverFile.path);
        finalPathForDb = standardCoverFile.path;
      } catch (e) {
        AppLogger.debug("Error saving new local cover: $e");
        finalPathForDb = currentCoverPathInDb; // Fallback
      }
    }
    // 2. Else if a new Google Books cover URL was selected
    else if (newNetworkCoverUrlToSave != null) {
      try {
        // Delete existing standard cover file and old DB local file
        if (await standardCoverFile.exists()) await standardCoverFile.delete();
        if (currentCoverPathInDb != null &&
            !currentCoverPathInDb.startsWith('http')) {
          final oldDbFile = File(currentCoverPathInDb);
          if (await oldDbFile.exists()) {
            try {
              await oldDbFile.delete();
            } catch (e) {
              AppLogger.debug("Error deleting old DB file: $e");
            }
          }
        }

        final response = await http.get(Uri.parse(newNetworkCoverUrlToSave));
        if (response.statusCode == 200) {
          await standardCoverFile.writeAsBytes(response.bodyBytes);
          finalPathForDb = standardCoverFile.path;
        } else {
          AppLogger.debug(
              'Failed to download GBooks cover: ${response.statusCode}');
          finalPathForDb =
              newNetworkCoverUrlToSave; // Save URL if download fails
        }
      } catch (e) {
        AppLogger.debug("Error downloading GBooks cover: $e");
        finalPathForDb = newNetworkCoverUrlToSave; // Save URL on other errors
      }
    }
    // 3. Else (no new selection), handle the existing cover path from DB
    else if (currentCoverPathInDb != null && currentCoverPathInDb.isNotEmpty) {
      if (currentCoverPathInDb.startsWith('http')) {
        finalPathForDb = currentCoverPathInDb; // Keep URL
      } else {
        // Existing cover is local
        final File existingLocalFileFromDb = File(currentCoverPathInDb);
        if (await existingLocalFileFromDb.exists()) {
          // If it's not already the standard cover file, standardize it
          if (existingLocalFileFromDb.absolute.path !=
              standardCoverFile.absolute.path) {
            try {
              if (await standardCoverFile.exists() &&
                  standardCoverFile.absolute.path !=
                      existingLocalFileFromDb.absolute.path) {
                // Only delete standardCoverFile if it exists AND is not the same as existingLocalFileFromDb
                // This case is tricky: if standardCoverFile exists but existingLocalFileFromDb is different,
                // we want to replace standardCoverFile with existingLocalFileFromDb (renamed).
                await standardCoverFile.delete();
              }
              await existingLocalFileFromDb.copy(standardCoverFile.path);
              await existingLocalFileFromDb
                  .delete(); // Delete original non-standard name file
              finalPathForDb = standardCoverFile.path;
            } catch (e) {
              AppLogger.debug("Error standardizing old local cover: $e");
              finalPathForDb =
                  existingLocalFileFromDb.path; // Fallback to its original path
            }
          } else {
            finalPathForDb = standardCoverFile.path; // Already standard
          }
        } else {
          finalPathForDb =
              null; // Local file from DB not found, effectively no cover
        }
      }
    } else {
      finalPathForDb = null; // No cover information at all
    }
    return finalPathForDb;
  }
}
