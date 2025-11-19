import 'dart:io';
import 'package:aradia/utils/app_logger.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/utils/permission_helper.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final FileDownloader _downloader = FileDownloader();
  final Box<dynamic> downloadStatusBox = Hive.box('download_status_box');
  final Map<String, bool> _activeDownloads = {};

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
    try {
      // Check notification permissions - download will work without them, but no notifications
      final hasNotificationPermission = await checkAndRequestPermissions();

      _downloader.configure(
          androidConfig: [(Config.useExternalStorage, Config.always)]);

      // Only configure notifications if we have permission
      if (hasNotificationPermission) {
        _downloader.configureNotification(
          running: TaskNotification(
              'Downloading $audiobookTitle', 'File: {filename}'),
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
      });

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
        String currentFileDirectoryPath = 'downloads/$audiobookId';

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
          }).then((result) {
            if (result.status == TaskStatus.complete) {
              completedFiles++;
            } else if (result.status == TaskStatus.failed ||
                result.status == TaskStatus.canceled) {
              throw Exception('Download ${result.status} for $fileName.');
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
          });
          AppLogger.debug('Download Error: $e');
          await _cleanupPartialDownload(audiobookId);
          onCompleted(false);
          return;
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
        });
      }
      AppLogger.debug('General Download Error: $e');
      await _cleanupPartialDownload(audiobookId);
      onCompleted(false);
    } finally {
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
