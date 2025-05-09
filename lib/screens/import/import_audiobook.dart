import 'dart:convert';
import 'dart:io';
import 'dart:math'; // For Random and min
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/screens/import/edit_audiobook_screen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; // For picking local cover
import 'package:aradia/widgets/low_and_high_image.dart'; // Your LowAndHighImage widget

const String _youtubeDirName = 'youtube';
const String _localDirName = 'local';
const String _coverFileName = 'cover.jpg'; // Standardized cover name

const List<String> _supportedAudioExtensions = [
  '.mp3',
  '.m4a',
  '.aac',
  '.wav',
  '.ogg',
  '.opus',
  '.flac',
];

// Model for Google Books search results
class GoogleBookResult {
  final String id;
  final String title;
  final String authors;
  final String? description;
  final String? thumbnailUrl;

  GoogleBookResult({
    required this.id,
    required this.title,
    required this.authors,
    this.description,
    this.thumbnailUrl,
  });

  factory GoogleBookResult.fromJson(Map<String, dynamic> json) {
    final volumeInfo = json['volumeInfo'] as Map<String, dynamic>? ?? {};
    return GoogleBookResult(
      id: json['id'] as String? ?? '',
      title: volumeInfo['title'] as String? ?? 'No Title',
      authors: (volumeInfo['authors'] as List<dynamic>?)?.join(', ') ??
          'Unknown Author',
      description: volumeInfo['description'] as String?,
      thumbnailUrl: (volumeInfo['imageLinks']
              as Map<String, dynamic>?)?['thumbnail'] as String? ??
          (volumeInfo['imageLinks'] as Map<String, dynamic>?)?['smallThumbnail']
              as String?,
    );
  }
}

class ImportAudiobookScreen extends StatefulWidget {
  const ImportAudiobookScreen({super.key});

  @override
  State<ImportAudiobookScreen> createState() => _ImportAudiobookScreenState();
}

