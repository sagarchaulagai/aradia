import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/google_book_result.dart';
import 'package:aradia/resources/services/google_books_service.dart';
import 'package:aradia/screens/import/widgets/cover_preview_widget.dart';
import 'package:aradia/screens/import/widgets/google_books_selection_dialog.dart';
import 'package:aradia/utils/app_logger.dart';

import 'package:flutter/material.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:aradia/utils/app_constants.dart';
import 'package:aradia/utils/media_helper.dart';
import 'package:aradia/utils/permission_helper.dart';

import 'package:aradia/widgets/common_text_field.dart';

class EditAudiobookScreen extends StatefulWidget {
  final Audiobook audiobook;

  const EditAudiobookScreen({super.key, required this.audiobook});

  @override
  State<EditAudiobookScreen> createState() => _EditAudiobookScreenState();
}

class _EditAudiobookScreenState extends State<EditAudiobookScreen> {
  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _descriptionController;

  String? _currentCoverDisplayPath;
  File? _pickedLocalCoverFileToSave;
  String? _selectedGBooksCoverUrlToSave;

  List<AudiobookFile> _currentAudioFiles = [];
  final List<File> _newlySelectedAudioFiles = [];

  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.audiobook.title);
    _authorController = TextEditingController(text: widget.audiobook.author);
    _descriptionController =
        TextEditingController(text: widget.audiobook.description);
    _currentCoverDisplayPath = widget.audiobook.lowQCoverImage;
    _loadAudioFilesMetadata();
  }

  Future<void> _loadAudioFilesMetadata() async {
    if (widget.audiobook.origin != AppConstants.localDirName &&
        widget.audiobook.origin != AppConstants.youtubeDirName) {
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cannot access storage.")));
        }
        return;
      }
      final filesFilePath = p.join(appDir.path, widget.audiobook.origin!,
          widget.audiobook.id, 'files.txt');
      final file = File(filesFilePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> filesJson = jsonDecode(content);
        if (mounted) {
          setState(() {
            _currentAudioFiles = filesJson
                .map((data) =>
                    AudiobookFile.fromMap(data as Map<String, dynamic>))
                .toList();
          });
        }
      } else {
        AppLogger.debug("files.txt not found at $filesFilePath");
      }
    } catch (e) {
      AppLogger.debug("Error loading audio files metadata: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error loading file details: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImageFromGallery() async {
    if (!await PermissionHelper.requestStorageAndMediaPermissions()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Media permission denied.")));
      }
      return;
    }
    try {
      final XFile? imageXFile = await MediaHelper.pickImageFromGallery(_picker);
      if (imageXFile != null && mounted) {
        setState(() {
          _pickedLocalCoverFileToSave = File(imageXFile.path);
          _currentCoverDisplayPath = imageXFile.path;
          _selectedGBooksCoverUrlToSave = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error picking image: $e")));
      }
    }
  }

  Future<void> _pickAdditionalAudioFiles() async {
    if (!mounted) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );

      if (result != null && mounted) {
        setState(() {
          _newlySelectedAudioFiles.addAll(result.files
              .where((f) => f.path != null)
              .map((f) => File(f.path!)));
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking audio files: $e')),
        );
      }
    }
  }

  Future<void> _fetchAndSelectFromGoogleBooks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    String query = _titleController.text.trim();

    if (query.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a title to search.')));
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final List<GoogleBookResult> results =
          await GoogleBooksService.fetchBooks(query);
      if (!mounted) return;

      if (results.isNotEmpty) {
        final GoogleBookResult? selectedBook =
            await showDialog<GoogleBookResult>(
          context: context,
          builder: (context) => GoogleBooksSelectionDialog(results: results),
        );

        if (selectedBook != null && mounted) {
          setState(() {
            _titleController.text = selectedBook.title;
            _authorController.text = selectedBook.authors;
            _descriptionController.text = selectedBook.description ?? '';

            _selectedGBooksCoverUrlToSave = selectedBook.thumbnailUrl;
            _currentCoverDisplayPath = selectedBook.thumbnailUrl;
            _pickedLocalCoverFileToSave = null;
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No results found on Google Books.')));
      }
    } catch (e) {
      AppLogger.debug("Google Books API error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching from Google Books: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) throw Exception("Cannot access storage directory");

      final audiobookSpecificDir = Directory(
          p.join(appDir.path, widget.audiobook.origin!, widget.audiobook.id));

      if (!await audiobookSpecificDir.exists()) {
        await audiobookSpecificDir.create(recursive: true);
      }

      String? finalCoverPathForDb = await MediaHelper.saveOrUpdateCoverImage(
        audiobookSpecificDir: audiobookSpecificDir,
        newLocalCoverFileToSave: _pickedLocalCoverFileToSave,
        newNetworkCoverUrlToSave: _selectedGBooksCoverUrlToSave,
        currentCoverPathInDb: widget.audiobook.lowQCoverImage,
      );

      Audiobook updatedAudiobook = widget.audiobook.copyWith(
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        description: _descriptionController.text.trim(),
        lowQCoverImage: finalCoverPathForDb ?? "",
      );

      if ((widget.audiobook.origin == AppConstants.localDirName) &&
          _newlySelectedAudioFiles.isNotEmpty) {
        final filesFilePath = p.join(audiobookSpecificDir.path, 'files.txt');
        List<AudiobookFile> allFiles = List.from(_currentAudioFiles);
        int totalSize = updatedAudiobook.size ?? 0;

        int trackNumber = allFiles.isNotEmpty
            ? allFiles.map((f) => f.track ?? 0).reduce(max) + 1
            : 1;

        for (var newFileSource in _newlySelectedAudioFiles) {
          final newFileName = p.basename(newFileSource.path);
          final targetFile =
              File(p.join(audiobookSpecificDir.path, newFileName));

          if (await targetFile.exists()) {
            AppLogger.debug(
                "Skipping already existing file: ${targetFile.path}");
            continue;
          }
          await newFileSource.copy(targetFile.path);

          final duration = await MediaHelper.getAudioDuration(newFileSource);
          final fileSize = await newFileSource.length();

          final newAudiobookFile = AudiobookFile.fromMap({
            "identifier":
                "${updatedAudiobook.id}_track${trackNumber}_${DateTime.now().millisecondsSinceEpoch}",
            "title": p.basenameWithoutExtension(newFileName),
            "name": newFileName,
            "track": trackNumber,
            "size": fileSize,
            "length": duration,
            "url": newFileName,
            "highQCoverImage": "",
          });
          allFiles.add(newAudiobookFile);
          totalSize += fileSize;
          trackNumber++;
        }
        _currentAudioFiles = allFiles;
        updatedAudiobook = updatedAudiobook.copyWith(size: totalSize);

        await File(filesFilePath).writeAsString(
            jsonEncode(allFiles.map((f) => f.toJson()).toList()));
        if (mounted) setState(() => _newlySelectedAudioFiles.clear());
      }

      final metadataFile =
          File(p.join(audiobookSpecificDir.path, 'audiobook.txt'));
      await metadataFile.writeAsString(jsonEncode(updatedAudiobook.toMap()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audiobook updated successfully!')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      AppLogger.debug("Error saving changes: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving changes: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;
    bool isLocalAudiobookType =
        widget.audiobook.origin == AppConstants.localDirName;

    final textFieldFillColor = isLightMode
        ? AppColors.lightOrange
        : AppColors.cardColor.withAlpha(128);

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Audiobook',
            style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            onPressed: _isLoading ? null : _saveChanges,
            tooltip: 'Save Changes',
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: Column(children: [
              GestureDetector(
                onTap: _isLoading ? null : _pickCoverImageFromGallery,
                child: Stack(alignment: Alignment.bottomRight, children: [
                  CoverPreviewWidget(
                    localCoverFile: _pickedLocalCoverFileToSave,
                    coverPathOrUrl: _pickedLocalCoverFileToSave == null
                        ? _currentCoverDisplayPath
                        : null,
                    height: 150,
                    width: 150,
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(Icons.edit, size: 20, color: AppColors.iconColor),
                  )
                ]),
              ),
              TextButton.icon(
                icon: Icon(Icons.photo_library_outlined,
                    color: AppColors.primaryColor),
                label: Text("Change Cover from Gallery",
                    style: TextStyle(color: AppColors.primaryColor)),
                onPressed: _isLoading ? null : _pickCoverImageFromGallery,
              ),
              const SizedBox(height: 16),
            ])),
            CommonTextField(
              controller: _titleController,
              labelText: 'Title',
              prefixIcon: Icons.title_outlined,
              fillColor: textFieldFillColor,
              theme: theme,
            ),
            const SizedBox(height: 12),
            CommonTextField(
              controller: _authorController,
              labelText: 'Author',
              prefixIcon: Icons.person_outline,
              fillColor: textFieldFillColor,
              theme: theme,
            ),
            const SizedBox(height: 12),
            CommonTextField(
              controller: _descriptionController,
              labelText: 'Description',
              prefixIcon: Icons.description_outlined,
              maxLines: 5,
              fillColor: textFieldFillColor,
              theme: theme,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(Icons.manage_search_outlined,
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black),
              label: Text('Fetch Info from Google Books',
                  style: TextStyle(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black)),
              onPressed: _isLoading ? null : _fetchAndSelectFromGoogleBooks,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonColor),
            ),
            const SizedBox(height: 16),
            if (isLocalAudiobookType) ...[
              OutlinedButton.icon(
                icon: Icon(Icons.playlist_add_outlined,
                    color: theme.brightness == Brightness.light
                        ? Colors.black
                        : Colors.white),
                label: Text('Add More Audio Files',
                    style: TextStyle(
                        color: theme.brightness == Brightness.light
                            ? Colors.black
                            : Colors.white)),
                onPressed: _isLoading ? null : _pickAdditionalAudioFiles,
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primaryColor)),
              ),
              if (_newlySelectedAudioFiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text("New files to add (${_newlySelectedAudioFiles.length}):",
                    style: theme.textTheme.titleSmall),
                ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _newlySelectedAudioFiles.length,
                        itemBuilder: (ctx, index) => ListTile(
                            dense: true,
                            leading: Icon(Icons.audiotrack_outlined,
                                color: theme.colorScheme.primary),
                            title: Text(
                                p.basename(
                                    _newlySelectedAudioFiles[index].path),
                                style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            trailing: IconButton(
                              icon: Icon(Icons.remove_circle_outline,
                                  size: 20, color: theme.colorScheme.error),
                              onPressed: () {
                                if (mounted) {
                                  setState(() =>
                                      _newlySelectedAudioFiles.removeAt(index));
                                }
                              },
                            ))))
              ],
              const SizedBox(height: 10),
            ],
            if ((isLocalAudiobookType ||
                    widget.audiobook.origin == AppConstants.youtubeDirName) &&
                _currentAudioFiles.isNotEmpty) ...[
              Text("Current Audio Files (${_currentAudioFiles.length}):",
                  style: theme.textTheme.titleSmall),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _currentAudioFiles.length,
                      itemBuilder: (context, index) {
                        final file = _currentAudioFiles[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.audiotrack, size: 20),
                          title: Text(
                              file.title ?? file.name ?? "Track ${file.track}",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        );
                      })),
            ],
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: theme.brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: const Text('Save Changes'),
              onPressed: _isLoading ? null : _saveChanges,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
