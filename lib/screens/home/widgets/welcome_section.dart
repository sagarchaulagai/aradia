import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:aradia/resources/designs/app_colors.dart';

class WelcomeSection extends StatelessWidget {
  final ThemeData theme;

  const WelcomeSection({
    super.key,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back!',
            style: GoogleFonts.ubuntu(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Discover your next favorite audiobook',
            style: GoogleFonts.ubuntu(
              fontSize: 16,
              color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
