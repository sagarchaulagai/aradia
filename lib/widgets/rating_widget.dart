import 'package:flutter/material.dart';
import 'package:aradia/resources/designs/app_colors.dart';

class RatingWidget extends StatelessWidget {
  final double rating;
  final double size;
  const RatingWidget({
    super.key,
    this.rating = 0.0,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < 5; i++)
          if (i < rating.floor())
            Icon(
              Icons.star,
              color: AppColors.primaryColor,
              size: size,
            )
          else if (i == rating.floor() && rating % 1 != 0)
            Icon(
              Icons.star_half,
              color: AppColors.primaryColor,
              size: size,
            )
          else
            Icon(
              Icons.star_border,
              color: AppColors.primaryColor,
              size: size,
            ),
      ],
    );
  }
}
