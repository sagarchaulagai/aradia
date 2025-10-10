import 'dart:io';
import 'package:aradia/resources/services/youtube/stream_client.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:aradia/utils/permission_helper.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:media_store_plus/media_store_plus.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal() {
    // Initialize MediaStore app folder for Android 10+
    if (Platform.isAndroid) {
      MediaStore.appFolder = "Aradia";
    }
  }

  final FileDownloader _downloader = FileDownloader();
  final Box<dynamic> downloadStatusBox = Hive.box('download_status_box');
  final Map<String, bool> _activeDownloads = {};

  static const int _veryLargeFileThresholdBytes = 50 * 1024 * 1024;

  /// Check if the current Android version is API 29 (Android 10) or higher
  /// If it is higher then we use temporary directory for downloads
  /// using MediaStore to move files to public directory
  Future<bool> _isAndroid10OrHigher() async {
    if (!Platform.isAndroid) return false;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return androidInfo.version.sdkInt >= 29;
  }

  /// Get the appropriate download directory based on Android version
  Future<Directory> _getDownloadDirectory(String audiobookId) async {
    if (await _isAndroid10OrHigher()) {
      // For Android 10+, we will use temporary directory first
      final tempDir = await getTemporaryDirectory();
      final downloadDir = Directory('${tempDir.path}/downloads/$audiobookId');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      return downloadDir;
    } else {
      // For Android 9 and below, use public Downloads/Aradia directory
      final publicDir = Directory('/storage/emulated/0/Download/Aradia/$audiobookId');
      if (!await publicDir.exists()) {
        await publicDir.create(recursive: true);
      }
      return publicDir;
    }
  }

  /// Get the final public directory where files are stored after download
  /// This is used for reading files during playback
  static Future<Directory> getPublicDownloadDirectory(String audiobookId) async {
    return Directory('/storage/emulated/0/Download/Aradia/$audiobookId');
  }

  /// Get the metadata directory for saving audiobook.txt and files.txt
  /// For Android 10+, save to temp first, then move to public
  /// For Android 9-, save directly to public
  Future<Directory> getMetadataDirectory(String audiobookId) async {
    if (await _isAndroid10OrHigher()) {
      // For Android 10+, save metadata to temp directory first
      final tempDir = await getTemporaryDirectory();
      final metadataDir = Directory('${tempDir.path}/downloads/$audiobookId');
      if (!await metadataDir.exists()) {
        await metadataDir.create(recursive: true);
      }
      return metadataDir;
    } else {
      // For Android 9 and below, save directly to public directory
      final publicDir = Directory('/storage/emulated/0/Download/Aradia/$audiobookId');
      if (!await publicDir.exists()) {
        await publicDir.create(recursive: true);
      }
      return publicDir;
    }
  }

  /// Move metadata files (audiobook.txt, files.txt) to public directory
  Future<bool> _moveMetadataToPublicDirectory(String audiobookId) async {
    try {
      if (!await _isAndroid10OrHigher()) {
        // For Android 9 and below, files are already in the correct location
        return true;
      }

      final tempDir = await getTemporaryDirectory();
      final tempMetadataDir = Directory('${tempDir.path}/downloads/$audiobookId');
      
      // Move audiobook.txt
      final tempAudiobookFile = File('${tempMetadataDir.path}/audiobook.txt');
      if (await tempAudiobookFile.exists()) {
        final moveSuccess = await _moveToPublicDirectory(tempAudiobookFile, 'audiobook.txt', audiobookId);
        if (!moveSuccess) return false;
      }
      
      // Move files.txt
      final tempFilesFile = File('${tempMetadataDir.path}/files.txt');
      if (await tempFilesFile.exists()) {
        final moveSuccess = await _moveToPublicDirectory(tempFilesFile, 'files.txt', audiobookId);
        if (!moveSuccess) return false;
      }
      
      return true;
    } catch (e) {
      AppLogger.debug('Error moving metadata to public directory: $e');
      return false;
    }
  }

  /// Move file from temporary location to public Downloads/Aradia directory using MediaStore
  Future<bool> _moveToPublicDirectory(File tempFile, String fileName, String audiobookId) async {
    try {
      if (!await _isAndroid10OrHigher()) {
        // For Android 9 and below, file is already in the correct location
        return true;
      }

      // For Android 10+, use MediaStore to save to public directory
      // Create subfolder for this specific audiobook
      final originalAppFolder = MediaStore.appFolder;
      MediaStore.appFolder = "Aradia/$audiobookId";
      
      // Ensure the temp file has the correct name with extension
      final tempFileWithCorrectName = File('${tempFile.parent.path}/$fileName');
      File fileToMove = tempFile;
      if (tempFile.path != tempFileWithCorrectName.path) {
        fileToMove = await tempFile.rename(tempFileWithCorrectName.path);
      }
      
      final mediaStore = MediaStore();
      final savedUri = await mediaStore.saveFile(
        tempFilePath: fileToMove.path,
        dirType: DirType.download,
        dirName: DirName.download,
      );
      
      // Restore original app folder
      MediaStore.appFolder = originalAppFolder;

      if (savedUri != null) {
        // Delete the temporary file after successful move
        if (await fileToMove.exists()) {
          await fileToMove.delete();
        }
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.debug('Error moving file to public directory: $e');
      return false;
    }
  }

  Future<bool> checkAndRequestPermissions() async {
    return await PermissionHelper.requestDownloadPermissions();
  }

  Future<void> downloadAudiobook(
    String audiobookId,
    String audiobookTitle,
    List<Map<String, dynamic>> files,
    Function(double) onProgressUpdate,
    Function(bool) onCompleted,
  ) async {
    YoutubeExplode? yt;
    AudioStreamClient? audioStreamClient;

    try {
      if (!await checkAndRequestPermissions()) {
        throw Exception('Storage permissions not granted.');
      }

      _downloader.configure(
          androidConfig: [(Config.useExternalStorage, Config.always)]);
      _downloader.configureNotification(
        running:
            TaskNotification('Downloading $audiobookTitle', 'File: {filename}'),
        progressBar: true,
        complete: TaskNotification(
            'Download complete: $audiobookTitle', 'File: {filename}'),
        error: TaskNotification(
            'Download error: $audiobookTitle', 'File: {filename}'),
      );

      if (_activeDownloads[audiobookId] == true) return;
      _activeDownloads[audiobookId] = true;

      final totalFiles = files.length;
      int completedFiles = 0;
      double totalProgress = 0.0;

      await downloadStatusBox.put('status_$audiobookId', {
        'isDownloading': true,
        'progress': 0.0,
        'isCompleted': false,
        'audiobookTitle': audiobookTitle,
        'audiobookId': audiobookId,
        'isYouTube': files.any((f) =>
            (f['url'] as String).contains('youtube.com') ||
            (f['url'] as String).contains('youtu.be')),
      });

      yt = YoutubeExplode();

      for (int i = 0; i < files.length; i++) {
        final fileData = files[i];
        if (_activeDownloads[audiobookId] != true) {
          await _cleanupPartialDownload(audiobookId);
          await downloadStatusBox.delete('status_$audiobookId');
          onCompleted(false);
          return;
        }

        final String fileTitle =
            fileData['title'] as String? ?? 'track_${i + 1}';
        final String fileName = '$fileTitle.mp3';
        final String url = fileData['url'] as String;
        final bool isYouTubeUrl =
            url.contains('youtube.com') || url.contains('youtu.be');
        
        // Get appropriate download directory based on Android version
        final downloadDirectory = await _getDownloadDirectory(audiobookId);
        String currentFileDirectoryPath = downloadDirectory.path;

        if (isYouTubeUrl) {
          File? outputFile;
          IOSink? fileStream;
          try {
            String? parsedVideoId = Uri.parse(url).queryParameters['v'] ??
                (url.contains('youtu.be/')
                    ? url.split('youtu.be/').last.split('?').first
                    : null);
            if (parsedVideoId == null) {
              throw Exception('Invalid YouTube URL: $url');
            }

            final manifest = await yt.videos.streams.getManifest(parsedVideoId,
                requireWatchPage: true,
                ytClients: [YoutubeApiClient.androidVr]);

            List<AudioOnlyStreamInfo> mp4AudioStreams = manifest.audioOnly
                .where((s) => s.container == StreamContainer.mp4)
                .sortByBitrate()
                .toList();

            AudioOnlyStreamInfo? audioStreamInfo = mp4AudioStreams.isNotEmpty
                ? mp4AudioStreams.last
                : manifest.audioOnly.withHighestBitrate();

            // Use the download directory we determined earlier
            outputFile = File('$currentFileDirectoryPath/$fileName');
            fileStream = outputFile.openWrite();

            final int totalBytesForFile = audioStreamInfo.size.totalBytes;
            int receivedBytesForFile = 0;

            audioStreamClient = AudioStreamClient();

            final bool useChunking = audioStreamInfo.isThrottled ||
                totalBytesForFile > _veryLargeFileThresholdBytes;

            final stream = audioStreamClient.getAudioStream(
              audioStreamInfo,
              start: 0,
              end: totalBytesForFile,
              isThrottledOrVeryLarge: useChunking,
            );

            await for (final data in stream) {
              if (_activeDownloads[audiobookId] != true) {
                await fileStream.close();
                if (await outputFile.exists()) await outputFile.delete();
                throw Exception('Download cancelled (YouTube)');
              }
              fileStream.add(data);
              receivedBytesForFile += data.length;
              double fileProgress = totalBytesForFile > 0
                  ? (receivedBytesForFile / totalBytesForFile)
                  : 0.0;
              totalProgress = (completedFiles + fileProgress) / totalFiles;
              onProgressUpdate(totalProgress);
              await downloadStatusBox.put('status_$audiobookId', {
                'isDownloading': true,
                'progress': totalProgress,
                'isCompleted': false,
                'audiobookTitle': audiobookTitle,
                'audiobookId': audiobookId,
                'isYouTube': true,
              });
            }
            await fileStream.flush();
            await fileStream.close();
            fileStream = null;
            
            // Move file to public directory if on Android 10+
            final moveSuccess = await _moveToPublicDirectory(outputFile, fileName, audiobookId);
            if (!moveSuccess) {
              throw Exception('Failed to move file to public directory: $fileName');
            }
            
            completedFiles++;
          } catch (e, s) {
            await fileStream?.close();
            _activeDownloads.remove(audiobookId);
            await downloadStatusBox.put('status_$audiobookId', {
              'isDownloading': false,
              'progress': totalProgress,
              'isCompleted': false,
              'error': 'File $fileName: ${e.toString()}',
              'audiobookTitle': audiobookTitle,
              'audiobookId': audiobookId,
              'isYouTube': true,
            });
            AppLogger.debug('YT Download Error: $e\n$s');
            await _cleanupPartialDownload(audiobookId);
            onCompleted(false);
            return;
          } finally {
            audioStreamClient?.close();
            audioStreamClient = null;
          }
        } else {
          final String uniqueFileTaskId =
              '$audiobookId-$i-${Uri.encodeComponent(fileTitle)}';
          
          // Get the actual download directory and configure task accordingly
          final downloadDirectory = await _getDownloadDirectory(audiobookId);
          
          // Use the full directory path with BaseDirectory.root for all Android versions
          final task = DownloadTask(
            taskId: uniqueFileTaskId,
            url: url,
            filename: fileName,
            directory: downloadDirectory.path,
            baseDirectory: BaseDirectory.root,
            updates: Updates.statusAndProgress,
            allowPause: true,
          );
          await downloadStatusBox.put('task_$uniqueFileTaskId', task.toJson());
          try {
            await _downloader.download(task, onProgress: (progress) {
              if (_activeDownloads[audiobookId] != true) {
                _downloader.cancelTaskWithId(task.taskId);
                throw Exception('Download cancelled (Direct URL)');
              }
              totalProgress = (completedFiles + progress) / totalFiles;
              onProgressUpdate(totalProgress);
              downloadStatusBox.put('status_$audiobookId', {
                'isDownloading': true,
                'progress': totalProgress,
                'isCompleted': false,
                'audiobookTitle': audiobookTitle,
                'audiobookId': audiobookId,
                'isYouTube': false,
              });
            }).then((result) async {
              if (result.status == TaskStatus.complete) {
                // Move file to public directory if on Android 10+
                if (await _isAndroid10OrHigher()) {
                  final tempFile = File('${downloadDirectory.path}/$fileName');
                  final moveSuccess = await _moveToPublicDirectory(tempFile, fileName, audiobookId);
                  if (!moveSuccess) {
                    throw Exception('Failed to move file to public directory: $fileName');
                  }
                }
                completedFiles++;
              } else if (result.status == TaskStatus.failed ||
                  result.status == TaskStatus.canceled) {
                throw Exception(
                    'Direct download ${result.status} for $fileName.');
              }
            });
          } catch (e) {
            _activeDownloads.remove(audiobookId);
            await downloadStatusBox.put('status_$audiobookId', {
              'isDownloading': false,
              'progress': totalProgress,
              'isCompleted': false,
              'error': 'File $fileName: ${e.toString()}',
              'audiobookTitle': audiobookTitle,
              'audiobookId': audiobookId,
              'isYouTube': false,
            });
            AppLogger.debug('Direct Download Error: $e');
            await _cleanupPartialDownload(audiobookId);
            onCompleted(false);
            return;
          }
        }
      }

      if (completedFiles == totalFiles) {
        // Move metadata files to public directory for Android 10+
        final metadataMoveSuccess = await _moveMetadataToPublicDirectory(audiobookId);
        if (!metadataMoveSuccess) {
          AppLogger.debug('Warning: Failed to move metadata files to public directory');
        }
        
        _activeDownloads.remove(audiobookId);
        await downloadStatusBox.put('status_$audiobookId', {
          'isDownloading': false,
          'progress': 1.0,
          'isCompleted': true,
          'audiobookTitle': audiobookTitle,
          'audiobookId': audiobookId,
          'downloadDate': DateTime.now().toIso8601String(),
          'isYouTube':
              downloadStatusBox.get('status_$audiobookId')?['isYouTube'] ??
                  false,
        });
        onCompleted(true);
      } else {
        _activeDownloads.remove(audiobookId);
        if (!downloadStatusBox.containsKey('status_$audiobookId') ||
            (downloadStatusBox.get('status_$audiobookId')?['error'] == null &&
                downloadStatusBox.get('status_$audiobookId')?['isCompleted'] ==
                    false)) {
          await downloadStatusBox.put('status_$audiobookId', {
            'isDownloading': false,
            'progress': totalProgress,
            'isCompleted': false,
            'error': 'Incomplete download.',
            'audiobookTitle': audiobookTitle,
            'audiobookId': audiobookId,
            'isYouTube':
                downloadStatusBox.get('status_$audiobookId')?['isYouTube'] ??
                    false,
          });
        }
        await _cleanupPartialDownload(audiobookId);
        onCompleted(false);
      }
    } catch (e) {
      _activeDownloads.remove(audiobookId);
      final existingStatus = downloadStatusBox.get('status_$audiobookId');
      if (existingStatus == null || existingStatus['error'] == null) {
        await downloadStatusBox.put('status_$audiobookId', {
          'isDownloading': false,
          'progress': existingStatus?['progress'] ?? 0.0,
          'isCompleted': false,
          'error': e.toString(),
          'audiobookTitle': audiobookTitle,
          'audiobookId': audiobookId,
          'isYouTube': existingStatus?['isYouTube'] ?? false,
        });
      }
      AppLogger.debug('General Download Error: $e');
      await _cleanupPartialDownload(audiobookId);
      onCompleted(false);
    } finally {
      yt?.close();
      _activeDownloads.remove(audiobookId);
    }
  }

  Future<void> _cleanupPartialDownload(String audiobookId) async {
    try {
      if (await _isAndroid10OrHigher()) {
        // Clean up temporary directory
        final tempDir = await getTemporaryDirectory();
        final downloadDir = Directory('${tempDir.path}/downloads/$audiobookId');
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      }
      
      // Always clean up public directory for both Android versions
      // This ensures complete cleanup regardless of Android version
      await _cleanupPublicDirectory(audiobookId);
    } catch (e) {
      AppLogger.debug('Cleanup Error: $e');
    }
  }

  /// Clean up the public Downloads/Aradia directory
  Future<void> _cleanupPublicDirectory(String audiobookId) async {
    try {
      final publicDir = Directory('/storage/emulated/0/Download/Aradia/$audiobookId');
      if (await publicDir.exists()) {
        await publicDir.delete(recursive: true);
        AppLogger.debug('Deleted public directory: ${publicDir.path}');
      }
    } catch (e) {
      AppLogger.debug('Error deleting public directory: $e');
    }
  }

  /// Delete a completed download and all its files
  /// This method can be called from UI to delete completed downloads
  Future<void> deleteDownload(String audiobookId) async {
    // Cancel any active downloads first
    if (_activeDownloads[audiobookId] == true) {
      cancelDownload(audiobookId);
      return;
    }
    
    // Clean up all directories and files
    await _cleanupPartialDownload(audiobookId);
    
    // Remove from status box
    await downloadStatusBox.delete('status_$audiobookId');
    
    // Remove any task entries
    for (var key in downloadStatusBox.keys.toList()) {
      if (key.toString().startsWith('task_$audiobookId-')) {
        await downloadStatusBox.delete(key);
      }
    }
    
    AppLogger.debug('Completely deleted download: $audiobookId');
  }

  void cancelDownload(String audiobookId) async {
    _activeDownloads.remove(audiobookId);
    for (var key in downloadStatusBox.keys.toList()) {
      if (key.toString().startsWith('task_$audiobookId-')) {
        final taskJson = downloadStatusBox.get(key);
        if (taskJson != null) {
          try {
            final task =
                DownloadTask.fromJson(taskJson as Map<String, dynamic>);
            await _downloader.cancelTaskWithId(task.taskId);
          } catch (e) {
            AppLogger.debug('Cancel Error: $e');
          }
        }
        await downloadStatusBox.delete(key);
      }
    }
    await _cleanupPartialDownload(audiobookId);
    await downloadStatusBox.delete('status_$audiobookId');
  }

  bool isDownloading(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return _activeDownloads[audiobookId] == true ||
        (status != null && status['isDownloading'] == true);
  }

  bool isDownloaded(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null && status['isCompleted'] == true;
  }

  double getProgress(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null
        ? (status['progress'] as num?)?.toDouble() ?? 0.0
        : 0.0;
  }

  String? getError(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null ? status['error'] as String? : null;
  }

  bool? isYouTubeDownload(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null ? status['isYouTube'] as bool? : null;
  }

  Future<void> pauseDownload(String uniqueFileTaskId) async {
    try {
      final taskJson = downloadStatusBox.get('task_$uniqueFileTaskId');
      if (taskJson != null) {
        final task = DownloadTask.fromJson(taskJson as Map<String, dynamic>);
        if (await _downloader.pause(task)) {}
      }
    } catch (e) {
      AppLogger.debug('Pause Error: $e');
    }
  }

  Future<void> resumeDownload(String uniqueFileTaskId) async {
    try {
      final taskJson = downloadStatusBox.get('task_$uniqueFileTaskId');
      if (taskJson != null) {
        final task = DownloadTask.fromJson(taskJson as Map<String, dynamic>);
        await _downloader.resume(task);
      }
    } catch (e) {
      AppLogger.debug('Resume Error: $e');
    }
  }

  List<String> getTaskIdsForAudiobook(String audiobookId) {
    List<String> ids = [];
    for (final key in downloadStatusBox.keys) {
      final keyString = key.toString();
      if (keyString.startsWith('task_$audiobookId-')) {
        ids.add(keyString.substring('task_'.length));
      }
    }
    return ids;
  }
}
