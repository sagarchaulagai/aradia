import 'package:aradia/resources/designs/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Themes {
  // Light Theme
  ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primaryColor,
    scaffoldBackgroundColor: AppColors.scaffoldBackgroundColor,
    textTheme: GoogleFonts.ubuntuTextTheme().apply(
      bodyColor: AppColors.textColor,
      displayColor: AppColors.textColor,
    ),
    tabBarTheme: TabBarTheme(
      labelColor: AppColors.primaryColor, // Color of the selected tab
      indicatorColor: AppColors.primaryColor,
      unselectedLabelColor:
          AppColors.iconColorLight.withOpacity(0.6), // Unselected tab color
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(
          color: AppColors.primaryColor,
          width: 2.0,
        ),
      ),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.bold,
      ), // Style for selected tab label
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.normal,
      ), // Style for unselected tab label
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      elevation: 2,
      iconTheme: IconThemeData(color: AppColors.iconColorLight),
      titleTextStyle: TextStyle(
        color: AppColors.textColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    iconTheme: const IconThemeData(
      color: AppColors.iconColorLight,
      size: 24,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.buttonColor,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 4,
      ),
    ),
    cardTheme: const CardTheme(
      color: AppColors.cardColorLight,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.dividerColorLight,
      thickness: 1.0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardColorLight,
      hintStyle: TextStyle(color: AppColors.textColor.withOpacity(0.6)),
      labelStyle: const TextStyle(color: AppColors.textColor),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.dividerColorLight),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: AppColors.iconColorLight.withOpacity(0.6),
      showUnselectedLabels: true,
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: AppColors.listTileBackgroundLight,
      textColor: AppColors.textColor,
      subtitleTextStyle: TextStyle(
        color: AppColors.subtitleTextColorLight,
      ),
      iconColor: AppColors.iconColorLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.buttonColor,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.cardColorLight,
      selectedColor: AppColors.primaryColor,
      labelStyle: TextStyle(color: AppColors.textColor),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
  );

  // Dark Theme
  ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primaryColor,
    scaffoldBackgroundColor: AppColors.darkScaffoldBackgroundColor,
    textTheme: GoogleFonts.ubuntuTextTheme().apply(
      bodyColor: AppColors.darkTextColor,
      displayColor: AppColors.darkTextColor,
    ),
    tabBarTheme: TabBarTheme(
      labelColor: AppColors.primaryColor, // Color of the selected tab
      indicatorColor: AppColors.primaryColor,
      unselectedLabelColor:
          AppColors.iconColor.withOpacity(0.6), // Unselected tab color
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(
          color: AppColors.primaryColor,
          width: 2.0,
        ),
      ),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.bold,
      ), // Style for selected tab label
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.normal,
      ), // Style for unselected tab label
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      elevation: 0,
      iconTheme: IconThemeData(color: AppColors.iconColor),
      titleTextStyle: TextStyle(
        color: AppColors.darkTextColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    iconTheme: const IconThemeData(
      color: AppColors.iconColor,
      size: 24,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.buttonColor,
        foregroundColor: AppColors.darkTextColor,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    cardTheme: const CardTheme(
      color: AppColors.cardColor,
      elevation: 2,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.dividerColor,
      thickness: 1.2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardColor,
      hintStyle: TextStyle(color: AppColors.darkTextColor.withOpacity(0.6)),
      labelStyle: const TextStyle(color: AppColors.darkTextColor),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkScaffoldBackgroundColor,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: AppColors.iconColor,
      showUnselectedLabels: true,
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: AppColors.listTileBackground,
      textColor: AppColors.listTileTitleColor,
      subtitleTextStyle: TextStyle(
        color: AppColors.listTileSubtitleColor,
      ),
      iconColor: AppColors.iconColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.buttonColor,
      foregroundColor: AppColors.darkTextColor,
    ),
  );
}
