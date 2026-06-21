import 'package:flutter/material.dart';

/// The standard dashboard card surface, matching the design's `#333` card on the
/// `#2a2a2a` page: a slightly-raised fill, a hairline border, and a 13px radius.
///
/// [YaruBorderContainer] defaults to a *transparent* fill, which left the cards
/// flat; this gives them the design's raised look while staying theme-driven.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Overrides the fill (e.g. a selected accent wash).
  final Color? color;

  /// Overrides the border (e.g. a selected accent border).
  final BoxBorder? border;

  static BorderRadius get _radius => BorderRadius.circular(13);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerHighest,
        borderRadius: _radius,
        border:
            border ??
            Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}
