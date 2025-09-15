import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/utils/app_events.dart';

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

  @override
  void initState() {
    super.initState();
    _box = Hive.box('language_prefs_box');
    _selected = List<String>.from(
      _box.get('selectedLanguages', defaultValue: <String>[]),
    );
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
                    SizedBox(
                      height: 10,
                    )
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

  @override
  Widget build(BuildContext context) {
    final chips = _selected.isEmpty
        ? [const Chip(label: Text('All languages (no filter)'))]
        : _selected.map((c) => Chip(label: Text(_langs[c] ?? c))).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
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
                                color: Colors.black.withOpacity(0.1),
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
