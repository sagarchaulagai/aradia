import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:aradia/utils/app_events.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  // Language code -> human label (match codes used in archive_api aliases)
  static const Map<String, String> _langs = {
    'en': 'English',
    'de': 'Deutsch (German)',
    'fr': 'Français (French)',
    'es': 'Español (Spanish)',
    'it': 'Italiano (Italian)',
    'pt': 'Português (Portuguese)',
    'nl': 'Nederlands (Dutch)',
    'ru': 'Русский (Russian)',
    'zh': '中文 (Chinese)',
    'ja': '日本語 (Japanese)',
    'ar': 'العربية (Arabic)',
    'hi': 'हिन्दी (Hindi)',
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
                return CheckboxListTile(
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
        : _selected
        .map((c) => Chip(label: Text(_langs[c] ?? c)))
        .toList();

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
              showAboutDialog(
                context: context,
                applicationName: 'Aradia',
                applicationVersion: '1.0.0',
                applicationIcon: const FlutterLogo(),
                applicationLegalese: '© 2024 Aradia Audiobook',
              );
            },
          ),
        ],
      ),
    );
  }
}
