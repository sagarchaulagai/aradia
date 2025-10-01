import 'dart:convert';
import 'dart:io';

import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:aradia/resources/services/youtube/youtube_audiobook_notifier.dart';
import 'package:aradia/resources/services/youtube/webview_keep_alive_provider.dart';
import 'package:aradia/utils/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
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
  bool _isWebViewLoading = true; // Still defaults to true
  String? _errorMessageYT;
  bool _isCurrentContentImported = false;
  InAppWebViewController? _webViewController;
  late final YoutubeAudiobookNotifier _audioBookNotifier;

  @override
  void initState() {
    super.initState();
    _audioBookNotifier = YoutubeAudiobookNotifier();
    _audioBookNotifier.addListener(_onAudiobookListChanged);
  }

  @override
  void dispose() {
    _audioBookNotifier.removeListener(_onAudiobookListChanged);
    super.dispose();
  }

  void _onAudiobookListChanged() {
    if (mounted) {
      _checkIfCurrentContentIsImported();
    }
  }

  void _checkIfCurrentContentIsImported() {
    if (_currentUrl == null) {
      _isCurrentContentImported = false;
      return;
    }

    try {
      String? entityId;

      if (_currentUrl!.contains('playlist?list=')) {
        final uri = Uri.parse(_currentUrl!);
        entityId = uri.queryParameters['list'];
      } else if (_currentUrl!.contains('youtube.com/watch')) {
        final uri = Uri.parse(_currentUrl!);
        entityId = uri.queryParameters['v'];
      }

      if (entityId != null) {
        final wasImported = _isCurrentContentImported;
        _isCurrentContentImported =
            _audioBookNotifier.isAudiobookAlreadyImported(entityId);

        if (wasImported != _isCurrentContentImported) {
          setState(() {});
        }
      } else {
        _isCurrentContentImported = false;
      }
    } catch (e) {
      _isCurrentContentImported = false;
    }
  }

  Future<void> _importFromYouTube() async {
    if (!mounted || _currentUrl == null) return;
    // Lets not pause the video , we can add this feature in the future if needed
    // try {
    //   await _webViewController?.evaluateJavascript(
    //       source: "document.querySelector('video')?.pause();");
    // } catch (_) {
    //   // Ignore if no video element found
    // }

    if (!_currentUrl!.contains('youtube.com/watch') &&
        !_currentUrl!.contains('youtube.com/playlist')) {
      setState(() => _errorMessageYT =
          'Please navigate to a YouTube video or playlist page');
      return;
    }
    // No need for permission, uses externalstorage
    // if (!await PermissionHelper.requestStorageAndMediaPermissions()) {
    //   setState(() => _errorMessageYT = 'Storage permission denied.');
    //   return;
    // }

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

        if (_isCurrentContentImported) {
          return;
        }

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

        if (_isCurrentContentImported) {
          return;
        }

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
      YoutubeAudiobookNotifier().addAudiobook(audiobook);
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
      // appBar: AppBar(
      //   title: Text(
      //     'YouTube Import',
      //     style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold),
      //   ),
      //   centerTitle: true,
      // ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_errorMessageYT != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Card(
                    elevation: 2,
                    color: theme.colorScheme.error.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessageYT!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      keepAlive: Provider.of<WebViewKeepAliveProvider>(context,
                              listen: false)
                          .keepAlive,
                      initialUrlRequest:
                          URLRequest(url: WebUri('https://www.youtube.com')),
                      onWebViewCreated: (controller) async {
                        _webViewController = controller;

                        final url = await controller.getUrl();

                        if (url != null && url.toString() != 'about:blank') {
                          if (mounted) {
                            setState(() {
                              _currentUrl = url.toString();
                              _isWebViewLoading = false;
                              _checkIfCurrentContentIsImported();
                            });
                          }
                        }
                      },
                      onLoadStart: (controller, url) {
                        if (mounted) {
                          setState(() {
                            _isWebViewLoading = true;
                          });
                        }
                      },
                      onLoadStop: (controller, url) {
                        if (mounted) {
                          setState(() {
                            _isWebViewLoading = false;
                            _currentUrl = url.toString();
                            _checkIfCurrentContentIsImported();
                          });
                        }
                      },
                      onUpdateVisitedHistory:
                          (controller, url, androidIsReload) {
                        if (mounted && url != null) {
                          setState(() {
                            _currentUrl = url.toString();
                            _checkIfCurrentContentIsImported();
                          });
                        }
                      },
                    ),
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
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FutureBuilder<bool>(
            future: _webViewController?.canGoBack() ?? Future.value(false),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return FloatingActionButton(
                  heroTag: 'back',
                  mini: true,
                  backgroundColor:
                      AppColors.primaryColor.withValues(alpha: 0.8),
                  onPressed: () => _webViewController?.goBack(),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          if (_currentUrl != null &&
              (_currentUrl!.contains('youtube.com/watch') ||
                  _currentUrl!.contains('youtube.com/playlist')))
            const SizedBox(width: 8),
          if (_currentUrl != null &&
              (_currentUrl!.contains('youtube.com/watch') ||
                  _currentUrl!.contains('youtube.com/playlist')))
            FloatingActionButton(
              heroTag: 'import',
              backgroundColor: AppColors.primaryColor,
              onPressed: _isImporting
                  ? null
                  : _isCurrentContentImported
                      ? () => context.go('/home')
                      : _importFromYouTube,
              child: _isImporting
                  ? const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    )
                  : _isCurrentContentImported
                      ? const Icon(Icons.visibility, color: Colors.white)
                      : const Icon(Icons.download_outlined,
                          color: Colors.white),
            ),
        ],
      ),
    );
  }
}
