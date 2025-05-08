import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/resources/designs/app_colors.dart';
import '../constants/home_constants.dart';

class GenreGrid extends StatelessWidget {
  final List<String> genres;

  const GenreGrid({
    super.key,
    required this.genres,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: HomeConstants.genreGridCrossAxisCount,
        mainAxisSpacing: HomeConstants.genreGridSpacing,
        crossAxisSpacing: HomeConstants.genreGridSpacing,
        childAspectRatio: HomeConstants.genreGridChildAspectRatio,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildGenreChip(context, genres[index]),
        childCount: genres.length,
      ),
    );
  }

  Widget _buildGenreChip(BuildContext context, String genre) {
    return Material(
      color: AppColors.primaryColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push('/genre_audiobooks', extra: genre);
        },
        child: Container(
          alignment: Alignment.center,
          child: Text(
            genre,
            style: GoogleFonts.ubuntu(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
