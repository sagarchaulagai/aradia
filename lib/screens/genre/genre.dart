import 'package:aradia/resources/designs/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

class Genre extends StatefulWidget {
  const Genre({super.key});

  @override
  State<Genre> createState() => _GenreState();
}

class _GenreState extends State<Genre> {
  // Icons for genres
  final Map<String, IconData> _genreIcons = {
    "adventure": Ionicons.earth_outline,
    "biography": Ionicons.person_outline,
    "children": Ionicons.ice_cream_outline,
    "comedy": Ionicons.happy_outline,
    "crime": Ionicons.glasses_outline,
    "fantasy": Ionicons.sparkles_outline,
    "horror": Ionicons.skull_outline,
    "humor": Ionicons.flower_outline,
    "love": Ionicons.heart_outline,
    "mystery": Ionicons.help_circle_outline,
    "philosophy": Ionicons.bulb_outline,
    "poem": Ionicons.musical_notes_outline,
    "romance": Ionicons.rose_outline,
    "scifi": Ionicons.rocket_outline,
    "war": Ionicons.shield_outline,
  };

  // Light theme colors
  final Map<String, Color> _lightGenreColors = {
    "adventure": const Color(0xFFFFE0B2), // Light Peach
    "biography": const Color(0xFFFFF3E0), // Soft Cream
    "children": const Color(0xFFE6F3FF), // Soft Sky Blue
    "comedy": const Color(0xFFFFF9C4), // Soft Butter Yellow
    "crime": const Color(0xFFF5F5F5), // Very Soft Gray
    "fantasy": const Color(0xFFF3E5F5), // Soft Lavender
    "horror": const Color(0xFFFFEBEE), // Soft Blush
    "humor": const Color(0xFFFFF9C4), // Soft Butter Yellow
    "love": const Color(0xFFFCE4EC), // Soft Pink
    "mystery": const Color(0xFFE0F2F1), // Soft Mint
    "philosophy": const Color(0xFFF9FBE7), // Soft Sage
    "poem": const Color(0xFFF1F8E9), // Soft Mint Green
    "romance": const Color(0xFFFFF0F5), // Lavender Blush
    "scifi": const Color(0xFFE3F2FD), // Soft Blue
    "war": const Color(0xFFE1F5FE), // Lightest Blue
  };

  // Dark theme colors
  final Map<String, Color> _darkGenreColors = {
    "adventure": const Color(0xFF4E342E), // Dark Brown
    "biography": const Color(0xFF3E2723), // Deep Brown
    "children": const Color(0xFF283593), // Deep Blue
    "comedy": const Color(0xFFEF6C00), // Orange
    "crime": const Color(0xFF212121), // Charcoal
    "fantasy": const Color(0xFF6A1B9A), // Deep Purple
    "horror": const Color(0xFFB71C1C), // Blood Red
    "humor": const Color(0xFFF57F17), // Golden Yellow
    "love": const Color(0xFFD81B60), // Bright Pink
    "mystery": const Color(0xFF004D40), // Teal Green
    "philosophy": const Color(0xFF1B5E20), // Forest Green
    "poem": const Color(0xFF33691E), // Olive Green
    "romance": const Color(0xFF880E4F), // Deep Pink
    "scifi": const Color(0xFF1A237E), // Indigo
    "war": const Color(0xFF0D47A1), // Navy Blue
  };

  Map<String, Color> _getGenreColors(BuildContext context) {
    // Choose colors based on theme mode
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.light
        ? _lightGenreColors
        : _darkGenreColors;
  }

  @override
  Widget build(BuildContext context) {
    final genreColors = _getGenreColors(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Choose a Genre',
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _genreIcons.keys.length,
          itemBuilder: (context, index) {
            String genre = _genreIcons.keys.elementAt(index);
            return _buildGenreCard(genre, genreColors[genre]!, context);
          },
        ),
      ),
    );
  }

  Widget _buildGenreCard(
      String genre, Color backgroundColor, BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push(
          '/genre_audiobooks',
          extra: genre,
        );
        print('Tapped $genre genre');
      },
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 4),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _genreIcons[genre],
              size: 60,
              color: // if light mode then black else white
                  Theme.of(context).brightness == Brightness.light
                      ? Colors.deepOrange
                      : Colors.white,
            ),
            const SizedBox(height: 10),
            Text(
              genre.toUpperCase(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.deepOrange
                    : Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
