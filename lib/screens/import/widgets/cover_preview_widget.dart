import 'dart:io';
import 'dart:math';
import 'package:aradia/resources/designs/app_colors.dart'; // Adjust path as needed
import 'package:flutter/material.dart';

class CoverPreviewWidget extends StatelessWidget {
  final File? localCoverFile;
  final String? coverPathOrUrl;
  final double height;
  final double width;
  final Widget? customPlaceholder;

  const CoverPreviewWidget({
    super.key,
    this.localCoverFile,
    this.coverPathOrUrl,
    this.height = 120,
    this.width = 120,
    this.customPlaceholder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;

    Widget defaultPlaceholder = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: isLightMode ? AppColors.cardColorLight : AppColors.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (isLightMode
                    ? AppColors.dividerColorLight
                    : AppColors.dividerColor)
                .withAlpha(128)),
      ),
      child: Icon(Icons.photo_size_select_actual_outlined,
          size: min(height, width) * 0.5,
          color: isLightMode ? AppColors.iconColorLight : AppColors.iconColor),
    );

    final Widget effectivePlaceholder = customPlaceholder ?? defaultPlaceholder;

    if (localCoverFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(localCoverFile!,
            height: height, width: width, fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) => effectivePlaceholder,
        ),
      );
    } else if (coverPathOrUrl != null && coverPathOrUrl!.isNotEmpty) {
      if (coverPathOrUrl!.startsWith('http')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            coverPathOrUrl!,
            height: height,
            width: width,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => effectivePlaceholder,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return SizedBox(
                  height: height,
                  width: width,
                  child: Center(
                      child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                    strokeWidth: 2,
                  )));
            },
          ),
        );
      } else {
        // Assumed local absolute path
        final file = File(coverPathOrUrl!);
        // It's good practice to ensure it's absolute for Image.file if paths might be relative
        if (file.existsSync()) { // p.isAbsolute(coverPathOrUrl!) might be redundant if paths are always constructed absolutely
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              height: height,
              width: width,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, st) => effectivePlaceholder,
            ),
          );
        } else {
          return effectivePlaceholder;
        }
      }
    }
    return effectivePlaceholder;
  }
}