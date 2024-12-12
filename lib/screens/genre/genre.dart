import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

class Genre extends StatefulWidget {
  const Genre({super.key});

  @override
  State<Genre> createState() => _GenreState();
}

class _GenreState extends State<Genre> {
  // Existing genresSubjectsJson map remains the same

  // New map with cute icons for each genre
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

  // Existing color map with softer, more pastel colors
  final Map<String, Color> _genreColors = {
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
    "war": const Color(0xFFE1F5FE) // Lightest Blue
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Choose a Genre',
        ),
        backgroundColor: Colors.white,
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
            return _buildGenreCard(genre);
          },
        ),
      ),
    );
  }

  Widget _buildGenreCard(String genre) {
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
          color: _genreColors[genre],
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
              color: Colors.deepOrange[800],
            ),
            const SizedBox(height: 10),
            Text(
              genre.toUpperCase(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.deepOrange[800],
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
