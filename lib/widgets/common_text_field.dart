import 'package:flutter/material.dart';

class CommonTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final IconData prefixIcon;
  final int maxLines;
  final bool readOnly;
  final Color fillColor;
  final ThemeData? theme; // Optional: pass theme if default from context is not enough

  const CommonTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    required this.prefixIcon,
    this.maxLines = 1,
    this.readOnly = false,
    required this.fillColor,
    this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final currentTheme = theme ?? Theme.of(context);
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: Icon(prefixIcon,
            color: currentTheme.inputDecorationTheme.prefixIconColor ??
                currentTheme.colorScheme.onSurfaceVariant),
        border: currentTheme.inputDecorationTheme.border ??
            const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8.0))),
        enabledBorder: currentTheme.inputDecorationTheme.enabledBorder ??
            OutlineInputBorder(
                borderSide: BorderSide(
                    color: currentTheme.colorScheme.outline.withAlpha(128)),
                borderRadius: const BorderRadius.all(Radius.circular(8.0))),
        focusedBorder: currentTheme.inputDecorationTheme.focusedBorder ??
            OutlineInputBorder(
                borderSide:
                    BorderSide(color: currentTheme.colorScheme.primary, width: 2.0),
                borderRadius: const BorderRadius.all(Radius.circular(8.0))),
        filled: true,
        fillColor: fillColor,
        labelStyle: currentTheme.inputDecorationTheme.labelStyle ??
            TextStyle(color: currentTheme.colorScheme.onSurfaceVariant),
        hintStyle: currentTheme.inputDecorationTheme.hintStyle,
      ),
      style: TextStyle(color: currentTheme.colorScheme.onSurface),
      maxLines: maxLines,
      readOnly: readOnly,
    );
  }
}