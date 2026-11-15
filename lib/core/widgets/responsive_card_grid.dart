import 'package:flutter/material.dart';

/// How many columns of at least [minCardWidth] (separated by [spacing]) fit in
/// [availableWidth]. Returns at least one column.
int responsiveColumnCount(
  double availableWidth,
  double minCardWidth,
  double spacing,
) {
  if (availableWidth <= 0 || minCardWidth <= 0) return 1;
  // n cards fit when n*min + (n-1)*spacing <= width
  //   => n <= (width + spacing) / (min + spacing)
  final columns = ((availableWidth + spacing) / (minCardWidth + spacing))
      .floor();
  return columns < 1 ? 1 : columns;
}

/// A grid of equal-width cards. Fits as many [minCardWidth] columns as possible,
/// then shares the remaining space. A narrower container still gets one column.
///
/// Intended to live inside a vertically scrolling page (bounded width). Use a
/// wider [minCardWidth] (≈420–520) for Dashboard hero cards and the default
/// (≈320) for dense control cards.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.children,
    this.minCardWidth = 320,
    this.spacing = 16,
    this.runSpacing = 16,
  });

  final List<Widget> children;
  final double minCardWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = responsiveColumnCount(width, minCardWidth, spacing);
        final cardWidth = columns <= 1
            ? width
            : (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
    );
  }
}
