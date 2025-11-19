// lib/resources/designs/themes.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class Themes {
  // Light Theme
  static final ThemeData lightTheme = ThemeData.light().copyWith(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.scaffoldBackgroundColor,
    // Kill surface tint so grays don't get a blue cast
    colorScheme: ThemeData.light().colorScheme.copyWith(
      primary: AppColors.primaryColor,
      secondary: AppColors.primaryColor,
      surfaceTint: Colors.transparent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 0,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: Colors.grey,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.cardColorLight,
    ),
  );

  // Dark Theme
  static final ThemeData darkTheme = ThemeData.dark().copyWith(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.darkScaffoldBackgroundColor,
    colorScheme: ThemeData.dark().colorScheme.copyWith(
      primary: AppColors.primaryColor,
      secondary: AppColors.primaryColor,
      surfaceTint: Colors.transparent,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      elevation: 0,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: Colors.grey,
    ),
  );
}
