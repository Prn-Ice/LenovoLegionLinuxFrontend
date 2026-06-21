import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'metric_format.dart';

/// A radial-arc telemetry gauge: a 270° track that fills with the value, a
/// large tabular center number with optional unit, and a label below it.
///
/// Uses [accent] normally and flips the value arc and number to the theme's
/// error color once [value] reaches [criticalThreshold]. Renders cleanly when
/// [value] is null (empty track + `—`).
class MetricGauge extends StatelessWidget {
  const MetricGauge({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.accent,
    this.unit = '',
    this.criticalThreshold,
    this.fractionDigits = 0,
    this.size = 120,
  });

  final double? value;
  final double min;
  final double max;
  final String label;
  final Color accent;
  final String unit;
  final double? criticalThreshold;
  final int fractionDigits;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fraction = metricFraction(value, min, max);
    final critical = isMetricCritical(value, criticalThreshold);
    final arcColor = critical ? scheme.error : accent;

    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: GaugeArcPainter(
          fraction: fraction ?? 0,
          color: arcColor,
          trackColor: scheme.surfaceContainerHighest,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: formatMetric(value, fractionDigits: fractionDigits),
                      style: textTheme.headlineMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w700,
                        color: critical ? scheme.error : null,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      TextSpan(
                        text: unit,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                label,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Painter for [MetricGauge]'s 270° arc. Public so its repaint contract is
/// unit-testable.
class GaugeArcPainter extends CustomPainter {
  const GaugeArcPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  /// Fill fraction, `0..1`.
  final double fraction;
  final Color color;
  final Color trackColor;

  // 270° arc beginning bottom-left (135°) and sweeping clockwise.
  static const double _startAngle = math.pi * 3 / 4;
  static const double _sweepAngle = math.pi * 3 / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final inset = (Offset.zero & size).deflate(stroke / 2 + 1);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawArc(inset, _startAngle, _sweepAngle, false, track);

    final clamped = fraction.clamp(0.0, 1.0);
    if (clamped > 0) {
      final value = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawArc(inset, _startAngle, _sweepAngle * clamped, false, value);
    }
  }

  @override
  bool shouldRepaint(GaugeArcPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}
