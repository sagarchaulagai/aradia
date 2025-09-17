import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/utils/app_events.dart';
import 'package:aradia/utils/permission_helper.dart';
import 'package:aradia/resources/services/local/local_audiobook_service.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:aradia/resources/designs/theme_notifier.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  // Used from archive.org/details/librivoxaudio 's language filter, sorted
  static const Map<String, String> _langs = {
    'en': 'English',
    'de': 'Deutsch (German)',
    'es': 'Español (Spanish)',
    'fr': 'Français (French)',
    'nl': 'Nederlands (Dutch)',
    'mul': 'Multiple / Multilingual',
    'pt': 'Português (Portuguese)',
    'it': 'Italiano (Italian)',
    'ru': 'Русский (Russian)',
    'el': 'Ελληνικά (Greek)',
    'grc': 'Ancient Greek',
    'ja': '日本語 (Japanese)',
    'pl': 'Polski (Polish)',
    'zh': '中文 (Chinese)',
    'he': 'עברית (Hebrew)',
    'la': 'Latina (Latin)',
    'fi': 'Suomi (Finnish)',
    'sv': 'Svenska (Swedish)',
    'ca': 'Català (Catalan)',
    'da': 'Dansk (Danish)',
    'eo': 'Esperanto',
  };

  late final Box _box;
  List<String> _selected = [];
  String? _rootFolderPath;

  @override
  void initState() {
    super.initState();
    _box = Hive.box('language_prefs_box');
    _selected = List<String>.from(
      _box.get('selectedLanguages', defaultValue: <String>[]),
    );
    _loadRootFolderPath();
  }

  Future<void> _loadRootFolderPath() async {
    final path = await LocalAudiobookService.getRootFolderPath();
    setState(() {
      _rootFolderPath = path;
    });
  }

  Future<void> _editLanguages() async {
    final temp = {..._selected}; // work on a copy in the dialog
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Visible languages'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _langs.entries.map((e) {
                final code = e.key;
                final label = e.value;
                final checked = temp.contains(code);
                return Column(
                  children: [
                    CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState(() {}); // keep dialog snappy
                        if (v == true) {
                          temp.add(code);
                        } else {
                          temp.remove(code);
                        }
                        // force rebuild of dialog
                        (ctx as Element).markNeedsBuild();
                      },
                      title: Text(label),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                // Persist selection
                await _box.put('selectedLanguages', temp.toList()..sort());
                setState(() {
                  _selected = temp.toList()..sort();
                });
                AppEvents.languagesChanged.add(null); // <-- broadcast refresh
                if (mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Language filter saved. Lists will update on next fetch.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
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
          _rootFolderPath = selectedDirectory;
        });

        // Notify other screens about the directory change
        AppEvents.localDirectoryChanged.add(null);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audiobooks directory updated successfully!'),
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

  String _themeSubtitle(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
      default:
        return 'System default';
    }
  }

  Future<void> _pickTheme(BuildContext context) async {
    final themeNotifier = Provider.of<ThemeNotifier>(context, listen: false);
    ThemeMode current = themeNotifier.themeMode;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('System default'),
              value: ThemeMode.system,
              groupValue: current,
              onChanged: (v) {
                if (v == null) return;
                themeNotifier.setTheme(v);
                Navigator.of(ctx).pop();
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: current,
              onChanged: (v) {
                if (v == null) return;
                themeNotifier.setTheme(v);
                Navigator.of(ctx).pop();
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: current,
              onChanged: (v) {
                if (v == null) return;
                themeNotifier.setTheme(v);
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );

    if (mounted) setState(() {}); // refresh subtitle after change
  }

  @override
  Widget build(BuildContext context) {
    final chips = _selected.isEmpty
        ? [const Chip(label: Text('All languages (no filter)'))]
        : _selected.map((c) => Chip(label: Text(_langs[c] ?? c))).toList();

    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final currentTheme = themeNotifier.themeMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Theme selection (moved from App Bar)
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Text(_themeSubtitle(currentTheme)),
            trailing: const Icon(Icons.edit),
            onTap: () => _pickTheme(context),
          ),
          const Divider(),

          // Language filter
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Visible languages'),
            subtitle: Wrap(
              spacing: 8,
              runSpacing: -8,
              children: chips,
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editLanguages,
          ),
          const Divider(),

          // Local Audiobooks Directory
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Local Audiobooks Directory'),
            subtitle: Text(
              _rootFolderPath ?? 'No directory selected',
              style: TextStyle(
                color: _rootFolderPath != null
                    ? Theme.of(context).textTheme.bodySmall?.color
                    : Colors.grey,
              ),
            ),
            trailing: const Icon(Icons.edit),
            onTap: _selectRootFolder,
          ),
          const Divider(),

          // Licenses
          ListTile(
            leading: const Icon(Icons.book),
            title: const Text('3rd Party Libraries'),
            subtitle: const Text('View licenses of the libraries used'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => showLicensePage(context: context),
          ),
          const Divider(),

          // About
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Learn more about this app'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/icon.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Aradia',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "Version 3.0.0",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                          'A Flutter app that provides access to a wide range of audiobooks from Librivox. Users can browse and listen to audiobooks in various genres, with the ability to customize their listening experience through a built-in audio player.',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.copyright,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '© 2024 Aradia Audiobook',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