class _ImportAudiobookScreenState extends State<ImportAudiobookScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  File? _pickedLocalCoverFile; // For locally picked cover
  String? _selectedGBooksCoverUrl; // For cover URL from selected Google Book

  bool _isLoading = false;
  String? _errorMessageYT;
  String? _errorMessageLocal;

  List<Audiobook> _importedAudiobooks = [];
  late TabController _tabController;
  List<File> _selectedFiles = [];
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && mounted) {
        setState(() {
          _errorMessageYT = null;
          _errorMessageLocal = null;
          if (_tabController.index != 1) {
            // Potentially clear local tab specific fields if desired when navigating away
            // TODO : Maybe Implement this, I will see it later
            // _clearLocalImportFields(clearTextControllers: false);
          }
        });
      }
      if (!_tabController.indexIsChanging &&
          _tabController.index == 2 &&
          mounted) {
        _loadImportedAudiobooks();
      }
    });
    _requestPermissionsAndLoad();
  }

  Future<void> _requestPermissionsAndLoad() async {
    bool granted = await _requestStoragePermission();
    if (granted) {
      await _loadImportedAudiobooks();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission is required.')),
        );
      }
    }
  }

  Future<bool> _requestStoragePermission() async {
    // Requesting general storage permission. For Android 10 (API 29) and below.
    // For Android 11+ (API 30+), direct file path access needs manageExternalStorage or SAF.
    // getExternalStorageDirectory() gives app-specific external dir, which is fine.
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    // If targeting Android 13+ for photo picker
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+
        var photoStatus = await Permission.photos.status;
        if (!photoStatus.isGranted)
          photoStatus = await Permission.photos.request();
        return status.isGranted && photoStatus.isGranted;
      }
    }
    return status.isGranted;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // --- Cover Handling ---
  Future<void> _pickCoverImageFromGallery() async {
    try {
      final XFile? image =
          await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        setState(() {
          _pickedLocalCoverFile = File(image.path);
          _selectedGBooksCoverUrl =
              null; // Local pick overrides GBooks for cover
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    }
  }

  Widget _buildCoverPreview(ThemeData theme) {
    final isLightMode = theme.brightness == Brightness.light;
    Widget placeholder = Container(
      height: 120,
      width: 120,
      decoration: BoxDecoration(
        color: isLightMode ? AppColors.cardColorLight : AppColors.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isLightMode
                ? AppColors.dividerColorLight.withValues(alpha: 0.5)
                : AppColors.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Icon(Icons.photo_size_select_actual_outlined,
          size: 50,
          color: isLightMode ? AppColors.iconColorLight : AppColors.iconColor),
    );

    if (_pickedLocalCoverFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(_pickedLocalCoverFile!,
            height: 120, width: 120, fit: BoxFit.cover),
      );
    } else if (_selectedGBooksCoverUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        // Using Image.network for preview, actual LowAndHighImage is for library display
        child: Image.network(
          _selectedGBooksCoverUrl!,
          height: 120,
          width: 120,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => placeholder,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
                height: 120,
                width: 120,
                child: Center(
                    child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                )));
          },
        ),
      );
    }
    return placeholder;
  }

  Future<String?> _saveCoverImageToAppDirectory(
      String audiobookId, Directory appDocDir) async {
    final audiobookDir =
        Directory(p.join(appDocDir.path, _localDirName, audiobookId));
    if (!await audiobookDir.exists()) {
      await audiobookDir.create(recursive: true);
    }
    final localCoverPath = p.join(audiobookDir.path, _coverFileName);

    try {
      if (_pickedLocalCoverFile != null) {
        await _pickedLocalCoverFile!.copy(localCoverPath);
        return localCoverPath;
      } else if (_selectedGBooksCoverUrl != null) {
        final response = await http.get(Uri.parse(_selectedGBooksCoverUrl!));
        if (response.statusCode == 200) {
          await File(localCoverPath).writeAsBytes(response.bodyBytes);
          return localCoverPath;
        } else {
          print(
              'Failed to download Google Books cover: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('Error saving cover image: $e');
    }
    return null; // No cover saved or error
  }

  // --- UI and Logic for Tabs ---
  void _showAudiobookActions(
      BuildContext context, Audiobook audiobook, ThemeData theme) {
    final isLightMode = theme.brightness == Brightness.light;
    showModalBottomSheet(
      context: context,
      backgroundColor:
          isLightMode ? AppColors.cardColorLight : AppColors.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading:
                    Icon(Icons.edit_outlined, color: AppColors.primaryColor),
                title: Text('Edit Metadata',
                    style: GoogleFonts.ubuntu(
                        color: isLightMode
                            ? AppColors.textColor
                            : AppColors.darkTextColor)),
                onTap: () async {
                  Navigator.pop(bc);
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          EditAudiobookScreen(audiobook: audiobook),
                    ),
                  );
                  if (result == true && mounted) {
                    _loadImportedAudiobooks();
                  }
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: AppColors.primaryColor),
                title: Text('Delete Audiobook',
                    style: GoogleFonts.ubuntu(color: AppColors.primaryColor)),
                onTap: () {
                  Navigator.pop(bc);
                  _deleteAudiobook(audiobook);
                },
              ),
              ListTile(
                leading: Icon(Icons.cancel_outlined,
                    color: isLightMode
                        ? AppColors.iconColorLight
                        : AppColors.iconColor),
                title: Text('Cancel',
                    style: GoogleFonts.ubuntu(
                        color: isLightMode
                            ? AppColors.iconColorLight
                            : AppColors.iconColor)),
                onTap: () {
                  Navigator.pop(bc);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadImportedAudiobooks() async {
    if (!mounted) return;
    if (!await _requestStoragePermission()) {
      if (mounted)
        setState(() => _errorMessageLocal = 'Storage permission denied.');
      return;
    }

    setState(() => _isLoading = true);
    final List<Audiobook> loadedAudiobooks = [];
    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) {
        if (mounted)
          setState(() => _errorMessageLocal = 'Could not access storage.');
        return;
      }

      Future<void> loadFromSource(String sourceDirName) async {
        final sourceDir = Directory(p.join(appDir.path, sourceDirName));
        if (await sourceDir.exists()) {
          final entities = sourceDir.list();
          await for (final entity in entities) {
            if (entity is Directory) {
              final audiobookFile = File(p.join(entity.path, 'audiobook.txt'));
              if (await audiobookFile.exists()) {
                try {
                  final content = await audiobookFile.readAsString();
                  final audiobookData =
                      jsonDecode(content) as Map<String, dynamic>;
                  if (!audiobookData.containsKey('origin') ||
                      audiobookData['origin'] == null) {
                    audiobookData['origin'] = sourceDirName;
                  }
                  // Ensure lowQCoverImage is an absolute path if it's a local file
                  if (audiobookData['lowQCoverImage'] != null &&
                      !(audiobookData['lowQCoverImage'] as String)
                          .startsWith('http') &&
                      (audiobookData['lowQCoverImage'] as String).isNotEmpty) {
                    // Check if it's already absolute, if not, construct it
                    if (!p.isAbsolute(audiobookData['lowQCoverImage'])) {
                      audiobookData['lowQCoverImage'] =
                          p.join(entity.path, audiobookData['lowQCoverImage']);
                    }
                  }

                  if (audiobookData['id'] != null &&
                      audiobookData['title'] != null) {
                    loadedAudiobooks.add(Audiobook.fromMap(audiobookData));
                  } else {
                    print(
                        'Skipping corrupted audiobook.txt in ${entity.path}: Missing id or title');
                  }
                } catch (e) {
                  print(
                      'Error decoding audiobook.txt in ${entity.path} ($sourceDirName): $e');
                }
              }
            }
          }
        }
      }

      await loadFromSource(_youtubeDirName);
      await loadFromSource(_localDirName);

      loadedAudiobooks.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      if (mounted) {
        setState(() {
          _importedAudiobooks = loadedAudiobooks;
        });
      }
    } catch (e) {
      print('Error loading imported audiobooks: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading library: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _generateRandomId() {
    // ... (same as previous version)
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(10, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  Future<void> _pickAudioFiles() async {
    // ... (same as _pickFiles in previous version)
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result != null && mounted) {
        setState(() {
          _selectedFiles.addAll(result.files
              .where((file) => file.path != null)
              .map((file) => File(file.path!)));
          _errorMessageLocal = null;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() => _errorMessageLocal = 'Error picking audio files: $e');
    }
  }

  Future<void> _pickAudioFolder() async {
    // ... (same as _pickFolder in previous version)
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null && mounted) {
        final newFiles = <File>[];
        Directory(result).listSync(recursive: false).forEach((entity) {
          if (entity is File &&
              _supportedAudioExtensions
                  .any((ext) => entity.path.toLowerCase().endsWith(ext))) {
            newFiles.add(entity);
          }
        });
        setState(() {
          _selectedFiles.addAll(newFiles);
          _errorMessageLocal = null;
          if (newFiles.isEmpty) {
            _errorMessageLocal =
                'No supported audio files found in the selected folder.';
          }
        });
      }
    } catch (e) {
      if (mounted)
        setState(() => _errorMessageLocal = 'Error picking audio folder: $e');
    }
  }

  Future<void> _fetchAndSelectFromGoogleBooks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    String query = _titleController.text.trim();
    if (_authorController.text.trim().isNotEmpty) {
      query += " inauthor:${_authorController.text.trim()}";
    }

    if (query.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a title to search.')),
        );
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final url = Uri.parse(
          'https://www.googleapis.com/books/v1/volumes?q=${Uri.encodeComponent(query)}&maxResults=5&printType=books&fields=items(id,volumeInfo/title,volumeInfo/authors,volumeInfo/description,volumeInfo/imageLinks)');
      final response = await http.get(url);
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          final List<GoogleBookResult> results = (data['items'] as List)
              .map((item) =>
                  GoogleBookResult.fromJson(item as Map<String, dynamic>))
              .toList();

          // Show dialog to select a book
          final GoogleBookResult? selectedBook =
              await showDialog<GoogleBookResult>(
            context: context,
            builder: (context) => _GoogleBooksSelectionDialog(results: results),
          );

          if (selectedBook != null && mounted) {
            setState(() {
              _titleController.text = selectedBook.title;
              _authorController.text = selectedBook.authors;
              _descriptionController.text = selectedBook.description ?? '';
              _selectedGBooksCoverUrl = selectedBook.thumbnailUrl;
              _pickedLocalCoverFile =
                  null; // GBooks selection overrides local file for cover
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No results found on Google Books.')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Google Books Error: ${response.statusCode}')));
      }
    } catch (e) {
      print("Google Books API error: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching from Google Books: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importFromLocal() async {
    if (!mounted) return;
    if (_selectedFiles.isEmpty) {
      setState(
          () => _errorMessageLocal = 'Please select at least one audio file.');
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      setState(() => _errorMessageLocal = 'Please enter a title.');
      return;
    }
    if (!await _requestStoragePermission()) {
      setState(() => _errorMessageLocal = 'Storage permission denied.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessageLocal = null;
    });

    try {
      final appDocDir = await getExternalStorageDirectory();
      if (appDocDir == null) throw Exception("Cannot get app directory");

      final audiobookId = _generateRandomId();

      // Save cover first to get its local path
      final String? localCoverFinalPath =
          await _saveCoverImageToAppDirectory(audiobookId, appDocDir);

      final files = _selectedFiles.asMap().entries.map((entry) {
        final file = entry.value;
        return AudiobookFile.fromMap({
          "identifier": "${audiobookId}_${entry.key}",
          "title": p.basenameWithoutExtension(file.path),
          "name": p.basename(file.path),
          "track": entry.key + 1,
          "size": file.lengthSync(),
          "length": 0.0,
          "url": p.basename(file.path),
          "highQCoverImage": "",
        });
      }).toList();

      final audiobook = Audiobook.fromMap({
        "title": _titleController.text.trim(),
        "id": audiobookId,
        "description": _descriptionController.text.trim(),
        "author": _authorController.text.trim().isNotEmpty
            ? _authorController.text.trim()
            : "Unknown Artist",
        "date": DateTime.now().toIso8601String(),
        "downloads": 0,
        "subject": [],
        "size": files.fold<int>(0, (sum, file) => sum + (file.size ?? 0)),
        "rating": 0.0,
        "reviews": 0,
        "lowQCoverImage": localCoverFinalPath ?? "",
        "language": "en",
        "origin": _localDirName,
      });

      // Save metadata and copy audio files
      await _saveAudiobookFilesAndMetadata(
          audiobook, files, _selectedFiles, appDocDir);

      if (mounted) {
        await _loadImportedAudiobooks();
        _clearLocalImportFields();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audiobook imported successfully!')));
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted)
        setState(() => _errorMessageLocal = 'Error importing from local: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAudiobookFilesAndMetadata(
      Audiobook audiobook,
      List<AudiobookFile> fileMetadata,
      List<File> sourceFiles,
      Directory appDocDir) async {
    final audiobookDir = Directory(
        p.join(appDocDir.path, audiobook.origin!, audiobook.id)); // Use origin
    // audiobookDir should already exist if cover was saved, but ensure it.
    if (!await audiobookDir.exists()) {
      await audiobookDir.create(recursive: true);
    }

    // Note: cover image is already saved by _saveCoverImageToAppDirectory
    // The audiobook.lowQCoverImage already has the correct local absolute path or is empty.

    final metadataFile = File(p.join(audiobookDir.path, 'audiobook.txt'));
    await metadataFile.writeAsString(jsonEncode(audiobook.toMap()));

    final filesFile = File(p.join(audiobookDir.path, 'files.txt'));
    await filesFile.writeAsString(
        jsonEncode(fileMetadata.map((f) => f.toJson()).toList()));

    for (int i = 0; i < sourceFiles.length; i++) {
      final sourceFile = sourceFiles[i];
      final targetFileName = fileMetadata[i].name;
      final newFile = File(p.join(audiobookDir.path, targetFileName));
      await sourceFile.copy(newFile.path);
    }
  }

  void _clearLocalImportFields({bool clearTextControllers = true}) {
    if (clearTextControllers) {
      _titleController.clear();
      _authorController.clear();
      _descriptionController.clear();
    }
    if (mounted) {
      setState(() {
        _selectedFiles.clear();
        _pickedLocalCoverFile = null;
        _selectedGBooksCoverUrl = null;
        _errorMessageLocal = null;
      });
    }
  }

  Future<void> _importFromYouTube() async {
    if (!mounted) return;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessageYT = 'Please enter a YouTube URL');
      return;
    }
    if (!await _requestStoragePermission()) {
      setState(() => _errorMessageYT = 'Storage permission denied.');
      return;
    }

    setState(() {
      _isLoading = true;
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

      if (url.contains('playlist?list=')) {
        final playlist = await yt.playlists.get(url);
        entityId = playlist.id.value;
        entityTitle = playlist.title;
        entityAuthor = playlist.author;
        entityDescription = playlist.description;
        tags = _extractTags(playlist.description);

        final videos = await yt.playlists.getVideos(playlist.id).toList();
        if (videos.isEmpty) throw Exception("Playlist contains no videos.");

        coverImage = videos.first.thumbnails.maxResUrl;

        for (var video in videos) {
          files.add(AudiobookFile.fromMap({
            "identifier": video.id.value,
            "title": video.title,
            "name": "${video.id.value}.mp3",
            "track": files.length + 1,
            "size": 0,
            "length": video.duration?.inSeconds.toDouble() ?? 0.0,
            "url": video.url,
            "highQCoverImage": video.thumbnails.maxResUrl,
          }));
        }
      } else {
        final videoId = VideoId(url);
        if (videoId == null)
          throw FormatException("Invalid YouTube video URL or ID format.");

        final video = await yt.videos.get(videoId);
        entityId = video.id.value;
        entityTitle = video.title;
        entityAuthor = video.author;
        entityDescription = video.description;
        tags = _extractTags(video.description);
        coverImage = video.thumbnails.maxResUrl;

        files.add(AudiobookFile.fromMap({
          "identifier": video.id.value,
          "title": video.title,
          "name": "${video.id.value}.mp3",
          "track": 1,
          "size": 0,
          "length": video.duration?.inSeconds.toDouble() ?? 0.0,
          "url": video.url,
          "highQCoverImage": video.thumbnails.maxResUrl,
        }));
      }

      final audiobook = Audiobook.fromMap({
        "title": entityTitle, "id": entityId, "description": entityDescription,
        "author": entityAuthor, "date": DateTime.now().toIso8601String(),
        "downloads": 0, "subject": tags, "size": 0, "rating": 0.0, "reviews": 0,
        "lowQCoverImage": coverImage ??
            files.firstOrNull?.highQCoverImage ??
            "", // This remains URL
        "language": "en", "origin": _youtubeDirName,
      });

      await _saveYouTubeAudiobookMetadata(
          audiobook, files); // This saves metadata with URL cover
      if (mounted) {
        await _loadImportedAudiobooks();
        _urlController.clear();
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${url.contains('playlist') ? 'Playlist' : 'Video'} metadata imported!')));
        _tabController.animateTo(0);
      }
    } on FormatException catch (e) {
      if (mounted)
        setState(() => _errorMessageYT = 'Invalid YouTube URL: ${e.message}');
    } catch (e) {
      if (mounted)
        setState(() => _errorMessageYT = 'Error importing from YouTube: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> _extractTags(String description) {
    /* ... same ... */
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
    // ... (same, saves audiobook.txt with URL cover)
    final appDir = await getExternalStorageDirectory();
    if (appDir == null) throw Exception('Could not access storage directory');
    final audiobookDir =
        Directory(p.join(appDir.path, _youtubeDirName, audiobook.id));
    await audiobookDir.create(recursive: true);

    final metadataFile = File(p.join(audiobookDir.path, 'audiobook.txt'));
    await metadataFile.writeAsString(jsonEncode(audiobook.toMap()));

    final filesFile = File(p.join(audiobookDir.path, 'files.txt'));
    await filesFile
        .writeAsString(jsonEncode(files.map((f) => f.toJson()).toList()));
  }

  Future<void> _deleteAudiobook(Audiobook audiobook) async {
    if (!mounted) return;
    if (!await _requestStoragePermission()) {
      return;
    }
    bool confirmDelete = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            final theme = Theme.of(context);
            final isLightMode = theme.brightness == Brightness.light;
            return AlertDialog(
              backgroundColor:
                  isLightMode ? AppColors.cardColorLight : AppColors.cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: Text('Confirm Delete',
                  style: TextStyle(
                      color: isLightMode
                          ? AppColors.textColor
                          : AppColors.darkTextColor)),
              content: Text(
                  'Are you sure you want to delete "${audiobook.title}"? This will remove its files from your device.',
                  style: TextStyle(
                      color: isLightMode
                          ? AppColors.subtitleTextColorLight
                          : AppColors.listTileSubtitleColor)),
              actions: <Widget>[
                TextButton(
                  child: Text('Cancel',
                      style: TextStyle(color: AppColors.primaryColor)),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: Text('Delete',
                      style: TextStyle(color: AppColors.primaryColor)),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmDelete) return;
    setState(() => _isLoading = true);
    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) throw Exception('Could not access storage directory');
      final audiobookDir = Directory(
          p.join(appDir.path, audiobook.origin ?? _localDirName, audiobook.id));
      if (await audiobookDir.exists()) {
        await audiobookDir.delete(recursive: true);
      }
      if (mounted) {
        await _loadImportedAudiobooks();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${audiobook.title}" deleted.')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error deleting: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;
    final textFieldFillColor = isLightMode
        ? AppColors.lightOrange
        : theme.cardTheme.color ?? AppColors.cardColor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Import Audiobook',
            style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.ubuntu(fontWeight: FontWeight.w500),
          unselectedLabelStyle: GoogleFonts.ubuntu(),
          indicatorColor: AppColors.primaryColor,
          labelColor: AppColors.primaryColor,
          unselectedLabelColor: isLightMode
              ? AppColors.iconColorLight.withValues(alpha: 0.6)
              : AppColors.iconColor.withValues(alpha: 0.6),
          tabs: const [
            Tab(text: 'My Library', icon: Icon(Ionicons.library_outline)),
            Tab(text: 'Local', icon: Icon(Ionicons.folder_open_outline)),
            Tab(text: 'Youtube', icon: Icon(Ionicons.logo_youtube)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildLibraryTab(theme),
          _buildLocalImportTab(theme, textFieldFillColor),
          _buildYouTubeImportTab(theme, textFieldFillColor),
        ],
      ),
    );
  }

  Widget _buildTextFieldWidget(
      {required TextEditingController controller,
      required String labelText,
      String? hintText,
      required IconData prefixIcon,
      int maxLines = 1,
      required ThemeData theme,
      required Color fillColor}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(prefixIcon,
            color: theme.inputDecorationTheme.prefixIconColor ??
                theme.colorScheme.onSurfaceVariant),
        border: theme.inputDecorationTheme.border ?? const OutlineInputBorder(),
        enabledBorder: theme.inputDecorationTheme.enabledBorder,
        focusedBorder: theme.inputDecorationTheme.focusedBorder,
        filled: true,
        fillColor: fillColor,
        labelStyle: theme.inputDecorationTheme.labelStyle,
        hintStyle: theme.inputDecorationTheme.hintStyle,
      ),
      style: TextStyle(color: theme.colorScheme.onSurface),
      maxLines: maxLines,
    );
  }

  Widget _buildYouTubeImportTab(ThemeData theme, Color textFieldFillColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildTextFieldWidget(
                    controller: _urlController,
                    labelText: 'YouTube URL (Video or Playlist)',
                    hintText: 'e.g., https://www.youtube.com/watch?v=...',
                    prefixIcon: Icons.link,
                    theme: theme,
                    fillColor: textFieldFillColor,
                  ),
                  const SizedBox(height: 12),
                  if (_errorMessageYT != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(_errorMessageYT!,
                          style: TextStyle(
                              color: theme.colorScheme.error, fontSize: 13)),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonColor,
                    ),
                    onPressed: _isLoading ? null : _importFromYouTube,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryColor,
                            ),
                          )
                        : const Icon(
                            Icons.cloud_download_outlined,
                            color: Colors.white,
                          ),
                    label: Text(
                      _isLoading ? 'Importing...' : 'Import Metadata',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLocalImportTab(ThemeData theme, Color textFieldFillColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Import from Local Files',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontFamily: GoogleFonts.ubuntu().fontFamily)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _buildCoverPreview(theme)),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppColors.primaryColor,
                    ),
                    label: Text(
                      'Pick Cover Image',
                      style: TextStyle(
                        color: AppColors.primaryColor,
                      ),
                    ),
                    onPressed: _isLoading ? null : _pickCoverImageFromGallery,
                  ),
                  const SizedBox(height: 16),
                  _buildTextFieldWidget(
                      controller: _titleController,
                      labelText: 'Audiobook Title*',
                      prefixIcon: Icons.title_outlined,
                      theme: theme,
                      fillColor: textFieldFillColor),
                  const SizedBox(height: 12),
                  _buildTextFieldWidget(
                      controller: _authorController,
                      labelText: 'Author',
                      prefixIcon: Icons.person_outline,
                      theme: theme,
                      fillColor: textFieldFillColor),
                  const SizedBox(height: 12),
                  _buildTextFieldWidget(
                      controller: _descriptionController,
                      labelText: 'Description',
                      prefixIcon: Icons.description_outlined,
                      maxLines: 3,
                      theme: theme,
                      fillColor: textFieldFillColor),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed:
                        _isLoading ? null : _fetchAndSelectFromGoogleBooks,
                    icon: _isLoading &&
                            (_titleController.text.isNotEmpty ||
                                _authorController.text.isNotEmpty)
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onSecondary))
                        : const Icon(Icons.manage_search_outlined),
                    label: const Text('Fetch Info (Google Books)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.buttonColor,
                      foregroundColor: theme.colorScheme.onSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _pickAudioFiles,
                      icon: const Icon(Icons.attach_file_outlined),
                      label: const Text('Select Files'),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryColor),
                          foregroundColor: AppColors.primaryColor),
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _pickAudioFolder,
                      icon: const Icon(Icons.folder_copy_outlined),
                      label: const Text('Select Folder'),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryColor),
                          foregroundColor: AppColors.primaryColor),
                    )),
                  ]),
                ],
              ),
            ),
          ),
          if (_selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                'Selected Audio Files (${_selectedFiles.length}):',
              ),
            ),
            const SizedBox(height: 8),
            Card(
              color: theme.brightness == Brightness.light
                  ? AppColors.cardColorLight
                  : AppColors.cardColor,
              elevation: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 150,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _selectedFiles.length,
                  itemBuilder: (context, index) {
                    final file = _selectedFiles[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.audiotrack_outlined,
                      ),
                      title: Text(p.basename(file.path),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: theme.brightness == Brightness.light
                                  ? AppColors.textColor
                                  : AppColors.listTileTitleColor)),
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle_outline,
                            color:
                                theme.colorScheme.error.withValues(alpha: 0.8)),
                        onPressed: () {
                          if (mounted)
                            setState(() => _selectedFiles.removeAt(index));
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_errorMessageLocal != null)
            Padding(
              /* Error Message */
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(_errorMessageLocal!,
                  style:
                      TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.buttonColor,
            ),
            onPressed:
                _isLoading || _selectedFiles.isEmpty ? null : _importFromLocal,
            icon: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                  )
                : Icon(
                    Icons.system_update_alt_outlined,
                    color: theme.brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
            label: Text(
              _isLoading ? 'Importing...' : 'Import Audiobook',
              style: TextStyle(
                color: theme.brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLibraryTab(ThemeData theme) {
    final bool isLight = theme.brightness == Brightness.light;
    return Column(
      children: [
        Padding(
          /* Header */
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 8.0, 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Audiobooks (${_importedAudiobooks.length})',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontFamily: GoogleFonts.ubuntu().fontFamily)),
              IconButton(
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: AppColors.primaryColor,
                  ),
                  tooltip: 'Refresh Library',
                  onPressed: _isLoading ? null : _loadImportedAudiobooks),
            ],
          ),
        ),
        if (_isLoading && _importedAudiobooks.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_importedAudiobooks.isEmpty)
          Expanded(
            /* Empty State */
            child: Center(
              child: Opacity(
                  opacity: 0.7,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.library_books_outlined,
                            size: 60,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text('No audiobooks imported yet.',
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontFamily: GoogleFonts.ubuntu().fontFamily,
                                color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Text('Use the tabs above to import audiobooks.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.8)),
                            textAlign: TextAlign.center),
                      ])),
            ),
          )
        else
          Expanded(
            // Library List
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
              itemCount: _importedAudiobooks.length,
              itemBuilder: (context, index) {
                final audiobook = _importedAudiobooks[index];
                Widget coverWidget;
                if (audiobook.lowQCoverImage.startsWith('http')) {
                  coverWidget = LowAndHighImage(
                      lowQImage: audiobook.lowQCoverImage,
                      highQImage: audiobook
                          .lowQCoverImage, // Or a different highQ field
                      height: 60,
                      width: 60);
                } else if (audiobook.lowQCoverImage.isNotEmpty) {
                  final coverFile = File(audiobook.lowQCoverImage);
                  // Note: File.existsSync() is synchronous and i think its okay here,
                  // but for very long lists or performance critical UI, we should consider async checks.
                  // TODO : I will later see if we can use async checks.
                  if (coverFile.existsSync()) {
                    coverWidget = Image.file(
                      coverFile,
                      height: 60,
                      width: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) =>
                          _defaultCoverPlaceholder(theme, 60, 60),
                    );
                  } else {
                    coverWidget = _defaultCoverPlaceholder(theme, 60, 60);
                  }
                } else {
                  coverWidget = _defaultCoverPlaceholder(theme, 60, 60);
                }

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(
                      vertical: 5.0, horizontal: 8.0),
                  color:
                      isLight ? AppColors.cardColorLight : AppColors.cardColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8.0, horizontal: 12.0),
                    leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: coverWidget),
                    title: Text(audiobook.title,
                        style: GoogleFonts.ubuntu(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isLight
                                ? AppColors.textColor
                                : AppColors.darkTextColor),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(audiobook.author ?? 'Unknown Author',
                        style: GoogleFonts.ubuntu(
                            fontSize: 14,
                            color: (isLight
                                    ? AppColors.subtitleTextColorLight
                                    : AppColors.listTileSubtitleColor)
                                .withValues(alpha: 0.9)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onLongPress: () =>
                        _showAudiobookActions(context, audiobook, theme),
                    onTap: () => context.push('/audiobook-details', extra: {
                      'audiobook': audiobook,
                      'isDownload': false,
                      'isYoutube': audiobook.origin == _youtubeDirName,
                      'isLocal': audiobook.origin == _localDirName,
                    }),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _defaultCoverPlaceholder(
      ThemeData theme, double height, double width) {
    final isLightMode = theme.brightness == Brightness.light;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: isLightMode ? AppColors.cardColorLight : AppColors.cardColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.book_outlined,
          color: isLightMode
              ? AppColors.iconColorLight.withValues(alpha: 0.5)
              : AppColors.iconColor.withValues(alpha: 0.5),
          size: min(height, width) * 0.6),
    );
  }
}

// Dialog for Google Books Selection
class _GoogleBooksSelectionDialog extends StatelessWidget {
  final List<GoogleBookResult> results;
  const _GoogleBooksSelectionDialog({required this.results});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Select Book from Google', style: GoogleFonts.ubuntu()),
      backgroundColor: theme.dialogTheme.backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, index) {
            final book = results[index];
            return ListTile(
              leading: book.thumbnailUrl != null
                  ? SizedBox(
                      width: 40,
                      height: 60,
                      child: Image.network(
                        book.thumbnailUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) =>
                            const Icon(Icons.broken_image_outlined, size: 30),
                      ))
                  : const SizedBox(
                      width: 40,
                      height: 60,
                      child: Icon(Icons.book_outlined, size: 30)),
              title: Text(book.title,
                  style: GoogleFonts.ubuntu(
                      fontSize: 15, color: theme.colorScheme.onSurface)),
              subtitle: Text(book.authors,
                  style: GoogleFonts.ubuntu(
                      fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
              onTap: () {
                Navigator.of(context).pop(book);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          child: Text('Cancel',
              style: TextStyle(color: theme.colorScheme.primary)),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
    );
  }
}
