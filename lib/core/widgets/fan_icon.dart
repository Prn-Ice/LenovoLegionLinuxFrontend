import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Yaru has no fan glyph. This three-blade mark uses the same 24px icon grid
/// and inherits the surrounding icon colour, including selected navigation.
class FanIcon extends StatelessWidget {
  const FanIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _FanPainter(
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _FanPainter extends CustomPainter {
  const _FanPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.translate(12, 12);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset.zero, 10, stroke);
    final fill = Paint()..color = color;
    final blade = Path()
      ..moveTo(-1, -2)
      ..cubicTo(-6, -4, -5, -8, -1, -8)
      ..cubicTo(3, -8, 4, -4, 1, -2)
      ..close();
    for (var i = 0; i < 3; i++) {
      canvas.drawPath(blade, fill);
      canvas.rotate(2 * math.pi / 3);
    }
    canvas.drawCircle(Offset.zero, 1.7, fill);
  }

  @override
  bool shouldRepaint(_FanPainter oldDelegate) => color != oldDelegate.color;
}
