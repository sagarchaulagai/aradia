import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/low_and_high_image.dart';

class ImportAudiobookScreen extends StatefulWidget {
  const ImportAudiobookScreen({super.key});

  @override
  State<ImportAudiobookScreen> createState() => _ImportAudiobookScreenState();
}

class _ImportAudiobookScreenState extends State<ImportAudiobookScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  List<Audiobook> _importedAudiobooks = [];

  @override
  void initState() {
    super.initState();
    _loadImportedAudiobooks();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadImportedAudiobooks() async {
    try {
      final appDir = await getExternalStorageDirectory();
      final importedDir = Directory('${appDir?.path}/youtube');

      if (await importedDir.exists()) {
        final directories = await importedDir
            .list()
            .where((entity) => entity is Directory)
            .toList();
        final audiobooks = <Audiobook>[];

        for (var dir in directories) {
          final audiobookFile = File('${dir.path}/audiobook.txt');
          if (await audiobookFile.exists()) {
            final content = await audiobookFile.readAsString();
            final audiobookData = jsonDecode(content) as Map<String, dynamic>;

            audiobooks.add(Audiobook.fromMap(audiobookData));
          }
        }

        setState(() {
          _importedAudiobooks = audiobooks;
        });
      }
    } catch (e) {
      print('Error loading imported audiobooks: $e');
    }
  }

  Future<void> _importFromYouTube() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Please enter a YouTube URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final yt = YoutubeExplode();
      List<AudiobookFile> files = [];
      String playlistId = '';
      String playlistTitle = '';
      String playlistAuthor = '';
      String playlistDescription = '';

      if (url.contains('playlist')) {
        final playlist = await yt.playlists.get(url);
        playlistId = playlist.id.value;
        playlistTitle = playlist.title;
        playlistAuthor = playlist.author;
        playlistDescription = playlist.description;

        final videos = await yt.playlists.getVideos(playlist.id).toList();
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
        final videoId = VideoId(url);
        final video = await yt.videos.get(videoId);
        playlistId = video.id.value;
        playlistTitle = video.title;
        playlistAuthor = video.author;
        playlistDescription = video.description;

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
        "title": playlistTitle,
        "id": playlistId,
        "description": playlistDescription,
        "author": playlistAuthor,
        "date": DateTime.now().toIso8601String(),
        "downloads": 0,
        "subject": [
          "YouTube ${url.contains('playlist') ? 'Playlist' : 'Video'}"
        ],
        "size": 0,
        "rating": 0.0,
        "reviews": 0,
        "lowQCoverImage": files[0].highQCoverImage,
        "language": "en",
        "origin": "youtube",
      });

      await _saveAudiobook(audiobook, files);
      setState(() {
        _importedAudiobooks.add(audiobook);
        _urlController.clear();
      });

      // Close the keyboard
      FocusScope.of(context).unfocus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${url.contains('playlist') ? 'Playlist' : 'Video'} imported successfully!'),
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error importing: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAudiobook(
      Audiobook audiobook, List<AudiobookFile> files) async {
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      throw Exception('Storage permission not granted');
    }

    final appDir = await getExternalStorageDirectory();
    final audiobookDir = Directory('${appDir?.path}/youtube/${audiobook.id}');
    await audiobookDir.create(recursive: true);

    final metadataFile = File('${audiobookDir.path}/audiobook.txt');
    await metadataFile.writeAsString(jsonEncode(audiobook.toMap()));

    final filesFile = File('${audiobookDir.path}/files.txt');
    await filesFile
        .writeAsString(jsonEncode(files.map((f) => f.toJson()).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import from YouTube'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube URL (Video or Playlist)',
                    hintText:
                        'https://www.youtube.com/watch?v=... or https://www.youtube.com/playlist?list=...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _importFromYouTube,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Import'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _importedAudiobooks.isEmpty
                ? const Center(
                    child: Text('No imported audiobooks yet'),
                  )
                : ListView.builder(
                    itemCount: _importedAudiobooks.length,
                    itemBuilder: (context, index) {
                      final audiobook = _importedAudiobooks[index];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LowAndHighImage(
                            lowQImage: audiobook.lowQCoverImage,
                            highQImage: audiobook.lowQCoverImage,
                            height: 50,
                            width: 50,
                          ),
                        ),
                        title: Text(
                          audiobook.title,
                          style: GoogleFonts.ubuntu(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          audiobook.author ?? 'Unknown Author',
                          style: GoogleFonts.ubuntu(
                            fontSize: 14,
                          ),
                        ),
                        onTap: () {
                          context.push(
                            '/audiobook-details',
                            extra: {
                              'audiobook': audiobook,
                              'isDownload': false,
                              'isYoutube': true,
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
