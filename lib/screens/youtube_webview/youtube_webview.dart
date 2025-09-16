import 'dart:convert';
import 'dart:io';

import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/youtube/youtube_audiobook_notifier.dart';
import 'package:aradia/utils/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:aradia/utils/permission_helper.dart';

class YoutubeWebview extends StatefulWidget {
  const YoutubeWebview({super.key});

  @override
  State<YoutubeWebview> createState() => _YoutubeWebviewState();
}

class _YoutubeWebviewState extends State<YoutubeWebview> {
  String? _currentUrl;
  bool _isImporting = false;
  bool _isWebViewLoading = true;
  String? _errorMessageYT;
  late final WebViewController _webViewController;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'URLChanged',
        onMessageReceived: (msg) {
          setState(() {
            _currentUrl = msg.message;
          });
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) {
            setState(() {
              _isWebViewLoading = true;
            });
          }
        },
        onPageFinished: (_) {
          if (mounted) {
            setState(() {
              _isWebViewLoading = false;
            });
          }
          _webViewController.runJavaScript('''
            const pushState = history.pushState;
            history.pushState = function() {
              pushState.apply(this, arguments);
              URLChanged.postMessage(window.location.href);
            };
            window.addEventListener('popstate', function() {
              URLChanged.postMessage(window.location.href);
            });
            URLChanged.postMessage(window.location.href);
          ''');
        },
      ))
      ..loadRequest(Uri.parse('https://www.youtube.com'));
  }

  Future<void> _importFromYouTube() async {
    if (!mounted || _currentUrl == null) return;

    // maybe pause the video when clicking import button
    try {
      await _webViewController
          .runJavaScript("document.querySelector('video')?.pause();");
    } catch (_) {
      // Ignore if no video element found
    }

    if (!_currentUrl!.contains('youtube.com/watch') &&
        !_currentUrl!.contains('youtube.com/playlist')) {
      setState(() => _errorMessageYT =
          'Please navigate to a YouTube video or playlist page');
      return;
    }

    if (!await PermissionHelper.requestStorageAndMediaPermissions()) {
      setState(() => _errorMessageYT = 'Storage permission denied.');
      return;
    }

    setState(() {
      _isImporting = true;
      _errorMessageYT = null;
    });

    try {
      final yt = YoutubeExplode();
      List<AudiobookFile> files = [];
      String entityId;
      String entityTitle;
      String entityAuthor;
      String entityDescription;
      String? coverImage;
      List<String> tags = [];

      if (_currentUrl!.contains('playlist?list=')) {
        final playlist = await yt.playlists.get(_currentUrl!);
        entityId = playlist.id.value;
        entityTitle = playlist.title;
        entityAuthor = playlist.author;
        entityDescription = playlist.description;
        tags = _extractTags(playlist.description);

        final videos = await yt.playlists.getVideos(playlist.id).toList();
        if (videos.isEmpty) throw Exception("Playlist contains no videos.");

        coverImage = videos.first.thumbnails.highResUrl;

        for (var video in videos) {
          files.add(AudiobookFile.fromMap({
            "identifier": video.id.value,
            "title": video.title,
            "name": "${video.id.value}.mp3",
            "track": files.length + 1,
            "size": 0,
            "length": video.duration?.inSeconds.toDouble() ?? 0.0,
            "url": video.url,
            "highQCoverImage": video.thumbnails.highResUrl,
          }));
        }
      } else {
        final video = await yt.videos.get(_currentUrl!);
        entityId = video.id.value;
        entityTitle = video.title;
        entityAuthor = video.author;
        entityDescription = video.description;
        tags = _extractTags(video.description);
        coverImage = video.thumbnails.highResUrl;

        files.add(AudiobookFile.fromMap({
          "identifier": video.id.value,
          "title": video.title,
          "name": "${video.id.value}.mp3",
          "track": 1,
          "size": 0,
          "length": video.duration?.inSeconds.toDouble() ?? 0.0,
          "url": video.url,
          "highQCoverImage": video.thumbnails.highResUrl,
        }));
      }

      final audiobook = Audiobook.fromMap({
        "title": entityTitle,
        "id": entityId,
        "description": entityDescription,
        "author": entityAuthor,
        "date": DateTime.now().toIso8601String(),
        "downloads": 0,
        "subject": tags,
        "size": 0,
        "rating": 0.0,
        "reviews": 0,
        "lowQCoverImage": coverImage,
        "language": "en",
        "origin": AppConstants.youtubeDirName,
      });

      await _saveYouTubeAudiobookMetadata(audiobook, files);

      // Notify the YoutubeAudiobookNotifier about the new audiobook
      YoutubeAudiobookNotifier().addAudiobook(audiobook);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${_currentUrl!.contains('playlist') ? 'Playlist' : 'Video'} imported successfully!'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessageYT = 'Error importing from YouTube: $e');
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  List<String> _extractTags(String description) {
    final tags = <String>{};
    final words = description.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.startsWith('#') && word.length > 1) {
        final cleaned = word.substring(1).replaceAll(RegExp(r'[^\w-]'), '');
        if (cleaned.isNotEmpty) tags.add(cleaned);
      }
    }
    return tags.toList();
  }

  Future<void> _saveYouTubeAudiobookMetadata(
      Audiobook audiobook, List<AudiobookFile> files) async {
    final appDir = await getExternalStorageDirectory();
    if (appDir == null) throw Exception('Could not access storage directory');
    final audiobookDir = Directory(
        p.join(appDir.path, AppConstants.youtubeDirName, audiobook.id));
    await audiobookDir.create(recursive: true);

    final metadataFile = File(p.join(audiobookDir.path, 'audiobook.txt'));
    await metadataFile.writeAsString(jsonEncode(audiobook.toMap()));

    final filesFile = File(p.join(audiobookDir.path, 'files.txt'));
    await filesFile
        .writeAsString(jsonEncode(files.map((f) => f.toJson()).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'YouTube Import',
          style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          if (_errorMessageYT != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12.0),
              color: theme.colorScheme.error.withValues(alpha: 0.1),
              child: Text(
                _errorMessageYT!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _webViewController),
                if (_isWebViewLoading)
                  Container(
                    color: theme.scaffoldBackgroundColor,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Loading YouTube...',
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _currentUrl != null &&
              (_currentUrl!.contains('youtube.com/watch') ||
                  _currentUrl!.contains('youtube.com/playlist'))
          ? FloatingActionButton.extended(
              onPressed: _isImporting ? null : _importFromYouTube,
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              icon: _isImporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(_isImporting ? 'Importing...' : 'Import Audio'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
