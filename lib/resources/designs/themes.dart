import 'package:aradia/resources/designs/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/material/theme_data.dart';

class Themes {
  // Light Theme
  ThemeData lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: AppColors.scaffoldBackgroundColor,
    cardTheme: const CardThemeData(
      color: AppColors.cardColorLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 2,
      surfaceTintColor: Colors.grey, // keep neutral
    ),
    colorScheme: ThemeData.light().colorScheme.copyWith(
      primary: AppColors.primaryColor, // <- make buttons orange
      secondary: AppColors.primaryColor, // optional: for FABs / accents
    ),
  );

  // Dark Theme
  ThemeData darkTheme = ThemeData.dark().copyWith(
    appBarTheme: const AppBarTheme(
      surfaceTintColor: Colors.transparent, // <- matches the dark surface exactly
    ),
    colorScheme: ThemeData.dark().colorScheme.copyWith(
      primary: AppColors.primaryColor, // <- make buttons orange
      secondary: AppColors.primaryColor,
    ),
  );

}
