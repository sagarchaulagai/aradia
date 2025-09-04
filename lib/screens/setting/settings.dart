import 'package:flutter/material.dart';

class Settings extends StatelessWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            leading: const Icon(Icons.book),
            title: const Text('3rd Party Libraries'),
            subtitle: const Text('View licenses of the libraries used'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              showLicensePage(context: context);
            },
          ),
          const Divider(),
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

Widget licensePage(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Licenses'),
    ),
    body: const LicensePage(
      applicationName: 'Aradia',
      applicationVersion: '1.0.0',
      applicationIcon: FlutterLogo(),
      applicationLegalese: '© 2024 Aradia Audiobook',
    ),
  );
}
