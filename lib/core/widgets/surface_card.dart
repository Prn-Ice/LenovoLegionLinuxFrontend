import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

/// The standard dashboard card surface: a theme-aware fill, a hairline border,
/// and a 13px radius.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultFill = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.045),
            scheme.surface,
          )
        : const Color(0xffFFFFFF);
    final defaultBorder = isDark
        ? scheme.onSurface.withValues(alpha: 0.06)
        : const Color(0xffE6E2DD);
    return YaruBorderContainer(
      padding: padding,
      color: color ?? defaultFill,
      border: border ?? Border.all(color: defaultBorder),
      borderRadius: _radius,
      child: child,
    );
  }
}
