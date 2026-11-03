import 'package:flutter/material.dart';

// 5 stars filled by the rating (4.5 gives 4 full stars and a half one)
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.size = 18});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rated ${rating.toStringAsFixed(1)} out of 5',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final v = rating - i;
          final icon = v >= 0.75
              ? Icons.star
              : v >= 0.25
              ? Icons.star_half
              : Icons.star_border;
          return Icon(icon, size: size, color: const Color(0xFFFFB400));
        }),
      ),
    );
  }
}
