import 'dart:io';
import 'package:aradia/resources/services/youtube/stream_client.dart';
import 'package:aradia/utils/app_logger.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:aradia/utils/permission_helper.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final FileDownloader _downloader = FileDownloader();
  final Box<dynamic> downloadStatusBox = Hive.box('download_status_box');
  final Map<String, bool> _activeDownloads = {};

  static const int _veryLargeFileThresholdBytes = 50 * 1024 * 1024;

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
      // Check notification permissions - download will work without them, but no notifications
      final hasNotificationPermission = await checkAndRequestPermissions();

      _downloader.configure(
          androidConfig: [(Config.useExternalStorage, Config.always)]);
      
      // Only configure notifications if we have permission
      if (hasNotificationPermission) {
        _downloader.configureNotification(
          running:
              TaskNotification('Downloading $audiobookTitle', 'File: {filename}'),
          progressBar: true,
          complete: TaskNotification(
              'Download complete: $audiobookTitle', 'File: {filename}'),
          error: TaskNotification(
              'Download error: $audiobookTitle', 'File: {filename}'),
        );
      }

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
        String currentFileDirectoryPath = 'downloads/$audiobookId';

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

            final appDocDir = await getExternalStorageDirectory();
            final fullDirectoryPath =
                Directory('${appDocDir?.path}/$currentFileDirectoryPath');
            if (!await fullDirectoryPath.exists()) {
              await fullDirectoryPath.create(recursive: true);
            }

            outputFile = File('${fullDirectoryPath.path}/$fileName');
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
          DownloadTask task = DownloadTask(
            taskId: uniqueFileTaskId,
            url: url,
            filename: fileName,
            directory: currentFileDirectoryPath,
            baseDirectory: BaseDirectory.applicationDocuments,
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
            }).then((result) {
              if (result.status == TaskStatus.complete) {
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
      final baseDir = await getExternalStorageDirectory();
      final downloadDir = Directory('${baseDir?.path}/downloads/$audiobookId');
      if (await downloadDir.exists()) {
        await downloadDir.delete(recursive: true);
      }
    } catch (e) {
      AppLogger.debug('Cleanup Error: $e');
    }
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
