import 'package:flutter/material.dart';

/// How many columns of at least [minCardWidth] (separated by [spacing]) fit in
/// [availableWidth]. Always at least 1. Pure so the breakpoint math is
/// unit-tested without layout.
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

/// An auto-fitting grid of equal-width cards. Each card is at least
/// [minCardWidth] wide; the column count adapts to the available width and the
/// cards share the remaining space evenly.
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
