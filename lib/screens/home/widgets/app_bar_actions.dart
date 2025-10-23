import 'package:flutter/material.dart';
import 'package:aradia/resources/designs/theme_notifier.dart';
import 'package:ionicons/ionicons.dart';
import 'package:go_router/go_router.dart';

class AppBarActions extends StatelessWidget {
  // ignore: unused_field
  final ThemeNotifier themeNotifier;
  final VoidCallback onSettingsPressed;

  const AppBarActions({
    super.key,
    required this.themeNotifier,
    required this.onSettingsPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedIconButton(
          icon: const Icon(Ionicons.logo_youtube),
          onPressed: () => context.push('/youtube'),
          tooltip: 'YouTube Import',
        ),
        // Theme toggling moved to Settings page.
        AnimatedIconButton(
          icon: const Icon(Icons.settings),
          onPressed: onSettingsPressed,
          tooltip: 'Settings',
        ),
      ],
    );
  }
}

class AnimatedIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const AnimatedIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 24,
    );
  }
}
