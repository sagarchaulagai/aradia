import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final FileDownloader _downloader = FileDownloader();
  final Box<dynamic> downloadStatusBox = Hive.box('download_status_box');
  final Map<String, bool> _activeDownloads = {};

  Future<bool> checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      // Check Android version
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13 and above
        final audio = await Permission.audio.status;
        if (audio.isDenied) {
          final result = await Permission.audio.request();
          return result.isGranted;
        }
        return audio.isGranted;
      } else if (sdkInt >= 30) {
        // Android 11 and 12
        final storage = await Permission.storage.status;
        final manageStorage = await Permission.manageExternalStorage.status;

        if (storage.isDenied) {
          await Permission.storage.request();
        }
        if (manageStorage.isDenied) {
          await Permission.manageExternalStorage.request();

          // Show dialog to guide user to enable all files access
          if (manageStorage.isDenied) {
            await openAppSettings();
          }
        }

        // Recheck permissions after requests
        final finalStorage = await Permission.storage.status;
        final finalManageStorage =
            await Permission.manageExternalStorage.status;

        return finalStorage.isGranted && finalManageStorage.isGranted;
      } else {
        // Android 10 and below
        final storage = await Permission.storage.status;
        if (storage.isDenied) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        return storage.isGranted;
      }
    }
    return true; // For non-Android platforms
  }

  Future<void> downloadAudiobook(
    String audiobookId,
    String audiobookTitle,
    List<Map<String, dynamic>> files,
    Function(double) onProgressUpdate,
    Function(bool) onCompleted,
  ) async {
    YoutubeExplode? yt;

    try {
      if (!await checkAndRequestPermissions()) {
        throw Exception(
            'Required storage permissions not granted. Please grant storage permissions in app settings.');
      }
      _downloader.configure(androidConfig: [
        (Config.useExternalStorage, Config.always),
      ]);
      _downloader.configureNotification(
        running: TaskNotification(
          'Downloading $audiobookTitle',
          'file: {filename}',
        ),
        progressBar: true,
      );

      if (_activeDownloads[audiobookId] == true) {
        return; // Already downloading
      }

      _activeDownloads[audiobookId] = true;

      final totalFiles = files.length;
      int completedFiles = 0;
      double totalProgress = 0;

      await downloadStatusBox.put('status_$audiobookId', {
        'isDownloading': true,
        'progress': 0.0,
        'isCompleted': false,
        'audiobookTitle': audiobookTitle,
        'audiobookId': audiobookId,
      });

      yt = YoutubeExplode();

      for (var file in files) {
        // Check if download was cancelled
        if (_activeDownloads[audiobookId] != true) {
          // Clean up any partially downloaded files
          await _cleanupPartialDownload(audiobookId);
          await downloadStatusBox.delete('status_$audiobookId');
          onCompleted(false);
          return;
        }

        final String fileName = '${file['title']}.mp3';
        final String url = file['url'];

        // Check if the URL is from YouTube
        final bool isYouTubeUrl =
            url.contains('youtube.com') || url.contains('youtu.be');

        if (isYouTubeUrl) {
          try {
            // Get application documents directory
            final appDir = await getExternalStorageDirectory();
            final String filePath = '${appDir?.path}/$audiobookId/$fileName';

            // Create directory if it doesn't exist
            final directory = Directory('${appDir?.path}/$audiobookId');
            if (!await directory.exists()) {
              await directory.create(recursive: true);
            }

            // Extract video ID from URL
            String? videoId;
            if (url.contains('youtube.com/watch?v=')) {
              videoId = Uri.parse(url).queryParameters['v'];
            } else if (url.contains('youtu.be/')) {
              videoId = url.split('youtu.be/')[1].split('?')[0];
            }

            if (videoId == null) {
              throw Exception('Invalid YouTube URL');
            }

            // Get the stream manifest - using the same parameters as in youtube_audio_service.dart
            final manifest = await yt.videos.streams.getManifest(videoId);

            // Get the audio stream with highest bitrate
            final audioStream = manifest.audioOnly.withHighestBitrate();

            // Create output file
            final outputFile = File(filePath);
            final fileStream = outputFile.openWrite();

            // Track download progress
            int totalBytes = audioStream.size.totalBytes;
            int receivedBytes = 0;

            // Download the stream using the correct method signature (stream, start, end)
            final stream = yt.videos.streams
                .get(audioStream, 0, audioStream.size.totalBytes);

            // Download and track progress
            await for (final data in stream) {
              // Check if download was cancelled
              if (_activeDownloads[audiobookId] != true) {
                await fileStream.close();
                throw Exception('Download cancelled');
              }

              fileStream.add(data);
              receivedBytes += data.length;

              // Calculate progress
              final progress = receivedBytes / totalBytes;
              totalProgress = (completedFiles + progress) / totalFiles;

              onProgressUpdate(totalProgress);
              await downloadStatusBox.put('status_$audiobookId', {
                'isDownloading': true,
                'progress': totalProgress,
                'isCompleted': false,
                'audiobookTitle': audiobookTitle,
                'audiobookId': audiobookId,
              });
            }

            await fileStream.flush();
            await fileStream.close();
            completedFiles++;
          } catch (e) {
            print('YouTube download error: $e');
            _activeDownloads.remove(audiobookId);
            await downloadStatusBox.put('status_$audiobookId', {
              'isDownloading': false,
              'progress': totalProgress,
              'isCompleted': false,
              'error': e.toString(),
              'audiobookTitle': audiobookTitle,
              'audiobookId': audiobookId,
            });
            onCompleted(false);
            return;
          }
        } else {
          // Handle direct URL downloads using background_downloader
          DownloadTask task = DownloadTask(
            taskId: audiobookId,
            url: url,
            filename: fileName,
            directory: audiobookId,
            baseDirectory: BaseDirectory.applicationDocuments,
            updates: Updates.statusAndProgress,
            allowPause: true,
          );

          // save this task to hive
          await downloadStatusBox.put('task_$audiobookId', task.toJson());

          try {
            final result = await _downloader.download(
              task,
              onProgress: (progress) {
                if (_activeDownloads[audiobookId] != true) {
                  throw Exception('Download cancelled');
                }
                totalProgress = (completedFiles + progress) / totalFiles;
                onProgressUpdate(totalProgress);
                downloadStatusBox.put('status_$audiobookId', {
                  'isDownloading': true,
                  'progress': totalProgress,
                  'isCompleted': false,
                  'audiobookTitle': audiobookTitle,
                  'audiobookId': audiobookId,
                });
              },
            );

            if (result.status == TaskStatus.complete) {
              completedFiles++;
            }
          } catch (e) {
            print('Download error: $e');
            _activeDownloads.remove(audiobookId);
            if (e.toString().contains('Download cancelled')) {
              await downloadStatusBox.delete('status_$audiobookId');
            } else {
              await downloadStatusBox.put('status_$audiobookId', {
                'isDownloading': false,
                'progress': totalProgress,
                'isCompleted': false,
                'error': e.toString(),
                'audiobookTitle': audiobookTitle,
                'audiobookId': audiobookId,
              });
            }
            onCompleted(false);
            return;
          }
        }
      }

      // Only mark as completed if all files were downloaded
      if (completedFiles == totalFiles) {
        _activeDownloads.remove(audiobookId);
        await downloadStatusBox.put('status_$audiobookId', {
          'isDownloading': false,
          'progress': 1.0,
          'isCompleted': true,
          'audiobookTitle': audiobookTitle,
          'audiobookId': audiobookId,
          'downloadDate': DateTime.now().toIso8601String(),
        });
        onCompleted(true);
      }
    } catch (e) {
      print('General download error: $e');
      _activeDownloads.remove(audiobookId);
      await downloadStatusBox.delete('status_$audiobookId');
      onCompleted(false);
    } finally {
      // Dispose YouTube client
      yt?.close();
    }
  }

  Future<void> _cleanupPartialDownload(String audiobookId) async {
    try {
      final appDir = await getExternalStorageDirectory();
      final downloadDir = Directory('${appDir?.path}/$audiobookId');
      if (await downloadDir.exists()) {
        await downloadDir.delete(recursive: true);
      }
    } catch (e) {
      print('Error cleaning up partial download: $e');
    }
  }

  void cancelDownload(String audiobookId) async {
    _activeDownloads.remove(audiobookId);
    _downloader.cancelTaskWithId(audiobookId);

    try {
      await _cleanupPartialDownload(audiobookId);
      // Ensure the status is removed from Hive
      await downloadStatusBox.delete('status_$audiobookId');
    } catch (e) {
      print('Error in cancelDownload: $e');
    }
  }

  bool isDownloading(String audiobookId) {
    return _activeDownloads[audiobookId] == true;
  }

  bool isDownloaded(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null && status['isCompleted'] == true;
  }

  double getProgress(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null ? (status['progress'] as double) : 0.0;
  }

  void pauseDownload(String audiobookId) async {
    try {
      final taskJson = downloadStatusBox.get('task_$audiobookId');
      if (taskJson != null) {
        final DownloadTask task = DownloadTask.fromJson(taskJson);
        final pauseResult = await _downloader.pause(task);
        if (pauseResult != TaskStatus.paused) {
          print('Failed to pause download: $audiobookId');
        }
      } else {
        print('No download task found for audiobookId: $audiobookId');
      }
    } catch (e) {
      print('Error pausing download for $audiobookId: $e');
    }
  }

  void resumeDownload(String audiobookId) async {
    try {
      final taskJson = downloadStatusBox.get('task_$audiobookId');
      if (taskJson != null) {
        final DownloadTask task = DownloadTask.fromJson(taskJson);
        final resumeResult = await _downloader.resume(task);
        if (resumeResult != TaskStatus.running) {
          print('Failed to resume download: $audiobookId');
        }
      } else {
        print('No download task found for audiobookId: $audiobookId');
      }
    } catch (e) {
      print('Error resuming download for $audiobookId: $e');
    }
  }
}
