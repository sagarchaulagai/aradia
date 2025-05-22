import 'package:flutter/material.dart';
import 'package:aradia/resources/designs/theme_notifier.dart';

class AppBarActions extends StatelessWidget {
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
          onPressed: themeNotifier.toggleTheme,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return RotationTransition(
                turns: animation,
                child: child,
              );
            },
            child: Icon(
              themeNotifier.themeMode == ThemeMode.light
                  ? Icons.nightlight_round
                  : Icons.wb_sunny,
              key: ValueKey<bool>(themeNotifier.themeMode == ThemeMode.light),
            ),
          ),
          tooltip: 'Toggle theme mode',
        ),
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
