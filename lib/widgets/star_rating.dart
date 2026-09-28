import 'package:flutter/material.dart';

class StarRating extends StatefulWidget {
  final int rating;
  final ValueChanged<int>? onRatingChanged;
  final double size;
  final bool readOnly;

  const StarRating({
    super.key,
    this.rating = 0,
    this.onRatingChanged,
    this.size = 32.0,
    this.readOnly = false,
  });

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  late int _currentRating;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.rating;
  }

  @override
  void didUpdateWidget(StarRating oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rating != oldWidget.rating) {
      _currentRating = widget.rating;
    }
  }

  void _handleTap(int rating) {
    if (widget.readOnly) return;
    
    setState(() {
      _currentRating = rating;
    });
    
    widget.onRatingChanged?.call(rating);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starNumber = index + 1;
        final isFilled = starNumber <= _currentRating;

        return GestureDetector(
          onTap: widget.readOnly ? null : () => _handleTap(starNumber),
          child: AnimatedScale(
            scale: 1.0,
            duration: const Duration(milliseconds: 100),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                isFilled ? Icons.star : Icons.star_border,
                color: isFilled ? const Color(0xFFFFD700) : Colors.grey[400],
                size: widget.size,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Display-only star rating (smaller, for badges and cards)
class StarRatingDisplay extends StatelessWidget {
  final int rating;
  final double size;
  final bool showCount;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 16.0,
    this.showCount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(
          rating,
          (index) => Icon(
            Icons.star,
            color: const Color(0xFFFFD700),
            size: size,
          ),
        ),
        if (showCount) ...[
          const SizedBox(width: 4),
          Text(
            '($rating/5)',
            style: TextStyle(
              fontSize: size * 0.75,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
