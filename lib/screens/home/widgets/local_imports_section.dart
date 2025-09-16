import 'dart:async';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:aradia/resources/models/local_audiobook.dart';
import 'package:aradia/resources/services/local/local_audiobook_service.dart';
import 'package:aradia/utils/app_events.dart';
import 'package:aradia/utils/permission_helper.dart';
import 'package:aradia/widgets/local_audiobook_item.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LocalImportsSection extends StatefulWidget {
  const LocalImportsSection({super.key});

  @override
  State<LocalImportsSection> createState() => _LocalImportsSectionState();
}

class _LocalImportsSectionState extends State<LocalImportsSection> {
  String? rootFolderPath;
  List<LocalAudiobook> audiobooks = [];
  bool isLoading = false;
  StreamSubscription<void>? _directoryChangeSubscription;

  @override
  void initState() {
    super.initState();
    _loadRootFolder();

    // Listen for directory changes from settings
    _directoryChangeSubscription =
        AppEvents.localDirectoryChanged.stream.listen((_) {
      _loadRootFolder();
    });
  }

  Future<void> _loadRootFolder() async {
    setState(() {
      isLoading = true;
    });

    rootFolderPath = await LocalAudiobookService.getRootFolderPath();

    if (rootFolderPath != null) {
      await _loadAudiobooks();
    }

    setState(() => isLoading = false);
  }

  Future<void> _loadAudiobooks() async {
    try {
      final loadedAudiobooks = await LocalAudiobookService.refreshAudiobooks();
      setState(() {
        audiobooks = loadedAudiobooks;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading audiobooks: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectRootFolder() async {
    // Request storage permissions first
    final hasPermission =
        await PermissionHelper.handleDownloadPermissionWithDialog(context);
    if (!hasPermission) return;

    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory != null) {
        await LocalAudiobookService.setRootFolderPath(selectedDirectory);
        setState(() {
          rootFolderPath = selectedDirectory;
        });

        // Load audiobooks from the selected folder
        await _loadAudiobooks();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Root folder set successfully!'),
              backgroundColor: AppColors.primaryColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshAudiobooks() async {
    setState(() => isLoading = true);
    await _loadAudiobooks();
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Local Audiobooks',
                style: GoogleFonts.ubuntu(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (rootFolderPath != null)
                IconButton(
                  onPressed: _refreshAudiobooks,
                  icon: const Icon(
                    Icons.refresh,
                    color: AppColors.primaryColor,
                  ),
                  tooltip: 'Refresh audiobooks',
                ),
            ],
          ),
          //const SizedBox(height: 8),
          if (isLoading)
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryColor,
              ),
            )
          else if (rootFolderPath == null)
            _buildSelectFolderCard()
          else if (audiobooks.isEmpty)
            _buildEmptyState()
          else
            _buildAudiobooksList(),
        ],
      ),
    );
  }

  Widget _buildSelectFolderCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: _selectRootFolder,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.folder_open,
                size: 48,
                color: AppColors.primaryColor,
              ),
              const SizedBox(height: 12),
              Text(
                'Select Root Folder',
                style: GoogleFonts.ubuntu(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the folder where you keep your local audiobooks.\nRecommended structure: Audiobooks/Author/Title/',
                textAlign: TextAlign.center,
                style: GoogleFonts.ubuntu(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              'No Audiobooks Found',
              style: GoogleFonts.ubuntu(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add audiobooks to your selected folder and tap refresh.',
              textAlign: TextAlign.center,
              style: GoogleFonts.ubuntu(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: _selectRootFolder,
                  icon: const Icon(
                    Icons.folder_open,
                    color: AppColors.primaryColor,
                  ),
                  label: const Text(
                    'Change Folder',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _refreshAudiobooks,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudiobooksList() {
    return SizedBox(
      height: 250,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: audiobooks.length,
        itemBuilder: (context, index) {
          return LocalAudiobookItem(
            audiobook: audiobooks[index],
            onUpdated: _loadAudiobooks,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _directoryChangeSubscription?.cancel();
    super.dispose();
  }
}
