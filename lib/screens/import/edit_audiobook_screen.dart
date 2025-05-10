// lib/screens/import/edit_audiobook_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // For Random and min
import 'package:aradia/resources/designs/app_colors.dart'; // Ensure this path is correct
import 'package:aradia/resources/models/google_book_result.dart';
import 'package:aradia/widgets/low_and_high_image.dart'; // Your LowAndHighImage widget
import 'package:flutter/material.dart';
import 'package:aradia/resources/models/audiobook.dart';
import 'package:aradia/resources/models/audiobook_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart'; // For permission handling

const String _youtubeDirNameEdit = 'youtube';
const String _localDirNameEdit = 'local';
const String _coverFileNameEdit = 'cover.jpg'; // Standardized cover name

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
  List<File> _newlySelectedAudioFiles = [];

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

  Future<bool> _requestMediaPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        var photoStatus = await Permission.photos.status;
        if (!photoStatus.isGranted)
          photoStatus = await Permission.photos.request();
        return photoStatus.isGranted;
      } else {
        var storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted)
          storageStatus = await Permission.storage.request();
        return storageStatus.isGranted;
      }
    } else if (Platform.isIOS) {
      var photoStatus = await Permission.photos.status;
      if (!photoStatus.isGranted)
        photoStatus = await Permission.photos.request();
      return photoStatus.isGranted;
    }
    return true;
  }

  Future<void> _loadAudioFilesMetadata() async {
    if (widget.audiobook.origin != _localDirNameEdit &&
        widget.audiobook.origin != _youtubeDirNameEdit) {
      return;
    }
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cannot access storage.")));
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
        print("files.txt not found at $filesFilePath");
      }
    } catch (e) {
      print("Error loading audio files metadata: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error loading file details: $e")));
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
    if (!await _requestMediaPermissions()) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Photo library permission denied.")));
      return;
    }
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        setState(() {
          _pickedLocalCoverFileToSave = File(image.path);
          _currentCoverDisplayPath = image.path;
          _selectedGBooksCoverUrlToSave = null;
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error picking image: $e")));
    }
  }

  // Method to pick additional audio files
  Future<void> _pickAdditionalAudioFiles() async {
    if (!mounted) return;
    // No special permissions needed for FilePicker.platform.pickFiles if using default OS picker.
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
    // if (_authorController.text.trim().isNotEmpty) {
    //   query += " inauthor:${_authorController.text.trim()}";
    // }

    if (query.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a title to search.')));
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

          final GoogleBookResult? selectedBook =
              await showDialog<GoogleBookResult>(
            context: context,
            builder: (context) =>
                _GoogleBooksSelectionDialogEdit(results: results),
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No results found on Google Books.')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Google Books Error: ${response.statusCode}. Please try again.')));
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

  Future<String?> _handleCoverSaving(
      Directory audiobookDir, String? originalDbCoverPath) async {
    final newLocalCoverTarget =
        File(p.join(audiobookDir.path, _coverFileNameEdit));
    String? finalSavedAbsolutePath;

    // Determine if the original cover in DB was already 'cover.jpg' and local
    bool originalWasStandardCoverJpg = false;
    if (originalDbCoverPath != null &&
        originalDbCoverPath.isNotEmpty &&
        !originalDbCoverPath.startsWith('http')) {
      if (p.basename(originalDbCoverPath) == _coverFileNameEdit &&
          File(originalDbCoverPath).existsSync()) {
        originalWasStandardCoverJpg = true;
      }
    }

    // 1. If a new local file was picked by the user
    if (_pickedLocalCoverFileToSave != null) {
      try {
        // Delete old 'cover.jpg' if it exists and is different from the new picked file's source
        if (await newLocalCoverTarget.exists() &&
            newLocalCoverTarget.path != _pickedLocalCoverFileToSave!.path) {
          await newLocalCoverTarget.delete();
        }
        // Also delete the original DB cover if it was local and not the same as the new target (cover.jpg)
        if (originalDbCoverPath != null &&
            !originalDbCoverPath.startsWith('http') &&
            originalDbCoverPath != newLocalCoverTarget.path &&
            File(originalDbCoverPath).existsSync()) {
          try {
            await File(originalDbCoverPath).delete();
          } catch (e) {
            print("Error deleting old original cover: $e");
          }
        }

        await _pickedLocalCoverFileToSave!.copy(newLocalCoverTarget.path);
        finalSavedAbsolutePath = newLocalCoverTarget.path;
        print("Saved new local cover from gallery: $finalSavedAbsolutePath");
      } catch (e) {
        print("Error copying picked local cover: $e");
        // Fallback or error handling
      }
    }
    // 2. Else if a Google Books cover URL was selected
    else if (_selectedGBooksCoverUrlToSave != null) {
      try {
        // Delete old 'cover.jpg' or original local DB cover before downloading new one
        if (await newLocalCoverTarget.exists())
          await newLocalCoverTarget.delete();
        if (originalDbCoverPath != null &&
            !originalDbCoverPath.startsWith('http') &&
            File(originalDbCoverPath).existsSync()) {
          try {
            await File(originalDbCoverPath).delete();
          } catch (e) {
            print("Error deleting old original cover: $e");
          }
        }

        final response =
            await http.get(Uri.parse(_selectedGBooksCoverUrlToSave!));
        if (response.statusCode == 200) {
          await newLocalCoverTarget.writeAsBytes(response.bodyBytes);
          finalSavedAbsolutePath = newLocalCoverTarget.path;
          print("Downloaded and saved GBooks cover: $finalSavedAbsolutePath");
        } else {
          print("Failed to download GBooks cover: ${response.statusCode}");
          // If GBooks download fails, we might want to revert to original or leave cover unchanged.
          // For now, if download fails, `finalSavedAbsolutePath` remains null, so the original cover path will be used.
        }
      } catch (e) {
        print("Error downloading GBooks cover: $e");
      }
    }
    // 3. Else if no new selection, but original local cover was not 'cover.jpg'
    else if (originalDbCoverPath != null &&
        originalDbCoverPath.isNotEmpty &&
        !originalDbCoverPath.startsWith('http') &&
        !originalWasStandardCoverJpg) {
      final oldCoverFile = File(originalDbCoverPath);
      if (await oldCoverFile.exists()) {
        try {
          if (await newLocalCoverTarget.exists())
            await newLocalCoverTarget
                .delete(); // Delete existing cover.jpg if any
          await oldCoverFile
              .copy(newLocalCoverTarget.path); // Copy to cover.jpg
          finalSavedAbsolutePath = newLocalCoverTarget.path;
          await oldCoverFile.delete(); // Delete original non-standard name file
          print("Standardized old local cover to: $finalSavedAbsolutePath");
        } catch (e) {
          print("Error standardizing old local cover: $e");
          finalSavedAbsolutePath = originalDbCoverPath; // Fallback
        }
      } else {
        finalSavedAbsolutePath = null; // Original local file not found
      }
    }
    // 4. If original was already cover.jpg and local, and no new selection
    else if (originalWasStandardCoverJpg) {
      finalSavedAbsolutePath = newLocalCoverTarget.path; // It's already correct
    }
    // 5. If original was a URL and no new selection, it remains a URL (or originalDbCoverPath)
    else if (originalDbCoverPath != null &&
        originalDbCoverPath.startsWith('http') &&
        _pickedLocalCoverFileToSave == null &&
        _selectedGBooksCoverUrlToSave == null) {
      finalSavedAbsolutePath = originalDbCoverPath; // Keep original URL
    }

    // If, after all, finalSavedAbsolutePath is still null, it means either:
    // - Original was a URL and no new selection was made.
    // - Original was local but not found/couldn't be standardized, and no new selection.
    // - A new selection was made but failed to save.
    // In these cases, we fall back to the originalDbCoverPath unless a new URL was explicitly chosen but failed.
    if (finalSavedAbsolutePath == null) {
      if (_selectedGBooksCoverUrlToSave != null) {
        // User intended to change to GBooks URL, but download failed. Store the URL.
        return _selectedGBooksCoverUrlToSave;
      }
      return originalDbCoverPath; // Fallback to whatever was originally in DB
    }

    return finalSavedAbsolutePath; // Path to 'cover.jpg' or an intended URL if download failed
  }

  Future<void> _saveChanges() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) throw Exception("Cannot access storage directory");

      final audiobookDir = Directory(
          p.join(appDir.path, widget.audiobook.origin!, widget.audiobook.id));
      await audiobookDir.create(recursive: true);

      String? finalCoverPathForDb = await _handleCoverSaving(
          audiobookDir, widget.audiobook.lowQCoverImage);

      Audiobook updatedAudiobook = widget.audiobook.copyWith(
        title: _titleController.text.trim(),
        author: _authorController.text.trim(),
        description: _descriptionController.text.trim(),
        lowQCoverImage: finalCoverPathForDb ?? "", // Ensure it's not null
      );

      if ((widget.audiobook.origin == _localDirNameEdit) &&
          _newlySelectedAudioFiles.isNotEmpty) {
        final filesFilePath = p.join(audiobookDir.path, 'files.txt');
        List<AudiobookFile> allFiles = List.from(_currentAudioFiles);
        int totalSize = updatedAudiobook.size ?? 0;
        int trackNumber = allFiles.isNotEmpty
            ? allFiles.map((f) => f.track ?? 0).fold(0, max) + 1
            : 1;

        for (var newFileSource in _newlySelectedAudioFiles) {
          final newFileName = p.basename(newFileSource.path);
          final targetFile = File(p.join(audiobookDir.path, newFileName));
          if (await targetFile.exists()) {
            continue;
          }
          await newFileSource.copy(targetFile.path);

          final newAudiobookFile = AudiobookFile.fromMap({
            "identifier":
                "${updatedAudiobook.id}_track${trackNumber}_${DateTime.now().millisecondsSinceEpoch}",
            "title": p.basenameWithoutExtension(newFileName),
            "name": newFileName,
            "track": trackNumber,
            "size": await newFileSource.length(),
            "length": 0.0,
            "url": newFileName,
            "highQCoverImage": "",
          });
          allFiles.add(newAudiobookFile);
          totalSize += newAudiobookFile.size ?? 0;
          trackNumber++;
        }
        _currentAudioFiles = allFiles;
        updatedAudiobook = updatedAudiobook.copyWith(size: totalSize);
        await File(filesFilePath).writeAsString(
            jsonEncode(allFiles.map((f) => f.toJson()).toList()));
        if (mounted) setState(() => _newlySelectedAudioFiles.clear());
      }

      final metadataFile = File(p.join(audiobookDir.path, 'audiobook.txt'));
      await metadataFile.writeAsString(jsonEncode(updatedAudiobook.toMap()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audiobook updated successfully!')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      print("Error saving changes: $e");
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving changes: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildCoverDisplayWidget(ThemeData theme) {
    Widget placeholder = Container(
      height: 150,
      width: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.3)),
      ),
      child: Icon(Icons.photo_library_outlined,
          size: 60, color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
    );

    if (_currentCoverDisplayPath == null || _currentCoverDisplayPath!.isEmpty) {
      return placeholder;
    }

    if (_currentCoverDisplayPath!.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LowAndHighImage(
          // Your widget for network images
          lowQImage: _currentCoverDisplayPath!,
          highQImage: _currentCoverDisplayPath,
          height: 150, width: 150,
        ),
      );
    } else {
      // Assumed to be an absolute local file path
      final file = File(_currentCoverDisplayPath!);
      // Check if it's absolute and exists. LowAndHighImage doesn't handle local files, so Image.file is correct.
      if (p.isAbsolute(_currentCoverDisplayPath!) && file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            height: 150,
            width: 150,
            fit: BoxFit.cover,
            errorBuilder: (c, e, s) => placeholder,
          ),
        );
      } else {
        print(
            "Cover display: File not found or path not absolute: $_currentCoverDisplayPath");
        return placeholder;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;
    bool isLocalAudiobookType = widget.audiobook.origin == _localDirNameEdit;

    // Use AppColors for text field fill if available, otherwise a theme-derived color
    final textFieldFillColor = isLightMode
        ? (AppColors
            .lightOrange) // Assuming AppColors is your aradia/resources/designs/app_colors.dart
        : (AppColors.cardColor.withOpacity(
            0.5)); // Adjust opacity or color as needed for dark mode

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
                        strokeWidth: 2,
                        color: Colors.white)) // Explicit white for appbar
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
                  _buildCoverDisplayWidget(theme),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.edit,
                      size: 20,
                      color: AppColors.iconColor,
                    ),
                  )
                ]),
              ),
              TextButton.icon(
                icon: Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primaryColor,
                ), // Changed icon
                label: Text(
                  "Change Cover from Gallery",
                  style: TextStyle(
                    color: AppColors.primaryColor,
                  ),
                ),
                onPressed: _isLoading ? null : _pickCoverImageFromGallery,
              ),
              const SizedBox(height: 16),
            ])),

            _buildTextField(
                controller: _titleController,
                label: 'Title',
                icon: Icons.title_outlined,
                theme: theme,
                fillColor: textFieldFillColor),
            const SizedBox(height: 12),
            _buildTextField(
                controller: _authorController,
                label: 'Author',
                icon: Icons.person_outline,
                theme: theme,
                fillColor: textFieldFillColor),
            const SizedBox(height: 12),
            _buildTextField(
                controller: _descriptionController,
                label: 'Description',
                icon: Icons.description_outlined,
                maxLines: 5,
                theme: theme,
                fillColor: textFieldFillColor),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              icon: Icon(
                Icons.manage_search_outlined,
                color: theme.brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
              label: Text(
                'Fetch Info from Google Books',
                style: TextStyle(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              ),
              onPressed: _isLoading ? null : _fetchAndSelectFromGoogleBooks,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.buttonColor,
              ),
            ),
            const SizedBox(height: 16),

            if (isLocalAudiobookType) ...[
              OutlinedButton.icon(
                icon: Icon(
                  Icons.playlist_add_outlined,
                  color: theme.brightness == Brightness.light
                      ? Colors.black
                      : Colors.white,
                ), // More suitable icon
                label: Text(
                  'Add More Audio Files',
                  style: TextStyle(
                    color: theme.brightness == Brightness.light
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
                onPressed: _isLoading
                    ? null
                    : _pickAdditionalAudioFiles, // Corrected method name
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.primaryColor,
                  ),
                ),
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
                                if (mounted)
                                  setState(() =>
                                      _newlySelectedAudioFiles.removeAt(index));
                              },
                            ))))
              ],
              const SizedBox(height: 10),
            ],

            if ((isLocalAudiobookType ||
                    widget.audiobook.origin == _youtubeDirNameEdit) &&
                _currentAudioFiles.isNotEmpty) ...[
              Text(
                "Current Audio Files (${_currentAudioFiles.length}):",
              ),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _currentAudioFiles.length,
                      itemBuilder: (context, index) {
                        final file = _currentAudioFiles[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.audiotrack, size: 20),
                          title: Text(
                              file.title ?? file.name ?? "Track ${file.track}",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle()),
                        );
                      })),
            ],
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(
                      Icons.save,
                      color: theme.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
              label: Text(
                'Save Changes',
                style: TextStyle(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              ),
              onPressed: _isLoading ? null : _saveChanges,
            ),
            const SizedBox(height: 16), // Padding at the bottom
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
      {required TextEditingController controller,
      required String label,
      required IconData icon,
      int maxLines = 1,
      bool readOnly = false,
      required ThemeData theme,
      required Color fillColor}) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon,
            color: theme.inputDecorationTheme.prefixIconColor ??
                theme.colorScheme.onSurfaceVariant),
        border: theme.inputDecorationTheme.border ??
            const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8.0))),
        enabledBorder: theme.inputDecorationTheme.enabledBorder ??
            OutlineInputBorder(
                borderSide: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.5)),
                borderRadius: const BorderRadius.all(Radius.circular(8.0))),
        focusedBorder: theme.inputDecorationTheme.focusedBorder ??
            OutlineInputBorder(
                borderSide:
                    BorderSide(color: theme.colorScheme.primary, width: 2.0),
                borderRadius: const BorderRadius.all(Radius.circular(8.0))),
        filled: true,
        fillColor: fillColor,
        labelStyle: theme.inputDecorationTheme.labelStyle ??
            TextStyle(color: theme.colorScheme.onSurfaceVariant),
        hintStyle: theme.inputDecorationTheme.hintStyle,
      ),
      style: TextStyle(color: theme.colorScheme.onSurface),
      maxLines: maxLines,
      readOnly: readOnly,
    );
  }
}

