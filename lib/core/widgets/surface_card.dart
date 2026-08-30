import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

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
    // Design: a subtle raise over the page (#333 over #2a2a2a), not Yaru's
    // lightest container which reads too bright. Derive it from the surface so
    // it tracks the theme.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultFill = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.045),
            scheme.surface,
          )
        : scheme.surfaceContainerLow;
    return YaruBorderContainer(
      padding: padding,
      color: color ?? defaultFill,
      border:
          border ?? Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      borderRadius: _radius,
      child: child,
    );
  }
}
