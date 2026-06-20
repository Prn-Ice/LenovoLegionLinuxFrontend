import 'package:flutter/material.dart';

/// The small Legion robot/sprite identity mark from the Yaru handoff, drawn
/// natively with [CustomPaint] (no SVG/asset dependency).
///
/// Geometry is reproduced from the handoff's inline SVG (viewBox `0 0 26 26`):
/// a rounded-rect head with two white eyes + accent pupils, a faint mouth bar,
/// and an optional antenna. [color] drives the head, pupils, and antenna; the
/// eyes are always white.
class LegionMark extends StatelessWidget {
  const LegionMark({
    super.key,
    required this.color,
    this.size = 24,
    this.showAntenna = true,
  });

  final Color color;
  final double size;
  final bool showAntenna;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: LegionMarkPainter(color: color, showAntenna: showAntenna),
      ),
    );
  }
}

/// Painter for [LegionMark]. Public so its repaint contract is unit-testable.
class LegionMarkPainter extends CustomPainter {
  const LegionMarkPainter({required this.color, required this.showAntenna});

  final Color color;
  final bool showAntenna;

  /// The handoff SVG viewBox edge; all coordinates below are in these units and
  /// scaled to the actual (square) canvas.
  static const double _viewBox = 26;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / _viewBox;
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final white = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = true;

    if (showAntenna) {
      final antenna = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7 * s
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawLine(Offset(13 * s, 2 * s), Offset(13 * s, 5.5 * s), antenna);
      canvas.drawCircle(Offset(13 * s, 2 * s), 1.7 * s, fill);
    }

    // Head.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4 * s, 5 * s, 18 * s, 16 * s),
        Radius.circular(5.5 * s),
      ),
      fill,
    );

    // Eyes (white) with accent pupils.
    canvas.drawCircle(Offset(9.6 * s, 12.6 * s), 2.3 * s, white);
    canvas.drawCircle(Offset(16.4 * s, 12.6 * s), 2.3 * s, white);
    canvas.drawCircle(Offset(10.1 * s, 13 * s), 1 * s, fill);
    canvas.drawCircle(Offset(16.9 * s, 13 * s), 1 * s, fill);

    // Mouth (75% opacity white bar).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10 * s, 16.6 * s, 6 * s, 1.7 * s),
        Radius.circular(0.85 * s),
      ),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.75),
    );
  }

  @override
  bool shouldRepaint(LegionMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.showAntenna != showAntenna;
}