// Dialog for Google Books Selection in Edit Screen
class _GoogleBooksSelectionDialogEdit extends StatelessWidget {
  final List<GoogleBookResult> results;
  const _GoogleBooksSelectionDialogEdit({required this.results});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('Select Book Info',
          style: GoogleFonts.ubuntu(color: theme.colorScheme.onSurface)),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: SizedBox(
        width: min(
            MediaQuery.of(context).size.width * 0.9, 400), // Responsive width
        child: results.isEmpty
            ? Center(
                child: Text("No results to display.",
                    style:
                        TextStyle(color: theme.colorScheme.onSurfaceVariant)))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: results.length,
                separatorBuilder: (context, index) =>
                    Divider(color: theme.dividerColor.withOpacity(0.5)),
                itemBuilder: (context, index) {
                  final book = results[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 4.0, horizontal: 8.0),
                    leading: book.thumbnailUrl != null
                        ? SizedBox(
                            width: 40,
                            height: 60,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                book.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(
                                    Icons.broken_image_outlined,
                                    size: 30),
                                loadingBuilder: (c, child, progress) =>
                                    progress == null
                                        ? child
                                        : const Center(
                                            child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))),
                              ),
                            ))
                        : Container(
                            width: 40,
                            height: 60,
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: theme.colorScheme.surfaceVariant),
                            child: const Icon(Icons.book_outlined, size: 30)),
                    title: Text(book.title,
                        style: GoogleFonts.ubuntu(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface)),
                    subtitle: Text(book.authors,
                        style: GoogleFonts.ubuntu(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant)),
                    onTap: () => Navigator.of(context).pop(book),
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
