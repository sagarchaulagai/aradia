import 'dart:io';
import 'package:aradia/resources/services/stream_client.dart';
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
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        // Android 13+
        var photos = await Permission.photos.status;
        var audio = await Permission.audio.status;
        var videos = await Permission.videos.status;

        if (photos.isDenied || audio.isDenied || videos.isDenied) {
          final results = await [
            Permission.photos,
            Permission.audio,
            Permission.videos,
          ].request();
          return results.values.every((status) => status.isGranted);
        }
        return photos.isGranted && audio.isGranted && videos.isGranted;
      } else if (sdkInt >= 30) {
        // Android 11 and 12
        final storage = await Permission.storage.status;
        final manageStorage = await Permission.manageExternalStorage.status;

        if (storage.isDenied) {
          await Permission.storage.request();
        }
        if (manageStorage.isDenied) {
          await Permission.manageExternalStorage.request();
          if (await Permission.manageExternalStorage.status.isDenied) {
            // Check again after request
            await openAppSettings(); // Guide user if still denied
          }
        }
        return await Permission.storage.status.isGranted &&
            await Permission.manageExternalStorage.status.isGranted;
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
    return true; // For non-Android platforms (e.g., iOS if supported)
  }

  Future<void> downloadAudiobook(
    String audiobookId,
    String audiobookTitle,
    List<Map<String, dynamic>> files,
    Function(double) onProgressUpdate,
    Function(bool) onCompleted,
  ) async {
    YoutubeExplode? yt;
    AudioStreamClient? audioStreamClient; // For YouTube downloads

    try {
      if (!await checkAndRequestPermissions()) {
        throw Exception(
            'Required storage permissions not granted. Please grant permissions in app settings.');
      }

      // Configure background_downloader (primarily for direct URLs)
      _downloader.configure(androidConfig: [
        (Config.useExternalStorage, Config.always),
      ]);
      _downloader.configureNotification(
        running: TaskNotification(
          'Downloading $audiobookTitle',
          'File: {filename}', // Use {filename} for individual file name
        ),
        progressBar: true,
        // Add completed and error notifications for direct downloads if desired
        complete: TaskNotification(
            'Download complete: $audiobookTitle', 'File: {filename}'),
        error: TaskNotification(
            'Download error: $audiobookTitle', 'File: {filename}'),
      );

      if (_activeDownloads[audiobookId] == true) {
        print('Audiobook $audiobookId is already being downloaded.');
        // onCompleted(false); // Or handle as you see fit, maybe just return
        return;
      }

      _activeDownloads[audiobookId] = true;

      final totalFiles = files.length;
      int completedFiles = 0;
      double totalProgress = 0.0; // Overall progress for the audiobook

      await downloadStatusBox.put('status_$audiobookId', {
        'isDownloading': true,
        'progress': 0.0,
        'isCompleted': false,
        'audiobookTitle': audiobookTitle,
        'audiobookId': audiobookId,
      });

      yt = YoutubeExplode(); // Initialize for YouTube metadata

      for (int i = 0; i < files.length; i++) {
        final fileData = files[i];
        // Check if download was cancelled before processing this file
        if (_activeDownloads[audiobookId] != true) {
          print(
              'Download cancelled for audiobook $audiobookId before processing all files.');
          // Cleanup is handled by cancelDownload or if an error occurs later
          await _cleanupPartialDownload(
              audiobookId); // Ensure cleanup on premature exit
          await downloadStatusBox.delete('status_$audiobookId');
          onCompleted(false);
          return;
        }

        final String fileTitle = fileData['title'] ?? 'track_${i + 1}';
        final String fileName = '$fileTitle.mp3';
        final String url = fileData['url'];

        final bool isYouTubeUrl =
            url.contains('youtube.com') || url.contains('youtu.be');

        String currentFileDirectoryPath = 'downloads/$audiobookId';
        String currentFilePathWithoutBase =
            '$currentFileDirectoryPath/$fileName';

        if (isYouTubeUrl) {
          File? outputFile;
          IOSink? fileStream;

          try {
            String? parsedVideoId;
            if (url.contains('youtube.com/watch?v=')) {
              parsedVideoId = Uri.parse(url).queryParameters['v'];
            } else if (url.contains('youtu.be/')) {
              parsedVideoId = url.split('youtu.be/').last.split('?').first;
            }

            print('DEBUG: Parsed Video ID: $parsedVideoId from URL: $url');
            if (parsedVideoId == null) {
              throw Exception(
                  'Invalid YouTube URL (could not parse Video ID): $url');
            }

            if (yt == null) {
              print(
                  'DEBUG: CRITICAL - yt instance is null before getManifest!');
              throw Exception('YoutubeExplode instance (yt) is null.');
            }

            print('DEBUG: Getting manifest for $parsedVideoId...');
            final manifest = await yt.videos.streams.getManifest(parsedVideoId,
                requireWatchPage: true,
                ytClients: [YoutubeApiClient.androidVr]);
            print(
                'DEBUG: Manifest retrieved for $parsedVideoId. Raw audioOnly count: ${manifest.audioOnly.length}');

            // --- APPLY FILTERING SIMILAR TO GYAWUN ---
            List<AudioOnlyStreamInfo> mp4AudioStreams = manifest.audioOnly
                .where((stream) => stream.container == StreamContainer.mp4)
                .sortByBitrate() // Sorts ascending by bitrate
                .toList();

            print(
                'DEBUG: Filtered MP4 audio streams count: ${mp4AudioStreams.length}');

            AudioOnlyStreamInfo? audioStreamInfo; // Make it nullable initially
            if (mp4AudioStreams.isNotEmpty) {
              // Gyawun has a quality setting; here we'll take the highest bitrate MP4
              audioStreamInfo = mp4AudioStreams.last;
              print('DEBUG: Selected highest bitrate MP4 stream.');
            } else {
              print(
                  'DEBUG: No MP4 audio streams found for $parsedVideoId. Falling back to manifest.audioOnly.withHighestBitrate().');
              // Fallback: try the original method if no MP4s are found (less preferred)
              audioStreamInfo = manifest.audioOnly.withHighestBitrate();
              if (audioStreamInfo != null) {
                print(
                    'DEBUG: Fallback selected a stream with container: ${audioStreamInfo.container.name}');
              }
            }
            // --- END OF FILTERING ---

            print(
                'DEBUG: 최종 선택된 audioStreamInfo 객체: ${audioStreamInfo == null ? "NULL" : "NOT NULL"}');
            if (audioStreamInfo != null) {
              print(
                  'DEBUG: 선택된 audioStreamInfo 상세: Container=${audioStreamInfo.container.name}, URL=${audioStreamInfo.url}, Size Obj=${audioStreamInfo.size}, Bitrate=${audioStreamInfo.bitrate}');
            }

            if (audioStreamInfo == null) {
              print(
                  'DEBUG: audioStreamInfo IS NULL after filtering/selection for $parsedVideoId. Throwing custom error.');
              throw Exception(
                  'No suitable audio stream found (MP4 or fallback) for YouTube video: $parsedVideoId.');
            }

            // --- AGGRESSIVE NULL CHECKS ON audioStreamInfo PROPERTIES ---
            if (audioStreamInfo.url == null) {
              // Should not happen for a valid StreamInfo
              print(
                  'DEBUG: CRITICAL - audioStreamInfo.url is NULL for $parsedVideoId');
              throw Exception(
                  'Audio stream info for $parsedVideoId has a null URL.');
            }
            if (audioStreamInfo.size == null) {
              print(
                  'DEBUG: CRITICAL - audioStreamInfo.size (the Size object itself) is NULL for $parsedVideoId');
              throw Exception(
                  'Audio stream info for $parsedVideoId has a null size object.');
            }
            // totalBytes is an int, not nullable itself, but accessed via .size
            print(
                'DEBUG: audioStreamInfo.size.totalBytes value: ${audioStreamInfo.size.totalBytes}');
            // --- END OF AGGRESSIVE CHECKS ---

            print(
                'DEBUG: audioStreamInfo seems valid for $parsedVideoId. Proceeding. Size in bytes: ${audioStreamInfo.size.totalBytes}');

            final appDocDir = await getApplicationDocumentsDirectory();
            final fullDirectoryPath =
                Directory('${appDocDir.path}/$currentFileDirectoryPath');
            final fullFilePath = '${fullDirectoryPath.path}/$fileName';

            if (!await fullDirectoryPath.exists()) {
              await fullDirectoryPath.create(recursive: true);
            }
            outputFile = File(fullFilePath);
            fileStream = outputFile.openWrite();

            final int totalBytesForFile =
                audioStreamInfo.size.totalBytes; // Should be safe now
            int receivedBytesForFile = 0;

            print('DEBUG: Initializing AudioStreamClient for $parsedVideoId');
            audioStreamClient = AudioStreamClient();
            print(
                'DEBUG: Calling audioStreamClient.getAudioStream for $parsedVideoId');
            final stream = audioStreamClient.getAudioStream(
              audioStreamInfo, // audioStreamInfo and its .url/.size should be confirmed non-null
              start: 0,
              end: totalBytesForFile,
            );
            print(
                'DEBUG: Stream received from AudioStreamClient for $parsedVideoId. Starting download loop...');

            await for (final data in stream) {
              // ... (rest of your streaming logic) ...
              if (_activeDownloads[audiobookId] != true) {
                await fileStream?.close();
                if (outputFile != null && await outputFile.exists())
                  await outputFile.delete();
                print(
                    'DEBUG: Download cancelled during streaming for $fileName');
                throw Exception(
                    'Download cancelled during YouTube streaming for $fileName');
              }
              fileStream.add(data);
              receivedBytesForFile += data.length;

              double fileProgress = (totalBytesForFile > 0)
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
              });
            }

            print(
                'DEBUG: YouTube file download completed for $fileName. Flushing and closing stream.');
            await fileStream.flush();
            await fileStream.close();
            fileStream = null;
            completedFiles++;
          } catch (e, s) {
            print(
                'YouTube download error for $audiobookId, file $fileName: $e');
            print('Stack trace: $s'); // <<<< THIS IS VERY IMPORTANT
            await fileStream?.close();
            _activeDownloads.remove(audiobookId);

            await downloadStatusBox.put('status_$audiobookId', {
              'isDownloading': false,
              'progress': totalProgress,
              'isCompleted': false,
              'error': 'File $fileName: ${e.toString()}',
              'audiobookTitle': audiobookTitle,
              'audiobookId': audiobookId,
            });
            await _cleanupPartialDownload(audiobookId);
            onCompleted(false);
            return;
          }
        } else {
          // --- Direct URL Download Logic ---
          // For multiple direct files, taskId should be unique per file for background_downloader
          // Current implementation uses audiobookId, which might only work well for a single direct file.
          final String uniqueFileTaskId =
              '$audiobookId-$i-${Uri.encodeComponent(fileTitle)}'; // More unique task ID

          DownloadTask task = DownloadTask(
            taskId: uniqueFileTaskId, // Use a unique ID per file
            url: url,
            filename: fileName,
            directory: currentFileDirectoryPath, // Relative to base directory
            baseDirectory: BaseDirectory
                .applicationDocuments, // Or getExternalStorageDirectory()
            updates: Updates.statusAndProgress,
            allowPause: true,
          );

          // Store task info for potential pause/resume, using uniqueFileTaskId
          await downloadStatusBox.put('task_$uniqueFileTaskId', task.toJson());

          try {
            await _downloader.download(
              task,
              onProgress: (progress) {
                // This progress is for the current file (0.0 to 1.0)
                if (_activeDownloads[audiobookId] != true) {
                  _downloader.cancelTaskWithId(
                      task.taskId); // Cancel this specific task
                  throw Exception(
                      'Download cancelled for direct file $fileName');
                }
                double fileProgress = progress;
                totalProgress = (completedFiles + fileProgress) / totalFiles;
                onProgressUpdate(totalProgress);
                downloadStatusBox.put('status_$audiobookId', {
                  'isDownloading': true,
                  'progress': totalProgress,
                  'isCompleted': false,
                  'audiobookTitle': audiobookTitle,
                  'audiobookId': audiobookId,
                });
              },
              // onStatus: (status) { // Optional: handle status changes for direct downloads
              //   if (status == TaskStatus.failed || status == TaskStatus.canceled) {
              //      // Error handling for this specific file might be needed here
              //   }
              // }
            ).then((result) async {
              if (result.status == TaskStatus.complete) {
                completedFiles++;
              } else if (result.status == TaskStatus.failed ||
                  result.status == TaskStatus.canceled) {
                // This specific file failed or was cancelled.
                throw Exception(
                    'Direct download failed or was cancelled for $fileName. Status: ${result.status}');
              }
            });
          } catch (e) {
            print('Direct download error for $audiobookId, file $fileName: $e');
            _activeDownloads.remove(audiobookId);

            if (e.toString().contains('Download cancelled')) {
              // If cancelled, status box for audiobook might be deleted by cancelDownload later.
              // Or, we might want to just update the general status to reflect cancellation.
              await downloadStatusBox.put('status_$audiobookId', {
                'isDownloading': false,
                'progress': totalProgress,
                'isCompleted': false,
                'error': 'Download cancelled for $fileName',
                'audiobookTitle': audiobookTitle,
                'audiobookId': audiobookId,
              });
            } else {
              await downloadStatusBox.put('status_$audiobookId', {
                'isDownloading': false,
                'progress': totalProgress,
                'isCompleted': false,
                'error': 'File $fileName: ${e.toString()}',
                'audiobookTitle': audiobookTitle,
                'audiobookId': audiobookId,
              });
            }
            await _cleanupPartialDownload(
                audiobookId); // Clean up entire audiobook dir
            onCompleted(false);
            return; // Stop processing further files
          }
        }
      } // End of for loop for files

      // If all files processed successfully
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
        // This case should ideally be caught by errors within the loop
        // If we reach here and not all files are completed, it's an unexpected state
        print(
            "Download ended but not all files completed. Completed: $completedFiles, Total: $totalFiles");
        _activeDownloads.remove(audiobookId);
        if (!downloadStatusBox.containsKey('status_$audiobookId') ||
            (downloadStatusBox.get('status_$audiobookId')['error'] == null &&
                downloadStatusBox.get('status_$audiobookId')['isCompleted'] ==
                    false)) {
          // If no specific error was recorded, mark as a generic failure
          await downloadStatusBox.put('status_$audiobookId', {
            'isDownloading': false,
            'progress': totalProgress,
            'isCompleted': false,
            'error': 'Incomplete download, not all files processed.',
            'audiobookTitle': audiobookTitle,
            'audiobookId': audiobookId,
          });
        }
        await _cleanupPartialDownload(audiobookId);
        onCompleted(false);
      }
    } catch (e) {
      // General errors (e.g., permission issues, initial setup)
      print('General download error for audiobook $audiobookId: $e');
      _activeDownloads.remove(audiobookId);
      // Ensure status reflects error, or delete if it was just a "downloading" state
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
      await _cleanupPartialDownload(
          audiobookId); // Clean up on general errors too
      onCompleted(false);
    } finally {
      yt?.close(); // Close YouTube client if it was initialized
      // audioStreamClient doesn't have an explicit close method in the provided snippet
      _activeDownloads.remove(audiobookId); // Ensure it's cleared on any exit
    }
  }

  Future<void> _cleanupPartialDownload(String audiobookId) async {
    try {
      // Determine base directory consistently
      final baseDir =
          await getApplicationDocumentsDirectory(); // Or getExternalStorageDirectory()
      final downloadDir = Directory('${baseDir.path}/downloads/$audiobookId');

      if (await downloadDir.exists()) {
        await downloadDir.delete(recursive: true);
        print('Cleaned up partial download directory: ${downloadDir.path}');
      }
    } catch (e) {
      print('Error cleaning up partial download for $audiobookId: $e');
    }
  }

  void cancelDownload(String audiobookId) async {
    print('Attempting to cancel download for audiobook: $audiobookId');
    _activeDownloads.remove(audiobookId); // Signal active downloads to stop

    // Attempt to cancel background_downloader tasks associated with this audiobookId
    // This requires iterating through potential task IDs if they are per-file
    // For simplicity, if task IDs were more complex (e.g., audiobookId-index),
    // you'd need a way to find all related tasks.
    // Here, we assume we might have stored tasks like 'task_audiobookId-0-title'
    // Or, if only one direct download task was expected per audiobookId with 'task_audiobookId':
    // final taskJson = downloadStatusBox.get('task_$audiobookId');
    // if (taskJson != null) {
    //   final task = DownloadTask.fromJson(taskJson);
    //   _downloader.cancelTaskWithId(task.taskId);
    // }
    // More robust: iterate keys if multiple direct download tasks per audiobook
    for (var key in downloadStatusBox.keys) {
      if (key.toString().startsWith('task_$audiobookId-')) {
        final taskJson = downloadStatusBox.get(key);
        if (taskJson != null) {
          try {
            final task = DownloadTask.fromJson(
                taskJson as Map<String, dynamic>); // Cast if necessary
            await _downloader.cancelTaskWithId(task.taskId);
            print('Cancelled background_downloader task: ${task.taskId}');
          } catch (e) {
            print('Error parsing or cancelling task $key: $e');
          }
        }
      }
    }

    await _cleanupPartialDownload(audiobookId);
    await downloadStatusBox
        .delete('status_$audiobookId'); // Remove main status entry
    // Also remove individual task entries from Hive for direct downloads
    for (var key in List.from(downloadStatusBox.keys)) {
      // List.from to avoid concurrent modification
      if (key.toString().startsWith('task_$audiobookId-')) {
        await downloadStatusBox.delete(key);
      }
    }
    print('Download cancelled and cleaned up for audiobook: $audiobookId');
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
    return status != null ? (status['progress'] as double? ?? 0.0) : 0.0;
  }

  String? getError(String audiobookId) {
    final status = downloadStatusBox.get('status_$audiobookId');
    return status != null ? (status['error'] as String?) : null;
  }

  // Pause/Resume only work for background_downloader tasks (direct URLs)
  // And they need the *specific file's task ID*.
  // The methods below are simplified and would need adjustment if an audiobook has multiple direct files.
  // They assume 'task_$audiobookId' stores a single relevant task, which is not
  // the case with the `uniqueFileTaskId` change for multiple direct files.
  // For a robust pause/resume of individual direct files, you'd need to pass the specific file's unique ID.

  Future<void> pauseDownload(String uniqueFileTaskId) async {
    // Now expects unique file task ID
    try {
      final taskJson = downloadStatusBox.get('task_$uniqueFileTaskId');
      if (taskJson != null) {
        final DownloadTask task =
            DownloadTask.fromJson(taskJson as Map<String, dynamic>);
        final pauseResult = await _downloader.pause(task);
        if (pauseResult) {
          // pause method now returns bool
          print('Download paused: $uniqueFileTaskId');
          // Update Hive status for the main audiobook if needed
        } else {
          print('Failed to pause download: $uniqueFileTaskId');
        }
      } else {
        print('No download task found for task ID: $uniqueFileTaskId');
      }
    } catch (e) {
      print('Error pausing download for $uniqueFileTaskId: $e');
    }
  }

  Future<void> resumeDownload(String uniqueFileTaskId) async {
    // Now expects unique file task ID
    try {
      final taskJson = downloadStatusBox.get('task_$uniqueFileTaskId');
      if (taskJson != null) {
        final DownloadTask task =
            DownloadTask.fromJson(taskJson as Map<String, dynamic>);
        final resumeResult = await _downloader.resume(task);
        if (resumeResult) {
          // resume method now returns bool
          print('Download resumed: $uniqueFileTaskId');
          // Update Hive status for the main audiobook if needed
        } else {
          print('Failed to resume download: $uniqueFileTaskId');
        }
      } else {
        print('No download task found for task ID: $uniqueFileTaskId');
      }
    } catch (e) {
      print('Error resuming download for $uniqueFileTaskId: $e');
    }
  }

  // Helper to get all task IDs for an audiobook (if needed by UI for pause/resume)
  List<String> getTaskIdsForAudiobook(String audiobookId) {
    List<String> ids = [];
    for (var key in downloadStatusBox.keys) {
      if (key.toString().startsWith('task_$audiobookId-')) {
        ids.add(key.toString());
      }
    }
    return ids;
  }
}
